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
import editor.NodeView;
import editor.EditorTheme;
import editor.ContextMenuManager;
import ui.TextInputPopup;
import ui.PropertiesWindow;
import ui.ButtonComponent;
import ui.SettingsPanel;
import ui.WireType;
import ui.DeviceWindow;
import ui.DeviceWindow2;
import system.io.ProjectIO;
import system.commands.editor.GroupAtomsCommand;
import system.commands.editor.CreateNewAssemblyCommand;
import system.commands.editor.AddPortCommand;
import system.commands.editor.RemovePortCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.base.MacroCommand;
import ecs.ECS;
import core.types.ContactType;

import openfl.Lib;
import openfl.events.Event;
import openfl.system.System;

using StringTools;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if html5
import js.html.CanvasElement;
import js.Browser;
#end

class Main extends Sprite {

    private var _appInitialized:Bool = false;

    // Paths
    private var _documentsPath:String;
    private var _libraryPath:String;
    private var _selfrunPath:String;

    private var _editorLayer:Sprite;
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

    // Context Menu Manager
    private var _contextManager:ContextMenuManager;

    private var _propertiesWindow:PropertiesWindow;
    private var _settingsPanel:SettingsPanel;

    private var _popup:TextInputPopup;

    private var _isEditorMode:Bool = true;

    private var _debugField:TextField;
    private var _hideTimer:haxe.Timer;

    // Buttons
    private var _btnBack:ButtonComponent;
    private var _btnReset:ButtonComponent;
    private var _btnNew:ButtonComponent;
    private var _btnView:ButtonComponent;
    private var _btnSettings:ButtonComponent;
    private var _btnDelete:ButtonComponent;
    private var _btnClose:ButtonComponent;

    private var _pathField:TextField;
    private var _nameField:TextField;

    private var _lastTime:Int = 0;
    private var _theme:EditorTheme;

    // DeviceWindow
    private var _deviceWindow:DeviceWindow;
    private var _customSprite:Sprite;
    
    // Кэш состояния окна устройств
    private var _cachedDeviceWindowState:Array<{path:Array<String>, x:Float, y:Float}> = null;

    public function new() {
        super();
        _theme = EditorTheme.getInstance();

        #if html5
        var canvas:CanvasElement = cast Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
        #end

        setupDebugLog();
        ProjectIO.logger = log;
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
        var home = Sys.getEnv("HOME");
        if (home == null) home = Sys.getEnv("USERPROFILE");

        if (home != null) {
            home = home.replace("\\", "/");
            if (!home.endsWith("/")) home += "/";
            _documentsPath = home + "Documents";
        } else {
            _documentsPath = Sys.getCwd();
        }

        var altauriRoot = _documentsPath + "/ALTAURI";
        _libraryPath = altauriRoot + "/Library";
        _selfrunPath = altauriRoot + "/Selfrun.atom";

        if (!FileSystem.exists(altauriRoot)) FileSystem.createDirectory(altauriRoot);
        if (!FileSystem.exists(_libraryPath)) FileSystem.createDirectory(_libraryPath);

        AtomRegistry.customLibraryPath = _libraryPath;
        #else
        _selfrunPath = "Selfrun.atom";
        _libraryPath = "library";
        #end
    }

    private function init(e:Event = null):Void {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        openfl.Lib.current.stage.window.visible = true;

        if (_appInitialized) {
            log("Restoring Editor Window...");
            Lib.current.stage.color = _theme.APP_BG_COLOR;
            stage.addEventListener(Event.RESIZE, onResize);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            #if sys
            openfl.Lib.current.stage.window.onClose.add(saveOnExit);
            #end
            onResize(null);
            updateButtonStates();
            return;
        }

        _appInitialized = true;
        stage.color = _theme.APP_BG_COLOR;

        DriverManager.getInstance();
        SignalQueue.getInstance();

        addEventListener(Event.ENTER_FRAME, onMainLoop);
        buildUI();
        stage.addEventListener(Event.RESIZE, onResize);

        #if sys
        openfl.Lib.current.stage.window.onClose.add(onMainWindowClose);
        #end

        loadSelfrun();
    }

    private function onMainWindowClose():Void {
        log("Main window close requested...");
        saveOnExit();
        if (_deviceWindow != null && _deviceWindow.isOpen) {
            log("Device window is active. Hiding editor instead of exit.");
        } else {
            log("Exiting application.");
            System.exit(0);
        }
    }

