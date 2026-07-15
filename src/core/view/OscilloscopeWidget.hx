package core.view;
import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Contact;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import library.electro.OscilloscopeAtom;
/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     OSCILLOSCOPE WIDGET v2.5                              ║
* ║                     (Real-Time Waveform Visualization)                    ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Visual component (Face) for OscilloscopeAtom.                            ║
* ║  Responsible for real-time waveform rendering, support for various        ║
* ║  geometries (linear, square, polar) and "History" mode (Ring Buffer)      ║
* ║  for creating phosphor afterglow effect.                                  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        RENDERING PIPELINE                                 ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  [Upstream Driver] ──(Array Ref)──► [OscilloscopeAtom]              │  ║
* ║  │         │                               │                           │  ║
* ║  │         │                               ▼                           │  ║
* ║  │         │                  Impulsys: FRAME_READY                    │  ║
* ║  │         │                               │                           │  ║
* ║  │         ▼                               ▼                           │  ║
* ║  │  [OscilloscopeWidget] ◄───────── onFrameReady()                     │  ║
* ║  │         │                                                           │  ║
* ║  │         ├─► _hasNewFrame = true (Dirty Flag)                        │  ║
* ║  │         │                                                           │  ║
* ║  │         ▼                                                           │  ║
* ║  │  [OpenFL ENTER_FRAME] ──► redrawFromAtom()                          │  ║
* ║  │         │                                                           │  ║
* ║  │         ├─► Atomic Snapshot (Copy Array to _renderBuffer)           │  ║
* ║  │         │                                                           │  ║
* ║  │         ├─► [History Mode?] ──Yes──► Ring Buffer Layer (Sprite)     │  ║
* ║  │         │               │                                           │  ║
* ║  │         │               No                                          │  ║
* ║  │         │               ▼                                           │  ║
* ║  │         └────────► [Normal Mode] ──► Canvas (Sprite)                │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     HISTORY MODE RING BUFFER                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Layer 0: [ Wave N-4 ]  ◄── Oldest (will be overwritten next)       │  ║
* ║  │  Layer 1: [ Wave N-3 ]                                              │  ║
* ║  │  Layer 2: [ Wave N-2 ]                                              │  ║
* ║  │  Layer 3: [ Wave N-1 ]                                              │  ║
* ║  │  Layer 4: [ Wave N   ]  ◄── Newest (Current write index)            │  ║
* ║  │                                                                     │  ║
* ║  │  _currentLayer points to the NEXT layer to be overwritten.          │  ║
* ║  │  This creates a visual "phosphor decay" effect without              │  ║
* ║  │  manually changing alpha or using shaders.                          │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class OscilloscopeWidget extends DeviceView
{
// =========================================================================
// CONFIGURATION (External parameters and colors)
// =========================================================================
	/** Base widget width (for rectangular shape). */
	public var widgetWidth:Float = 300;
	/** Base widget height (for rectangular shape). */
	public var widgetHeight:Float = 150;
	/** Waveform line color (white). */
	public var colorLine:Int = 0xFFFFFF;
	/** Widget background color (dark blue/black). */
	public var colorBg:Int = 0x0a0a12;
	/** Grid color (dark green, semi-transparent). */
	public var colorGrid:Int = 0x1a2a1a;
// =========================================================================
// HISTORY MODE (History Mode / Ring Buffer)
// =========================================================================
	/** Number of layers in the ring buffer (history depth). */
	private static inline var HISTORY_LAYERS:Int = 5;
	/** History mode flag. Disabled by default, can be activated. */
	private var _historyMode:Bool = false;
	/** Container (Sprite) holding all history layers. Allows moving them together. */
	private var _historyContainer:Sprite;
	/** Array of sprites, each representing one history frame. */
	private var _historyLayers:Array<Sprite>;
	/** Current write position in the ring buffer (index from 0 to HISTORY_LAYERS-1). */
	private var _currentLayer:Int = 0;
	/** Counter of processed frames in history mode (used for debugging and logging). */
	private var _historyFrameCount:Int = 0;
// =========================================================================
// NORMAL MODE COMPONENTS
// =========================================================================
	/** Main canvas for waveform rendering in normal mode (single frame). */
	private var _canvas:Sprite;
	/** Sprite for coordinate grid rendering. */
	private var _grid:Sprite;
	/** Mask (Shape) that clips rendering to widget bounds or circle shape. */
	private var _mask:Shape;
	/** Reference to the linked oscilloscope atom for reading data and parameters. */
	private var _oscAtom:OscilloscopeAtom;
// =========================================================================
// FRAME SYNCHRONIZATION
// =========================================================================
	/**
	* "Dirty" frame flag.
	* Set to true when OSCILLOSCOPE_FRAME_READY event is received.
	* Reset to false after rendering in onEnterFrame.
	*/
	private var _hasNewFrame:Bool = false;
	/** Rendering lock flag (protection against recursive calls or races). */
	private var _isRendering:Bool = false;
	/**
	* Local buffer for atomic data snapshot.
	* Copies data from the atom to avoid "tearing" if the upstream driver
	* updates the array during rendering.
	*/
	private var _renderBuffer:Array<Float>;
// =========================================================================
// CONSTRUCTOR
// =========================================================================
	/**
	* Creates an oscilloscope widget and links it to the atom.
	*
	* @param atom Base atom (can be OscilloscopeAtom or Assembly containing it).
	* @param contactName Input contact name (default: "in").
	*/
	public function new(atom:Atom, contactName:String = "in")
	{
		super(atom);
// --- Resolve OscilloscopeAtom reference ---
// If the oscilloscope itself is passed, use it.
		if (Std.isOfType(atom, OscilloscopeAtom))
		{
			_oscAtom = cast(atom, OscilloscopeAtom);
		}
// If an Assembly is passed, search for the oscilloscope among its internal atoms.
		else if (Std.isOfType(atom, Assembly))
		{
			var asm = cast(atom, Assembly);
			for (internalAtom in asm.internalAtoms)
			{
				if (Std.isOfType(internalAtom, OscilloscopeAtom))
				{
					_oscAtom = cast(internalAtom, OscilloscopeAtom);
					break;
				}
			}
		}
// --- Initialize UI and subscriptions ---
		buildUI();
// Subscribe to global Impulsys events for instant response
// to shape changes and new data, bypassing the standard propagate cycle.
		Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
		Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
// Synchronize rendering with screen refresh rate (ENTER_FRAME).
		addEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
	}
// =========================================================================
// WIDGET SIZE
// =========================================================================
	/**
	* Returns current widget dimensions for the layout manager.
	* In history mode, height is multiplied by the number of layers.
	*/
	override public function getWidgetSize(): {width:Float, height:Float}
	{
		if (_historyMode)
		{
			return {width: widgetWidth, height: widgetHeight * HISTORY_LAYERS};
		}
		return {width: widgetWidth, height: widgetHeight};
	}
// =========================================================================
// UI CONSTRUCTION
// =========================================================================
	/**
	* Orchestrates creation of all visual components: background, grid, mask, and canvas.
	*/
	private function buildUI():Void
	{
		updateDimensions();
		drawBackground();
// Create and add the grid
		_grid = new Sprite();
		addChild(_grid);
// Create mask and apply it to the grid so grid lines don't exceed bounds
		_mask = new Shape();
		addChild(_mask);
		_grid.mask = _mask;
		drawGrid();
		drawMask();
// Initialize canvas depending on the selected mode
		if (_historyMode)
		{
			initHistoryLayers();
		}
		else {
			_canvas = new Sprite();
			addChild(_canvas);
			_canvas.mask = _mask; // Mask also applies to the waveform canvas
		}
	}
	/**
	* Initializes the ring buffer of sprites for history mode.
	* Each layer is offset on the Y axis so they don't visually overlap
	* (although in the current rendering logic they are drawn in the same place, just overwritten).
	* Note: In v2.5, layers are drawn on top of each other in the same place,
	* creating a superposition effect, but y = i * widgetHeight is used for
	* potential vertical stacking if needed in the future.
	*/
	private function initHistoryLayers():Void
	{
		_historyContainer = new Sprite();
		addChild(_historyContainer);
		_historyLayers = [];
		for (i in 0...HISTORY_LAYERS)
		{
			var layer = new Sprite();
			layer.y = i * widgetHeight; // Offset (in current rendering logic they overlap)
			_historyContainer.addChild(layer);
			_historyLayers.push(layer);
		}
		_currentLayer = 0;
		_historyFrameCount = 0;
	}
	/**
	* Updates base widget dimensions depending on the selected geometry (Shape).
	* Square and Circle require equal proportions (200x200).
	*/
	private function updateDimensions():Void
	{
		if (_oscAtom == null) return;
		var shape = _oscAtom.getDisplayShape();
		switch (shape)
		{
			case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR:
				widgetWidth = 200;
				widgetHeight = 200;
			default:
				widgetWidth = 300;
				widgetHeight = 150;
		}
	}
	/**
	* Draws the widget background and frame.
	* Uses drawCircle for circular shape, drawRoundRect for others.
	*/
	private function drawBackground():Void
	{
		var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
		graphics.clear();
		graphics.beginFill(colorBg);
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
			graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
		else
			graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
		graphics.endFill();
// Frame
		graphics.lineStyle(3, 0x333355);
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
			graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
		else
			graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
	}
	/**
	* Draws the coordinate grid.
	* For circle: concentric circles and crosshair.
	* For rectangle: vertical and horizontal lines with highlighted central axis.
	*/
	private function drawGrid():Void
	{
		var g = _grid.graphics;
		g.clear();
		g.lineStyle(1, colorGrid, 0.7);
		var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
		{
			var cx = widgetWidth / 2;
			var cy = widgetHeight / 2;
			var radius = widgetWidth / 2;
// Draw 5 concentric circles
			for (i in 1...6) g.drawCircle(cx, cy, radius * (i / 5.0));
// Draw crosshair (X and Y axes)
			g.moveTo(cx - radius, cy); g.lineTo(cx + radius, cy);
			g.moveTo(cx, cy - radius); g.lineTo(cx, cy + radius);
		}
		else {
// Vertical lines (10 divisions)
			var stepX = widgetWidth / 10;
			for (i in 0...11)
			{
				g.moveTo(i * stepX, 0);
				g.lineTo(i * stepX, widgetHeight);
			}
// Horizontal lines (6 divisions)
			var stepY = widgetHeight / 6;
			for (i in 0...7)
			{
				g.moveTo(0, i * stepY);
				g.lineTo(widgetWidth, i * stepY);
			}
// Central horizontal axis (zero line) — make it brighter
			g.lineStyle(1, colorGrid, 1.0);
			g.moveTo(0, widgetHeight / 2);
			g.lineTo(widgetWidth, widgetHeight / 2);
		}
	}
	/**
	* Creates a vector mask for canvas clipping.
	* This prevents the waveform line from exceeding widget bounds
	* or the circle during polar sweep.
	*/
	private function drawMask():Void
	{
		var g = _mask.graphics;
		g.clear();
		g.beginFill(0xFFFFFF); // Color doesn't matter, alpha (opacity) does
		if ((_oscAtom != null) && (_oscAtom.getDisplayShape() == OscilloscopeAtom.SHAPE_CIRCULAR))
		{
// Mask radius slightly smaller than background to hide boundary artifacts
			g.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2 - 2);
		}
		else {
// FIXED: Added +1 to width so the rightmost pixel of the waveform
// (at x = widgetWidth) is not clipped due to OpenFL rasterization specifics.
			g.drawRect(0, 0, widgetWidth + 1, widgetHeight);
		}
		g.endFill();
	}
