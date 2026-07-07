package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * OSCILLOSCOPE ATOM v4.0 (Time-Based Sampling)
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * OscilloscopeAtom is an active driver atom with timing from TickGenerator.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeAtom                                                      │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   update(dt) {                                                          │
 * │       1. Accumulate time until next sample                              │
 * │       2. Calculate interval: sampleInterval = timeScale / BUFFER_SIZE   │
 * │       3. If enough time accumulated → takeSample()                      │
 * │       4. takeSample() reads current "in" contact value                  │
 * │       5. Check trigger and write to buffer                              │
 * │   }                                                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   private var _buffer:Array<Float>;        // Ring buffer 512           │
 * │   private var _writeIndex:Int = 0;         // Current write position    │
 * │   private var _samplesCollected:Int = 0;   // Samples collected count   │
 * │   private var _totalSamples:Int = 0;       // Total counter             │
 * │   private var _sampleAccumulator:Float = 0;// Time accumulator          │
 * │   private var _timeScale:Float = 1.0;      // Seconds per full screen   │
 * │   private var _triggerLevel:Float = 0.0;   // Trigger level             │
 * │   private var _triggerEdge:Int = 0;        // 0=rising, 1=falling       │
 * │   private var _triggerMode:Int = 0;        // 0=auto, 1=normal, 2=single│
 * │   private var _triggerArmed:Bool = true;   // Is trigger armed          │
 * │                                                                         │
 * │   public function getBuffer():Array<Float>  // API for DeviceView       │
 * │   public function getWriteIndex():Int                                   │
 * │   public function getSamplesCollected():Int                             │
 * │   public function getSamplingStatus() // Sampling status                │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   OscilloscopeWidget reads from Databank:                               │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │ var buffer = oscAtom.getBuffer();                               │   │
 * │   │ var idx = oscAtom.getWriteIndex();                              │   │
 * │   │ drawWave(buffer, idx, oscAtom.getSamplesCollected());           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Headless Mode:                                                        │
 * │   ──────────────                                                        │
 * │   Atom works autonomously - samples input by time.                      │
 * │   DeviceView not required for operation.                                │
 * │   Data can be saved via getPersistentState().                           │
 * │                                                                         │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │   TIMING FROM TICKGENERATOR                                             │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │                                                                         │
 * │   TickGenerator (60 Hz)                                                 │
 * │        │                                                                │
 * │        ├──► SignalGenerator.update(dt) - generates signal               │
 * │        │                                                                │
 * │        └──► OscilloscopeAtom.update(dt) - samples input                 │
 * │                                                                         │
 * │   Both use same fixedDeltaTime for consistent time!                     │
 * │                                                                         │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │   INTERVAL CALCULATION                                                  │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │                                                                         │
 * │   timeScale = 0.01 (10ms per screen)                                    │
 * │   BUFFER_SIZE = 512                                                     │
 * │   sampleInterval = 0.01 / 512 = 19.5μs                                  │
 * │   sampleRate = 512 / 0.01 = 51.2 kHz                                    │
 * │                                                                         │
 * │   For 440 Hz sine wave:                                                 │
 * │   - Period = 2.27ms                                                     │
 * │   - Samples per period = 51.2kHz / 440Hz ≈ 116 samples                  │
 * │   - Enough for smooth wave!                                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v4.0 Changes:
 * - ARCHITECTURE: Time-based sampling instead of event-driven
 * - Oscilloscope is now an active Driver (isActive = true)
 * - Uses TickGenerator.update(dt) for precise timing
 * - Sample interval calculated from timeScale / BUFFER_SIZE
 * - Trigger logic works with time-based sampling
 * - Input contact ignores oscillation for fast signals
 * - Sampling status API for debugging
 */
class OscilloscopeAtom extends Atom implements Driver
{
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Buffer size = oscilloscope screen width in pixels.
    // 512 points is enough for smooth line.
    private static inline var BUFFER_SIZE:Int = 512;
    
    // Minimum sample interval (protection from too high frequency)
    private static inline var MIN_SAMPLE_INTERVAL:Float = 0.00001; // 10μs

    // =========================================================================
    // DISPLAY SHAPE ENUM
    // =========================================================================
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    public static inline var SHAPE_SQUARE:Int = 1;
    public static inline var SHAPE_CIRCULAR:Int = 2;

