package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ============================================================================
 * OSCILLOSCOPE ATOM
 * ============================================================================
 * A specialized Driver acting as a terminal data sink for real-time waveform 
 * visualization. It consumes high-frequency audio/sample buffers from upstream 
 * atoms and bridges the gap between the computational graph and the UI layer.
 *
 * ARCHITECTURAL PRINCIPLES:
 * 1. Zero-GC Data Passing: Receives array references directly from upstream 
 *    drivers without copying data. This prevents Garbage Collection (GC) spikes 
 *    during real-time rendering of high-frequency audio streams.
 * 2. Event-Driven UI Decoupling: Uses the Impulsys event bus to notify the UI 
 *    layer about state changes. This keeps the atom graph clean and avoids 
 *    unnecessary tick recalculations in the reactive graph.
 * 3. Oscillation Bypass: Disables oscillation checks on the high-throughput 
 *    input contact to allow continuous data streaming without triggering 
 *    reactive graph feedback loops or infinite recalculation cycles.
 *
 * DATA & EVENT FLOW:
 * ┌──────────────────┐       ┌─────────────────────┐       ┌───────────────┐
 * │ Upstream Driver  │──────▶│  OscilloscopeAtom   │──────▶│  UI Widget    │
 * │ (e.g., MiniAudio)│  Ref  │    (Data Sink)      │ Event │  (Renderer)   │
 * └──────────────────┘       └─────────────────────┘       └───────────────┘
 *       Contact                     Impulsys
 *       (Array<Float>)      (OSCILOSCOPE_FRAME_READY)
 *                           (OSCILOSCOPE_SHAPE_CHANGED)
 * ============================================================================
 */
class OscilloscopeAtom extends Atom implements Driver
{
    // =========================================================================
    // CONSTANTS: VISUAL SHAPES
    // =========================================================================
    /** Rectangular display shape (a classic oscilloscope). */
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    /** Square display shape (equal X/Y axis proportions). */
    public static inline var SHAPE_SQUARE:Int = 1;
    /** Circular display shape (polar coordinates, Lissajous-like). */
    public static inline var SHAPE_CIRCULAR:Int = 2;
    
    // =========================================================================
    // STATE & DATA (ZERO-GC)
    // =========================================================================
    /**
    * The current sample buffer for rendering.
    * 
    * IMPORTANT: we store exactly the reference to the array from the upstream driver,
    * not a copy of it. This implements the Zero-GC Data Passing pattern,
    * critical for realtime audio visualization, since allocating
    * a new array every frame would cause fatal GC freezes.
    */
    private var _currentBuffer:Array<Float>;
    
    /**
    * The amplitude scaling factor (Zoom).
    * Determines how strongly the wave is stretched vertically.
    */
    private var _zoom:Float = 1.0;
    
    /**
    * The current visualization shape (SHAPE_RECTANGULAR, SHAPE_SQUARE, SHAPE_CIRCULAR).
    */
    private var _displayShape:Int = SHAPE_RECTANGULAR;
    
    /**
    * The time stretch factor (Time Scale).
    * Determines how many samples fit on the screen horizontally.
    */
    private var _timeScale:Float = 1.0;

	
    // Frame rate regulation
	private var _targetFrameRate:Float = 60.0;
	private var _decimation:Int = 1;
	private var _frameAccumulator:Float = 0.0;
	private var _lastEmitTime:Float = 0.0;
	
