package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Contact;
import library.drivers.SignalGenerator;

/**
 * SIGNAL GENERATOR WIDGET v1.0
 * Интерактивная панель управления генератором сигналов.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * SignalGeneratorWidget - это ЛИЦО (Face) для SignalGeneratorAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SignalGeneratorWidget                                                 │
 * │                                                                         │
 * │   ┌───────────────────────────────────────────────────────────────┐     │
 * │   │  ┌─────────────────────────────────────────────────────────┐  │     │
 * │   │  │  [Title: Signal Generator]                     [LED]    │  │     │
 * │   │  ├─────────────────────────────────────────────────────────┤  │     │
 * │   │  │                                                         │  │     │
 * │   │  │  FREQUENCY: [████████████░░░░] 440.0 Hz     [-] [+]     │  │     │
 * │   │  │                                                         │  │     │
 * │   │  │  QUANTUM:   [████░░░░░░░░░░░░] 0.10         [-] [+]     │  │     │
 * │   │  │                                                         │  │     │
 * │   │  │  MODE:  [OFF][SIN][SQR][SAW][TRI][NOI]                  │  │     │
 * │   │  │         ════ ════ ════ ════ ════ ════                   │  │     │
 * │   │  │                      ^ Active                           │  │     │
 * │   │  │                                                         │  │     │
 * │   │  │  ┌─────────────────────────────────────────────────┐    │  │     │
 * │   │  │  │  OUTPUT: +0.50                                  │    │  │     │
 * │   │  │  │  PULSES: 1234                                   │    │  │     │
 * │   │  │  └─────────────────────────────────────────────────┘    │  │     │
 * │   │  │                                                         │  │     │
 * │   │  └─────────────────────────────────────────────────────────┘  │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget ЧИТАЕТ состояние из контактов атома (Databank)                 │
 * │   Widget ПИШЕТ в контакты при взаимодействии с пользователем            │
 * │   Виджет синхронизируется с изменениями контактов автоматически         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * ЭЛЕМЕНТЫ УПРАВЛЕНИЯ:
 * ───────────────────
 * 1. Слайдеры частоты и квантования (визуализация + перетаскивание)
 * 2. Кнопки +/- для точной настройки
 * 3. Переключатели режимов генерации
 * 4. Индикатор активности (LED)
 * 5. Дисплей текущего значения и статистики
 */
class SignalGeneratorWidget extends DeviceView {

    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================

    private static inline var MIN_FREQ:Float = 0.1;
    private static inline var MAX_FREQ:Float = 20000.0;
    private static inline var MIN_QUANTUM:Float = 0.001;
    private static inline var MAX_QUANTUM:Float = 1.0;

    // =========================================================================
    // UI КОМПОНЕНТЫ
    // =========================================================================

    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;

    // Частота
    private var _freqLabel:TextField;
    private var _freqValue:TextField;
    private var _freqSlider:SliderControl;
    private var _freqMinusBtn:Sprite;
    private var _freqPlusBtn:Sprite;

    // Квантование
    private var _quantumLabel:TextField;
    private var _quantumValue:TextField;
    private var _quantumSlider:SliderControl;
    private var _quantumMinusBtn:Sprite;
    private var _quantumPlusBtn:Sprite;

    // Режимы
    private var _modeLabel:TextField;
    private var _modeButtons:Array<Sprite>;

    // Вывод
    private var _outputDisplay:Sprite;
    private var _outputValueField:TextField;
    private var _pulseCountField:TextField;

    // Индикатор
    private var _led:Sprite;
    private var _ledGlow:Sprite;

    // =========================================================================
    // КОНФИГУРАЦИЯ
    // =========================================================================

    public var widgetWidth:Float = 280;
    public var widgetHeight:Float = 280;

    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorAccent:Int = 0x00AAFF;
    private var _colorActive:Int = 0x00FF88;
    private var _colorInactive:Int = 0x333344;
    private var _colorText:Int = 0xFFFFFF;

    // =========================================================================
    // СОСТОЯНИЕ
    // =========================================================================

