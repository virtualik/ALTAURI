package editor;

import openfl.display.Sprite;
import openfl.display.DisplayObject;
import openfl.events.Event;
import openfl.events.TouchEvent;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;

/**
 * VIEWPORT MANAGER v5.1 (Touch + Mouse API compatibility)
 *
 * Manages canvas pan and zoom via two input paths:
 *   • TOUCH (Android): 2-finger drag = PAN, 2-finger pinch = ZOOM.
 *     1-finger touches are ignored — they pass through to NodeEditor.
 *     >2 fingers are rejected (ignored until count drops below 3).
 *   • MOUSE (Desktop): middle-button drag = PAN, scroll wheel = ZOOM.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * TOUCH INTERACTION RULES (7-rule spec)
 * ═══════════════════════════════════════════════════════════════════════════
 *  1. 1 finger on atom  + immediate move → drag atom      [NodeEditor]
 *  2. 1 finger on atom  + hold 2s        → context menu   [NodeEditor]
 *  3. 1 finger on wire  + hold 2s        → context menu   [NodeEditor]
 *  4. 1 finger on bg    + immediate move → lasso select   [NodeEditor]
 *  5. 1 finger on bg    + hold 2s        → context menu   [NodeEditor]
 *  6. 2 fingers + move                     → PAN canvas    [THIS CLASS]
 *  7. 2 fingers + pinch                    → ZOOM canvas   [THIS CLASS]
 *  >2 fingers                             → IGNORE         [THIS CLASS]
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * TOUCH STATE MACHINE
 * ═══════════════════════════════════════════════════════════════════════════
 *  IDLE        ──(2nd finger down)──>  TWO_FINGER
 *  TWO_FINGER  ──(either finger up)──>  IDLE  (finalize, fire callbacks)
 *  TWO_FINGER  ──(3rd+ finger down)──>  REJECTED
 *  REJECTED    ──(fingerCount < 3)──>  IDLE
 *  1-finger touches NEVER change state — they pass through to children.
 * ═══════════════════════════════════════════════════════════════════════════
 */
class ViewportManager {

    // ─── Touch state enum ───────────────────────────────────────────────
    private static inline var STATE_IDLE:Int       = 0;
    private static inline var STATE_TWO_FINGER:Int = 1;
    private static inline var STATE_REJECTED:Int   = 2;  // >2 fingers

    // ─── References ─────────────────────────────────────────────────────
    private var _canvas:Sprite;
    private var _hitLayer:Sprite;
    private var _target:Sprite;

    // ─── Touch state ────────────────────────────────────────────────────
    private var _touchState:Int = STATE_IDLE;
    private var _activeTouches:Map<Int, TouchData> = new Map();
    private var _hasPendingTransform:Bool = false;

    // ─── Touch pan tracking ─────────────────────────────────────────────
    private var _panLastCenter:Point = null;

    // ─── Touch zoom tracking ────────────────────────────────────────────
    private var _pinchStartDist:Float = 0;
    private var _pinchLastDist:Float = 0;
    private var _pinchStartScale:Float = 1.0;
    private var _touchZoomActive:Bool = false;  // track if pinch zoom happened

    // ─── Mouse pan tracking (desktop middle-button) ─────────────────────
    private var _mousePanning:Bool = false;
    private var _mousePanLastX:Float = 0;
    private var _mousePanLastY:Float = 0;

    // ─── Zoom constraints ───────────────────────────────────────────────
    private var _minScale:Float = 0.15;
    private var _maxScale:Float = 5.0;

    // ─── Pan constraints ────────────────────────────────────────────────
    private var _panBounds:Rectangle = null;

    // ─── Callbacks (assigned by NodeEditor) ─────────────────────────────
    public var onZoomStart:Void->Void = null;
    public var onZoomEnd:Void->Void = null;
    public var onTransformEnd:Void->Void = null;
    /**
     * Fired when VM transitions IDLE → TWO_FINGER.
     * NodeEditor uses this to cancel any in-progress 1-finger gesture
     * (lasso / long-press) so it doesn't conflict with pan/zoom.
     */
    public var onViewportGesturingStart:Void->Void = null;


