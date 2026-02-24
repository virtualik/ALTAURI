package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.geom.Point;
import core.AtomDefinitions;
import core.AssemblyFactory;
import core.Assembly;
import core.Impulsys;
import core.Impulse;
import editor.NodeEditor;
import ui.ContextMenu;

// Special import for HTML5 specific fixes
#if html5
import js.html.CanvasElement;
import js.Browser;
#end

class Main extends Sprite {
    
    private var _editor:NodeEditor;
    private var _menu:ContextMenu;

    public function new() {
        super();
        
        // --- HTML5 FIX ---
        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) {
            canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        }
        #end
        
        AtomDefinitions.initialize();
        
        var assembly = AssemblyFactory.createAssembly("Doubler");
        
        _editor = new NodeEditor(assembly);
        addChild(_editor);
        
        _menu = new ContextMenu();
        _menu.visible = false;
        addChild(_menu);
        
        buildMenu();
        
        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        // 1. Listen for menu actions to hide menu after selection
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
    }
    
    private function buildMenu():Void {
        _menu.addItem("Add NumberSource", "ADD_ATOM", {typeId: "NumberSource"});
        _menu.addItem("Add PassThrough", "ADD_ATOM", {typeId: "PassThrough"});
        _menu.addItem("Add Adder", "ADD_ATOM", {typeId: "Adder"});
    }
    
    private function onRightClick(e:MouseEvent):Void {
        _menu.show(e.stageX, e.stageY);
    }
    
    // 2. Handle Keyboard
    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ESCAPE) {
            _menu.hide();
        }
    }
    
    // 3. Hide menu after action
    private function onMenuAction(impulse:Impulse):Void {
        _menu.hide();
    }
}