    private var _genAtom:SignalGenerator;
    private var _freqContact:Contact;
    private var _quantumContact:Contact;
    private var _modeContact:Contact;
    private var _outContact:Contact;
    private var _changedContact:Contact;

    private var _ledPulseTimer:Float = 0;
    private var _ledPulseDuration:Float = 0.1;

    // =========================================================================
    // КОНСТРУКТОР
    // =========================================================================

    public function new(atom:Atom) {
        super(atom);

        if (Std.isOfType(atom, SignalGenerator)) {
            _genAtom = cast(atom, SignalGenerator);
        }

        // Находим контакты
        findContacts();

        // Строим UI
        buildUI();

        // Синхронизируем начальное состояние
        syncFromAtom();
    }

    // =========================================================================
    // ИНИЦИАЛИЗАЦИЯ
    // =========================================================================

    private function findContacts():Void {
        if (atom != null) {
            _freqContact = atom.getInput("freq");
            _quantumContact = atom.getInput("quantum");
            _modeContact = atom.getInput("mode");
            _outContact = atom.getOutput("out");
            _changedContact = atom.getOutput("changed");
        }
    }

    override private function onActivate():Void {
        findContacts();
        syncFromAtom();
    }

    private function buildUI():Void {
        // === ФОН ===
        _bg = new Sprite();
        addChild(_bg);

        // === ЗАГОЛОВОК ===
        _header = new Sprite();
        addChild(_header);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 14, _colorText, true);
        _titleLabel.text = "  SIGNAL GENERATOR";
        _titleLabel.width = widgetWidth - 30;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // === LED ИНДИКАТОР ===
        _led = new Sprite();
        _led.graphics.beginFill(0x003300);
        _led.graphics.drawCircle(0, 0, 6);
        _led.graphics.endFill();
        _led.x = widgetWidth - 18;
        _led.y = 14;
        _header.addChild(_led);

        _ledGlow = new Sprite();
        _ledGlow.graphics.beginFill(0x00FF00, 0.3);
        _ledGlow.graphics.drawCircle(0, 0, 10);
        _ledGlow.graphics.endFill();
        _ledGlow.x = _led.x;
        _ledGlow.y = _led.y;
        _ledGlow.visible = false;
        _header.addChild(_ledGlow);

        // === СЕКЦИЯ ЧАСТОТЫ ===
        var yPos = 40;

        _freqLabel = createLabel("FREQUENCY (Hz)");
        _freqLabel.y = yPos;
        addChild(_freqLabel);
        yPos += 20;

        _freqSlider = new SliderControl(widgetWidth - 80, 20, MIN_FREQ, MAX_FREQ, true);
        _freqSlider.x = 10;
        _freqSlider.y = yPos;
        _freqSlider.onChange = onFreqSliderChange;
        addChild(_freqSlider);
        yPos += 24;

        _freqValue = createValueField("440.0");
        _freqValue.x = 10;
        _freqValue.y = yPos;
        addChild(_freqValue);

        _freqMinusBtn = createButton("-", 0x335566, onFreqMinus);
        _freqMinusBtn.x = widgetWidth - 60;
        _freqMinusBtn.y = yPos - 2;
        addChild(_freqMinusBtn);

        _freqPlusBtn = createButton("+", 0x336655, onFreqPlus);
        _freqPlusBtn.x = widgetWidth - 30;
        _freqPlusBtn.y = yPos - 2;
        addChild(_freqPlusBtn);

        yPos += 35;

        // === СЕКЦИЯ КВАНТОВАНИЯ ===
        _quantumLabel = createLabel("QUANTUM STEP");
        _quantumLabel.y = yPos;
        addChild(_quantumLabel);
        yPos += 20;

        _quantumSlider = new SliderControl(widgetWidth - 80, 20, MIN_QUANTUM, MAX_QUANTUM, false);
        _quantumSlider.x = 10;
        _quantumSlider.y = yPos;
        _quantumSlider.onChange = onQuantumSliderChange;
        addChild(_quantumSlider);
        yPos += 24;