    public function new(canvas:Sprite, hitLayer:Sprite) {
        _canvas = canvas;
        _hitLayer = hitLayer;
        _target = hitLayer;

        // Touch listeners
        _target.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
        _target.addEventListener(TouchEvent.TOUCH_MOVE,  onTouchMove);
        _target.addEventListener(TouchEvent.TOUCH_END,   onTouchEnd);
        _target.addEventListener(Event.ENTER_FRAME,      onEnterFrame);
    }


    public function dispose():Void {
        if (_target != null) {
            _target.removeEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
            _target.removeEventListener(TouchEvent.TOUCH_MOVE,  onTouchMove);
            _target.removeEventListener(TouchEvent.TOUCH_END,   onTouchEnd);
            _target.removeEventListener(Event.ENTER_FRAME,      onEnterFrame);
        }
        _activeTouches = null;
        _canvas = null;
        _hitLayer = null;
        _target = null;
        onZoomStart = null;
        onZoomEnd = null;
        onTransformEnd = null;
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  TOUCH EVENT HANDLERS (Android — 2-finger only)
    // ═══════════════════════════════════════════════════════════════════════

    private function onTouchBegin(e:TouchEvent):Void {
        // Always record the touch
        _activeTouches.set(e.touchPointID, {
            startX: e.localX,
            startY: e.localY,
            lastX:  e.localX,
            lastY:  e.localY
        });

        var count:Int = getTouchCount();

        switch (_touchState) {
            case STATE_IDLE:
                if (count == 2) {
                    _touchState = STATE_TWO_FINGER;
                    _panLastCenter = getTouchCenter();
                    _pinchStartDist = getTouchDistance();
                    _pinchLastDist  = _pinchStartDist;
                    _pinchStartScale = _canvas.scaleX;
                    _touchZoomActive = false;

                    // Notify NodeEditor to cancel any 1-finger gesture
                    if (onViewportGesturingStart != null) onViewportGesturingStart();

                    // Block 1-finger handling in NodeEditor while we're active
                    e.stopImmediatePropagation();
                }
                // count == 1: do NOT stopPropagation — let NodeEditor handle lasso/drag

            case STATE_TWO_FINGER:
                if (count > 2) {
                    _touchState = STATE_REJECTED;
                }
                e.stopImmediatePropagation();

            case STATE_REJECTED:
                e.stopImmediatePropagation();
                if (count < 3) {
                    resetTouchState();
                }
        }
    }


    private function onTouchMove(e:TouchEvent):Void {
        var td:Null<TouchData> = _activeTouches.get(e.touchPointID);
        if (td == null) return;

        td.lastX = e.localX;
        td.lastY = e.localY;

        if (_touchState == STATE_TWO_FINGER) {
            _hasPendingTransform = true;
            e.stopImmediatePropagation();
        }
        // IDLE / REJECTED: don't block — let NodeEditor handle 1-finger moves
    }


    private function onTouchEnd(e:TouchEvent):Void {
        _activeTouches.remove(e.touchPointID);
        var count:Int = getTouchCount();

        switch (_touchState) {
            case STATE_TWO_FINGER:
                if (count < 2) {
                    // Flush any pending transform
                    _hasPendingTransform = false;
                    applyTouchTransform();

                    // Fire callbacks
                    if (_touchZoomActive && onZoomEnd != null) {
                        onZoomEnd();
                    }
                    if (onTransformEnd != null) {
                        onTransformEnd();
                    }

                    resetTouchState();
                }
                e.stopImmediatePropagation();

            case STATE_REJECTED:
                e.stopImmediatePropagation();
                if (count < 3) {
                    resetTouchState();
                }

            case STATE_IDLE:
                // 1-finger released — nothing for us
        }
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  ENTER_FRAME — throttled touch transform
    // ═══════════════════════════════════════════════════════════════════════

    private function onEnterFrame(e:Event):Void {
        if (_hasPendingTransform && _touchState == STATE_TWO_FINGER) {
            _hasPendingTransform = false;
            applyTouchTransform();
        }
    }


    private function applyTouchTransform():Void {
        if (_touchState != STATE_TWO_FINGER) return;
        if (getTouchCount() < 2) return;

        var center:Point = getTouchCenter();

        // ── PAN: move canvas by center-of-two-fingers delta ──
        if (_panLastCenter != null) {
            var dx:Float = center.x - _panLastCenter.x;
            var dy:Float = center.y - _panLastCenter.y;
            _canvas.x += dx;
            _canvas.y += dy;
            applyPanBounds();
        }
        _panLastCenter = center;

        // ── ZOOM: scale relative to pinch center ──
        var dist:Float = getTouchDistance();
        if (dist < 1.0) dist = 1.0;

        if (_pinchLastDist > 0) {
            var ratio:Float = dist / _pinchLastDist;
            var newScale:Float = _canvas.scaleX * ratio;
            newScale = clamp(newScale, _minScale, _maxScale);

            // Only fire onZoomStart once, when zoom first deviates
            if (!_touchZoomActive && Math.abs(ratio - 1.0) > 0.005) {
                _touchZoomActive = true;
                if (onZoomStart != null) onZoomStart();
            }

            // Pivot: keep the point under pinch center fixed
            var localPivotX:Float = (center.x - _canvas.x) / _canvas.scaleX;
            var localPivotY:Float = (center.y - _canvas.y) / _canvas.scaleY;

            _canvas.scaleX = newScale;
            _canvas.scaleY = newScale;

            _canvas.x = center.x - localPivotX * newScale;
            _canvas.y = center.y - localPivotY * newScale;
        }

        _pinchLastDist = dist;
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  MOUSE API — desktop (middle-button pan + scroll-wheel zoom)
    //  Called by NodeEditor from MouseEvent handlers.
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * Begin mouse-based pan (middle mouse button down).
     */
    public function handlePanStart(stageX:Float, stageY:Float):Void {
        _mousePanning = true;
        _mousePanLastX = stageX;
        _mousePanLastY = stageY;
    }


    /**
     * Continue mouse-based pan (middle mouse button drag).
     */
    public function handlePanMove(stageX:Float, stageY:Float):Void {
        if (!_mousePanning) return;

        var dx:Float = stageX - _mousePanLastX;
        var dy:Float = stageY - _mousePanLastY;
        _canvas.x += dx;
        _canvas.y += dy;
        applyPanBounds();

        _mousePanLastX = stageX;
        _mousePanLastY = stageY;
    }


    /**
     * End mouse-based pan (middle mouse button up).
     */
    public function handlePanEnd():Void {
        if (_mousePanning) {
            _mousePanning = false;
            if (onTransformEnd != null) onTransformEnd();
        }
    }


    /**
     * Returns true if mouse-based panning is active (desktop middle-button).
     */
    public function isPanning():Bool {
        return _mousePanning;
    }


    /**
     * Handle scroll-wheel zoom (desktop).
     * @param delta  Mouse wheel delta (typically +/- 3 on most platforms)
     * @param stageX Mouse X in stage coordinates (pivot point)
     * @param stageY Mouse Y in stage coordinates (pivot point)
     * @param target DisplayObject for coordinate conversion (unused but kept for API compat)
     */
    public function handleZoom(delta:Float, stageX:Float, stageY:Float, target:DisplayObject):Void {
        if (delta == 0) return;

        // Convert delta to a scale factor.
        // delta > 0 = scroll up = zoom in; delta < 0 = scroll down = zoom out
        var zoomFactor:Float = 1.0 + (delta * 0.004);
        var newScale:Float = _canvas.scaleX * zoomFactor;
        newScale = clamp(newScale, _minScale, _maxScale);

        if (onZoomStart != null) onZoomStart();

        // Pivot zoom around (stageX, stageY)
        var localPivotX:Float = (stageX - _canvas.x) / _canvas.scaleX;
        var localPivotY:Float = (stageY - _canvas.y) / _canvas.scaleY;

        _canvas.scaleX = newScale;
        _canvas.scaleY = newScale;

        _canvas.x = stageX - localPivotX * newScale;
        _canvas.y = stageY - localPivotY * newScale;

        if (onZoomEnd != null) onZoomEnd();
        if (onTransformEnd != null) onTransformEnd();
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  STATE API — get/set viewport position & zoom
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * Returns current viewport state: canvas position and zoom level.
     */
    public function getViewState():{x:Float, y:Float, zoom:Float} {
        return {
            x: _canvas.x,
            y: _canvas.y,
            zoom: _canvas.scaleX
        };
    }


    /**
     * Sets viewport position and zoom atomically.
     */
    public function setViewState(state:{x:Float, y:Float, zoom:Float}):Void {
        _canvas.x = state.x;
        _canvas.y = state.y;
        _canvas.scaleX = state.zoom;
        _canvas.scaleY = state.zoom;
    }


    /**
     * Update visibility of nodes based on current viewport bounds.
     * Hides nodes that are completely outside the visible area.
     *
     * @param nodes  Iterator of NodeView objects
     * @param viewW  Viewport width in pixels
     * @param viewH  Viewport height in pixels
     */
    public function updateVisibility<T:DisplayObject>(nodes:Iterator<T>, viewW:Float, viewH:Float):Void {
        var scale:Float = _canvas.scaleX;
        if (scale <= 0) scale = 1.0;

        // Visible area in canvas-local coordinates
        var visLeft:Float   = -_canvas.x / scale;
        var visTop:Float    = -_canvas.y / scale;
        var visRight:Float  = visLeft + viewW / scale;
        var visBottom:Float = visTop + viewH / scale;

        // Expand by a margin (1 node width ~150px in canvas space)
        var margin:Float = 200 / scale;
        visLeft   -= margin;
        visTop    -= margin;
        visRight  += margin;
        visBottom += margin;

        for (node in nodes) {
            if (node == null) continue;
            // Check if node center is within visible area
            var cx:Float = node.x + node.width / 2;
            var cy:Float = node.y + node.height / 2;
            node.visible = (cx >= visLeft && cx <= visRight && cy >= visTop && cy <= visBottom);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TOUCH STATE QUERY — for NodeEditor to check before lasso/drag
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * Returns true if a 2-finger touch gesture is currently active.
     * NodeEditor should check this to avoid conflicting with pan/zoom.
     */
    public function isGesturing():Bool {
        return _touchState == STATE_TWO_FINGER;
    }


    /**
     * Returns true if the viewport is handling touches (2-finger or rejected).
     * NodeEditor should skip lasso/atom-drag when this is true.
     */
    public function isViewportActive():Bool {
        return _touchState == STATE_TWO_FINGER || _touchState == STATE_REJECTED;
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  PUBLIC CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    public function setZoomLimits(minS:Float, maxS:Float):Void {
        _minScale = minS;
        _maxScale = maxS;
    }

    public function setPanBounds(r:Rectangle):Void {
        _panBounds = r;
    }


    // ═══════════════════════════════════════════════════════════════════════
    //  INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    private function getTouchCount():Int {
        var n:Int = 0;
        for (_ in _activeTouches) n++;
        return n;
    }


    private function getTouchCenter():Point {
        var sumX:Float = 0, sumY:Float = 0, n:Int = 0;
        for (td in _activeTouches) {
            sumX += td.lastX;
            sumY += td.lastY;
            n++;
        }
        if (n == 0) return new Point(0, 0);
        return new Point(sumX / n, sumY / n);
    }


    private function getTouchDistance():Float {
        var pts:Array<{x:Float, y:Float}> = [];
        for (td in _activeTouches) {
            pts.push({x: td.lastX, y: td.lastY});
            if (pts.length >= 2) break;  // only need 2
        }
        if (pts.length < 2) return 0;
        var dx:Float = pts[1].x - pts[0].x;
        var dy:Float = pts[1].y - pts[0].y;
        return Math.sqrt(dx * dx + dy * dy);
    }


    private function resetTouchState():Void {
        _touchState = STATE_IDLE;
        _panLastCenter = null;
        _pinchStartDist = 0;
        _pinchLastDist = 0;
        _pinchStartScale = _canvas != null ? _canvas.scaleX : 1.0;
        _touchZoomActive = false;
        _hasPendingTransform = false;
    }


    private function applyPanBounds():Void {
        if (_panBounds == null) return;
        _canvas.x = clamp(_canvas.x, _panBounds.x, _panBounds.x + _panBounds.width);
        _canvas.y = clamp(_canvas.y, _panBounds.y, _panBounds.y + _panBounds.height);
    }


    private inline function clamp(v:Float, min:Float, max:Float):Float {
        if (v < min) return min;
        if (v > max) return max;
        return v;
    }
}


/**
 * Per-touch tracking data, stored in a Map keyed by touchPointID.
 */
private typedef TouchData = {
    startX:Float,
    startY:Float,
    lastX:Float,
    lastY:Float
};
