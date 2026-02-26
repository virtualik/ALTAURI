package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.Event; // Добавлен импорт
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.Atom;
import core.Contact;
import ui.hmi.NumberInput;
import ui.hmi.NumberDisplay;

class PropertiesWindow extends Sprite {

    private var _bg:Sprite;
    private var _title:TextField;
    private var _content:Sprite;
    private var _target:Dynamic; 

    public function new() {
        super();
        
        _bg = new Sprite();
        addChild(_bg);
        drawBg(300, 200);
        
        _title = new TextField();
        _title.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _title.width = 280;
        _title.height = 20;
        _title.x = 10;
        _title.y = 5;
        _title.selectable = false;
        addChild(_title);
        
        _content = new Sprite();
        _content.y = 30;
        _content.x = 10;
        addChild(_content);
        
        // Кнопка закрытия [X]
        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0,0,15,15);
        closeBtn.x = 280;
        closeBtn.y = 5;
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(_) close());
        addChild(closeBtn);
        
        // --- ИСПРАВЛЕНИЕ ---
        // Сначала слушаем заголовок для старта перетаскивания
        _title.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDownHeader);
        
        // Подписываемся на stage только когда объект добавлен на сцену
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUpStage);
        } else {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
    }
    
    private function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUpStage);
    }
    
    private function onMouseDownHeader(e:MouseEvent):Void {
        startDrag();
    }
    
    private function onMouseUpStage(e:MouseEvent):Void {
        stopDrag();
    }
    
    public function show(target:Dynamic, x:Float, y:Float):Void {
        _target = target;
        this.x = x;
        this.y = y;
        
        while(_content.numChildren > 0) _content.removeChildAt(0);
        
        if (Std.isOfType(target, Atom)) {
            populateAtom(cast target);
        } else {
            _title.text = "Properties";
            var tf = new TextField();
            tf.text = "Unknown object";
            tf.width = 250;
            _content.addChild(tf);
        }
        
        visible = true;
    }
    
    public function close():Void {
        visible = false;
        stopDrag();
    }
    
    private function populateAtom(atom:Atom):Void {
        _title.text = "Atom: " + atom.name;
        
        var yPos = 0;
        
        for (c in atom.getInputs()) {
            var input = new NumberInput(c, "In: " + c.name);
            input.y = yPos;
            _content.addChild(input);
            yPos += 40;
        }
        
        for (c in atom.getOutputs()) {
            var output = new NumberDisplay(c, "Out: " + c.name);
            output.y = yPos;
            _content.addChild(output);
            yPos += 40;
        }
        
        drawBg(300, yPos + 50);
    }
    
    private function drawBg(w:Float, h:Float):Void {
        _bg.graphics.clear();
        _bg.graphics.beginFill(0x222233, 0.95);
        _bg.graphics.lineStyle(1, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        _bg.graphics.endFill();
    }
}