        _quantumValue = createValueField("0.10");
        _quantumValue.x = 10;
        _quantumValue.y = yPos;
        addChild(_quantumValue);

        _quantumMinusBtn = createButton("-", 0x335566, onQuantumMinus);
        _quantumMinusBtn.x = widgetWidth - 60;
        _quantumMinusBtn.y = yPos - 2;
        addChild(_quantumMinusBtn);

        _quantumPlusBtn = createButton("+", 0x336655, onQuantumPlus);
        _quantumPlusBtn.x = widgetWidth - 30;
        _quantumPlusBtn.y = yPos - 2;
        addChild(_quantumPlusBtn);

        yPos += 40;

        // === СЕКЦИЯ РЕЖИМОВ ===
        _modeLabel = createLabel("MODE");
        _modeLabel.y = yPos;
        addChild(_modeLabel);
        yPos += 22;

        createModeButtons(yPos);
        yPos += 35;

        // === ДИСПЛЕЙ ВЫВОДА ===
        _outputDisplay = new Sprite();
        _outputDisplay.y = yPos;
        addChild(_outputDisplay);

        _outputValueField = new TextField();
        _outputValueField.defaultTextFormat = new TextFormat("_typewriter", 18, _colorActive, true, null, null, null, null, TextFormatAlign.CENTER);
        _outputValueField.text = "+0.000";
        _outputValueField.width = widgetWidth - 20;
        _outputValueField.height = 30;
        _outputValueField.x = 10;
        _outputValueField.selectable = false;
        _outputDisplay.addChild(_outputValueField);

        _pulseCountField = new TextField();
        _pulseCountField.defaultTextFormat = new TextFormat("_typewriter", 10, 0x888888);
        _pulseCountField.text = "Pulses: 0";
        _pulseCountField.width = widgetWidth - 20;
        _pulseCountField.height = 15;
        _pulseCountField.x = 10;
        _pulseCountField.y = 30;
        _pulseCountField.selectable = false;
        _outputDisplay.addChild(_pulseCountField);

