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

    /** Минимальный размер (для одно-символьных кнопок сохраняем 40×40) */
    private static inline var MIN_SIZE:Float = 33;
    /** Боковой padding для длинных подписей */
    private static inline var H_PADDING:Float = 14;

    /** Финальная ширина кнопки. Устанавливается в applyLabel() */
    private var _btnWidth:Float = MIN_SIZE;

    public function new(label: String, action: ButtonAction) {
        super();
        _action = action;

        _textField = new TextField();
        var format = new TextFormat("_sans", 16, 0xffffff, true);
        format.align = TextFormatAlign.CENTER;
        _textField.defaultTextFormat = format;
        _textField.selectable = false;
        _textField.mouseEnabled = false;
        _textField.text = label;
        _textField.autoSize = LEFT;   // temproraly — for text measurement
        addChild(_textField);

        applyLabel();

        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.CLICK, onClick);
        addEventListener(MouseEvent.MOUSE_OVER, onOver);
        addEventListener(MouseEvent.MOUSE_OUT, onOut);
    }

    /** Recalculates width using current text and center TextField */
    private function applyLabel():Void {
        var tw:Float = _textField.textWidth + 2;          // textWidth without tails
        _btnWidth = tw + H_PADDING * 2;
        if (_btnWidth < MIN_SIZE) _btnWidth = MIN_SIZE;

        _textField.autoSize = NONE;                        // fixed
        _textField.width  = _btnWidth;
        _textField.height = MIN_SIZE;
        _textField.x = 0;
        _textField.y = (MIN_SIZE - _textField.textHeight) * 0.5 - 2;

        redraw(false);
    }

    private function redraw(isOver:Bool):Void {
        graphics.clear();
        graphics.beginFill(isOver ? 0x4a4a5a : 0x3a3a4a);
        graphics.lineStyle(1, isOver ? 0x888888 : 0x666666);
        graphics.drawRoundRect(0, 0, _btnWidth, MIN_SIZE, 5, 5);
        graphics.endFill();
    }

    /** Outer API, if needed to change labels on the fly */
    public function setLabel(label:String):Void {
        _textField.autoSize = LEFT;
        _textField.text = label;
        applyLabel();
    }

    private function onClick(e: MouseEvent) { if (_action != null) _action(); }
    private function onOver(e: MouseEvent) { redraw(true); }
    private function onOut(e: MouseEvent) { redraw(false); }
}