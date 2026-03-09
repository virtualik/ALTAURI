package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;

class TextInputPopup extends Sprite {

    private var _bg:Sprite;
    private var _window:Sprite;
    private var _input:TextField;
    private var _okBtn:Sprite;
    private var _cancelBtn:Sprite;
    private var _callback:String -> Void;

    public function new() {
        super();
        visible = false;
        mouseEnabled = false;
    }

    public function show(title:String, defaultText:String, callback:String -> Void):Void {
        _callback = callback;
        
        // 1. Dim Background
        _bg = new Sprite();
        _bg.graphics.beginFill(0x000000, 0.6);
        _bg.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
        _bg.graphics.endFill();
        addChild(_bg);

        // 2. Window Container
        _window = new Sprite();
        _window.graphics.beginFill(0x222233);
        _window.graphics.lineStyle(2, 0x00AAFF);
        _window.graphics.drawRoundRect(0, 0, 400, 150, 10, 10);
        _window.graphics.endFill();
        
        _window.x = (stage.stageWidth - 400) / 2;
        _window.y = (stage.stageHeight - 150) / 2;
        addChild(_window);

        // 3. Title
        var titleTF = new TextField();
        titleTF.defaultTextFormat = new TextFormat("_typewriter", 16, 0x00AAFF, true);
        titleTF.text = title;
        titleTF.width = 380;
        titleTF.x = 10;
        titleTF.y = 10;
        titleTF.selectable = false;
        _window.addChild(titleTF);

        // 4. Input Field
        _input = new TextField();
        _input.type = TextFieldType.INPUT;
        _input.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
        _input.text = defaultText;
        _input.width = 380;
        _input.height = 30;
        _input.x = 10;
        _input.y = 45;
        _input.border = true;
        _input.borderColor = 0x00AAFF;
        _input.background = true;
        _input.backgroundColor = 0x111122;
        _window.addChild(_input);

        // 5. OK Button
        _okBtn = createButton("OK");
        _okBtn.x = 100;
        _okBtn.y = 100;
        _okBtn.addEventListener(MouseEvent.CLICK, onOk);
        _window.addChild(_okBtn);

        // 6. Cancel Button
        _cancelBtn = createButton("Cancel");
        _cancelBtn.x = 210;
        _cancelBtn.y = 100;
        _cancelBtn.addEventListener(MouseEvent.CLICK, onCancel);
        _window.addChild(_cancelBtn);

        visible = true;
        stage.focus = _input;
        _input.setSelection(0, _input.text.length);
        
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
        // ИСПРАВЛЕНИЕ: Сохраняем текст ПЕРЕД удалением визуальных элементов
        var resultText:String = _input.text;
        
        hide();
        
        if (_callback != null) {
            _callback(resultText);
            _callback = null;
        }
    }

    private function onCancel(_):Void {
        hide();
        if (_callback != null) {
            _callback(null);
            _callback = null;
        }
    }

    private function hide():Void {
        stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        if (_okBtn != null) _okBtn.removeEventListener(MouseEvent.CLICK, onOk);
        if (_cancelBtn != null) _cancelBtn.removeEventListener(MouseEvent.CLICK, onCancel);
        
        // Удаляем графику
        while (numChildren > 0) removeChildAt(0);
        _bg = null;
        _window = null;
        _input = null; // Здесь зануляется ссылка
        _okBtn = null;
        _cancelBtn = null;
        
        visible = false;
    }
}