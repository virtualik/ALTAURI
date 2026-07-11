package core.view;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import library.electro.OscilloscopeAtom;

/**
 * OSCILLOSCOPE WIDGET v7.0 (Full Buffer Rendering)
 * 
 * v7.0 Changes:
 * - Always renders ENTIRE buffer (0 to bufferSize)
 * - timeScale affects horizontal zoom (visual only)
 * - zoom affects vertical scale
 * - No partial buffer rendering - entire waveform always visible
 * 
 * Rendering:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  Buffer[2048] ──> Draw entire buffer from index 0 to 2047              │
 * │                    stepX = widgetWidth / bufferSize                    │
 * │                    Each sample gets equal horizontal space             │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class OscilloscopeWidget extends DeviceView
{
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 150;
    public var colorLine:Int = 0x00FF00;
    public var colorBg:Int = 0x0a0a12;
    public var colorGrid:Int = 0x1a2a1a;
    
    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _mask:Shape;
    private var _label:TextField;
    private var _debugLabel:TextField;
    
    private var _oscAtom:OscilloscopeAtom;
    
    private var _lastDrawTime:Float = 0;
    private static inline var DRAW_INTERVAL:Float = 0.016;
    
    public function new(atom:Atom, contactName:String = "in")
    {
        super(atom);
        if (Std.isOfType(atom, OscilloscopeAtom))
        {
            _oscAtom = cast(atom, OscilloscopeAtom);
        }
        buildUI();
        Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
        Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
    }
    
    private function buildUI():Void
    {
        updateDimensions();
        drawBackground();
        
        _grid = new Sprite();
        addChild(_grid);
        
        _canvas = new Sprite();
        addChild(_canvas);
        
        _mask = new Shape();
        addChild(_mask);
        
        _canvas.mask = _mask;
        _grid.mask = _mask;
        
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
        
        _label = new TextField();
        _label.width = widgetWidth;
        _label.height = 20;
        _label.y = widgetHeight - 20;
        _label.selectable = false;
        _label.mouseEnabled = false;
        _label.defaultTextFormat = new TextFormat("_sans", 10, 0x666688, null, null, null, null, null, "center");
        _label.text = "Oscilloscope";
        addChild(_label);
        
        drawGrid();
        drawMask();
    }
    
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
        
        graphics.lineStyle(3, 0x333355);
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
            graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
        else
            graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
    }
    
    private function drawGrid():Void
    {
        var g = _grid.graphics;
        g.clear();
        g.lineStyle(1, colorGrid, 0.5);
        
        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
        
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
        {
            var cx = widgetWidth / 2;
            var cy = widgetHeight / 2;
            var radius = widgetWidth / 2;
            
            for (i in 1...6)
            {
                g.drawCircle(cx, cy, radius * (i / 5.0));
            }
            g.moveTo(cx - radius, cy);
            g.lineTo(cx + radius, cy);
            g.moveTo(cx, cy - radius);
            g.lineTo(cx, cy + radius);
        }
        else
        {
            var stepX = widgetWidth / 10;
            for (i in 0...11)
            {
                g.moveTo(i * stepX, 0);
                g.lineTo(i * stepX, widgetHeight);
            }
            
            var stepY = widgetHeight / 6;
            for (i in 0...7)
            {
                g.moveTo(0, i * stepY);
                g.lineTo(widgetWidth, i * stepY);
            }
            
            g.lineStyle(1, colorGrid, 1.0);
            g.moveTo(0, widgetHeight / 2);
            g.lineTo(widgetWidth, widgetHeight / 2);
        }
        
        var triggerLevel = (_oscAtom != null) ? _oscAtom.getTriggerLevel() : 0.0;
        if (Math.abs(triggerLevel) > 0.01)
        {
            g.lineStyle(1, 0xFF8888, 0.8);
            var y = (1 - triggerLevel) * widgetHeight / 2 + widgetHeight / 2;
            g.moveTo(0, y);
            g.lineTo(widgetWidth, y);
        }
    }
    
    private function drawMask():Void
    {
        var g = _mask.graphics;
        g.clear();
        
        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
        
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
        {
            g.beginFill(0xFFFFFF);
            g.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2 - 2);
            g.endFill();
        }
    }
    
    override private function onActivate():Void
    {
        syncFromAtom();
    }
    
    override private function syncFromAtom():Void
    {
        if (_oscAtom == null) return;
        updateDimensions();
        drawBackground();
        drawGrid();
        drawMask();
        redrawFromAtom();
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed || _oscAtom == null) return;
        
        if (contact.name == "samples") return;
        
        var now:Float = haxe.Timer.stamp();
        if (now - _lastDrawTime < DRAW_INTERVAL) return;
        _lastDrawTime = now;
        
        if (contact.name == "triggerLevel" || contact.name == "triggerEdge")
        {
            drawGrid();
        }
        else
        {
            drawGrid();
            redrawFromAtom();
        }
    }
    
    private function onFrameReady(impulse:Impulse):Void
    {
        if (isDisposed || impulse == null || impulse.data == null) return;
        if (impulse.data.atomId != atom.id) return;
        redrawFromAtom();
    }
    
    private function onShapeChanged(impulse:Impulse):Void
    {
        if (isDisposed || impulse == null || impulse.data == null) return;
        if (impulse.data.atomId != atom.id) return;
        
        var newShape:Int = impulse.data.shape;
        switch (newShape)
        {
            case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR:
                widgetWidth = 200; widgetHeight = 200;
            default:
                widgetWidth = 300; widgetHeight = 150;
        }
        rebuildUI();
    }
    
    private function rebuildUI():Void
    {
        removeChildren();
        
        drawBackground();
        
        _grid = new Sprite(); addChild(_grid);
        _canvas = new Sprite(); addChild(_canvas);
        _mask = new Shape(); addChild(_mask);
        
        _canvas.mask = _mask;
        _grid.mask = _mask;
        
        _debugLabel = new TextField();
        _debugLabel.width = widgetWidth - 10;
        _debugLabel.height = 20;
        _debugLabel.x = 5; _debugLabel.y = 5;
        _debugLabel.selectable = false; _debugLabel.mouseEnabled = false;
        _debugLabel.defaultTextFormat = new TextFormat("_sans", 9, 0xFFFF00);
        addChild(_debugLabel);
        
        _label = new TextField();
        _label.width = widgetWidth;
        _label.height = 20;
        _label.y = widgetHeight - 20;
        _label.selectable = false; _label.mouseEnabled = false;
        _label.defaultTextFormat = new TextFormat("_sans", 10, 0x666688, null, null, null, null, null, "center");
        addChild(_label);
        
        drawGrid();
        drawMask();
        redrawFromAtom();
    }
    
    /**
     * v7.0: Render ENTIRE buffer from index 0 to bufferSize.
     * Each sample gets equal horizontal space: stepX = widgetWidth / bufferSize
     */
    private function redrawFromAtom():Void
    {
        if (_oscAtom == null || _canvas == null) return;
        
        var buffer = _oscAtom.getBuffer();
        var triggerIndex = _oscAtom.getTriggerIndex();
        var samplesCollected = _oscAtom.getSamplesCollected();
        
        if (samplesCollected < 2)
        {
            setLabel('Collecting: $samplesCollected / ${_oscAtom.getBufferSize()}');
            return;
        }
        
        var shape = _oscAtom.getDisplayShape();
        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
            drawWaveCircular(buffer, triggerIndex, samplesCollected);
        else
            drawWaveLinear(buffer, triggerIndex, samplesCollected);
        
        setLabel('Samples: $samplesCollected | Total: ${_oscAtom.getTotalSamples()}');
    }
    
    /**
     * v7.0: Draw entire buffer as linear waveform.
     * All samples from 0 to bufferSize are rendered with equal spacing.
     */
    private function drawWaveLinear(buffer:Array<Float>, triggerIndex:Int, count:Int):Void
    {
        var g = _canvas.graphics;
        g.clear();
        
        if (buffer == null || buffer.length == 0) return;
        
        var totalSamples = buffer.length;
        var zoom = _oscAtom.getZoom();
        var centerY = widgetHeight / 2.0;
        var scale = (widgetHeight / 2.0) * 0.9 * zoom;
        
        // v7.0: Each sample gets equal horizontal space
        var stepX = widgetWidth / (totalSamples - 1);
        
        // Decimation for performance: skip samples if too many
        var renderStep = Math.ceil(totalSamples / 600);
        if (renderStep < 1) renderStep = 1;
        
        g.lineStyle(1.8, colorLine, 1.0);
        g.moveTo(0, centerY - buffer[0] * scale);
        
        for (i in 1...totalSamples)
        {
            if (i % renderStep != 0 && i != totalSamples - 1) continue;
            
            var x = i * stepX;
            g.lineTo(x, centerY - buffer[i] * scale);
        }
    }
    
    private function drawWaveCircular(buffer:Array<Float>, triggerIndex:Int, count:Int):Void
    {
        var g = _canvas.graphics;
        g.clear();
        
        if (buffer == null || buffer.length == 0) return;
        
        var totalSamples = buffer.length;
        var zoom = _oscAtom.getZoom();
        
        var cx = widgetWidth / 2;
        var cy = widgetHeight / 2;
        var maxRadius = (widgetWidth / 2) * 0.9 * zoom;
        
        var renderStep = Math.ceil(totalSamples / 600);
        if (renderStep < 1) renderStep = 1;
        
        g.lineStyle(1.8, colorLine, 1.0);
        
        var firstPoint = true;
        for (i in 0...totalSamples)
        {
            if (i % renderStep != 0 && i != totalSamples - 1) continue;
            
            var value = buffer[i];
            var angle = (i / totalSamples) * Math.PI * 2;
            var r = ((value + 1) / 2.0) * maxRadius;
            
            var px = cx + Math.cos(angle) * r;
            var py = cy + Math.sin(angle) * r;
            
            if (firstPoint)
            {
                g.moveTo(px, py);
                firstPoint = false;
            }
            else
            {
                g.lineTo(px, py);
            }
        }
    }
    
    private function setLabel(text:String):Void
    {
        if (_label != null) _label.text = text;
    }
    
    public function clearDisplay():Void
    {
        if (_canvas != null) _canvas.graphics.clear();
    }
    
    public function clearAll():Void
    {
        if (_oscAtom != null) _oscAtom.clearBuffer();
        clearDisplay();
    }
    
    override public function dispose():Void
    {
        Impulsys.removeImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
        Impulsys.removeImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
        
        _canvas = null;
        _grid = null;
        _mask = null;
        _label = null;
        _debugLabel = null;
        _oscAtom = null;
        
        super.dispose();
    }
}