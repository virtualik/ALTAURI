package;

import core.logic.Timebase;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.geom.Point;
import openfl.Lib;
import openfl.events.Event;
import openfl.system.System;
import core.base.Assembly;
import core.base.Atom;
import core.data.Blueprint;
import core.logic.SignalQueue;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import system.managers.UndoManager;
import system.managers.DriverManager;
import system.managers.ProjectManager;
import editor.NodeEditor;
import editor.NodeView;
import editor.EditorTheme;
import editor.ContextMenuManager;
import editor.EditorContext;
import ui.TextInputPopup;
import ui.PropertiesWindow;
import ui.ButtonComponent;
import ui.SettingsPanel;
import ui.WireType;
import ui.DeviceWindow;
import ui.DevicePanel;
import ui.DeviceCard;
import ui.WindowController;
import system.commands.editor.GroupAtomsCommand;
import system.commands.editor.CreateNewAssemblyCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.base.MacroCommand;
import ecs.ECS;
import core.types.ContactType;
import library.AtomRegistry;
using StringTools;

/**
* Main v2.8 (Fix Device Panel Save on Exit)
*
* v2.8 Changes:
* - FIXED: Device Panel state now syncs to cache before saving on exit.
* - FIXED: Adding a device to Device Panel now triggers auto-save.
*/
class Main extends Sprite
{
// --- UI Layers ---
	private var _editorLayer:Sprite;
	private var _uiLayer:Sprite;
	private var _settingsLayer:Sprite;
// --- Managers ---
	private var _projectManager:ProjectManager;
	private var _editorContext:EditorContext;
	private var _contextManager:ContextMenuManager;
// --- UI Elements ---
	private var _propertiesWindow:PropertiesWindow;
	private var _settingsPanel:SettingsPanel;
	private var _popup:TextInputPopup;
	private var _debugField:TextField;
	private var _pathField:TextField;
	private var _nameField:TextField;
// --- Buttons ---
	private var _btnBack:ButtonComponent;
	private var _btnReset:ButtonComponent;
	private var _btnNew:ButtonComponent;
	private var _btnView:ButtonComponent;
	private var _btnSettings:ButtonComponent;
	private var _btnDelete:ButtonComponent;
	private var _btnClose:ButtonComponent;
// --- State ---
	private var _lastTime:Int = 0;
	private var _theme:EditorTheme;
	private var _deviceWindow:DeviceWindow;

// v2.5: Device Panel & Transparency
	private var _devicePanel:DevicePanel;
	private var _windowController:WindowController;
	private var _isPanelMode:Bool = false; // false = Editor Mode, true = Device Panel Mode

// v2.2: Cache for window position
	private var _cachedDeviceWindowState:Array<
	{
		path:Array<String>,
		x:Float,
		y:Float,
		?width:Float,
		?height:Float
	}> = null;
	private var _cachedWindowWidth:Float = 420;
	private var _cachedWindowHeight:Float = 320;
	private var _cachedWindowX:Float = 100;
	private var _cachedWindowY:Float = 100;
// v2.3: Debounce timer for window saving
	private var _windowSaveTimer:haxe.Timer = null;
	private var _hideTimer:haxe.Timer;
	private var _isDisposed:Bool = false;
	public function new()
	{
		super();
		_theme = EditorTheme.getInstance();
		#if html5
		var canvas:js.html.CanvasElement = cast js.Browser.document.getElementById("openfl-content");
		if (canvas == null) canvas = cast js.Browser.document.querySelector("canvas");
		if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
		#end
		setupDebugLog();
		_projectManager = ProjectManager.getInstance();
		_projectManager.init();
		AtomRegistry.initialize();
		log("System initialized");
		ECS.init();
		setupLayers();

		// v2.5: Инициализация прозрачности сразу после создания слоев
		initTransparency();

		if (stage != null) init();
		else addEventListener(Event.ADDED_TO_STAGE, init);
	}
	private function init(e:Event = null):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, init);
		openfl.Lib.current.stage.window.visible = true;
		stage.color = _theme.APP_BG_BLACK;
		// Устанавливаем низкое качество рендеринга.
		// Это отключает Anti-Aliasing для векторной графики (линии, круги).
		stage.quality = HIGH;

		_editorContext = new EditorContext(_editorLayer);
		DriverManager.getInstance();
		SignalQueue.getInstance();
		addEventListener(Event.ENTER_FRAME, onMainLoop);
		buildUI();
		stage.addEventListener(Event.RESIZE, onResize);
		#if sys
		openfl.Lib.current.stage.window.onClose.add(onMainWindowClose);
		#end
		loadProject();
		SignalQueue.getInstance().maxTicksPerFrame = 0; // Без лимита
	}

