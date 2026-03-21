package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;
import library.electro.OscilloscopeAtom;

/**
 * OSCILLOSCOPE WIDGET v2.0 (Databank Architecture)
 * Real-time signal visualization widget.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * OscilloscopeWidget - это ЛИЦО (Face) OscilloscopeAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeWidget НЕ ХРАНИТ ДАННЫЕ!                                  │
 * │                                                                         │
 * │   OscilloscopeWidget:                                                   │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │   ССЫЛКИ:                                                       │   │
 * │   │   - atom:OscilloscopeAtom  // Ссылка на Databank                │   │
 * │   │   - _oscAtom:OscilloscopeAtom  // Типизированная ссылка         │   │
 * │   │                                                                 │   │
 * │   │   UI КОМПОНЕНТЫ:                                                │   │
 * │   │   - _canvas:Sprite   // Область отрисовки                       │   │
 * │   │   - _grid:Sprite     // Сетка                                   │   │
 * │   │   - _label:TextField // Метка                                   │   │
 * │   │   - _debugLabel:TextField // Отладка                            │   │
 * │   │                                                                 │   │
 * │   │   НАСТРОЙКИ:                                                    │   │
 * │   │   - widgetWidth:Float = 300                                     │   │
 * │   │   - widgetHeight:Float = 150                                    │   │
 * │   │   - colorLine:Int = 0x00FF00                                    │   │
 * │   │                                                                 │   │
 * │   │   THROTTLING (UI-only state):                                   │   │
 * │   │   - _lastDrawTime:Float  // Для ограничения FPS отрисовки       │   │
 * │   │   - DRAW_INTERVAL:Float = 1/30   // 30 FPS max                  │   │
 * │   │                                                                 │   │
 * │   │   ЧТЕНИЕ ДАННЫХ:                                                │   │
 * │   │   var buffer = _oscAtom.getBuffer();                            │   │
 * │   │   var idx = _oscAtom.getWriteIndex();                           │   │
 * │   │   var count = _oscAtom.getSamplesCollected();                   │   │
 * │   │   drawWave(buffer, idx, count);                                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   ИСТОЧНИК ДАННЫХ:                                                      │
 * │   ─────────────────                                                     │
 * │   OscilloscopeAtom._buffer → единственный источник истины               │
 * │                                                                         │
 * │   HEADLESS MODE:                                                        │
 * │   ──────────────                                                        │
 * │   Атом продолжает работать, виджет не нужен.                            │
 * │   При создании виджета - он читает актуальное состояние атома.          │
 * │                                                                         │
 * │   SINGLETON:                                                            │
 * │   ──────────                                                            │
 * │   DeviceViewRegistry гарантирует один виджет на атом.                   │
 * │   Виджет перемещается между NodeView и DeviceWindow.                    │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.0 Changes:
 * - COMPLETE REWRITE: Buffer moved to OscilloscopeAtom
 * - Widget reads from atom's Databank via getBuffer(), getWriteIndex()
 * - Multiple widgets see the SAME data (same atom = same buffer)
 * - Works with DeviceViewRegistry for singleton pattern
 * - Closing/reopening DeviceWindow preserves data (in atom)
 *
 * v5.1 (Old):
 * - Widget had its own buffer
 * - Data was lost when widget closed
 * - Multiple widgets had different buffers
 */
class OscilloscopeWidget extends DeviceView {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 150;
    public var colorLine:Int = 0x00FF00;
    public var colorBg:Int = 0x0a0a12;
    public var colorGrid:Int = 0x1a2a1a;

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _label:TextField;
    private var _debugLabel:TextField;

    // =========================================================================
    // REFERENCE TO DATABANK
    // =========================================================================

    /**
     * Typed reference to OscilloscopeAtom.
     * This is our Databank - the single source of truth.
     */
    private var _oscAtom:OscilloscopeAtom;

    // =========================================================================
    // THROTTLING (UI-only state)
    // =========================================================================

    /**
     * Time of last draw.
     * Used to throttle redraws to 30 FPS max.
     */
    private var _lastDrawTime:Float = 0;

