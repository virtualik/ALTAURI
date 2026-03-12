package ui.widgets;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import core.base.Contact;
import ui.widgets.IHMIWidget;

/**
 * NumberDisplay Widget v2.1
 * FIXED: Removed TextField.isDisposed check (OpenFL doesn't have this)
 */
class NumberDisplay extends Sprite implements IHMIWidget {
    public var contact(default, null):Contact;
    private var _display:TextField;
    private var _label:TextField;
    private var _isDisposed:Bool = false;
    private var _callbackId:String = null;

    public function new(contact:Contact, label:String = "Output") {
        super();
        if (contact == null) {
            trace('WARN: NumberDisplay created with null contact for "$label"');
            return;
        }
        this.contact = contact;
        _createUI(label);
        _subscribe();
    }

    private function _createUI(label:String):Void {
        _label = new TextField();
        _label.text = label;
        _label.width = 150;
        _label.height = 20;
        _label.textColor = 0xAAAAAA;
        _label.selectable = false;
        _label.mouseEnabled = false;
        addChild(_label);

        _display = new TextField();
        _display.border = true;
        _display.borderColor = 0xFF8800;
        _display.background = true;
        _display.backgroundColor = 0x000000;
        _display.textColor = 0x00FF00;
        _display.width = 150;
        _display.height = 30;
        _display.y = 20;
        _display.selectable = true;
        _display.mouseEnabled = true;
        _display.wordWrap = true;
        _display.multiline = false;
        _display.autoSize = TextFieldAutoSize.NONE;
        _display.maxChars = 50;
        var fmt = new TextFormat("_typewriter", 14);
        _display.defaultTextFormat = fmt;
        _display.text = _safeStringValue(contact.value);
        addChild(_display);
    }

    private function _subscribe():Void {
        if (contact != null && !contact.isDisposed) {
            contact.subscribe(_onValueChanged);
        }
    }

    private function _onValueChanged(newValue:Dynamic):Void {
        if (_isDisposed) return;
        if (contact == null || contact.isDisposed) {
            _unsubscribe();
            return;
        }
        _updateDisplay(newValue);
    }

    public function onValueChanged(newValue:Dynamic):Void {
        _onValueChanged(newValue);
    }

    private function _updateDisplay(value:Dynamic):Void {
        if (_display == null || _label == null) return;
        var str = _safeStringValue(value);
        if (str.length > 50) {
            str = str.substr(0, 47) + "...";
        }
        if (_display.text != str) {
            _display.text = str;
        }
    }

    private function _safeStringValue(value:Dynamic):String {
        if (value == null) return "null";
        try {
            return Std.string(value);
        } catch (e:Dynamic) {
            return "[error]";
        }
    }

    private function _unsubscribe():Void {
        if (contact != null && !contact.isDisposed) {
            contact.unsubscribe(_onValueChanged);
        }
    }

    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        _unsubscribe();
        contact = null;
        if (_display != null) {
            if (_display.parent != null) _display.parent.removeChild(_display);
            _display = null;
        }
        if (_label != null) {
            if (_label.parent != null) _label.parent.removeChild(_label);
            _label = null;
        }
    }
}