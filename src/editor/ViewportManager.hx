package editor;

import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.events.TouchEvent;
import editor.NodeView;

/**
 * VIEWPORT MANAGER v1.3 (Zoom Performance Fix + Touch Support + Smart Pan Target)
 * Handles Pan, Zoom, Visibility culling, and Touch interactions.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ViewportManager                                                       │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Mouse Operations:                                              │   │
 * │   │  - handlePanStart/Move/End()  → Middle mouse pan                │   │
 * │   │  - handleZoom()               → Mouse wheel zoom                │   │
 * │   │                                                                 │   │
 * │   │  Touch Operations (Mobile/Tablet):                              │   │
 * │   │  - 1 Finger on BG           → Pan canvas                        │   │
 * │   │  - 1 Finger on Node/Port    → Ignored (let NodeEditor handle)   │   │
 * │   │  - 2 Fingers                → Pinch-to-zoom canvas              │   │
 * │   │  - Touch tracking           → Map<Int, {x, y}> by touchPointID  │   │
 * │   │                                                                 │   │
 * │   │  Visibility Culling:                                            │   │
 * │   │  - updateVisibility()      → Hide/show nodes based on viewport  │   │
 * │   │  - Throttled updates       → 20 FPS max during rapid zoom       │   │
 * │   │  - Batch activation        → Process pending in small batches   │   │
 * │   │                                                                 │   │
 * │   │  State:                                                         │   │
 * │   │  - getViewState()        → {x, y, zoom}                         │   │
 * │   │  - setViewState(state)   → Restore saved viewport               │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   v1.3 Changes:                                                         │
 * │   - Added isBackgroundTouch() to prevent pan from hijacking node/port   │
 * │     interactions. Pan now only triggers on _bgHitArea or _canvas.       │
 * │   - Added robust multi-touch tracking via touchPointID Map              │
 * │   - Removed invalid `stage` references (ViewportManager is not a Sprite)│
 * │   - Removed non-existent TouchEvent.TOUCH_CANCEL (OpenFL compatibility) │
 * │   - Added lazy activation for DeviceView (prevents mass activation)     │
 * │   - Added visibility update throttling                                  │
 * │   - Integrated EditorState for global zoom tracking                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ViewportManager
{
    // =========================================================================
    // DEPENDENCIES
    // =========================================================================
    private var _canvas:Sprite;
    private var _bgHitArea:Sprite; // Reference to the background hit area
    private var _theme:EditorTheme;
    
    // =========================================================================
    // PAN STATE
    // =========================================================================
    private var _isPanning:Bool = false;
    private var _panStartX:Float = 0;
    private var _panStartY:Float = 0;
    private var _canvasStartX:Float = 0;
    private var _canvasStartY:Float = 0;
    
    // =========================================================================
    // ZOOM SETTINGS
    // =========================================================================
    private var _zoomMin:Float = 0.1;
    private var _zoomMax:Float = 3.0;
    
    // =========================================================================
    // LAZY ACTIVATION SYSTEM
    // =========================================================================
    private var _isZooming:Bool = false;
    private var _zoomEndTimer:haxe.Timer = null;
    private var _pendingActivations:Array<NodeView> = [];
    
    // =========================================================================
    // THROTTLING
    // =========================================================================
    private var _lastVisibilityUpdate:Float = 0;
    private static inline var VISIBILITY_THROTTLE:Float = 0.05; // 20 FPS max
    
    // =========================================================================
    // TOUCH STATE
    // =========================================================================
    private var _activeTouches:Map<Int, {x:Float, y:Float}>;
    private var _touchCount:Int = 0;
    
    private var _touchPanning:Bool = false;
    private var _touchPanStartX:Float = 0;
    private var _touchPanStartY:Float = 0;
    private var _touchPanStartCanvasX:Float = 0;
    private var _touchPanStartCanvasY:Float = 0;

    private var _pinchZooming:Bool = false;
    private var _pinchStartDistance:Float = 0;
    private var _pinchStartScale:Float = 1.0;
    private var _pinchCenterX:Float = 0;
    private var _pinchCenterY:Float = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
     * Create ViewportManager.
     * 
     * @param canvas The main canvas sprite.
     * @param bgHitArea Optional background hit area sprite. If provided, pan 
     *                  will ONLY trigger when this specific sprite is touched,
     *                  preventing interference with NodeView/Port interactions.
     */
    public function new(canvas:Sprite, ?bgHitArea:Sprite)
    {
        _canvas = canvas;
        _bgHitArea = bgHitArea;
        _theme = EditorTheme.getInstance();
        _activeTouches = new Map();
        
        // Listen to touch events directly on the canvas.
        // NOTE: OpenFL TouchEvent does NOT have TOUCH_CANCEL. 
        // TOUCH_END reliably captures both finger lifts and system interruptions.
        _canvas.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
        _canvas.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
        _canvas.addEventListener(TouchEvent.TOUCH_END, onTouchEnd);
    }
    
    // =========================================================================
    // PAN OPERATIONS
    // =========================================================================
    /**
     * Begin pan operation.
     */
    public function handlePanStart(stageX:Float, stageY:Float):Void
    {
        if (_isPanning) return;
        
        _isPanning = true;
        _panStartX = stageX;
        _panStartY = stageY;
        _canvasStartX = _canvas.x;
        _canvasStartY = _canvas.y;
        
        // Update global state
        EditorState.setIsPanning(true);
    }
    
    /**
     * Update canvas position during pan.
     */
    public function handlePanMove(stageX:Float, stageY:Float):Void
    {
        if (!_isPanning) return;
        
        var dx = stageX - _panStartX;
        var dy = stageY - _panStartY;
        
        _canvas.x = _canvasStartX + dx;
        _canvas.y = _canvasStartY + dy;
    }
    
    /**
     * End pan operation.
     */
    public function handlePanEnd():Void
    {
        _isPanning = false;
        EditorState.setIsPanning(false);
    }
    
    public function isPanning():Bool return _isPanning;
    
    // =========================================================================
    // ZOOM OPERATIONS (WITH LAZY ACTIVATION)
    // =========================================================================
    /**
     * Handle zoom operation.
     * Scales canvas towards cursor position.
     * 
     * Uses lazy activation to prevent mass DeviceView activation during zoom.
     */
    public function handleZoom(delta:Int, stageX:Float, stageY:Float, container:Sprite):Void
    {
        var zoomFactor:Float = 1.1;
        if (delta < 0) zoomFactor = 1 / 1.1;
        
        var mouseLocal:Point = _canvas.globalToLocal(new Point(stageX, stageY));
        
        var oldScale:Float = _canvas.scaleX;
        var newScale:Float = oldScale * zoomFactor;
        
        if (newScale < _zoomMin) newScale = _zoomMin;
        if (newScale > _zoomMax) newScale = _zoomMax;
        if (newScale == oldScale) return;
        
        // Mark as zooming
        _isZooming = true;
        EditorState.setIsZooming(true);
        
        // Reset zoom end timer
        if (_zoomEndTimer != null)
        {
            _zoomEndTimer.stop();
            _zoomEndTimer = null;
        }
        
        // Schedule zoom end detection (15ms after last zoom)
        _zoomEndTimer = haxe.Timer.delay(() -> {
            _isZooming = false;
            EditorState.setIsZooming(false);
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
    
    // =========================================================================
    // STATE MANAGEMENT
    // =========================================================================
    /**
     * Get current viewport state.
     */
    public function getViewState():{x:Float, y:Float, zoom:Float}
    {
        return { x: _canvas.x, y: _canvas.y, zoom: _canvas.scaleX };
    }
    
    /**
     * Restore viewport state.
     */
    public function setViewState(state:{x:Float, y:Float, zoom:Float}):Void
    {
        if (state == null) return;
        
        _canvas.x = state.x;
        _canvas.y = state.y;
        
        var z = state.zoom;
        if (z < _zoomMin) z = _zoomMin;
        if (z > _zoomMax) z = _zoomMax;
        
        _canvas.scaleX = z;
        _canvas.scaleY = z;
    }
    
    // =========================================================================
    // VISIBILITY CULLING (WITH LAZY ACTIVATION)
    // =========================================================================
    /**
     * Update node visibility based on viewport bounds.
     * 
     * During zoom: only hide nodes, defer activation until zoom ends.
     * Throttled to 20 FPS max during rapid zoom.
     */
    public function updateVisibility(nodes:Iterator<NodeView>, stageWidth:Float, stageHeight:Float):Void
    {
        // Throttle visibility updates during rapid zoom
        var now = haxe.Timer.stamp();
        if (_isZooming && (now - _lastVisibilityUpdate) < VISIBILITY_THROTTLE)
        {
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
        
        for (view in nodes)
        {
            if (view == null) continue;
											
            var wasVisible = view.visible;
			var size = view.getNodeSize();
			// AABB check: node is visible if any part of it is within viewport
			var isVisible = (view.x + size.width > viewLeft && view.x < viewRight &&
							 view.y + size.height > viewTop  && view.y < viewBottom);
            
            if (isVisible) visibleCount++;
            
            if (view.visible != isVisible)
            {
                // During zoom, only hide nodes, defer activation
                if (_isZooming)
                {
                    if (isVisible && !wasVisible)
                    {
                        // Node became visible during zoom - defer activation
                        if (_pendingActivations.indexOf(view) == -1)
                        {
                            _pendingActivations.push(view);
                        }
                        // Still set visible for rendering
                        view.visible = true;
                        newlyVisible++;
                    }
                    else if (!isVisible && wasVisible)
                    {
                        // Node became hidden - deactivate immediately
                        view.visible = false;
                        newlyHidden++;
                    }
                }
                else
                {
                    // Not zooming - full activation/deactivation
                    view.visible = isVisible;
                    if (isVisible && !wasVisible) newlyVisible++;
                    else if (!isVisible && wasVisible) newlyHidden++;
                }
            }
        }
        
        // Log if many nodes changed visibility at once
        if (newlyVisible > 3 || newlyHidden > 3)
        {
            //trace('VISIBILITY DEBUG: Zoom=${Std.string(_canvas.scaleX).substr(0, 5)}, Visible=${visibleCount}, NewVisible=${newlyVisible}, NewHidden=${newlyHidden}');
        }
    }
    
    /**
     * Process pending activations after zoom ends.
     * Activates in small batches to avoid single-frame spike.
     */
    private function _processPendingActivations():Void
    {
        if (_pendingActivations.length == 0) return;
        
        //trace('VISIBILITY: Processing ${_pendingActivations.length} pending activations after zoom');
        
        // Activate in small batches to avoid single-frame spike
        var batchSize = 5;
        var processed = 0;
        
        for (view in _pendingActivations)
        {
            if (view != null && view.visible)
            {
                // Re-trigger visible to activate DeviceView
                view.visible = view.visible;
                processed++;
                
                // Stop if batch limit reached (remaining will process next frame)
                if (processed >= batchSize) break;
            }
        }
        
        _pendingActivations = _pendingActivations.slice(batchSize);
        
        // If still pending, schedule next batch
        if (_pendingActivations.length > 0)
        {
            haxe.Timer.delay(() -> _processPendingActivations(), 50);
        }
    }
    
    public function isZooming():Bool
    {
        return _isZooming;
    }
    
    public function getCurrentScale():Float
    {
        return _canvas.scaleX;
    }
	
    // =========================================================================
    // TOUCH HANDLERS
    // =========================================================================
    private function onTouchBegin(e:TouchEvent):Void
    {
        // CRITICAL FIX v1.3: Only allow touch panning if the user touched the empty canvas background.
        // If they touched a NodeView, Port, Wire, or Widget, let that object handle the interaction.
        if (!isBackgroundTouch(e.target))
        {
            return; // Ignore this touch for viewport panning
        }

        if (!_activeTouches.exists(e.touchPointID))
        {
            _touchCount++;
        }
        _activeTouches.set(e.touchPointID, {x: e.stageX, y: e.stageY});
        updateTouchState();
    }

    private function onTouchMove(e:TouchEvent):Void
    {
        if (_activeTouches.exists(e.touchPointID))
        {
            _activeTouches.set(e.touchPointID, {x: e.stageX, y: e.stageY});
        }
        updateTouchState();
    }

    private function onTouchEnd(e:TouchEvent):Void
    {
        if (_activeTouches.exists(e.touchPointID))
        {
            _touchCount--;
        }
        _activeTouches.remove(e.touchPointID);
        updateTouchState();
    }

    // =========================================================================
    // TOUCH STATE MACHINE
    // =========================================================================
    private function updateTouchState():Void
    {
        if (_touchCount == 1)
        {
            if (!_touchPanning)
            {
                // One finger - start pan
                _touchPanning = true;
                _pinchZooming = false;
                EditorState.setIsPanning(true);
                EditorState.setIsZooming(false);
                
                var firstTouch = getFirstTouch();
                _touchPanStartX = firstTouch.x;
                _touchPanStartY = firstTouch.y;
                _touchPanStartCanvasX = _canvas.x;
                _touchPanStartCanvasY = _canvas.y;
            }
            else
            {
                // Continue pan with one finger
                var firstTouch = getFirstTouch();
                var dx = firstTouch.x - _touchPanStartX;
                var dy = firstTouch.y - _touchPanStartY;
                _canvas.x = _touchPanStartCanvasX + dx;
                _canvas.y = _touchPanStartCanvasY + dy;
            }
        }
        else if (_touchCount == 2)
        {
            if (!_pinchZooming)
            {
                // Two fingers - start pinch-to-zoom
                _pinchZooming = true;
                _touchPanning = false;
                EditorState.setIsPanning(false);
                EditorState.setIsZooming(true);
                
                _pinchStartDistance = calculatePinchDistance();
                _pinchStartScale = _canvas.scaleX;
                var center = getPinchCenter();
                _pinchCenterX = center.x;
                _pinchCenterY = center.y;
            }
            else
            {
                // Continue pinch-to-zoom
                var currentDistance = calculatePinchDistance();
                var scaleRatio = currentDistance / _pinchStartDistance;
                var newScale = _pinchStartScale * scaleRatio;
                
                // Clamp scale
                if (newScale < _zoomMin) newScale = _zoomMin;
                if (newScale > _zoomMax) newScale = _zoomMax;
                
                // Apply scale relative to pinch center
                var mouseLocal:Point = _canvas.globalToLocal(new Point(_pinchCenterX, _pinchCenterY));
                _canvas.scaleX = newScale;
                _canvas.scaleY = newScale;
                
                // Adjust position to zoom towards pinch center
                var targetGlobalPos:Point = new Point(
                    _pinchCenterX - (mouseLocal.x * newScale),
                    _pinchCenterY - (mouseLocal.y * newScale)
                );
                
                var container = _canvas.parent;
                if (container != null)
                {
                    var targetLocalPos:Point = container.globalToLocal(targetGlobalPos);
                    _canvas.x = targetLocalPos.x;
                    _canvas.y = targetLocalPos.y;
                }
            }
        }
        else if (_touchCount == 0)
        {
            // All fingers removed
            _touchPanning = false;
            _pinchZooming = false;
            EditorState.setIsPanning(false);
            EditorState.setIsZooming(false);
        }
        else if (_touchCount == 1 && _pinchZooming)
        {
            // Transitioned from pinch to pan
            _pinchZooming = false;
            _touchPanning = true;
            EditorState.setIsZooming(false);
            EditorState.setIsPanning(true);
            
            var firstTouch = getFirstTouch();
            _touchPanStartX = firstTouch.x;
            _touchPanStartY = firstTouch.y;
            _touchPanStartCanvasX = _canvas.x;
            _touchPanStartCanvasY = _canvas.y;
        }
    }

    // =========================================================================
    // TOUCH HELPER METHODS
    // =========================================================================
    /**
     * Check if the touch target is the background (empty canvas space).
     * 
     * This prevents the viewport from hijacking interactions with Nodes, 
     * Ports, Wires, or Widgets.
     * 
     * @param target The DisplayObject that was touched.
     * @return true if the touch is on the background, false otherwise.
     */
    private function isBackgroundTouch(target:openfl.display.DisplayObject):Bool
    {
        // 1. Strict check: If we have a dedicated background hit area, ONLY allow pan if touched.
        // This naturally excludes Nodes, Ports, Wires, and Widgets.
        if (_bgHitArea != null)
        {
            return (target == _bgHitArea || target == _canvas);
        }
        
        // 2. Fallback: Walk up the display list to ensure we didn't touch a NodeView.
        var current:openfl.display.DisplayObject = target;
        while (current != null && current != _canvas)
        {
            if (Std.isOfType(current, NodeView)) 
            {
                return false; // Touched a node or its child (port/widget)
            }
            current = current.parent;
        }
        
        return true; // Reached canvas without hitting a NodeView
    }

    private function getFirstTouch():{x:Float, y:Float}
    {
        for (touch in _activeTouches)
        {
            return touch;
        }
        return {x: 0, y: 0};
    }

    private function calculatePinchDistance():Float
    {
        // Calculate distance between two fingers
        var touches = [];
        for (t in _activeTouches) touches.push(t);
        
        if (touches.length >= 2)
        {
            var dx = touches[1].x - touches[0].x;
            var dy = touches[1].y - touches[0].y;
            return Math.sqrt(dx * dx + dy * dy);
        }
        
        return 0;
    }

    private function getPinchCenter():{x:Float, y:Float}
    {
        var touches = [];
        for (t in _activeTouches) touches.push(t);
        
        if (touches.length >= 2)
        {
            return {
                x: (touches[0].x + touches[1].x) / 2,
                y: (touches[0].y + touches[1].y) / 2
            };
        }
        
        return {x: 0, y: 0};
    }

    // =========================================================================
    // CLEANUP
    // =========================================================================
    /**
     * Dispose resources and remove event listeners.
     */
    public function dispose():Void
    {
        _canvas.removeEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
        _canvas.removeEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
        _canvas.removeEventListener(TouchEvent.TOUCH_END, onTouchEnd);
        
        _activeTouches = null;
        _pendingActivations = null;
        
        if (_zoomEndTimer != null)
        {
            _zoomEndTimer.stop();
            _zoomEndTimer = null;
        }
    }
}