package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
 * OSCILLOSCOPE WIDGET v5.1
 * Real-time signal visualization widget.
 * 
 * IMPORTANT: Oscilloscope is PASSIVE - requires connected signal source.
 * 
 * USAGE:
 * 1. Add UniversalGeneratorAtom to schematic
 * 2. Set one mode to TRUE (square/saw/sine)
 * 3. Connect Generator "out" -> Oscilloscope "in"
 * 4. Oscilloscope will display the waveform
 */
class OscilloscopeWidget extends DeviceView {
    
    // UI
    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _label:TextField;
    private var _debugLabel:TextField;
    
    // Configuration
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 150;
    public var colorLine:Int = 0x00FF00;
    public var colorBg:Int = 0x0a0a12;
    public var colorGrid:Int = 0x1a2a1a;
    
    // Ring Buffer for samples
    private static inline var BUFFER_SIZE:Int = 512;
    private var _buffer:Array<Float>;
    private var _writeIndex:Int = 0;
    private var _samplesCollected:Int = 0;
    
    // Performance throttling
    private var _lastUpdateTime:Float = 0;
    private static inline var UPDATE_INTERVAL:Float = 1.0 / 30.0;
    
    // Stats
    private var _totalSamples:Int = 0;

    public function new(atom:Atom, contactName:String = "in") {
        super(atom);
        
        // Initialize buffer FIRST
        _buffer = [];
        for (i in 0...BUFFER_SIZE) {
            _buffer.push(0.0);
        }
        
        // Build UI
        buildUI();
    }
    
    private function buildUI():Void {
        // Background
        graphics.beginFill(colorBg);
        graphics.lineStyle(3, 0x333355);
        graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
        graphics.endFill();
        
        // Grid
        _grid = new Sprite();
        drawGrid();
        addChild(_grid);
        
        // Wave canvas
        _canvas = new Sprite();
        addChild(_canvas);
        
        // Debug label (top)
        _debugLabel = new TextField();
        _debugLabel.width = widgetWidth - 10;
        _debugLabel.height = 20;
        _debugLabel.x = 5;
        _debugLabel.y = 5;
        _debugLabel.selectable = false;
        _debugLabel.mouseEnabled = false;
        _debugLabel.defaultTextFormat = new TextFormat("_sans", 9, 0xFFFF00);
        _debugLabel.text = "Waiting for signal...";
        addChild(_debugLabel);
        
        // Bottom label
        _label = new TextField();
        _label.width = widgetWidth;
        _label.height = 20;
        _label.y = widgetHeight - 20;
        _label.selectable = false;
        _label.mouseEnabled = false;
        _label.defaultTextFormat = new TextFormat("_sans", 10, 0x666688, null, null, null, null, null, "center");
        _label.text = "Oscilloscope";
        addChild(_label);
    }
    
    private function drawGrid():Void {
        var g = _grid.graphics;
        g.clear();
        g.lineStyle(1, colorGrid, 0.5);
        
        // Vertical lines
        var stepX = widgetWidth / 10;
        for (i in 0...11) {
            g.moveTo(i * stepX, 0);
            g.lineTo(i * stepX, widgetHeight);
        }
        
        // Horizontal lines
        var stepY = widgetHeight / 6;
        for (i in 0...7) {
            g.moveTo(0, i * stepY);
            g.lineTo(widgetWidth, i * stepY);
        }
        
        // Center line - brighter
        g.lineStyle(1, colorGrid, 1.0);
        g.moveTo(0, widgetHeight / 2);
        g.lineTo(widgetWidth, widgetHeight / 2);
    }
    
    override private function onActivate():Void {
        debug('Activated - monitoring ${getContactCount()} contacts');
    }
    
    private function getContactCount():Int {
        if (atom == null) return 0;
        var count = 0;
        var inputs = atom.getInputs();
        var outputs = atom.getOutputs();
        if (inputs != null) count += inputs.length;
        if (outputs != null) count += outputs.length;
        return count;
    }
    
