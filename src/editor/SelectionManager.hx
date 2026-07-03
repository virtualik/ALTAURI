package editor;

import openfl.display.Sprite;
import openfl.geom.Rectangle;
import core.base.Assembly;
import editor.NodeView;
import editor.EditorTheme;
import ecs.ECS;

/**
 * SELECTION MANAGER v1.0
 * Handles node selection logic and Lasso visualization.
 *
 * Responsibilities:
 * - Handle click/lasso selection on canvas
 * - Manage selected nodes and wires
 * - Draw lasso rectangle during selection
 * - Integrate with ECS for selection state
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SelectionManager                                                      │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Dependencies:                                                  │   │
 * │   │  - _assembly:Assembly          → Current assembly context       │   │
 * │   │  - _container:Sprite           → Canvas for lasso drawing       │   │
 * │   │  - _getNodeView:NodeView       → Node lookup by ID              │   │
 * │   │  - _selection:GroupSelectionManager → Data storage              │   │
 * │   │  - _lasso:Sprite               → Lasso visualization            │   │
 * │   │                                                                 │   │
 * │   │  Mouse Handling:                                                │   │
 * │   │  - handleCanvasMouseDown(x, y)  → Start lasso                   │   │
 * │   │  - handleMouseMove(x, y)        → Draw lasso rect               │   │
 * │   │  - handleMouseUp()              → Finalize selection            │   │
 * │   │  - handleNodeClick(id, ctrl)    → Handle node click             │   │
 * │   │                                                                 │   │
 * │   │  Selection Operations:                                          │   │
 * │   │  - selectNode(id, view)                                         │   │
 * │   │  - deselectNode(id, view)                                       │   │
 * │   │  - deselectAll()                                                │   │
 * │   │  - selectInRect(rect)                                           │   │
 * │   │  - selectAll(ids)                                               │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var selection = new SelectionManager();                               │
 * │   selection.setContext(assembly, canvas, getNodeView);                  │
 * │   selection.handleCanvasMouseDown(mouseX, mouseY);                      │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class SelectionManager
{
    // =========================================================================
    // DEPENDENCIES
    // =========================================================================
    private var _assembly:Assembly;
    private var _container:Sprite;
    private var _theme:EditorTheme;
    private var _getNodeView:String -> NodeView;
    private var _selection:GroupSelectionManager;
    
    // =========================================================================
    // LASSO STATE
    // =========================================================================
    private var _lasso:Sprite;
    private var _isLassoing:Bool = false;
    private var _lassoStartX:Float = 0;
    private var _lassoStartY:Float = 0;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new()
    {
        _selection = new GroupSelectionManager();
        _theme = EditorTheme.getInstance();
    }
    
    // =========================================================================
    // CONTEXT SETUP
    // =========================================================================
    /**
     * Set context for selection manager.
     * Must be called before using selection operations.
     * 
     * @param assembly       Current assembly being edited
     * @param container      Canvas sprite for drawing lasso
     * @param nodeViewProvider Function to get NodeView by ID
     */
    public function setContext(assembly:Assembly, container:Sprite, nodeViewProvider:String -> NodeView):Void
    {
        _assembly = assembly;
        _container = container;
        _getNodeView = nodeViewProvider;
        
        if (_lasso == null)
        {
            _lasso = new Sprite();
            _lasso.mouseEnabled = false;
        }
        
        if (_container != null && !_container.contains(_lasso))
        {
            _container.addChild(_lasso);
        }
    }
    
    // =========================================================================
    // MOUSE HANDLING
    // =========================================================================
    /**
     * Handle node click event.
     * Supports Ctrl+click for multi-selection.
     * 
     * @param nodeId  ID of clicked node
     * @param view    NodeView instance
     * @param ctrlKey true if Ctrl key was held
     */
    public function handleNodeClick(nodeId:String, view:NodeView, ctrlKey:Bool):Void
    {
        if (_isLassoing) return;
        
        if (ctrlKey)
        {
            // Ctrl+click: toggle selection
            if (_selection.hasNode(nodeId))
            {
                deselectNode(nodeId, view);
            }
            else
            {
                selectNode(nodeId, view);
            }
        }
        else
        {
            // Regular click: select only this node if not already selected
            if (!_selection.hasNode(nodeId))
            {
                deselectAll();
                selectNode(nodeId, view);
            }
        }
    }
    
    /**
     * Handle canvas mouse down — start lasso selection.
     * 
     * @param localX Mouse X in canvas coordinates
     * @param localY Mouse Y in canvas coordinates
     */
    public function handleCanvasMouseDown(localX:Float, localY:Float):Void
    {
        _isLassoing = true;
        _lassoStartX = localX;
        _lassoStartY = localY;
        
        _lasso.graphics.clear();
        _lasso.x = localX;
        _lasso.y = localY;
        
        if (_container != null) _container.addChild(_lasso);
    }
    
    /**
     * Handle mouse move — draw lasso rectangle.
     * 
     * @param localX Mouse X in canvas coordinates
     * @param localY Mouse Y in canvas coordinates
     */
    public function handleMouseMove(localX:Float, localY:Float):Void
    {
        if (!_isLassoing) return;
        
        var dx = localX - _lassoStartX;
        var dy = localY - _lassoStartY;
        
        _lasso.graphics.clear();
        _lasso.graphics.lineStyle(1, _theme.LASSO_BORDER_COLOR, 0.8);
        _lasso.graphics.beginFill(_theme.LASSO_FILL_COLOR, _theme.LASSO_FILL_ALPHA);
        _lasso.graphics.drawRect(0, 0, dx, dy);
        _lasso.graphics.endFill();
    }
    
    /**
     * Handle mouse up — finalize lasso selection.
     * Selects all nodes within lasso rectangle.
     */
    public function handleMouseUp():Void
    {
        if (!_isLassoing) return;
        
        _isLassoing = false;
        
        var lassoBounds:Rectangle = _lasso.getBounds(_container);
        
        // Only select if lasso was large enough (not accidental click)
        if (lassoBounds.width > 5 && lassoBounds.height > 5)
        {
            deselectAll();
            selectInRect(lassoBounds);
        }
        else
        {
            deselectAll();
        }
        
        _lasso.graphics.clear();
    }
    
    // =========================================================================
    // SELECTION OPERATIONS
    // =========================================================================
    /**
     * Select a single node.
     * Updates both visual state and ECS.
     * 
     * @param id   Node ID
     * @param view NodeView instance
     */
    public function selectNode(id:String, view:NodeView):Void
    {
        _selection.addNode(id);
        view.selected = true;
        ECS.setSelected(id, true);
    }
    
    /**
     * Deselect a single node.
     * Updates both visual state and ECS.
     * 
     * @param id   Node ID
     * @param view NodeView instance
     */
    public function deselectNode(id:String, view:NodeView):Void
    {
        _selection.removeNode(id);
        view.selected = false;
        ECS.setSelected(id, false);
    }
    
    /**
     * Deselect all nodes and wires.
     * Clears entire selection state.
     */
    public function deselectAll():Void
    {
        for (id in _selection.getNodeIds())
        {
            var view = _getNodeView(id);
            if (view != null)
            {
                view.selected = false;
                ECS.setSelected(id, false);
            }
        }
        
        _selection.clearNodes();
        _selection.clearWires();
    }
    
    /**
     * Clear wire selection only.
     * Used when switching between node and wire selection.
     */
    public function clearWires():Void
    {
        _selection.clearWires();
    }
    
    /**
     * Select all nodes within a rectangle.
     * Uses ECS spatial query for efficiency.
     * 
     * @param rect Rectangle bounds in canvas coordinates
     */
    public function selectInRect(rect:Rectangle):Void
    {
        var idsInRect = ECS.getInRect(rect.x, rect.y, rect.width, rect.height);
        
        for (id in idsInRect)
        {
            var view = _getNodeView(id);
            if (view != null)
            {
                selectNode(id, view);
            }
        }
    }
    
    /**
     * Select all specified nodes.
     * Called from ContextMenu "Select All" action.
     * 
     * @param nodeIds Array of node IDs to select
     */
    public function selectAll(nodeIds:Array<String>):Void
    {
        deselectAll();
        
        for (id in nodeIds)
        {
            var view = _getNodeView(id);
            if (view != null) selectNode(id, view);
        }
    }
    
    // =========================================================================
    // GETTERS
    // =========================================================================
    /**
     * Get all selected node IDs.
     * @return Array of selected node IDs
     */
    public function getSelectedNodeIds():Array<String>
    {
        return _selection.getNodeIds();
    }
    
    /**
     * Get count of selected nodes.
     * @return Number of selected nodes
     */
    public function getSelectedNodeCount():Int
    {
        return _selection.getNodeCount();
    }
    
    /**
     * Get all selected wire IDs.
     * @return Array of selected wire IDs
     */
    public function getSelectedWireIds():Array<String>
    {
        return _selection.getWireIds();
    }
    
    /**
     * Check if a node is selected.
     * @param id Node ID to check
     * @return true if selected
     */
    public function hasNode(id:String):Bool
    {
        return _selection.hasNode(id);
    }
    
    /**
     * Check if lasso selection is in progress.
     * @return true if lasso is active
     */
    public function isLassoing():Bool
    {
        return _isLassoing;
    }
    
    /**
     * Set wire selection (called by WireRenderer).
     * @param ids Array of wire IDs to select
     */
    public function setWires(ids:Array<String>):Void
    {
        _selection.setWires(ids);
    }
    
    // =========================================================================
    // DISPOSE
    // =========================================================================
    /**
     * Clean up resources.
     * Removes lasso from container and clears selection.
     */
    public function dispose():Void
    {
        if (_lasso != null && _lasso.parent != null)
        {
            _lasso.parent.removeChild(_lasso);
        }
        
        _lasso = null;
        _selection.clear();
    }
}