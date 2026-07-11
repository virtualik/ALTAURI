package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * OSCILLOSCOPE ATOM v7.0 (Buffer Input Architecture)
 * 
 * v7.0 Changes:
 * - Input changed from "in:Float" to "samples:Array<Float>"
 * - Receives full audio buffer from MiniAudioAtom
 * - Writes buffer into internal ring buffer
 * - Applies trigger detection to find stable waveform
 * - Emits OSCILLOSCOPE_FRAME_READY when frame is ready
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  MiniAudioAtom "samples" ──> OscilloscopeAtom "samples"                 │
 * │                                                                         │
 * │  OscilloscopeAtom:                                                      │
 * │    1. Receives Array<Float> buffer                                      │
 * │    2. Writes into internal ring buffer (2048 samples)                   │
 * │    3. Searches for trigger edge                                         │
 * │    4. If trigger found: snapshot + emit FRAME_READY                     │
 * │    5. If no trigger for 100ms: free-run snapshot + emit                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class OscilloscopeAtom extends Atom implements Driver
{
    private static inline var DEFAULT_BUFFER_SIZE:Int = 256;
    private static inline var MIN_BUFFER_SIZE:Int = 128;
    private static inline var MAX_BUFFER_SIZE:Int = 4096;
    private static inline var DISPLAY_REFRESH_INTERVAL:Float = 0.1;
    
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    public static inline var SHAPE_SQUARE:Int = 1;
    public static inline var SHAPE_CIRCULAR:Int = 2;
    
    public static inline var STATE_IDLE:Int = 0;
    public static inline var STATE_CAPTURED:Int = 1;
    public static inline var STATE_HOLDOFF:Int = 2;
    
    /** Internal ring buffer - stores incoming samples */
    private var _buffer:Array<Float>;
    private var _bufferSize:Int = DEFAULT_BUFFER_SIZE;
    private var _writeIndex:Int = 0;
    private var _trtrig:Bool =  true;
    /** Snapshot buffer - frozen frame for display */
    private var _lastCapturedBuffer:Array<Float>;
    private var _triggerIndex:Int = 0;
    
    private var _totalSamples:Int = 0;
    private var _isTriggered:Bool = false;
    
    private var _state:Int = STATE_IDLE;
    private var _triggerArmed:Bool = true;
    private var _displayTimer:Float = 0.0;
    
    /** Trigger configuration */
    private var _timeScale:Float = 0.1;
    private var _zoom:Float = 1.0;
    private var _triggerLevel:Float = 0.0;
    private var _triggerEdge:Int = 0;
    private var _triggerMode:Int = 0;
    private var _displayShape:Int = SHAPE_RECTANGULAR;
    
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "in"),  // v7.0: Array<Float> input
                new Contact(0.1, INPUT, "timeScale"),
                new Contact(0.0, INPUT, "triggerLevel"),
                new Contact(0, INPUT, "triggerEdge"),
                new Contact(0, INPUT, "triggerMode"),
                new Contact(DEFAULT_BUFFER_SIZE, INPUT, "bufferSize"),
                new Contact(1.0, INPUT, "zoom"),
                new Contact(0, INPUT, "displayShape")
            ],
            [],
            null,
            id,
            "Oscilloscope",
            true
        );
        
        var samplesContact = getInput("samples");
        if (samplesContact != null) {
            samplesContact.ignoreOscillation = true;
            samplesContact.resetOscillation();
        }
        
        trace('OscilloscopeAtom v7.0: Created (id: $id, bufferSize: $_bufferSize)');
    }
    
    override public function init():Void
    {
        _state = STATE_IDLE;
        _displayTimer = 0.0;
        _totalSamples = 0;
        _writeIndex = 0;
        _triggerArmed = true;
        
        _buffer = [];
        for (i in 0..._bufferSize) _buffer.push(0.0);
        
        _lastCapturedBuffer = [];
        for (i in 0..._bufferSize) _lastCapturedBuffer.push(0.0);
        
        trace('OscilloscopeAtom: Initialized (Buffer Input Mode)');
    }
    
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        
        readParameters();
        
        // === v7.0: Read samples buffer from input ===
        var samplesContact = getInput("in");
        if (samplesContact != null && samplesContact.value != null)
        {
			if (_trtrig) {	trace('OscilloscopeAtom: samplesBuffer !=0 Input Data is Here!'); _trtrig = false; }
            var samplesBuffer:Array<Float> = samplesContact.value;
            if (samplesBuffer != null && samplesBuffer.length > 0)
            {
                processSamplesBuffer(samplesBuffer);
            }
        }
        
        // === Auto mode: free-run if no trigger for 100ms ===
        if (_triggerMode == 0)
        {
            _displayTimer += dt;
            if (_displayTimer >= DISPLAY_REFRESH_INTERVAL)
            {
                _isTriggered = false;
                captureBuffer();
                Impulsys.quickEmit(EventType.OSCILLOSCOPE_FRAME_READY, { atomId: this.id });
                _displayTimer = 0.0;
            }
        }
    }
    
    /**
     * v7.0: Process incoming samples buffer.
     * Writes samples into ring buffer and searches for trigger.
     */
    private function processSamplesBuffer(samples:Array<Float>):Void
    {
        var triggered = false;
        var triggerPos = -1;
        
        // Write samples into ring buffer and search for trigger
        for (i in 0...samples.length)
        {
            var sample = samples[i];
            
            // Trigger detection (compare with previous sample)
            if (_triggerArmed && i > 0)
            {
                var prevSample = samples[i - 1];
                if (checkTrigger(prevSample, sample))
                {
                    triggered = true;
                    triggerPos = i;
                }
            }
            
            // Write to ring buffer
            _buffer[_writeIndex] = sample;
            _writeIndex = (_writeIndex + 1) % _bufferSize;
            _totalSamples++;
        }
        
        // If trigger found, capture frame
        if (triggered)
        {
            _isTriggered = true;
            // Trigger index points to where the edge occurred in the captured buffer
            _triggerIndex = (_writeIndex - samples.length + triggerPos + _bufferSize) % _bufferSize;
            captureBuffer();
            Impulsys.quickEmit(EventType.OSCILLOSCOPE_FRAME_READY, { atomId: this.id });
            _displayTimer = 0.0;
            
            if (_triggerMode == 2)
            {
                _triggerArmed = false;
            }
        }
    }
    
    private function checkTrigger(lastValue:Float, currentValue:Float):Bool
    {
        if (_triggerEdge == 0)
        {
            return (lastValue < _triggerLevel && currentValue >= _triggerLevel);
        }
        else
        {
            return (lastValue > _triggerLevel && currentValue <= _triggerLevel);
        }
    }
    
    private function captureBuffer():Void
    {
        for (i in 0..._bufferSize)
        {
            _lastCapturedBuffer[i] = _buffer[i];
        }
    }
    
    private function readParameters():Void
    {
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null)
        {
            var ts = safeFloat(timeScaleContact.value, _timeScale);
            if (ts >= 0.001 && ts <= 100.0) _timeScale = ts;
        }
        
        var bufferSizeContact = getInput("bufferSize");
        if (bufferSizeContact != null && bufferSizeContact.value != null)
        {
            var bs = safeInt(bufferSizeContact.value, _bufferSize);
            if (bs < MIN_BUFFER_SIZE) bs = MIN_BUFFER_SIZE;
            if (bs > MAX_BUFFER_SIZE) bs = MAX_BUFFER_SIZE;
            if (bs != _bufferSize)
            {
                _bufferSize = bs;
                resizeBuffer(_bufferSize);
            }
        }
        
        var zoomContact = getInput("zoom");
        if (zoomContact != null && zoomContact.value != null)
        {
            _zoom = safeFloat(zoomContact.value, 1.0);
            if (_zoom < 0.1) _zoom = 0.1;
            if (_zoom > 10.0) _zoom = 10.0;
        }
        
        var shapeContact = getInput("displayShape");
        if (shapeContact != null && shapeContact.value != null)
        {
            var newShape = safeInt(shapeContact.value, _displayShape);
            if (newShape != _displayShape)
            {
                _displayShape = newShape;
                Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, {
                    atomId: this.id,
                    shape: _displayShape
                });
            }
        }
        
        var triggerLevelContact = getInput("triggerLevel");
        if (triggerLevelContact != null && triggerLevelContact.value != null)
        {
            _triggerLevel = safeFloat(triggerLevelContact.value, 0.0);
            _triggerLevel = Math.max(-1.0, Math.min(1.0, _triggerLevel));
        }
        
        var triggerEdgeContact = getInput("triggerEdge");
        if (triggerEdgeContact != null && triggerEdgeContact.value != null)
        {
            _triggerEdge = safeInt(triggerEdgeContact.value, 0);
        }
        
        var triggerModeContact = getInput("triggerMode");
        if (triggerModeContact != null && triggerModeContact.value != null)
        {
            var newMode = safeInt(triggerModeContact.value, _triggerMode);
            if (newMode != _triggerMode)
            {
                _triggerMode = newMode;
                if (_triggerMode == 2) _triggerArmed = true;
            }
        }
    }
    
    // Public accessors
    public function getBuffer():Array<Float> return _lastCapturedBuffer;
    public function getTriggerIndex():Int return _triggerIndex;
    public function getBufferSize():Int return _bufferSize;
    public function getZoom():Float return _zoom;
    public function getTimeScale():Float return _timeScale;
    public function getTriggerLevel():Float return _triggerLevel;
    public function getDisplayShape():Int return _displayShape;
    public function getFSMState():Int return _state;
    public function isTriggered():Bool return _isTriggered;
    public function getSamplesCollected():Int return Std.int(Math.min(_totalSamples, _bufferSize));
    public function getTotalSamples():Int return _totalSamples;
    
    public function setDisplayShape(shape:Int):Void
    {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR)
        {
            _displayShape = shape;
            Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, {
                atomId: this.id,
                shape: _displayShape
            });
        }
    }
    
    public function clearBuffer():Void
    {
        _writeIndex = 0;
        _triggerIndex = 0;
        _totalSamples = 0;
        _displayTimer = 0.0;
        _triggerArmed = true;
        _state = STATE_IDLE;
        
        for (i in 0..._bufferSize)
        {
            _buffer[i] = 0.0;
            _lastCapturedBuffer[i] = 0.0;
        }
    }
    
    public function rearm():Void
    {
        _triggerArmed = true;
        _state = STATE_IDLE;
    }
    
    private function resizeBuffer(newSize:Int):Void
    {
        var oldBuffer = _buffer;
        var oldCaptured = _lastCapturedBuffer;
        
        _buffer = [];
        _lastCapturedBuffer = [];
        
        for (i in 0...newSize)
        {
            _buffer.push(i < oldBuffer.length ? oldBuffer[i] : 0.0);
            _lastCapturedBuffer.push(i < oldCaptured.length ? oldCaptured[i] : 0.0);
        }
        
        _writeIndex = _writeIndex % newSize;
        _triggerIndex = _triggerIndex % newSize;
        _bufferSize = newSize;
    }
    
    private function safeFloat(value:Dynamic, defaultVal:Float):Float
    {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, String))
        {
            var f = Std.parseFloat(cast value);
            return Math.isNaN(f) ? defaultVal : f;
        }
        return defaultVal;
    }
    
    private function safeInt(value:Dynamic, defaultVal:Int):Int
    {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Int)) return cast value;
        if (Std.isOfType(value, Float)) return Std.int(cast(value, Float));
        if (Std.isOfType(value, String))
        {
            var i = Std.parseInt(cast value);
            return i == null ? defaultVal : i;
        }
        return defaultVal;
    }
    
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result = {
            displayShape: _displayShape,
            timeScale: _timeScale,
            zoom: _zoom,
            bufferSize: _bufferSize,
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
        if (state.zoom != null) _zoom = state.zoom;
        if (state.bufferSize != null)
        {
            var bs = state.bufferSize;
            if (bs >= MIN_BUFFER_SIZE && bs <= MAX_BUFFER_SIZE && bs != _bufferSize)
            {
                _bufferSize = bs;
                resizeBuffer(_bufferSize);
            }
        }
        if (state.triggerLevel != null) _triggerLevel = state.triggerLevel;
        if (state.triggerEdge != null) _triggerEdge = state.triggerEdge;
        if (state.triggerMode != null) _triggerMode = state.triggerMode;
        if (state.displayShape != null) _displayShape = state.displayShape;
        if (state.totalSamples != null) _totalSamples = state.totalSamples;
    }
    
    override public function dispose():Void
    {
        DriverManager.getInstance().unregister(this.id);
        _buffer = null;
        _lastCapturedBuffer = null;
        super.dispose();
    }
}