// =========================================================================
// HISTORY MODE API (Public API for history mode control)
// =========================================================================
	/**
	* Enables or disables history mode.
	* Completely rebuilds UI when mode changes.
	*
	* @param enabled Enable flag.
	*/
	public function setHistoryMode(enabled:Bool):Void
	{
		if (_historyMode == enabled) return;
		_historyMode = enabled;
// Full UI rebuild for correct switching between Canvas and HistoryLayers
		removeChildren();
		buildUI();
		if (_oscAtom != null) syncFromAtom();
	}
	/** Returns current history mode status. */
	public function isHistoryMode():Bool return _historyMode;
	/** Returns the index of the current active layer in the ring buffer. */
	public function getCurrentLayer():Int return _currentLayer;
	/** Returns the total number of rendered frames in history mode. */
	public function getHistoryFrameCount():Int return _historyFrameCount;
// =========================================================================
// LIFECYCLE & EVENT HANDLERS
// =========================================================================
	/**
	* Called when the widget is activated. Synchronizes initial state.
	*/
	override private function onActivate():Void
	{
		syncFromAtom();
	}
	/**
	* Force synchronization of visual with current atom state.
	* Redraws background, grid, and the waveform.
	*/
	override private function syncFromAtom():Void
	{
		if (_oscAtom == null) return;
		updateDimensions();
		drawBackground();
		drawGrid();
		drawMask();
		if (_historyMode)
		{
// In history mode, wait for new frames via onFrameReady
		}
		else {
// In normal mode, draw immediately if data is available
			redrawFromAtom();
		}
	}
	/**
	* Reaction to input contact changes (e.g., zoom, timeScale).
	* Ignores the "in" contact (raw data) as it's handled via Impulsys.
	*/
	override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
	{
		if (isDisposed || _oscAtom == null) return;
		if (contact.name == "in") return; // Data is handled in onFrameReady
// When parameters change, redraw grid and waveform
		drawGrid();
		redrawFromAtom();
	}
	/**
	* OSCILLOSCOPE_FRAME_READY event handler.
	* Sets the _hasNewFrame flag so rendering happens in the next ENTER_FRAME.
	* This is critical for synchronizing with monitor refresh rate and preventing tearing.
	*/
	private function onFrameReady(impulse:Impulse):Void
	{
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
		_hasNewFrame = true;
	}
	/**
	* OSCILLOSCOPE_SHAPE_CHANGED event handler.
	* Instantly rebuilds UI when shape changes (e.g., from rectangle to circle)
	* from the Properties window, without needing to switch tabs.
	*/
	private function onShapeChanged(impulse:Impulse):Void
	{
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
		var newShape:Int = impulse.data.shape;
		switch (newShape)
		{
			case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR:
				widgetWidth = 200;
				widgetHeight = 200;
			default:
				widgetWidth = 300;
				widgetHeight = 150;
		}
// Full UI rebuild for new geometry
		removeChildren();
		buildUI();
	}
	/**
	* Main rendering loop, tied to screen refresh rate (ENTER_FRAME).
	* Checks the _hasNewFrame flag and triggers rendering if new data is available.
	*/
	private function onEnterFrame(e:openfl.events.Event):Void
	{
		if (_hasNewFrame && !_isRendering)
		{
			_hasNewFrame = false;
			redrawFromAtom();
		}
	}