    /**
     * Minimum interval between redraws.
     * 1/30 = 30 FPS max for performance.
     */
    private static inline var DRAW_INTERVAL:Float = 1.0 / 120.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom, contactName:String = "in") {
        super(atom);

        // Get typed reference to Databank
        if (Std.isOfType(atom, OscilloscopeAtom)) {
            _oscAtom = cast(atom, OscilloscopeAtom);
        }

        // Build UI
        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================

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

    // =========================================================================
    // LIFECYCLE
    // =========================================================================

    override private function onActivate():Void {
        // Sync current state from atom's Databank
        syncFromAtom();
        debug('Activated - reading from Databank');
    }

    override private function syncFromAtom():Void {
        // This is called on activate() to show current atom state
        redrawFromAtom();
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================

    /**
     * Called when contact value changes.
     * This is our notification that new data arrived.
     *
     * We don't store the data - just trigger a redraw.
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed || _oscAtom == null) return;

        // Throttle redraws
        var now = haxe.Timer.stamp();
        if (now - _lastDrawTime < DRAW_INTERVAL) return;
        _lastDrawTime = now;

        // Redraw from atom's Databank
        redrawFromAtom();

        // Update debug label periodically
        if (_oscAtom.getTotalSamples() % 60 == 0) {
            debug('Sample #${_oscAtom.getTotalSamples()}');
        }
    }

    /**
     * Redraw the waveform from atom's Databank.
     *
     * This is the CORE method - reads data from atom and draws it.
     */
    private function redrawFromAtom():Void {
        if (_oscAtom == null || _canvas == null) return;

        // Read from Databank
        var buffer = _oscAtom.getBuffer();
        var writeIndex = _oscAtom.getWriteIndex();
        var samplesCollected = _oscAtom.getSamplesCollected();
        var totalSamples = _oscAtom.getTotalSamples();

        // Need at least 2 samples
        if (samplesCollected < 2) {
            setLabel('Collecting: $samplesCollected / ${_oscAtom.getBufferSize()}');
            return;
        }

        // Draw waveform
        drawWave(buffer, writeIndex, samplesCollected);

        // Update label
        setLabel('Samples: $samplesCollected | Total: $totalSamples');
    }

    /**
     * Draw the waveform from buffer data.
     *
     * @param buffer Sample buffer from atom
     * @param writeIndex Current write position
     * @param count Number of valid samples
     */
    private function drawWave(buffer:Array<Float>, writeIndex:Int, count:Int):Void {
        if (_canvas == null || buffer == null) return;

        var g = _canvas.graphics;
        g.clear();

        var displayCount = Std.int(Math.min(count, buffer.length));
        var stepX = widgetWidth / displayCount;
        var centerY = widgetHeight / 2.0;
        var scale = (widgetHeight / 2.0) * 0.9;

        // Determine starting index
        // If buffer is full, start from writeIndex (oldest data)
        // If buffer is filling, start from 0
        var startIdx = (count >= buffer.length) ? writeIndex : 0;

        // Draw waveform
        g.lineStyle(1.5, colorLine, 1.0);

        // First point
        g.moveTo(0, centerY - buffer[startIdx] * scale);

        // Rest of the points
        for (i in 1...displayCount) {
            var idx = (startIdx + i) % buffer.length;
            g.lineTo(i * stepX, centerY - buffer[idx] * scale);
        }
    }

    // =========================================================================
    // UI HELPERS
    // =========================================================================

    private function setLabel(text:String):Void {
        if (_label != null) _label.text = text;
    }

    private function debug(msg:String):Void {
        // trace('[OscilloscopeWidget] $msg');
        if (_debugLabel != null) {
            _debugLabel.text = msg;
        }
    }

    /**
     * Clear the display.
     * Note: This clears the VISUAL only, not the atom's buffer!
     * To clear data, call _oscAtom.clearBuffer() instead.
     */
    public function clearDisplay():Void {
        if (_canvas != null) {
            _canvas.graphics.clear();
        }
        setLabel("Display Cleared");
        debug('Display cleared (atom buffer unchanged)');
    }

    /**
     * Clear both display and atom's buffer.
     */
    public function clearAll():Void {
        if (_oscAtom != null) {
            _oscAtom.clearBuffer();
        }
        clearDisplay();
        debug('Buffer and display cleared');
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        _canvas = null;
        _grid = null;
        _label = null;
        _debugLabel = null;
        _oscAtom = null;

        super.dispose();
    }
}
