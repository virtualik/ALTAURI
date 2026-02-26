package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.events.Event;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.AtomDefinitions;
import core.Assembly;
import core.Blueprint;
import core.SignalQueue;
import core.Impulsys;
import core.Impulse;
import core.UndoManager;
import drivers.DriverManager;
import editor.NodeEditor;
import ui.ContextMenu;
import ui.DevicePanel;
import ui.PropertiesWindow;
import ui.ButtonComponent;
import utils.ProjectIO;

#if html5
import js.html.CanvasElement;
import js.Browser;
#end

class Main extends Sprite {

    private var _editorLayer:Sprite;
    private var _deviceLayer:Sprite;
    private var _uiLayer:Sprite;

    private var _editor:NodeEditor;
    private var _devicePanel:DevicePanel;
    private var _menu:ContextMenu;
    private var _fileMenu:ContextMenu;
    private var _propertiesWindow:PropertiesWindow;

    private var _assembly:Assembly;
    private var _isEditorMode:Bool = true;
    
    private var _debugField:TextField;
    private var _hideTimer:haxe.Timer;
    
    // Для контекстного меню
    private var _contextTargetId:String = null;

    public function new() {
        super();

        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        #end

        setupDebugLog();
        
        ProjectIO.logger = log; 

        AtomDefinitions.initialize();
        log("System initialized");

        var emptyBlueprint = new Blueprint("main_scheme", "Main Scheme", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        _assembly = new Assembly("main_asm", emptyBlueprint);

        setupLayers();
        buildUI();
    }
    
    private function log(msg:String) {
        trace(msg); 
        
        if (_hideTimer != null) _hideTimer.stop();
        
        if (_debugField != null) {
            _debugField.text = msg;
            _debugField.alpha = 1.0;
            _debugField.visible = true;
        }

        _hideTimer = haxe.Timer.delay(() -> {
            fadeOutLog();
        }, 20000);
    }

    private function fadeOutLog() {
        if (_debugField != null) {
            _debugField.visible = false;
        }
    }

    private function setupDebugLog() {
        _debugField = new TextField();
        _debugField.width = 600;
        _debugField.height = 30;
        _debugField.x = 10;
        _debugField.y = 55; 
        _debugField.background = true;
        _debugField.backgroundColor = 0x333333;
        _debugField.textColor = 0x00FF00;
        _debugField.selectable = false;
        var fmt = new TextFormat("_typewriter", 12);
        _debugField.defaultTextFormat = fmt;
        addChild(_debugField);
    }

    private function setupLayers():Void {
        _editorLayer = new Sprite();
        addChild(_editorLayer);

        _editor = new NodeEditor(_assembly);
        _editorLayer.addChild(_editor);

        _deviceLayer = new Sprite();
        _deviceLayer.visible = false;
        addChild(_deviceLayer);

        _uiLayer = new Sprite();
        addChild(_uiLayer);
    }

    private function buildUI():Void {
        var toggleBtn = new ButtonComponent("Toggle View [F5]", onToggleView);
        toggleBtn.x = 10;
        toggleBtn.y = 10;
        _uiLayer.addChild(toggleBtn);

        var fileBtn = new ButtonComponent("File", onFileClick);
        fileBtn.x = 170;
        fileBtn.y = 10;
        _uiLayer.addChild(fileBtn);
        
        var resetBtn = new ButtonComponent("Reset [R]", onResetClick);
        resetBtn.x = 330;
        resetBtn.y = 10;
        _uiLayer.addChild(resetBtn);

        _menu = new ContextMenu();
        _menu.visible = false;
        _uiLayer.addChild(_menu);
        buildAtomMenu();

        _propertiesWindow = new PropertiesWindow();
        _propertiesWindow.visible = false;
        _uiLayer.addChild(_propertiesWindow);

        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);

        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("NODE_RIGHT_CLICKED", onNodeRightClick);
    }
    
