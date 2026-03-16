package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
* LED WIDGET v1.0 (Fixed Highlight Ring)
* Круглый светодиод для отображения булева значения.
*
* Цвета:
* - ON (true): яркий цвет
* - OFF (false): тёмный цвет
*/
class LEDWidget extends DeviceView {
    private var _ledSprite:Sprite;
    private var _labelField:TextField;
    private var _contact:Contact;

    // Настройки
    public var radius:Float = 20;
    public var colorOn:Int = 0x00FF00;
    public var colorOff:Int = 0x003300;
    public var labelOn:String = "ON";
    public var labelOff:String = "OFF";
    public var showLabel:Bool = true;

    public function new(atom:Atom, contactName:String = "in") {
        super(atom);
        // Находим контакт для отображения
        if (atom != null) {
            _contact = atom.getOutput(contactName);
            if (_contact == null) _contact = atom.getInput(contactName);
        }
        buildUI();
    }

    private function buildUI():Void {
        // LED круг
        _ledSprite = new Sprite();
        addChild(_ledSprite);

        // Метка
        if (showLabel) {
            _labelField = new TextField();
            _labelField.width = 80;
            _labelField.height = 20;
            _labelField.y = radius + 5;
            _labelField.x = -40;
            _labelField.selectable = false;
            _labelField.mouseEnabled = false;
            var fmt = new TextFormat("_sans", 11, 0xAAAAAA);
            fmt.align = TextFormatAlign.CENTER;
            _labelField.defaultTextFormat = fmt;
            addChild(_labelField);
        }

        // Начальная отрисовка
        updateVisual();
    }

    override private function onActivate():Void {
        updateVisual();
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _contact) {
            updateVisual();
        }
    }

    private function updateVisual():Void {
        var isOn:Bool = false;
        if (_contact != null) {
            var v = _contact.value;
            if (Std.isOfType(v, Bool)) {
                isOn = cast(v, Bool);
            } else if (v != null) {
                // Проверяем на "истинность" - не null и не 0
                isOn = (v != 0 && v != null);
            }
        }

        // Перерисовываем LED
        _ledSprite.graphics.clear();
        
        // Внешнее кольцо (рамка)
        _ledSprite.graphics.lineStyle(2, 0x444444);
        _ledSprite.graphics.beginFill(isOn ? colorOn : colorOff);
        _ledSprite.graphics.drawCircle(0, 0, radius);
        _ledSprite.graphics.endFill();

        // Блик (для объема)
        if (isOn) {
            // FIX: Явно убираем обводку перед рисованием блика, чтобы избежать артефактов/колец
            _ledSprite.graphics.lineStyle(0, 0, 0);
            
            _ledSprite.graphics.beginFill(0xFFFFFF, 0.3);
            _ledSprite.graphics.drawCircle(-radius * 0.3, -radius * 0.3, radius * 0.3);
            _ledSprite.graphics.endFill();
        }
    }

    override public function dispose():Void {
        _contact = null;
        _ledSprite = null;
        _labelField = null;
        super.dispose();
    }
}