package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import library.AtomRegistry;
import core.base.Assembly;
import core.data.Blueprint;
import core.logic.SignalQueue;
import core.logic.Impulsys;
import core.logic.Impulse;
import system.managers.UndoManager;
import system.managers.DriverManager;
import editor.NodeEditor;
import ui.ContextMenu;
import ui.DevicePanel;
import ui.PropertiesWindow;
import ui.ButtonComponent;
import ui.SettingsPanel;
import ui.WireType;
import system.io.ProjectIO;
import system.commands.editor.GroupAtomsCommand;
import ecs.ECS;

// Импорты для работы с окнами и либами
import openfl.Lib;
import openfl.events.Event;
import lime.ui.Window;
import lime.ui.WindowAttributes;

#if desktop
import ui.virtual.NativeWindowExtension;
#end

#if html5
import js.html.CanvasElement;
import js.Browser;
#end

/**
 * MAIN APPLICATION v3.4 (Added Main Loop for immediate Driver execution)
 */
class Main extends Sprite {

    private var _editorLayer:Sprite;
    private var _deviceLayer:Sprite;
    private var _uiLayer:Sprite;
    private var _settingsLayer:Sprite;

    private var _editor:NodeEditor;
    private var _devicePanel:DevicePanel;
    private var _menu:ContextMenu;
    private var _fileMenu:ContextMenu;
    private var _propertiesWindow:PropertiesWindow;
    private var _settingsPanel:SettingsPanel;

    private var _assembly:Assembly;
    private var _isEditorMode:Bool = true;

    private var _debugField:TextField;
    private var _hideTimer:haxe.Timer;
    private var _contextTargetId:String = null;

    private var _fileBtn:ButtonComponent;
    private var _settingsBtn:ButtonComponent;

    private var _assemblyStack:Array<{assembly:Assembly, viewState:{x:Float, y:Float, zoom:Float}}>;
    private var _backBtn:ButtonComponent;
    private var _pathField:TextField;

    private var _newAssemblyBtn:ButtonComponent;

    // === ПЕРЕМЕННЫЕ ДЛЯ ОКОН И ВРЕМЕНИ ===
    private var _lastTime:Int = 0;
    
    #if cpp
    private var _overlaySprite:Sprite;
    #end
    
