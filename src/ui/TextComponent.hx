package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Contact;

class TextComponent extends Sprite {
    private var _textField: TextField;
    private var _contact: Contact;

    public function new(contact: Contact, ?width: Float = 200, ?height: Float = 50) {
        super();
        _contact = contact;
        _textField = new TextField();
        var format = new TextFormat("_typewriter", 16, 0xE0E0E0);
        format.align = TextFormatAlign.CENTER;
        _textField.defaultTextFormat = format;
        _textField.width = width;
        _textField.height = height;
        _textField.selectable = false;
        _textField.wordWrap = true;
        _textField.border = true;
        _textField.borderColor = 0x444444;
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, width, height);
        updateText(_contact.value);
        _contact.subscribe(onContactChange);
        addChild(_textField);
    }

    private function onContactChange(newValue: Dynamic) { updateText(newValue); }
    private function updateText(value: Dynamic) { _textField.text = Std.string(value); }
    public function destroy() { _contact.unsubscribe(onContactChange); }
}