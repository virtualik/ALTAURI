package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Assembly;
import core.base.AssemblyFactory;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint.ConnectionPoint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.types.ContactType;
import core.types.ContactType.*;

/**
 * EDITOR CONTEXT v2.2 (NodeView Reattach + Pre-Save Sync)
 * Manages the stack of open editors (NodeEditor instances) and their camera states.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.2 CHANGES (NodeView Reattach + Pre-Save Sync)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  PROBLEM A (displayNames lost on disk after restart):
 *  The sync methods (refreshExternalPortNames, syncDisplayNamesToBlueprint,
 *  syncConnectionsToTemplateIds) were called INSIDE pop(), but Main's
 *  onBackClicked flow was:
 *
 *      saveCurrentContext();        ← writes OLD bp to disk
 *      closeCurrentEditor(true);    ← pop() runs sync, but too late
 *
 *  Result: in-memory bp was synced, but disk copy was stale. Renamed atoms
 *  reverted to default names after app restart.
 *
 *  SOLUTION A:
 *  Added prepareCurrentAssemblyForSave() — public method that Main.hx calls
 *  BEFORE saveCurrentContext(). Sync methods run BEFORE the bp is serialized
 *  to disk, so disk and memory stay consistent.
 *
 *  PROBLEM B (ports + labels vanish after Editor ↔ Device Panel switch):
 *  updateInstancesOf() disposes the old Assembly and creates a new one with
 *  the SAME runtimeId. But the parent's NodeView kept holding a reference to
 *  the OLD (disposed) Assembly. After Assembly.dispose():
 *    - internalAtoms = null
 *    - ports = null
 *    - _inputs / _outputs = null
 *
 *  The first time createPorts() ran after a mode switch (Editor → Device →
 *  Editor forces updateLayout → createPorts), atom.getInputs() returned
 *  null and no ports were created. Symptom: "графика контактов и названия
 *  контактов пропадают".
 *
 *  SOLUTION B:
 *  After replacing the atom in currentAssembly.internalAtoms, call:
 *
 *      currentEditor.reattachNodeView(oldRuntimeId, newInstance)
 *
 *  This swaps the NodeView's atom reference, releases the old DeviceView
 *  (with its Contact subscriptions on the disposed atom), acquires a fresh
 *  DeviceView for the new atom, and rebuilds layout + ports + inline editors.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.1 CHANGES (Load-Symmetric Blueprint Sync in pop())
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  PROBLEM:
 *  After "enter assembly → add wires → rename atoms → exit", the reconstructed
 *  assembly lost all wires AND the user's renamed atoms appeared disconnected.
 *  Trace logs showed:
 *
 *    WARN: Atom "id_9082dcea" not found in Assembly(id_9d0b2ea5)
 *    SAFETY NET: Removed ghost connection: id_9082dcea.device → ...
 *
 *  ROOT CAUSE:
 *  ConnectCommand stores RUNTIME IDs in blueprint.internalConnections.
 *  ProjectManager.saveAssemblyToLibrary() translates runtime → template
 *  when writing to disk, so disk-saved blueprints are correct. But the
 *  in-memory blueprint used by updateInstancesOf() still contained runtime
 *  IDs. When AssemblyFactory.createAtom ran the constructor,
 *  _createInternalInstances generated NEW runtime IDs (via UID.generate),
 *  so the OLD runtime IDs in the blueprint matched nothing — and the
 *  SAFETY NET in _createInternalConnections purged every connection as
 *  a ghost. Atom displayNames were restored correctly, but the atoms
 *  appeared "unsaved" because they were orphaned (no wires).
 *
 *  SOLUTION:
 *  Before reconstruction, call three sync methods in order:
 *    1. asm.refreshExternalPortNames()     — update PinDef.externalName
 *                                           based on connected atoms
 *    2. asm.syncDisplayNamesToBlueprint()  — write displayName into
 *                                           atomDef.values for restoreState
 *    3. asm.syncConnectionsToTemplateIds() — translate runtime IDs in
 *                                           internalConnections to template IDs
 *  Then registerBlueprint() + updateInstancesOf() run against a blueprint
 *  that is structurally identical to a freshly-loaded-from-disk one.
 *  Reconstruction is now fully load-symmetric.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.0 CHANGES (Load-Symmetric Assembly Reconstruction)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  PROBLEM:
 *  After "enter assembly → exit assembly", feeding signals into the assembly's
 *  external contacts crashed the application. Re-loading the project from disk
 *  healed the system, which proved that the construction path was correct and
 *  the exit path was not.
 *
 *  ROOT CAUSE:
 *  pop(updateInstances=true) called asm.updateFromBlueprint(newBp), which only
 *  mutated ports on the existing Assembly instance while preserving its internal
 *  atom instances. Those internal atoms still had live DeviceView callbacks
 *  subscribed to their contacts (because NodeView.dispose() never disposes
 *  DeviceViews). After exit, when a signal reached an internal atom, those
 *  orphaned callbacks fired against torn-down display objects → crash.
 *
 *  Additionally, NodeEditor.dispose() failed to actually unsubscribe two of its
 *  Impulsys listeners (REDRAW_WIRES and ASSEMBLY_PORTS_CHANGED), because it
 *  passed freshly-allocated anonymous functions to removeImpulse() instead of
 *  the same references used in subscribeToImpulse(). Those stale listeners kept
 *  firing on every ASSEMBLY_PORTS_CHANGED emit, calling drawFrame() on an
 *  already-disposed editor.
 *
 *  SOLUTION:
 *  Replace the partial updateFromBlueprint() call in updateInstancesOf() with a
 *  FULL reconstruction that mirrors exactly what project load does:
 *
 *    1. Remember the assembly's runtime ID
 *    2. Unlink parent-side wires pointing at the assembly's port.external
 *       (Contact.dispose() only removes THIS from targets that THIS links to;
 *        it cannot remove THIS from contacts that link TO this — see unlinkParentWiresTo)
 *    3. Dispose the old assembly completely
 *       → disposes internal atoms → disposes their contacts → nullifies
 *         callbackTargets → leaked DeviceView callbacks can no longer fire
 *    4. Recreate the assembly via AssemblyFactory.createAtom(typeId, oldRuntimeId)
 *       → constructor path: _createInterface + _createInternalInstances +
 *         _createInternalConnections + _initializeLogicState + _updatePortLinks +
 *         _processPendingSignals
 *       → identical to what happens during project load
 *    5. Reconnect parent's external wires to the new port.external contacts
 *
 *  This makes the system state after exit identical to the state after load:
 *  fresh atom instances, fresh contacts with empty callbackTargets, fresh
 *  ConductorPort instances, state restored from saved blueprint values.
 *
 *  NodeEditor v4.5 (companion fix in this same patch):
 *  - All 8 Impulsys listeners are now stored in named private fields and
 *    unsubscribed via the same reference.
 *  - drawFrame() now early-returns when isDisposed, so even if a stale event
 *    somehow reaches a disposed editor it cannot crash.
 *
 *  v1.4 Changes:
 *  - FIXED: push() now calls editor.forceFullRedraw() twice (immediately and after 100ms)
 *    to ensure all NodeViews are created and wires are drawn.
 *  - FIXED: pop() now calls prev.editor.forceFullRedraw() with double delay.
 *
 *  v1.3 Changes:
 *  - FIXED: push() now calls editor.forceFullRedraw() after a short delay
 *    to ensure all NodeViews are created and wires are drawn.
 *  - FIXED: pop() now calls prev.editor.forceFullRedraw() to restore parent view.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   EditorContext                                                         │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Stack Management:                                              │   │
 * │   │  - _stack:Array<EditorEntry>                                    │   │
 * │   │  - push(assembly)    → Open new assembly (drill down)           │   │
 * │   │  - pop()             → Close current assembly (go back)         │   │
 * │   │  - clear()           → Reset entire stack                       │   │
 * │   │  - getStackEntries() → Return array of entries (for external)   │   │
 * │   │                                                                 │   │
 * │   │  Camera State Management:                                       │   │
 * │   │  - _cameraStates:Map<String, {x, y, zoom}>                      │   │
 * │   │    Stores viewport state for each assembly by blueprint.id.     │   │
 * │   │  - On push: store parent state, then restore or auto-center.    │   │
 * │   │  - On pop: store current state, restore parent state.           │   │
 * │   │                                                                 │   │
 * │   │  v2.0 Assembly Reconstruction (on pop with updateInstances):    │   │
 * │   │  - updateInstancesOf(typeId)                                    │   │
 * │   │    → unlinkParentWiresTo(asm)                                   │   │
 * │   │    → asm.dispose()                                              │   │
 * │   │    → AssemblyFactory.createAtom(typeId, oldRuntimeId)           │   │
 * │   │    → reconnectExternalLinksToAssembly(newAsm)                   │   │
 * │   │                                                                 │   │
 * │   │  Visual State:                                                  │   │
 * │   │  - currentAssembly   → Currently edited assembly                │   │
 * │   │  - currentEditor     → Active NodeEditor instance               │   │
 * │   │  - blocker:Sprite    → Semi-transparent overlay (blocks input)  │   │
 * │   │                                                                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class EditorContext
{
    // =========================================================================
    // DEPENDENCIES
    // =========================================================================
    private var _layer:Sprite;
    private var _theme:EditorTheme;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _stack:Array<EditorEntry>;

    public var currentAssembly(default, null):Assembly;
    public var currentEditor(default, null):NodeEditor;

    // =========================================================================
    // v1.2: CAMERA STATE STORAGE
    // =========================================================================
    /**
     * Map: blueprint.id → {x, y, zoom}
     * Stores the last known camera state for each assembly.
     * Used to restore viewport when re-entering a previously visited assembly.
     */
    private var _cameraStates:Map<String, {x:Float, y:Float, zoom:Float}>;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(layer:Sprite)
    {
        _layer = layer;
        _stack = [];
        _theme = EditorTheme.getInstance();
        _cameraStates = new Map();
    }

    // =========================================================================
    // STACK OPERATIONS
    // =========================================================================
    /**
     * Open a new assembly (drill down into nested structure).
     * Creates a new editor instance and adds it to the stack.
     *
     * @param assembly Assembly to open
     * @param isRoot   If true, this is the root assembly (no blocker)
     */
    public function push(assembly:Assembly, ?isRoot:Bool = false):Void
    {
        // If not root, block the previous editor
        var parentState: {x:Float, y:Float, zoom:Float} = null;
        if (!isRoot && _stack.length > 0)
        {
            var top = _stack[_stack.length - 1];

            // ── Save parent camera state before entering child ──
            parentState = top.editor.getViewState();

            var blocker = new Sprite();
            blocker.graphics.beginFill(0x808080, 0.6);
            blocker.graphics.drawRect(0, 0, _layer.stage.stageWidth, _layer.stage.stageHeight);
            blocker.graphics.endFill();

            // Blocker intercepts clicks (prevents interaction with background)
            blocker.addEventListener(openfl.events.MouseEvent.CLICK, function(e) e.stopPropagation());
            _layer.addChild(blocker);

            top.editor.mouseEnabled = false;
            top.editor.mouseChildren = false;
            top.blocker = blocker;
        }

        // Create container for new editor
        var container = new Sprite();
        drawContainerFrame(container);
        _layer.addChild(container);

        // Create editor
        var editor = new NodeEditor(assembly);
        editor.setSize(container.width, container.height);
        container.addChild(editor);

        // =========================================================================
        // v1.4 FIX: Двойной принудительный реблд для гарантии
        // =========================================================================
        // Сначала сразу после добавления, потом через 100 мс.
        editor.forceFullRedraw();
        haxe.Timer.delay(() -> {
            if (editor != null && !editor.isDisposed) {
                editor.forceFullRedraw();
            }
        }, 100);
        // =========================================================================

        var entry:EditorEntry = {
            assembly: assembly,
            editor: editor,
            blocker: null,
            container: container,
            parentCameraState: parentState
        };
        _stack.push(entry);

        currentEditor = editor;
        currentAssembly = assembly;

        // ═══════════════════════════════════════════════════════════════════
        // v1.2: RESTORE OR AUTO-CENTER CAMERA
        // ═══════════════════════════════════════════════════════════════════
        var bpId = assembly.blueprint.id;
        if (_cameraStates.exists(bpId))
        {
            // Restore previously saved state
            var state = _cameraStates.get(bpId);
            editor.setViewState(state);
            trace('EditorContext: Restored camera state for "$bpId"');
        }
        else
        {
            // First time entering this assembly — auto-center on content
            editor.centerOnContent();
            trace('EditorContext: Auto-centered on "$bpId"');
        }
    }

    /**
     * Close current assembly and return to parent.
     *
     * v2.0: When updateInstances=true, child assemblies of the same typeId as
     * the just-closed assembly are FULLY RECONSTRUCTED (dispose + recreate)
     * rather than partially updated via updateFromBlueprint(). This mirrors
     * the project-load path and eliminates the orphaned-DeviceView-callback
     * crash that occurred when signals reached assemblies after exit.
     *
     * @param updateInstances If true, update assembly instances in parent after save
     */
    public function pop(updateInstances:Bool = false):Void
    {
        if (_stack.length <= 1) return; // Cannot close root

        var current = _stack.pop();
        var editedId = current.assembly.blueprint.id;

        // ── v1.2: Save current camera state for this assembly ──
        var currentState = current.editor.getViewState();
        _cameraStates.set(editedId, currentState);
        trace('EditorContext: Saved camera state for "$editedId"');

        // Remove current editor
        current.editor.dispose();
        if (_layer.contains(current.container)) _layer.removeChild(current.container);

        // Restore previous editor
        var prev = _stack[_stack.length - 1];
        if (prev.blocker != null)
        {
            if (_layer.contains(prev.blocker)) _layer.removeChild(prev.blocker);
            prev.blocker = null;
        }

        prev.editor.mouseEnabled = true;
        prev.editor.mouseChildren = true;

        currentEditor = prev.editor;
        currentAssembly = prev.assembly;

        // =========================================================================
        // v1.4 FIX: Двойной реблд родительского редактора
        // =========================================================================
        prev.editor.forceFullRedraw();
        haxe.Timer.delay(() -> {
            if (prev.editor != null && !prev.editor.isDisposed) {
                prev.editor.forceFullRedraw();
            }
        }, 50);
        // =========================================================================

        // ── v1.2: Restore parent camera state (if we saved it) ──
        if (current.parentCameraState != null)
        {
            currentEditor.setViewState(current.parentCameraState);
            trace('EditorContext: Restored parent camera state');
        }

        // Update assembly preview in parent if it changed
        if (updateInstances)
        {
            // ═══════════════════════════════════════════════════════════════════
            // v2.1: Load-Symmetric Blueprint Sync BEFORE reconstruction
            // ═══════════════════════════════════════════════════════════════════
            // The child assembly is about to be disposed + recreated via
            // AssemblyFactory.createAtom. For the new instance to inherit the
            // user's edits (renamed atoms, new wires, semantic port names),
            // we must first synchronize the in-memory blueprint so that it is
            // in the SAME state as a freshly-loaded-from-disk blueprint.
            //
            // Order matters:
            //   1. refreshExternalPortNames()    — needs runtime IDs to resolve
            //                                      atoms; updates PinDef.externalName
            //   2. syncDisplayNamesToBlueprint() — writes displayName into
            //                                      atomDef.values for restoreState
            //   3. syncConnectionsToTemplateIds()— translates runtime IDs in
            //                                      internalConnections to template IDs
            //   4. registerBlueprint()           — publish updated bp to AtomRegistry
            //   5. updateInstancesOf()           — dispose + recreate via Factory
            //
            // After step 3, the bp is structurally identical to what
            // ProjectManager.saveAssemblyToLibrary() writes to disk, so the
            // reconstruction path is load-symmetric.
            // ═══════════════════════════════════════════════════════════════════
            var asm = current.assembly;

            // 1. Refresh external port names based on connected atoms
            asm.refreshExternalPortNames();

            // 2. Sync renamed atom displayNames into atomDef.values
            asm.syncDisplayNamesToBlueprint();

            // 3. Translate runtime IDs → template IDs in internalConnections
            asm.syncConnectionsToTemplateIds();

            // 4. Register the UPDATED blueprint in registry so that
            //    AssemblyFactory.createAtom(typeId, ...) sees the latest state
            library.AtomRegistry.registerBlueprint(asm.blueprint.id, asm.blueprint);

            // 5. Now reconstruct with up-to-date data
            updateInstancesOf(asm.blueprint.id);
        }

        // Refresh assembly views and wires
        currentEditor.refreshAssemblyViews();
    }

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
     *
     * The runtime ID is preserved (forcedId) so the parent blueprint's
     * AtomDef.instanceId reference remains valid and no blueprint mutation
     * is required.
     */
    private function updateInstancesOf(typeId:String):Void
    {
        var newBp = library.AtomRegistry.get(typeId);
        if (newBp == null) return;

        // Iterate through all atoms in CURRENT editor (the parent)
        for (id in currentAssembly.internalAtoms.keys())
        {
            var atom = currentAssembly.internalAtoms.get(id);
            if (Std.isOfType(atom, Assembly))
            {
                var asm = cast(atom, Assembly);
                if (asm.blueprint.id == typeId)
                {
                    // ═══════════════════════════════════════════════════════════════════
                    // v2.0: FULL RECONSTRUCTION (load-symmetric)
                    // ═══════════════════════════════════════════════════════════════════

                    var oldRuntimeId = asm.id;

                    // 1. Unlink parent's external wires to old assembly's port.external.
                    //    This MUST happen BEFORE dispose() because Contact.dispose()
                    //    only removes THIS from contacts that THIS links to — it
                    //    cannot remove THIS from contacts that link TO this.
                    unlinkParentWiresTo(asm);

                    // 2. Dispose old assembly completely.
                    //    This disposes internal atoms → their contacts →
                    //    contact.callbackTargets = null → leaked DeviceView
                    //    callbacks can no longer fire.
                    asm.dispose();

                    // 3. Recreate via Factory using the SAME runtime ID so the
                    //    parent's blueprint.internalAtoms references stay valid.
                    //    AssemblyFactory.createAtom() runs the full Assembly
                    //    constructor, which is identical to the project-load path.
                    var newInstance = AssemblyFactory.createAtom(typeId, oldRuntimeId);
                    if (newInstance == null)
                    {
                        trace('ERROR: EditorContext.updateInstancesOf: Failed to recreate assembly $typeId ($oldRuntimeId)');
                        continue;
                    }

                    // 4. Replace in parent's internalAtoms map (key unchanged).
                    currentAssembly.internalAtoms.set(oldRuntimeId, newInstance);

                    // 5. Reconnect parent's external wires to the new port.external
                    //    contacts of the freshly constructed assembly.
                    if (Std.isOfType(newInstance, Assembly))
                    {
                        reconnectExternalLinksToAssembly(cast(newInstance, Assembly));
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
                    // manifesting as "графика контактов и названия контактов
                    // пропадают" after Editor → Device Panel → Editor.
                    //
                    // reattachNodeView swaps the atom reference, releases the
                    // old DeviceView, acquires a fresh one, and rebuilds layout.
                    // ═══════════════════════════════════════════════════════════════════
                    currentEditor.reattachNodeView(oldRuntimeId, newInstance);
                }
            }
        }
    }

    /**
     * v2.2: Synchronizes the current assembly's blueprint BEFORE saving to disk.
     *
     * MUST be called by Main.hx BEFORE saveCurrentContext() in onBackClicked().
     *
     * PROBLEM:
     * Previously the sync methods (refreshExternalPortNames,
     * syncDisplayNamesToBlueprint, syncConnectionsToTemplateIds) were called
     * INSIDE pop(), which runs AFTER saveCurrentContext() in the typical
     * onBackClicked flow:
     *
     *     saveCurrentContext();        ← writes OLD bp to disk
     *     closeCurrentEditor(true);    ← pop() runs sync, but too late
     *
     * This caused user-renamed atom displayNames to be lost on disk after
     * app restart (the in-memory bp was synced, but the disk copy was stale).
     *
     * SOLUTION:
     * Main.hx now calls prepareCurrentAssemblyForSave() BEFORE saveCurrentContext():
     *
     *     _editorContext.prepareCurrentAssemblyForSave();   ← sync in-memory bp
     *     saveCurrentContext();                              ← writes synced bp
     *     closeCurrentEditor(true);                          ← pop() (sync calls
     *                                                         in pop are now
     *                                                         redundant but
     *                                                         idempotent and safe)
     *
     * This method is also safe to call from any other code path that intends
     * to persist the current assembly — e.g., an explicit "Save" menu action.
     */
    public function prepareCurrentAssemblyForSave():Void
    {
        if (currentAssembly == null) return;

        // 1. Refresh external port names based on connected atoms
        currentAssembly.refreshExternalPortNames();

        // 2. Sync renamed atom displayNames into atomDef.values
        currentAssembly.syncDisplayNamesToBlueprint();

        // 3. Translate runtime IDs → template IDs in internalConnections
        currentAssembly.syncConnectionsToTemplateIds();

        // 4. Register the UPDATED blueprint in registry so that
        //    ProjectManager.saveAssemblyToLibrary() sees the latest state
        //    and so that AssemblyFactory.createAtom(typeId, ...) on any
        //    future reconstruction uses the synced bp.
        library.AtomRegistry.registerBlueprint(
            currentAssembly.blueprint.id, currentAssembly.blueprint);
    }

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
     */
    private function unlinkParentWiresTo(targetAsm:Assembly):Void
    {
        var bp = currentAssembly.blueprint;
        if (bp.internalConnections == null) return;

        for (conn in bp.internalConnections)
        {
            var isTarget = false;
            var parentSide:ConnectionPoint = null; // the end that is NOT the assembly

            // Check 'to' side: if 'to' references targetAsm, then 'from' is the parent side
            if (conn.to.atomId != "SELF")
            {
                var realAtomId = currentAssembly.idMap.get(conn.to.atomId);
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
                var realAtomId = currentAssembly.idMap.get(conn.from.atomId);
                if (realAtomId == null) realAtomId = conn.from.atomId;

                if (realAtomId == targetAsm.id || conn.from.atomId == targetAsm.id)
                {
                    isTarget = true;
                    parentSide = conn.to;
                }
            }

            if (!isTarget || parentSide == null) continue;

            // Resolve the parent-side contact (could be SELF of parent, or another atom)
            var parentContact = resolveContactInParent(parentSide);
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

    /**
     * Reconnects wires from the parent assembly to the (re)constructed child assembly.
     *
     * When a child assembly is freshly constructed (e.g., after exit-from-assembly
     * in v2.0), its ports are brand-new Contact instances. The parent's blueprint
     * still has the correct ConnectionDef, but the physical Contact.link() must
     * be re-established against the new port.external contacts.
     */
    private function reconnectExternalLinksToAssembly(targetAsm:Assembly):Void
    {
        var bp = currentAssembly.blueprint;
        if (bp.internalConnections == null) return;

        for (conn in bp.internalConnections)
        {
            // Check if this connection involves our target assembly
            var isTarget = false;

            // Check 'to' side
            if (conn.to.atomId != "SELF")
            {
                var realAtomId = currentAssembly.idMap.get(conn.to.atomId);
                if (realAtomId == null) realAtomId = conn.to.atomId; // fallback if already runtime ID

                if (realAtomId == targetAsm.id || conn.to.atomId == targetAsm.id)
                {
                    isTarget = true;
                }
            }

            // Check 'from' side (for completeness)
            if (!isTarget && conn.from.atomId != "SELF")
            {
                var realAtomId = currentAssembly.idMap.get(conn.from.atomId);
                if (realAtomId == null) realAtomId = conn.from.atomId;

                if (realAtomId == targetAsm.id || conn.from.atomId == targetAsm.id)
                {
                    isTarget = true;
                }
            }

            if (isTarget)
            {
                // Re-establish the physical link
                var cOut = resolveContactInParent(conn.from);
                var cIn = resolveContactInParent(conn.to);

                if (cOut != null && cIn != null && !cOut.hasLink(cIn))
                {
                    cOut.link(cIn);
                }
            }
        }
    }

    /**
     * Resolves a Contact in the context of the CURRENT (parent) assembly.
     *
     * This leverages the existing Atom.getInput/getOutput methods,
     * which already know how to find Assembly ports by their externalName.
     *
     * NOTE: For an Assembly atom, getInput/getOutput search by Contact.name,
     * which equals externalName (see ConductorPort v2.0 dual naming). For a
     * simple Atom, contacts are registered with their standard name. This
     * matches the contactName stored in the parent's blueprint.
     */
    private function resolveContactInParent(point:ConnectionPoint):Contact
    {
        if (point.atomId == "SELF")
        {
            var port = currentAssembly.ports.get(point.contactName);
            return port != null ? port.internal : null;
        }
        else
        {
            // Resolve Template ID to Runtime ID
            var realAtomId = currentAssembly.idMap.get(point.atomId);
            if (realAtomId == null) realAtomId = point.atomId;

            var obj = currentAssembly.internalAtoms.get(realAtomId);
            if (obj == null) return null;

            var atom:Atom = cast obj;

            var c = atom.getInput(point.contactName);
            if (c != null) return c;

            return atom.getOutput(point.contactName);
        }
    }

    /**
     * Reset entire stack (on project reload) and clear camera states.
     */
    public function clear():Void
    {
        while (_stack.length > 0)
        {
            var item = _stack.pop();
            item.editor.dispose();
            if (item.container.parent != null) _layer.removeChild(item.container);
            if (item.blocker != null && item.blocker.parent != null) _layer.removeChild(item.blocker);
        }
        currentEditor = null;
        currentAssembly = null;
        _cameraStates.clear();
    }

    public function getStackLength():Int return _stack.length;

    // =========================================================================
    // v1.1: GET STACK ENTRIES (for external operations)
    // =========================================================================
    /**
     * Returns a copy of the current editor stack entries.
     * Used by Main to find parent assemblies when handling PORT_REMOVED events.
     *
     * @return Array of EditorEntry (copy)
     */
    public function getStackEntries():Array<EditorEntry>
    {
        return _stack.copy();
    }

    // =========================================================================
    // VISUAL
    // =========================================================================
    private function drawContainerFrame(container:Sprite):Void
    {
        var margin = 12;
        var w = _layer.stage.stageWidth - (margin * 2);
        var h = _layer.stage.stageHeight - (margin * 2);

        container.graphics.clear();
        container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
        container.graphics.lineStyle(1, _theme.FRAME_BORDER_COLOR);
        container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        container.graphics.endFill();

        container.x = margin;
        container.y = margin;
    }
}

typedef EditorEntry = {
    var assembly:Assembly;
    var editor:NodeEditor;
    var blocker:Sprite;
    var container:Sprite;
    @:optional var parentCameraState:{x:Float, y:Float, zoom:Float};
}
