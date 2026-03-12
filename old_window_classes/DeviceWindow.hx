package ui;

import openfl.display.Window;
import openfl.display.Sprite;
import openfl.Lib;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Assembly;

class DeviceWindow {

    private var _window:Window;
    private var _panel:DevicePanel;
    private var _assembly:Assembly;

    // Для кастомного перетаскивания
    private var _dragging:Bool = false;
    // Запоминаем начальное смещение клика один раз
    private var _clickOffsetX:Float = 0;
    private var _clickOffsetY:Float = 0;
    private var _header:Sprite;

    public function new(assembly:Assembly) {
        _assembly = assembly;
        create();
    }

    private function create():Void {
        var config = {
            title: "Device",
            width: 420,
            height: 500,
            borderless: true,
            alwaysOnTop: true,
            parameters: {
                background: 0x000000
            }
        };

        _window = Lib.application.createWindow(config);
        
        if (_window != null && _window.stage != null) {
            createCustomHeader();

            _panel = new DevicePanel(_assembly);
            _panel.y = 30;
            _window.stage.addChild(_panel);
        }

        haxe.Timer.delay(() -> {
            applyWindowEffects();
        }, 100);
    }

    private function createCustomHeader():Void {
        _header = new Sprite();
        
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 420, 30);
        _header.graphics.endFill();

        var title = new TextField();
        title.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        title.text = "  Device Panel";
        title.width = 380;
        title.height = 30;
        title.selectable = false;
        title.mouseEnabled = false;
        _header.addChild(title);

        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0, 0, 30, 30);
        closeBtn.graphics.endFill();
        closeBtn.x = 390;
        
        var xText = new TextField();
        xText.text = "X";
        xText.width = 30;
        xText.height = 30;
        xText.selectable = false;
        xText.mouseEnabled = false;
        xText.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, "center");
        closeBtn.addChild(xText);
        
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(e) { close(); });
        _header.addChild(closeBtn);

        _header.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
            if (e.target != closeBtn) {
                _dragging = true;
                // ИСПРАВЛЕНИЕ: Запоминаем, где именно мы кликнули внутри окна (локальные координаты)
                // Эти значения НЕ МЕНЯЮТСЯ во время перетаскивания
                _clickOffsetX = e.localX;
                _clickOffsetY = e.localY;
                
                _window.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
                _window.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
            }
        });
        
        _header.buttonMode = true; 

        _window.stage.addChild(_header);
    }

    private function onMouseMoveDrag(e:MouseEvent):Void {
        if (_dragging && _window != null) {
            // Используем глобальные координаты мыши (stageX/Y),
            // но так как это окно, stageX == глобальному X экрана (для borderless).
            // Мы просто вычитаем начальное смещение клика.
            
            // Внимание: Для borderless окна stageX/Y - это координаты относительно левого верхнего угла окна.
            // Нам нужно двигать окно так, чтобы точка клика совпадала с позицией мыши на экране.
            
            // Самый надежный способ для OpenFL borderless:
            // Использовать relative positions, так как stageX обновляется корректно.
            
            // Однако, т.к. мы двигаем окно, stageX меняется "вместе" с ним.
            // Поэтому просто вычисляем разницу между текущей позицией мыши и точкой клика.
            
            // Но stageX - это координата внутри окна.
            // Если мы просто скажем: window.x = mouseX - offset.
            
            // Получаем текущую позицию мыши на экране (в borderless режиме stageX ~ globalX, но window.x влияет на расчеты)
            
            // Давайте используем сырые координаты мыши относительно stage.
            // Поскольку окно borderless, то:
            // e.stageX - это координата курсора относительно левого верхнего угла окна.
            
            // Чтобы двигать окно плавно:
            // Мы должны поместить окно так, чтобы e.stageX был равен _clickOffsetX.
            
            // Но изменение window.x меняет систему координат для следующего события.
            // Поэтому простая формула:
            // newX = currentGlobalMouse - offsetX.
            // В OpenFL e.stageX для отдельного окна — это и есть позиция мыши в этом окне.
            
            // Двигаем окно так, чтобы координата мыши внутри него вернулась к _clickOffsetX.
            // Текущая позиция мыши внутри окна: e.stageX
            // Желаемая: _clickOffsetX
            // Разница: diff = e.stageX - _clickOffsetX
            
            var dx = e.stageX - _clickOffsetX;
            var dy = e.stageY - _clickOffsetY;
            
            // Обновляем позицию окна
            _window.x = Std.int(_window.x + dx);
            _window.y = Std.int(_window.y + dy);
        }
    }

    private function onMouseUpDrag(e:MouseEvent):Void {
        _dragging = false;
        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
        }
    }

    private function applyWindowEffects():Void {
        #if windows
        var ctrl = new WindowController();
        var success = ctrl.applyTransparencyToWindow("Device");
        if (success) trace("Device window transparency enabled.");
        #end
    }

    public function close():Void {
        if (_window != null && _window.stage != null) {
             _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
             _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
        }
        
        if (_panel != null) {
            _panel.dispose();
            if (_panel.parent != null) _panel.parent.removeChild(_panel);
            _panel = null;
        }
        if (_window != null) {
            _window.close();
            _window = null;
        }
    }
}