package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;

/**
 * TOGGLE WIDGET v1.0
 * Кнопка-переключатель с двумя состояниями.
 * 
 * При клике меняет состояние и отправляет значение в контакт.
 */
class ToggleWidget extends DeviceView {

    private var _btn:Sprite;
    private var _labelField:TextField;
    private var _stateField:TextField;
    private var _contact:Contact;
    
    private var _currentState:Bool = false;
    
    // Настройки (переименованы, т.к. width/height уже есть в DisplayObject)
    public var widgetWidth:Float = 80;
    public var widgetHeight:Float = 30;
    public var colorOn:Int = 0x448844;
    public var colorOff:Int = 0x444444;
    public var colorOver:Int = 0x555555;
    public var labelOn:String = "ON";
    public var labelOff:String = "OFF";
    public var initialState:Bool = false;
    
    public function new(atom:Atom, contactName:String = "out") {
        super(atom);
        
        // Находим контакт для управления
        if (atom != null) {
            _contact = atom.getOutput(contactName);
            if (_contact == null) _contact = atom.getInput(contactName);
        }
        
        // Начальное состояние
        _currentState = initialState;
        
        buildUI();
    }
    
    private function buildUI():Void {
        // Кнопка
        _btn = new Sprite();
        _btn.buttonMode = true;
        _btn.useHandCursor = true;
        _btn.addEventListener(MouseEvent.CLICK, onClick);
        _btn.addEventListener(MouseEvent.MOUSE_OVER, onOver);
        _btn.addEventListener(MouseEvent.MOUSE_OUT, onOut);
        addChild(_btn);
        
        // Метка состояния
        _stateField = new TextField();
        _stateField.width = widgetWidth;
        _stateField.height = widgetHeight;
        _stateField.selectable = false;
        _stateField.mouseEnabled = false;
        
        var fmt = new TextFormat("_sans", 14, 0xFFFFFF, true);
        fmt.align = TextFormatAlign.CENTER;
        _stateField.defaultTextFormat = fmt;
        addChild(_stateField);
        
        // Подпись снизу
        _labelField = new TextField();
        _labelField.width = widgetWidth;
        _labelField.height = 20;
        _labelField.y = widgetHeight + 5;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        
        var fmt2 = new TextFormat("_sans", 10, 0x888888);
        fmt2.align = TextFormatAlign.CENTER;
        _labelField.defaultTextFormat = fmt2;
        _labelField.text = atom != null ? atom.name : "Toggle";
        addChild(_labelField);
        
        updateVisual();
    }
    
    override private function onActivate():Void {
        // Считываем текущее значение из контакта
        if (_contact != null && _contact.value != null) {
            _currentState = cast(_contact.value, Bool);
        }
        updateVisual();
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _contact) {
            if (Std.isOfType(newValue, Bool)) {
                _currentState = cast(newValue, Bool);
                updateVisual();
            }
        }
    }
    
    private function onClick(e:MouseEvent):Void {
        _currentState = !_currentState;
        
        // Отправляем значение в контакт
        if (_contact != null) {
            _contact.value = _currentState;
        }
        
        updateVisual();
    }
    
    private function onOver(e:MouseEvent):Void {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorOver);
        _btn.graphics.lineStyle(2, 0x666666);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();
    }
    
    private function onOut(e:MouseEvent):Void {
        updateVisual();
    }
    
    private function updateVisual():Void {
        var color = _currentState ? colorOn : colorOff;
        
        _btn.graphics.clear();
        _btn.graphics.beginFill(color);
        _btn.graphics.lineStyle(2, _currentState ? 0x66AA66 : 0x555555);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();
        
        _stateField.text = _currentState ? labelOn : labelOff;
    }
    
    override public function dispose():Void {
        if (_btn != null) {
            _btn.removeEventListener(MouseEvent.CLICK, onClick);
            _btn.removeEventListener(MouseEvent.MOUSE_OVER, onOver);
            _btn.removeEventListener(MouseEvent.MOUSE_OUT, onOut);
        }
        _btn = null;
        _contact = null;
        _labelField = null;
        _stateField = null;
        super.dispose();
    }
}