// =========================================================================
// REDRAW LOGIC
// =========================================================================
	/**
	* Main rendering function.
	* Implements the "Atomic Snapshot" pattern: copies the data array from the atom
	* into a local _renderBuffer before starting rendering.
	* This guarantees that even if the upstream driver changes the array
	* in the middle of the rendering cycle, we work with a consistent snapshot.
	*/
	private function redrawFromAtom():Void
	{
		if (_oscAtom == null) return;
		var buffer = _oscAtom.getBuffer();
		if (buffer == null || buffer.length == 0) return;
		_isRendering = true;
// --- Atomic Snapshot ---
		var count = buffer.length;
// Reallocate local buffer only if size changed
		if (_renderBuffer == null || _renderBuffer.length != count)
		{
			_renderBuffer = new Array<Float>();
			for (i in 0...count) _renderBuffer.push(0.0);
		}
// Fast data copy
		for (i in 0...count)
		{
			_renderBuffer[i] = buffer[i];
		}
// Route to the appropriate rendering mode
		if (_historyMode)
		{
			redrawHistory(_renderBuffer);
		}
		else {
			redrawNormal(_renderBuffer);
		}
		_isRendering = false;
	}
	/**
	* Rendering in normal mode (single canvas).
	* Routes the call to linear or circular algorithm.
	*/
	private function redrawNormal(buffer:Array<Float>):Void
	{
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
		{
			drawWaveCircular(buffer);
		}
		else {
			drawWaveLinear(buffer);
		}
	}
	/**
	* Rendering in history mode (Ring Buffer).
	* Clears the oldest layer and draws the new waveform on it,
	* then shifts the _currentLayer pointer.
	*/
	private function redrawHistory(buffer:Array<Float>):Void
	{
		var layer = _historyLayers[_currentLayer];
		var g = layer.graphics;
// Clear the current layer (which is the oldest in the ring buffer)
		g.clear();
// Draw the new waveform on this layer
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
		{
			drawWaveCircular(buffer, g);
		}
		else {
			drawWaveLinear(buffer, g);
		}
// Shift the ring buffer pointer
		_currentLayer = (_currentLayer + 1) % HISTORY_LAYERS;
		_historyFrameCount++;
// Debug output every 10 frames
		if (_historyFrameCount % 10 == 0)
		{
			trace('OscilloscopeWidget: History frame $_historyFrameCount, next layer to clear: $_currentLayer');
		}
	}