    private function onResetClick():Void {
        hardReset();
        var emptyBlueprint = new Blueprint("main_scheme", "Main Scheme", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        _assembly = new Assembly("main_asm", emptyBlueprint);
        _editor = new NodeEditor(_assembly);
        _editorLayer.addChild(_editor);
        log("System Reset Complete.");
    }

    private function hardReset():Void {
        log("SYSTEM: Hard Reset initiated...");
        DriverManager.getInstance().dispose();
        SignalQueue.getInstance().clear();
        UndoManager.getInstance().clear(); // Очистка истории

        if (_editor != null) {
            _editor.dispose();
            _editorLayer.removeChild(_editor);
            _editor = null;
        }

        if (_assembly != null) {
            _assembly.dispose();
            _assembly = null;
        }
        
        log("SYSTEM: Memory cleared.");
    }

    private function onToggleView():Void {
        _isEditorMode = !_isEditorMode;
        _editorLayer.visible = _isEditorMode;
        _deviceLayer.visible = !_isEditorMode;

        if (!_isEditorMode) {
            while (_deviceLayer.numChildren > 0) _deviceLayer.removeChildAt(0);
            _devicePanel = new DevicePanel(_assembly);
            _deviceLayer.addChild(_devicePanel);
        }
    }

    private function onFileClick():Void {
        if (_fileMenu == null) {
            _fileMenu = new ContextMenu();
            _fileMenu.addItem("Save Project", "FILE_SAVE");
            _fileMenu.addItem("Load Project", "FILE_LOAD");
            _uiLayer.addChild(_fileMenu);
        }

        var fileBtn = cast _uiLayer.getChildAt(1);
        _fileMenu.show(fileBtn.x, fileBtn.y + 40);
    }

    private function buildAtomMenu():Void {
        var ids = core.AtomDefinitions.getAllIds();
        ids.sort(function(a, b) return Reflect.compare(a, b));
        for (id in ids) {
            var bp = core.AtomDefinitions.get(id);
            if (bp != null) _menu.addItem("Add " + bp.name, "ADD_ATOM", {typeId: id});
        }
    }

    // --- НОВОЕ: Контекстное меню для Атома ---
    private function onNodeRightClick(impulse:Impulse):Void {
        _contextTargetId = impulse.data.id;
        
        // Очищаем меню и заполняем актуальными пунктами
        // Нужно добавить метод clear в ContextMenu, пока пересоздадим
        _menu = new ContextMenu();
        _uiLayer.addChild(_menu); // Добавляем заново, так как старый удалили
        buildAtomMenu(); // Восстанавливаем список добавления
        
        // Добавляем специфичные пункты
        _menu.addItem("——————", "SEP");
        _menu.addItem("Delete " + impulse.data.name, "DELETE_ATOM", {id: _contextTargetId});
        
        _menu.show(stage.mouseX, stage.mouseY);
    }

    private function onRightClick(e:MouseEvent):Void {
        // Если кликнули не по ноде - показываем дефолтное меню
        _menu.show(e.stageX, e.stageY);
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ESCAPE) {
            _menu.hide();
            if(_fileMenu != null) _fileMenu.hide();
        }
        if (e.keyCode == Keyboard.F5) onToggleView();
        
        // Hotkeys
        if (e.ctrlKey && e.keyCode == Keyboard.Z) UndoManager.getInstance().undo();
        if (e.ctrlKey && e.keyCode == Keyboard.Y) UndoManager.getInstance().redo();
        
        if (e.keyCode == Keyboard.R) onResetClick();
        
        // Delete Key
        if (e.keyCode == Keyboard.DELETE) {
            if (_contextTargetId != null) {
                _editor.deleteAtom(_contextTargetId);
                _contextTargetId = null;
            }
        }
    }

    private function onMenuAction(impulse:Impulse):Void {
        _menu.hide();
        if(_fileMenu != null) _fileMenu.hide();

        var action = impulse.data.action;
        var data = impulse.data.data;
        var x = impulse.data.x;
        var y = impulse.data.y;

        switch (action) {
            case "FILE_SAVE":
                log("Saving...");
                var positions = _editor.getNodePositions();
                ProjectIO.save(_assembly.blueprint, positions);
                log("Saved!");
                return;

            case "FILE_LOAD":
                log("Opening file dialog...");
                
                ProjectIO.load(function(bp) {
                    log("File loaded: " + bp.name);
                    hardReset();
                    _assembly = new Assembly("loaded_asm", bp);
                    _editor = new NodeEditor(_assembly);
                    _editorLayer.addChild(_editor);
                    log("SUCCESS: Loaded " + bp.name);
                });
                return;
                
            case "DELETE_ATOM":
                if (data != null && data.id != null) {
                    _editor.deleteAtom(data.id);
                }
                return;
        }

        if (action == "ADD_ATOM") {
            if (data != null && data.typeId != null) {
                _editor.createAtom(data.typeId, x, y);
            }
        }
    }

    private function onPropertiesRequest(impulse:Impulse):Void {
        var target = impulse.data.atom;
        var view = impulse.data.view;

        var posX = view.x + 100;
        var posY = view.y;

        if (posX > stage.stageWidth - 320) posX = stage.stageWidth - 320;
        if (posY > stage.stageHeight - 200) posY = stage.stageHeight - 200;

        _propertiesWindow.show(target, posX, posY);
    }
}