    private function saveOnExit():Void {
        log("Auto-saving on exit...");
        saveSelfrun();

        if (_editorStack.length > 1) {
            for (i in 1..._editorStack.length) {
                var entry = _editorStack[i];
                saveAssemblyToLibrary(entry.assembly);
            }
        }
    }

    private function restoreEditorWindow():Void {
        log("Restoring main editor...");
        var config = {
            title: "ALTAURI Editor",
            width: stage != null ? stage.stageWidth : 1024,
            height: stage != null ? stage.stageHeight : 600,
            parameters: { background: 0x111111 }
        };
        var newWindow = Lib.application.createWindow(config);
        newWindow.stage.addChild(this);
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
                var bp = parseBlueprintFromJson(rawBp);

                rootAssembly = new Assembly("main_asm", bp);

                var viewState = {x: 0.0, y: 0.0, zoom: 1.0};
                if (json.editor != null) {
                    viewState.x = json.editor.x;
                    viewState.y = json.editor.y;
                    viewState.zoom = json.editor.zoom;
                }

                pushEditor(rootAssembly, true);
                _currentEditor.setViewState(viewState);

                // Загрузка состояния DeviceWindow
                if (json.deviceWindow != null && json.deviceWindow.devices != null) {
                    // ПАРСИНГ JSON В ТИПИЗИРОВАННЫЙ МАССИВ (Fix for error)
                    _cachedDeviceWindowState = [];
                    var devs:Array<Dynamic> = json.deviceWindow.devices;
                    for (d in devs) {
                        var p:Array<String> = [];
                        if (d.path != null) {
                            for (s in cast(d.path, Array<Dynamic>)) {
                                p.push(Std.string(s));
                            }
                        }
                        _cachedDeviceWindowState.push({
                            path: p,
                            x: d.x,
                            y: d.y
                        });
                    }

                    if (json.deviceWindow.isOpen) {
                        restoreDeviceWindow(rootAssembly);
                    }
                }
                log("Selfrun loaded.");

            } catch (err:Dynamic) {
                log("Error parsing Selfrun: " + Std.string(err));
                createEmptySelfrun();
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

    private function restoreDeviceWindow(rootAssembly:Assembly):Void {
        onToggleView();
    }

    private function findDevicePath(container:Assembly, target:Atom):Array<String> {
        if (container == null || target == null) return null;
        for (runtimeId in container.internalAtoms.keys()) {
            var atom = container.internalAtoms.get(runtimeId);
            if (atom == target) {
                var templateId = container.getTemplateId(runtimeId);
                return [templateId];
            }
            if (Std.isOfType(atom, Assembly)) {
                var subPath = findDevicePath(cast(atom, Assembly), target);
                if (subPath != null) {
                    var templateId = container.getTemplateId(runtimeId);
                    subPath.insert(0, templateId);
                    return subPath;
                }
            }
        }
        return null;
    }

    private function resolveDevicePath(root:Assembly, path:Array<String>):Atom {
        var current:Assembly = root;
        for (i in 0...path.length) {
            var templateId = path[i];
            var runtimeId:String = null;
            if (current.idMap != null) {
                for (tid => rid in current.idMap) {
                    if (tid == templateId) { runtimeId = rid; break; }
                }
            }
            if (runtimeId == null && current.internalAtoms.exists(templateId)) {
                runtimeId = templateId;
            }
            if (runtimeId == null) return null;
            var next = current.internalAtoms.get(runtimeId);
            if (i == path.length - 1) return next;
            else {
                if (Std.isOfType(next, Assembly)) current = cast(next, Assembly);
                else return null;
            }
        }
        return null;
    }

    private function parseBlueprintFromJson(rawBp:Dynamic):Blueprint {
        var pins:Array<core.data.Blueprint.PinDef> = [];
        if (rawBp.pins != null) {
            for (p in (cast(rawBp.pins, Array<Dynamic>))) {
                pins.push({
                    name: Std.string(p.name),
                    type: parseContactType(p.type),
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
                    y: a.y,
                    values: a.values
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
            switch(Std.int(val)) {
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
            blocker.graphics.beginFill(0x808080, 0.6);
            blocker.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            blocker.graphics.endFill();
            blocker.addEventListener(MouseEvent.CLICK, function(e) { e.stopPropagation(); });
            _editorLayer.addChild(blocker);
            top.editor.mouseEnabled = false;
            top.editor.mouseChildren = false;
            top.blocker = blocker;
        }

        var container = new Sprite();
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

        if (_contextManager != null) {
            _contextManager.setContext(_currentEditor, _currentAssembly);
        }

        updateNavigationUI();
        updateButtonStates();
    }

    private function drawContainerFrame(container:Sprite):Void {
        var margin = 12;
        var w = stage.stageWidth - margin * 2;
        var h = stage.stageHeight - margin * 2;

        container.graphics.clear();
        container.graphics.beginFill(_theme.FRAME_FILL_COLOR, _theme.FRAME_FILL_ALPHA);
        container.graphics.lineStyle(2, _theme.FRAME_BORDER_COLOR);
        container.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        container.graphics.endFill();

        container.x = margin;
        container.y = margin;
    }

    private function onCloseClicked():Void {
        _popup.showConfirm("Exit", "Do You want to close Editor?", function(confirmed:Bool) {
            if (confirmed) {
                saveOnExit();
                System.exit(0);
            }
        });
    }

    private function onBackClicked():Void {
        if (_editorStack.length <= 1) {
            log("Cannot close root assembly.");
            return;
        }
        var isUnsaved = !isAssemblyFileExists(_currentAssembly.blueprint.id);
        if (isUnsaved) {
            _popup.show("Save New Assembly", _currentAssembly.blueprint.name, function(name:String) {
                if (name != null && name.length > 0) {
                    saveNewNamedAssembly(name);
                    performPopEditor(true);
                }
            });
        } else {
            saveCurrentContext();
            performPopEditor(true);
        }
    }

    private function onDeleteCurrentAssembly():Void {
        if (_editorStack.length <= 1) {
            log("Cannot delete root assembly.");
            return;
        }
        var bp = _currentAssembly.blueprint;
        var isSaved = isAssemblyFileExists(bp.id);
        var title = "Confirm Erase";
        var message = isSaved
            ? "Assembly '" + bp.name + "' will be erased from Library. Continue?"
            : "Assembly '" + bp.name + "' is not saved and will be discarded. Continue?";

        _popup.showConfirm(title, message, function(confirmed:Bool) {
            if (confirmed) deleteCurrentAssemblyConfirmed(isSaved);
        });
    }

    private function deleteCurrentAssemblyConfirmed(isSaved:Bool):Void {
        var bp = _currentAssembly.blueprint;
        var deletedId = bp.id;
        AtomRegistry.remove(deletedId);
        if (isSaved) {
            #if sys
            var path = _libraryPath + "/" + bp.id + ".atom";
            if (FileSystem.exists(path)) {
                try { FileSystem.deleteFile(path); } catch (e:Dynamic) { log("Error deleting file: " + e); }
            }
            #end
        }
        performPopEditor(false);
        for (entry in _editorStack) recursiveRemoveInstances(entry.assembly, deletedId);
        cleanRegistryDanglingReferences(deletedId);
    }

    private function recursiveRemoveInstances(parent:Assembly, deletedId:String):Void {
        if (parent == null || parent.internalAtoms == null) return;
        var idsToRemove:Array<String> = [];
        for (id in parent.internalAtoms.keys()) {
            var atom = parent.internalAtoms.get(id);
            if (atom != null && Std.isOfType(atom, Assembly)) {
                var asm = cast(atom, Assembly);
                if (asm.blueprint != null && asm.blueprint.id == deletedId) idsToRemove.push(id);
                else recursiveRemoveInstances(asm, deletedId);
            }
        }
        if (idsToRemove.length > 0) {
            var macrocom = new MacroCommand();
            for (id in idsToRemove) macrocom.addCommand(new DeleteAtomCommand(parent.blueprint, parent, id));
            macrocom.execute();
        }
    }

    private function cleanRegistryDanglingReferences(deletedId:String):Void {
        #if sys
        var allIds = AtomRegistry.getAllIds();
        for (bpId in allIds) {
            var bp = AtomRegistry.get(bpId);
            if (bp == null || bp.internalAtoms == null) continue;
            var changed = false;
            var atomsToKeep = [];
            for (atomDef in bp.internalAtoms) {
                if (atomDef.typeId == deletedId) changed = true;
                else atomsToKeep.push(atomDef);
            }
            if (changed) {
                var targetAtoms = bp.internalAtoms; targetAtoms.resize(0);
                for (a in atomsToKeep) targetAtoms.push(a);
                var connsToKeep = [];
                if (bp.internalConnections != null) {
                    for (conn in bp.internalConnections) {
                        var fromValid = false; var toValid = false;
                        if (conn.from.atomId == "SELF") fromValid = true;
                        else { for (a in atomsToKeep) if (a.instanceId == conn.from.atomId) { fromValid = true; break; } }
                        if (conn.to.atomId == "SELF") toValid = true;
                        else { for (a in atomsToKeep) if (a.instanceId == conn.to.atomId) { toValid = true; break; } }
                        if (fromValid && toValid) connsToKeep.push(conn);
                    }
                    var targetConns = bp.internalConnections; targetConns.resize(0);
                    for (c in connsToKeep) targetConns.push(c);
                }
                saveBlueprintToDisk(bp);
            }
        }
        #end
    }

    private function saveBlueprintToDisk(bp:Blueprint):Void {
        #if sys
        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in bp.internalAtoms) atomsToSave.push({ instanceId: atomDef.instanceId, typeId: atomDef.typeId, x: atomDef.x, y: atomDef.y });
        var connsToSave:Array<Dynamic> = [];
        for (conn in bp.internalConnections) connsToSave.push({ from: { atomId: conn.from.atomId, contactName: conn.from.contactName }, to: { atomId: conn.to.atomId, contactName: conn.to.contactName } });
        var data:Dynamic = { version: "1.0", blueprint: { id: bp.id, name: bp.name, category: bp.category, pins: bp.pins, internalAtoms: atomsToSave, internalConnections: connsToSave } };
        var path = _libraryPath + "/" + bp.id + ".atom";
        try { File.saveContent(path, haxe.Json.stringify(data, null, "  ")); } catch(e:Dynamic) { trace("Error saving blueprint: " + e); }
        #end
    }

    private function performPopEditor(isUpdate:Bool):Void {
        var current = _editorStack.pop();
        var editedId = current.assembly.blueprint.id;
        current.editor.dispose();
        _editorLayer.removeChild(current.container);
        var prev = _editorStack[_editorStack.length - 1];
        if (prev.blocker != null) { _editorLayer.removeChild(prev.blocker); prev.blocker = null; }
        prev.editor.mouseEnabled = true;
        prev.editor.mouseChildren = true;
        _currentEditor = prev.editor;
        _currentAssembly = prev.assembly;
        if (isUpdate) updateInstancesOf(editedId);
        _currentEditor.refreshAssemblyViews();

        if (_contextManager != null) _contextManager.setContext(_currentEditor, _currentAssembly);

        updateNavigationUI();
        updateButtonStates();
        log("Returned to: " + _currentAssembly.blueprint.name);
    }

    private function updateInstancesOf(typeId:String):Void {
        var newBp = AtomRegistry.get(typeId);
        if (newBp == null) return;
        for (id in _currentAssembly.internalAtoms.keys()) {
            var atom = _currentAssembly.internalAtoms.get(id);
            if (Std.isOfType(atom, Assembly)) {
                var asm = cast(atom, Assembly);
                if (asm.blueprint.id == typeId) asm.updateFromBlueprint(newBp);
            }
        }
    }

    private function isAssemblyFileExists(id:String):Bool {
        #if sys return FileSystem.exists(_libraryPath + "/" + id + ".atom"); #else return true; #end
    }

    private function saveNewNamedAssembly(name:String):Void {
        var safeName = StringTools.replace(name, " ", "_");
        if (safeName.length == 0) { log("Error: Invalid assembly name."); return; }
        var bp = _currentAssembly.blueprint;
        bp.id = safeName;
        bp.name = name;
        saveAssemblyToLibrary(_currentAssembly);
    }

    private function onMainLoop(e:Event):Void {
        var now = Lib.getTimer();
        var dt = (now - _lastTime) / 1000.0;
        _lastTime = now;
        DriverManager.getInstance().update(dt);
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
        _hideTimer = haxe.Timer.delay(function() { fadeOutLog(); }, 5000);
    }
    private function fadeOutLog() { if (_debugField != null) _debugField.visible = false; }

    private function setupDebugLog() {
        _debugField = new TextField();
        _debugField.width = 600; _debugField.height = 30;
        _debugField.x = 10; _debugField.y = stage.stageHeight - 40;
        _debugField.background = true;
        _debugField.backgroundColor = _theme.DEBUG_BG_COLOR;
        _debugField.textColor = _theme.DEBUG_TEXT_COLOR;
        _debugField.selectable = false;
        var fmt = new TextFormat("_sans", 12);
        _debugField.defaultTextFormat = fmt;
        addChild(_debugField);
    }

    private function setupLayers():Void {
        _editorLayer = new Sprite();
        addChild(_editorLayer);
        _uiLayer = new Sprite();
        addChild(_uiLayer);
        _settingsLayer = new Sprite();
        _settingsLayer.mouseEnabled = false;
        addChild(_settingsLayer);
    }

    private function buildUI():Void {
        var btnSize = 40;
        var btnPadding = 5;
        var startX = stage.stageWidth - btnPadding;
        var startY = btnPadding;

        _popup = new TextInputPopup();
        addChild(_popup);

        _btnClose = new ButtonComponent("X", onCloseClicked);
        _btnClose.x = startX - btnSize; _btnClose.y = startY;
        _uiLayer.addChild(_btnClose);

        _btnBack = new ButtonComponent("<", onBackClicked);
        _btnBack.x = _btnClose.x - btnSize - btnPadding; _btnBack.y = startY;
        _uiLayer.addChild(_btnBack);

        _btnDelete = new ButtonComponent("E", onDeleteCurrentAssembly);
        _btnDelete.x = _btnBack.x - btnSize - btnPadding; _btnDelete.y = startY;
        _uiLayer.addChild(_btnDelete);

        _btnView = new ButtonComponent("V", onToggleView);
        _btnView.x = _btnDelete.x - btnSize - btnPadding; _btnView.y = startY;
        _uiLayer.addChild(_btnView);

        _btnNew = new ButtonComponent("N", onNewAssembly);
        _btnNew.x = _btnView.x - btnSize - btnPadding; _btnNew.y = startY;
        _uiLayer.addChild(_btnNew);

        _btnReset = new ButtonComponent("R", onResetClick);
        _btnReset.x = _btnNew.x - btnSize - btnPadding; _btnReset.y = startY;
        _uiLayer.addChild(_btnReset);

        _btnSettings = new ButtonComponent("?", onSettingsClick);
        _btnSettings.x = _btnReset.x - btnSize - btnPadding; _btnSettings.y = startY;
        _uiLayer.addChild(_btnSettings);

        _nameField = new TextField();
        _nameField.defaultTextFormat = new TextFormat("_sans", 24, _theme.TITLE_TEXT_COLOR, true);
        _nameField.text = "Selfrun";
        _nameField.autoSize = LEFT;
        _nameField.selectable = false;
        _nameField.mouseEnabled = false;
        _nameField.x = 20;
        _nameField.y = 5;
        _uiLayer.addChild(_nameField);

        _pathField = new TextField();
        _pathField.width = 400; _pathField.height = 20;
        _pathField.x = 10; _pathField.y = stage.stageHeight - 20;
        _pathField.selectable = false; _pathField.mouseEnabled = false;
        var pathFmt = new TextFormat("_sans", 16, _theme.PATH_TEXT_COLOR);
        _pathField.defaultTextFormat = pathFmt;
        _uiLayer.addChild(_pathField);

        _propertiesWindow = new PropertiesWindow();
        _propertiesWindow.visible = false;
        _uiLayer.addChild(_propertiesWindow);

        _settingsPanel = new SettingsPanel();
        _settingsPanel.visible = false;
        _settingsPanel.onSettingsChanged = onSettingsChanged;
        _settingsLayer.addChild(_settingsPanel);

        _contextManager = new ContextMenuManager(_settingsPanel);
        _uiLayer.addChild(_contextManager.getView());

        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);

        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("OPEN_ASSEMBLY_REQUEST", onOpenAssemblyRequest);
        Impulsys.subscribeToImpulse("REQUEST_NEW_ASSEMBLY_CONTEXT", onRequestNewContext);
        Impulsys.subscribeToImpulse("VALUE_COMMITTED", onValueCommitted);
    }

    private function onNewAssembly():Void {
        if (!_settingsPanel.allowAssembly) { log("Assembly disabled"); return; }
        var cmd = new CreateNewAssemblyCommand();
        UndoManager.getInstance().executeAndStore(cmd);
    }

    private function onValueCommitted(impulse:Impulse):Void {
        saveCurrentContext();
        log("Data saved.");
    }

    private function onResize(e:Event):Void {
        _debugField.y = stage.stageHeight - 40;
        _pathField.y = stage.stageHeight - 20;

        var btnSize = 40;
        var btnPadding = 5;
        var rightEdge = stage.stageWidth - btnPadding;

        _btnClose.x = rightEdge - btnSize;
        _btnBack.x = _btnClose.x - btnSize - btnPadding;
        _btnDelete.x = _btnBack.x - btnSize - btnPadding;
        _btnView.x = _btnDelete.x - btnSize - btnPadding;
        _btnNew.x = _btnView.x - btnSize - btnPadding;
        _btnReset.x = _btnNew.x - btnSize - btnPadding;
        _btnSettings.x = _btnReset.x - btnSize - btnPadding;

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
        _btnDelete.visible = !isRoot;
        _btnNew.visible = _settingsPanel.allowAssembly;
    }

    private function saveCurrentContext():Void {
        #if sys
        var isRoot = (_editorStack.length == 1);
        if (isRoot) {
            log("Saving Selfrun...");
            saveSelfrun();
        } else {
            log("Saving Assembly to Library...");
            saveAssemblyToLibrary(_currentAssembly);
        }
        #end
    }

   private function saveSelfrun():Void {
        #if sys
        if (_editorStack.length == 0) return;

        var rootEntry = _editorStack[0];
        var rootAssembly:Assembly = rootEntry.assembly;
        var rootEditor:NodeEditor = rootEntry.editor;

        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in rootAssembly.blueprint.internalAtoms) {

            var runtimeId = rootAssembly.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;

            var atomInstance:Atom = cast rootAssembly.internalAtoms.get(runtimeId);

            var values:Dynamic = null;
            if (atomInstance != null) {
                values = atomInstance.getPersistentState();
            }

            atomsToSave.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y,
                values: values
            });
        }

        var connsToSave:Array<Dynamic> = [];
        for (conn in rootAssembly.blueprint.internalConnections) {
            var fromId = conn.from.atomId;
            var toId = conn.to.atomId;

            if (fromId != "SELF") fromId = rootAssembly.getTemplateId(fromId);
            if (toId != "SELF") toId = rootAssembly.getTemplateId(toId);

            connsToSave.push({
                from: { atomId: fromId, contactName: conn.from.contactName },
                to: { atomId: toId, contactName: conn.to.contactName }
            });
        }

        var bp = rootAssembly.blueprint;
        var viewState = rootEditor.getViewState();

        // Исправлено: Явная типизация массива для сохранения
        var deviceWindowData:Array<{path:Array<String>, x:Float, y:Float}> = [];
        
        if (_deviceWindow != null && _deviceWindow.isOpen) {
            var cards = _deviceWindow.getDeviceCards();
            for (card in cards) {
                var path = findDevicePath(rootAssembly, card.atom);
                if (path != null && path.length > 0) {
                    deviceWindowData.push({
                        path: path,
                        x: card.x,
                        y: card.y
                    });
                }
            }
            _cachedDeviceWindowState = deviceWindowData;
        } else if (_cachedDeviceWindowState != null) {
            deviceWindowData = _cachedDeviceWindowState;
        }

        var data:Dynamic = {
            version: "1.3",
            blueprint: {
                id: bp.id,
                name: bp.name,
                category: bp.category,
                pins: bp.pins,
                internalAtoms: atomsToSave,
                internalConnections: connsToSave
            },
            editor: viewState,
            deviceWindow: {
                isOpen: (_deviceWindow != null && _deviceWindow.isOpen),
                devices: deviceWindowData
            }
        };

        try {
            File.saveContent(_selfrunPath, haxe.Json.stringify(data, null, "  "));
            log("Selfrun saved.");
        } catch(e:Dynamic) { log("Error saving Selfrun: " + e); }

        saveInternalAssemblies(rootAssembly);
        #end
    }