    #if hl
    private var _playerWindow:Window;
    #end

public function new() {
        super();

        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        #end

        setupDebugLog();
        ProjectIO.logger = log;

        AtomRegistry.initialize();

        #if sys
        AtomRegistry.scanFolder("library");
        #end

        log("System initialized");

        ECS.init();
        log("ECS initialized");

        _assemblyStack = [];

        var emptyBlueprint = new Blueprint("main_scheme", "Main Scheme", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        _assembly = new Assembly("main_asm", emptyBlueprint);

        setupLayers();
        buildUI();
        
        // === ЗАПУСК ГЛАВНОГО ЦИКЛА ОБРАБОТКИ СИГНАЛОВ ===
        // DriverManager запускается сам при регистрации драйвера.
        // Но SignalQueue нужно "прокручивать" вручную, чтобы импульсы доходили.
        addEventListener(Event.ENTER_FRAME, onMainLoop);
    }

    // === ГЛАВНЫЙ ЦИКЛ (HEARTBEAT) ===
    private function onMainLoop(e:Event):Void {
        // 1. Считаем дельту времени (dt)
        var now = Lib.getTimer();
        var dt = (now - _lastTime) / 1000.0;
        _lastTime = now;

        // 2. Обновляем менеджер драйверов (это "тикает" все атомы)
        // Если у вашего DriverManager есть метод update, он должен вызываться здесь.
        // Если DriverManager автоматически управляет атомами, добавленными в него.
        if (DriverManager.getInstance() != null) {
        //   DriverManager.getInstance().update(dt);
        }

        // 3. Обрабатываем очередь сигналов (Impulsys)
        // Чтобы импульсы проходили сразу, а не ждали клика
        if (SignalQueue.getInstance() != null) {
            SignalQueue.getInstance().process();
        }
        
        // 4. Обновляем нативное окно (для C++)
        #if cpp
        // NativeWindowExtension.pollEvents();
        // Если оверлей активен и контент меняется динамически, можно обновлять тут:
        // if (_overlaySprite != null && _overlaySprite.visible) {
        //    NativeWindowExtension.updateFromSprite(_overlaySprite); 
        // }
        #end
    }

    private function log(msg:String) {
        trace(msg);
        if (_hideTimer != null) _hideTimer.stop();
        if (_debugField != null) {
            _debugField.text = msg;
            _debugField.alpha = 1.0;
            _debugField.visible = true;
        }
        _hideTimer = haxe.Timer.delay(() -> { fadeOutLog(); }, 5000);
    }

    private function fadeOutLog() {
        if (_debugField != null) _debugField.visible = false;
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

        _settingsLayer = new Sprite();
        _settingsLayer.mouseEnabled = false;
        addChild(_settingsLayer);
    }

    private function buildUI():Void {
        _backBtn = new ButtonComponent("<- BACK", onBackClick);
        _backBtn.x = 10;
        _backBtn.y = -10;
        _backBtn.visible = false;
        _uiLayer.addChild(_backBtn);

        var toggleBtn = new ButtonComponent("Toggle View [F5]", onToggleView);
        toggleBtn.x = 120;
        toggleBtn.y = 10;
        _uiLayer.addChild(toggleBtn);

        _fileBtn = new ButtonComponent("File", onFileClick);
        _fileBtn.x = 280;
        _fileBtn.y = 10;
        _uiLayer.addChild(_fileBtn);

        _settingsBtn = new ButtonComponent("[S]", onSettingsClick);
        _settingsBtn.x = 440;
        _settingsBtn.y = 10;
        _uiLayer.addChild(_settingsBtn);

        var resetBtn = new ButtonComponent("Reset [R]", onResetClick);
        resetBtn.x = 520;
        resetBtn.y = 10;
        _uiLayer.addChild(resetBtn);

        var playerBtn = new ButtonComponent("Launch Player", onLaunchPlayer);
        playerBtn.x = 680;
        playerBtn.y = 10;
        _uiLayer.addChild(playerBtn);

        _newAssemblyBtn = new ButtonComponent("New Assembly", onNewAssembly);
        _newAssemblyBtn.x = 840;
        _newAssemblyBtn.y = 10;
        _uiLayer.addChild(_newAssemblyBtn);

        _pathField = new TextField();
        _pathField.width = 400;
        _pathField.height = 20;
        _pathField.x = 10;
        _pathField.y = 40;
        _pathField.selectable = false;
        _pathField.mouseEnabled = false;
        var pathFmt = new TextFormat("_typewriter", 11, 0x888888);
        _pathField.defaultTextFormat = pathFmt;
        _pathField.text = "/ Main Scheme";
        _uiLayer.addChild(_pathField);

        _propertiesWindow = new PropertiesWindow();
        _propertiesWindow.visible = false;
        _uiLayer.addChild(_propertiesWindow);

        _settingsPanel = new SettingsPanel();
        _settingsPanel.visible = false;
        _settingsPanel.onSettingsChanged = onSettingsChanged;
        _settingsLayer.addChild(_settingsPanel);

        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);

        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.subscribeToImpulse("CLOSE_CONTEXT_MENU", onCloseContextMenu);
        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("NODE_RIGHT_CLICKED", onNodeRightClick);
        Impulsys.subscribeToImpulse("OPEN_ASSEMBLY_REQUEST", onOpenAssemblyRequest);
    }

    private function onSettingsClick():Void {
        if (_settingsPanel.visible) {
            _settingsPanel.visible = false;
        } else {
            _settingsPanel.show(stage.stageWidth, stage.stageHeight);
            updateSettingsStats();
        }
    }

    private function onSettingsChanged():Void {
        if (_editor != null) {
            _editor.setUseEcsRender(_settingsPanel.useEcsRender);
            _editor.setWireType(_settingsPanel.wireType);
            _editor.setAllowAssembly(_settingsPanel.allowAssembly);
        }
        
        _newAssemblyBtn.visible = _settingsPanel.allowAssembly;
        
        if (!_settingsPanel.allowAssembly && _assemblyStack.length > 0) {
            while (_assemblyStack.length > 0) {
                onBackClick();
            }
        }
        _backBtn.visible = _settingsPanel.allowAssembly && (_assemblyStack.length > 0);
        
        log("Render: " + (_settingsPanel.useEcsRender ? "ECS" : "Direct") 
            + ", Wire: " + Std.string(_settingsPanel.wireType)
            + ", Assembly: " + (_settingsPanel.allowAssembly ? "Allowed" : "Disabled"));
        updateSettingsStats();
    }

