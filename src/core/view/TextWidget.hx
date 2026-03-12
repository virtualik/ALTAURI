package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.FocusEvent;
import core.base.Atom;
import core.base.Contact;

/**
 * TEXT WIDGET v1.0
 * Текстовое поле для отображения и редактирования значения.
 * 
 * - Отображает значение контакта
 * - При редактировании отправляет новое значение
 */
class TextWidget extends DeviceView {

    private var _input:TextField;
    private var _labelField:TextField;
    private var _contact:Contact;
    
    private var _isEditing:Bool = false;

    // Настройки (переименованы, т.к. width/height уже есть в DisplayObject)
    public var widgetWidth:Float = 150;
    public var widgetHeight:Float = 30;
    public var editable:Bool = true;
    public var isInput:Bool = true;  // true = input contact, false = output contact
    public var contactName:String = "value";
    
    public function new(atom:Atom, ?contactName:String = "value", ?isInput:Bool = true) {
        super(atom);
        
        this.contactName = contactName;
        this.isInput = isInput;
        
        buildUI();
    }
    
    private function buildUI():Void {
        // Метка названия
        _labelField = new TextField();
        _labelField.width = widgetWidth;
        _labelField.height = 18;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        
        var labelFmt = new TextFormat("_sans", 10, 0x888888);
        _labelField.defaultTextFormat = labelFmt;
        _labelField.text = atom != null ? atom.name : "Value";
        addChild(_labelField);
        
        // Поле ввода/отображения
        _input = new TextField();
        _input.y = 20;
        _input.width = widgetWidth;
        _input.height = widgetHeight;
        _input.border = true;
        _input.borderColor = 0x00AAFF;
        _input.background = true;
        _input.backgroundColor = 0x222233;
        _input.textColor = 0xFFFFFF;
        _input.selectable = true;
        _input.mouseEnabled = true;
        
        if (editable) {
            _input.type = TextFieldType.INPUT;
            _input.addEventListener(Event.CHANGE, onInputChange);
            _input.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            _input.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        }
        
        var inputFmt = new TextFormat("_typewriter", 14, 0xFFFFFF);
        _input.defaultTextFormat = inputFmt;
        
        addChild(_input);
        
        updateFromContact();
    }
    
    override private function onActivate():Void {
        // Находим контакт
        if (atom != null) {
            if (isInput) {
                _contact = atom.getInput(contactName);
            } else {
                _contact = atom.getOutput(contactName);
            }
        }
        
        updateFromContact();
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _contact && !_isEditing) {
            updateFromContact();
        }
    }
    
    private function onFocusIn(e:FocusEvent):Void {
        _isEditing = true;
    }
    
    private function onFocusOut(e:FocusEvent):Void {
        _isEditing = false;
        pushValue();
    }
    
    private function onInputChange(e:Event):Void {
        // Можно добавить валидацию здесь
    }
    
    private function pushValue():Void {
        if (_contact == null) return;
        
        var textVal = _input.text;
        
        // Пытаемся распарсить число
        var floatVal = Std.parseFloat(textVal);
        if (!Math.isNaN(floatVal)) {
            _contact.value = floatVal;
            return;
        }
        
        // Булево
        if (textVal.toLowerCase() == "true") {
            _contact.value = true;
            return;
        }
        if (textVal.toLowerCase() == "false") {
            _contact.value = false;
            return;
        }
        
        // Строка
        _contact.value = textVal;
    }
    
    private function updateFromContact():Void {
        if (_contact == null || _isEditing) return;
        
        var v = _contact.value;
        var str = "null";
        
        if (v == null) {
            str = "null";
        } else if (Std.isOfType(v, Bool)) {
            str = cast(v, Bool) ? "true" : "false";
        } else if (Std.isOfType(v, Float)) {
            // Форматируем число
            var f = cast(v, Float);
            if (Math.abs(f) < 0.001 || Math.abs(f) > 10000) {
                str = Std.string(f);
            } else {
                str = Std.string(Math.round(f * 1000) / 1000);
            }
        } else {
            str = Std.string(v);
        }
        
        if (_input.text != str) {
            _input.text = str;
        }
    }
    
    override public function dispose():Void {
        if (_input != null && editable) {
            _input.removeEventListener(Event.CHANGE, onInputChange);
            _input.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            _input.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        }
        _input = null;
        _contact = null;
        _labelField = null;
        super.dispose();
    }
}
