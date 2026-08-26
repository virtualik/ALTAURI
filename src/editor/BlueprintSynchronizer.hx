package editor;

import core.base.Assembly;
import core.data.Blueprint;
import core.logic.NamingService;

/**
 * BLUEPRINT SYNCHRONIZER v1.0
 * ═══════════════════════════════════════════════════════════════════════════
 * EXTRACTED FROM EditorContext v2.13 — Episod B of the Editor de-god-ification.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Stateless service for keeping an Assembly's in-memory blueprint consistent
 * with its live state. Two symmetric entry points, plus one legacy helper:
 *
 *   prepareForSave(currentAsm)                  — run BEFORE disk serialization.
 *                                                 Captures displayNames, inline
 *                                                 values, external port names,
 *                                                 runtime→template ID translation
 *                                                 so the disk file mirrors what
 *                                                 the user sees.
 *
 *   syncBeforeReconstruction(childAsm, parentAsm)
 *                                               — run BEFORE AssemblyFactory.
 *                                                 createAtom(typeId) on a child
 *                                                 that is about to be disposed +
 *                                                 recreated. Mirrors exactly what
 *                                                 prepareForSave + save→load would
 *                                                 have produced, so the freshly
 *                                                 constructed instance inherits the
 *                                                 user's edits (renamed atoms, new
 *                                                 wires, semantic port names).
 *
 *   syncChildStateToParentAtomDef(childAsm, parentAsm)
 *                                               — the BUG-B level-2 helper that
 *                                                 runs as step 2c inside
 *                                                 syncBeforeReconstruction. Exposed
 *                                                 separately because the
 *                                                 explanation in code comments is
 *                                                 long enough to deserve its own
 *                                                 doc block.
 *
 * ALL methods are pure: caller passes the parent assembly explicitly, no
 * EditorContext dependency, no Impulsys, no subscriptions, no global state.
 *
 * INVARIANT (Load-Symmetric Reconstruction — established EditorContext v2.0):
 *   reconstruct = save = load
 * After syncBeforeReconstruction the in-memory blueprint is structurally
 * identical to what ProjectManager.saveAssemblyToLibrary() writes to disk,
 * so the AssemblyFactory.createAtom() path produces the same instance state
 * that a fresh project-load would have produced.
 *
 * Migration guide for EditorContext callers:
 *   ─ prepareCurrentAssemblyForSave()              → _bpSync.prepareForSave(currentAssembly)
 *   ─ syncChildStateToParentAtomDef(childAsm)       → _bpSync.syncChildStateToParentAtomDef(childAsm, currentAssembly)
 *   ─ (inline sync block in pop())                  → _bpSync.syncBeforeReconstruction(asm, currentAssembly)
 *
 * See the class-level v2.0 / v2.1 / v2.8 changelog in EditorContext.hx for the
 * forensic rationale behind each step (lost wires, lost values, lost names —
 * each bug, each fix).
 */
class BlueprintSynchronizer
{
        public function new() {}

        // ═══════════════════════════════════════════════════════════════════
        // PRE-SAVE SYNC (run before disk serialization)
        // ═══════════════════════════════════════════════════════════════════
        /**
         * Synchronizes the assembly's blueprint BEFORE saving to disk.
         *
         * MUST be called by Main.hx BEFORE saveCurrentContext() in
         * onBackClicked() — see prepareCurrentAssemblyForSave in EditorContext.
         *
         * PROBLEM (v2.2 of EditorContext, Problem A — displayNames lost on disk
         * after restart):
         * The sync methods (refreshExternalPortNames, syncDisplayNamesToBlueprint,
         * syncConnectionsToTemplateIds) were called INSIDE pop(), but Main's
         * onBackClicked flow was:
         *
         *     saveCurrentContext();        ← writes OLD bp to disk
         *     closeCurrentEditor(true);    ← pop() runs sync, but too late
         *
         * This caused user-renamed atom displayNames to be lost on disk after
         * app restart (the in-memory bp was synced, but the disk copy was stale).
         *
         * SOLUTION:
         * Main.hx now calls prepareCurrentAssemblyForSave() BEFORE
         * saveCurrentContext():
         *
         *     _editorContext.prepareCurrentAssemblyForSave();   ← sync in-memory bp
         *     saveCurrentContext();                              ← writes synced bp
         *     closeCurrentEditor(true);                          ← pop() (sync calls
         *                                                        in pop are now
         *                                                        redundant but
         *                                                        idempotent and safe)
         *
         * This method is also safe to call from any other code path that intends
         * to persist the current assembly — e.g., an explicit "Save" menu action.
         */
        public function prepareForSave(currentAsm:Assembly):Void
        {
                if (currentAsm == null) return;

                // 1. Refresh external port names based on connected atoms
                currentAsm.refreshExternalPortNames();

                // 2. Sync renamed atom displayNames into atomDef.values
                currentAsm.syncDisplayNamesToBlueprint();

                // 2b. Sync the assembly's own displayName into blueprint.name
                //     so the .atom file on disk reflects the user's rename.
                if (currentAsm.displayName != null
                        && currentAsm.displayName != currentAsm.blueprint.name)
                {
                        currentAsm.blueprint.name = currentAsm.displayName;
                }

                // 2c. v2.8 (BUG-B): Sync live inline values into atomDef.values so
                //     DISK saves capture the CURRENT state through the same funnel
                //     the pop()-reconstruction path relies on (save = load =
                //     reconstruct — full load-symmetry).
                currentAsm.syncAtomValuesToBlueprint();

                // 3. Translate runtime IDs → template IDs in internalConnections
                currentAsm.syncConnectionsToTemplateIds();

                // 4. Register the UPDATED blueprint in registry so that
                //    ProjectManager.saveAssemblyToLibrary() sees the latest state
                //    and so that AssemblyFactory.createAtom(typeId, ...) on any
                //    future reconstruction uses the synced bp.
                library.AtomRegistry.registerBlueprint(
                        currentAsm.blueprint.id, currentAsm.blueprint);
        }

