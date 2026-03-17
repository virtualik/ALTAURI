package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType; // <--- IMPORT

/**
 * TEXT INPUT WIDGET v1.1
 * Виджет для ввода текста или чисел.
 * - При потере фокуса или Enter отправляет значение в атом.
 * - Масштабируется при встраивании в ноду.
 * v1.1: Added Impulse on value commit.
 */
class TextInputWidget extends DeviceView {

    private var _inputField:TextField;
    private var _outputContact:Contact;
    private var _setContact:Contact;

    // Настройки размера (для NodeView)
    public var widgetWidth:Float = 120;
    public var widgetHeight:Float = 30;

    public function new(atom:Atom) {
        super(atom);

        // Находим контакты
        _outputContact = atom.getOutput("out");
        _setContact = atom.getInput("set");

        buildUI();
    }

    private function buildUI():Void {
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x00AAFF);
        graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 4, 4);
        graphics.endFill();

        _inputField = new TextField();
        _inputField.type = TextFieldType.INPUT;
        _inputField.width = widgetWidth - 4;
        _inputField.height = widgetHeight - 4;
        _inputField.x = 2;
        _inputField.y = 2;
        _inputField.border = false; // Рамка уже нарисована на спрайте
        _inputField.background = false;
        _inputField.textColor = 0xFFFFFF;
        _inputField.mouseEnabled = true;

        var fmt = new TextFormat("_sans", 12, 0xFFFFFF);
        _inputField.defaultTextFormat = fmt;

        // Устанавливаем начальное значение
        if (_outputContact != null && _outputContact.value != null) {
            _inputField.text = Std.string(_outputContact.value);
        } else {
            _inputField.text = "";
        }

        addChild(_inputField);

        // События
        _inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    }

    private function onFocusOut(e:FocusEvent):Void {
        pushValue();
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ENTER) {
            pushValue();
            // Убираем фокус, чтобы подтвердить ввод
            if (stage != null) stage.focus = null;

            // --- НОВОЕ: Сигнал на сохранение ---
            Impulsys.quickEmit(EventType.VALUE_COMMITTED);
        }
    }

    // Отправляем значение в атом
    private function pushValue():Void {
        if (_outputContact != null) {
            var txt = _inputField.text;
            // Пробуем распарсить число, если похоже на число
            var f = Std.parseFloat(txt);
            if (!Math.isNaN(f) && txt.indexOf(".") != -1 || Std.parseInt(txt) != null && txt.length > 0 && !Math.isNaN(f)) {
                // Если это число, отправляем число
                 _outputContact.value = f;
            } else {
                 _outputContact.value = txt;
            }
        }
    }

    // Реакция на изменения в атоме (например, через вход "set")
    override private function onContactChanged(c:Contact, v:Dynamic):Void {
        if ((c == _outputContact || c == _setContact) && v != null) {
            var str = Std.string(v);
            if (_inputField.text != str) {
                _inputField.text = str;
            }
        }
    }

    override public function dispose():Void {
        if (_inputField != null) {
            _inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        }
        _inputField = null;
        _outputContact = null;
        _setContact = null;
        super.dispose();
    }
}