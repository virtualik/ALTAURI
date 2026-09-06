package editor;

import core.base.Assembly;
import core.base.Contact;
import core.data.Blueprint.ConnectionPoint;
import core.base.AssemblyFactory;
import core.logic.Impulse;
import core.logic.TickGenerator;
import core.types.ContactType;
import core.types.ContactType.*;
import utils.Trap;

/**
 * ASSEMBLY RECONSTRUCTOR v1.0
 * ═══════════════════════════════════════════════════════════════════════════
 * EXTRACTED FROM EditorContext v2.13 — Episod D of the Editor de-god-ification.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Stateless service that tears down and rebuilds an Assembly instance inside
 * its parent editor after the child's blueprint has changed. Reconstruction
 * is "load-symmetric": it walks the same 5-step pipeline that a fresh
 * project-load walks, so what the user sees after pop() == what they would
 * see after quitting and relaunching the app.
 *
 * Four entry points (one public-facing, three internal helpers):
 *
 *   updateInstancesOf(typeId, parentAsm, parentEditor, portResolver)
 *                                               — find every child of
 *                                                 `typeId` in parentAsm and
 *                                                 fully reconstruct it
 *                                                 (unlink → dispose →
 *                                                 createAtom → reconnect →
 *                                                 reattachNodeView).
 *
 *   unlinkParentWiresTo(targetAsm, parentAsm, portResolver)
 *                                               — Step 1 of the pipeline:
 *                                                 break parent-side
 *                                                 Contact.linkedTargets
 *                                                 references to the
 *                                                 soon-to-be-disposed
 *                                                 port.external contacts.
 *
 *   reconnectExternalLinksToAssembly(targetAsm, parentAsm, portResolver)
 *                                               — Step 4 of the pipeline:
 *                                                 re-establish physical
 *                                                 Contact.link() between
 *                                                 parent's wires and the
 *                                                 freshly created
 *                                                 port.external contacts.
 *                                                 Includes v2.7 STEEL name
 *                                                 reconciliation, v2.6
 *                                                 suppressPropagation=true
 *                                                 silent links, and v2.10
 *                                                 Re-Alignment Wave.
 *
 *   onAssemblyPortsChanged(impulse, stack, currentAsm, portResolver)
 *                                               — v2.12 reactive handler:
 *                                                 listens to
 *                                                 ASSEMBLY_PORTS_CHANGED
 *                                                 emitted by
 *                                                 refreshExternalPortNames
 *                                                 whenever a gateway port
 *                                                 is recreated; immediately
 *                                                 re-establishes parent-side
 *                                                 physical links through the
 *                                                 same reconciliation path as
 *                                                 pop()-reconstruction.
 *
 * ALL methods are pure: callers pass parent assembly, parent editor, port
 * resolver and (for the impulse handler) the editor stack explicitly. No
 * EditorContext dependency, no Impulsys, no subscriptions, no global state
 * beyond AtomRegistry / TickGenerator / AssemblyFactory (all global
 * singletons, deliberately so).
 *
 * INVARIANT (Load-Symmetric Reconstruction — established EditorContext v2.0):
 *   reconstruct = save = load
 * Before this method runs, BlueprintSynchronizer.syncBeforeReconstruction
 * (Episod B) has already brought the in-memory blueprint to the same state
 * a fresh project-load would have produced, so AssemblyFactory.createAtom()
 * here produces the same instance state that a load would have produced.
 *
 * Migration guide for EditorContext callers:
 *   ─ updateInstancesOf(typeId)                              → _recon.updateInstancesOf(typeId, currentAssembly, currentEditor, _portResolver)
 *   ─ unlinkParentWiresTo(targetAsm)                         → _recon.unlinkParentWiresTo(targetAsm, currentAssembly, _portResolver)
 *   ─ reconnectExternalLinksToAssembly(targetAsm, ?parentCtx)→ _recon.reconnectExternalLinksToAssembly(targetAsm, parentCtx != null ? parentCtx : currentAssembly, _portResolver)
 *   ─ onAssemblyPortsChanged(impulse)                        → _recon.onAssemblyPortsChanged(impulse, _stack, currentAssembly, _portResolver)
 *
 * See the class-level v2.0 / v2.6 / v2.7 / v2.10 / v2.12 changelog in
 * EditorContext.hx for the forensic rationale behind each step (lost wires,
 * stale names, silent links, value wave, parent-wire auto-heal).
 */
