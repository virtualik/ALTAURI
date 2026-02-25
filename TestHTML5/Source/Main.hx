package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.geom.Point;
import core.AtomDefinitions;
import core.AssemblyFactory;
import core.Assembly;
import core.Blueprint;
import core.Atom;
import core.Contact;
import core.Impulsys;
import core.Impulse;
import editor.NodeEditor;
import ui.ContextMenu;
import drivers.DriverManager;
import drivers.MockSensorDriver;

// HTML5 fix
#if html5
import js.html.CanvasElement;
import js.Browser;
#end

class Main extends Sprite {
    
    private var _editor:NodeEditor;
    private var _menu:ContextMenu;

    public function new() {
        super();
        
        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        #end
        
        AtomDefinitions.initialize();
        
        // --- CREATE EMPTY SCHEME ---
        // We create a hollow Assembly manually to have a clean canvas
        
        var emptyBlueprint = new Blueprint("main_scheme", "Main Scheme", [
            // External pins of the main scheme (optional, usually for sub-assemblies)
            // For main scheme, we might not need SELF pins visible? 
            // But NodeEditor currently forces "SELF" node.
            // Let's add dummy pins just to satisfy NodeEditor layout logic for SELF node
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        
        var assembly = new Assembly("main_asm", emptyBlueprint);
        
        // --- EDITOR ---
        
        _editor = new NodeEditor(assembly);
        addChild(_editor);
        
        _menu = new ContextMenu();
        _menu.visible = false;
        addChild(_menu);
        
        buildMenu();
        
        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        
        // --- DRIVER TEST ---
    
		// 1. Create FPS Atom visually
		var fpsAtom = _editor.createAtom("FPSMonitor", 50, 50);
		
		// 2. Create and bind Driver
		if (fpsAtom != null) {
			var fpsContact = fpsAtom.getOutputs()[0];
			var fpsDriver = new drivers.FPSDriver("sys_fps", fpsContact);
			DriverManager.getInstance().register(fpsDriver);
		}
        // Create one sensor atom and attach driver
        var sensorAtom = _editor.createAtom("SensorMock", 100, 200);
        if (sensorAtom != null) {
            var contact = sensorAtom.getOutputs()[0];
            var drv = new MockSensorDriver("live_sensor", contact, 0.5);
            DriverManager.getInstance().register(drv);
        }
        
        // Create one display atom
        _editor.createAtom("AlphaNumericLine", 400, 200);
    }
   
	private function buildMenu():Void {
		var ids = AtomDefinitions.getAllIds();
		
		// Сортируем для красоты
		ids.sort(function(a, b) return Reflect.compare(a, b));

		for (id in ids) {
			// Получаем чертеж, чтобы узнать красивое имя
			var bp = AtomDefinitions.get(id);
			if (bp != null) {
				_menu.addItem("Add " + bp.name, "ADD_ATOM", {typeId: id});
			}
		}
	}
    
    private function onRightClick(e:MouseEvent):Void {
        _menu.show(e.stageX, e.stageY);
    }
    
    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ESCAPE) _menu.hide();
    }
    
	private function onMenuAction(impulse:Impulse):Void {
    _menu.hide();

    // Распаковываем данные из события
    var action = impulse.data.action;
    var data = impulse.data.data;
    var x = impulse.data.x;
    var y = impulse.data.y;

    // Обрабатываем команды
    if (action == "ADD_ATOM") {
        // Проверяем, что данные пришли
        if (data != null && data.typeId != null) {
            _editor.createAtom(data.typeId, x, y);
        }
    }
}
}