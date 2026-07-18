// ============================================================================
// FILE: editor/EditorContext.hx (ИСПРАВЛЕННАЯ ВЕРСИЯ v1.4)
// ============================================================================
package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * EDITOR CONTEXT v1.4 (Full Redraw Fix – Double Delay)
 * Manages the stack of open editors (NodeEditor instances) and their camera states.
 *
 * v1.4 Changes:
 * - FIXED: push() now calls editor.forceFullRedraw() twice (immediately and after 100ms)
 *   to ensure all NodeViews are created and wires are drawn.
 * - FIXED: pop() now calls prev.editor.forceFullRedraw() with double delay.
 *
 * v1.3 Changes:
 * - FIXED: push() now calls editor.forceFullRedraw() after a short delay
 *   to ensure all NodeViews are created and wires are drawn.
 * - FIXED: pop() now calls prev.editor.forceFullRedraw() to restore parent view.
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
            updateInstancesOf(editedId);
        }
        
        // Refresh assembly views and wires
        currentEditor.refreshAssemblyViews();
    }
    
	/**
	* Update visual representation of assemblies with specified ID
	* in all open editors.
	* 
	* v1.5 FIX: FULL RECONSTRUCTION PATTERN
	* Instead of fragile updateFromBlueprint(), we completely dispose the old 
	* Assembly instance and create a fresh one with the SAME runtimeId.
	* This guarantees clean state (no leaked callbacks, fresh _idMap) while 
	* maintaining valid external connections from the parent blueprint.
	*/
	private function updateInstancesOf(typeId:String):Void
	{
		var newBp = library.AtomRegistry.get(typeId);
		if (newBp == null) return;
		
		// Iterate through all atoms in CURRENT editor
		for (id in currentAssembly.internalAtoms.keys())
		{
			var atom = currentAssembly.internalAtoms.get(id);
			if (Std.isOfType(atom, Assembly))
			{
				var oldAsm = cast(atom, Assembly);
				
				// Check if this is the assembly that was just edited
				if (oldAsm.blueprint.id == typeId)
				{
					trace('EditorContext: Reconstructing Assembly ${oldAsm.id} with fresh blueprint');
					
					// 1. Preserve the runtime ID so parent connections remain valid
					var oldRuntimeId = oldAsm.id;
					
					// 2. Dispose the old instance completely 
					// (This triggers NodeView.dispose -> DeviceView.deactivate -> unsubscribes contacts)
					if (Std.isOfType(oldAsm, core.base.IDisposable))
					{
						try {
							cast(oldAsm, core.base.IDisposable).dispose();
						} catch (e:Dynamic) {
							trace('EditorContext: Error disposing old assembly: $e');
						}
					}
					
					// 3. Remove from internal atoms map
					currentAssembly.internalAtoms.remove(oldRuntimeId);
					
					// 4. Create a FRESH instance using the SAME runtime ID
					var newAsm = core.base.AssemblyFactory.createAtom(typeId, oldRuntimeId);
					
					if (newAsm != null)
					{
						// 5. Insert the fresh instance back into the parent
						currentAssembly.internalAtoms.set(oldRuntimeId, newAsm);
						
						// 6. Rebuild external links. 
						// Since the runtimeId is the same, parent blueprint connections are valid.
						// We just need the parent to re-resolve contacts to the NEW internal ports.
						currentAssembly.rebuildInternalConnections();
						
						trace('EditorContext: Assembly ${oldRuntimeId} successfully reconstructed');
					}
					else
					{
						trace('ERROR: EditorContext failed to recreate assembly ${typeId}');
					}
				}
			}
		}
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
		var bp = currentAssembly.blueprint;
		if (bp.internalConnections == null) return;
		
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