    /**
     * Called by DeviceView when contact value changes.
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed || newValue == null) return;
        
        _totalSamples++;
        
        // Throttle redraws
        var now = haxe.Timer.stamp();
        var shouldRedraw = (now - _lastUpdateTime >= UPDATE_INTERVAL);
        
        if (Std.isOfType(newValue, Float)) {
            addSample(cast(newValue, Float), shouldRedraw);
        } else if (Std.isOfType(newValue, Int)) {
            addSample(cast(newValue, Int) * 1.0, shouldRedraw);
        } else if (Std.isOfType(newValue, Array)) {
            var arr:Array<Dynamic> = cast newValue;
            if (arr.length > 0 && Std.isOfType(arr[0], Float)) {
                addSamples(cast arr, shouldRedraw);
            }
        }
        
        if (shouldRedraw) {
            _lastUpdateTime = now;
        }
        
        // Update debug every 60 samples
        if (_totalSamples % 60 == 0) {
            debug('Sample #$_totalSamples: ${Std.string(newValue).substr(0, 15)}');
        }
    }
    
    private function addSample(value:Float, redraw:Bool):Void {
        // Clamp
        if (value > 1.0) value = 1.0;
        if (value < -1.0) value = -1.0;
        
        _buffer[_writeIndex] = value;
        _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;
        
        if (_samplesCollected < BUFFER_SIZE) {
            _samplesCollected++;
        }
        
        if (redraw) {
            drawWave();
        }
    }
    
    private function addSamples(samples:Array<Float>, redraw:Bool):Void {
        if (samples == null || samples.length == 0) return;
        
        for (s in samples) {
            var val = s;
            if (val > 1.0) val = 1.0;
            if (val < -1.0) val = -1.0;
            
            _buffer[_writeIndex] = val;
            _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;
            
            if (_samplesCollected < BUFFER_SIZE) {
                _samplesCollected++;
            }
        }
        
        if (redraw) {
            drawWave();
        }
    }
    
    private function drawWave():Void {
        if (_canvas == null) return;
        
        if (_samplesCollected < 2) {
            setLabel('Collecting: $_samplesCollected/$BUFFER_SIZE');
            return;
        }
        
        var g = _canvas.graphics;
        g.clear();
        
        var displayCount = Std.int(Math.min(_samplesCollected, BUFFER_SIZE));
        var stepX = widgetWidth / displayCount;
        var centerY = widgetHeight / 2.0;
        var scale = (widgetHeight / 2.0) * 0.9;
        
        // Draw waveform
        g.lineStyle(2.5, colorLine, 0.9);
        
        var startIdx = (_samplesCollected < BUFFER_SIZE) ? 0 : _writeIndex;
        
        g.moveTo(0, centerY - _buffer[startIdx] * scale);
        
        for (i in 1...displayCount) {
            var idx = (startIdx + i) % BUFFER_SIZE;
            g.lineTo(i * stepX, centerY - _buffer[idx] * scale);
        }
        
        setLabel('Samples: $_samplesCollected | Total: $_totalSamples');
    }
    
    private function setLabel(text:String):Void {
        if (_label != null) _label.text = text;
    }
    
    private function debug(msg:String):Void {
        trace('[OscilloscopeWidget] $msg');
        if (_debugLabel != null) {
            _debugLabel.text = msg;
        }
    }
    
    public function clear():Void {
        _writeIndex = 0;
        _samplesCollected = 0;
        _totalSamples = 0;
        for (i in 0...BUFFER_SIZE) {
            _buffer[i] = 0.0;
        }
        if (_canvas != null) {
            _canvas.graphics.clear();
        }
        setLabel("Cleared");
    }
    
    override public function dispose():Void {
        _buffer = null;
        _canvas = null;
        _grid = null;
        _label = null;
        _debugLabel = null;
        super.dispose();
    }
}
