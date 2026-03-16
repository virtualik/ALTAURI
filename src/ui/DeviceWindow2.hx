package ui;

import openfl.display.Window;
import openfl.display.Sprite;
import openfl.Lib;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.display.StageScaleMode;
import openfl.display.StageAlign;
import openfl.text.TextFieldAutoSize;
import openfl.events.Event;
import openfl.events.MouseEvent;

class DeviceWindow2 {
    private var _window:Window;
    private var _container:Sprite;
    private var _bg:Sprite;

    public function new() {
        var config = {
            title: "STABLE UI WINDOW",
            width: 450,
            height: 350,
            resizable: true,
            context: {
                background: 0x1a1a24,
                antialiasing: 2,
                hardware: false // КЛЮЧЕВОЙ МОМЕНТ: программный рендер стабильнее для 2-го окна
            }
        };

        _window = Lib.application.createWindow(config);

        if (_window != null && _window.stage != null) {
            var stage = _window.stage;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            // 1. Слой фона
            _bg = new Sprite();
            stage.addChild(_bg);

            // 2. Контейнер для интерфейса
            _container = new Sprite();
            stage.addChild(_container);

            // 3. Тестовая кнопка
            var btn = new Sprite();
            btn.graphics.beginFill(0x44BB44);
            btn.graphics.drawRoundRect(0, 0, 120, 35, 8);
            btn.graphics.endFill();
            btn.x = 20; btn.y = 20;
            btn.buttonMode = true;
            btn.addEventListener(MouseEvent.CLICK, function(_) trace("Click in Window 2!"));
            _container.addChild(btn);

            // 4. Текст
            var tf = new TextField();
            tf.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
            tf.text = "SOFTWARE MODE: ACTIVE\nСтабильная отрисовка спрайтов.";
            tf.autoSize = TextFieldAutoSize.LEFT;
            tf.x = 20; tf.y = 70;
            tf.selectable = false;
            _container.addChild(tf);

            // Подписка на ресайз для перерисовки фона
            stage.addEventListener(Event.RESIZE, onResize);
            updateLayout();
        }
    }

    private function onResize(e:Event):Void {
        updateLayout();
    }

    private function updateLayout():Void {
        if (_bg != null && _window != null) {
            _bg.graphics.clear();
            _bg.graphics.beginFill(0x1a1a24); // Заливка цветом темы
            _bg.graphics.drawRect(0, 0, _window.stage.stageWidth, _window.stage.stageHeight);
            _bg.graphics.endFill();
        }
    }

    public function close():Void {
        if (_window != null) {
            _window.close();
            _window = null;
        }
    }
}
