package editor;

import openfl.display.Sprite;
import openfl.geom.Rectangle;
import core.base.Assembly;
import editor.NodeView;
import editor.EditorTheme;
import ecs.ECS;

/**
 * SELECTION MANAGER v1.0
 * Отвечает за логику выделения узлов и визуализацию Лассо.
 */
class SelectionManager {

    private var _assembly:Assembly;
    private var _container:Sprite;
    private var _theme:EditorTheme;
    private var _getNodeView:String -> NodeView;

    private var _selection:editor.GroupSelectionManager;

    // Lasso State
    private var _lasso:Sprite;
    private var _isLassoing:Bool = false;
    private var _lassoStartX:Float = 0;
    private var _lassoStartY:Float = 0;

    public function new() {
        _selection = new editor.GroupSelectionManager();
        _theme = EditorTheme.getInstance();
    }

    public function setContext(assembly:Assembly, container:Sprite, nodeViewProvider:String -> NodeView):Void {
        _assembly = assembly;
        _container = container;
        _getNodeView = nodeViewProvider;

        if (_lasso == null) {
            _lasso = new Sprite();
            _lasso.mouseEnabled = false;
        }
        if (_container != null && !_container.contains(_lasso)) {
            _container.addChild(_lasso);
        }
    }

    // =========================================================================
    // API
    // =========================================================================

    public function handleNodeClick(nodeId:String, view:NodeView, ctrlKey:Bool):Void {
        if (_isLassoing) return;

        if (ctrlKey) {
            if (_selection.hasNode(nodeId)) {
                deselectNode(nodeId, view);
            } else {
                selectNode(nodeId, view);
            }
        } else {
            if (!_selection.hasNode(nodeId)) {
                deselectAll();
                selectNode(nodeId, view);
            }
        }
    }

    public function handleCanvasMouseDown(localX:Float, localY:Float):Void {
        _isLassoing = true;
        _lassoStartX = localX;
        _lassoStartY = localY;

        _lasso.graphics.clear();
        _lasso.x = localX;
        _lasso.y = localY;
        
        if (_container != null) _container.addChild(_lasso);
    }

    public function handleMouseMove(localX:Float, localY:Float):Void {
        if (!_isLassoing) return;

        var dx = localX - _lassoStartX;
        var dy = localY - _lassoStartY;

        _lasso.graphics.clear();
        _lasso.graphics.lineStyle(1, _theme.LASSO_BORDER_COLOR, 0.8);
        _lasso.graphics.beginFill(_theme.LASSO_FILL_COLOR, _theme.LASSO_FILL_ALPHA);
        _lasso.graphics.drawRect(0, 0, dx, dy);
        _lasso.graphics.endFill();
    }

    public function handleMouseUp():Void {
        if (!_isLassoing) return;
        _isLassoing = false;

        var lassoBounds:Rectangle = _lasso.getBounds(_container);
        
        if (lassoBounds.width > 5 && lassoBounds.height > 5) {
            deselectAll();
            selectInRect(lassoBounds);
        } else {
            deselectAll();
        }

        _lasso.graphics.clear();
    }

    // =========================================================================
    // OPERATIONS
    // =========================================================================

    public function selectNode(id:String, view:NodeView):Void {
        _selection.addNode(id);
        view.selected = true;
        ECS.setSelected(id, true);
    }

    public function deselectNode(id:String, view:NodeView):Void {
        _selection.removeNode(id);
        view.selected = false;
        ECS.setSelected(id, false);
    }

    public function deselectAll():Void {
        for (id in _selection.getNodeIds()) {
            var view = _getNodeView(id);
            if (view != null) {
                view.selected = false;
                ECS.setSelected(id, false);
            }
        }
        _selection.clearNodes();
        _selection.clearWires();
    }

	public function clearWires():Void {
        _selection.clearWires();
    }

    public function selectInRect(rect:Rectangle):Void {
        var idsInRect = ECS.getInRect(rect.x, rect.y, rect.width, rect.height);
        for (id in idsInRect) {
            var view = _getNodeView(id);
            if (view != null) {
                selectNode(id, view);
            }
        }
    }
    
    // Called from ContextMenu "Select All"
    public function selectAll(nodeIds:Array<String>):Void {
        deselectAll();
        for (id in nodeIds) {
            var view = _getNodeView(id);
            if (view != null) selectNode(id, view);
        }
    }

    // =========================================================================
    // GETTERS
    // =========================================================================

    public function getSelectedNodeIds():Array<String> return _selection.getNodeIds();
    public function getSelectedNodeCount():Int return _selection.getNodeCount();
    public function getSelectedWireIds():Array<String> return _selection.getWireIds();
    public function hasNode(id:String):Bool return _selection.hasNode(id);
    public function isLassoing():Bool return _isLassoing;
	public function setWires(ids:Array<String>):Void {_selection.setWires(ids);}
	
    public function dispose():Void {
        if (_lasso != null && _lasso.parent != null) _lasso.parent.removeChild(_lasso);
        _lasso = null;
        _selection.clear();
    }
}