    private function saveAssemblyToLibrary(asm:Assembly):Void {
        #if sys
        var bp = asm.blueprint;
        if (bp.id == "selfrun" || bp.id == "loaded_asm") return;

        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in bp.internalAtoms) {
            var runtimeId = asm.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;
            var atomInstance:Atom = cast asm.internalAtoms.get(runtimeId);
            var values:Dynamic = null;
            if (atomInstance != null) values = atomInstance.getPersistentState();
            atomsToSave.push({ instanceId: atomDef.instanceId, typeId: atomDef.typeId, x: atomDef.x, y: atomDef.y, values: values });
        }

        var connsToSave:Array<Dynamic> = [];
        for (conn in bp.internalConnections) {
            var fromId = conn.from.atomId; var toId = conn.to.atomId;
            if (fromId != "SELF") fromId = asm.getTemplateId(fromId);
            if (toId != "SELF") toId = asm.getTemplateId(toId);
            connsToSave.push({ from: { atomId: fromId, contactName: conn.from.contactName }, to: { atomId: toId, contactName: conn.to.contactName } });
        }

        var pinsData:Array<Dynamic> = [];
        for (pin in bp.pins) pinsData.push({ name: pin.name, type: Std.string(pin.type), defaultValue: pin.defaultValue, dataType: pin.dataType });

