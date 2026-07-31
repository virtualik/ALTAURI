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

/**
* EDITOR CONTEXT v2.5 (Global Name Uniqueness via NamingService + Load-Symmetric Reconstruction + isActive + Reattach + Pre-Save Sync)
* Manages the stack of open editors (NodeEditor instances) and their camera states.
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
*  pop() sets prev.editor.isActive = true and calls forceFullRedraw()
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
* │   │    → reconnectExternalLinksToAssembly(newAsm)                   │   │
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
	 *   5. currentEditor.reattachNodeView(oldRuntimeId, newInstance) —
	 *      v2.2: swap the parent's NodeView atom reference to the new
	 *      instance, release old DeviceView, acquire fresh one
	 *
	 * The runtime ID is preserved (forcedId) so the parent blueprint's
	 * AtomDef.instanceId reference remains valid and no blueprint mutation
	 * is required.
	 */
	private function updateInstancesOf(typeId:String):Void
	{
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
					trace('✅ updateInstancesOf: Found assembly "$typeId" with runtimeId="$id"');

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
	    if (foundCount == 0) {
			trace('⚠️ updateInstancesOf: No assemblies of type "$typeId" found in parent!');
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
						// Find a port whose externalName ends with the
						// requested contactName pattern. This handles the
						// common case where refreshExternalPortNames
						// prefixed the name with the assembly displayName.
						var requestedName = conn.to.contactName;
						var fallbackPort = findPortByContactSuffix(toAsm, requestedName, INPUT);
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
						var requestedName = conn.from.contactName;
						var fallbackPort = findPortByContactSuffix(fromAsm, requestedName, OUTPUT);
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
					cOut.link(cIn);
					trace('   ✓ Linked!');
				} else if (cOut == null || cIn == null) {
					trace('   ✗ FAILED to link!');
				}
			}
		}
		trace('🔗 reconnect: Reconnected $reconnectedCount links');
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
		container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
		container.graphics.lineStyle(1, _theme.FRAME_BORDER_COLOR);
		container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
		container.graphics.endFill();

		container.x = margin;
		container.y = margin;
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