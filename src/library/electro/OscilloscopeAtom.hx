package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

class OscilloscopeAtom extends Atom implements Driver
{
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    public static inline var SHAPE_SQUARE:Int = 1;
    public static inline var SHAPE_CIRCULAR:Int = 2;
    
    private var _currentBuffer:Array<Float>;
    private var _zoom:Float = 1.0;
    private var _displayShape:Int = SHAPE_RECTANGULAR;
    private var _timeScale:Float = 1.0;
    
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "in"),
                new Contact(1.0, INPUT, "zoom"),
                new Contact(0, INPUT, "displayShape"),
                new Contact(1.0, INPUT, "timeScale"),
                new Contact(256, INPUT, "bufferSize")
            ],
            [],
            null,
            id,
            "Oscilloscope",
            true
        );
        
        var samplesContact = getInput("in");
        if (samplesContact != null) {
            samplesContact.ignoreOscillation = true;
            samplesContact.resetOscillation();
        }
    }
    
    override public function init():Void {}
    
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        
        readParameters();
        
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
    
    private function readParameters():Void
    {
        var zoomContact = getInput("zoom");
        if (zoomContact != null && zoomContact.value != null) {
            _zoom = safeFloat(zoomContact.value, 1.0);
            if (_zoom < 0.1) _zoom = 0.1;
            if (_zoom > 10.0) _zoom = 10.0;
        }
        
        var shapeContact = getInput("displayShape");
        if (shapeContact != null && shapeContact.value != null) {
            var newShape = safeInt(shapeContact.value, _displayShape);
            if (newShape != _displayShape) {
                _displayShape = newShape;
                Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
            }
        }
        
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null) {
            _timeScale = safeFloat(timeScaleContact.value, 1.0);
            if (_timeScale < 0.1) _timeScale = 0.1;
            if (_timeScale > 5.0) _timeScale = 5.0;
        }
    }
    
    public function getBuffer():Array<Float> return _currentBuffer;
    public function getZoom():Float return _zoom;
    public function getDisplayShape():Int return _displayShape;
    public function getTimeScale():Float return _timeScale;
    
    public function setDisplayShape(shape:Int):Void {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR) {
            _displayShape = shape;
            Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
        }
    }
    
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
    
    override public function dispose():Void {
        DriverManager.getInstance().unregister(this.id);
        _currentBuffer = null;
        super.dispose();
    }
}