	public function getDecimation():Int return _decimation;
	public function getTargetFrameRate():Float return _targetFrameRate;
	
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
    * Creates a new oscilloscope instance.
    * 
    * FEATURE: this atom has NO output contacts (outputs = []).
    * It is a "terminal node" (a Data Sink). Its task is not to pass
    * data further along the graph but to visualize it or pass it to the UI.
    * 
    * @param id The unique identifier of the atom.
    */
    public function new(id:String)
    {
        super(
            // === INPUTS (Parameters and raw data) ===
            [
                new Contact(null, INPUT, "in"),            // The raw sample array from the upstream driver
                new Contact(1.0, INPUT, "zoom"),           // The amplitude scale
                new Contact(0, INPUT, "displayShape"),     // The widget shape (0, 1, 2)
                new Contact(1.0, INPUT, "timeScale"),      // The time scale
                new Contact(512, INPUT, "bufferSize"),     // The expected buffer size (informational)
				new Contact(60.0, INPUT, "frameRate"),	   // The target rendering rate (FPS)
				new Contact(1.0, INPUT, "decimation")      // Sample decimation (1 = all, 2 = every 2nd)


            ],
            // === OUTPUTS ===
            [], // An empty array. The oscilloscope generates no data for other atoms.
            null,
            id,
            "Oscilloscope",
            true
        );
        
        // ═══════════════════════════════════════════════════════════════════
        // OSCILLATION BYPASS (HIGH-FREQUENCY DATA PIPE)
        // ═══════════════════════════════════════════════════════════════════
        // The "in" contact receives data at the audio buffer rate (e.g., 40 times per second).
        // If the oscillation protection is not disabled, the reactive graph may try to
        // recompute downstream atoms or loop.
        // ignoreOscillation = true allows an infinite stream of changes.
        // resetOscillation() resets the counter to avoid false triggers at startup.
        var samplesContact = getInput("in");
        if (samplesContact != null) {
            samplesContact.ignoreOscillation = true;
            samplesContact.resetOscillation();
        }
    }
    
    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    /**
    * Driver initialization.
    * Not needed in this case, since the oscilloscope does not create
    * heavy resources (like audio devices) at startup.
    */
    override public function init():Void {}
    
    /**
    * The main update loop of the driver.
    * Called every frame from DriverManager.update(dt).
    * 
    * The Event-Driven UI Decoupling pattern is implemented here:
    * 1. We take the reference to the buffer (Zero-GC).
    * 2. We notify the UI via Impulsys instead of propagateCurrentValue().
    * This unloads the TickGenerator, since the UI updates asynchronously via events.
    * 
    * @param dt Delta time (the time since the last frame, in seconds).
    */
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;
		
		// 1. Reading the parameters (including frameRate and decimation)
		readParameters();
		
		// 2. Frame-rate throttling
		_frameAccumulator += dt;
		var targetInterval = 1.0 / _targetFrameRate;
		
		if (_frameAccumulator < targetInterval) return;  // Skip a frame
		
		_frameAccumulator = 0.0;  // Reset the accumulator
		