// =============================================================================================
// v2.5: TRANSPARENCY INITIALIZATION
// =============================================================================================
	private function initTransparency():Void
	{
		_windowController = new WindowController();

		#if windows
		// Включаем прозрачность по умолчанию при старте
		if (_windowController.enableLayeredTransparency())
		{
			log("Main Window: Transparency ENABLED (Black = Transparent)");
			// Устанавливаем черный цвет фона сцены, чтобы "прозрачные" области стали прозрачными
			stage.color = _theme.APP_BG_BLACK;
		}
		else {
			log("Main Window: Transparency NOT SUPPORTED or FAILED");
		}
		#end
	}

// =============================================================================================
// LOADING v2.7
// =============================================================================================
	private function loadProject():Void
	{
		var data = _projectManager.loadSelfrun();
		var rootAssembly:Assembly = null;
		if (data != null && data.blueprint != null)
		{
			rootAssembly = new Assembly("main_asm", data.blueprint);
			trace('=== DEBUG: Checking isLogic flags ===');
			checkIsLogicRecursive(rootAssembly, 0);
			trace('=== DEBUG: Check complete ===');
			_cachedDeviceWindowState = [];
			if (data.devices != null)
			{
				for (d in data.devices)
				{
					var w:Float = (d.width != null) ? d.width : 100.0;
					var h:Float = (d.height != null) ? d.height : 80.0;
					_cachedDeviceWindowState.push(
					{
						path: d.path,
						x: d.x,
						y: d.y,
						width: w,
						height: h
					});
				}
			}
			_cachedWindowWidth = data.windowWidth;
			_cachedWindowHeight = data.windowHeight;
			_cachedWindowX = data.windowX;
			_cachedWindowY = data.windowY;
			_editorContext.push(rootAssembly, true);
			_editorContext.currentEditor.setViewState(data.view);
			if (data.isOpen)
			{
				// При загрузке, если было открыто, переключаемся в режим Device
				_isPanelMode = false; // Сбрасываем, чтобы сработал toggle
				onToggleView();
			}
			log("Project loaded (v2.8).");
		}
		else {
			createEmptyProject();
		}
		updateNavigationUI();
		updateButtonStates();
	}
	private function checkIsLogicRecursive(asm:Assembly, depth:Int):Void
	{
		if (asm == null || asm.internalAtoms == null || depth > 10) return;
		var indent = StringTools.lpad("", "  ", depth);
		for (id in asm.internalAtoms.keys())
		{
			var atom = asm.internalAtoms.get(id);
			if (atom != null)
			{
				var logicStatus = atom.isLogic ? "DIGITAL" : "ANALOG";
				trace('${indent}Atom: ${atom.name} (${atom.id}) - ${logicStatus}');
				if (Std.isOfType(atom, Assembly))
				{
					checkIsLogicRecursive(cast(atom, Assembly), depth + 1);
				}
			}
		}
	}
	private function createEmptyProject():Void
	{
		log("Creating new project...");
		var emptyBlueprint = new Blueprint("selfrun", "Selfrun", [
		{name: "IN", type: INPUT},
		{name: "OUT", type: OUTPUT}
		]);
		var rootAssembly = new Assembly("main_asm", emptyBlueprint);
		_editorContext.push(rootAssembly, true);
	}
