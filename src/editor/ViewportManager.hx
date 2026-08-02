package editor;

import flash.events.MouseEvent;
import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.events.TouchEvent;
import editor.NodeView;

/**
* VIEWPORT MANAGER v1.5 (Async Transform End + Zero-Allocation Pinch Math)
* Handles Pan, Zoom, Visibility culling, and Touch interactions.
*
* v1.5 Changes:
* - Deferred onTransformEnd callback via haxe.Timer.delay to decouple
*   heavy UI operations (rebuildAll, updateVisibility) from the touch
*   event handler. This allows the browser to present the hardware-scaled
*   canvas immediately after the gesture ends, making zoom feel responsive.
* - Replaced array allocation in calculatePinchDistance() and getPinchCenter()
*   with iterator-based traversal. Eliminates GC pressure on low-end Android
*   devices where array allocation in hot paths causes micro-stutters.
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
* └─────────────────────────────────────────────────────────────────────────┘
*/
class ViewportManager
{
	// =========================================================================
	// DEPENDENCIES
	// =========================================================================
	private var _canvas:Sprite;
	private var _hitLayer:Sprite;
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
	private static inline var VISIBILITY_THROTTLE:Float = 0.05;
	private var _hasPendingTransform:Bool = false;
	
	// =========================================================================
	// ZOOM CALLBACKS
	// =========================================================================
	public var onZoomStart:Void -> Void;
	public var onZoomEnd:Void -> Void;
	
	// =========================================================================
	// TRANSFORM CALLBACKS
	// =========================================================================
	public var onTransformEnd:Void -> Void;
	
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
	private var _wasZooming:Bool = false;
	private var _pinchZooming:Bool = false;
	private var _pinchStartDistance:Float = 0;
	private var _pinchStartScale:Float = 1.0;
	private var _pinchCenterX:Float = 0;
	private var _pinchCenterY:Float = 0;

