package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;

/**
 * TEXT INPUT POPUP v1.0
 * Modal popup for text input or confirmation dialogs.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   TextInputPopup                                                        │
 * │                                                                         │
 * │   ┌──────────────────────────────────────────────────────────────────┐  │
 * │   │  [Semi-transparent overlay]                                      │  │
 * │   │                                                                  │  │
 * │   │  ┌────────────────────────────────────────────────────────────┐  │  │
 * │   │  │  Title                                                     │  │  │
 * │   │  ├────────────────────────────────────────────────────────────┤  │  │
 * │   │  │  [Input Field / Message]                                   │  │  │
 * │   │  ├────────────────────────────────────────────────────────────┤  │  │
 * │   │  │              [OK]              [Cancel]                    │  │  │
 * │   │  └────────────────────────────────────────────────────────────┘  │  │
 * │   └──────────────────────────────────────────────────────────────────┘  │
 * │                                                                         │
 * │   Modes:                                                                │
 * │   - Text Input: show(title, defaultText, callback)                      │
 * │   - Confirm:    showConfirm(title, message, boolCallback)               │
 * │                                                                         │
 * │   Keyboard:                                                             │
 * │   - ENTER: confirm                                                      │
 * │   - ESCAPE: cancel                                                      │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class TextInputPopup extends Sprite {
    private var _bg:Sprite;
    private var _window:Sprite;
    private var _input:TextField;
    private var _messageField:TextField;
    private var _okBtn:Sprite;
    private var _cancelBtn:Sprite;
    private var _callback:String -> Void;
    private var _boolCallback:Bool -> Void;
    private var _isConfirmMode:Bool = false;
    
    public function new() {
        super();
        visible = false;
        mouseEnabled = false;
    }
    
    /**
     * Show text input popup.
     * @param title       Window title
     * @param defaultText Initial text in input field
     * @param callback    Called with entered text (or null if cancelled)
     */
    public function show(title:String, defaultText:String, callback:String -> Void):Void {
        _callback = callback;
        _isConfirmMode = false;
        buildUI(title, defaultText, false);
    }
    
    /**
     * Show confirmation popup.
     * @param title    Window title
     * @param message  Confirmation message
     * @param callback Called with true (OK) or false (Cancel)
     */
    public function showConfirm(title:String, message:String, callback:Bool -> Void):Void {
        _boolCallback = callback;
        _isConfirmMode = true;
        buildUI(title, message, true);
    }
    
    private function buildUI(title:String, content:String, isConfirm:Bool):Void {
        _bg = new Sprite();
        _bg.graphics.beginFill(0x000000, 0.6);
        _bg.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
        _bg.graphics.endFill();
        addChild(_bg);
        
        var windowHeight = isConfirm ? 150 : 180;
        
        _window = new Sprite();
        _window.graphics.beginFill(0x222233);
        _window.graphics.lineStyle(2, 0x00AAFF);
        _window.graphics.drawRoundRect(0, 0, 400, windowHeight, 10, 10);
        _window.graphics.endFill();
        _window.x = (stage.stageWidth - 400) / 2;
        _window.y = (stage.stageHeight - windowHeight) / 2;
        addChild(_window);
        
        var titleTF = new TextField();
        titleTF.defaultTextFormat = new TextFormat("_typewriter", 16, 0x00AAFF, true);
        titleTF.text = title;
        titleTF.width = 380;
        titleTF.x = 10;
        titleTF.y = 10;
        titleTF.selectable = false;
        _window.addChild(titleTF);
        
        if (isConfirm) {
            _messageField = new TextField();
            _messageField.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
            _messageField.text = content;
            _messageField.width = 380;
            _messageField.height = 60;
            _messageField.x = 10;
            _messageField.y = 45;
            _messageField.selectable = false;
            _messageField.wordWrap = true;
            _window.addChild(_messageField);
        } else {
            _input = new TextField();
            _input.type = TextFieldType.INPUT;
            _input.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
            _input.text = content;
            _input.width = 380;
            _input.height = 30;
            _input.x = 10;
            _input.y = 45;
            _input.border = true;
            _input.borderColor = 0x00AAFF;
            _input.background = true;
            _input.backgroundColor = 0x111122;
            _window.addChild(_input);
        }
        
        _okBtn = createButton("OK");
        _okBtn.x = 100;
        _okBtn.y = isConfirm ? 100 : 130;
        _okBtn.addEventListener(MouseEvent.CLICK, onOk);
        _window.addChild(_okBtn);
        
        _cancelBtn = createButton("Cancel");
        _cancelBtn.x = 210;
        _cancelBtn.y = isConfirm ? 100 : 130;
        _cancelBtn.addEventListener(MouseEvent.CLICK, onCancel);
        _window.addChild(_cancelBtn);
        
        visible = true;
        
        if (!isConfirm && _input != null) {
            stage.focus = _input;
            _input.setSelection(0, _input.text.length);
        } else {
            stage.focus = _okBtn;
        }
        
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    }
    
    private function createButton(label:String):Sprite {
        var s = new Sprite();
        s.graphics.beginFill(0x3a3a4a);
        s.graphics.lineStyle(1, 0x666666);
        s.graphics.drawRoundRect(0, 0, 80, 30, 5, 5);
        s.graphics.endFill();
        
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF, null, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label;
        tf.width = 80;
        tf.height = 30;
        tf.selectable = false;
        tf.mouseEnabled = false;
        s.addChild(tf);
        s.buttonMode = true;
        return s;
    }
    
    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ENTER) onOk(null);
        if (e.keyCode == Keyboard.ESCAPE) onCancel(null);
    }
    
    private function onOk(_):Void {
        // Save text BEFORE removing visual elements
        var resultText:String = "";
        if (!_isConfirmMode && _input != null) {
            resultText = _input.text;
        }
        
        hide();
        
        if (_isConfirmMode) {
            if (_boolCallback != null) {
                _boolCallback(true);
                _boolCallback = null;
            }
        } else {
            if (_callback != null) {
                _callback(resultText);
                _callback = null;
            }
        }
    }
    
    private function onCancel(_):Void {
        hide();
        
        if (_isConfirmMode) {
            if (_boolCallback != null) {
                _boolCallback(false);
                _boolCallback = null;
            }
        } else {
            if (_callback != null) {
                _callback(null);
                _callback = null;
            }
        }
    }
    
    private function hide():Void {
        stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        if (_okBtn != null) _okBtn.removeEventListener(MouseEvent.CLICK, onOk);
        if (_cancelBtn != null) _cancelBtn.removeEventListener(MouseEvent.CLICK, onCancel);
        
        while (numChildren > 0) removeChildAt(0);
        
        if (_window != null) {
            while (_window.numChildren > 0) _window.removeChildAt(0);
        }
        
        _bg = null;
        _window = null;
        _input = null;
        _messageField = null;
        _okBtn = null;
        _cancelBtn = null;
        visible = false;
    }
}