// =============================================================================================
// SAVING v2.8
// =============================================================================================
	private function saveCurrentContext():Void
	{
		var isRoot = (_editorContext.getStackLength() == 1);
		if (isRoot)
		{
			log("Saving Root...");

			// v2.8 FIX: Синхронизируем состояние панели ПЕРЕД записью файла,
			// даже если мы сейчас находимся в режиме Device Panel.
			if (_isPanelMode)
			{
				syncDevicePanelToCache();
			}

			var viewState = _editorContext.currentEditor.getViewState();
			var devicesData = _cachedDeviceWindowState != null ? _cachedDeviceWindowState : [];
			var isWindowOpen = _isPanelMode; // Если мы в режиме панели, значит "открыто"

			_projectManager.saveSelfrun(
				_editorContext.currentAssembly,
				viewState,
				devicesData,
				isWindowOpen,
				_cachedWindowWidth,
				_cachedWindowHeight,
				_cachedWindowX,
				_cachedWindowY
			);
		}
		else {
			log("Saving Assembly to Library...");
			_projectManager.saveAssemblyToLibrary(_editorContext.currentAssembly);
		}
	}
	private function saveOnExit():Void
	{
		log("Auto-saving on exit...");
		saveCurrentContext();
	}
// =============================================================================================
// ACTIONS & UI CALLBACKS
// =============================================================================================
	private function onBackClicked():Void
	{
		if (_editorContext.getStackLength() <= 1)
		{
			log("Cannot close root assembly.");
			return;
		}
		var isUnsaved = !isAssemblyFileExists(_editorContext.currentAssembly.blueprint.id);
		if (isUnsaved)
		{
			_popup.show("Save New Assembly", _editorContext.currentAssembly.blueprint.name, function(name:String)
			{
				if (name != null && name.length > 0)
				{
					saveNewNamedAssembly(name);
					closeCurrentEditor(true);
				}
			});
		}
		else {
			saveCurrentContext();
			closeCurrentEditor(true);
		}
	}
	private function closeCurrentEditor(updateInstances:Bool):Void
	{
		_editorContext.pop(updateInstances);
		updateNavigationUI();
		updateButtonStates();
		log("Returned to: " + _editorContext.currentAssembly.blueprint.name);
	}
	private function onDeleteCurrentAssembly():Void
	{
		if (_editorContext.getStackLength() <= 1)
		{
			log("Cannot delete root assembly.");
			return;
		}
		var bp = _editorContext.currentAssembly.blueprint;
		var isSaved = isAssemblyFileExists(bp.id);
		var title = "Confirm Erase";
		var message = isSaved
		? "Assembly '" + bp.name + "' will be erased from Library. Continue?"
		: "Assembly '" + bp.name + "' is not saved and will be discarded. Continue?";
		_popup.showConfirm(title, message, function(confirmed:Bool)
		{
			if (confirmed) deleteCurrentAssemblyConfirmed(isSaved);
		});
	}
	private function deleteCurrentAssemblyConfirmed(isSaved:Bool):Void
	{
		var bp = _editorContext.currentAssembly.blueprint;
		var deletedId = bp.id;
		AtomRegistry.remove(deletedId);
		if (isSaved)
		{
			_projectManager.deleteAssemblyFile(deletedId);
		}
		closeCurrentEditor(false);
		cleanRegistryDanglingReferences(deletedId);
	}
	private function cleanRegistryDanglingReferences(deletedId:String):Void
	{
		var currentAsm = _editorContext.currentAssembly;
		var idsToRemove:Array<String> = [];
		for (id in currentAsm.internalAtoms.keys())
		{
			var atom = currentAsm.internalAtoms.get(id);
			if (Std.isOfType(atom, Assembly))
			{
				if (cast(atom, Assembly).blueprint.id == deletedId) idsToRemove.push(id);
			}
		}
		if (idsToRemove.length > 0)
		{
			var macrocom = new MacroCommand();
			for (id in idsToRemove) macrocom.addCommand(new DeleteAtomCommand(currentAsm.blueprint, currentAsm, id));
			macrocom.execute();
			_editorContext.currentEditor.refreshAssemblyViews();
		}
	}
	private function saveNewNamedAssembly(name:String):Void
	{
		var safeName = StringTools.replace(name, " ", "_");
		if (safeName.length == 0) { log("Error: Invalid assembly name."); return; }
		var bp = _editorContext.currentAssembly.blueprint;
		bp.id = safeName;
		bp.name = name;
		saveCurrentContext();
	}