	// =========================================================================
	// REUSABLE POINTS
	// =========================================================================
	private var _tempPoint1:openfl.geom.Point = new openfl.geom.Point();
	private var _tempPoint2:openfl.geom.Point = new openfl.geom.Point();
	
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
	public function new(canvas:Sprite, ?hitLayer:Sprite)
	{
		_canvas = canvas;
		_hitLayer = hitLayer;
		_theme = EditorTheme.getInstance();
		_activeTouches = new Map();
		
		// Listen to the Glass Pane (Hit Layer)
		// If hitLayer is null (fallback), listen to canvas, but canvas.mouseEnabled is false now, 
		// so we really need hitLayer.
		var target = _hitLayer != null ? _hitLayer : _canvas;
		
		target.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
		target.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
		target.addEventListener(TouchEvent.TOUCH_END, onTouchEnd);
		
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
		
		// Prevent panning outside the canvas
		//clampCanvasBounds();
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
	// ZOOM OPERATIONS
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
		
		_tempPoint1.x = stageX;
		_tempPoint1.y = stageY;
		var mouseLocal:openfl.geom.Point = _canvas.globalToLocal(_tempPoint1);
		
		var oldScale:Float = _canvas.scaleX;
		var newScale:Float = oldScale * zoomFactor;
		
		if (newScale < _zoomMin) newScale = _zoomMin;
		if (newScale > _zoomMax) newScale = _zoomMax;
		if (newScale == oldScale) return;
		
		_isZooming = true;
		EditorState.setIsZooming(true);
		
		if (_zoomEndTimer != null)
		{
			_zoomEndTimer.stop();
			_zoomEndTimer = null;
		}
		
		_zoomEndTimer = haxe.Timer.delay(() -> {
			_isZooming = false;
			EditorState.setIsZooming(false);
			_processPendingActivations();
			
			core.logic.Impulsys.quickEmit(core.logic.EventType.REDRAW_WIRES);
		}, 15);
		
		_canvas.scaleX = newScale;
		_canvas.scaleY = newScale;
		
		_tempPoint2.x = stageX - (mouseLocal.x * newScale);
		_tempPoint2.y = stageY - (mouseLocal.y * newScale);
		var targetGlobalPos:openfl.geom.Point = _tempPoint2;
		
		var targetLocalPos:Point = container.globalToLocal(targetGlobalPos);
		
		_canvas.x = targetLocalPos.x;
		_canvas.y = targetLocalPos.y;
		
		// Clamp to bounds ===
		//clampZoomToBounds();
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
	
	/**
	 * Clamps canvas position to prevent panning outside the canvas bounds.
	 * Takes current zoom scale into account.
	 */
	private function clampCanvasBounds():Void
	{
		var stage = _canvas.stage;
		if (stage == null) return;

		var stageW = stage.stageWidth;
		var stageH = stage.stageHeight;
		
		// Effective canvas dimensions considering current zoom
		var effectiveWidth = 10000 * _canvas.scaleX;
		var effectiveHeight = 10000 * _canvas.scaleY;

		// Clamp X axis
		if (effectiveWidth > stageW)
		{
			// Canvas wider than stage: clamp to [-(effectiveWidth - stageW), 0]
			if (_canvas.x > 0) _canvas.x = 0;
			if (_canvas.x < -(effectiveWidth - stageW)) _canvas.x = -(effectiveWidth - stageW);
		}
		else
		{
			// Canvas narrower than stage: allow movement but keep within [0, stageW - effectiveWidth]
			var maxOffsetX = stageW - effectiveWidth;
			if (_canvas.x < 0) _canvas.x = 0;
			if (_canvas.x > maxOffsetX) _canvas.x = maxOffsetX;
		}

		// Clamp Y axis
		if (effectiveHeight > stageH)
		{
			// Canvas taller than stage: clamp to [-(effectiveHeight - stageH), 0]
			if (_canvas.y > 0) _canvas.y = 0;
			if (_canvas.y < -(effectiveHeight - stageH)) _canvas.y = -(effectiveHeight - stageH);
		}
		else
		{
			// Canvas shorter than stage: allow movement but keep within [0, stageH - effectiveHeight]
			var maxOffsetY = stageH - effectiveHeight;
			if (_canvas.y < 0) _canvas.y = 0;
			if (_canvas.y > maxOffsetY) _canvas.y = maxOffsetY;
		}
	}
	
	/**
	* Clamp zoom and position to prevent canvas from going out of bounds.
	* Adds a margin to prevent the canvas from snapping tightly to screen edges during zoom.
	*/
	private function clampZoomToBounds():Void
	{
		if (_canvas == null || _canvas.stage == null) return;
		
		var stageW = _canvas.stage.stageWidth;
		var stageH = _canvas.stage.stageHeight;
		
		// Canvas dimensions in stage coordinates
		var canvasW = 10000 * _canvas.scaleX;
		var canvasH = 10000 * _canvas.scaleY;
		
		// Add margin to prevent canvas from snapping tightly to screen edges during zoom
		var margin:Float = 100.0;
		
		// Clamp position: prevent canvas from going beyond stage edges + margin
		if (canvasW < stageW)
		{
			// Canvas is smaller than stage - center it
			_canvas.x = (stageW - canvasW) / 2;
		}
		else
		{
			// Canvas is larger than stage - clamp to edges with margin
			if (_canvas.x > margin) _canvas.x = margin;
			if (_canvas.x < stageW - canvasW - margin) _canvas.x = stageW - canvasW - margin;
		}
		
		if (canvasH < stageH)
		{
			// Canvas is smaller than stage - center it
			_canvas.y = (stageH - canvasH) / 2;
		}
		else
		{
			// Canvas is larger than stage - clamp to edges with margin
			if (_canvas.y > margin) _canvas.y = margin;
			if (_canvas.y < stageH - canvasH - margin) _canvas.y = stageH - canvasH - margin;
		}
	}
	
	// =========================================================================
	// VISIBILITY CULLING
	// =========================================================================
	/**
	* Update node visibility based on viewport bounds.
	* 
	* During zoom: only hide nodes, defer activation until zoom ends.
	* Throttled to 20 FPS max during rapid zoom.
	*/
	public function updateVisibility(nodes:Iterator<NodeView>, stageWidth:Float, stageHeight:Float):Void
	{
		var now = haxe.Timer.stamp();
		if (_isZooming && (now - _lastVisibilityUpdate) < VISIBILITY_THROTTLE)
		{
			return;
		}
		_lastVisibilityUpdate = now;
		
		var margin:Float = 150;
		
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
			var isVisible = (view.x + size.width > viewLeft && view.x < viewRight &&
							 view.y + size.height > viewTop  && view.y < viewBottom);
			
			if (isVisible) visibleCount++;
			
			if (view.visible != isVisible)
			{
				if (_isZooming)
				{
					if (isVisible && !wasVisible)
					{
						if (_pendingActivations.indexOf(view) == -1)
						{
							_pendingActivations.push(view);
						}
						view.visible = true;
						newlyVisible++;
					}
					else if (!isVisible && wasVisible)
					{
						view.visible = false;
						newlyHidden++;
					}
				}
				else
				{
					view.visible = isVisible;
					if (isVisible && !wasVisible) newlyVisible++;
					else if (!isVisible && wasVisible) newlyHidden++;
				}
			}
		}
		
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
		
		var batchSize = 5;
		var processed = 0;
		
		for (view in _pendingActivations)
		{
			if (view != null && view.visible)
			{
				view.visible = view.visible;
				processed++;
				
				if (processed >= batchSize) break;
			}
		}
		
		_pendingActivations = _pendingActivations.slice(batchSize);
		
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
		/**
		* Always track all touches for potential pinch gestures,
		* even if the touch is not on the background (e.g., on a NodeView).
		* The isBackgroundTouch check only prevents starting a PAN,
		* not tracking the touch for potential PINCH.
		*/
		var isFirstTouch = !_activeTouches.exists(e.touchPointID);
		if (isFirstTouch)
		{
			_touchCount++;
		}
		_activeTouches.set(e.touchPointID, {x: e.stageX, y: e.stageY});
		
		if (isFirstTouch && _touchCount == 1 && !isBackgroundTouch(e.target))
		{
			return;
		}

		updateTouchState();
	}