    private function updateSettingsStats():Void {
        if (_settingsPanel != null && _editor != null) {
            var nodeCount = _editor.getNodeCount();
            var wireCount = _editor.getWireCount();
            _settingsPanel.updateStats(nodeCount, wireCount, _settingsPanel.useEcsRender, _settingsPanel.wireType, _settingsPanel.allowAssembly);
        }
    }

    private function onBackClick():Void {
        if (_assemblyStack.length == 0) {
            log("Already at root level");
            return;
        }

        _editor.dispose();
        _editorLayer.removeChild(_editor);

        var prev = _assemblyStack.pop();
        _assembly = prev.assembly;

        _editor = new NodeEditor(_assembly);
        _editor.setViewState(prev.viewState);
        _editor.setUseEcsRender(_settingsPanel.useEcsRender);
        _editor.setWireType(_settingsPanel.wireType);
        _editor.setAllowAssembly(_settingsPanel.allowAssembly);
        _editorLayer.addChild(_editor);

        updateNavigationUI();
        log("Navigated back");
    }

    private function updateNavigationUI():Void {
        _backBtn.visible = _settingsPanel.allowAssembly && (_assemblyStack.length > 0);

        var path = "/ " + _assembly.blueprint.name;
        for (item in _assemblyStack) {
            path += " / " + item.assembly.blueprint.name;
        }
        _pathField.text = path;
    }

    private function resetContextMenu():Void {
        if (_menu == null) {
            _menu = new ContextMenu();
            _uiLayer.addChild(_menu);
        }
        _uiLayer.removeChild(_menu);
        _menu = new ContextMenu();
        _uiLayer.addChild(_menu);
    }

    private function onRightClick(e:MouseEvent):Void {
        resetContextMenu();
        buildAtomMenu();
        _menu.show(e.stageX, e.stageY);
    }

    private function onNodeRightClick(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) {
            log("ERROR: Invalid impulse in onNodeRightClick");
            return;
        }

        _contextTargetId = impulse.data.id;

        resetContextMenu();
        buildAtomMenu();

        _menu.addItem("——————", "SEP");
        _menu.addItem("Delete " + impulse.data.name, "DELETE_ATOM", {id: _contextTargetId});

        var selected = _editor.getSelectedNodeIds();
        if (_settingsPanel.allowAssembly && selected.length > 1) {
            _menu.addItem("Group to Assembly", "GROUP_ATOMS", {id: _contextTargetId});
        }