// =============================================================================================
// v2.7: TOGGLE VIEW & STATE SYNC
// =============================================================================================

	/**
	 * Сохраняет текущее состояние DevicePanel в кэш.
	 */
	private function syncDevicePanelToCache():Void
	{
		if (_devicePanel == null) return;
		var cards = _devicePanel.getDeviceCards();
		if (cards.length == 0 && (_cachedDeviceWindowState == null || _cachedDeviceWindowState.length == 0)) return;

		var newData:Array<{path:Array<String>, x:Float, y:Float, width:Float, height:Float}> = [];
		for (card in cards)
		{
			var path = findDevicePath(_editorContext.currentAssembly, card.atom);
			if (path != null && path.length > 0)
			{
				newData.push(
				{
					path: path,
					x: card.x,
					y: card.y,
					width: card.cardWidth,
					height: card.cardHeight
				});
			}
		}
		_cachedDeviceWindowState = newData;
	}

	/**
	 * Восстанавливает состояние DevicePanel из кэша.
	 */
	private function restoreDevicePanelFromCache():Void
	{
		if (_cachedDeviceWindowState == null) return;
		_devicePanel.clearDevices(); // Clear current state first
		for (data in _cachedDeviceWindowState)
		{
			var atom = resolveDevicePath(_editorContext.currentAssembly, data.path);
			if (atom != null)
			{
				_devicePanel.addDevice(atom, data.x, data.y);
			}
		}
	}

	private function onToggleView():Void
	{
		_isPanelMode = !_isPanelMode;
		if (_isPanelMode)
		{
			// --- SWITCH TO DEVICE PANEL MODE ---
			log("Mode: Device Panel");

			// 1. Скрываем Редактор и UI редактора
			_editorLayer.visible = false;
			_uiLayer.visible = false;

			// 2. Показываем Device Panel
			_devicePanel.visible = true;
			_devicePanel.setSize(stage.stageWidth, stage.stageHeight);

			// 3. Передаем текущий контекст (сборку)
			_devicePanel.setContext(_editorContext.currentAssembly);

			// 4. Восстанавливаем состояние из кэша
			restoreDevicePanelFromCache();

			// 5. Закрываем отдельное окно (если открыто)
			if (_deviceWindow != null && _deviceWindow.isOpen) _deviceWindow.close();

			#if windows
			_windowController.enableLayeredTransparency();
			#end
		}
		else {
			// --- SWITCH TO EDITOR MODE ---
			log("Mode: Node Editor");

			// 1. Сохраняем текущее состояние панели в кэш
			syncDevicePanelToCache();

			// 2. Прячем панель
			if (_devicePanel != null) _devicePanel.visible = false;

			// 3. Показываем редактор
			_editorLayer.visible = true;
			_uiLayer.visible = true;

			// 4. Возвращаем все виджеты из Panel в NodeViews
			if (_editorContext.currentEditor != null)
			{
				_editorContext.currentEditor.restoreAllWidgets();
			}

			// 5. Очищаем визуал панели
			if (_devicePanel != null) _devicePanel.clearDevices();
		}
	}

// v2.3: Auto-save with 300ms debounce
	private function onDeviceWindowChanged(impulse:Impulse):Void
	{
		if (_windowSaveTimer != null)
		{
			_windowSaveTimer.stop();
		}
		_windowSaveTimer = haxe.Timer.delay(() -> {
			syncDevicePanelToCache();
			saveCurrentContext();
			_windowSaveTimer = null;
			log("Device state auto-saved.");
		}, 300);
	}
