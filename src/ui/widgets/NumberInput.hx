package ui.widgets;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.text.TextFieldAutoSize;
import openfl.events.Event;
import openfl.events.FocusEvent;
import core.base.Contact;
import ui.widgets.IHMIWidget;

/**
 * NumberInput Widget v2.1
 * FIXED: Removed TextField.isDisposed check (OpenFL doesn't have this)
 */
class NumberInput extends Sprite implements IHMIWidget {
    public var contact(default, null):Contact;
    private var _input:TextField;
    private var _label:TextField;
    private var _isDisposed:Bool = false;
    private var _isEditing:Bool = false;

    public function new(contact:Contact, label:String = "Input") {
        super();
        if (contact == null) {
            trace('WARN: NumberInput created with null contact for "$label"');
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

        _input = new TextField();
        _input.type = TextFieldType.INPUT;
        _input.border = true;
        _input.borderColor = 0x00AAFF;
        _input.background = true;
        _input.backgroundColor = 0x222233;
        _input.textColor = 0xFFFFFF;
        _input.width = 150;
        _input.height = 30;
        _input.y = 20;
        _input.selectable = true;
        _input.mouseEnabled = true;
        _input.wordWrap = false;
        _input.multiline = false;
        _input.autoSize = TextFieldAutoSize.NONE;
        _input.maxChars = 30;
        var fmt = new TextFormat("_typewriter", 14);
        _input.defaultTextFormat = fmt;
        _input.text = _safeStringValue(contact.value);
        addChild(_input);

        _input.addEventListener(Event.CHANGE, _onUserInput);
        _input.addEventListener(FocusEvent.FOCUS_IN, _onFocusIn);
        _input.addEventListener(FocusEvent.FOCUS_OUT, _onFocusOut);
    }

    private function _subscribe():Void {
        if (contact != null && !contact.isDisposed) {
            contact.subscribe(_onContactUpdate);
        }
    }

    private function _onFocusIn(e:FocusEvent):Void {
        _isEditing = true;
    }

    private function _onFocusOut(e:FocusEvent):Void {
        _isEditing = false;
        _validateAndPush();
    }

    private function _onUserInput(e:Event):Void {
        _validateAndPush();
    }

    private function _validateAndPush():Void {
        if (_isDisposed || contact == null || contact.isDisposed) return;
        var val = Std.parseFloat(_input.text);
        if (!Math.isNaN(val)) {
            contact.value = val;
        }
    }

    private function _onContactUpdate(val:Dynamic):Void {
        if (_isDisposed) return;
        if (_isEditing) return;
        _updateInput(val);
    }

    public function onValueChanged(newValue:Dynamic):Void {
        _updateInput(newValue);
    }

    private function _updateInput(value:Dynamic):Void {
        if (_input == null || _label == null) return;
        var str = _safeStringValue(value);
        if (str.length > 30) {
            str = str.substr(0, 27) + "...";
        }
        if (_input.text != str) {
            _input.text = str;
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
            contact.unsubscribe(_onContactUpdate);
        }
    }

    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        _unsubscribe();
        if (_input != null) {
            _input.removeEventListener(Event.CHANGE, _onUserInput);
            _input.removeEventListener(FocusEvent.FOCUS_IN, _onFocusIn);
            _input.removeEventListener(FocusEvent.FOCUS_OUT, _onFocusOut);
            if (_input.parent != null) _input.parent.removeChild(_input);
            _input = null;
        }
        if (_label != null) {
            if (_label.parent != null) _label.parent.removeChild(_label);
            _label = null;
        }
        contact = null;
    }
}