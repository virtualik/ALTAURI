package;

import lime.app.Application;
import lime.ui.Window;
import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.events.Event;
import openfl.Lib;

/**
 * Transparent Overlay Window Controller
 * Lime 8.1.3 + OpenFL 9.4.0
 */
class AdvancedOverlay {

    private static var _instance:AdvancedOverlay;
    
    private var _window:Window;
    private var _stage:Stage;
    private var _rootSprite:Sprite;
    private var _angle:Float = 0;
    private var _assembly:Dynamic;

    public static function create(?assembly:Dynamic):AdvancedOverlay {
        if (_instance != null) {
            _instance.show();
            return _instance;
        }
        
        _instance = new AdvancedOverlay(assembly);
        return _instance;
    }

    public static function getInstance():AdvancedOverlay {
        return _instance;
    }

    private function new(assembly:Dynamic) {
        _assembly = assembly;
        createWindow();
    }

    private function createWindow():Void {
        var app = Application.current;
        if (app == null) {
            trace("ERROR: No Lime Application found!");
            return;
        }

        var attrs:lime.ui.WindowAttributes = {
            width: 800,
            height: 600,
            x: null,
            y: null,
            title: "ALTAURI Player",
            borderless: true,
            resizable: false,
            fullscreen: false,
            hidden: false,
            maximized: false,
            minimized: false,
            parameters: null,
            element: null
        };

        _window = app.createWindow(attrs);

        if (_window == null) {
            trace("ERROR: Failed to create overlay window!");
            return;
        }

        trace("Overlay window created!");
        trace("  ID: " + _window.id);
        trace("  Size: " + _window.width + "x" + _window.height);

        setupStage();
    }

    private function setupStage():Void {
        _stage = new Stage(_window.width, _window.height, 0x00000000, null, true, true);

        _rootSprite = new Sprite();
        _stage.addChild(_rootSprite);

        buildUI();

        _stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);

        _window.onClose.add(onWindowClose);
        _window.onResize.add(onWindowResize);
    }

    private function buildUI():Void {
        var container = new Sprite();
        container.graphics.beginFill(0x0f0f23, 0.9);
        container.graphics.drawRoundRectComplex(0, 0, 500, 400, 0, 0, 16, 16);
        container.graphics.endFill();
        container.x = 150;
        container.y = 100;
        _rootSprite.addChild(container);

        var accent = new Sprite();
        accent.graphics.beginFill(0x00aaff);
        accent.graphics.drawRect(0, 0, 4, 400);
        accent.graphics.endFill();
        container.addChild(accent);

        var titleBg = new Sprite();
        titleBg.graphics.beginFill(0x16213e, 0.95);
        titleBg.graphics.drawRect(4, 0, 496, 50);
        titleBg.graphics.endFill();
        container.addChild(titleBg);

        for (i in 0...5) {
            var orb = new Sprite();
            orb.graphics.beginFill(0x00aaff, 0.3 + i * 0.1);
            orb.graphics.drawCircle(0, 0, 10 + i * 5);
            orb.graphics.endFill();
            orb.x = 100 + i * 80;
            orb.y = 250;
            orb.name = "orb_" + i;
            container.addChild(orb);
        }

        var info = new Sprite();
        info.graphics.beginFill(0x1a1a2e, 0.8);
        info.graphics.drawRoundRect(20, 300, 460, 80, 8);
        info.graphics.endFill();
        container.addChild(info);
    }

    private function onEnterFrame(e:Event):Void {
        _angle += 0.02;

        for (i in 0...5) {
            var orb = _rootSprite.getChildByName("orb_" + i);
            if (orb != null) {
                orb.y = 350 + Math.sin(_angle + i * 0.5) * 30;
                orb.scaleX = orb.scaleY = 1 + Math.sin(_angle * 2 + i) * 0.2;
            }
        }

        _stage.__render();
    }

    // ИСПРАВЛЕНО: принимает Window как параметр
    private function onWindowResize(window:Window):Void {
        if (_stage != null) {
            _stage.__setStageSize(window.width, window.height);
        }
    }

    private function onWindowClose():Void {
        dispose();
    }

    public function show():Void {
        if (_window != null) {
            _window.visible = true;
        }
    }

    public function hide():Void {
        if (_window != null) {
            _window.visible = false;
        }
    }

    public function setPosition(x:Int, y:Int):Void {
        if (_window != null) {
            _window.x = x;
            _window.y = y;
        }
    }

    public function setSize(width:Int, height:Int):Void {
        if (_window != null) {
            _window.width = width;
            _window.height = height;
        }
    }

    public function dispose():Void {
        if (_stage != null) {
            _stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
            _stage = null;
        }
        
        _rootSprite = null;
        _instance = null;
    }
}