// =============================================================================================
// MAIN LOOP & SETUP
// =============================================================================================
	private function onMainLoop(e:Event):Void
	{
		var now = Lib.getTimer();
		var dt = (now - _lastTime) / 1000.0;
		_lastTime = now;
		Timebase.getInstance().updateFrame();
		DriverManager.getInstance().update(dt);
	}
	private function setupDebugLog()
	{
		_debugField = new TextField();
		_debugField.width = 600; _debugField.height = 30;
		_debugField.x = 10; _debugField.y = (stage != null ? stage.stageHeight : 600) - 40;
		_debugField.background = true;
		_debugField.backgroundColor = _theme.DEBUG_BG_COLOR;
		_debugField.textColor = _theme.DEBUG_TEXT_COLOR;
		_debugField.selectable = false;
		var fmt = new TextFormat("_sans", 12);
		_debugField.defaultTextFormat = fmt;
		addChild(_debugField);
	}
	private function log(msg:String)
	{
		trace(msg);
		if (_hideTimer != null) _hideTimer.stop();
		if (_debugField != null)
		{
			_debugField.text = msg;
			_debugField.alpha = 1.0;
			_debugField.visible = true;
		}
		_hideTimer = haxe.Timer.delay(function() { fadeOutLog(); }, 5000);
	}
	private function fadeOutLog() { if (_debugField != null) _debugField.visible = false; }
	private function setupLayers():Void
	{
		_editorLayer = new Sprite();
		addChild(_editorLayer);
		_uiLayer = new Sprite();
		addChild(_uiLayer);
		_settingsLayer = new Sprite();
		_settingsLayer.mouseEnabled = false;
		addChild(_settingsLayer);
	}
	private function buildUI():Void
	{
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
		Impulsys.subscribeToImpulse(EventType.ATOM_PROPERTIES_REQUEST, onPropertiesRequest);
		Impulsys.subscribeToImpulse(EventType.OPEN_ASSEMBLY_REQUEST, onOpenAssemblyRequest);
		Impulsys.subscribeToImpulse(EventType.REQUEST_NEW_ASSEMBLY_CONTEXT, onRequestNewContext);
		Impulsys.subscribeToImpulse(EventType.VALUE_COMMITTED, onValueCommitted);
		Impulsys.subscribeToImpulse(EventType.DEVICE_WINDOW_CHANGED, onDeviceWindowChanged);
		// v2.5: Initialize DevicePanel
		_devicePanel = new DevicePanel();
		_devicePanel.visible = false;
		addChild(_devicePanel);
		_devicePanel.onShowEditor = function()
		{
			if (_isPanelMode) onToggleView();
		};
		_devicePanel.onGetAssemblyList = getAllDevicesRecursive;
	}
	private function onSettingsChanged():Void
	{
		if (_editorContext.currentEditor != null)
		{
			_editorContext.currentEditor.setUseEcsRender(_settingsPanel.useEcsRender);
			_editorContext.currentEditor.setWireType(_settingsPanel.wireType);
			_editorContext.currentEditor.setAllowAssembly(_settingsPanel.allowAssembly);
		}
		updateButtonStates();
	}
	private function onResize(e:Event):Void
	{

		graphics.clear();
		graphics.beginFill(0, 0); // Alpha = 0 (Полностью прозрачный)
		graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
		graphics.endFill();
		_debugField.y = stage.stageHeight - 40;
		_pathField.y = stage.stageHeight - 20;
		var btnSize = 40; var btnPadding = 5;
		var rightEdge = stage.stageWidth - btnPadding;
		_btnClose.x = rightEdge - btnSize;
		_btnBack.x = _btnClose.x - btnSize - btnPadding;
		_btnDelete.x = _btnBack.x - btnSize - btnPadding;
		_btnView.x = _btnDelete.x - btnSize - btnPadding;
		_btnNew.x = _btnView.x - btnSize - btnPadding;
		_btnReset.x = _btnNew.x - btnSize - btnPadding;
		_btnSettings.x = _btnReset.x - btnSize - btnPadding;
		if (_editorContext.currentEditor != null)
		{
			var margin = 12;
			_editorContext.currentEditor.setSize(stage.stageWidth - margin*2, stage.stageHeight - margin*2);
		}
		// v2.5: Resize DevicePanel if active
		if (_devicePanel != null && _devicePanel.visible)
		{
			_devicePanel.setSize(stage.stageWidth, stage.stageHeight);
		}
	}
	private function updateButtonStates():Void
	{
		var isRoot = (_editorContext.getStackLength() <= 1);
		_btnBack.visible = !isRoot;
		_btnDelete.visible = !isRoot;
		_btnNew.visible = _settingsPanel.allowAssembly;
	}
	private function updateNavigationUI():Void
	{
		if (_editorContext.currentAssembly != null)
		{
			_nameField.text = _editorContext.currentAssembly.blueprint.name;
			_pathField.text = "Depth: " + _editorContext.getStackLength();
		}
		if (_contextManager != null)
		{
			_contextManager.setContext(_editorContext.currentEditor, _editorContext.currentAssembly);
		}
	}
