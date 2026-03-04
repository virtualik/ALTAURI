package;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.geom.Point;
import library.AtomRegistry;
import core.base.Assembly;
import core.base.Atom;
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
import system.commands.editor.CreateNewAssemblyCommand;
import system.commands.editor.AddPortCommand;
import system.commands.editor.RemovePortCommand;
import ecs.ECS;
import core.types.ContactType;

import openfl.Lib;
import openfl.events.Event;

// Исправление: добавляем StringTools для работы со строками
using StringTools;

#if sys
import sys.FileSystem;
import sys.io.File;
// import sys.io.Path; // Убираем проблемный импорт
#end

#if desktop
import ui.virtual.NativeWindowExtension;
#end

#if html5
import js.html.CanvasElement;
import js.Browser;
#end

class Main extends Sprite {

    // Paths
    private var _documentsPath:String;
    private var _libraryPath:String;
    private var _selfrunPath:String;

    private var _editorLayer:Sprite;
    private var _deviceLayer:Sprite;
    private var _uiLayer:Sprite;
    private var _settingsLayer:Sprite;

    private var _editorStack:Array<{
        assembly:Assembly,
        editor:NodeEditor,
        blocker:Sprite,
        container:Sprite
    }>;

    private var _currentAssembly:Assembly;
    private var _currentEditor:NodeEditor;

    private var _devicePanel:DevicePanel;
    private var _menu:ContextMenu;
    private var _fileMenu:ContextMenu;
    private var _propertiesWindow:PropertiesWindow;
    private var _settingsPanel:SettingsPanel;

    private var _isEditorMode:Bool = true;

    private var _debugField:TextField;
    private var _hideTimer:haxe.Timer;
    private var _contextTargetId:String = null;

    // Buttons
    private var _btnBack:ButtonComponent;
    private var _btnSave:ButtonComponent;
    private var _btnLoad:ButtonComponent;
    private var _btnNew:ButtonComponent;
    private var _btnView:ButtonComponent;
    private var _btnSettings:ButtonComponent;

    private var _pathField:TextField;
    private var _nameField:TextField; // Moved name field

    private var _lastTime:Int = 0;

    private var _cbPortRightClick:Impulse -> Void;

    public function new() {
        super();

        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        #end

        setupDebugLog();
        ProjectIO.logger = log;

        // --- PATH SETUP ---
        setupPaths();

        AtomRegistry.initialize();
        AtomRegistry.scanFolder(_libraryPath);

        log("System initialized");
        ECS.init();

        _editorStack = [];

        setupLayers();

        if (stage != null) init();
        else addEventListener(Event.ADDED_TO_STAGE, init);
    }

    private function setupPaths():Void {
        #if sys
        // Determine Documents Path
        var home = Sys.getEnv("HOME");
        if (home == null) home = Sys.getEnv("USERPROFILE");

        if (home != null) {
            // Manual normalization of path
            home = home.replace("\\", "/");
            if (!home.endsWith("/")) home += "/";
            _documentsPath = home + "Documents";
        } else {
            _documentsPath = Sys.getCwd(); // Fallback
        }

        var altairRoot = _documentsPath + "/ALTAURI";
        _libraryPath = altairRoot + "/Library";
        _selfrunPath = altairRoot + "/Selfrun.atom";

        // Ensure directories exist
        if (!FileSystem.exists(altairRoot)) FileSystem.createDirectory(altairRoot);
        if (!FileSystem.exists(_libraryPath)) FileSystem.createDirectory(_libraryPath);

        AtomRegistry.customLibraryPath = _libraryPath;
        #else
        // Fallback for non-sys targets
        _selfrunPath = "Selfrun.atom";
        _libraryPath = "library";
        #end
    }

    private function init(e:Event = null):Void {
        removeEventListener(Event.ADDED_TO_STAGE, init);

        DriverManager.getInstance();
        SignalQueue.getInstance();

        addEventListener(Event.ENTER_FRAME, onMainLoop);

        buildUI();

        stage.addEventListener(Event.RESIZE, onResize);

        // --- AUTO LOAD SELFRUN ---
        loadSelfrun();
    }