        var data:Dynamic = { version: "1.1", blueprint: { id: bp.id, name: bp.name, category: bp.category, pins: pinsData, internalAtoms: atomsToSave, internalConnections: connsToSave } };
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
                if (subAsm.blueprint.internalAtoms != null && subAsm.blueprint.internalAtoms.length > 0) {
                    saveAssemblyToLibrary(subAsm);
                    saveInternalAssemblies(subAsm);
                }
            }
        }
        #end
    }

    private function onOpenAssemblyRequest(impulse:Impulse):Void {
        if (!_settingsPanel.allowAssembly) { log("Assembly editing disabled"); return; }
        var id = impulse.data.atomId;
        var obj = _currentAssembly.internalAtoms.get(id);
        if (Std.isOfType(obj, Assembly)) {
            var targetAsm = cast(obj, Assembly);
            if (targetAsm.blueprint != null && targetAsm.blueprint.isNative) { log("Cannot edit native atom: " + targetAsm.blueprint.name); return; }
            _currentEditor.deselectAll();
            _propertiesWindow.close();
            pushEditor(targetAsm);
            log("Opened: " + targetAsm.blueprint.name);
        } else { log("Cannot enter: not an Assembly or not found."); }
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
        for (i in 0..._editorStack.length) path += " / " + _editorStack[i].assembly.blueprint.name;
        _pathField.text = path;
        if (_currentAssembly != null) _nameField.text = _currentAssembly.blueprint.name;
    }

    private function onToggleView():Void {
        if (_deviceWindow != null && _deviceWindow.isOpen) {
            var rootAssembly:Assembly = _editorStack[0].assembly;
            _cachedDeviceWindowState = [];
            
            var cards = _deviceWindow.getDeviceCards();
            for (card in cards) {
                var path = findDevicePath(rootAssembly, card.atom);
                if (path != null && path.length > 0) {
                    _cachedDeviceWindowState.push({
                        path: path, 
                        x: card.x, 
                        y: card.y
                    });
                }
            }
            
            log("Closing Device Window (state cached).");
            _deviceWindow.close();
            _deviceWindow = null;
        } else {
            log("Opening Device Window...");
            _deviceWindow = new DeviceWindow();
            _deviceWindow.onShowEditor = restoreEditorWindow;
            _deviceWindow.onGetAssemblyList = getAllDevicesRecursive;
            _deviceWindow.onAssemblySelected = function(atom:Atom) { log("Device added: " + atom.name); };

            if (_cachedDeviceWindowState != null && _cachedDeviceWindowState.length > 0) {
                var rootAssembly:Assembly = _editorStack[0].assembly;
                for (item in _cachedDeviceWindowState) {
                    var atom = resolveDevicePath(rootAssembly, item.path);
                    if (atom != null) {
                        _deviceWindow.addDevice(atom, item.x, item.y);
                    }
                }
                log("Restored " + _cachedDeviceWindowState.length + " devices from cache.");
            }
        }
    }

    private function getAllDevicesRecursive():Array<{id:String, name:String, atom:Atom}> {
        var result:Array<{id:String, name:String, atom:Atom}> = [];
        for (entry in _editorStack) { if (entry.assembly != null) collectDevicesRecursive(entry.assembly, result); }
        return result;
    }

    private function collectDevicesRecursive(asm:Assembly, result:Array<{id:String, name:String, atom:Atom}>):Void {
        if (asm == null || asm.internalAtoms == null) return;
        for (id in asm.internalAtoms.keys()) {
            var obj = asm.internalAtoms.get(id);
            if (Std.isOfType(obj, Atom)) {
                var atom:Atom = cast(obj, Atom);
                result.push({ id: id, name: atom.name, atom: atom });
                if (Std.isOfType(obj, Assembly)) collectDevicesRecursive(cast(obj, Assembly), result);
            }
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
        if (_deviceWindow != null) { _deviceWindow.close(); _deviceWindow = null; _customSprite = null; }
        _cachedDeviceWindowState = null;
        
        Impulsys.clear();
        Impulsys.subscribeToImpulse("ATOM_PROPERTIES_REQUEST", onPropertiesRequest);
        Impulsys.subscribeToImpulse("OPEN_ASSEMBLY_REQUEST", onOpenAssemblyRequest);
        Impulsys.subscribeToImpulse("REQUEST_NEW_ASSEMBLY_CONTEXT", onRequestNewContext);
        Impulsys.subscribeToImpulse("VALUE_COMMITTED", onValueCommitted);

        if (_contextManager != null) _uiLayer.removeChild(_contextManager.getView());
        _contextManager = new ContextMenuManager(_settingsPanel);
        _uiLayer.addChild(_contextManager.getView());

        DriverManager.getInstance().dispose();
        SignalQueue.getInstance().clear();
        UndoManager.getInstance().clear();
        ECS.reset();
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        if (_popup.visible) return;
        if (e.keyCode == Keyboard.S && !e.ctrlKey) { saveCurrentContext(); return; }
        if (e.ctrlKey && e.keyCode == Keyboard.C) { if (_currentEditor != null) _currentEditor.copySelection(); return; }
        if (e.ctrlKey && e.keyCode == Keyboard.X) { if (_currentEditor != null) _currentEditor.cutSelection(); return; }
        if (e.ctrlKey && e.keyCode == Keyboard.V) { if (_currentEditor != null) _currentEditor.pasteSelection(); return; }
        if (e.ctrlKey && e.keyCode == Keyboard.A) { if (_currentEditor != null) _currentEditor.selectAll(); return; }
        if (e.keyCode == Keyboard.ESCAPE) {
            if (_settingsPanel.visible) { _settingsPanel.visible = false; return; }
            if (_editorStack.length > 1) onBackClicked();
            return;
        }
        if (e.ctrlKey && e.keyCode == Keyboard.Z) { UndoManager.getInstance().undo(); return; }
        if (e.ctrlKey && e.keyCode == Keyboard.Y) { UndoManager.getInstance().redo(); return; }
        if (e.keyCode == Keyboard.R) { onResetClick(); return; }
        if (e.keyCode == Keyboard.D || e.keyCode == Keyboard.DELETE) { deleteSelectedOnCanvas(); return; }
        if (e.keyCode == Keyboard.E) { if (_editorStack.length > 1) onDeleteCurrentAssembly(); else log("Cannot erase root assembly."); return; }
        if (e.keyCode == Keyboard.BACKSPACE) { if (_editorStack.length > 1) onBackClicked(); return; }
    }

    private function deleteSelectedOnCanvas():Void {
        if (_currentEditor == null) return;
        var nodeCount = _currentEditor.getSelectedNodeCount();
        var wireIds = _currentEditor.getSelectedWireIds();
        if (nodeCount > 0) {
            _currentEditor.deleteSelectedNodes();
            updateSettingsStats();
        } else if (wireIds.length > 0) {
            var cmd = new DeleteWiresCommand(_currentAssembly.blueprint, _currentAssembly, wireIds);
            UndoManager.getInstance().executeAndStore(cmd);
        }
    }

    private function onPropertiesRequest(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) return;
        var target = impulse.data.atom;
        var view = impulse.data.view;
        var posX = view.x + 100; var posY = view.y;
        if (posX > stage.stageWidth - 320) posX = stage.stageWidth - 320;
        if (posY > stage.stageHeight - 200) posY = stage.stageHeight - 200;
        _propertiesWindow.show(target, posX, posY);
    }
}