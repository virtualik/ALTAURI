package editor;

import openfl.display.Sprite;
import openfl.geom.Point;
import editor.NodeView;

/**
 * VIEWPORT MANAGER v1.0
 * Handles Pan, Zoom, and Visibility culling logic.
 * Extracted from NodeEditor to separate concerns.
 */
class ViewportManager {

    private var _canvas:Sprite;
    private var _theme:EditorTheme;

    // Pan State
    private var _isPanning:Bool = false;
    private var _panStartX:Float = 0;
    private var _panStartY:Float = 0;
    private var _canvasStartX:Float = 0;
    private var _canvasStartY:Float = 0;

    // Zoom Settings
    private var _zoomMin:Float = 0.1;
    private var _zoomMax:Float = 3.0;

    public function new(canvas:Sprite) {
        _canvas = canvas;
        _theme = EditorTheme.getInstance();
    }

    // ========================================================================
    // PAN
    // ========================================================================

    public function handlePanStart(stageX:Float, stageY:Float):Void {
        if (_isPanning) return;
        _isPanning = true;
        _panStartX = stageX;
        _panStartY = stageY;
        _canvasStartX = _canvas.x;
        _canvasStartY = _canvas.y;
    }

    public function handlePanMove(stageX:Float, stageY:Float):Void {
        if (!_isPanning) return;
        var dx = stageX - _panStartX;
        var dy = stageY - _panStartY;
        _canvas.x = _canvasStartX + dx;
        _canvas.y = _canvasStartY + dy;
    }

    public function handlePanEnd():Void {
        _isPanning = false;
    }

    public function isPanning():Bool return _isPanning;

    // ========================================================================
    // ZOOM
    // ========================================================================

    public function handleZoom(delta:Int, stageX:Float, stageY:Float, container:Sprite):Void {
        var zoomFactor:Float = 1.1;
        if (delta < 0) zoomFactor = 1 / 1.1;

        var mouseLocal:Point = _canvas.globalToLocal(new Point(stageX, stageY));

        var oldScale:Float = _canvas.scaleX;
        var newScale:Float = oldScale * zoomFactor;

        if (newScale < _zoomMin) newScale = _zoomMin;
        if (newScale > _zoomMax) newScale = _zoomMax;
        if (newScale == oldScale) return;

        _canvas.scaleX = newScale;
        _canvas.scaleY = newScale;

        // Adjust position to zoom towards cursor
        var targetGlobalPos:Point = new Point(
            stageX - (mouseLocal.x * newScale),
            stageY - (mouseLocal.y * newScale)
        );

        var targetLocalPos:Point = container.globalToLocal(targetGlobalPos);

        _canvas.x = targetLocalPos.x;
        _canvas.y = targetLocalPos.y;
    }

    // ========================================================================
    // STATE
    // ========================================================================

    public function getViewState():{x:Float, y:Float, zoom:Float} {
        return { x: _canvas.x, y: _canvas.y, zoom: _canvas.scaleX };
    }

    public function setViewState(state:{x:Float, y:Float, zoom:Float}):Void {
        if (state == null) return;
        _canvas.x = state.x;
        _canvas.y = state.y;
        var z = state.zoom;
        if (z < _zoomMin) z = _zoomMin;
        if (z > _zoomMax) z = _zoomMax;
        _canvas.scaleX = z;
        _canvas.scaleY = z;
    }

    // ========================================================================
    // VISIBILITY CULLING
    // ========================================================================

    public function updateVisibility(nodes:Iterator<NodeView>, stageWidth:Float, stageHeight:Float):Void {
        var margin:Float = 150;
        
        // Calculate visible bounds in Canvas coordinates
        var viewLeft:Float = (-_canvas.x / _canvas.scaleX) - margin;
        var viewTop:Float = (-_canvas.y / _canvas.scaleY) - margin;
        var viewRight:Float = viewLeft + (stageWidth / _canvas.scaleX) + (margin * 2);
        var viewBottom:Float = viewTop + (stageHeight / _canvas.scaleY) + (margin * 2);

        for (view in nodes) {
            if (view == null) continue;
            var isVisible = (view.x > viewLeft && view.x < viewRight && view.y > viewTop && view.y < viewBottom);
            if (view.visible != isVisible) view.visible = isVisible;
        }
    }
}