package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * EDITOR CONTEXT v1.0
 * Manages the stack of open editors (NodeEditor instances).
 * Responsible for creating containers, background blocking, and context switching.
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
 * │   │                                                                 │   │
 * │   │  Visual State:                                                  │   │
 * │   │  - currentAssembly   → Currently edited assembly                │   │
 * │   │  - currentEditor     → Active NodeEditor instance               │   │
 * │   │  - blocker:Sprite    → Semi-transparent overlay (blocks input)  │   │
 * │   │                                                                 │   │
 * │   │  Container Management:                                          │   │
 * │   │  - _layer:Sprite     → Parent layer for all editors             │   │
 * │   │  - container:Sprite  → Frame with border for each editor        │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var context = new EditorContext(editorLayer);                         │
 * │   context.push(rootAssembly, true);  // Open root                      │
 * │   context.push(nestedAssembly);      // Drill down                     │
 * │   context.pop();                     // Go back                        │
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
    // CONSTRUCTOR
    // =========================================================================
    public function new(layer:Sprite)
    {
        _layer = layer;
        _stack = [];
        _theme = EditorTheme.getInstance();
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
        if (!isRoot && _stack.length > 0)
        {
            var top = _stack[_stack.length - 1];
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
        
        var entry:EditorEntry = {
            assembly: assembly,
            editor: editor,
            blocker: null,
            container: container
        };
        _stack.push(entry);
        
        currentEditor = editor;
        currentAssembly = assembly;
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
        
        // Update assembly preview in parent if it changed
        if (updateInstances)
        {
            updateInstancesOf(editedId);
        }
        
        currentEditor.refreshAssemblyViews();
    }
    
    /**
     * Update visual representation of assemblies with specified ID
     * in all open editors.
     */
    private function updateInstancesOf(typeId:String):Void
    {
        var newBp = library.AtomRegistry.get(typeId);
        if (newBp == null) return;
        
        // Iterate through all atoms in CURRENT editor
        // (stack is hierarchical, but cascade update not needed — 
        // sufficient to update view in parent)
        for (id in currentAssembly.internalAtoms.keys())
        {
            var atom = currentAssembly.internalAtoms.get(id);
            if (Std.isOfType(atom, Assembly))
            {
                var asm = cast(atom, Assembly);
                if (asm.blueprint.id == typeId) asm.updateFromBlueprint(newBp);
            }
        }
    }
    
    /**
     * Reset entire stack (on project reload).
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
    }
    
    public function getStackLength():Int return _stack.length;
    
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
}