class AssemblyReconstructor
{
        public function new() {}

        // ═══════════════════════════════════════════════════════════════════
        // FULL RECONSTRUCTION (Step 0 of the pipeline — orchestrator)
        // ═══════════════════════════════════════════════════════════════════
        /**
         * Update visual representation of assemblies with specified ID
         * in all open editors.
         *
         * v2.0 FIX: After the child assembly's internal structure may have changed,
         * we NO LONGER call asm.updateFromBlueprint(newBp). That partial mutation
         * preserved stale internal atom instances together with their leaked
         * DeviceView callback subscriptions, which crashed the app when signals
         * later reached those atoms.
         *
         * Instead, we FULLY RECONSTRUCT the child assembly through the same path
         * used at project load:
         *   1. unlinkParentWiresTo(asm) — break parent-side Contact.linkedTargets
         *      references to the soon-to-be-disposed port.external contacts
         *   2. asm.dispose() — disposes internal atoms, their contacts, and
         *      nullifies contact.callbackTargets (neutralizing any leaked
         *      DeviceView subscriptions)
         *   3. AssemblyFactory.createAtom(typeId, oldRuntimeId) — runs the
         *      constructor path: _createInterface + _createInternalInstances +
         *      _createInternalConnections + _initializeLogicState + _updatePortLinks
         *   4. reconnectExternalLinksToAssembly(newAsm) — re-establish physical
         *      Contact.link() between parent's wires and the new port.external
         *      (v2.6: with suppressPropagation — NO value push mid-operation)
         *   5. currentEditor.reattachNodeView(oldRuntimeId, newInstance) —
         *      v2.2: swap the parent's NodeView atom reference to the new
         *      instance, release old DeviceView, acquire fresh one
         *
         * The runtime ID is preserved (forcedId) so the parent blueprint's
         * AtomDef.instanceId reference remains valid and no blueprint mutation
         * is required.
         *
         * v2.6 NOTE: runs inside the pop() topology transaction. The Assembly
         * constructor's suspend/resume and _processPendingSignals pushes all
         * land in _deferredTopologyTasks and flush after the graph is whole.
         *
         * Episod D (v1.0): extracted verbatim from EditorContext.updateInstancesOf.
         * parentAsm / parentEditor / portResolver are now passed explicitly
         * instead of being read from EditorContext state — the method is pure
         * and unit-testable in isolation.
         */
        public function updateInstancesOf(typeId:String, parentAsm:Assembly, parentEditor:NodeEditor, portResolver:PortNameResolver):Void
        {
                Trap.log("RECON", "updateInstancesOf: " + typeId + " in parent " + parentAsm.blueprint.name);
                trace('🔍 updateInstancesOf: Looking for assemblies of type "$typeId" in parent "${parentAsm.blueprint.name}"');
                var newBp = library.AtomRegistry.get(typeId);
                if (newBp == null)
                {
                        trace('❌ updateInstancesOf: Blueprint "$typeId" not found in registry!');
                        return;
                }
                var foundCount = 0;
                // Iterate through all atoms in PARENT (parentAsm)
                for (id in parentAsm.internalAtoms.keys())
                {
                        var atom = parentAsm.internalAtoms.get(id);
                        if (Std.isOfType(atom, Assembly))
                        {
                                var asm = cast(atom, Assembly);
                                if (asm.blueprint.id == typeId)
                                {
                                        foundCount++;
                                        Trap.log("RECON", "found: runtime=" + id);
                                        trace('✅ updateInstancesOf: Found assembly "$typeId" with runtimeId="$id"');

                                        // ═══════════════════════════════════════════════════════════════════
                                        // v2.0: FULL RECONSTRUCTION (load-symmetric)
                                        // ═══════════════════════════════════════════════════════════════════

                                        var oldRuntimeId = asm.id;

                                        // 1. Unlink parent's external wires to old assembly's port.external.
                                        //    This MUST happen BEFORE dispose() because Contact.dispose()
                                        //    only removes THIS from contacts that THIS links to — it
                                        //    cannot remove THIS from contacts that link TO this.
                                        Trap.log("RECON", "pre-unlink wires");
                                        unlinkParentWiresTo(asm, parentAsm, portResolver);

                                        // 2. Dispose old assembly completely.
                                        //    This disposes internal atoms → their contacts →
                                        //    contact.callbackTargets = null → leaked DeviceView
                                        //    callbacks can no longer fire.
                                        Trap.log("RECON", "pre-dispose old instance");
                                        asm.dispose();

                                        // 3. Recreate via Factory using the SAME runtime ID so the
                                        //    parent's blueprint.internalAtoms references stay valid.
                                        //    AssemblyFactory.createAtom() runs the full Assembly
                                        //    constructor, which is identical to the project-load path.
                                        //    (v2.6: under the topology lock its value pushes are
                                        //    deferred — see class docs.)
                                        var newInstance = AssemblyFactory.createAtom(typeId, oldRuntimeId);
                                        Trap.log("RECON", "createAtom returned: " + (newInstance != null ? newInstance.id : "NULL"));
                                        if (newInstance == null)
                                        {
                                                trace('ERROR: AssemblyReconstructor.updateInstancesOf: Failed to recreate assembly $typeId ($oldRuntimeId)');
                                                continue;
                                        }

                                        // 4. Replace in parent's internalAtoms map (key unchanged).
                                        parentAsm.internalAtoms.set(oldRuntimeId, newInstance);

                                        // 5. Reconnect parent's external wires to the new port.external
                                        //    contacts of the freshly constructed assembly.
                                        //    (v2.6: suppressPropagation — values are aligned by the
                                        //    new instance's Deferred Sync Wave, not pushed mid-operation.)
                                        if (Std.isOfType(newInstance, Assembly))
                                        {
                                                reconnectExternalLinksToAssembly(cast(newInstance, Assembly), parentAsm, portResolver);
                                        }

                                        // ═══════════════════════════════════════════════════════════════════
                                        // v2.2 FIX: Reattach the parent's NodeView to the new instance.
                                        // ═══════════════════════════════════════════════════════════════════
                                        // Without this, the NodeView in the parent editor keeps holding
                                        // a reference to the OLD (disposed) Assembly. After dispose():
                                        //   - internalAtoms = null
                                        //   - ports = null
                                        //   - _inputs / _outputs = null
                                        //
                                        // The first time createPorts() runs after a mode switch,
                                        // atom.getInputs() returns null and no ports are created,
                                        // manifesting as "contact graphics and contact names
                                        // disappearing" after Editor -> Device Panel -> Editor.
                                        //
                                        // reattachNodeView swaps the atom reference, releases the
                                        // old DeviceView, acquires a fresh one, and rebuilds layout.
                                        // ═══════════════════════════════════════════════════════════════════
                                        parentEditor.reattachNodeView(oldRuntimeId, newInstance);
                                        Trap.log("RECON", "reattachNodeView done");
                                }
                        }
                }
                if (foundCount == 0) {
                        trace('⚠️ updateInstancesOf: No assemblies of type "$typeId" found in parent!');
                }
        }