        // ═══════════════════════════════════════════════════════════════════
        // PRE-RECONSTRUCTION SYNC (run before AssemblyFactory.createAtom)
        // ═══════════════════════════════════════════════════════════════════
        /**
         * The full load-symmetric sync pipeline, run inside pop() BEFORE
         * updateInstancesOf(typeId) reconstructs the child assembly via
         * AssemblyFactory.createAtom(typeId, oldRuntimeId).
         *
         * WHY THIS EXISTS (EditorContext v2.1 — Load-Symmetric Blueprint Sync):
         * After "enter assembly → add wires → rename atoms → exit", the
         * reconstructed assembly used to lose all wires AND the user's renamed
         * atoms appeared disconnected. Trace logs showed:
         *
         *     WARN: Atom "id_9082dcea" not found in Assembly(id_9d0b2ea5)
         *     SAFETY NET: Removed ghost connection: id_9082dcea.device → ...
         *
         * ROOT CAUSE:
         * ConnectCommand stored RUNTIME IDs in blueprint.internalConnections.
         * ProjectManager.saveAssemblyToLibrary() translated runtime → template
         * when writing to disk, so disk-saved blueprints were correct. But the
         * in-memory blueprint used by updateInstancesOf() still contained runtime
         * IDs. When AssemblyFactory.createAtom ran the constructor,
         * _createInternalInstances generated NEW runtime IDs (via UID.generate),
         * so the OLD runtime IDs in the blueprint matched nothing — and the
         * SAFETY NET in _createInternalConnections purged every connection as a
         * ghost.
         *
         * SOLUTION:
         * Before reconstruction, run this sync pipeline:
         *   1. refreshExternalPortNames()                — update PinDef.externalName
         *                                               based on connected atoms
         *   1b. remapParentConnectionsToPortNames()      — propagate the renamed
         *                                               externalNames into the
         *                                               PARENT's blueprint internalConnections
         *                                               (v2.7 — prevents cOut=null
         *                                               "FAILED to link" after exit)
         *   2. syncDisplayNamesToBlueprint()             — write displayName into
         *                                               atomDef.values for restoreState
         *   2b. syncAtomValuesToBlueprint() [v2.8]       — write LIVE inline values
         *                                               into atomDef.values (BUG-B fix:
         *                                               leaf values lost on exit)
         *   2c. syncChildStateToParentAtomDef() [v2.8]   — write child state into
         *                                               PARENT atomDef.values (prevents
         *                                               the stale internalStates overwrite)
         *   3. syncConnectionsToTemplateIds()            — translate runtime IDs in
         *                                               internalConnections to template IDs
         *   4. registerBlueprint()                       — publish updated bp to AtomRegistry
         *
         * After step 3, the bp is structurally identical to what
         * ProjectManager.saveAssemblyToLibrary() writes to disk, so the
         * reconstruction path is load-symmetric. The caller (EditorContext.pop)
         * then calls updateInstancesOf(typeId) and gets a fresh instance that
         * inherits the user's live edits.
         *
         * @param childAsm   The assembly being exited (about to be disposed + recreated)
         * @param parentAsm   The parent assembly whose blueprint.internalAtoms holds
         *                     the AtomDef for childAsm (used as the overwrite source
         *                     by _createInternalInstances.restoreState; syncChildStateToParentAtomDef
         *                     keeps that source fresh)
         * @param portResolver  EditorContext's port-name resolver (used by step 1b).
         *                     Passed in to avoid BlueprintSynchronizer having to
         *                     instantiate its own (single resolver instance shared
         *                     with EditorContext — preserves the v1.0 Episod A
         *                     extraction contract).
         */
        public function syncBeforeReconstruction(
                childAsm:Assembly,
                parentAsm:Assembly,
                portResolver:PortNameResolver):Void
        {
                if (childAsm == null || parentAsm == null) return;

                // 1. Refresh external port names based on connected atoms
                childAsm.refreshExternalPortNames();

                // 1b. v2.7: REMAP parent connection contactNames to the
                // refreshed external names. refreshExternalPortNames()
                // renames ports (PinDef + ConductorPort) but does NOT
                // notify the PARENT — its blueprint.internalConnections
                // keep referencing OLD names (internalName or stale
                // externalName), which breaks reconnect + WireRenderer
                // after reconstruction (the exit-crash forensics:
                // "cOut=null → FAILED to link"). This remap restores
                // in-memory consistency to the same state a
                // save→load cycle would produce.
                portResolver.remapParentConnectionsToPortNames(childAsm, parentAsm);

                // 2. Sync renamed atom displayNames into atomDef.values
                childAsm.syncDisplayNamesToBlueprint();

                // 2b. v2.8 (BUG-B): Sync LIVE inline values of internal atoms
                //     (TextInput text, gains, toggle states...) into
                //     atomDef.values. Before this, values reached the
                //     in-memory blueprint ONLY during disk saves, so
                //     pop()-reconstruction restored the LAST SAVED state
                //     (e.g., 50 instead of the edited 3).
                childAsm.syncAtomValuesToBlueprint();

                // 2c. v2.8 (BUG-B level-2): Sync the exited child's own
                //     persistent state into the PARENT's atomDef.values.
                //     _createInternalInstances() calls restoreState()
                //     AFTER the child constructor finishes — which
                //     OVERWRITES the child internals with whatever the
                //     parent atomDef.values holds. Stale internalStates
                //     there (from the last disk save) would resurrect
                //     dead values; this keeps the overwrite fresh.
                syncChildStateToParentAtomDef(childAsm, parentAsm);

                // 3. Translate runtime IDs → template IDs in internalConnections
                childAsm.syncConnectionsToTemplateIds();

                // 4. Register the UPDATED blueprint in registry so that
                //    AssemblyFactory.createAtom(typeId, ...) sees the latest state
                library.AtomRegistry.registerBlueprint(childAsm.blueprint.id, childAsm.blueprint);
        }