// =========================================================================
// WAVE DRAWING (Waveform rendering algorithms)
// =========================================================================
	/**
	* Linear (Cartesian) waveform rendering.
	*
	* FIXED: X step (stepX) is calculated as `widgetWidth / (count - 1)`.
	* This guarantees that the last waveform point has X coordinate = widgetWidth,
	* and the waveform physically stretches across the full widget width without edge gaps.
	*
	* @param buffer Array of samples (snapshot).
	* @param targetGraphics Target graphics context (if null, _canvas is used).
	*/
	private function drawWaveLinear(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void
	{
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
// === CRITICAL FIX: Always clear canvas before rendering ===
		g.clear();
		if (targetGraphics == null)
		{
			_canvas.mask = _mask;
		}
		var count = buffer.length;
		if (count == 0) return;
// === Decimation: sample thinning ===
		var decimation = (_oscAtom != null) ? _oscAtom.getDecimation() : 1;
		if (decimation < 1) decimation = 1;
		var effectiveCount = Math.ceil(count / decimation);
		if (effectiveCount < 2) effectiveCount = 2;
		var zoom = _oscAtom.getZoom();
		var centerY = widgetHeight / 2.0;
		var scale = (widgetHeight / 2.0) * 0.9 * zoom;
// === FIX: Calculate step for effective number of points ===
		var stepX = widgetWidth / (effectiveCount - 1);
		g.lineStyle(1.0, colorLine, 1.0);
// First point
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 1.0) sample = 1.0;
		if (sample < -1.5) sample = -1.5;
		g.moveTo(0, centerY - sample * scale);
// Rendering with decimation
		var drawIndex = 0;
		for (i in 1...count)
		{
			if (i % decimation != 0 && i != count - 1) continue;  // ← Skip samples
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 10) sample = 10;
			if (sample < -1.5) sample = -1.5;
			drawIndex++;
			g.lineTo(drawIndex * stepX, centerY - sample * scale);
		}
	}
	/**
	* Circular (polar) waveform rendering.
	* Sample amplitude maps to radius.
	* Angle is evenly distributed across the buffer length (from 0 to 2*PI).
	*
	* @param buffer Array of samples.
	* @param targetGraphics Target graphics context.
	*/
	private function drawWaveCircular(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void
	{
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
// === CRITICAL FIX: Always clear canvas ===
		g.clear();
		var count = buffer.length;
		var decimation = (_oscAtom != null) ? _oscAtom.getDecimation() : 1;
		if (decimation < 1) decimation = 1;
		var effectiveCount = Math.ceil(count / decimation);
		if (effectiveCount < 2) effectiveCount = 2;
		var zoom = _oscAtom.getZoom();
		var cx = widgetWidth / 2;
		var cy = widgetHeight / 2;
		var maxRadius = (widgetWidth / 2) * 0.9 * zoom;
		g.lineStyle(0.5, colorLine, 1.0);
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 1.0) sample = 1.0;
		if (sample < -1.0) sample = -1.0;
		var angle:Float = 0.0;
		var r = ((sample + 1.0) / 2.0) * maxRadius;
		g.moveTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		var drawIndex = 0;
		for (i in 1...count)
		{
			if (i % decimation != 0 && i != count - 1) continue;
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 1.0) sample = 1.0;
			if (sample < -1.0) sample = -1.0;
			drawIndex++;
			angle = (drawIndex / effectiveCount) * Math.PI * 2;
			r = ((sample + 1.0) / 2.0) * maxRadius;
			g.lineTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		}
	}
// =========================================================================
// CLEAR & DISPOSE
// =========================================================================
	/**
	* Clears the screen of drawn waveforms.
	* In history mode, clears all ring buffer layers and resets pointers.
	*/
	public function clearDisplay():Void
	{
		if (_historyMode)
		{
			for (layer in _historyLayers)
			{
				if (layer != null) layer.graphics.clear();
			}
			_currentLayer = 0;
			_historyFrameCount = 0;
		}
		else if (_canvas != null)
		{
			_canvas.graphics.clear();
		}
	}
	/** Alias for full clear (compatibility). */
	public function clearAll():Void
	{
		clearDisplay();
	}
	/**
	* Releases widget resources.
	* Unsubscribes from Impulsys events, removes ENTER_FRAME listeners
	* and nullifies references to help the Garbage Collector.
	*/
	override public function dispose():Void
	{
		removeEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
		Impulsys.removeImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
		Impulsys.removeImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
		_canvas = null;
		_grid = null;
		_mask = null;
		_oscAtom = null;
		_renderBuffer = null;
		_historyLayers = null;
		_historyContainer = null;
		super.dispose();
	}
}