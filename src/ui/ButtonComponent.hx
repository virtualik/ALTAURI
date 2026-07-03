package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;

/**
 * BUTTON COMPONENT v1.0
 * Square 40x40 button with label and click action.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ButtonComponent                                                       │
 * │                                                                         │
 * │   ┌──────────────────────────┐                                          │
 * │   │                          │  ← 40x40 square                          │
 * │   │        LABEL             │                                          │
 * │   │                          │                                          │
 * │   └──────────────────────────┘                                          │
 * │                                                                         │
 * │   States:                                                               │
 * │   - Normal:  bg=0x3a3a4a, border=0x666666                               │
 * │   - Hover:   bg=0x4a4a5a, border=0x888888                               │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
typedef ButtonAction = Void -> Void;

class ButtonComponent extends Sprite {
    private var _textField: TextField;
    private var _action: ButtonAction;
    
    /** Fixed size for square buttons */
    private static inline var SIZE:Float = 40;
    
    public function new(label: String, action: ButtonAction) {
        super();
        _action = action;
        
        // Draw square background
        redraw(false);
        
        _textField = new TextField();
        var format = new TextFormat("_sans", 18, 0xffffff, true);
        format.align = TextFormatAlign.CENTER;
        _textField.defaultTextFormat = format;
        _textField.y = 5;
        _textField.width = SIZE;
        _textField.height = SIZE;
        _textField.text = label;
        _textField.selectable = false;
        _textField.mouseEnabled = false;
        addChild(_textField);
        
        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.CLICK, onClick);
        addEventListener(MouseEvent.MOUSE_OVER, onOver);
        addEventListener(MouseEvent.MOUSE_OUT, onOut);
    }
    
    private function redraw(isOver:Bool):Void {
        graphics.clear();
        graphics.beginFill(isOver ? 0x4a4a5a : 0x3a3a4a);
        graphics.lineStyle(1, isOver ? 0x888888 : 0x666666);
        graphics.drawRoundRect(0, 0, SIZE, SIZE, 5, 5);
        graphics.endFill();
    }
    
    private function onClick(e: MouseEvent) { if (_action != null) _action(); }
    private function onOver(e: MouseEvent) { redraw(true); }
    private function onOut(e: MouseEvent) { redraw(false); }
}