    // =========================================================================
    // DATABANK
    // =========================================================================
    private var _buffer:Array<Float>;
    // Write index in ring buffer
    private var _writeIndex:Int = 0;
    // Counter of collected samples (for "waiting for signal" logic)
    private var _samplesCollected:Int = 0;
    private var _totalSamples:Int = 0;
    private var _lastValue:Float = 0.0;
    private var _displayShape:Int = SHAPE_RECTANGULAR;

    // =========================================================================
    // TIME BASE & TRIGGER
    // =========================================================================
    private var _timeScale:Float = 0.1;      // seconds per full screen (buffer width)
    private var _triggerLevel:Float = 0.0;
    private var _triggerEdge:Int = 0;        // 0=rising, 1=falling
    private var _triggerMode:Int = 0;        // 0=auto, 1=normal, 2=single
    private var _triggerArmed:Bool = true;   // is trigger armed (for single/normal)

    // =========================================================================
    // SAMPLING STATE (v4.0)
    // =========================================================================
    private var _sampleAccumulator:Float = 0.0;  // Time accumulator for samples
    private var _lastInputValue:Float = 0.0;     // Last read input value
    private var _isSampling:Bool = false;        // Active sampling flag

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "in"),
                new Contact(0.1, INPUT, "timeScale"),
                new Contact(0.0, INPUT, "triggerLevel"),
                new Contact(0, INPUT, "triggerEdge"),
                new Contact(0, INPUT, "triggerMode")
            ],
            [], // no outputs
            null,
            id,
            "Oscilloscope",
            true  // v4.0: isActive = true (register in DriverManager)
        );
        
        var inContact = getInput("in");
        if (inContact != null) {
            inContact.ignoreOscillation = true;  // v4.0: Ignore oscillation for fast signals
            inContact.resetOscillation();
        }
        
        // Initialize buffer with zeros
        _buffer = [];
        for (i in 0...BUFFER_SIZE) {
            _buffer.push(0.0);
        }
        
        trace('OscilloscopeAtom: Created (id: $id, bufferSize: $BUFFER_SIZE, active: true)');
    }

    // =========================================================================
    // LIFECYCLE - Driver Interface
    // =========================================================================
    /**
     * Driver initialization.
     */
    override public function init():Void
    {
        _sampleAccumulator = 0.0;
        _lastInputValue = 0.0;
        _isSampling = true;
        _triggerArmed = true;
        trace('OscilloscopeAtom: Initialized (sampling active)');
    }

    /**
     * Update every frame - main sampling logic.
     * Called from DriverManager.update().
     *
     * v4.0: Time-based sampling instead of event-driven
     *
     * @param dt Delta time in seconds
     */
    override public function update(dt:Float):Void
    {
        if (_isDisposed || !_isSampling) return;
        
        // 1. Read parameters (timeScale, trigger, etc.)
        readParameters();
        
        // 2. Calculate sample interval
        var sampleInterval = _timeScale / BUFFER_SIZE;
        if (sampleInterval < MIN_SAMPLE_INTERVAL) {
            sampleInterval = MIN_SAMPLE_INTERVAL;
        }
        
        // 3. Accumulate time
        _sampleAccumulator += dt;
        
        // 4. If enough time accumulated - take sample(s)
        while (_sampleAccumulator >= sampleInterval) {
            takeSample();
            _sampleAccumulator -= sampleInterval;
        }
        
        // 5. Auto-arm trigger in auto mode
        if (_triggerMode == 0 && !_triggerArmed && _samplesCollected >= BUFFER_SIZE) {
            _triggerArmed = true;
        }
    }

    /**
     * Free resources.
     */
    override public function dispose():Void
    {
        DriverManager.getInstance().unregister(this.id);
        _buffer = null;
        super.dispose();
        trace('OscilloscopeAtom: Disposed (total samples: $_totalSamples)');
    }

    // =========================================================================
    // PARAMETER READING
    // =========================================================================
    /**
     * Read values from parameter input contacts.
     */
    private function readParameters():Void
    {
        // timeScale
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null) {
            var ts = _safeFloat(timeScaleContact.value, _timeScale);
            if (ts >= 0.001 && ts <= 10.0) {
                _timeScale = ts;
            }
        }
        
        // triggerLevel
        var triggerLevelContact = getInput("triggerLevel");
        if (triggerLevelContact != null && triggerLevelContact.value != null) {
            _triggerLevel = _safeFloat(triggerLevelContact.value, 0.0);
            if (_triggerLevel < -1.0) _triggerLevel = -1.0;
            if (_triggerLevel > 1.0) _triggerLevel = 1.0;
        }
        
        // triggerEdge
        var triggerEdgeContact = getInput("triggerEdge");
        if (triggerEdgeContact != null && triggerEdgeContact.value != null) {
            _triggerEdge = _safeInt(triggerEdgeContact.value, 0);
        }
        
        // triggerMode
        var triggerModeContact = getInput("triggerMode");
        if (triggerModeContact != null && triggerModeContact.value != null) {
            _triggerMode = _safeInt(triggerModeContact.value, 0);
            if (_triggerMode == 2) _triggerArmed = true; // single mode: re-arm
        }
    }

    // =========================================================================
    // EVENT HANDLING (for parameter changes only)
    // =========================================================================
    /**
     * Handle contact changes.
     * v4.0: Only for parameters, not for sampling!
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isDisposed) return;
        
        // v4.0: Ignore "in" for sampling - it happens in update()
        // But process parameter changes
        switch (c.name) {
            case "timeScale":
                _timeScale = _safeFloat(c.value, 1.0);
                if (_timeScale < 0.001) _timeScale = 0.001;
            case "triggerLevel":
                _triggerLevel = _safeFloat(c.value, 0.0);
                if (_triggerLevel < -1.0) _triggerLevel = -1.0;
                if (_triggerLevel > 1.0) _triggerLevel = 1.0;
            case "triggerEdge":
                _triggerEdge = _safeInt(c.value, 0);
            case "triggerMode":
                _triggerMode = _safeInt(c.value, 0);
                if (_triggerMode == 2) _triggerArmed = true; // single mode: re-arm
            case "in":
                // v4.0: Ignore for sampling, but save last value
                // in case update() doesn't have time to read
                if (c.value != null) {
                    _lastInputValue = _toFloat(c.value, 0.0);
                }
        }
    }

    // =========================================================================
    // SAMPLING LOGIC (v4.0)
    // =========================================================================
    /**
     * Take one sample from input.
     * Called from update() when enough time accumulated.
     *
     * v4.1 FIX: Always write to buffer for continuous sweep,
     * even if trigger hasn't fired. Trigger only syncs display start,
     * but doesn't stop sampling.
     */
    private function takeSample():Void
    {
        // 1. Read current input value
        var inContact = getInput("in");
        var currentValue:Float = 0.0;
        if (inContact != null && inContact.value != null) {
            currentValue = _toFloat(inContact.value, _lastInputValue);
        } else {
            currentValue = _lastInputValue;
        }
        
        // Update last value
        _lastInputValue = currentValue;
        
        // 2. === FIX v4.1: ALWAYS write to buffer (continuous sweep) ===
        _buffer[_writeIndex] = currentValue;
        _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;
        if (_samplesCollected < BUFFER_SIZE) {
            _samplesCollected++;
        }
        _totalSamples++;
        
        // 3. Trigger logic (only for sync, doesn't block sampling)
        if (_triggerMode != 0 && !_triggerArmed) {
            // Wait for trigger
            var triggered = false;
            if (_triggerEdge == 0) { // rising
                if (_lastValue < _triggerLevel && currentValue >= _triggerLevel) {
                    triggered = true;
                }
            } else { // falling
                if (_lastValue > _triggerLevel && currentValue <= _triggerLevel) {
                    triggered = true;
                }
            }
            if (triggered) {
                _triggerArmed = false;
                // Reset writeIndex to start display from this sample
                // But DON'T clear buffer - just change reference point
                _writeIndex = 0;
                _samplesCollected = 1;
            }
            _lastValue = currentValue;
            return; // Exit, but buffer already written!
        }
        
        // 4. Auto-arm trigger in auto mode
        if (_triggerMode == 0 && !_triggerArmed && _samplesCollected >= BUFFER_SIZE) {
            _triggerArmed = true;
        }
        
        _lastValue = currentValue;
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================
    public function getBuffer():Array<Float> return _buffer;
    public function getWriteIndex():Int return _writeIndex;
    public function getSamplesCollected():Int return _samplesCollected;
    public function getTotalSamples():Int return _totalSamples;
    public function getLastValue():Float return _lastValue;
    public function getBufferSize():Int return BUFFER_SIZE;
    public function getDisplayShape():Int return _displayShape;
    
    public function setDisplayShape(shape:Int):Void
    {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR) {
            _displayShape = shape;
        }
    }

    /**
     * v4.0: Sampling status for debugging
     */
    public function getSamplingStatus():{
        sampleRate:Float,
        timePerSample:Float,
        isTriggered:Bool,
        accumulator:Float
    } {
        var sampleInterval = _timeScale / BUFFER_SIZE;
        return {
            sampleRate: 1.0 / sampleInterval,
            timePerSample: sampleInterval,
            isTriggered: !_triggerArmed,
            accumulator: _sampleAccumulator
        };
    }

    /**
     * v4.0: Enable/disable sampling
     */
    public function setSampling(active:Bool):Void
    {
        _isSampling = active;
        if (active) {
            _sampleAccumulator = 0.0;
            _triggerArmed = true;
        }
    }

    public function clearBuffer():Void
    {
        _writeIndex = 0;
        _samplesCollected = 0;
        // Don't reset _totalSamples - this is overall statistics
        _lastValue = 0.0;
        for (i in 0...BUFFER_SIZE) {
            _buffer[i] = 0.0;
        }
    }

    // =========================================================================
    // TIME SCALE & TRIGGER API
    // =========================================================================
    public function getTimeScale():Float return _timeScale;
    public function setTimeScale(scale:Float):Void {
        _timeScale = Math.max(0.001, scale);
    }
    public function getTriggerLevel():Float return _triggerLevel;
    public function setTriggerLevel(level:Float):Void {
        _triggerLevel = Math.max(-1.0, Math.min(1.0, level));
    }
    public function getTriggerEdge():Int return _triggerEdge;
    public function setTriggerEdge(edge:Int):Void {
        _triggerEdge = edge;
    }
    public function getTriggerMode():Int return _triggerMode;
    public function setTriggerMode(mode:Int):Void {
        _triggerMode = mode;
        if (mode == 2) _triggerArmed = true;
    }
    public function rearm():Void {
        _triggerArmed = true;
    }

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();
		var result = {
			displayShape: _displayShape,
			timeScale: _timeScale,
			triggerLevel: _triggerLevel,
			triggerEdge: _triggerEdge,
			triggerMode: _triggerMode,
			totalSamples: _totalSamples
		};
		if (base != null)
		{
			for (field in Reflect.fields(base))
			{
				Reflect.setField(result, field, Reflect.field(base, field));
			}
		}
		return result;
	}

    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        super.restoreState(state);
        if (state.timeScale != null) _timeScale = state.timeScale;
        if (state.triggerLevel != null) _triggerLevel = state.triggerLevel;
        if (state.triggerEdge != null) _triggerEdge = state.triggerEdge;
        if (state.triggerMode != null) {
            _triggerMode = state.triggerMode;
            if (_triggerMode == 2) _triggerArmed = true;
        }
        if (state.displayShape != null) _displayShape = state.displayShape;
        if (state.totalSamples != null) _totalSamples = state.totalSamples;
        
        // Reconfigure contact
        var inContact = getInput("in");
        if (inContact != null) {
            inContact.ignoreOscillation = true;
            inContact.resetOscillation();
        }
        trace('OscilloscopeAtom: Restored state (timeScale: $_timeScale, totalSamples: $_totalSamples)');
    }

    // =========================================================================
    // UTILITY FUNCTIONS
    // =========================================================================
    private function _safeFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, String)) {
            var f = Std.parseFloat(cast value);
            return Math.isNaN(f) ? defaultVal : f;
        }
        return defaultVal;
    }

    private function _safeInt(value:Dynamic, defaultVal:Int):Int {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Int)) return cast value;
        if (Std.isOfType(value, Float)) return Std.int(cast(value, Float));
        if (Std.isOfType(value, String)) {
            var i = Std.parseInt(cast value);
            return i == null ? defaultVal : i;
        }
        return defaultVal;
    }

    private function _toFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, Bool)) return cast(value, Bool) ? 1.0 : 0.0;
        if (Std.isOfType(value, String)) {
            var f = Std.parseFloat(cast value);
            return Math.isNaN(f) ? defaultVal : f;
        }
        return defaultVal;
    }
}