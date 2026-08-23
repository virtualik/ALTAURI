package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint.ConnectionPoint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.types.ContactType;
import core.types.ContactType.*;
import core.base.AssemblyFactory;
import core.logic.TickGenerator;

/**
* EDITOR CONTEXT v2.11 (Progressive Suffix Matching + Value Re-Alignment + Traps)
* Manages the stack of open editors (NodeEditor instances) and their camera states.
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.11 CHANGES (Progressive Suffix Matching — wire disappearance fix)
* ═══════════════════════════════════════════════════════════════════════════
*
*  FIELD EVIDENCE (crash_trap.log + output.txt, session 2026-08-24):
*  After a pop() the parent wires vanished: reconnect logged
*  "cIn=null -> FAILED to link!" x21 and WireRenderer warned
*  "No port position for Custom_Assembly_2_Com_Port_*" x573 while the
*  blueprint still had all 6 connections. The child's ports were named
*  "Custom_Assembly_1_Com_Port_*" — the nested atom's displayName had
*  changed between pop cycles, and semantic port externalNames follow
*  it (refreshExternalPortNames: atomName + "_" + contactName).
*
*  FIX: findPortByProgressiveSuffix() — strips leading tokens of the
*  requested name until EXACTLY ONE port of the right type ends with
*  "_"+tail:
*     "Custom_Assembly_2_Com_Port_close"
*       -> tail "Assembly_2_Com_Port_close"  (no unique match)
*       -> tail "2_Com_Port_close"           (no unique match)
*       -> tail "Com_Port_close"             -> UNIQUE port
*          "Custom_Assembly_1_Com_Port_close"  -> match, rewrite.
*  The rewrite lands in blueprint.internalConnections (in-memory AND
*  on the next disk save), so the fix is self-healing: every cycle
*  re-anchors the parent connections to the CURRENT port names.
*
*  Ambiguity (several ports share the tail) resolves to NO match —
*  logged, connection left untouched (better broken than mis-wired).
*
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.10 CHANGES (Value Re-Alignment Wave — persistent values lost on exit)
* ═══════════════════════════════════════════════════════════════════════════
*
*  FIELD EVIDENCE (crash_trap.log): after pop()-reconstruction the
*  txData wire carried no value — the driver's txData input stayed
*  empty, so pressing SEND inside fired the driver but produced no
*  transmission ("send REFUSED" pattern). Root cause: reconnect links
*  are created with suppressPropagation=true (correct — no signals
*  mid-reconstruction), and the new instance's Deferred Sync Wave can
*  only align values that live ON the port external contact. Values
*  living UPSTREAM (e.g., TextInput.out holding "ABC") never cross
*  the silent link — links PUSH, they never PULL.
*
*  FIX: reconnectExternalLinksToAssembly() now records the SOURCE
*  contact (cOut) of every reconnected wire and schedules a
*  Re-Alignment Wave on the next tick (graph whole, topology
*  unlocked): each source propagates its CURRENT value through the
*  fresh links. Event inputs (button pulses) are unaffected; LEVEL
*  inputs (texts, gains, toggles) are restored — reconstruction
*  becomes truly load-symmetric for values.
*
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.9 CHANGES (BUG-A hunt: crash-proof trace breadcrumbs)
* ═══════════════════════════════════════════════════════════════════════════
*
*  All breadcrumbs go to crash_trap.log via utils.Trap (flush-per-line
*  file logger — survives c0000005, unlike buffered stdout whose tail
*  is lost on hard crash; the exit-crash log ended with NO pop traces
*  at all, which is exactly the blindness this removes).
*
*  Markers:
*    POP   — pop() pipeline: entry / before updateInstancesOf /
*            normal unlock / exception
*    RECON — updateInstancesOf microscope: found / pre-unlink /
*            pre-dispose / post-createAtom / post-reattach
*
*  See patches/TRAP_PLAN_v1.md for the full trap map (Main/ComPortAtom/
*  Contact points are manual one-liners).
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.8 CHANGES (BUG-B fix: inline values do not survive exit)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM (field-reported):
*  Editing an inline value deep inside a nested assembly (TextInput
*  gain 50 → 3 on level 4) works live, but after exiting ONE level
*  up the reconstructed instance shows 50 again. The same edit DOES
*  survive a full app save/load round-trip — the asymmetry pinpoints
*  the reconstruction path as the gap.
*
*  ROOT CAUSE (two gaps, both violate Load-Symmetric Reconstruction):
*  1. Assembly.syncDisplayNamesToBlueprint() persists ONLY displayName.
*     Live inline values never reached atomDef.values in memory — they
*     were written there only by ProjectManager during disk saves.
*     pop()-reconstruction therefore restores the LAST SAVED values.
*  2. The parent-side restoreState(atomDef.values) that runs AFTER the
*     child Assembly constructor (inside _createInternalInstances)
*     OVERWRITES the freshly built child internals with the saved
*     state.internalStates snapshot. If the parent atomDef.values holds
*     the snapshot from the last DISK save, stale values resurrect EVEN
*     AFTER gap 1 is closed.
*
*  SOLUTION (this version, together with Assembly v2.3):
*  A) pop() now calls asm.syncAtomValuesToBlueprint() (new Assembly
*     method): merges every internal atom's live getPersistentState()
*     into atomDef.values — leaf atoms AND nested assemblies.
*  B) pop() now calls syncChildStateToParentAtomDef(asm) (new): merges
*     the exited child's full persistent state into the PARENT's
*     atomDef.values, so the post-create overwrite (gap 2) reads FRESH
*     internalStates instead of the last-saved snapshot.
*  C) prepareCurrentAssemblyForSave() also calls (A), so DISK saves
*     capture current values through the very same funnel.
*
*  Result: reconstruction = save = load (full load-symmetry for values).
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.6 CHANGES (Crash fix: exit-from-assembly freeze/crash)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM (field-reported):
*  Enter an assembly (nesting 3-4), interact with atoms (button presses,
*  wire reconnections), then exit 1-2 levels up → app FREEZES then CRASHES.
*
*  ROOT CAUSE (forensic conclusion after auditing TickGenerator, Contact,
*  Assembly, NodeView, MiniAudioAtom, DriverManager):
*  pop(updateInstances=true) was the ONLY graph mutation running OUTSIDE the
*  Topology Transaction Guard. During pop the following race unfolds:
*
*    1. updateInstancesOf() disposes the child assembly and reconstructs it
*       via AssemblyFactory.createAtom → the Assembly constructor performs
*       suspend() → build → resume() → _processPendingSignals(), and
*       scheduleNextTick() queues the Final Sync Wave carrying references
*       to the fresh contacts.
*    2. reconnectExternalLinksToAssembly() called cOut.link(cIn) WITHOUT
*       suppressPropagation → link() synchronously pushes the current value
*       into the half-reconstructed graph MID-OPERATION.
*    3. A quick second pop() disposes the parent that holds the freshly
*       created instances → the queued sync waves and deferred propagations
*       then fire against contacts/views that are mid-teardown, while the
*       parent editor's NodeViews are between reattach states.
*    4. unlockTopology() (from OTHER guarded commands finishing nearby)
*       emits REDRAW_WIRES while the blueprint still references disposed
*       assemblies.
*
*  SOLUTION (this version):
*  A) pop() now runs the WHOLE operation (child editor dispose + sync +
*     updateInstancesOf reconstruction + parent reactivation) inside
*     TickGenerator.lockTopology()/unlockTopology(). Every value push and
*     propagation attempted during the reconstruction is deferred into
*     _deferredTopologyTasks and flushed ONLY after the graph is whole
*     again. This puts pop() in line with GroupAtoms/Undo/Redo/PortDelete,
*     which were already guarded — pop() was the one uncovered path.
*  B) reconnectExternalLinksToAssembly() now links with
*     suppressPropagation=true. Values are aligned afterwards by the
*     Deferred Sync Wave of the freshly constructed instance (the
*     Hot-Start pattern), NOT synchronously mid-operation.
*
*  ╔══════════════════════════════════════════════════════════════════╗
*  ║  TRANSACTION LIFECYCLE OF pop() v2.6:                            ║
*  ║                                                                  ║
*  ║  lockTopology()                                                  ║
*  ║    ├─ save camera state                                          ║
*  ║    ├─ dispose child editor (view layer)                          ║
*  ║    ├─ reactivate parent editor (isActive=true)                   ║
*  ║    ├─ sync blueprint (4 methods + register)                      ║
*  ║    ├─ updateInstancesOf():                                       ║
*  ║    │    unlink parent wires → dispose child asm →                ║
*  ║    │    createAtom (suspend/resume inside, pushes deferred) →    ║
*  ║    │    reconnect links (suppressed, no value push) →            ║
*  ║    │    reattachNodeView                                         ║
*  ║    └─ refreshAssemblyViews                                       ║
*  ║  unlockTopology()                                                ║
*  ║    ├─ flush _deferredTopologyTasks (graph is WHOLE now)          ║
*  ║    ├─ quickEmit(REDRAW_WIRES)                                   ║
*  ║    └─ resume process()                                           ║
*  ╚══════════════════════════════════════════════════════════════════╝
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.5 CHANGES (NamingService Delegation)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  Previous tree-walk approach (hasNameRecursive) only saw atoms in the
*  currently-loaded editor stack and duplicated state already maintained
*  by NamingService, causing potential desync.
*
*  SOLUTION:
*  isNameTakenGlobally() now directly delegates to NamingService.isInstanceNameTaken().
*  NamingService is the single source of truth for global name uniqueness.
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.4 CHANGES (Global Name Uniqueness Integration)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  When pasting or adding atoms, the system only checked for name uniqueness
*  within the current assembly. This allowed duplicate displayNames across
*  different nesting levels, causing wire misrouting and UI confusion.
*
*  SOLUTION:
*  Added isNameTakenGlobally() callback passed down to NodeEditor, which
*  forwards it to NodeView and EditorActionHandler.
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.3 CHANGES (isActive Flag — Broadcast Storm Prevention)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  When push()-ing into a nested assembly, the previous NodeEditor stayed
*  alive behind a blocker. All 9 of its Impulsys subscriptions remained
*  active. On nesting level N, every REDRAW_WIRES emit triggered N
*  concurrent rebuildAll() calls — O(N) work per event, causing UI
*  freezes during pan/zoom at deep nesting.
*
*  SOLUTION:
*  push() now sets top.editor.isActive = false on the parent.
*  pop() sets it back to true and calls forceFullRedraw()
*  (already did the redraw — now also reactivates impulse handling).
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
*  SOLUTION:
*  Replace the partial updateFromBlueprint() call in updateInstancesOf() with a
*  FULL reconstruction that mirrors exactly what project load does:
*
*    1. Remember the assembly's runtime ID
*    2. Unlink parent-side wires pointing at the assembly's port.external
*       (Contact.dispose() only removes THIS from targets that THIS links to;
*        it cannot remove THIS from contacts that link TO it — see unlinkParentWiresTo)
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
* │   │  v2.6 Topology Transaction on pop:                              │   │
* │   │  - pop() wrapped in lockTopology()/unlockTopology()             │   │
* │   │  - All mid-reconstruction propagations deferred                 │   │
* │   │  - reconnectExternalLinksToAssembly links with                  │   │
* │   │    suppressPropagation=true                                     │   │
* │   │                                                                 │   │
* │   │  v2.5 Global Name Uniqueness:                                   │   │
* │   │  - isNameTakenGlobally(name, excludeId) → delegates to          │   │
* │   │    NamingService.isInstanceNameTaken()                          │   │
* │   │  - Passed to NodeEditor constructor on push()                   │   │
* │   │                                                                 │   │
* │   │  v2.3 Broadcast Storm Prevention:                               │   │
* │   │  - push() sets parent editor's isActive = false                 │   │
* │   │  - pop() sets it back to true + forceFullRedraw                 │   │
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
* │   │    → reconnectExternalLinksToAssembly(newAsm) [v2.6: no push]   │   │
* │   │    → currentEditor.reattachNodeView(oldRuntimeId, newInstance)  │   │
* │   │                                                                 │   │
* │   │  v2.2 Pre-Save Sync (called by Main BEFORE saveCurrentContext): │   │
* │   │  - prepareCurrentAssemblyForSave()                              │   │
* │   │    → refreshExternalPortNames()                                 │   │
* │   │    → syncDisplayNamesToBlueprint()                              │   │
* │   │    → syncConnectionsToTemplateIds()                             │   │
* │   │    → registerBlueprint()                                        │   │
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
                        // v2.3: Deactivate parent editor's impulse handlers to prevent
                        // broadcast storm at deep nesting levels.
                        top.editor.isActive = false;
                        top.blocker = blocker;
                }

                // Create container for new editor
                        var container = new Sprite();
                        drawContainerFrame(container);
                        _layer.addChild(container);

                        // v3.0 FIX: Use explicit stage dimensions instead of container.width/height
                        // which may be 0 before the next render frame
                        var margin = 12;
                        var w = (_layer.stage != null) ? _layer.stage.stageWidth - (margin * 2) : 1000;
                        var h = (_layer.stage != null) ? _layer.stage.stageHeight - (margin * 2) : 700;

                        // Create editor (v2.5: pass global name uniqueness checker)
                        var editor = new NodeEditor(assembly, isNameTakenGlobally);
                        editor.setSize(w, h);
                        container.addChild(editor);

                // =========================================================================
                // v1.4 FIX: Двойной принудительный реблд для гарантии
                // =========================================================================
                // Сначала сразу после добавления, потом через 100 мс.
                editor.forceFullRedraw();
                haxe.Timer.delay(() -> {
                        if (editor != null && !editor.isDisposed)
                        {
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
         * v2.6: THE ENTIRE OPERATION RUNS INSIDE A TOPOLOGY TRANSACTION.
         * See the class-level v2.6 documentation for the forensic rationale.
         * Everything attempted by the reactive graph while pop() is tearing
         * down and rebuilding (value pushes from link(), propagations from
         * the Assembly constructor Hot-Start, deferred sync waves) is parked
         * in TickGenerator._deferredTopologyTasks and flushed ONLY after the
         * graph is whole again — at which point REDRAW_WIRES is also emitted,
         * so every live WireRenderer rebuilds against a consistent blueprint.
         *
         * @param updateInstances If true, update assembly instances in parent after save
         */
        public function pop(updateInstances:Bool = false):Void
        {
                if (_stack.length <= 1) return; // Cannot close root

                var tg = TickGenerator.getInstance();
                utils.Trap.log("POP", "enter: stack=" + _stack.length + " updateInstances=" + updateInstances);
                tg.lockTopology();
                try
                {
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
                        // v2.3: Reactivate parent editor's impulse handlers.
                        // forceFullRedraw below will catch up on any missed REDRAW_WIRES
                        // events that were skipped while isActive was false.
                        prev.editor.isActive = true;

                        currentEditor = prev.editor;
                        currentAssembly = prev.assembly;

                        // =========================================================================
                        // v1.4 FIX: Двойной реблд родительского редактора
                        // =========================================================================
                        prev.editor.forceFullRedraw();
                        haxe.Timer.delay(() -> {
                                if (prev.editor != null && !prev.editor.isDisposed)
                                {
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
                                //   2b. syncAtomValuesToBlueprint() [v2.8] — writes LIVE inline values
                                //                                       into atomDef.values (BUG-B fix)
                                //   2c. syncChildStateToParentAtomDef() [v2.8] — writes child state
                                //                                       into PARENT atomDef.values (prevents
                                //                                       the stale internalStates overwrite)
                                //   3. syncConnectionsToTemplateIds()— translates runtime IDs in
                                //                                      internalConnections to template IDs
                                //   4. registerBlueprint()           — publish updated bp to AtomRegistry
                                //   5. updateInstancesOf()           — dispose + recreate via Factory
                                //
                                // After step 3, the bp is structurally identical to what
                                // ProjectManager.saveAssemblyToLibrary() writes to disk, so the
                                // reconstruction path is load-symmetric.
                                // ═══════════════════════════════════════════════════════════════════
                                utils.Trap.log("POP", "editor disposed, parent reactivated; sync+reconstruct begin");
                                var asm = current.assembly;

                                // 1. Refresh external port names based on connected atoms
                                asm.refreshExternalPortNames();

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
                                remapParentConnectionsToPortNames(asm);

                                // 2. Sync renamed atom displayNames into atomDef.values
                                asm.syncDisplayNamesToBlueprint();

                                // 2b. v2.8 (BUG-B): Sync LIVE inline values of internal atoms
                                //     (TextInput text, gains, toggle states...) into
                                //     atomDef.values. Before this, values reached the
                                //     in-memory blueprint ONLY during disk saves, so
                                //     pop()-reconstruction restored the LAST SAVED state
                                //     (e.g., 50 instead of the edited 3).
                                asm.syncAtomValuesToBlueprint();

                                // 2c. v2.8 (BUG-B level-2): Sync the exited child's own
                                //     persistent state into the PARENT's atomDef.values.
                                //     _createInternalInstances() calls restoreState()
                                //     AFTER the child constructor finishes — which
                                //     OVERWRITES the child internals with whatever the
                                //     parent atomDef.values holds. Stale internalStates
                                //     there (from the last disk save) would resurrect
                                //     dead values; this keeps the overwrite fresh.
                                syncChildStateToParentAtomDef(asm);

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
                catch (e:Dynamic)
                {
                        // v2.6: NO finally-block in Haxe (try REQUIRES catch, and the
                        // finally keyword does not exist in the language). This catch
                        // serves as the finally-substitute: the topology lock MUST be
                        // released even on exception — a stuck lock would freeze the
                        // whole simulation permanently. Re-throw afterwards so the
                        // caller learns about the failure.
                        utils.Trap.log("POP", "EXCEPTION in pop: " + e);
                        tg.unlockTopology();
                        throw e;
                }
                // v2.6: Normal path — the graph is whole again. Flush deferred
                utils.Trap.log("POP", "unlockTopology (normal) — graph whole");
                // propagations + emit REDRAW_WIRES.
                tg.unlockTopology();
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
         */
        private function updateInstancesOf(typeId:String):Void
        {
                utils.Trap.log("RECON", "updateInstancesOf: " + typeId + " in parent " + currentAssembly.blueprint.name);
                trace('🔍 updateInstancesOf: Looking for assemblies of type "$typeId" in parent "${currentAssembly.blueprint.name}"');
                var newBp = library.AtomRegistry.get(typeId);
                if (newBp == null)
                {
                        trace('❌ updateInstancesOf: Blueprint "$typeId" not found in registry!');
                        return;
                }
                var foundCount = 0;
                // Iterate through all atoms in CURRENT editor (the parent)
                for (id in currentAssembly.internalAtoms.keys())
                {
                        var atom = currentAssembly.internalAtoms.get(id);
                        if (Std.isOfType(atom, Assembly))
                        {
                                var asm = cast(atom, Assembly);
                                if (asm.blueprint.id == typeId)
                                {
                                        foundCount++;
                                        utils.Trap.log("RECON", "found: runtime=" + id);
                                        trace('✅ updateInstancesOf: Found assembly "$typeId" with runtimeId="$id"');

                                        // ═══════════════════════════════════════════════════════════════════
                                        // v2.0: FULL RECONSTRUCTION (load-symmetric)
                                        // ═══════════════════════════════════════════════════════════════════

                                        var oldRuntimeId = asm.id;

                                        // 1. Unlink parent's external wires to old assembly's port.external.
                                        //    This MUST happen BEFORE dispose() because Contact.dispose()
                                        //    only removes THIS from contacts that THIS links to — it
                                        //    cannot remove THIS from contacts that link TO this.
                                        utils.Trap.log("RECON", "pre-unlink wires");
                                        unlinkParentWiresTo(asm);

                                        // 2. Dispose old assembly completely.
                                        //    This disposes internal atoms → their contacts →
                                        //    contact.callbackTargets = null → leaked DeviceView
                                        //    callbacks can no longer fire.
                                        utils.Trap.log("RECON", "pre-dispose old instance");
                                        asm.dispose();

                                        // 3. Recreate via Factory using the SAME runtime ID so the
                                        //    parent's blueprint.internalAtoms references stay valid.
                                        //    AssemblyFactory.createAtom() runs the full Assembly
                                        //    constructor, which is identical to the project-load path.
                                        //    (v2.6: under the topology lock its value pushes are
                                        //    deferred — see class docs.)
                                        var newInstance = AssemblyFactory.createAtom(typeId, oldRuntimeId);
                                        utils.Trap.log("RECON", "createAtom returned: " + (newInstance != null ? newInstance.id : "NULL"));
                                        if (newInstance == null)
                                        {
                                                trace('ERROR: EditorContext.updateInstancesOf: Failed to recreate assembly $typeId ($oldRuntimeId)');
                                                continue;
                                        }

                                        // 4. Replace in parent's internalAtoms map (key unchanged).
                                        currentAssembly.internalAtoms.set(oldRuntimeId, newInstance);

                                        // 5. Reconnect parent's external wires to the new port.external
                                        //    contacts of the freshly constructed assembly.
                                        //    (v2.6: suppressPropagation — values are aligned by the
                                        //    new instance's Deferred Sync Wave, not pushed mid-operation.)
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
                                        utils.Trap.log("RECON", "reattachNodeView done");
                                }
                        }
                }
                if (foundCount == 0) {
                        trace('⚠️ updateInstancesOf: No assemblies of type "$typeId" found in parent!');
                }
        }

        /**
         * v2.7: Remap PARENT blueprint connection contactNames to the actual
         * (refreshed) external port names of the child assembly.
         *
         * WHY THIS EXISTS (exit-crash forensics):
         * Assembly.refreshExternalPortNames() renames the child's ports
         * (PinDef.externalName + recreated ConductorPort), but the PARENT's
         * blueprint.internalConnections still reference the OLD contactName
         * (often the port's internalName, e.g. "outgoing_1", while the port
         * is now called "Mini_Audio_Capture_buffer"). Reconstruction then
         * fails to resolve contacts ("cOut=null → FAILED to link"), wires
         * vanish, and the app later crashes on the inconsistent graph.
         * A save→load cycle works fine because the DISK file stores the
         * refreshed externalName — this remap restores the SAME consistency
         * in memory.
         *
         * Matching strategy per connection endpoint that references the
         * child assembly (by runtime or template id):
         *   1. exact externalName match → OK, nothing to do
         *   2. contactName == port.internalName → remap (the common case:
         *      parent connections created before the first refresh, or via
         *      GroupAtoms which stores internalName)
         *   3. suffix match: externalName ends with "_" + contactName → remap
         *
         * @param childAsm The assembly whose ports were just refreshed
         */
        private function remapParentConnectionsToPortNames(childAsm:Assembly):Void
        {
                if (childAsm == null || childAsm.ports == null) return;
                var bp = currentAssembly.blueprint;
                if (bp == null || bp.internalConnections == null) return;

                // Build lookup: internalName → ConductorPort
                var byInternal = new Map<String, ConductorPort>();
                for (port in childAsm.ports)
                {
                        if (port != null && port.internalName != null)
                        {
                                byInternal.set(port.internalName, port);
                        }
                }

                var remapped = 0;
                for (conn in bp.internalConnections)
                {
                        // TO side references the child?
                        if (conn.to.atomId != "SELF" && _connRefersTo(conn.to.atomId, childAsm))
                        {
                                var port = _resolveChildPort(conn.to.contactName, childAsm, byInternal);
                                if (port != null && port.externalName != conn.to.contactName)
                                {
                                        trace('🔄 remap to: "${conn.to.contactName}" → "${port.externalName}"');
                                        conn.to.contactName = port.externalName;
                                        remapped++;
                                }
                        }
                        // FROM side references the child?
                        if (conn.from.atomId != "SELF" && _connRefersTo(conn.from.atomId, childAsm))
                        {
                                var port = _resolveChildPort(conn.from.contactName, childAsm, byInternal);
                                if (port != null && port.externalName != conn.from.contactName)
                                {
                                        trace('🔄 remap from: "${conn.from.contactName}" → "${port.externalName}"');
                                        conn.from.contactName = port.externalName;
                                        remapped++;
                                }
                        }
                }
                if (remapped > 0)
                {
                        trace('🔄 remapParentConnectionsToPortNames: remapped $remapped endpoint names for "${childAsm.blueprint.id}"');
                }
        }

        /** v2.7: does the connection atomId (runtime or template) refer to the child? */
        private function _connRefersTo(atomId:String, childAsm:Assembly):Bool
        {
                if (atomId == childAsm.id) return true;
                var realAtomId = currentAssembly.idMap.get(atomId);
                if (realAtomId == null) realAtomId = atomId;
                return realAtomId == childAsm.id;
        }

        /** v2.7: resolve a child port by contactName — exact, internalName, suffix */
        private function _resolveChildPort(contactName:String, childAsm:Assembly, byInternal:Map<String, ConductorPort>):ConductorPort
        {
                // 1. Exact externalName
                for (port in childAsm.ports)
                {
                        if (port != null && port.externalName == contactName) return port;
                }
                // 2. internalName (the common stale-name case)
                if (byInternal.exists(contactName)) return byInternal.get(contactName);
                // 3. Suffix "_name"
                var suffix = "_" + contactName;
                for (port in childAsm.ports)
                {
                        if (port != null && port.externalName != null
                                && StringTools.endsWith(port.externalName, suffix)) return port;
                }
                // 4. v2.11: PROGRESSIVE suffix — semantic names drift when the
                //    nested atom gets renamed (e.g. "Custom_Assembly_2_Com_Port_close"
                //    vs "Custom_Assembly_1_Com_Port_close"). Strip leading tokens
                //    until exactly one port matches the tail.
                return findPortByProgressiveSuffix(childAsm, contactName, null);
        }

        /**
         * v2.8: Syncs the EXITED child assembly's persistent state into the
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
         */
        private function syncChildStateToParentAtomDef(childAsm:Assembly):Void
        {
                if (childAsm == null || currentAssembly == null) return;
                var parentBp = currentAssembly.blueprint;
                if (parentBp == null || parentBp.internalAtoms == null) return;

                // Child's runtime id → template id, as seen from the PARENT's _idMap
                // (getTemplateId falls back to the runtime id itself for atoms that
                // were added at runtime without a registered mapping).
                var templateId = currentAssembly.getTemplateId(childAsm.id);

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
         *                                                        in pop are now
         *                                                        redundant but
         *                                                        idempotent and safe)
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

                // 2b. Sync the assembly's own displayName into blueprint.name
                //     so the .atom file on disk reflects the user's rename.
                if (currentAssembly.displayName != null
                        && currentAssembly.displayName != currentAssembly.blueprint.name)
                {
                        currentAssembly.blueprint.name = currentAssembly.displayName;
                }

                // 2c. v2.8 (BUG-B): Sync live inline values into atomDef.values so
                //     DISK saves capture the CURRENT state through the same funnel
                //     the pop()-reconstruction path relies on (save = load =
                //     reconstruct — full load-symmetry).
                currentAssembly.syncAtomValuesToBlueprint();

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
         */
        private function reconnectExternalLinksToAssembly(targetAsm:Assembly):Void
        {
                trace('🔗 reconnectExternalLinksToAssembly: targetAsm.id="${targetAsm.id}", targetAsm.blueprint.id="${targetAsm.blueprint.id}"');
                var bp = currentAssembly.blueprint;
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
                                var cOut = resolveContactInParent(conn.from);
                                var cIn = resolveContactInParent(conn.to);

                                // If cIn is null and conn.to references an Assembly,
                                // try to reconcile the contactName with actual port externalNames.
                                if (cIn == null && conn.to.atomId != "SELF")
                                {
                                        var toAsm = resolveAssemblyInParent(conn.to.atomId);
                                        if (toAsm != null)
                                        {
                                                // v2.7 STEEL RECONCILIATION (in priority order):
                                                //   a) suffix match (externalName ends with "_"+requested) — legacy v2.7
                                                //   b) internalName match — the common stale-name case:
                                                //      GroupAtoms stored internalName; refreshExternalPortNames
                                                //      renamed the port to a semantic externalName
                                                var requestedName = conn.to.contactName;
                                                var fallbackPort = findPortByContactSuffix(toAsm, requestedName, INPUT);
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
                                                        fallbackPort = findPortByProgressiveSuffix(toAsm, requestedName, INPUT);
                                                }
                                                if (fallbackPort != null)
                                                {
                                                        // Update connection in-place
                                                        conn.to.contactName = fallbackPort.externalName;
                                                        // Re-resolve cIn
                                                        cIn = resolveContactInParent(conn.to);
                                                        trace('   🔄 Reconciled cIn: "${requestedName}" → "${conn.to.contactName}"');
                                                }
                                        }
                                }

                                // Same for cOut (if conn.from references an Assembly)
                                if (cOut == null && conn.from.atomId != "SELF")
                                {
                                        var fromAsm = resolveAssemblyInParent(conn.from.atomId);
                                        if (fromAsm != null)
                                        {
                                                // v2.7 STEEL RECONCILIATION: suffix, then internalName
                                                var requestedName = conn.from.contactName;
                                                var fallbackPort = findPortByContactSuffix(fromAsm, requestedName, OUTPUT);
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
                                                        fallbackPort = findPortByProgressiveSuffix(fromAsm, requestedName, OUTPUT);
                                                }
                                                if (fallbackPort != null)
                                                {
                                                        conn.from.contactName = fallbackPort.externalName;
                                                        cOut = resolveContactInParent(conn.from);
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
                                                utils.Trap.log("REALIGN", "pushing value from " + (src.owner != null ? src.owner.id : "?") + "." + src.name);
                                                src.propagateCurrentValue();
                                        }
                                }
                        });
                }
        }
    /**
     * v2.7: Resolve an atomId (template or runtime) to an Assembly instance
     * in the parent's internalAtoms. Returns null if the atom is not an Assembly.
     */
    private function resolveAssemblyInParent(atomId:String):core.base.Assembly
    {
        if (atomId == null || atomId == "SELF") return null;
        var realAtomId = currentAssembly.idMap.get(atomId);
        if (realAtomId == null) realAtomId = atomId;
        var obj = currentAssembly.internalAtoms.get(realAtomId);
        if (obj == null) return null;
        if (Std.isOfType(obj, core.base.Assembly)) {
            return cast(obj, core.base.Assembly);
        }
        return null;
    }

    /**
     * v2.7: Find a port on the target Assembly whose externalName ends with
     * the requested suffix pattern.
     *
     * Used when parent.bp.internalConnections references a port by its OLD
     * externalName (e.g., "Pass_in"), but refreshExternalPortNames() has
     * changed the port's externalName to a longer form (e.g.,
     * "Custom_Assembly_1_Pass_in"). We match by suffix to find the right port.
     *
     * Heuristic:
     *   - Exact match: externalName == requestedName (preferred)
     *   - Suffix match: externalName ends with "_" + requestedName
     *   - Type filter: only consider ports of the requested type
     *
     * @param asm           Target assembly
     * @param requestedName The contactName from parent's blueprint
     * @param type          Expected port type (INPUT or OUTPUT)
     * @return Matching ConductorPort or null
     */
    /**
     * v2.11: Progressive suffix matching — the weapon against semantic
     * port-name drift.
     *
     * Port externalNames are composed from the connected atom's displayName
     * ("Custom_Assembly_2_Com_Port_close"). When that displayName changes
     * between pop cycles, the parent blueprint keeps the OLD composed name.
     * Exact / internalName / full-suffix matchers all fail on such drift.
     *
     * This matcher strips leading tokens of the requested name, one at a
     * time, and at each level collects the ports (of the requested type,
     * when given) whose externalName ends with "_" + tail. The FIRST level
     * with EXACTLY ONE candidate wins — the match is unambiguous.
     *
     *   requested: "Custom_Assembly_2_Com_Port_close"
     *   ports:      "Custom_Assembly_1_Com_Port_close" ... (unique tails)
     *   level tail "Com_Port_close" -> unique -> MATCH
     *
     * Ambiguity at every level returns null (never mis-wire), with a trace.
     *
     * @param asm           Target assembly
     * @param requestedName Stale contactName from the parent blueprint
     * @param type          Optional port type filter (INPUT / OUTPUT)
     * @return The uniquely matching ConductorPort or null
     */
    private function findPortByProgressiveSuffix(asm:core.base.Assembly, requestedName:String, ?type:Null<core.types.ContactType>):core.base.ConductorPort
    {
        if (asm == null || asm.ports == null || requestedName == null) return null;

        var tokens:Array<String> = requestedName.split("_");
        if (tokens.length < 2) return null; // nothing to strip

// Walk from the longest tail to the shortest, dropping one leading
// token per level. Stop at the tail of length 1 (shorter tails are
// too generic to be trusted).
        var level:Int = 1;
        while (level < tokens.length - 1)
        {
                var tail:String = tokens.slice(level).join("_");
                var suffix:String = "_" + tail;
                var candidate:core.base.ConductorPort = null;
                var count:Int = 0;
                for (p in asm.ports)
                {
                        if (p == null || p.externalName == null) continue;
                        if (type != null && p.type != type) continue;
                        if (p.externalName == requestedName) continue; // exact tried already
                        if (StringTools.endsWith(p.externalName, suffix))
                        {
                                candidate = p;
                                count++;
                                if (count > 1) break; // ambiguous — stop early
                        }
                }
                if (count == 1)
                {
                        trace('🔄 Progressive suffix match: "${requestedName}" ~ "${candidate.externalName}" (tail "${tail}")');
                        return candidate;
                }
                level++;
        }
        trace('⚠️ Progressive suffix match: no unique port for "${requestedName}"');
        return null;
    }

    private function findPortByContactSuffix(asm:core.base.Assembly, requestedName:String, type:core.types.ContactType):core.base.ConductorPort
    {
        if (asm == null || asm.ports == null) return null;

        // First: exact match
        for (p in asm.ports) {
            if (p != null && p.externalName == requestedName && p.type == type) {
                return p;
            }
        }

        // Second: suffix match ("X_requestedName")
        // Haxe String has no endsWith() method — use StringTools.endsWith().
        var suffix = "_" + requestedName;
        for (p in asm.ports) {
            if (p == null || p.externalName == null) continue;
            if (p.type != type) continue;
            if (StringTools.endsWith(p.externalName, suffix)) {
                return p;
            }
        }

        return null;
    }

        /**
         * Resolves a Contact in the context of the CURRENT (parent) assembly.
         *
         * This brilliantly leverages the existing Atom.getInput/getOutput methods,
         * which already know how to find Assembly ports by their externalName!
         */
        private function resolveContactInParent(point:core.data.Blueprint.ConnectionPoint):core.base.Contact
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

                        var atom:core.base.Atom = cast obj;

                        // getInput and getOutput search by Contact.name.
                        // For Assemblies, external contacts are registered with externalName.
                        // For simple atoms, contacts are registered with their standard name.
                        // This perfectly matches the contactName stored in the parent's blueprint!
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

        /**
        * v2.5: Delegates to NamingService instead of walking the tree.
        *
        * The previous tree-walk approach had two issues:
        *  (a) It only saw atoms in the currently-loaded editor stack — atoms
        *      in not-yet-loaded or already-closed contexts were invisible.
        *  (b) It was duplicating state already maintained by NamingService,
        *      causing potential desync.
        *
        * NamingService is the single source of truth: every atom's displayName
        * is registered on creation and unregistered on dispose, so its map is
        * always in sync with the live atom set.
        *
        * The signature (name, ?excludeId) → Bool is preserved for backwards
        * compatibility with all callers that pass this method as a callback
        * to NodeEditor / NodeView / GroupAtomsCommand.
        */
        public function isNameTakenGlobally(name:String, ?excludeId:String):Bool
        {
                return core.logic.NamingService.isInstanceNameTaken(name, excludeId);
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
                //container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
                //container.graphics.lineStyle(1, _theme.FRAME_BORDER_COLOR);
                container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
                container.graphics.endFill();

                container.x = margin;
                container.y = margin;
        }

        // =========================================================================
        // v2.6 HELPER: suppressPropagation variants for future call sites
        // =========================================================================
        /**
        * v2.6: Creates a physical link between two contacts WITHOUT pushing
        * the current value (suppressPropagation). Kept as a named helper so
        * future call sites that must not inject signals mid-mutation have a
        * self-documenting entry point instead of remembering the flag.
        */
        public static function linkSilent(cOut:Contact, cIn:Contact):Bool
        {
                if (cOut == null || cIn == null) return false;
                if (cOut.hasLink(cIn)) return true;
                cOut.link(cIn, true);
                return true;
        }
}

typedef EditorEntry =
{
        var assembly:Assembly;
        var editor:NodeEditor;
        var blocker:Sprite;
        var container:Sprite;
        @:optional var parentCameraState:{x:Float, y:Float, zoom:Float};
}