        // Отрисовка фона
        redrawBackground();
    }

    private function redrawBackground():Void {
        // Основной фон
        _bg.graphics.clear();
        _bg.graphics.beginFill(_colorBg, 0.95);
        _bg.graphics.lineStyle(1, _colorAccent);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _bg.graphics.endFill();

        // Заголовок
        _header.graphics.clear();
        _header.graphics.beginFill(_colorHeader);
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 28, 8, 8, 0, 0);
        _header.graphics.endFill();

        // Дисплей вывода
        _outputDisplay.graphics.clear();
        _outputDisplay.graphics.beginFill(0x000000, 0.5);
        _outputDisplay.graphics.lineStyle(1, 0x333344);
        _outputDisplay.graphics.drawRoundRect(5, 0, widgetWidth - 10, 50, 4, 4);
        _outputDisplay.graphics.endFill();
    }

    // =========================================================================
    // СОЗДАНИЕ UI ЭЛЕМЕНТОВ
    // =========================================================================

    private function createLabel(text:String):TextField {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 10, 0x888888);
        tf.text = text;
        tf.width = widgetWidth - 20;
        tf.height = 18;
        tf.x = 10;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createValueField(text:String):TextField {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 12, _colorAccent, true);
        tf.text = text;
        tf.width = 80;
        tf.height = 20;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createButton(label:String, color:Int, callback:MouseEvent -> Void):Sprite {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRoundRect(0, 0, 24, 20, 3, 3);
        btn.graphics.endFill();

        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_sans", 14, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label;
        tf.width = 24;
        tf.height = 20;
        tf.selectable = false;
        tf.mouseEnabled = false;
        btn.addChild(tf);

        btn.buttonMode = true;
        btn.useHandCursor = true;
        btn.addEventListener(MouseEvent.CLICK, callback);

        return btn;
    }

    private function createModeButtons(yPos:Float):Void {
        _modeButtons = [];

        var modes = [
            { id: 0, label: "OFF", color: 0x666666 },
            { id: 3, label: "SIN", color: 0x3366AA },
            { id: 1, label: "SQR", color: 0x3366AA },
            { id: 2, label: "SAW", color: 0x3366AA },
            { id: 4, label: "TRI", color: 0x3366AA },
            { id: 5, label: "NOI", color: 0x3366AA }
        ];

        var btnWidth = 40;
        var spacing = 5;
        var startX = 10;

        for (i in 0...modes.length) {
            var mode = modes[i];
            var btn = new Sprite();

            btn.graphics.beginFill(mode.color);
            btn.graphics.drawRoundRect(0, 0, btnWidth, 24, 3, 3);
            btn.graphics.endFill();

            var tf = new TextField();
            tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
            tf.text = mode.label;
            tf.width = btnWidth;
            tf.height = 24;
            tf.selectable = false;
            tf.mouseEnabled = false;
            btn.addChild(tf);

            btn.x = startX + i * (btnWidth + spacing);
            btn.y = yPos;
            btn.buttonMode = true;
            btn.useHandCursor = true;

            // Сохраняем ID режима в userData спрайта
            btn.name = Std.string(mode.id);
            btn.addEventListener(MouseEvent.CLICK, onModeClick);

            addChild(btn);
            _modeButtons.push(btn);
        }
    }

    // =========================================================================
    // СИНХРОНИЗАЦИЯ С АТОМОМ
    // =========================================================================

    override private function syncFromAtom():Void {
        if (_freqContact != null && _freqContact.value != null) {
            updateFreqUI(_freqContact.value);
        }

        if (_quantumContact != null && _quantumContact.value != null) {
            updateQuantumUI(_quantumContact.value);
        }

        if (_modeContact != null && _modeContact.value != null) {
            updateModeUI(Std.int(_modeContact.value));
        }

        if (_outContact != null && _outContact.value != null) {
            updateOutputDisplay(_outContact.value);
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed) return;

        if (contact == _freqContact) {
            updateFreqUI(newValue);
        }
        else if (contact == _quantumContact) {
            updateQuantumUI(newValue);
        }
        else if (contact == _modeContact) {
            updateModeUI(Std.int(newValue));
        }
        else if (contact == _outContact) {
            updateOutputDisplay(newValue);
        }
        else if (contact == _changedContact) {
            if (newValue == true) {
                pulseLed();
                updatePulseCount();
            }
        }
    }

    // =========================================================================
    // ОБНОВЛЕНИЕ UI
    // =========================================================================

    private function updateFreqUI(value:Dynamic):Void {
        var freq = parseFloat(value, 440.0);
        _freqValue.text = formatFrequency(freq);
        _freqSlider.value = freq;
    }

    private function updateQuantumUI(value:Dynamic):Void {
        var quantum = parseFloat(value, 0.1);
        _quantumValue.text = formatQuantum(quantum);
        _quantumSlider.value = quantum;
    }

    private function updateModeUI(mode:Int):Void {
        for (btn in _modeButtons) {
            var btnMode = Std.parseInt(btn.name);
            if (btnMode == mode) {
                // Активный режим
                btn.graphics.clear();
                btn.graphics.beginFill(_colorActive);
                btn.graphics.drawRoundRect(0, 0, 40, 24, 3, 3);
                btn.graphics.endFill();
                btn.graphics.lineStyle(2, 0x00FF88);
                btn.graphics.drawRoundRect(0, 0, 40, 24, 3, 3);
            }
            else {
                // Неактивный режим
                btn.graphics.clear();
                btn.graphics.beginFill(_colorInactive);
                btn.graphics.drawRoundRect(0, 0, 40, 24, 3, 3);
                btn.graphics.endFill();
            }
        }
    }

    private function updateOutputDisplay(value:Dynamic):Void {
        var v = parseFloat(value, 0.0);
        var sign = v >= 0 ? "+" : "";
        _outputValueField.text = sign + formatValue(v, 3);
    }

    private function updatePulseCount():Void {
        if (_genAtom != null) {
            var count = _genAtom.getPulseCount();
            _pulseCountField.text = 'Pulses: $count';
        }
    }

    private function pulseLed():Void {
        _ledPulseTimer = _ledPulseDuration;
        _ledGlow.visible = true;
        _led.graphics.clear();
        _led.graphics.beginFill(0x00FF00);
        _led.graphics.drawCircle(0, 0, 6);
        _led.graphics.endFill();
    }

    // =========================================================================
    // ОБРАБОТЧИКИ СОБЫТИЙ
    // =========================================================================

    // --- Частота ---

    private function onFreqSliderChange(value:Float):Void {
        if (_freqContact != null) {
            _freqContact.value = value;
        }
    }

    private function onFreqMinus(e:MouseEvent):Void {
        if (_freqContact == null) return;
        var current = parseFloat(_freqContact.value, 440.0);
        var step = getFrequencyStep(current);
        var newValue = Math.max(MIN_FREQ, current - step);
        _freqContact.value = newValue;
    }

    private function onFreqPlus(e:MouseEvent):Void {
        if (_freqContact == null) return;
        var current = parseFloat(_freqContact.value, 440.0);
        var step = getFrequencyStep(current);
        var newValue = Math.min(MAX_FREQ, current + step);
        _freqContact.value = newValue;
    }

    // --- Квантование ---

    private function onQuantumSliderChange(value:Float):Void {
        if (_quantumContact != null) {
            _quantumContact.value = value;
        }
    }

    private function onQuantumMinus(e:MouseEvent):Void {
        if (_quantumContact == null) return;
        var current = parseFloat(_quantumContact.value, 0.1);
        var step = getQuantumStep(current);
        var newValue = Math.max(MIN_QUANTUM, current - step);
        _quantumContact.value = newValue;
    }

    private function onQuantumPlus(e:MouseEvent):Void {
        if (_quantumContact == null) return;
        var current = parseFloat(_quantumContact.value, 0.1);
        var step = getQuantumStep(current);
        var newValue = Math.min(MAX_QUANTUM, current + step);
        _quantumContact.value = newValue;
    }

    // --- Режим ---

    private function onModeClick(e:MouseEvent):Void {
        if (_modeContact == null) return;
        var btn = cast(e.currentTarget, Sprite);
        var mode = Std.parseInt(btn.name);
        _modeContact.value = mode;
    }

    // =========================================================================
    // ОБНОВЛЕНИЕ (для анимации LED)
    // =========================================================================

    override public function activate():Void {
        super.activate();
        // Подписываемся на ENTER_FRAME для анимации LED
        if (stage != null) {
            stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
        } else {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
    }

    override public function deactivate():Void {
        super.deactivate();
        if (stage != null) {
            stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        }
    }

    private function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function onEnterFrame(e:Event):Void {
        // Анимация затухания LED
        if (_ledPulseTimer > 0) {
            _ledPulseTimer -= 1 / 60;

            if (_ledPulseTimer <= 0) {
                _ledPulseTimer = 0;
                _ledGlow.visible = false;
                _led.graphics.clear();
                _led.graphics.beginFill(0x003300);
                _led.graphics.drawCircle(0, 0, 6);
                _led.graphics.endFill();
            }
        }
    }

    // =========================================================================
    // ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
    // =========================================================================

    private function parseFloat(value:Dynamic, defaultValue:Float):Float {
        if (value == null) return defaultValue;
        if (Std.isOfType(value, Float)) return cast(value, Float);
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        return defaultValue;
    }

    private function formatFrequency(freq:Float):String {
        if (freq >= 1000) {
            return Std.string(Math.round(freq * 10) / 10);
        }
        return Std.string(Math.round(freq * 100) / 100);
    }

    private function formatQuantum(q:Float):String {
        return Std.string(Math.round(q * 1000) / 1000);
    }

    private function formatValue(v:Float, decimals:Int):String {
        var mult = Math.pow(10, decimals);
        return Std.string(Math.round(v * mult) / mult);
    }

    private function getFrequencyStep(current:Float):Float {
        // Адаптивный шаг: чем выше частота, тем больше шаг
        if (current < 100) return 1;
        if (current < 1000) return 10;
        if (current < 10000) return 100;
        return 1000;
    }

    private function getQuantumStep(current:Float):Float {
        // Адаптивный шаг квантования
        if (current < 0.01) return 0.001;
        if (current < 0.1) return 0.01;
        return 0.05;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        if (stage != null) {
            stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        }

        // Удаляем слушатели кнопок
        if (_freqMinusBtn != null) _freqMinusBtn.removeEventListener(MouseEvent.CLICK, onFreqMinus);
        if (_freqPlusBtn != null) _freqPlusBtn.removeEventListener(MouseEvent.CLICK, onFreqPlus);
        if (_quantumMinusBtn != null) _quantumMinusBtn.removeEventListener(MouseEvent.CLICK, onQuantumMinus);
        if (_quantumPlusBtn != null) _quantumPlusBtn.removeEventListener(MouseEvent.CLICK, onQuantumPlus);

        for (btn in _modeButtons) {
            btn.removeEventListener(MouseEvent.CLICK, onModeClick);
        }

        _freqSlider = null;
        _quantumSlider = null;
        _genAtom = null;
        _freqContact = null;
        _quantumContact = null;
        _modeContact = null;
        _outContact = null;
        _changedContact = null;

        super.dispose();
    }
}