    private function loadSelfrun():Void {
        var rootAssembly:Assembly = null;

        #if sys
        if (FileSystem.exists(_selfrunPath)) {
            log("Loading Selfrun...");
            try {
                var content = File.getContent(_selfrunPath);
                var json = haxe.Json.parse(content);
                var rawBp:Dynamic = json.blueprint;

                // Parse Blueprint manually to ensure types are correct
                var bp = parseBlueprintFromJson(rawBp);

                rootAssembly = new Assembly("main_asm", bp);

                // Restore view state if exists
                var viewState = {x: 0.0, y: 0.0, zoom: 1.0};
                if (json.editor != null) {
                    viewState.x = json.editor.x;
                    viewState.y = json.editor.y;
                    viewState.zoom = json.editor.zoom;
                }

                pushEditor(rootAssembly, true);
                // Apply view state after push
                _currentEditor.setViewState(viewState);
                log("Selfrun loaded.");

            } catch (err:Dynamic) {
                log("Error parsing Selfrun: " + Std.string(err));
                createEmptySelfrun(); // Fallback
            }
        } else {
            createEmptySelfrun();
        }
        #else
        createEmptySelfrun();
        #end
    }

    private function createEmptySelfrun():Void {
        log("Creating new Selfrun...");
        var emptyBlueprint = new Blueprint("selfrun", "Selfrun", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        var rootAssembly = new Assembly("main_asm", emptyBlueprint);
        pushEditor(rootAssembly, true);
    }

    private function parseBlueprintFromJson(rawBp:Dynamic):Blueprint {
        var pins:Array<core.data.Blueprint.PinDef> = [];
        if (rawBp.pins != null) {
            for (p in (cast(rawBp.pins, Array<Dynamic>))) {
                pins.push({
                    name: Std.string(p.name),
                    type: parseContactType(p.type), // Local helper
                    defaultValue: p.defaultValue,
                    dataType: Std.string(p.dataType)
                });
            }
        }

        var conns = [];
        if (rawBp.internalConnections != null) {
            for(c in (cast(rawBp.internalConnections, Array<Dynamic>))) {
                conns.push({
                    from: { atomId: Std.string(c.from.atomId), contactName: Std.string(c.from.contactName) },
                    to: { atomId: Std.string(c.to.atomId), contactName: Std.string(c.to.contactName) }
                });
            }
        }

        var atoms = [];
        if (rawBp.internalAtoms != null) {
            for(a in (cast(rawBp.internalAtoms, Array<Dynamic>))) {
                atoms.push({
                    instanceId: Std.string(a.instanceId),
                    typeId: Std.string(a.typeId),
                    x: a.x,
                    y: a.y
                });
            }
        }

        return new Blueprint(
            Std.string(rawBp.id),
            Std.string(rawBp.name),
            pins,
            null,
            atoms,
            conns,
            Std.string(rawBp.category)
        );
    }

    // Local helper to avoid dependency on AtomRegistry private methods
    private function parseContactType(val:Dynamic):ContactType {
        if (Std.isOfType(val, ContactType)) return val;
        if (Std.isOfType(val, String)) {
            switch(Std.string(val)) {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        if (Std.isOfType(val, Int) || Std.isOfType(val, Float)) {
            var index = Std.int(val);
            switch(index) {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        return UNDEFINED;
    }

    private function pushEditor(assembly:Assembly, isRoot:Bool = false):Void {
        if (!isRoot && _editorStack.length > 0) {
            var top = _editorStack[_editorStack.length - 1];

            var blocker = new Sprite();
            blocker.graphics.beginFill(0x000000, 0.6);
            blocker.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            blocker.graphics.endFill();
            blocker.addEventListener(MouseEvent.CLICK, function(e) { e.stopPropagation(); });

            _editorLayer.addChild(blocker);

            top.editor.mouseEnabled = false;
            top.editor.mouseChildren = false;

            top.blocker = blocker;
        }

        var container = new Sprite();

        // Frame is handled by resize logic now, but we draw initial here
        drawContainerFrame(container);

        _editorLayer.addChild(container);

        var editor = new NodeEditor(assembly);
        editor.setSize(container.width, container.height);
        container.addChild(editor);

        _editorStack.push({
            assembly: assembly,
            editor: editor,
            blocker: null,
            container: container
        });

        _currentEditor = editor;
        _currentAssembly = assembly;

        updateNavigationUI();
        updateButtonStates();
    }

    private function drawContainerFrame(container:Sprite):Void {
        var margin = 12; // 24px total margin (12 left + 12 right)
        var w = stage.stageWidth - margin * 2;
        var h = stage.stageHeight - margin * 2;

        container.graphics.clear();
        container.graphics.beginFill(0x222222);
        container.graphics.lineStyle(2, 0x00AAFF);
        container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        container.graphics.endFill();

        container.x = margin;
        container.y = margin;
    }

    private function popEditor():Void {
        if (_editorStack.length <= 1) {
            log("Cannot close root assembly.");
            return;
        }

        var current = _editorStack.pop();
        current.editor.dispose();
        _editorLayer.removeChild(current.container);

        var prev = _editorStack[_editorStack.length - 1];

        if (prev.blocker != null) {
            _editorLayer.removeChild(prev.blocker);
            prev.blocker = null;
        }

        prev.editor.mouseEnabled = true;
        prev.editor.mouseChildren = true;

        _currentEditor = prev.editor;
        _currentAssembly = prev.assembly;

        updateNavigationUI();
        updateButtonStates();
        log("Returned to: " + _currentAssembly.blueprint.name);
    }

    private function onMainLoop(e:Event):Void {
        var now = Lib.getTimer();
        var dt = (now - _lastTime) / 1000.0;
        _lastTime = now;

        SignalQueue.getInstance().process();
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

    private function fadeOutLog() { if (_debugField != null) _debugField.visible = false; }

    private function setupDebugLog() {
        _debugField = new TextField();
        _debugField.width = 600; _debugField.height = 30;
        _debugField.x = 10; _debugField.y = stage.stageHeight - 40;
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
        // --- Top Right Buttons ---
        var btnSize = 40;
        var btnPadding = 5;
        var startX = stage.stageWidth - btnPadding;
        var startY = btnPadding;

        // Order: Back, View, New, Load, Save (Right to Left)
        
        _btnBack = new ButtonComponent("<", popEditor);
        _btnBack.x = startX - btnSize; _btnBack.y = startY;
        _uiLayer.addChild(_btnBack);

        _btnView = new ButtonComponent("V", onToggleView);
        _btnView.x = _btnBack.x - btnSize - btnPadding; _btnView.y = startY;
        _uiLayer.addChild(_btnView);

        _btnNew = new ButtonComponent("N", onNewAssembly);
        _btnNew.x = _btnView.x - btnSize - btnPadding; _btnNew.y = startY;
        _uiLayer.addChild(_btnNew);

        _btnLoad = new ButtonComponent("L", onFileLoad);
        _btnLoad.x = _btnNew.x - btnSize - btnPadding; _btnLoad.y = startY;
        _uiLayer.addChild(_btnLoad);

        _btnSave = new ButtonComponent("S", saveCurrentContext);
        _btnSave.x = _btnLoad.x - btnSize - btnPadding; _btnSave.y = startY;
        _uiLayer.addChild(_btnSave);

        _btnSettings = new ButtonComponent("?", onSettingsClick);
        _btnSettings.x = _btnSave.x - btnSize - btnPadding; _btnSettings.y = startY;
        _uiLayer.addChild(_btnSettings);


        // --- Name Field (Top Left) ---
        _nameField = new TextField();
        _nameField.defaultTextFormat = new TextFormat("_typewriter", 16, 0x00AAFF, true);
        _nameField.text = "Selfrun";
        _nameField.autoSize = LEFT;
        _nameField.selectable = false;
        _nameField.mouseEnabled = false;
        _nameField.x = 20; // Outside frame margin
        _nameField.y = 5;  // Top alignment
        _uiLayer.addChild(_nameField);

        // --- Path Field (Bottom Left) ---
        _pathField = new TextField();
        _pathField.width = 400; _pathField.height = 20;
        _pathField.x = 10; _pathField.y = stage.stageHeight - 20;
        _pathField.selectable = false; _pathField.mouseEnabled = false;
        var pathFmt = new TextFormat("_typewriter", 11, 0x888888);
        _pathField.defaultTextFormat = pathFmt;
        _uiLayer.addChild(_pathField);

        // --- Windows ---
        _propertiesWindow = new PropertiesWindow();
        _propertiesWindow.visible = false;
        _uiLayer.addChild(_propertiesWindow);

        _settingsPanel = new SettingsPanel();
        _settingsPanel.visible = false;
        _settingsPanel.onSettingsChanged = onSettingsChanged;
        _settingsLayer.addChild(_settingsPanel);

        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);

        _cbPortRightClick = onPortRightClick;

        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.subscribeToImpulse("CLOSE_CONTEXT_MENU", onCloseContextMenu);
        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("NODE_RIGHT_CLICKED", onNodeRightClick);
        Impulsys.subscribeToImpulse("OPEN_ASSEMBLY_REQUEST", onOpenAssemblyRequest);
        Impulsys.subscribeToImpulse("WIRE_RIGHT_CLICKED", onWireRightClick);
        Impulsys.subscribeToImpulse("PORT_RIGHT_CLICKED", _cbPortRightClick);
        Impulsys.subscribeToImpulse("REQUEST_NEW_ASSEMBLY_CONTEXT", onRequestNewContext);
    }

    private function onResize(e:Event):Void {
        // Resize debug field
        _debugField.y = stage.stageHeight - 40;
        _pathField.y = stage.stageHeight - 20;

        // Reposition buttons
        var btnSize = 40; // Approximation
        var btnPadding = 5;
        var rightEdge = stage.stageWidth - btnPadding;

        _btnBack.x = rightEdge - btnSize;
        _btnView.x = _btnBack.x - btnSize - btnPadding;
        _btnNew.x = _btnView.x - btnSize - btnPadding;
        _btnLoad.x = _btnNew.x - btnSize - btnPadding;
        _btnSave.x = _btnLoad.x - btnSize - btnPadding;
        _btnSettings.x = _btnSave.x - btnSize - btnPadding;

        // Resize current editor container
        if (_currentEditor != null) {
            var margin = 12;
            var w = stage.stageWidth - margin * 2;
            var h = stage.stageHeight - margin * 2;
            
            var container = _editorStack[_editorStack.length - 1].container;
            drawContainerFrame(container);
            _currentEditor.setSize(w, h);
        }
    }

    private function updateButtonStates():Void {
        var isRoot = (_editorStack.length <= 1);
        _btnBack.visible = !isRoot;
        _btnNew.visible = _settingsPanel.allowAssembly;
    }

    private function saveCurrentContext():Void {
        #if sys
        var isRoot = (_editorStack.length == 1);

        if (isRoot) {
            // Save Selfrun
            log("Saving Selfrun...");
            saveSelfrun();
        } else {
            // Save Custom Assembly to Library
            log("Saving Assembly to Library...");
            saveAssemblyToLibrary(_currentAssembly);
        }
        #end
    }

    private function saveSelfrun():Void {
        #if sys
        // 1. Update internal atom positions
        var positions = _currentEditor.getNodePositions();
        for (atomDef in _currentAssembly.blueprint.internalAtoms) {
            var nodeData = Lambda.find(positions, function(n) return n.id == atomDef.instanceId);
            if (nodeData != null) { atomDef.x = nodeData.x; atomDef.y = nodeData.y; }
        }

        // 2. Prepare JSON
        var viewState = _currentEditor.getViewState();
        var data:Dynamic = {
            version: "1.1",
            blueprint: _currentAssembly.blueprint,
            editor: viewState
        };

        // 3. Save
        try {
            File.saveContent(_selfrunPath, haxe.Json.stringify(data, null, "  "));
            log("Selfrun saved.");
        } catch(e:Dynamic) { log("Error saving Selfrun: " + e); }

        // 4. Recursively save dirty children
        saveInternalAssemblies(_currentAssembly);
        #end
    }

    private function saveAssemblyToLibrary(asm:Assembly):Void {
        #if sys
        var bp = asm.blueprint;
        if (bp.id == "selfrun" || bp.id == "loaded_asm") return;

        var data:Dynamic = { version: "1.0", blueprint: bp };
        var path = _libraryPath + "/" + bp.id + ".atom";

        try {
            File.saveContent(path, haxe.Json.stringify(data, null, "  "));
            log("Saved: " + bp.id + " to Library");
            AtomRegistry.registerBlueprint(bp.id, bp);
        } catch(e:Dynamic) { log("Error saving assembly: " + e); }
        #end
    }

    private function saveInternalAssemblies(asm:Assembly):Void {
        #if sys
        if (asm.internalAtoms == null) return;
        for (key in asm.internalAtoms.keys()) {
            var sub = asm.internalAtoms.get(key);
            if (Std.isOfType(sub, Assembly)) {
                var subAsm = cast(sub, Assembly);
                // If it's a custom assembly (has internals), save it
                if (subAsm.blueprint.internalAtoms != null && subAsm.blueprint.internalAtoms.length > 0) {
                    saveAssemblyToLibrary(subAsm);
                    saveInternalAssemblies(subAsm); // Recursion
                }
            }
        }
        #end
    }

    private function onFileLoad():Void {
        log("Opening file dialog...");
        ProjectIO.load(function(loadData) {
            try {
                log("File loaded: " + loadData.blueprint.name);
                clearStack();
                var loadedAsm = new Assembly("loaded_asm", loadData.blueprint);
                pushEditor(loadedAsm, true);
                _currentEditor.setViewState(loadData.viewState);
                log("SUCCESS: Loaded " + loadData.blueprint.name);
            } catch (e:Dynamic) { log("ERROR: " + Std.string(e)); }
        });
    }

    private function onOpenAssemblyRequest(impulse:Impulse):Void {
        if (!_settingsPanel.allowAssembly) { log("Assembly editing disabled"); return; }

        var id = impulse.data.atomId;
        var obj = _currentAssembly.internalAtoms.get(id);

        if (Std.isOfType(obj, Assembly)) {
            var targetAsm = cast(obj, Assembly);
            pushEditor(targetAsm);
            log("Opened: " + targetAsm.blueprint.name);
        } else {
            log("Atom is primitive or not found.");
        }
    }

    private function onRequestNewContext(impulse:Impulse):Void {
        var bp:Blueprint = impulse.data.blueprint;
        var id:String = impulse.data.id;

        var newAsm = new Assembly(id, bp);
        pushEditor(newAsm);
        log("Created New Assembly Context");
    }

    private function onSettingsClick():Void {
        if (_settingsPanel.visible) _settingsPanel.visible = false;
        else {
            _settingsPanel.show(stage.stageWidth, stage.stageHeight);
            updateSettingsStats();
        }
    }

    private function onSettingsChanged():Void {
        if (_currentEditor != null) {
            _currentEditor.setUseEcsRender(_settingsPanel.useEcsRender);
            _currentEditor.setWireType(_settingsPanel.wireType);
            _currentEditor.setAllowAssembly(_settingsPanel.allowAssembly);
        }
        updateButtonStates();
    }

    private function updateSettingsStats():Void {
        if (_settingsPanel != null && _currentEditor != null) {
            _settingsPanel.updateStats(_currentEditor.getNodeCount(), _currentEditor.getWireCount(),
                _settingsPanel.useEcsRender, _settingsPanel.wireType, _settingsPanel.allowAssembly);
        }
    }

    private function updateNavigationUI():Void {
        var path = "";
        for (i in 0..._editorStack.length) {
            path += " / " + _editorStack[i].assembly.blueprint.name;
        }
        _pathField.text = path;

        // Update Top Left Name
        if (_currentAssembly != null) {
            _nameField.text = _currentAssembly.blueprint.name;
        }
    }

    private function resetContextMenu():Void {
        if (_menu == null) { _menu = new ContextMenu(); _uiLayer.addChild(_menu); }
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
        if (impulse == null || impulse.data == null) return;
        _contextTargetId = impulse.data.id;

        resetContextMenu();
        buildAtomMenu();

        _menu.addItem("——————", "SEP");
        _menu.addItem("Delete " + impulse.data.name, "DELETE_ATOM", {id: _contextTargetId});

        var selected = _currentEditor.getSelectedNodeIds();
        if (_settingsPanel.allowAssembly && selected.length > 1) {
            _menu.addItem("Group to Assembly", "GROUP_ATOMS", {id: _contextTargetId});
        }
        _menu.show(stage.mouseX, stage.mouseY);
    }

    private function onPortRightClick(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) return;
        resetContextMenu();
        _menu.addItem('Delete Port "${impulse.data.portName}"', "REMOVE_PORT", {name: impulse.data.portName});
        _menu.show(impulse.data.x, impulse.data.y);
    }

    private function onWireRightClick(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) return;
        resetContextMenu();
        var count = impulse.data.ids.length;
        _menu.addItem("Delete Selected Wire" + (count > 1 ? "s" : ""), "DELETE_WIRES", {ids: impulse.data.ids});
        _menu.show(stage.mouseX, stage.mouseY);
    }

    private function buildAtomMenu():Void {
        var ids = AtomRegistry.getAllIds();
        ids.sort(function(a, b) return Reflect.compare(a, b));
        for (id in ids) {
            var bp = AtomRegistry.get(id);
            if (bp != null) _menu.addItem("Add " + bp.name, "ADD_ATOM", {typeId: id});
        }
        _menu.addItem("——————", "SEP");
        _menu.addItem("Add Input Port", "ADD_PORT", {type: INPUT});
        _menu.addItem("Add Output Port", "ADD_PORT", {type: OUTPUT});
    }

    private function onMenuAction(impulse:Impulse):Void {
        if (_menu != null) _menu.hide();
        if (_fileMenu != null) _fileMenu.hide();
        if (impulse == null || impulse.data == null || impulse.data.action == null) return;

        var action = impulse.data.action;
        var data = impulse.data.data;
        var x = impulse.data.x;
        var y = impulse.data.y;

        switch (action) {
            case "FILE_LOAD":
                onFileLoad();
                return;

            case "DELETE_ATOM":
                if (data != null && data.id != null) {
                    _currentEditor.deleteAtom(data.id);
                    _contextTargetId = null;
                    updateSettingsStats();
                }
                return;

            case "DELETE_WIRES":
                _currentEditor.deleteSelectedWires();
                updateSettingsStats();
                return;

            case "GROUP_ATOMS":
                if (_settingsPanel.allowAssembly) groupSelectedToAssembly();
                else log("Assembly disabled");
                return;

            case "ADD_PORT":
                if (data != null && data.type != null) {
                    var cmd = new AddPortCommand(_currentAssembly, data.type);
                    UndoManager.getInstance().executeAndStore(cmd);
                }
                return;

            case "REMOVE_PORT":
                if (data != null && data.name != null) {
                    var cmd = new RemovePortCommand(_currentAssembly, data.name);
                    UndoManager.getInstance().executeAndStore(cmd);
                }
                return;
        }

        if (action == "ADD_ATOM") {
            if (data != null && data.typeId != null) {
                _currentEditor.createAtom(data.typeId, x, y);
                updateSettingsStats();
            }
        }
    }

    private function onCloseContextMenu(i:Impulse):Void {
        if (_menu != null) _menu.hide();
        if (_fileMenu != null) _fileMenu.hide();
    }

    private function groupSelectedToAssembly():Void {
        var selectedIds = _currentEditor.getSelectedNodeIds();
        if (selectedIds.length < 1) { log("Select atoms to group."); return; }

        log("Grouping " + selectedIds.length + " atoms...");
        var cmd = new GroupAtomsCommand(_currentAssembly.blueprint, _currentAssembly, selectedIds);
        cmd.execute();
        _currentEditor.deselectAll();
        log("Grouping complete.");
        updateSettingsStats();
    }

    private function onNewAssembly():Void {
        if (!_settingsPanel.allowAssembly) { log("Assembly disabled"); return; }
        var cmd = new CreateNewAssemblyCommand();
        UndoManager.getInstance().executeAndStore(cmd);
    }

    private function onToggleView():Void {
        _isEditorMode = !_isEditorMode;
        _editorLayer.visible = _isEditorMode;
        _deviceLayer.visible = !_isEditorMode;
        if (!_isEditorMode) {
            while (_deviceLayer.numChildren > 0) _deviceLayer.removeChildAt(0);
            _devicePanel = new DevicePanel(_currentAssembly);
            _deviceLayer.addChild(_devicePanel);
        }
    }

    private function onResetClick():Void {
        hardReset();
        createEmptySelfrun();
        log("System Reset.");
    }

    private function clearStack():Void {
        while (_editorStack.length > 0) {
            var item = _editorStack.pop();
            item.editor.dispose();
            if (item.container.parent != null) _editorLayer.removeChild(item.container);
            if (item.blocker != null && item.blocker.parent != null) _editorLayer.removeChild(item.blocker);
        }
        _currentEditor = null;
        _currentAssembly = null;
    }

    private function hardReset():Void {
        log("SYSTEM: Hard Reset...");
        clearStack();

        Impulsys.clear();
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.subscribeToImpulse("CLOSE_CONTEXT_MENU", onCloseContextMenu);
        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("NODE_RIGHT_CLICKED", onNodeRightClick);
        Impulsys.subscribeToImpulse("OPEN_ASSEMBLY_REQUEST", onOpenAssemblyRequest);
        Impulsys.subscribeToImpulse("WIRE_RIGHT_CLICKED", onWireRightClick);
        Impulsys.subscribeToImpulse("PORT_RIGHT_CLICKED", _cbPortRightClick);
        Impulsys.subscribeToImpulse("REQUEST_NEW_ASSEMBLY_CONTEXT", onRequestNewContext);

        DriverManager.getInstance().dispose();
        SignalQueue.getInstance().clear();
        UndoManager.getInstance().clear();
        ECS.reset();
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        // S - Save
        if (e.keyCode == Keyboard.S && !e.ctrlKey) {
            saveCurrentContext();
            return;
        }

        // ESCAPE - Close Settings or Pop Editor
        if (e.keyCode == Keyboard.ESCAPE) {
            if (_settingsPanel.visible) { _settingsPanel.visible = false; return; }
            if (_menu != null) _menu.hide();
            if (_fileMenu != null) _fileMenu.hide();
            if (_editorStack.length > 1) popEditor();
        }

        if (e.keyCode == Keyboard.F5) onToggleView();
        if (e.ctrlKey && e.keyCode == Keyboard.Z) UndoManager.getInstance().undo();
        if (e.ctrlKey && e.keyCode == Keyboard.Y) UndoManager.getInstance().redo();
        if (e.keyCode == Keyboard.R) onResetClick();
        if (e.keyCode == Keyboard.BACKSPACE) if (_editorStack.length > 1) popEditor();
        if (e.keyCode == Keyboard.DELETE) {
            _currentEditor.deleteSelectedWires();
            if (_contextTargetId != null) {
                _currentEditor.deleteAtom(_contextTargetId);
                _contextTargetId = null;
                updateSettingsStats();
            }
        }
    }

    private function onPropertiesRequest(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) return;
        var target = impulse.data.atom;
        var view = impulse.data.view;
        var posX = view.x + 100;
        var posY = view.y;
        if (posX > stage.stageWidth - 320) posX = stage.stageWidth - 320;
        if (posY > stage.stageHeight - 200) posY = stage.stageHeight - 200;
        _propertiesWindow.show(target, posX, posY);
    }
}