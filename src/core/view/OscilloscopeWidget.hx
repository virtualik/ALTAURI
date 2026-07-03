package core.view;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.geom.Rectangle;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;
import library.electro.OscilloscopeAtom;

/**
 * OSCILLOSCOPE WIDGET
 * Real-time signal visualization widget.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * OscilloscopeWidget is the FACE of OscilloscopeAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeWidget DOES NOT STORE DATA!                               │
 * │                                                                         │
 * │   OscilloscopeWidget:                                                   │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │   REFERENCES:                                                   │   │
 * │   │   - atom:OscilloscopeAtom  // Reference to Databank             │   │
 * │   │   - _oscAtom:OscilloscopeAtom  // Typed reference               │   │
 * │   │                                                                 │   │
 * │   │   UI COMPONENTS:                                                │   │
 * │   │   - _canvas:Sprite   // Drawing area                            │   │
 * │   │   - _grid:Sprite     // Grid overlay                            │   │
 * │   │   - _label:TextField // Bottom label                            │   │
 * │   │   - _debugLabel:TextField // Debug info                         │   │
 * │   │                                                                 │   │
 * │   │   CONFIGURATION:                                                │   │
 * │   │   - widgetWidth:Float = 300                                     │   │
 * │   │   - widgetHeight:Float = 150                                    │   │
 * │   │   - colorLine:Int = 0x00FF00                                    │   │
 * │   │                                                                 │   │
 * │   │   THROTTLING (UI-only state):                                   │   │
 * │   │   - _lastDrawTime:Float  // For FPS limiting                    │   │
 * │   │   - DRAW_INTERVAL:Float = 1/30   // 30 FPS max                  │   │
 * │   │                                                                 │   │
 * │   │   DATA READING:                                                 │   │
 * │   │   var buffer = _oscAtom.getBuffer();                            │   │
 * │   │   var idx = _oscAtom.getWriteIndex();                           │   │
 * │   │   var count = _oscAtom.getSamplesCollected();                   │   │
 * │   │   drawWave(buffer, idx, count);                                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   DATA SOURCE:                                                          │
 * │   ──────────────                                                        │
 * │   OscilloscopeAtom._buffer → single source of truth                     │
 * │                                                                         │
 * │   HEADLESS MODE:                                                        │
 * │   ──────────────                                                        │
 * │   Atom continues working without widget.                                │
 * │   When widget is created, it reads current atom state.                  │
 * │                                                                         │
 * │   SINGLETON:                                                            │
 * │   ──────────                                                            │
 * │   DeviceViewRegistry guarantees one widget per atom.                    │
 * │   Widget moves between NodeView and DeviceWindow.                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class OscilloscopeWidget extends DeviceView 
{
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Widget dimensions
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 100;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    public var colorLine:Int = 0x00FF00;
    public var colorBg:Int = 0x0a0a12;
    public var colorGrid:Int = 0x1a2a1a;

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _mask:Shape;
    private var _label:TextField;
    private var _debugLabel:TextField;

    // =========================================================================
    // REFERENCE TO DATABANK
    // =========================================================================
    private var _oscAtom:OscilloscopeAtom;

    // =========================================================================
    // THROTTLING
    // =========================================================================
    private var _lastDrawTime:Float = 0;
    private static inline var DRAW_INTERVAL:Float = 1.0 / 60.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom, contactName:String = "in") 
    {
        super(atom);
        if (Std.isOfType(atom, OscilloscopeAtom)) 
        {
            _oscAtom = cast(atom, OscilloscopeAtom);
        }
        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void 
    {
        // Determine initial size based on atom setting
        updateDimensions();

        // Background
        drawBackground();

        // Grid
        _grid = new Sprite();
        addChild(_grid);

        // Wave canvas
        _canvas = new Sprite();
        addChild(_canvas);

        // Mask for circular shape
        _mask = new Shape();
        addChild(_mask);
        _canvas.mask = _mask;
        _grid.mask = _mask;

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

        drawGrid();
        drawMask();
    }

    /**
     * Update widget dimensions based on display shape.
     */
    private function updateDimensions():Void 
    {
        if (_oscAtom == null) return;

        var shape = _oscAtom.getDisplayShape();

        switch (shape) 
        {
            case OscilloscopeAtom.SHAPE_SQUARE:
                // Square: make width equal to height (200x200)
                widgetWidth = 200;
                widgetHeight = 200;

            case OscilloscopeAtom.SHAPE_CIRCULAR:
                // Circular: fits in 200x200
                widgetWidth = 200;
                widgetHeight = 200;

            default:
                // Rectangular: default 300x150
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
        {
            graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
        } 
        else 
        {
            graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
        }

        graphics.endFill();

        graphics.lineStyle(3, 0x333355);

        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
        {
            graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
        } 
        else 
        {
            graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
        }
    }

    private function drawGrid():Void 
    {
        var g = _grid.graphics;
        g.clear();
        g.lineStyle(1, colorGrid, 0.5);

        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;

        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
        {
            // Circular grid: concentric circles
            var cx = widgetWidth / 2;
            var cy = widgetHeight / 2;
            var radius = widgetWidth / 2;

            for (i in 1...6) 
            {
                var r = radius * (i / 5.0);
                g.drawCircle(cx, cy, r);
            }

            // Cross lines
            g.moveTo(cx - radius, cy);
            g.lineTo(cx + radius, cy);
            g.moveTo(cx, cy - radius);
            g.lineTo(cx, cy + radius);
        } 
        else 
        {
            // Rectangular/Square grid
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

            // Center line
            g.lineStyle(1, colorGrid, 1.0);
            g.moveTo(0, widgetHeight / 2);
            g.lineTo(widgetWidth, widgetHeight / 2);
        }

        // Draw trigger level indicator
        var triggerLevel = _oscAtom.getTriggerLevel();
        if (triggerLevel != 0) 
        {
            g.lineStyle(1, 0xFF8888, 0.8);
            var y = (1 - triggerLevel) * widgetHeight / 2 + widgetHeight / 2;
            g.moveTo(0, y);
            g.lineTo(widgetWidth, y);
        }
    }

    /**
     * Draw mask for circular shape.
     */
    private function drawMask():Void 
    {
        var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
        var g = _mask.graphics;
        g.clear();

        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
        {
            g.beginFill(0xFFFFFF);
            g.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2 - 2);
            g.endFill();
        } 
        else 
        {
            // No mask needed for rect/square
        }
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    override private function onActivate():Void 
    {
        syncFromAtom();
        debug('Activated');
    }

    override private function syncFromAtom():Void 
    {
        // Check if shape changed and rebuild UI
        if (_oscAtom != null) 
        {
            updateDimensions();
            drawBackground();
            drawGrid();
            drawMask();
            redrawFromAtom();
        }
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        if (isDisposed || _oscAtom == null) return;

        // If any parameter changed (timeScale, triggerLevel, etc.) — redraw
        if (contact.name != "in") 
        {
            redrawFromAtom();
        } 
        else 
        {
            // Throttle drawing for input signal changes
            var now = haxe.Timer.stamp();
            if (now - _lastDrawTime < DRAW_INTERVAL) return;
            _lastDrawTime = now;
            redrawFromAtom();
        }

        if (_oscAtom.getTotalSamples() % 60 == 0) 
        {
            debug('Sample #${_oscAtom.getTotalSamples()}');
        }
    }

    /**
     * Redraw the waveform from atom's Databank.
     */
    private function redrawFromAtom():Void 
    {
        if (_oscAtom == null || _canvas == null) return;

        var buffer = _oscAtom.getBuffer();
        var writeIndex = _oscAtom.getWriteIndex();
        var samplesCollected = _oscAtom.getSamplesCollected();
        var totalSamples = _oscAtom.getTotalSamples();

        if (samplesCollected < 2) 
        {
            setLabel('Collecting: $samplesCollected / ${_oscAtom.getBufferSize()}');
            return;
        }

        var shape = _oscAtom.getDisplayShape();

        if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) 
        {
            drawWaveCircular(buffer, writeIndex, samplesCollected);
        } 
        else 
        {
            drawWaveLinear(buffer, writeIndex, samplesCollected);
        }

        setLabel('Samples: $samplesCollected | Total: $totalSamples');
    }

    /**
     * Draw linear waveform (rectangular or square display).
     *
     * Visual zoom is controlled by timeScale:
     * - timeScale = 1.0 → show entire buffer (512 samples)
     * - timeScale = 0.1 → show only 10% of buffer (51 samples) → Zoom IN
     * - timeScale = 2.0 → show 2x buffer (stretch) → Zoom OUT
     */
    private function drawWaveLinear(buffer:Array<Float>, writeIndex:Int, count:Int):Void 
    {
        var g = _canvas.graphics;
        g.clear();

        if (buffer == null || buffer.length == 0) return;

        var timeScale = _oscAtom.getTimeScale();
        var totalSamples = buffer.length;

        // Calculate how many samples to display on screen
        var displayCount = Std.int(totalSamples * timeScale);
        if (displayCount > totalSamples) displayCount = totalSamples;
        if (displayCount < 2) displayCount = 2;

        // Calculate X step — now depends on displayCount
        var stepX = widgetWidth / displayCount;

        // How many points we actually draw
        var countToDraw = count;
        if (countToDraw > displayCount) countToDraw = displayCount;
        if (countToDraw < 2) return;

        var centerY = widgetHeight / 2.0;
        var scale = (widgetHeight / 2.0) * 0.9;

        // Index of the LAST written sample (most recent)
        var lastIdx = (writeIndex - 1 + totalSamples) % totalSamples;

        g.lineStyle(1.5, colorLine, 1.0);

        // Always start drawing from the RIGHT edge of the display
        g.moveTo(widgetWidth, centerY - buffer[lastIdx] * scale);

        // Move strictly left with fixed step
        for (i in 1...countToDraw) 
        {
            var idx = (lastIdx - i + totalSamples) % totalSamples;
            var x = widgetWidth - (i * stepX);
            g.lineTo(x, centerY - buffer[idx] * scale);
        }
    }

    /**
     * Draw circular waveform (spiral or polar).
     * For simplicity, we draw it as a radial graph where angle = time.
     */
    private function drawWaveCircular(buffer:Array<Float>, writeIndex:Int, count:Int):Void 
    {
        var g = _canvas.graphics;
        g.clear();

        var displayCount = Std.int(Math.min(count, buffer.length));
        var cx = widgetWidth / 2;
        var cy = widgetHeight / 2;
        var maxRadius = (widgetWidth / 2) * 0.9;

        var startIdx = (count >= buffer.length) ? writeIndex : 0;

        g.lineStyle(1.5, colorLine, 1.0);

        for (i in 0...displayCount) 
        {
            var idx = (startIdx + i) % buffer.length;
            var value = buffer[idx];

            // Map time (i) to angle: 0 .. 2PI
            var angle = (i / displayCount) * Math.PI * 2;

            // Map value (-1..1) to radius
            // 0 = center, -1 = inner circle, +1 = outer circle
            var r = ((value + 1) / 2.0) * maxRadius;

            var px = cx + Math.cos(angle) * r;
            var py = cy + Math.sin(angle) * r;

            if (i == 0) g.moveTo(px, py);
            else g.lineTo(px, py);
        }
    }

    // =========================================================================
    // UI HELPERS
    // =========================================================================
    private function setLabel(text:String):Void 
    {
        if (_label != null) _label.text = text;
    }

    private function debug(msg:String):Void 
    {
        if (_debugLabel != null) 
        {
            _debugLabel.text = msg;
        }
    }

    public function clearDisplay():Void 
    {
        if (_canvas != null) 
        {
            _canvas.graphics.clear();
        }
        setLabel("Display Cleared");
        debug('Display cleared');
    }

    public function clearAll():Void 
    {
        if (_oscAtom != null) 
        {
            _oscAtom.clearBuffer();
        }
        clearDisplay();
        debug('Buffer and display cleared');
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        _canvas = null;
        _grid = null;
        _mask = null;
        _label = null;
        _debugLabel = null;
        _oscAtom = null;
        super.dispose();
    }
}