// =============================================================================================
// HELPERS & EVENTS
// =============================================================================================
	private function onOpenAssemblyRequest(impulse:Impulse):Void
	{
		if (!_settingsPanel.allowAssembly)
		{
			log("Assembly editing disabled");
			return;
		}
		if (impulse == null || impulse.data == null)
		{
			trace("ERROR: Open Assembly Request has no data!");
			return;
		}
		var id = impulse.data.atomId;
		trace('DEBUG: Open Request for ID: $id');
		var obj = _editorContext.currentAssembly.internalAtoms.get(id);
		if (obj == null)
		{
			var runtimeId = _editorContext.currentAssembly.idMap.get(id);
			if (runtimeId != null)
			{
				obj = _editorContext.currentAssembly.internalAtoms.get(runtimeId);
				trace('DEBUG: Found via ID Map. RuntimeID: $runtimeId');
			}
		}
		if (obj == null)
		{
			trace('ERROR: Atom with ID $id NOT FOUND in current assembly!');
			trace('  Available keys: ${[for(k in _editorContext.currentAssembly.internalAtoms.keys()) k]}');
			return;
		}
		if (!Std.isOfType(obj, Assembly))
		{
			trace('ERROR: Object $id is NOT an Assembly. It is ${Type.getClassName(Type.getClass(obj))}');
			return;
		}
		var targetAsm = cast(obj, Assembly);
		if (targetAsm.blueprint.isNative)
		{
			log("Cannot edit native atom: " + targetAsm.blueprint.name);
			return;
		}
		_editorContext.currentEditor.deselectAll();
		_propertiesWindow.close();
		_editorContext.push(targetAsm);
		log("Opened: " + targetAsm.blueprint.name);
		updateNavigationUI();
		updateButtonStates();
	}
	private function onRequestNewContext(impulse:Impulse):Void
	{
		var bp:Blueprint = impulse.data.blueprint;
		var id:String = impulse.data.id;
		var newAsm = new Assembly(id, bp);
		_editorContext.push(newAsm);
		log("Created New Assembly Context");
		updateNavigationUI();
		updateButtonStates();
	}
	private function onValueCommitted(impulse:Impulse):Void
	{
		syncDevicePanelToCache();
		saveCurrentContext();
		log("Data saved.");
	}
	private function onPropertiesRequest(impulse:Impulse):Void
	{
		if (impulse == null || impulse.data == null) return;
		var target = impulse.data.atom;
		var view = impulse.data.view;
		var posX = view.x + 100; var posY = view.y;
		if (posX > stage.stageWidth - 320) posX = stage.stageWidth - 320;
		if (posY > stage.stageHeight - 200) posY = stage.stageHeight - 200;
		_propertiesWindow.show(target, posX, posY);
	}
	private function mapIsEmpty<K,V>(map:Map<K,V>):Bool
	{
		return !map.keys().hasNext();
	}
	private function mapCount<K,V>(map:Map<K,V>):Int
	{
		var count = 0;
		for (k in map.keys()) count++;
		return count;
	}
	private function onNewAssembly():Void
	{
		if (!_settingsPanel.allowAssembly) { log("Assembly disabled"); return; }
		var cmd = new CreateNewAssemblyCommand();
		UndoManager.getInstance().executeAndStore(cmd);
	}
	private function onResetClick():Void
	{
		hardReset();
		createEmptyProject();
		log("System Reset.");
	}
	private function hardReset():Void
	{
		log("SYSTEM: Hard Reset...");
		_editorContext.clear();
		if (_deviceWindow != null)
		{
			_deviceWindow.close();
			_deviceWindow = null;
		}
		// v2.5: Reset Device Panel
		if (_devicePanel != null)
		{
			_devicePanel.dispose();
			removeChild(_devicePanel);
			_devicePanel = null;
		}
		_devicePanel = new DevicePanel(); // Recreate
		_devicePanel.visible = false;
		_devicePanel.onShowEditor = function() { if (_isPanelMode) onToggleView(); };
		_devicePanel.onGetAssemblyList = getAllDevicesRecursive;
		addChild(_devicePanel);
		_isPanelMode = false;
		_editorLayer.visible = true;
		_uiLayer.visible = true;
		_cachedDeviceWindowState = null;
		_cachedWindowWidth = 420;
		_cachedWindowHeight = 320;
		_cachedWindowX = 100;
		_cachedWindowY = 100;
		if (_contextManager != null)
		{
			_contextManager.dispose();
			_uiLayer.removeChild(_contextManager.getView());
		}
		Impulsys.clear();
		Impulsys.subscribeToImpulse(EventType.ATOM_PROPERTIES_REQUEST, onPropertiesRequest);
		Impulsys.subscribeToImpulse(EventType.OPEN_ASSEMBLY_REQUEST, onOpenAssemblyRequest);
		Impulsys.subscribeToImpulse(EventType.REQUEST_NEW_ASSEMBLY_CONTEXT, onRequestNewContext);
		Impulsys.subscribeToImpulse(EventType.VALUE_COMMITTED, onValueCommitted);
		Impulsys.subscribeToImpulse(EventType.DEVICE_WINDOW_CHANGED, onDeviceWindowChanged);
		_contextManager = new ContextMenuManager(_settingsPanel);
		_uiLayer.addChild(_contextManager.getView());
		DriverManager.getInstance().dispose();
		SignalQueue.getInstance().clear();
		UndoManager.getInstance().clear();
		ECS.reset();
	}
	private function onMainWindowClose():Void
	{
		log("Main window close requested...");
		saveOnExit();
		if (_deviceWindow != null && _deviceWindow.isOpen)
		{
			log("Device window is active. Hiding editor instead of exit.");
		}
		else {
			log("Exiting application.");
			System.exit(0);
		}
	}
	private function onCloseClicked():Void
	{
		_popup.showConfirm("Exit", "Do You want to close Editor?", function(confirmed:Bool)
		{
			if (confirmed)
			{
				saveOnExit();
				System.exit(0);
			}
		});
	}
	private function onKeyDown(e:KeyboardEvent):Void
	{
		if (_popup.visible) return;
		if (e.keyCode == Keyboard.S && !e.ctrlKey) { saveCurrentContext(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.C) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.copySelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.X) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.cutSelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.V) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.pasteSelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.A) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.selectAll(); return; }
		if (e.keyCode == Keyboard.ESCAPE)
		{
			if (_settingsPanel.visible) { _settingsPanel.visible = false; return; }
			if (_editorContext.getStackLength() > 1) onBackClicked();
			return;
		}
		if (e.ctrlKey && e.keyCode == Keyboard.Z) { UndoManager.getInstance().undo(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.Y) { UndoManager.getInstance().redo(); return; }
		if (e.keyCode == Keyboard.R) { onResetClick(); return; }
		if (e.keyCode == Keyboard.D || e.keyCode == Keyboard.DELETE) { deleteSelectedOnCanvas(); return; }
		if (e.keyCode == Keyboard.E) { if (_editorContext.getStackLength() > 1) onDeleteCurrentAssembly(); else log("Cannot erase root assembly."); return; }
		if (e.keyCode == Keyboard.BACKSPACE) { if (_editorContext.getStackLength() > 1) onBackClicked(); return; }
	}
	private function deleteSelectedOnCanvas():Void
	{
		if (_editorContext.currentEditor == null) return;
		var nodeCount = _editorContext.currentEditor.getSelectedNodeCount();
		var wireIds = _editorContext.currentEditor.getSelectedWireIds();
		if (nodeCount > 0)
		{
			_editorContext.currentEditor.deleteSelectedNodes();
			updateSettingsStats();
		}
		else if (wireIds.length > 0)
		{
			var cmd = new DeleteWiresCommand(_editorContext.currentAssembly.blueprint, _editorContext.currentAssembly, wireIds);
			UndoManager.getInstance().executeAndStore(cmd);
		}
	}
	private function updateSettingsStats():Void
	{
		if (_settingsPanel != null && _editorContext.currentEditor != null)
		{
			_settingsPanel.updateStats(_editorContext.currentEditor.getNodeCount(), _editorContext.currentEditor.getWireCount(),
			_settingsPanel.useEcsRender, _settingsPanel.wireType, _settingsPanel.allowAssembly);
		}
	}
	private function onSettingsClick():Void
	{
		if (_settingsPanel.visible) _settingsPanel.visible = false;
		else {
			_settingsPanel.show(stage.stageWidth, stage.stageHeight);
			updateSettingsStats();
		}
	}
	private function restoreEditorWindow():Void
	{
		var mainWin = Lib.current.stage.window;
		if (mainWin != null) mainWin.visible = true;
	}
	private function isAssemblyFileExists(id:String):Bool
	{
		#if sys return sys.FileSystem.exists(_projectManager.libraryPath + "/" + id + ".atom"); #else return true; #end
	}
