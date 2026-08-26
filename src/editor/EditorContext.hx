package editor;

import openfl.display.Sprite;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.TickGenerator;

/**
* EDITOR CONTEXT v2.14 (Stable Port Naming v3.0 bridge: legacy alias resolution + heal + background wire safety net)
* Manages the stack of open editors (NodeEditor instances) and their camera states.
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.14 CHANGES (Gate-Independent Background Wire Refresh — Episod G-4.2)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM (crash_trap.log, session 2026-08-26): after port operations done
*  from INSIDE an assembly, the dimmed background editors never rebuilt
*  their wires — the v4.14 G41-SYNC marker (placed after NodeEditor's
*  own-child gate) fired only for the active editor, while the background
*  NodeView for the same assembly demonstrably reacted. Every static link
*  of the gate chain re-audited clean; the defect is runtime-only and is
*  being localized by the v4.15 exit-path breadcrumbs (G41-BG-ENTER /
*  NULLID / FOREIGN / PASS / ERR).
*
*  FIX (safety net): EditorContext — the FIRST ASSEMBLY_PORTS_CHANGED
*  subscriber (resubscriber-protected through Impulsys.clear(), field-proven
*  by the v2.12 auto-heal) — schedules ONE coalesced 100 ms pass that calls
*  the now-public NodeEditor.refreshWiresAfterPortsChange() on EVERY
*  non-top stack editor. The background wires heal regardless of what the
*  own-child gate does at runtime; the G41-BG-NET Trap tag records every
*  net-driven refresh, so the field log separates gate-driven and
*  net-driven heals cleanly.
*
* ═══════════════════════════════════════════════════════════════════════════
* v2.12 CHANGES (Parent-Wire Auto-Heal — fix F, Naming & Integrity pack)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM (field evidence, Test 2, 2026-08-24): when a child assembly's
*  gateway port is renamed (refreshExternalPortNames via ConnectCommand or
*  wall-port operations), _recreatePortWithNewExternalName disposes the old
*  external contact — and every PARENT wire linked to it dies silently. The
*  blueprint definition survives, the physical link is gone; redrawn wires
*  hit the ConnectCommand "already exists" skip and stayed dead forever.
*
*  FIX: EditorContext subscribes to ASSEMBLY_PORTS_CHANGED (emitted by
*  Assembly.refreshExternalPortNames v2.6 whenever a port was recreated) and
*  immediately re-establishes the parent-side physical links through the
*  same battle-tested reconciliation path as pop()-reconstruction (STEEL
*  matchers, silent links, REALIGN value wave). Two cases:
*    1. the changed assembly is a child of currentAssembly;
*    2. the changed assembly IS currentAssembly (being edited right now) —
*       the affected parent sits one level down the editor stack.
*  reconnectExternalLinksToAssembly() gained an optional parentCtx parameter
*  for case 2 (default keeps prior behaviour for all existing call sites).
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
* │   │  Camera State Management (Episod C → editor.EditorCameraStore):  │   │
* │   │  - _camStore:EditorCameraStore                                   │   │
* │   │    Stores viewport state for each assembly by blueprint.id.     │   │
* │   │    across multiple push/pop cycles.                             │   │
* │   │  - On push: has(bpId)? get → restore : centerOnContent         │   │
* │   │  - On pop:  save(bpId, currentEditor.getViewState())            │   │
* │   │  - clear():  wipe store on project reload                       │   │
* │   │  Visual Chrome (Episod C → editor.EditorVisuals):                │   │
* │   │  - _visuals.drawContainerFrame(container, stage)                 │   │
* │   │  - _visuals.createBlocker(stage) on non-root push()             │   │
* │   │                                                                 │   │
* │   │  v2.0 Assembly Reconstruction (on pop with updateInstances):    │   │
* │   │  - updateInstancesOf(typeId)                                    │   │
* │   │    → unlinkParentWiresTo(asm)                                   │   │
* │   │    → asm.dispose()                                              │   │
* │   │    → AssemblyFactory.createAtom(typeId, oldRuntimeId)           │   │
* │   │    → reconnectExternalLinksToAssembly(newAsm) [v2.6: no push]   │   │
* │   │    → currentEditor.reattachNodeView(oldRuntimeId, newInstance)  │   │
* │   │  (Episod D — all 4 steps delegated to editor.AssemblyReconstructor │ │
* │   │   via _recon.updateInstancesOf(typeId, currentAssembly,         │   │
* │   │   currentEditor, _portResolver); see                           │   │
* │   │   editor/AssemblyReconstructor.hx for the full v2.0/v2.6/v2.7/  │   │
* │   │   v2.10/v2.12 rationale)                                        │   │
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

        // v1.0 (Episod A — Editor de-god-ification): stateless port-name
        // resolver extracted from EditorContext. All port-matching and
        // connection-resolution logic lives in editor.PortNameResolver now;
        // EditorContext delegates through _portResolver.method(...).
        private var _portResolver:PortNameResolver;

        // v1.0 (Episod B — Editor de-god-ification): stateless blueprint
        // synchronization service extracted from EditorContext. All
        // prepare-for-save and pre-reconstruction sync pipelines live in
        // editor.BlueprintSynchronizer now; EditorContext delegates through
        // _bpSync.method(...).
        private var _bpSync:BlueprintSynchronizer;

        // v1.0 (Episod C — Editor de-god-ification): cross-push/pop camera
        // state store extracted from EditorContext. Per-blueprint.id
        // viewport snapshots persist here across multiple enter/exit
        // cycles; see editor.EditorCameraStore.hx for the rationale of
        // why this is a separate class vs EditorEntry.parentCameraState.
        private var _camStore:EditorCameraStore;

        // v1.0 (Episod C — Editor de-god-ification): stateless rendering
        // helpers (container frame + parent-blocker overlay) extracted
        // from EditorContext. Pure Sprite/Stage manipulation; no
        // EditorContext state involved.
        private var _visuals:EditorVisuals;

        // v1.0 (Episod D — Editor de-god-ification): stateless
        // reconstruction service extracted from EditorContext. All
        // updateInstancesOf / unlinkParentWiresTo /
        // reconnectExternalLinksToAssembly / onAssemblyPortsChanged logic
        // lives in editor.AssemblyReconstructor now; EditorContext
        // delegates through _recon.method(...).
        private var _recon:AssemblyReconstructor;

        // =========================================================================
        // STATE
        // =========================================================================
        private var _stack:Array<EditorEntry>;

        public var currentAssembly(default, null):Assembly;
        public var currentEditor(default, null):NodeEditor;

        /** v2.12: ASSEMBLY_PORTS_CHANGED handler (parent-wire auto-heal, fix F). */
        private var _onAssemblyPortsChanged:Impulse -> Void;

        /**
        * v2.14 (Episod G-4.2): coalesced timer for the gate-independent
        * background wire refresh. Non-null while a pass is pending; stopped
        * in clear() so a torn-down stack is never poked after disposal.
        */
        private var _bgRefreshTimer:haxe.Timer = null;

        // =========================================================================
        // CONSTRUCTOR
        // =========================================================================
        public function new(layer:Sprite)
        {
                _layer = layer;
                _stack = [];
                _theme = EditorTheme.getInstance();
                _portResolver = new PortNameResolver();
                _bpSync = new BlueprintSynchronizer();
                _camStore = new EditorCameraStore();
                _visuals = new EditorVisuals();
                _recon = new AssemblyReconstructor();
                // v2.12: parent-wire auto-heal — see onAssemblyPortsChanged().
                _onAssemblyPortsChanged = onAssemblyPortsChanged;
                Impulsys.subscribeToImpulse(core.logic.EventType.ASSEMBLY_PORTS_CHANGED, _onAssemblyPortsChanged);
                // v3.2 (Episod F-bold): register for auto-restore — Impulsys.clear()
                // invokes resubscribe() by itself; Main no longer needs to know
                // about this subscription's lifecycle.
                Impulsys.registerResubscriber(resubscribe);
        }

        /**
         * v3.1 (Episod F-fix): Re-subscribe to Impulsys after a system-wide
         * Impulsys.clear().
         *
         * WHY THIS EXISTS:
         *   EditorContext is created exactly ONCE (Main.hx init) and lives for
         *   the whole application session. Its constructor subscribes to
         *   ASSEMBLY_PORTS_CHANGED (v2.12 parent-wire auto-heal, delegated to
         *   AssemblyReconstructor.onAssemblyPortsChanged). Main.hx hardReset()
         *   calls Impulsys.clear() which wipes ALL subscriptions — including
         *   ours — and until v3.1 nothing restored this one. The auto-heal
         *   silently died after every Reset (visual redraw kept working via
         *   per-instance NodeEditor subscriptions, so the loss was invisible).
         *
         * v3.2 (Episod F-bold): the constructor now registers this method
         * with Impulsys.registerResubscriber(), so Impulsys.clear() invokes
         * it automatically. Until v3.2 it was called from a manual recovery
         * block in Main.hx hardReset() — that block no longer exists.
         *
         * Safe to call multiple times: Impulsys.subscribeToImpulse() rejects
         * duplicate references.
         */
        public function resubscribe():Void
        {
                Impulsys.subscribeToImpulse(core.logic.EventType.ASSEMBLY_PORTS_CHANGED, _onAssemblyPortsChanged);
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
                        // (per-stack-entry scratch — separate from the
                        // persistent _camStore, which is for cross-cycle reuse)
                        parentState = top.editor.getViewState();

                        // Episod C (v1.0): blocker creation delegated to
                        // editor.EditorVisuals.createBlocker(). Returns a fully
                        // configured Sprite; caller adds it to the layer.
                        var blocker = _visuals.createBlocker(_layer.stage);
                        _layer.addChild(blocker);

                        top.editor.mouseEnabled = false;
                        top.editor.mouseChildren = false;
                        // v2.3: Deactivate parent editor's impulse handlers to prevent
                        // broadcast storm at deep nesting levels.
                        top.editor.isActive = false;
                        // v4.16 (Ghost Wire Leak, Episod G-5): an editor going to the
                        // background must not keep any gesture state. PORT_DRAG_START
                        // is a global-bus impulse and now guarded by isActive in
                        // NodeEditor, but any flag that predates the deactivation
                        // dies HERE, by construction, instead of surviving until
                        // the matching pop() reactivates the editor.
                        top.editor.cancelPendingGestures();
                        utils.Trap.log("G5-PUSH", "parent deactivated: bp=" + top.assembly.blueprint.id);
                        top.blocker = blocker;
                }

                // Create container for new editor
                        var container = new Sprite();
                        // Episod C (v1.0): frame drawing delegated to
                        // editor.EditorVisuals.drawContainerFrame().
                        _visuals.drawContainerFrame(container, _layer.stage);
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
                // Episod C (v1.0): cross-cycle camera storage delegated to
                // editor.EditorCameraStore. has/get/save/clear mirror what
                // the bare Map<String,{x,y,zoom}> did before, but the storage
                // concern is now externalised.
                // ═══════════════════════════════════════════════════════════════════
                var bpId = assembly.blueprint.id;
                if (_camStore.has(bpId))
                {
                        // Restore previously saved state
                        var state = _camStore.get(bpId);
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
                        // Episod C (v1.0): delegated to _camStore.save(...).
                        var currentState = current.editor.getViewState();
                        _camStore.save(editedId, currentState);
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
                        // v4.16 (Ghost Wire Leak, Episod G-5): clean gesture slate
                        // on reactivation. Belt-and-suspenders: even if a future
                        // code path smuggles a pending flag past the isActive
                        // guards while this editor was covered, it is dropped HERE
                        // — never drawn as a stray ghost wire after pop().
                        prev.editor.cancelPendingGestures();
                        utils.Trap.log("G5-POP", "parent reactivated: bp=" + prev.assembly.blueprint.id);

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
                                // Episod B (v1.0): the full sync pipeline (refreshExternalPortNames →
                                // remapParentConnectionsToPortNames → syncDisplayNamesToBlueprint →
                                // syncAtomValuesToBlueprint → syncChildStateToParentAtomDef →
                                // syncConnectionsToTemplateIds → registerBlueprint) lives in
                                // editor.BlueprintSynchronizer.syncBeforeReconstruction now;
                                // EditorContext delegates through _bpSync.method(...).
                                // ═══════════════════════════════════════════════════════════════════
                                utils.Trap.log("POP", "editor disposed, parent reactivated; sync+reconstruct begin");
                                var asm = current.assembly;

                                // Steps 1-4: full sync pipeline (load-symmetric to save→load)
                                _bpSync.syncBeforeReconstruction(asm, currentAssembly, _portResolver);

                                // 5. Now reconstruct with up-to-date data
                                // Episod D (v1.0): delegated to
                                // _recon.updateInstancesOf — see
                                // editor/AssemblyReconstructor.hx.
                                _recon.updateInstancesOf(asm.blueprint.id, currentAssembly, currentEditor, _portResolver);
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

        // ═══════════════════════════════════════════════════════════════════
        // ASSEMBLY RECONSTRUCTION ORCHESTRATOR — EXTRACTED to
        // editor.AssemblyReconstructor (Episod D, removed in Episod E)
        // ═══════════════════════════════════════════════════════════════════
        // The method that used to live here —
        //     updateInstancesOf(typeId)  [v2.0 orchestrator]
        // — has been removed from EditorContext. pop() now calls
        //     _recon.updateInstancesOf(typeId, currentAssembly, currentEditor, _portResolver)
        // directly. See editor/AssemblyReconstructor.hx for the full v2.0
        // / v2.2 / v2.6 rationale (load-symmetric reconstruction,
        // topology-locked value push deferral).
        // ═══════════════════════════════════════════════════════════════════

        // ═══════════════════════════════════════════════════════════════════
        // PORT RESOLUTION — EXTRACTED to editor.PortNameResolver (Episod A)
        // ═══════════════════════════════════════════════════════════════════
        // The three methods that used to live here —
        //     remapParentConnectionsToPortNames(childAsm)
        //     _connRefersTo(atomId, childAsm)
        //     _resolveChildPort(contactName, childAsm, byInternal)
        // — have been moved to the stateless editor.PortNameResolver class.
        // All call sites in this file now read
        //     _portResolver.method(args, currentAssembly)
        // See editor/PortNameResolver.hx for the full documentation + impl.
        // ═══════════════════════════════════════════════════════════════════
        // ═══════════════════════════════════════════════════════════════════
        // CHILD-TO-PARENT STATE SYNC — EXTRACTED to editor.BlueprintSynchronizer (Episod B)
        // ═══════════════════════════════════════════════════════════════════
        // The method that used to live here —
        //     syncChildStateToParentAtomDef(childAsm)  [BUG-B level-2 helper]
        // — has been moved to the stateless editor.BlueprintSynchronizer class.
        // All call sites in this file now read
        //     _bpSync.syncChildStateToParentAtomDef(childAsm, currentAssembly)
        //     _bpSync.syncBeforeReconstruction(childAsm, currentAssembly, _portResolver)
        // See editor/BlueprintSynchronizer.hx for the full documentation + impl.
        // ═══════════════════════════════════════════════════════════════════

        // ═══════════════════════════════════════════════════════════════════
        // PARENT-WIRE UNLINK — EXTRACTED to editor.AssemblyReconstructor
        // (Episod D, removed in Episod E)
        // ═══════════════════════════════════════════════════════════════════
        // The method that used to live here —
        //     unlinkParentWiresTo(targetAsm)  [v2.0 helper]
        // — has been removed from EditorContext. AssemblyReconstructor
        // calls _recon.unlinkParentWiresTo(targetAsm, parentAsm, portResolver)
        // directly from within its updateInstancesOf pipeline. See
        // editor/AssemblyReconstructor.hx for the full v2.0 rationale
        // (stale Contact.linkedTargets after child dispose).
        // ═══════════════════════════════════════════════════════════════════

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
                // Episod B (v1.0): the full pre-save sync pipeline lives in
                // editor.BlueprintSynchronizer.prepareForSave now; EditorContext
                // delegates through _bpSync.prepareForSave(currentAssembly).
                // See editor/BlueprintSynchronizer.hx for the full v2.2/v2.8
                // rationale (lost displayNames on disk, lost inline values).
                _bpSync.prepareForSave(currentAssembly);
        }
        // =========================================================================
        // v2.12: PARENT-WIRE AUTO-HEAL (fix F — Naming & Integrity pack)
        // =========================================================================
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
         */
        private function onAssemblyPortsChanged(impulse:Impulse):Void
        {
                // Episod D (v1.0): reactive parent-wire auto-heal logic moved
                // to editor.AssemblyReconstructor.onAssemblyPortsChanged.
                // EditorContext delegates through _recon.onAssemblyPortsChanged(...).
                // The Impulsys subscription is still OWNED by EditorContext (in the
                // constructor); only the reaction body lives in the delegate.
                // See editor/AssemblyReconstructor.hx for the full v2.12
                // rationale (parent-wire auto-heal after gateway port rename).
                _recon.onAssemblyPortsChanged(impulse, _stack, currentAssembly, _portResolver);
                // v2.14 (Episod G-4.2): gate-independent background safety net.
                // Runs 100 ms AFTER the dispatch settles, so every NodeView
                // subscriber has already rebuilt its port sprites by then.
                scheduleBackgroundRefresh();
        }

        /**
         * v2.14 (Episod G-4.2): schedule ONE coalesced pass that refreshes
         * the wires of every BACKGROUND editor (all stack entries except
         * the top — the active editor refreshes itself through its own
         * two-stage deferred pipeline, NodeEditor v4.14+).
         *
         * WHY A SAFETY NET: the own-child gate inside NodeEditor's own
         * ASSEMBLY_PORTS_CHANGED handler provably never fires for background
         * editors in the field (v4.14 G41 log: 27 lines, all active=true),
         * while every static link of that gate re-audits clean. Until the
         * runtime defect is localized (v4.15 breadcrumbs), this net keeps
         * the dimmed background wires correct — and it does NOT reintroduce
         * the v2.3 broadcast storm: everything is coalesced into a single
         * 100 ms pass per impulse burst, not a per-impulse O(N) fan-out.
         */
        private function scheduleBackgroundRefresh():Void
        {
                if (_bgRefreshTimer != null) return; // already scheduled
                _bgRefreshTimer = haxe.Timer.delay(function():Void
                {
                        _bgRefreshTimer = null;
                        // The TOP editor is skipped: it is the one the user is
                        // editing in, and NodeEditor's own deferred pipeline
                        // already refreshes it.
                        var top:Int = _stack.length - 1;
                        for (i in 0...top)
                        {
                                var entry:EditorEntry = _stack[i];
                                if (entry == null || entry.editor == null) continue;
                                if (entry.editor.isDisposed) continue;
                                utils.Trap.log("G41-BG-NET",
                                        "asm=" + (entry.assembly != null
                                                && entry.assembly.blueprint != null
                                                ? entry.assembly.blueprint.id : "?")
                                        + " level=" + i);
                                entry.editor.refreshWiresAfterPortsChange();
                        }
                }, 100);
        }

        // ═══════════════════════════════════════════════════════════════════
        // PARENT-WIRE RECONNECT — EXTRACTED to editor.AssemblyReconstructor
        // (Episod D, removed in Episod E)
        // ═══════════════════════════════════════════════════════════════════
        // The method that used to live here —
        //     reconnectExternalLinksToAssembly(targetAsm, ?parentCtx)
        // — has been removed from EditorContext. AssemblyReconstructor
        // calls _recon.reconnectExternalLinksToAssembly(targetAsm, parentCtx,
        // portResolver) directly. The optional parentCtx parameter from
        // v2.12 became MANDATORY in the delegate (Episod D). See
        // editor/AssemblyReconstructor.hx for the full v2.6 / v2.7 / v2.10 /
        // v2.12 rationale (silent links, STEEL reconciliation, REALIGN wave).
        // ═══════════════════════════════════════════════════════════════════
        // ═══════════════════════════════════════════════════════════════════
        // PORT RESOLUTION — EXTRACTED to editor.PortNameResolver (Episod A)
        // ═══════════════════════════════════════════════════════════════════
        // The four methods that used to live here —
        //     resolveAssemblyInParent(atomId, ?ctx)
        //     findPortByProgressiveSuffix(asm, requestedName, ?type)
        //     findPortByContactSuffix(asm, requestedName, type)
        //     resolveContactInParent(point, ?ctx)
        // — have been moved to the stateless editor.PortNameResolver class.
        // All call sites in this file now read
        //     _portResolver.method(args, currentAssembly)
        // See editor/PortNameResolver.hx for the full documentation + impl.
        // ═══════════════════════════════════════════════════════════════════

        /**
         * Reset entire stack (on project reload) and clear camera states.
         */
        public function clear():Void
        {
                // v2.14 (Episod G-4.2): a pending background refresh must never
                // fire against a torn-down stack.
                if (_bgRefreshTimer != null)
                {
                        _bgRefreshTimer.stop();
                        _bgRefreshTimer = null;
                }
                while (_stack.length > 0)
                {
                        var item = _stack.pop();
                        item.editor.dispose();
                        if (item.container.parent != null) _layer.removeChild(item.container);
                        if (item.blocker != null && item.blocker.parent != null) _layer.removeChild(item.blocker);
                }
                currentEditor = null;
                currentAssembly = null;
                // Episod C (v1.0): camera state reset delegated to _camStore.clear().
                _camStore.clear();
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

        // ═══════════════════════════════════════════════════════════════════
        // VISUAL — EXTRACTED to editor.EditorVisuals (Episod C)
        // ═══════════════════════════════════════════════════════════════════
        // The methods that used to live here —
        //     drawContainerFrame(container)
        //     (inline blocker creation in push())
        // — have been moved to the stateless editor.EditorVisuals class.
        // All call sites in this file now read
        //     _visuals.drawContainerFrame(container, _layer.stage)
        //     _visuals.createBlocker(_layer.stage)
        // See editor/EditorVisuals.hx for the full documentation + impl.
        // ═══════════════════════════════════════════════════════════════════

        // =========================================================================
        // v2.6 HELPER: suppressPropagation variants for future call sites
        // =========================================================================
        // ═══════════════════════════════════════════════════════════════════
        // v2.6 HELPER linkSilent — REMOVED in Episod E (dead code)
        // ═══════════════════════════════════════════════════════════════════
        // Audit (Episod E) found ZERO live callers across all 136 source
        // files. It was a self-documenting wrapper around
        //     cOut.link(cIn, true)  // suppressPropagation
        // intended for future call sites, but no such sites ever
        // materialized. Direct cOut.link(cIn, true) is the canonical
        // pattern now. The wrapper is removed to keep EditorContext lean.
        // ═══════════════════════════════════════════════════════════════════
}

// EditorEntry typedef lives in editor/EditorEntry.hx (Episod D v1.0):
// Haxe requires top-level types to live in a file matching the type name,
// so EditorEntry had to move out of EditorContext.hx to be visible to
// editor.AssemblyReconstructor. See editor/EditorEntry.hx for the
// structure + rationale.


