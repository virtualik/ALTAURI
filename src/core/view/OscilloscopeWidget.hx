package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
 * OSCILLOSCOPE WIDGET v2.1 (Performance Optimize)
 * Визуализирует массив сэмплов (Array<Float>).
 * Рисует сетку и волну.
 *
 * v2.1 Changes:
 * - Throttling: Max 30 FPS update rate.
 * - Hash check: Skip redraw if data hasn't changed.
 */
class OscilloscopeWidget extends DeviceView {

    private var _canvas:Sprite;
    private var _grid:Sprite;
    private var _label:TextField;
    private var _contact:Contact;

    // Настройки
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 150;
    public var colorLine:Int = 0x00FF00; // Зеленый фосфор
    public var colorBg:Int = 0x0a0a12;   // Темный фон
    public var colorGrid:Int = 0x1a2a1a; // Тусклая сетка

    // PERFORMANCE OPTIMIZATION
    private var _lastUpdateTime:Float = 0;
    private var _lastSampleHash:Int = 0;
    private static inline var UPDATE_INTERVAL:Float = 1.0 / 30.0; // 30 FPS max

    public function new(atom:Atom, contactName:String = "samples") {
        super(atom);

        if (atom != null) {
            // Сначала ищем вход (для OscilloscopeAtom)
            _contact = atom.getInput(contactName);

            // Если входа нет, ищем выход (на случай, если навесим виджет на сам генератор)
            if (_contact == null) {
                _contact = atom.getOutput(contactName);
            }
        }

        buildUI();
    }

    private function buildUI():Void {
        // Фон
        graphics.beginFill(colorBg);
        graphics.lineStyle(3, 0x333355);
        graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
        graphics.endFill();

        // Сетка (рисуется один раз)
        _grid = new Sprite();
        drawGrid();
        addChild(_grid);

        // Холст для волны
        _canvas = new Sprite();
        addChild(_canvas);

        // Подпись
        _label = new TextField();
        _label.width = widgetWidth;
        _label.height = 20;
        _label.y = widgetHeight - 20;
        _label.selectable = false;
        _label.mouseEnabled = false;
        var fmt = new TextFormat("_sans", 10, 0x666688);
        fmt.align = TextFormatAlign.CENTER;
        _label.defaultTextFormat = fmt;
        _label.text = "Waveform";
        addChild(_label);
    }

    private function drawGrid():Void {
        var g = _grid.graphics;
        g.clear();
        g.lineStyle(1, colorGrid, 0.5);

        // Вертикальные линии
        var stepX = widgetWidth / 10;
        for (i in 0...11) {
            var x = i * stepX;
            g.moveTo(x, 0);
            g.lineTo(x, widgetHeight);
        }

        // Горизонтальные линии
        var stepY = widgetHeight / 6;
        for (i in 0...7) {
            var y = i * stepY;
            g.moveTo(0, y);
            g.lineTo(widgetWidth, y);
        }

        // Центральная линия (ось X) - поярче
        g.lineStyle(1, colorGrid, 1.0);
        var centerY = widgetHeight / 2;
        g.moveTo(0, centerY);
        g.lineTo(widgetWidth, centerY);
    }

    // Этот метод вызывается автоматически при изменении данных в контакте
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _contact) {
            if (Std.isOfType(newValue, Array)) {
                // PERFORMANCE: Throttle updates
                var now = haxe.Timer.stamp();
                if (now - _lastUpdateTime < UPDATE_INTERVAL) return;
                
                // PERFORMANCE: Check data change
                var arr:Array<Float> = cast newValue;
                var hash = arr.length > 0 ? Std.int(arr[0] * 1000) : 0; // Простой хэш
                if (hash == _lastSampleHash && arr.length > 0) return; // Данные те же
                
                _lastUpdateTime = now;
                _lastSampleHash = hash;
                
                drawWave(arr);
            }
        }
    }

    /**
     * Рисует волну по переданному массиву сэмплов.
     * @param samples Массив Float значений от -1.0 до 1.0
     */
    private function drawWave(samples:Array<Float>):Void {
        var g = _canvas.graphics;
        g.clear();

        // Если данных нет или мало — выходим
        if (samples == null || samples.length == 0) return;

        // Настройка линии
        g.lineStyle(3.5, colorLine, 0.9);

        // Вычисляем шаг по X
        var stepX:Float = widgetWidth / samples.length;
        var centerY:Float = widgetHeight / 2.0;
        var scale:Float = (widgetHeight / 2.0) * 0.9; // 90% высоты, с отступом

        // Рисуем линию
        for (i in 0...samples.length) {
            var val:Float = samples[i];

            // Защита от выхода за границы
            if (val > 1.0) val = 1.0;
            if (val < -1.0) val = -1.0;

            var x:Float = i * stepX;
            var y:Float = centerY - (val * scale); // -1.0 это низ, 1.0 это верх

            if (i == 0) {
                g.moveTo(x, y);
            } else {
                g.lineTo(x, y);
            }
        }
    }

    override public function dispose():Void {
        _contact = null;
        _canvas = null;
        _grid = null;
        super.dispose();
    }
}