        // ═══════════════════════════════════════════════════════════════════
        // CHILD-TO-PARENT STATE SYNC (the BUG-B level-2 helper)
        // ═══════════════════════════════════════════════════════════════════
        /**
         * Syncs the EXITED child assembly's persistent state into the
         * PARENT blueprint's atomDef.values (matched by template id).
         *
         * WHY THIS EXISTS (BUG-B, level-2):
         * _createInternalInstances() calls instance.restoreState(atomDef.values)
         * AFTER the child Assembly constructor has finished. For a nested
         * Assembly, restoreState() re-applies state.internalStates to the
         * freshly built internal atoms — OVERWRITING whatever the child's own
         * constructor restored from its (freshly synced) registry blueprint.
         *
         * If the parent's atomDef.values still holds internalStates from the
         * LAST DISK SAVE (e.g., value: 50 when the user edited 50 → 3), the
         * overwrite resurrects the stale value and defeats the leaf-atom sync
         * performed by Assembly.syncAtomValuesToBlueprint() one level deeper.
         *
         * This method keeps the overwrite source FRESH: the child's live
         * getPersistentState() (captured BEFORE dispose) is merged into the
         * parent's atomDef.values, mirroring what a save→load cycle would
         * have produced. Load-symmetry restored.
         *
         * @param childAsm   The exited assembly (about to be disposed + recreated)
         * @param parentAsm  The parent whose blueprint.internalAtoms holds the
         *                   matching AtomDef
         */
        public function syncChildStateToParentAtomDef(
                childAsm:Assembly,
                parentAsm:Assembly):Void
        {
                if (childAsm == null || parentAsm == null) return;
                var parentBp = parentAsm.blueprint;
                if (parentBp == null || parentBp.internalAtoms == null) return;

                // Child's runtime id → template id, as seen from the PARENT's _idMap
                // (getTemplateId falls back to the runtime id itself for atoms that
                // were added at runtime without a registered mapping).
                var templateId = parentAsm.getTemplateId(childAsm.id);

                var state:Dynamic = null;
                try
                {
                        state = childAsm.getPersistentState();
                }
                catch (e:Dynamic)
                {
                        trace('WARN: syncChildStateToParentAtomDef: getPersistentState() failed for "${templateId}": $e');
                        return;
                }

                for (atomDef in parentBp.internalAtoms)
                {
                        if (atomDef.instanceId != templateId) continue;

                        if (state == null)
                        {
                                // Nothing live to preserve — drop stale internalStates so the
                                // post-create overwrite cannot resurrect dead values.
                                if (atomDef.values != null
                                        && Reflect.hasField(atomDef.values, "internalStates"))
                                {
                                        Reflect.deleteField(atomDef.values, "internalStates");
                                        trace('📦 syncChildState: cleared stale internalStates for "${templateId}"');
                                }
                                return;
                        }

                        if (atomDef.values == null) atomDef.values = {};
                        var fields:Array<String> = Reflect.fields(state);
                        for (field in fields)
                        {
                                Reflect.setField(atomDef.values, field, Reflect.field(state, field));
                        }
                        trace('📦 syncChildState: "${templateId}" → parent atomDef.values (${fields.length} field(s) [${fields.join(", ")}])');
                        return;
                }
        }
}