// =============================================================================
// ВСПОМОГАТЕЛЬНЫЙ КЛАСС: SLIDER CONTROL
// =============================================================================

/**
 * Простой слайдер для управления параметрами.
 */
class SliderControl extends Sprite {

    public var value(default, set):Float = 0;
    public var min:Float = 0;
    public var max:Float = 100;
    public var logarithmic:Bool = false;

    public var onChange:Float -> Void = null;

    private var _track:Sprite;
    private var _fill:Sprite;
    private var _handle:Sprite;
    private var _width:Float;
    private var _height:Float;

    private var _dragging:Bool = false;

    public function new(width:Float, height:Float, min:Float, max:Float, logarithmic:Bool = false) {
        super();

        this._width = width;
        this._height = height;
        this.min = min;
        this.max = max;
        this.logarithmic = logarithmic;

        buildUI();
    }

    private function buildUI():Void {
        // Трек
        _track = new Sprite();
        _track.graphics.beginFill(0x333344);
        _track.graphics.drawRoundRect(0, 0, _width, _height, 4, 4);
        _track.graphics.endFill();
        addChild(_track);

        // Заполнение
        _fill = new Sprite();
        _fill.graphics.beginFill(0x00AAFF);
        _fill.graphics.drawRoundRect(0, 0, _width, _height, 4, 4);
        _fill.graphics.endFill();
        addChild(_fill);

        // Ручка (опционально, сейчас просто кликабельный трек)

        buttonMode = true;
        useHandCursor = true;

        addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
    }

    private function onMouseDown(e:MouseEvent):Void {
        _dragging = true;
        updateFromMouse();

        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_dragging) {
            updateFromMouse();
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        _dragging = false;

        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
    }

    private function updateFromMouse():Void {
        var localX = mouseX;
        var ratio = localX / _width;
        ratio = Math.max(0, Math.min(1, ratio));

        if (logarithmic) {
            // Логарифмическая шкала для частоты
            var logMin = Math.log(min);
            var logMax = Math.log(max);
            value = Math.exp(logMin + ratio * (logMax - logMin));
        }
        else {
            value = min + ratio * (max - min);
        }

        if (onChange != null) {
            onChange(value);
        }
    }

    private function set_value(v:Float):Float {
        value = v;

        // Обновляем визуал
        var ratio:Float;
        if (logarithmic) {
            var logMin = Math.log(min);
            var logMax = Math.log(max);
            var logVal = Math.log(Math.max(min, v));
            ratio = (logVal - logMin) / (logMax - logMin);
        }
        else {
            ratio = (v - min) / (max - min);
        }

        ratio = Math.max(0, Math.min(1, ratio));
        _fill.scaleX = ratio;

        return value;
    }
}