		// 3. Processing the input data stream (Zero-GC)
		var samplesContact = getInput("in");
		if (samplesContact != null && samplesContact.value != null)
		{
			if (Std.isOfType(samplesContact.value, Array)) {
				var samplesBuffer:Array<Float> = samplesContact.value;
				if (samplesBuffer != null && samplesBuffer.length > 0) {
					_currentBuffer = samplesBuffer;
					Impulsys.quickEmit(EventType.OSCILLOSCOPE_FRAME_READY, { atomId: this.id });
				}
			}
		}
	}
    
    // =========================================================================
    // PARAMETER READING & EDGE DETECTION
    // =========================================================================
    /**
    * Reads the values of the input contacts, validates and applies them.
    * Implements the Edge Detection pattern for the displayShape parameter:
    * the event is generated ONLY at the moment the value changes, not every frame.
    */
    private function readParameters():Void
    {
        // - Reading and clamping Zoom
        var zoomContact = getInput("zoom");
        if (zoomContact != null && zoomContact.value != null) {
            _zoom = safeFloat(zoomContact.value, 1.0);
            // Limit the range so the user cannot break the renderer.
            if (_zoom < 0.1) _zoom = 0.1;
            if (_zoom > 1.5) _zoom = 1.5;
        }
        
        // - Reading Display Shape (with Edge Detection) -
        var shapeContact = getInput("displayShape");
        if (shapeContact != null && shapeContact.value != null) {
            var newShape = safeInt(shapeContact.value, _displayShape);
            
            // Generate the event ONLY if the value actually changed.
            // This prevents extra UI redraws and shader/geometry recreation.
            if (newShape != _displayShape) {
                _displayShape = newShape;
                Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
            }
        }
        
        // - Reading and clamping Time Scale -
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null) {
            _timeScale = safeFloat(timeScaleContact.value, 1.0);
            if (_timeScale < 0.1) _timeScale = 0.1;
            if (_timeScale > 1.5) _timeScale = 1.5;
        }
	    // - Reading frameRate -
		var frameRateContact = getInput("frameRate");
		if (frameRateContact != null && frameRateContact.value != null) {
			var fr = safeFloat(frameRateContact.value, 60.0);
			if (fr >= 10.0 && fr <= 120.0) _targetFrameRate = fr;
		}
		
		// - Reading decimation -
		var decimationContact = getInput("decimation");
		if (decimationContact != null && decimationContact.value != null) {
			var dec = safeInt(decimationContact.value, 1);
			if (dec >= 1 && dec <= 16) _decimation = dec;
		}
    }
    
    // =========================================================================
    // PUBLIC API (FOR UI WIDGETS)
    // =========================================================================
    // These methods are used by the widget (DeviceView) to get the atom state.
    // The widget polls them in its rendering cycle.
    
    /** Returns the reference to the current sample buffer (Zero-GC). */
    public function getBuffer():Array<Float> return _currentBuffer;
    
    /** Returns the current amplitude scaling factor. */
    public function getZoom():Float return _zoom;
    
    /** Returns the current display shape type. */
    public function getDisplayShape():Int return _displayShape;
    
    /** Returns the current time scaling factor. */
    public function getTimeScale():Float return _timeScale;
    
    /**
    * Programmatic change of the display shape.
    * Also triggers an event for the UI so the widget rebuilds its geometry.
    * 
    * @param shape The new shape (must be in the range 0..2).
    */
    public function setDisplayShape(shape:Int):Void {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR) {
            _displayShape = shape;
            Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
        }
    }
    
    // =========================================================================
    // ROBUST TYPE COERCION (DEFENSIVE PROGRAMMING)
    // =========================================================================
    // Contacts in Haxe can take values of type Dynamic.
    // The value may come from the UI (where it can be String or Int),
    // or from another atom (where it is Float). These methods guarantee
    // safe type casting without crashing the application.
    
    /**
    * Safe conversion of Dynamic to Float.
    * Supports Float, Int and String. Returns defaultVal on error.
    * 
    * @param value The raw value from the contact.
    * @param defaultVal The default value.
    * @return The safely converted Float value.
    */
    private function safeFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, String)) { 
            var f = Std.parseFloat(cast value); 
            return Math.isNaN(f) ? defaultVal : f; 
        }
        return defaultVal;
    }
    
    /**
    * Safe conversion of Dynamic to Int.
    * Supports Int, Float and String. Returns defaultVal on error.
    * 
    * @param value The raw value from the contact.
    * @param defaultVal The default value.
    * @return The safely converted Int value.
    */
    private function safeInt(value:Dynamic, defaultVal:Int):Int {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Int)) return cast value;
        if (Std.isOfType(value, Float)) return Std.int(cast(value, Float));
        if (Std.isOfType(value, String)) { 
            var i = Std.parseInt(cast value); 
            return i == null ? defaultVal : i; 
        }
        return defaultVal;
    }
    
    // =========================================================================
    // CLEANUP
    // =========================================================================
    /**
    * Releasing resources and unregistering.
    * We null the buffer reference so the GC can collect it if the upstream driver
    * no longer holds a reference (though usually the upstream driver manages the buffer itself).
    */
    override public function dispose():Void {
        DriverManager.getInstance().unregister(this.id);
        _currentBuffer = null;
        super.dispose();
    }
}