// --- Device Window Helpers v2.2 ---
	private function getAllDevicesRecursive():Array< {id:String, name:String, atom:Atom}>
	{
		var result:Array<{id:String, name:String, atom:Atom}> = [];
		if (_editorContext.currentAssembly != null)
		{
			collectDevicesRecursive(_editorContext.currentAssembly, result);
		}
		return result;
	}
	private function collectDevicesRecursive(asm:Assembly, result:Array< {id:String, name:String, atom:Atom}>):Void
	{
		if (asm == null || asm.internalAtoms == null) return;
		for (id in asm.internalAtoms.keys())
		{
			var obj = asm.internalAtoms.get(id);
			if (Std.isOfType(obj, Atom))
			{
				var atom:Atom = cast(obj, Atom);
				result.push({ id: id, name: atom.name, atom: atom });
				if (Std.isOfType(obj, Assembly)) collectDevicesRecursive(cast(obj, Assembly), result);
			}
		}
	}
	private function extractDeviceWindowData():Array< {path:Array<String>, x:Float, y:Float, ?width:Float, ?height:Float}>
	{
		if (_devicePanel != null && _devicePanel.visible)
		{
			return _cachedDeviceWindowState;
		}
		return _cachedDeviceWindowState != null ? _cachedDeviceWindowState : [];
	}
	private function findDevicePath(container:Assembly, target:Atom):Array<String>
	{
		if (container == null || target == null) return null;
		for (runtimeId in container.internalAtoms.keys())
		{
			var atom = container.internalAtoms.get(runtimeId);
			if (atom == target)
			{
				var templateId = container.getTemplateId(runtimeId);
				return [templateId];
			}
			if (Std.isOfType(atom, Assembly))
			{
				var subPath = findDevicePath(cast(atom, Assembly), target);
				if (subPath != null)
				{
					var templateId = container.getTemplateId(runtimeId);
					subPath.insert(0, templateId);
					return subPath;
				}
			}
		}
		return null;
	}
	private function resolveDevicePath(root:Assembly, path:Array<String>):Atom
	{
		var current:Assembly = root;
		for (i in 0...path.length)
		{
			var templateId = path[i];
			var runtimeId:String = null;
			if (current.idMap != null)
			{
				for (tid => rid in current.idMap)
				{
					if (tid == templateId) { runtimeId = rid; break; }
				}
			}
			if (runtimeId == null && current.internalAtoms.exists(templateId))
			{
				runtimeId = templateId;
			}
			if (runtimeId == null) return null;
			var next = current.internalAtoms.get(runtimeId);
			if (i == path.length - 1) return next;
			else
			{
				if (Std.isOfType(next, Assembly)) current = cast(next, Assembly);
				else return null;
			}
		}
		return null;
	}
}