        _menu.show(stage.mouseX, stage.mouseY);
    }

    private function buildAtomMenu():Void {
        var ids = AtomRegistry.getAllIds();
        ids.sort(function(a, b) return Reflect.compare(a, b));
        for (id in ids) {
            var bp = AtomRegistry.get(id);
            if (bp != null) _menu.addItem("Add " + bp.name, "ADD_ATOM", {typeId: id});
        }
    }

    private function onMenuAction(impulse:Impulse):Void {
        if (_menu != null) _menu.hide();
        if (_fileMenu != null) _fileMenu.hide();

        if (impulse == null) {
            log("ERROR: Received NULL impulse in onMenuAction");
            return;
        }

        if (impulse.data == null) {
            log("ERROR: Impulse data is NULL in onMenuAction");
            return;
        }

        if (impulse.data.action == null) {
            log("ERROR: Impulse action is NULL in onMenuAction");
            return;
        }

        var action = impulse.data.action;
        var data = impulse.data.data;
        var x = impulse.data.x;
        var y = impulse.data.y;

        switch (action) {
            case "FILE_SAVE":
                log("Saving...");
                var positions = _editor.getNodePositions();
                var viewState = _editor.getViewState();
                ProjectIO.save(_assembly.blueprint, positions, viewState);
                log("Saved!");
                return;

            case "FILE_LOAD":
                log("Opening file dialog...");
                ProjectIO.load(function(loadData) {
                    try {
                        log("File loaded: " + loadData.blueprint.name);

                        _assemblyStack = [];

                        hardReset();
                        _assembly = new Assembly("loaded_asm", loadData.blueprint);
                        _editor = new NodeEditor(_assembly);
                        _editor.setViewState(loadData.viewState);
                        _editor.setUseEcsRender(_settingsPanel.useEcsRender);
                        _editor.setWireType(_settingsPanel.wireType);
                        _editor.setAllowAssembly(_settingsPanel.allowAssembly);
                        _editorLayer.addChild(_editor);

                        updateNavigationUI();
                        log("SUCCESS: Loaded " + loadData.blueprint.name);
                    } catch (e:Dynamic) {
                        log("ERROR in load callback: " + Std.string(e));
                    }
                });
                return;

            case "DELETE_ATOM":
                if (data != null && data.id != null) {
                    _editor.deleteAtom(data.id);
                    _contextTargetId = null;
                    updateSettingsStats();
                }
                return;

            case "GROUP_ATOMS":
                if (_settingsPanel.allowAssembly) {
                    groupSelectedToAssembly();
                } else {
                    log("Assembly is disabled in settings");
                }
                return;
        }

        if (action == "ADD_ATOM") {
            if (data != null && data.typeId != null) {
                _editor.createAtom(data.typeId, x, y);
                updateSettingsStats();
            }
        }
    }

    private function onCloseContextMenu(i:Impulse):Void {
        if (_menu != null) _menu.hide();
        if (_fileMenu != null) _fileMenu.hide();
    }

    private function groupSelectedToAssembly():Void {
        var selectedIds = _editor.getSelectedNodeIds();
        if (selectedIds.length < 1) {
            log("Select atoms to group.");
            return;
        }

        log("Grouping " + selectedIds.length + " atoms...");

        var cmd = new GroupAtomsCommand(_assembly.blueprint, _assembly, selectedIds);
        cmd.execute();

        var vs = _editor.getViewState();
        _editor.dispose();
        _editorLayer.removeChild(_editor);

        _editor = new NodeEditor(_assembly);
        _editor.setViewState(vs);
        _editor.setUseEcsRender(_settingsPanel.useEcsRender);
        _editor.setWireType(_settingsPanel.wireType);
        _editor.setAllowAssembly(_settingsPanel.allowAssembly);
        _editorLayer.addChild(_editor);

        log("Grouping complete.");
        updateSettingsStats();
    }

    private function onNewAssembly():Void {
        if (!_settingsPanel.allowAssembly) {
            log("Assembly is disabled in settings");
            return;
        }

        hardReset();
        _assemblyStack = [];

        var bp = new Blueprint("new_assembly", "New Assembly", []);
        _assembly = new Assembly("main_asm", bp);
        _editor = new NodeEditor(_assembly);
        _editor.setUseEcsRender(_settingsPanel.useEcsRender);
        _editor.setWireType(_settingsPanel.wireType);
        _editor.setAllowAssembly(_settingsPanel.allowAssembly);
        _editorLayer.addChild(_editor);

        updateNavigationUI();
        log("Created New Empty Assembly");
    }

    private function onOpenAssemblyRequest(impulse:Impulse):Void {
        if (!_settingsPanel.allowAssembly) {
            log("Assembly editing is disabled in settings");
            return;
        }

        if (impulse == null || impulse.data == null) {
            log("ERROR: Invalid impulse in onOpenAssemblyRequest");
            return;
        }

        var id = impulse.data.atomId;
        var obj = _assembly.internalAtoms.get(id);

        if (obj == null) return;

        var atomInst = cast(obj, core.base.Atom);
        var bp = AtomRegistry.get(atomInst.type);

        if (bp != null && bp.internalAtoms != null && bp.internalAtoms.length > 0) {
            var currentViewState = _editor.getViewState();
            _assemblyStack.push({
                assembly: _assembly,
                viewState: currentViewState
            });

            if (_editor != null) {
                _editor.dispose();
                _editorLayer.removeChild(_editor);
            }

            _assembly = new Assembly("nested_view", bp);
            _editor = new NodeEditor(_assembly);
            _editor.setUseEcsRender(_settingsPanel.useEcsRender);
            _editor.setWireType(_settingsPanel.wireType);
            _editor.setAllowAssembly(_settingsPanel.allowAssembly);
            _editorLayer.addChild(_editor);

            updateNavigationUI();
            log("Opened nested assembly: " + bp.name);
        } else {
            log("Atom is primitive, cannot open.");
        }
    }

    private function onLaunchPlayer():Void {
        log("Launching Virtual Device Window...");

        #if cpp
        log("Target C++: Creating Native Overlay...");
        
        NativeWindowExtension.destroyWindow(); 
        
        NativeWindowExtension.createWindow(1280, 500, "ALTAURI Overlay");
        
        if (_overlaySprite == null) {
            _overlaySprite = new Sprite();
        }
        
        while (_overlaySprite.numChildren > 0) {
            _overlaySprite.removeChildAt(0);
        }
        
        var panel = new DevicePanel(_assembly);
        _overlaySprite.addChild(panel);
        
        NativeWindowExtension.updateFromSprite();
        
        // Цикл обновления уже запущен глобально в onMainLoop, тут ничего добавлять не нужно

        #elseif hl
        log("Target HL: Creating Standard Window...");
        
        if (_playerWindow != null) {
            _playerWindow.focus();
            return;
        }

        var attributes:WindowAttributes = {
            width: 1280,
            height: 500,
            title: "ALTAURI Player",
          //  transparent: false,
            resizable: true
        };

        _playerWindow = Lib.application.createWindow(attributes);
        
        if (_playerWindow.stage != null) {
            var panel = new DevicePanel(_assembly);
            _playerWindow.stage.addChild(panel);
        }

        #else
        log("Target not supported for separate window. Switching to Device View.");
        onToggleView();
        #end
    }

    private function onResetClick():Void {
        hardReset();
        _assemblyStack = [];

        var emptyBlueprint = new Blueprint("main_scheme", "Main Scheme", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        _assembly = new Assembly("main_asm", emptyBlueprint);
        _editor = new NodeEditor(_assembly);
        _editor.setUseEcsRender(_settingsPanel.useEcsRender);
        _editor.setWireType(_settingsPanel.wireType);
        _editor.setAllowAssembly(_settingsPanel.allowAssembly);
        _editorLayer.addChild(_editor);

        updateNavigationUI();
        log("System Reset Complete.");
    }

    private function hardReset():Void {
        log("SYSTEM: Hard Reset initiated...");
        DriverManager.getInstance().dispose();
        SignalQueue.getInstance().clear();
        UndoManager.getInstance().clear();

        if (_editor != null) {
            _editor.dispose();
            _editorLayer.removeChild(_editor);
            _editor = null;
        }

        if (_assembly != null) {
            _assembly.dispose();
            _assembly = null;
        }

        ECS.reset();
        log("SYSTEM: Memory cleared. ECS reset.");
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
        if (_fileBtn != null) {
            _fileMenu.show(_fileBtn.x, _fileBtn.y + 40);
        } else {
            _fileMenu.show(280, 50);
        }
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.S && !e.ctrlKey) {
            onSettingsClick();
            return;
        }

        if (e.keyCode == Keyboard.ESCAPE) {
            if (_settingsPanel.visible) {
                _settingsPanel.visible = false;
                return;
            }
            if (_menu != null) _menu.hide();
            if (_fileMenu != null) _fileMenu.hide();

            if (_settingsPanel.allowAssembly && _assemblyStack.length > 0) {
                onBackClick();
            }
        }
        if (e.keyCode == Keyboard.F5) onToggleView();

        if (e.ctrlKey && e.keyCode == Keyboard.Z) UndoManager.getInstance().undo();
        if (e.ctrlKey && e.keyCode == Keyboard.Y) UndoManager.getInstance().redo();

        if (e.keyCode == Keyboard.R) onResetClick();

        if (e.keyCode == Keyboard.BACKSPACE) {
            if (_settingsPanel.allowAssembly) {
                onBackClick();
            }
        }

        if (e.keyCode == Keyboard.DELETE) {
            if (_contextTargetId != null) {
                _editor.deleteAtom(_contextTargetId);
                _contextTargetId = null;
                updateSettingsStats();
            }
        }
    }

    private function onPropertiesRequest(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) {
            log("ERROR: Invalid impulse in onPropertiesRequest");
            return;
        }

        var target = impulse.data.atom;
        var view = impulse.data.view;
        var posX = view.x + 100;
        var posY = view.y;
        if (posX > stage.stageWidth - 320) posX = stage.stageWidth - 320;
        if (posY > stage.stageHeight - 200) posY = stage.stageHeight - 200;
        _propertiesWindow.show(target, posX, posY);
    }
}