        // ═══════════════════════════════════════════════════════════════════
        // STEP 1 — UNLINK PARENT WIRES TO OLD INSTANCE
        // ═══════════════════════════════════════════════════════════════════
        /**
         * v2.0: Unlink parent's external wires pointing TO a child assembly's
         * port.external contacts.
         *
         * WHY THIS IS NEEDED:
         * When the parent established a wire to the child assembly, it called
         * `parentContact.link(childPort.external)`, which pushed
         * `childPort.external` into `parentContact.linkedTargets`. The reverse
         * direction (parentContact in childPort.external.linkedTargets) was NOT
         * registered.
         *
         * When the child is later disposed, `Contact.dispose()` iterates the
         * dying contact's OWN linkedTargets and unlinks itself from them. But
         * it has no way to find contacts in the system that hold a reference
         * TO it. So `parentContact.linkedTargets` would retain a stale entry
         * pointing to a disposed Contact.
         *
         * Stale entries in linkedTargets are mostly tolerated (propagation
         * checks `!target.isDisposed`), but they:
         *   - grow `linkedTargets` arrays on every entry/exit cycle
         *   - break code that iterates linkedTargets without re-checking
         *     isDisposed (e.g., hasLinks(), getLinkCount())
         *   - are a smell that something elsewhere may dereference them
         *
         * This method cleanly removes those references BEFORE disposal.
         *
         * Algorithm:
         *   For each connection in the parent's blueprint that references the
         *   target assembly, resolve the parent-side contact (the end that is
         *   NOT on the assembly), then unlink any of the assembly's
         *   port.external contacts that parentContact currently links to.
         *
         * Episod D (v1.0): extracted verbatim from EditorContext.unlinkParentWiresTo.
         * parentAsm / portResolver are now passed explicitly — the method is
         * pure and unit-testable in isolation.
         */
        public function unlinkParentWiresTo(targetAsm:Assembly, parentAsm:Assembly, portResolver:PortNameResolver):Void
        {
                var bp = parentAsm.blueprint;
                if (bp.internalConnections == null) return;

                for (conn in bp.internalConnections)
                {
                        var isTarget = false;
                        var parentSide:ConnectionPoint = null; // the end that is NOT the assembly

                        // Check 'to' side: if 'to' references targetAsm, then 'from' is the parent side
                        if (conn.to.atomId != "SELF")
                        {
                                var realAtomId = parentAsm.idMap.get(conn.to.atomId);
                                if (realAtomId == null) realAtomId = conn.to.atomId;

                                if (realAtomId == targetAsm.id || conn.to.atomId == targetAsm.id)
                                {
                                        isTarget = true;
                                        parentSide = conn.from;
                                }
                        }

                        // Check 'from' side (if not already matched)
                        if (!isTarget && conn.from.atomId != "SELF")
                        {
                                var realAtomId = parentAsm.idMap.get(conn.from.atomId);
                                if (realAtomId == null) realAtomId = conn.from.atomId;

                                if (realAtomId == targetAsm.id || conn.from.atomId == targetAsm.id)
                                {
                                        isTarget = true;
                                        parentSide = conn.to;
                                }
                        }

                        if (!isTarget || parentSide == null) continue;

                        // Resolve the parent-side contact (could be SELF of parent, or another atom)
                        var parentContact = portResolver.resolveContactInParent(parentSide, parentAsm);
                        if (parentContact == null) continue;

                        // Unlink any of targetAsm's port.external contacts that parentContact
                        // currently links to. We don't need to know which specific port this
                        // connection referenced — hasLink() guards the unlink safely, and
                        // the assembly is about to be disposed anyway.
                        for (port in targetAsm.ports)
                        {
                                if (port == null || port.external == null || port.external.isDisposed) continue;
                                if (parentContact.hasLink(port.external))
                                {
                                        parentContact.unlink(port.external);
                                }
                        }
                }
        }

