package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;

/**
 * BUTTON WIDGET v1.0
 * Кнопка для отправки импульса или значения.
 * 
 * - При нажатии отправляет true
 * - При отпускании отправляет false
 */
class ButtonWidget extends DeviceView {

    private var _btn:Sprite;
    private var _labelField:TextField;
    private var _contact:Contact;
    
    private var _isPressed:Bool = false;
    
    // Настройки (переименованы, т.к. width/height уже есть в DisplayObject)
    public var widgetWidth:Float = 80;
    public var widgetHeight:Float = 40;
    public var colorNormal:Int = 0x444455;
    public var colorPressed:Int = 0x4488AA;
    public var colorOver:Int = 0x555566;
    public var label:String = "PUSH";
    
    public function new(atom:Atom, ?contactName:String = "out") {
        super(atom);
        
        // Находим контакт
        if (atom != null) {
            _contact = atom.getOutput(contactName);
            if (_contact == null) _contact = atom.getInput(contactName);
        }
        
        buildUI();
    }
    
    private function buildUI():Void {
        // Кнопка
        _btn = new Sprite();
        _btn.buttonMode = true;
        _btn.useHandCursor = true;
        _btn.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _btn.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        _btn.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
        _btn.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        addChild(_btn);
        
        // Метка
        _labelField = new TextField();
        _labelField.width = widgetWidth;
        _labelField.height = widgetHeight;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        
        var fmt = new TextFormat("_sans", 14, 0xFFFFFF, true);
        fmt.align = TextFormatAlign.CENTER;
        _labelField.defaultTextFormat = fmt;
        _labelField.text = label;
        
        addChild(_labelField);
        
        // Подпись атома
        var nameField = new TextField();
        nameField.width = widgetWidth;
        nameField.height = 18;
        nameField.y = widgetHeight + 5;
        nameField.selectable = false;
        nameField.mouseEnabled = false;
        
        var nameFmt = new TextFormat("_sans", 10, 0x888888);
        nameFmt.align = TextFormatAlign.CENTER;
        nameField.defaultTextFormat = nameFmt;
        nameField.text = atom != null ? atom.name : "Button";
        
        addChild(nameField);
        
        drawNormal();
    }
    
    private function onMouseDown(e:MouseEvent):Void {
        _isPressed = true;
        drawPressed();
        
        if (_contact != null) {
            _contact.value = true;
        }
    }
    
    private function onMouseUp(e:MouseEvent):Void {
        if (_isPressed) {
            _isPressed = false;
            drawNormal();
            
            if (_contact != null) {
                _contact.value = false;
            }
        }
    }
    
    private function onMouseOver(e:MouseEvent):Void {
        if (!_isPressed) {
            drawOver();
        }
    }
    
    private function onMouseOut(e:MouseEvent):Void {
        if (_isPressed) {
            _isPressed = false;
            drawNormal();
            
            if (_contact != null) {
                _contact.value = false;
            }
        } else {
            drawNormal();
        }
    }
    
    private function drawNormal():Void {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorNormal);
        _btn.graphics.lineStyle(2, 0x666677);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }
    
    private function drawPressed():Void {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorPressed);
        _btn.graphics.lineStyle(2, 0x88AACC);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }
    
    private function drawOver():Void {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorOver);
        _btn.graphics.lineStyle(2, 0x777788);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }
    
    override public function dispose():Void {
        if (_btn != null) {
            _btn.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _btn.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _btn.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            _btn.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        }
        _btn = null;
        _contact = null;
        _labelField = null;
        super.dispose();
    }
}