	private function onTouchMove(e:TouchEvent):Void
	{
		if (_activeTouches.exists(e.touchPointID))
		{
			_activeTouches.set(e.touchPointID, {x: e.stageX, y: e.stageY});
		}
		
		_hasPendingTransform = true;
	}

	private function onTouchEnd(e:TouchEvent):Void
	{
		if (_activeTouches.exists(e.touchPointID))
		{
			_touchCount--;
		}
		_activeTouches.remove(e.touchPointID);
		
		_hasPendingTransform = true;
		updateTouchState();
		
		/**
		* Defer onTransformEnd to the next frame cycle.
		* Heavy operations like updateVisibility() and rebuildAll() traverse
		* the entire node graph and call localToGlobal() for each wire endpoint.
		* On low-end Android devices this blocks the UI thread for seconds.
		* By deferring, the browser presents the hardware-scaled canvas
		* immediately after the gesture ends, making zoom feel responsive.
		* The wire redraw happens asynchronously after the UI has settled.
		*/
		if (onTransformEnd != null)
		{
			var callback = onTransformEnd;
			haxe.Timer.delay(function() {
				if (callback != null) callback();
			}, 16);
		}
	}

	// =========================================================================
	// TOUCH THROTTLING
	// =========================================================================
	private function onEnterFrame(e:openfl.events.Event):Void
	{
		if (_hasPendingTransform)
		{
			updateTouchState();
			_hasPendingTransform = false;
		}
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
				
				// Prevent panning outside the canvas
				//clampCanvasBounds();
			}
		}
		else if (_touchCount == 2)
		{
			if (!_pinchZooming)
			{
				var initialDistance = calculatePinchDistance();
				
				if (initialDistance < 15)
				{
					return;
				}
				
				_pinchZooming = true;
				_touchPanning = false;
				EditorState.setIsPanning(false);
				EditorState.setIsZooming(true);
				_wasZooming = true;
				
				if (onZoomStart != null) onZoomStart();
				
				_pinchStartDistance = initialDistance;
				_pinchStartScale = _canvas.scaleX;
				var center = getPinchCenter();
				_pinchCenterX = center.x;
				_pinchCenterY = center.y;
				
				//trace('Pinch started: distance=${_pinchStartDistance}, scale=${_pinchStartScale}, center=(${_pinchCenterX}, ${_pinchCenterY})');
			}
			else
			{
				var currentDistance = calculatePinchDistance();
				var scaleRatio = currentDistance / _pinchStartDistance;
				var newScale = _pinchStartScale * scaleRatio;
				
				if (newScale < _zoomMin) newScale = _zoomMin;
				if (newScale > _zoomMax) newScale = _zoomMax;
				
				_tempPoint1.x = _pinchCenterX;
				_tempPoint1.y = _pinchCenterY;
				var mouseLocal:openfl.geom.Point = _canvas.globalToLocal(_tempPoint1);
				
				_canvas.scaleX = newScale;
				_canvas.scaleY = newScale;
				
				_tempPoint2.x = _pinchCenterX - (mouseLocal.x * newScale);
				_tempPoint2.y = _pinchCenterY - (mouseLocal.y * newScale);
				var targetGlobalPos:openfl.geom.Point = _tempPoint2;
				
				var container = _canvas.parent;
				if (container != null)
				{
					var targetLocalPos:Point = container.globalToLocal(targetGlobalPos);
					_canvas.x = targetLocalPos.x;
					_canvas.y = targetLocalPos.y;
				}
				// Clamp to bounds ===
				//clampZoomToBounds();
			}
		}
		else if (_touchCount == 0)
		{
			_touchPanning = false;
			_pinchZooming = false;
			_isZooming = false;
			EditorState.setIsPanning(false);
			EditorState.setIsZooming(false);
			
			if (_wasZooming)
			{
				if (onZoomEnd != null) onZoomEnd();
				core.logic.Impulsys.quickEmit(core.logic.EventType.REDRAW_WIRES);
				_wasZooming = false;
			}
		}
		else if (_touchCount == 1 && _pinchZooming)
		{
			_pinchZooming = false;
			_touchPanning = true;
			_isZooming = false;
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
		if (_hitLayer != null)
		{
			return (target == _hitLayer || target == _canvas);
		}
		
		// background only where _canvas is drawn.
		return (target == _canvas);
	}

	private function getFirstTouch():{x:Float, y:Float}
	{
		for (touch in _activeTouches)
		{
			return touch;
		}
		return {x: 0, y: 0};
	}

	/**
	* Calculate distance between two active touch points.
	* Uses iterator-based traversal instead of array allocation to avoid
	* GC pressure on low-end Android devices where array allocation in
	* hot paths (called every frame during pinch) causes micro-stutters.
	*/
	private function calculatePinchDistance():Float
	{
		var first:Null<{x:Float, y:Float}> = null;
		var second:Null<{x:Float, y:Float}> = null;
		
		for (t in _activeTouches)
		{
			if (first == null) first = t;
			else if (second == null) second = t;
			else break;
		}
		
		if (first != null && second != null)
		{
			var dx = second.x - first.x;
			var dy = second.y - first.y;
			return Math.sqrt(dx * dx + dy * dy);
		}
		
		return 0;
	}

	/**
	* Calculate center point between two active touch points.
	* Uses iterator-based traversal instead of array allocation.
	*/
	private function getPinchCenter():{x:Float, y:Float}
	{
		var first:Null<{x:Float, y:Float}> = null;
		var second:Null<{x:Float, y:Float}> = null;
		
		for (t in _activeTouches)
		{
			if (first == null) first = t;
			else if (second == null) second = t;
			else break;
		}
		
		if (first != null && second != null)
		{
			return {
				x: (first.x + second.x) / 2,
				y: (first.y + second.y) / 2
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
		_canvas.removeEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
		
		_activeTouches = null;
		_pendingActivations = null;
		
		if (_zoomEndTimer != null)
		{
			_zoomEndTimer.stop();
			_zoomEndTimer = null;
		}
	}
}