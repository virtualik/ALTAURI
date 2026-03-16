package editor;

import openfl.display.Sprite;
import openfl.geom.Point;
import editor.NodeView;

/**
 * VIEWPORT MANAGER v1.1 (Zoom Performance Fix)
 * Handles Pan, Zoom, and Visibility culling logic.
 * 
 * v1.1 Changes:
 * - Added lazy activation for DeviceView (prevents mass activation during zoom)
 * - Added visibility update throttling
 * - Integrated EditorState for global zoom tracking
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
    private var _zoomMin:Float = 1.7;
    private var _zoomMax:Float = 3.0;
    
    // FIX: Lazy activation system
    private var _isZooming:Bool = false;
    private var _zoomEndTimer:haxe.Timer = null;
    private var _pendingActivations:Array<NodeView> = [];
    
    // FIX: Throttling
    private var _lastVisibilityUpdate:Float = 0;
    private static inline var VISIBILITY_THROTTLE:Float = 0.05; // 20 FPS max for visibility
    
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
        
        // Update global state
        EditorState.setIsPanning(true);
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
        EditorState.setIsPanning(false);
    }
    
    public function isPanning():Bool return _isPanning;
    
    // ========================================================================
    // ZOOM (WITH LAZY ACTIVATION)
    // ========================================================================
    public function handleZoom(delta:Int, stageX:Float, stageY:Float, container:Sprite):Void {
        var zoomFactor:Float = 1.2;
        if (delta < 0) zoomFactor = 1 / 1.2;
        
        var mouseLocal:Point = _canvas.globalToLocal(new Point(stageX, stageY));
        var oldScale:Float = _canvas.scaleX;
        var newScale:Float = oldScale * zoomFactor;
        
        if (newScale < _zoomMin) newScale = _zoomMin;
        if (newScale > _zoomMax) newScale = _zoomMax;
        
        if (newScale == oldScale) return;
        
        // FIX: Mark as zooming
        _isZooming = true;
        EditorState.setIsZooming(true); // ← Update global state
        
        // Reset zoom end timer
        if (_zoomEndTimer != null) {
            _zoomEndTimer.stop();
            _zoomEndTimer = null;
        }
        
        // Schedule zoom end detection (150ms after last zoom)
        _zoomEndTimer = haxe.Timer.delay(() -> {
            _isZooming = false;
            EditorState.setIsZooming(false); // ← Reset global state
            _processPendingActivations();
        }, 15);
        
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
    // VISIBILITY CULLING (WITH LAZY ACTIVATION)
    // ========================================================================
    public function updateVisibility(nodes:Iterator<NodeView>, stageWidth:Float, stageHeight:Float):Void {
        // FIX: Throttle visibility updates during rapid zoom
        var now = haxe.Timer.stamp();
        if (_isZooming && (now - _lastVisibilityUpdate) < VISIBILITY_THROTTLE) {
            return;
        }
        _lastVisibilityUpdate = now;
        
        var margin:Float = 150;
        
        // Calculate visible bounds in Canvas coordinates
        var viewLeft:Float = (-_canvas.x / _canvas.scaleX) - margin;
        var viewTop:Float = (-_canvas.y / _canvas.scaleY) - margin;
        var viewRight:Float = viewLeft + (stageWidth / _canvas.scaleX) + (margin * 2);
        var viewBottom:Float = viewTop + (stageHeight / _canvas.scaleY) + (margin * 2);
        
        var visibleCount:Int = 0;
        var newlyVisible:Int = 0;
        var newlyHidden:Int = 0;
        
        for (view in nodes) {
            if (view == null) continue;
            
            var wasVisible = view.visible;
            var isVisible = (view.x > viewLeft && view.x < viewRight && view.y > viewTop && view.y < viewBottom);
            
            if (isVisible) visibleCount++;
            
            if (view.visible != isVisible) {
                // FIX: During zoom, only hide nodes, defer activation
                if (_isZooming) {
                    if (isVisible && !wasVisible) {
                        // Node became visible during zoom - defer activation
                        if (_pendingActivations.indexOf(view) == -1) {
                            _pendingActivations.push(view);
                        }
                        // Still set visible for rendering
                        view.visible = true;
                        newlyVisible++;
                    } else if (!isVisible && wasVisible) {
                        // Node became hidden - deactivate immediately
                        view.visible = false;
                        newlyHidden++;
                    }
                } else {
                    // Not zooming - full activation/deactivation
                    view.visible = isVisible;
                    if (isVisible && !wasVisible) newlyVisible++;
                    else if (!isVisible && wasVisible) newlyHidden++;
                }
            }
        }
        
        // Log if many nodes became visible at once
        if (newlyVisible > 3 || newlyHidden > 3) {
            trace('VISIBILITY DEBUG: Zoom=${Std.string(_canvas.scaleX).substr(0, 5)}, Visible=${visibleCount}, NewVisible=${newlyVisible}, NewHidden=${newlyHidden}');
        }
    }
    
    // FIX: Process pending activations after zoom ends
    private function _processPendingActivations():Void {
        if (_pendingActivations.length == 0) return;
        
        trace('VISIBILITY: Processing ${_pendingActivations.length} pending activations after zoom');
        
        // Activate in small batches to avoid single-frame spike
        var batchSize = 5;
        var processed = 0;
        
        for (view in _pendingActivations) {
            if (view != null && view.visible) {
                // Re-trigger visible to activate DeviceView
                view.visible = view.visible;
                processed++;
                
                // Stop if batch limit reached (remaining will process next frame)
                if (processed >= batchSize) break;
            }
        }
        
        _pendingActivations = _pendingActivations.slice(batchSize);
        
        // If still pending, schedule next batch
        if (_pendingActivations.length > 0) {
            haxe.Timer.delay(() -> _processPendingActivations(), 50);
        }
    }
    
    public function isZooming():Bool {
        return _isZooming;
    }
    
    public function getCurrentScale():Float {
        return _canvas.scaleX;
    }
}