        // ═══════════════════════════════════════════════════════════════════
        // v2.12 — REACTIVE PARENT-WIRE AUTO-HEAL (post-port-rename)
        // ═══════════════════════════════════════════════════════════════════
        /**
         * ASSEMBLY_PORTS_CHANGED listener.
         *
         * Assembly.refreshExternalPortNames() v2.6 emits this event whenever
         * a gateway port was recreated (renamed). The recreation disposes the
         * old external contact, killing every parent wire linked to it. This
         * listener immediately re-establishes those physical links through
         * reconnectExternalLinksToAssembly (STEEL reconciliation + silent
         * links + REALIGN wave) — the same path pop()-reconstruction uses.
         *
         * Case 1: the changed assembly is a CHILD of currentAssembly
         *         (e.g. pop() refreshing the assembly being exited).
         * Case 2: the changed assembly IS currentAssembly — the user is
         *         editing it right now; the affected parent sits one level
         *         down the stack (e.g. ConnectCommand renaming a wall port
         *         from inside the assembly).
         *
         * Episod D (v1.0): extracted verbatim from
         * EditorContext.onAssemblyPortsChanged. The impulse stack / currentAsm /
         * portResolver are now passed explicitly — the method is pure and
         * unit-testable in isolation. Note: EditorContext still OWNS the
         * Impulsys subscription (in its constructor); this class only holds
         * the reaction logic.
         */
        public function onAssemblyPortsChanged(impulse:Impulse, stack:Array<EditorEntry>, currentAsm:Assembly, portResolver:PortNameResolver):Void
        {
                if (impulse == null || impulse.data == null) return;
                var changedId:String = impulse.data.assemblyId;
                if (changedId == null || currentAsm == null) return;

                if (currentAsm.id == changedId)
                {
                        // Case 2: heal the wires in the PARENT context.
                        if (stack.length >= 2)
                        {
                                var parentAsm:Assembly = stack[stack.length - 2].assembly;
                                if (parentAsm != null && parentAsm.blueprint != null)
                                {
                                        Trap.log("PORT-HEAL", "current " + changedId + " ports changed -> healing wires in parent " + parentAsm.blueprint.id);
                                        reconnectExternalLinksToAssembly(currentAsm, parentAsm, portResolver);
                                }
                        }
                        return;
                }

                // Case 1: the changed assembly is a child of currentAsm.
                for (id in currentAsm.internalAtoms.keys())
                {
                        var atom = currentAsm.internalAtoms.get(id);
                        if (Std.isOfType(atom, Assembly))
                        {
                                var child = cast(atom, Assembly);
                                if (child.id == changedId)
                                {
                                        Trap.log("PORT-HEAL", "child " + changedId + " ports changed -> healing wires in " + currentAsm.blueprint.id);
                                        reconnectExternalLinksToAssembly(child, currentAsm, portResolver);
                                        return;
                                }
                        }
                }
        }

