package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;

typedef ButtonAction = Void -> Void;

class ButtonComponent extends Sprite {
    private var _textField: TextField;
    private var _action: ButtonAction;
    
    public function new(label: String, action: ButtonAction) {
        super();
        _action = action;
        graphics.beginFill(0x3a3a4a);
        graphics.lineStyle(1, 0x666666);
        graphics.drawRoundRect(0, 0, 150, 40, 8, 8);
        buttonMode = true;
        useHandCursor = true;
        
        _textField = new TextField();
        var format = new TextFormat("_typewriter", 14, 0xffffff);
        format.align = TextFormatAlign.CENTER;
        _textField.defaultTextFormat = format;
        _textField.width = 150;
        _textField.height = 40;
        _textField.text = label;
        _textField.selectable = false;
        _textField.mouseEnabled = false;
        addChild(_textField);
        
        addEventListener(MouseEvent.CLICK, onClick);
        addEventListener(MouseEvent.MOUSE_OVER, onOver);
        addEventListener(MouseEvent.MOUSE_OUT, onOut);
    }
    
    private function onClick(e: MouseEvent) { if (_action != null) _action(); }
    private function onOver(e: MouseEvent) {
        graphics.clear(); graphics.beginFill(0x4a4a5a); graphics.lineStyle(1, 0x888888);
        graphics.drawRoundRect(0, 0, 150, 40, 8, 8);
    }
    private function onOut(e: MouseEvent) {
        graphics.clear(); graphics.beginFill(0x3a3a4a); graphics.lineStyle(1, 0x666666);
        graphics.drawRoundRect(0, 0, 150, 40, 8, 8);
    }
}
