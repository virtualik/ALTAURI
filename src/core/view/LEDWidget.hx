package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
 * LED WIDGET v2.5
 * Circular LED indicator for boolean or analog signals.
 */
class LEDWidget extends DeviceView {
    
    private var _ledSprite:Sprite;
    private var _labelField:TextField;
    
    // Settings
    public var radius:Float = 20;
    public var colorOn:Int = 0x00FF00;
    public var colorOff:Int = 0x003300;
    public var labelOn:String = "ON";
    public var labelOff:String = "OFF";
    public var showLabel:Bool = true;
    public var threshold:Float = 0.1;
    
    // Protection
    private var _isUpdating:Bool = false;

    public function new(atom:Atom, contactName:String = "in") {
        super(atom);
        buildUI();
    }
    
    private function buildUI():Void {
        _ledSprite = new Sprite();
        addChild(_ledSprite);

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

        updateVisual(false);
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed || _isUpdating) return;
        updateVisual(isOn(newValue));
    }
    
    private function isOn(value:Dynamic):Bool {
        if (value == null) return false;
        if (Std.isOfType(value, Bool)) return cast(value, Bool);
        if (Std.isOfType(value, Float)) return cast(value, Float) > threshold;
        if (Std.isOfType(value, Int)) return cast(value, Int) > 0;
        return false;
    }
    
    private function updateVisual(isOn:Bool):Void {
        if (_isUpdating || isDisposed || _ledSprite == null) return;
        _isUpdating = true;

        _ledSprite.graphics.clear();
        _ledSprite.graphics.lineStyle(2, 0x444444);
        _ledSprite.graphics.beginFill(isOn ? colorOn : colorOff);
        _ledSprite.graphics.drawCircle(0, 0, radius);
        _ledSprite.graphics.endFill();

        // Glow effect when on
        if (isOn) {
            _ledSprite.graphics.lineStyle(0, 0, 0);
            _ledSprite.graphics.beginFill(0xFFFFFF, 0.3);
            _ledSprite.graphics.drawCircle(-radius * 0.3, -radius * 0.3, radius * 0.3);
            _ledSprite.graphics.endFill();
        }

        if (_labelField != null) {
            _labelField.text = isOn ? labelOn : labelOff;
        }

        _isUpdating = false;
    }
    
    override public function dispose():Void {
        _ledSprite = null;
        _labelField = null;
        super.dispose();
    }
}