        // ═══════════════════════════════════════════════════════════════════
        // STEP 4 — RECONNECT PARENT WIRES TO NEW INSTANCE
        // ═══════════════════════════════════════════════════════════════════
        /**
         * Reconnects wires from the parent assembly to the updated child assembly.
         *
         * When a child assembly updates, its ports are recreated (new Contact instances).
         * The parent's blueprint still has the correct ConnectionDef, but the physical
         * Contact.link() is broken. This method restores the physical links.
         *
         * v2.6 FIX: links are created with suppressPropagation = true.
         * Previously link() synchronously pushed the current value into the
         * freshly constructed (but not yet reattached) assembly — a signal
         * travelling through a graph that is mid-reconstruction. Now the
         * physical link is established silently, and values are aligned by
         * the Deferred Sync Wave of the new instance (the Hot-Start pattern:
         * _processPendingSignals → scheduleNextTick Final Sync), which runs
         * after the topology transaction is complete and every view is
         * reattached.
         *
         * Episod D (v1.0): extracted verbatim from
         * EditorContext.reconnectExternalLinksToAssembly. parentCtx is now
         * MANDATORY (was optional `?parentCtx:Assembly` in v2.12) because
         * all callers must declare their target context explicitly.
         * portResolver is also passed explicitly. The method is pure and
         * unit-testable in isolation.
         */
        public function reconnectExternalLinksToAssembly(targetAsm:Assembly, parentCtx:Assembly, portResolver:PortNameResolver):Void
        {
                // v2.12: parent context — when the changed assembly IS the one
                // being edited, the wires to heal live one level down the
                // editor stack (onAssemblyPortsChanged, case 2). Callers must
                // pass parentCtx explicitly now (Episod D made it mandatory).
                var ctx:Assembly = parentCtx;
                trace('🔗 reconnectExternalLinksToAssembly: targetAsm.id="${targetAsm.id}", targetAsm.blueprint.id="${targetAsm.blueprint.id}"');
                var bp = ctx.blueprint;
                if (bp.internalConnections == null)
                {
                        trace('❌ reconnectExternalLinksToAssembly: parent blueprint has NO connections!');
                        return;
                }
                trace('🔗 reconnectExternalLinksToAssembly: parent has ${bp.internalConnections.length} connections');
                var reconnectedCount = 0;
                // v2.10: sources of reconnected wires — for the Value Re-Alignment Wave.
                var realignSources:Array<Contact> = [];
                for (conn in bp.internalConnections)
                {
                        // Check if this connection involves our updated assembly
                        var isTarget = false;

                        // Check 'to' side
                        if (conn.to.atomId != "SELF")
                        {
                                var realAtomId = ctx.idMap.get(conn.to.atomId);
                                if (realAtomId == null) realAtomId = conn.to.atomId; // fallback if already runtime ID

                                if (realAtomId == targetAsm.id || conn.to.atomId == targetAsm.id)
                                {
                                        isTarget = true;
                                }
                        }

                        // Check 'from' side (for completeness)
                        if (!isTarget && conn.from.atomId != "SELF")
                        {
                                var realAtomId = ctx.idMap.get(conn.from.atomId);
                                if (realAtomId == null) realAtomId = conn.from.atomId;

                                if (realAtomId == targetAsm.id || conn.from.atomId == targetAsm.id)
                                {
                                        isTarget = true;
                                }
                        }

                        if (isTarget) {
                                reconnectedCount++;

                                // ═══════════════════════════════════════════════════════════════════
                                // v2.7 FIX: Reconcile conn.contactName with actual port externalName.
                                // ═══════════════════════════════════════════════════════════════════
                                // After refreshExternalPortNames() runs on the child assembly,
                                // its port externalNames may have changed (e.g., "Pass_in" →
                                // "Custom_Assembly_1_Pass_in" because the child contains a
                                // sub-assembly whose displayName is "Custom Assembly_1").
                                //
                                // parent.bp.internalConnections still references the OLD
                                // externalName. Without reconciliation, resolveContactInParent
                                // returns null because getInput(oldName) finds nothing.
                                //
                                // Solution: when cIn (or cOut) is null and the connection
                                // references an Assembly, look up the Assembly's actual ports
                                // and find the one that matches by internalName. We then
                                // rewrite conn.contactName in-place so future calls (and
                                // save-to-disk) use the correct externalName.
                                // ═══════════════════════════════════════════════════════════════════
                                var cOut = portResolver.resolveContactInParent(conn.from, ctx);
                                var cIn = portResolver.resolveContactInParent(conn.to, ctx);

                                // If cIn is null and conn.to references an Assembly,
                                // try to reconcile the contactName with actual port externalNames.
                                if (cIn == null && conn.to.atomId != "SELF")
                                {
                                        var toAsm = portResolver.resolveAssemblyInParent(conn.to.atomId, ctx);
                                        if (toAsm != null)
                                        {
                                                // v2.7 STEEL RECONCILIATION (in priority order):
                                                //   a) suffix match (externalName ends with "_"+requested) — legacy v2.7
                                                //   b) internalName match — the common stale-name case:
                                                //      GroupAtoms stored internalName; refreshExternalPortNames
                                                //      renamed the port to a semantic externalName
                                                var requestedName = conn.to.contactName;
                                                var fallbackPort = portResolver.findPortByContactSuffix(toAsm, requestedName, INPUT);
                                                if (fallbackPort == null)
                                                {
                                                        for (p in toAsm.ports)
                                                        {
                                                                if (p != null && p.internalName == requestedName && p.type == INPUT)
                                                                {
                                                                        fallbackPort = p;
                                                                        break;
                                                                }
                                                        }
                                                }
                                                if (fallbackPort == null)
                                                {
                                                        fallbackPort = portResolver.findPortByProgressiveSuffix(toAsm, requestedName, INPUT);
                                                }
                                                // v2.13: LEGACY ALIAS — pre-stable-naming name
                                                if (fallbackPort == null)
                                                {
                                                        fallbackPort = toAsm.getPortByAnyName(requestedName);
                                                }
                                                if (fallbackPort != null)
                                                {
                                                        // Update connection in-place
                                                        conn.to.contactName = fallbackPort.externalName;
                                                        // Re-resolve cIn
                                                        cIn = portResolver.resolveContactInParent(conn.to, ctx);
                                                        trace('   🔄 Reconciled cIn: "${requestedName}" → "${conn.to.contactName}"');
                                                }
                                        }
                                }

                                // Same for cOut (if conn.from references an Assembly)
                                if (cOut == null && conn.from.atomId != "SELF")
                                {
                                        var fromAsm = portResolver.resolveAssemblyInParent(conn.from.atomId, ctx);
                                        if (fromAsm != null)
                                        {
                                                // v2.7 STEEL RECONCILIATION: suffix, then internalName
                                                var requestedName = conn.from.contactName;
                                                var fallbackPort = portResolver.findPortByContactSuffix(fromAsm, requestedName, OUTPUT);
                                                if (fallbackPort == null)
                                                {
                                                        for (p in fromAsm.ports)
                                                        {
                                                                if (p != null && p.internalName == requestedName && p.type == OUTPUT)
                                                                {
                                                                        fallbackPort = p;
                                                                        break;
                                                                }
                                                        }
                                                }
                                                if (fallbackPort == null)
                                                {
                                                        fallbackPort = portResolver.findPortByProgressiveSuffix(fromAsm, requestedName, OUTPUT);
                                                }
                                                // v2.13: LEGACY ALIAS — pre-stable-naming name
                                                if (fallbackPort == null)
                                                {
                                                        fallbackPort = fromAsm.getPortByAnyName(requestedName);
                                                }
                                                if (fallbackPort != null)
                                                {
                                                        conn.from.contactName = fallbackPort.externalName;
                                                        cOut = portResolver.resolveContactInParent(conn.from, ctx);
                                                        trace('   🔄 Reconciled cOut: "${requestedName}" → "${conn.from.contactName}"');
                                                }
                                        }
                                }

                                trace('🔗 reconnect: ${conn.from.atomId}.${conn.from.contactName} → ${conn.to.atomId}.${conn.to.contactName}');
                                trace('   cOut=${cOut != null ? cOut.name : "null"}, cIn=${cIn != null ? cIn.name : "null"}');
                                if (cOut != null && cIn != null && !cOut.hasLink(cIn)) {
                                        // v2.6: suppressPropagation=true — NO synchronous value
                                        // push through the half-reconstructed graph. Values are
                                        // aligned by the new instance's Deferred Sync Wave.
                                        cOut.link(cIn, true);
                                        trace('   ✓ Linked (suppressed propagation)');
                                        if (realignSources.indexOf(cOut) == -1) realignSources.push(cOut);
                                } else if (cOut == null || cIn == null) {
                                        trace('   ✗ FAILED to link!');
                                }
                        }
                }
                trace('🔗 reconnect: Reconnected $reconnectedCount links');

                // ═══════════════════════════════════════════════════════════════
                // v2.10: VALUE RE-ALIGNMENT WAVE.
                // The links above were created silent (suppressPropagation) —
                // correct during reconstruction, but LEVEL values living on
                // upstream sources (TextInput.out, Toggle.out...) never cross
                // a silent link. On the next tick (graph whole, unlocked) each
                // recorded source pushes its CURRENT value through the fresh
                // links, restoring the pre-exit signal state.
                // ═══════════════════════════════════════════════════════════════
                if (realignSources.length > 0)
                {
                        TickGenerator.getInstance().scheduleNextTick(function()
                        {
                                for (src in realignSources)
                                {
                                        if (src != null && !src.isDisposed)
                                        {
                                                Trap.log("REALIGN", "pushing value from " + (src.owner != null ? src.owner.id : "?") + "." + src.name);
                                                src.propagateCurrentValue();
                                        }
                                }
                        });
                }
        }
}
