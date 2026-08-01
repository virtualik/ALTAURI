package;

import core.base.Atom;
import core.logic.TickGenerator;
import openfl.display.Sprite;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;
import openfl.events.Event;
import openfl.system.System;
import core.base.Assembly;
import core.data.Blueprint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import system.managers.UndoManager;
import system.managers.DriverManager;
import system.managers.ProjectManager;
import editor.EditorTheme;
import editor.ContextMenuManager;
import editor.EditorContext;
import ui.TextInputPopup;
import ui.PropertiesWindow;
import ui.ButtonComponent;
import ui.SettingsPanel;
import ui.DeviceWindow;
import ui.DevicePanel;
import ui.WindowController;
import ui.DisplayConfig;
import ui.DisplayMode;
import system.commands.editor.CreateNewAssemblyCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.base.MacroCommand;
import ecs.ECS;
import library.AtomRegistry;
import utils.UID;
using StringTools;

/**
* MAIN v3.0 (DisplayConfig Integration)
* Application entry point and main coordinator.
*
* ═══════════════════════════════════════════════════════════════════════════
* v3.0 CHANGES (DisplayConfig Integration)
* ═══════════════════════════════════════════════════════════════════════════
*
*  PROBLEM:
*  Display state (_isPanelMode, _isWindowMaximized, btnSize, btnPadding)
*  was scattered across Main.hx as local variables and private fields.
*  This violated Single Source of Truth principle and made it impossible
*  for other components to query or react to display state changes.
*
*  SOLUTION:
*  - Removed _isPanelMode → replaced with DisplayConfig.currentMode
*  - Removed _isWindowMaximized → replaced with DisplayConfig.isFullscreen
*  - Replaced local btnSize/btnPadding with DisplayConfig.editorButtons
*  - Added Impulsys subscriptions for DISPLAY_MODE_CHANGED, SCENE_RESIZED,
*    FULLSCREEN_TOGGLED events
*  - Added _onDisplayModeChanged, _onSceneResized, _onFullscreenToggled
*    handlers for reactive UI synchronization
*
*  Architecture:
*  ┌─────────────────────────────────────────────────────────────────────┐
*  │   Main (Application Root)                                           │
*  │                                                                     │
*  │   ┌─────────────────────────────────────────────────────────────┐   │
*  │   │  Display State (v3.0 — DisplayConfig):                      │   │
*  │   │  - DisplayConfig.currentMode   → EDITOR | DEVICE_PANEL      │   │
*  │   │  - DisplayConfig.isFullscreen  → Bool                       │   │
*  │   │  - DisplayConfig.sceneWidth    → Float                      │   │
*  │   │  - DisplayConfig.sceneHeight   → Float                      │   │
*  │   │                                                             │   │
*  │   │  Event Subscriptions (v3.0):                                │   │
*  │   │  - DISPLAY_MODE_CHANGED → _onDisplayModeChanged()           │   │
*  │   │  - SCENE_RESIZED        → _onSceneResized()                 │   │
*  │   │  - FULLSCREEN_TOGGLED   → _onFullscreenToggled()            │   │
*  │   │                                                             │   │
*  │   │  UI Layers:                                                 │   │
*  │   │  - _editorLayer      → NodeEditor stack (EditorContext)     │   │
*  │   │  - _uiLayer          → Buttons, popups, properties window   │   │
*  │   │  - _settingsLayer    → Settings panel overlay               │   │
*  │   │                                                             │   │
*  │   │  Managers:                                                  │   │
*  │   │  - _projectManager   → File I/O, paths, save/load           │   │
*  │   │  - _editorContext    → Editor stack (push/pop assemblies)   │   │
*  │   │  - _contextManager   → Context menu handling                │   │
*  │   │  - TickGenerator     → Simulation clock (60 Hz fixed step)  │   │
*  │   │  - DriverManager     → Active driver updates                │   │
*  │   │  - UndoManager       → Command history                      │   │
*  │   │                                                             │   │
*  │   │  UI Elements:                                               │   │
*  │   │  - _propertiesWindow → Atom properties editor               │   │
*  │   │  - _settingsPanel    → Application settings                 │   │
*  │   │  - _popup            → Text input / confirmation dialogs    │   │
*  │   │  - _devicePanel      → Device display panel (v2.5)          │   │
*  │   │  - _deviceWindow     → Separate device window (legacy)      │   │
*  │   │  - _windowController → Windows transparency control         │   │
*  │   │                                                             │   │
*  │   │  Buttons:                                                   │   │
*  │   │  - [?] Settings  [R] Reset  [N] New Assembly                │   │
*  │   │  - [V] View Toggle  [E] Erase  [<] Back  [X] Close          │   │
*  │   │                                                             │   │
*  │   │  Keyboard Shortcuts:                                        │   │
*  │   │  - Ctrl+C/X/V/A  → Copy/Cut/Paste/Select All                │   │
*  │   │  - Ctrl+Z/Y      → Undo/Redo                                │   │
*  │   │  - S             → Save                                     │   │
*  │   │  - D / DELETE    → Delete selected                          │   │
*  │   │  - E             → Erase current assembly                   │   │
*  │   │  - BACKSPACE     → Go back                                  │   │
*  │   │  - ESCAPE        → Close panel / Go back                    │   │
*  │   │  - F4            → Toggle transparency (Windows)            │   │
*  │   └─────────────────────────────────────────────────────────────┘   │
*  │                                                                     │
*  │  Main Loop:                                                         │
*  │  ──────────                                                         │
*  │  onEnterFrame() {                                                   │
*  │      var dt = calculateDelta();                                     │
*  │      TickGenerator.getInstance().update(dt);                        │
*  │  }                                                                  │
*  │                                                                     │
*  └─────────────────────────────────────────────────────────────────────┘
*
*  v2.9 Changes:
*  - Replaced SimulationClock/Timebase/SignalQueue with TickGenerator
*
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

// ═══════════════════════════════════════════════════════════════════════
// v3.0 REMOVED: _isPanelMode and _isWindowMaximized
// These are now managed by DisplayConfig singleton.
// ═══════════════════════════════════════════════════════════════════════
// private var _isPanelMode:Bool = false;
// private var _isWindowMaximized:Bool = false;

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

// =========================================================================
// CONSTRUCTOR
// =========================================================================
	public function new()
	{
		super();
		_theme = EditorTheme.getInstance();

		#if html5
		var canvas:js.html.CanvasElement = cast js.Browser.document.getElementById("openfl-content");
		if (canvas == null) canvas = cast js.Browser.document.querySelector("canvas");
		if (canvas != null) canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
		#end

		_projectManager = ProjectManager.getInstance();
		_projectManager.init();
		AtomRegistry.initialize();
		ECS.init();

		setupLayers();
		setupDebugLog();

// v2.5: Initialize transparency right after layer creation
		initTransparency();

		if (stage != null) init();
		else addEventListener(Event.ADDED_TO_STAGE, init);
	}

// =========================================================================
// INITIALIZATION
// =========================================================================
	private function init(e:Event = null):Void
	{
		#if html5
		var canvas:js.html.CanvasElement = cast js.Browser.document.getElementById("openfl-content");
		if (canvas == null) canvas = cast js.Browser.document.querySelector("canvas");
		if (canvas != null)
		{
			// Блокировка контекстного меню (уже есть)
			canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
			
			// ═══════════════════════════════════════════════════════════════
			// Блокировка браузерного autoscroll на средней кнопке мыши
			// ═══════════════════════════════════════════════════════════════
			// Браузер активирует autoscroll mode на нативном mousedown event
			// с button === 1 ДО того, как OpenFL получит MIDDLE_MOUSE_DOWN.
			// preventDefault() на canvas останавливает браузерный autoscroll,
			// позволяя OpenFL/ViewportManager обработать pan самостоятельно.
			canvas.addEventListener("mousedown", function(e:js.html.MouseEvent) {
				if (e.button == 1) {
					e.preventDefault();
					e.stopPropagation();
				}
			});
			
			// Дополнительно: блокируем auxclick (срабатывает при отпускании средней кнопки)
			canvas.addEventListener("auxclick", function(e:js.html.MouseEvent) {
				if (e.button == 1) {
					e.preventDefault();
				}
			});
		}
		#end
		#if html5
		var canvas:js.html.CanvasElement = cast js.Browser.document.getElementById("openfl-content");
		if (canvas == null) canvas = cast js.Browser.document.querySelector("canvas");
		if (canvas != null)
		{
			// Блокировка контекстного меню
			canvas.oncontextmenu = function(e) { e.preventDefault(); return false; };
			
			// ═══════════════════════════════════════════════════════════════
			// Блокировка браузерного autoscroll на средней кнопке мыши
			// ═══════════════════════════════════════════════════════════════
			canvas.addEventListener("mousedown", function(e:js.html.MouseEvent) {
				if (e.button == 1) {
					e.preventDefault();
					e.stopPropagation();
				}
			});
			
			canvas.addEventListener("auxclick", function(e:js.html.MouseEvent) {
				if (e.button == 1) {
					e.preventDefault();
				}
			});
			
			// ═══════════════════════════════════════════════════════════════
			// Блокировка прокрутки страницы при колесе мыши над canvas
			// ═══════════════════════════════════════════════════════════════
			// Браузерное событие wheel срабатывает ДО того, как OpenFL получит
			// MouseEvent.MOUSE_WHEEL. Без preventDefault() браузер прокручивает
			// страницу одновременно с тем, как OpenFL обрабатывает zoom.
			//
			// {passive: false} — критически важен! По умолчанию современные
			// браузеры (Chrome, Firefox) делают wheel event passive, что
			// запрещает вызов preventDefault(). Явное указание passive: false
			// позволяет блокировать прокрутку страницы.
			//
			// OpenFL всё равно получит свой MOUSE_WHEEL (его обработчики
			// зарегистрированы внутри canvas и не зависят от preventDefault
			// на уровне DOM), поэтому zoom продолжит работать как обычно.
			// ═══════════════════════════════════════════════════════════════
			canvas.addEventListener("wheel", function(e:js.html.WheelEvent) {
				e.preventDefault();
			}, {passive: false});
		}
		#end
		
// Перехватываем trace() для отправки в DebugConsoleAtom
		var originalTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?infos:haxe.PosInfos)
		{
// 1. Стандартный вывод в консоль браузера (только для HTML5 target)
			#if html5
			untyped console.log(v);
			#end
// 2. Отправка в DebugConsoleAtom (работает на всех платформах)
			library.electro.DebugConsoleAtom.log(Std.string(v));
		};

		trace("DEBUG CONSOLE TEST: Если ты это видишь, перехват работает!");
		log("System initialized");

		removeEventListener(Event.ADDED_TO_STAGE, init);
		openfl.Lib.current.stage.window.visible = true;
		stage.color = _theme.APP_BG_BLACK;

// Set low rendering quality.
// This disables Anti-Aliasing for vector graphics (lines, circles).
		stage.quality = openfl.display.StageQuality.LOW;

		_editorContext = new EditorContext(_editorLayer);
		DriverManager.getInstance();

// Initialize TickGenerator
		TickGenerator.getInstance();
		TickGenerator.getInstance().targetHz = 60; // 60 Hz — standard for simulation

		addEventListener(Event.ENTER_FRAME, onMainLoop);

		buildUI();

		stage.addEventListener(Event.RESIZE, onResize);

		Lib.current.stage.addEventListener(flash.events.Event.EXITING, function(e)
		{
			e.preventDefault();
			_popup.showConfirm("Exit", "Save before closing?", function(confirmed)
			{
				if (confirmed) saveOnExit();
				System.exit(0);
			});
		});

		#if html5
// Create demo project manually
		createDemoProject();
		#end

		#if windows
// Load project manually
		loadProject();
		#end

// Pass control of the limit to TickGenerator
		TickGenerator.getInstance().maxStepsPerFrame = 100;
	}

// =========================================================================
// v2.5: TRANSPARENCY INITIALIZATION
// =========================================================================
	/**
	* Initialize Windows transparency support.
	* Enables color-key transparency where black pixels become transparent.
	*/
	private function initTransparency():Void
	{
		_windowController = new WindowController();

		#if windows
// Enable transparency by default at startup
		if (_windowController.enableLayeredTransparency())
		{
			log("Main Window: Transparency ENABLED (Black = Transparent)");
// Set black stage background so "transparent" areas become transparent
			stage.color = _theme.APP_BG_BLACK;
		}
		else {
			log("Main Window: Transparency NOT SUPPORTED or FAILED");
		}
		#end
	}

// =========================================================================
// DEMO PROJECT (v1.1 — with connections)
// =========================================================================
	private function createDemoProject():Void
	{
//this.visible = false;

		var demoBlueprint = new Blueprint("demo", "Demo Showcase", [
		{name: "IN", type: INPUT},
		{name: "OUT", type: OUTPUT}
		]);

		var rootAssembly = new Assembly("main_asm", demoBlueprint);
		_editorContext.push(rootAssembly, true);

		var editor = _editorContext.currentEditor;

// === Generate IDs for connections ===
		var openPortButtonId = UID.generate();
		var closePortButtonId = UID.generate();
		var sendTxDataButtonId = UID.generate();
		var textInputTxDataId = UID.generate();
		var textAreaRxDataId = UID.generate();
		var comportStatusLedId = UID.generate();
		var comport1AtomId = UID.generate();
		var fileWriterId = UID.generate();
		var openFileButtonId = UID.generate();
		var closeFileButtonId = UID.generate();
		var fileWriterStatusLedId = UID.generate();

// === Create atoms ===
		editor.createAtomWithId("ComPortAtom", comport1AtomId, 500, 20);
		editor.createAtomWithId("Button", openPortButtonId, 200, 50);
		editor.createAtomWithId("Button", closePortButtonId, 200, 150);
		editor.createAtomWithId("Button", sendTxDataButtonId, 200, 250);
		editor.createAtomWithId("TextInput", textInputTxDataId, 200, 350);
		editor.createAtomWithId("TextArea", textAreaRxDataId, 850, 350);
		editor.createAtomWithId("LED", comportStatusLedId, 750, 70);
		editor.createAtomWithId("FileWriterAtom", fileWriterId, 1100, 20);
		editor.createAtomWithId("Button", openFileButtonId, 900, 50);
		editor.createAtomWithId("Button", closeFileButtonId, 900, 150);
		editor.createAtomWithId("LED", fileWriterStatusLedId, 1300, 70);

// === Connect them! ===
// Button.out → LED.in
		editor.connectAtoms(comport1AtomId, "isOpen", comportStatusLedId, "in");
		editor.connectAtoms(comport1AtomId, "rxData", textAreaRxDataId, "append");
		editor.connectAtoms(openPortButtonId, "out", comport1AtomId, "open");
		editor.connectAtoms(closePortButtonId, "out", comport1AtomId, "close");
		editor.connectAtoms(sendTxDataButtonId, "out", comport1AtomId, "send");
		editor.connectAtoms(textInputTxDataId, "out", comport1AtomId, "txData");
		editor.connectAtoms(openFileButtonId, "out", fileWriterId, "open");
		editor.connectAtoms(closeFileButtonId, "out", fileWriterId, "close");
		editor.connectAtoms(comport1AtomId, "rxData", fileWriterId, "append");
		editor.connectAtoms(fileWriterId, "isOpen", fileWriterStatusLedId, "in");

		trace("MainHTML5: Demo project created with 2 atoms and 1 connection");

// ==========================================
// ALTAURI PROGRAMMATIC SETUP PIPELINE
// ==========================================

// 1. Rename Atoms (Human-readable UI)
		renameAtom(rootAssembly, openPortButtonId, "Open Port");
		renameAtom(rootAssembly, closePortButtonId, "Close Port");
		renameAtom(rootAssembly, sendTxDataButtonId, "Send TX");
		renameAtom(rootAssembly, textInputTxDataId, "TX Payload");
		renameAtom(rootAssembly, comportStatusLedId, "COMPort Open?");
		renameAtom(rootAssembly, comport1AtomId, "COM1 Interface");
		renameAtom(rootAssembly, fileWriterId, "File Writer");
		renameAtom(rootAssembly, openFileButtonId, "Open File");
		renameAtom(rootAssembly, closeFileButtonId, "Close File");
		renameAtom(rootAssembly, fileWriterStatusLedId, "FileWriter Open?");

// 2. Inject Data into Databank
		injectTextInputData(rootAssembly, textInputTxDataId, "ALTAURI Data 1234567890\r");

// 3. Force initial redraw of the schematic
		haxe.Timer.delay(function()
		{
			if (editor != null && !editor.isDisposed)
			{
				editor.forceFullRedraw();
			}
// v3.0: Use DisplayConfig instead of _isPanelMode
			if (DisplayConfig.getInstance().isDeviceMode())
			{
				onToggleView();
			}
		}, 10);

// 4. Setup Device Panel & Toggle View
		haxe.Timer.delay(function()
		{
// 1. SWITCH MODE FIRST
// If we add devices before toggling, restoreDevicePanelFromCache()
// will call clearDevices() and wipe our manual additions.
// v3.0: Use DisplayConfig instead of _isPanelMode
			if (!DisplayConfig.getInstance().isDeviceMode())
			{
				onToggleView();
			}

			if (_devicePanel == null) return;

// 2. ADD WIDGETS
			var comport1Atom:Atom = cast rootAssembly.internalAtoms.get(comport1AtomId);
			var txAtom:Atom = cast rootAssembly.internalAtoms.get(textInputTxDataId);
			var textArea:Atom = cast rootAssembly.internalAtoms.get(textAreaRxDataId);
			var comportledAtom:Atom = cast rootAssembly.internalAtoms.get(comportStatusLedId);
			var openPortBtAtom:Atom = cast rootAssembly.internalAtoms.get(openPortButtonId);
			var closePortBtAtom:Atom = cast rootAssembly.internalAtoms.get(closePortButtonId);
			var sendBtAtom:Atom = cast rootAssembly.internalAtoms.get(sendTxDataButtonId);
			var openFileBtAtom:Atom = cast rootAssembly.internalAtoms.get(openFileButtonId);
			var closeFileBtAtom:Atom = cast rootAssembly.internalAtoms.get(closeFileButtonId);
			var fileLedAtom:Atom = cast rootAssembly.internalAtoms.get(fileWriterStatusLedId);

			if (comport1Atom != null) _devicePanel.addDevice(comport1Atom, 10, 10);
			if (txAtom != null) _devicePanel.addDevice(txAtom, 350, 50);
			if (textArea != null) _devicePanel.addDevice(textArea, 550, 250);
			if (comportledAtom != null) _devicePanel.addDevice(comportledAtom, 300, 270);
			if (openPortBtAtom != null) _devicePanel.addDevice(openPortBtAtom, 100, 280);
			if (closePortBtAtom != null) _devicePanel.addDevice(closePortBtAtom, 200, 280);
			if (sendBtAtom != null) _devicePanel.addDevice(sendBtAtom, 500, 50);
			if (openFileBtAtom != null) _devicePanel.addDevice(openFileBtAtom, 100, 450);
			if (closeFileBtAtom != null) _devicePanel.addDevice(closeFileBtAtom, 200, 450);
			if (fileLedAtom != null) _devicePanel.addDevice(fileLedAtom, 300, 440);

// 3. SYNC CACHE
// Crucial: saves the current panel layout to _cachedDeviceWindowState.
// Without this, toggling back to Editor and then to Panel again would
// result in an empty screen because the cache would be empty.
			syncDevicePanelToCache();

// v3.0: Use DisplayConfig instead of _isPanelMode
			if (!DisplayConfig.getInstance().isDeviceMode())
			{
				onToggleView();
			}

//this.visible = true;
		}, 10);
		
		updateNavigationUI();
		updateButtonStates();
		
		//Видимость кнопок Button Visibility
		var cfg = DisplayConfig.getInstance();
		cfg.deviceButtons.showClose = false;     // Скрыть [X] с Device панели
	}

	/**
	* Programmatically renames an atom while respecting the global NamingService registry.
	* Prevents memory leaks of old names and guarantees global uniqueness.
	*
	* @param asm       The assembly containing the atom
	* @param atomId    The runtime ID of the atom
	* @param desired   The human-readable name you want to assign
	*/
	private function renameAtom(asm:Assembly, atomId:String, desired:String):Void
	{
		var atom:Atom = cast asm.internalAtoms.get(atomId);
		if (atom != null)
		{
			var oldName = atom.displayName;
// Resolve ensures if "Open Port" is taken, it becomes "Open Port_1"
			var uniqueName = core.logic.NamingService.resolveUniqueInstanceName(desired, atomId);
// Atomically unregisters oldName and registers uniqueName
			core.logic.NamingService.renameInstance(oldName, uniqueName, atomId);
			atom.displayName = uniqueName;
		}
	}

	/**
	* Injects initial data into the TextInput Databank.
	* The Widget will automatically reflect this value via the "set" -> "out" pipeline.
	*/
	private function injectTextInputData(asm:Assembly, atomId:String, text:String):Void
	{
		var atom:Atom = cast asm.internalAtoms.get(atomId);
		if (atom != null)
		{
			var setContact = atom.getInput("set");
			if (setContact != null)
			{
				setContact.value = text;
			}
		}
	}

// =========================================================================
// LOADING v2.7
// =========================================================================
	/**
	* Load project from Selfrun.atom file.
	* Restores editor state, device window state, and assembly hierarchy.
	*/
	private function loadProject():Void
	{
		var data = _projectManager.loadSelfrun();
		var rootAssembly:Assembly = null;

// v1.0: Reset NamingService before loading any atoms — ensures stale
// entries from a previous session are gone.
		core.logic.NamingService.clearInstanceNames();

		if (data != null && data.blueprint != null)
		{
			rootAssembly = new Assembly("main_asm", data.blueprint);

// _createInternalInstances() inside the Assembly constructor will now
// register every loaded atom's displayName in NamingService automatically.

//trace('=== DEBUG: Checking isLogic flags ===');
			checkIsLogicRecursive(rootAssembly, 0);
//trace('=== DEBUG: Check complete ===');

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

// === v4.3: Force full redraw after project load ===
// WireRenderer and ViewportManager may not have triggered
// their initial draw cycle yet. Delay ensures all nodes
// are registered in ECS before we redraw.
			if (_editorContext.currentEditor != null)
			{
				haxe.Timer.delay(function()
				{
					if (_editorContext.currentEditor != null)
					{
						_editorContext.currentEditor.forceFullRedraw();
					}
				}, 100);
			}

			if (data.isOpen)
			{
// On load, if it was open, switch to Device mode
// v3.0: Reset DisplayConfig mode before toggle
				DisplayConfig.getInstance().currentMode = DisplayMode.EDITOR;
				onToggleView();
			}

			log("Project loaded (v3.0 with DisplayConfig).");
		}
		else {
			createEmptyProject();
		}

		updateNavigationUI();
		updateButtonStates();
	}

	/**
	* Recursively check and log isLogic flags for all atoms.
	* Used for debugging logic mode state.
	*/
	private function checkIsLogicRecursive(asm:Assembly, depth:Int):Void
	{
		if (asm == null || asm.internalAtoms == null || depth > 10) return;

//var indent = StringTools.lpad("", "  ", depth);

		for (id in asm.internalAtoms.keys())
		{
			var atom = asm.internalAtoms.get(id);
			if (atom != null)
			{
//var logicStatus = atom.isLogic ? "DIGITAL" : "ANALOG";
//trace('${indent}Atom: ${atom.name} (${atom.id}) - ${logicStatus}');

				if (Std.isOfType(atom, Assembly))
				{
					checkIsLogicRecursive(cast(atom, Assembly), depth + 1);
				}
			}
		}
	}

	/**
	* Create empty project with default blueprint.
	*/
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

// =========================================================================
// SAVING v2.8
// =========================================================================
	/**
	* Save current context (root or nested assembly).
	* Syncs device panel state before writing file.
	*/
	private function saveCurrentContext():Void
	{
		var isRoot = (_editorContext.getStackLength() == 1);

		if (isRoot)
		{
			log("Saving Root...");

// v3.0: Use DisplayConfig instead of _isPanelMode
			var cfg = DisplayConfig.getInstance();
			if (cfg.isDeviceMode())
			{
				syncDevicePanelToCache();
			}

			var viewState = _editorContext.currentEditor.getViewState();
			var devicesData = _cachedDeviceWindowState != null ? _cachedDeviceWindowState : [];
			var isWindowOpen = cfg.isDeviceMode(); // If in panel mode, then "open"

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

	/**
	* Save on application exit.
	*/
	private function saveOnExit():Void
	{
		log("Auto-saving on exit...");
		_editorContext.prepareCurrentAssemblyForSave();
		saveCurrentContext();
	}

// =========================================================================
// ACTIONS & UI CALLBACKS
// =========================================================================
	/**
	* Back button clicked.
	* Saves unsaved assembly or navigates back.
	*/
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
// v2.2: Sync blueprint BEFORE save (renames, port names, template IDs)
					_editorContext.prepareCurrentAssemblyForSave();
					saveNewNamedAssembly(name);
					closeCurrentEditor(true);
				}
			});
		}
		else {
// v2.2: Sync blueprint BEFORE save so disk matches memory.
// Without this, renamed atoms and semantic port names are lost
// on app restart.
			_editorContext.prepareCurrentAssemblyForSave();
			saveCurrentContext();
			closeCurrentEditor(true);
		}
	}

	/**
	* Close current editor and return to parent.
	*/
	private function closeCurrentEditor(updateInstances:Bool):Void
	{
		_editorContext.pop(updateInstances);
		updateNavigationUI();
		updateButtonStates();
		log("Returned to: " + _editorContext.currentAssembly.blueprint.name);
	}

	/**
	* Delete current assembly button clicked.
	* Shows confirmation dialog.
	*/
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

	/**
	* Confirm assembly deletion.
	* Removes from registry, deletes file, closes editor.
	*/
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

	/**
	* Clean up dangling references to deleted assembly.
	* Removes any atoms of the deleted type from current assembly.
	*/
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

	/**
	* Save new named assembly.
	* v2.0: Updates blueprint ID and name, then saves.
	*
	* v2.1 CHANGES (NamingService integration):
	* ────────────────────────────
	*  - blueprint.name is now resolved through NamingService to guarantee
	*    global uniqueness against ALL other registered blueprints (native
	*    atoms + every saved custom assembly).
	*  - If user enters a name that's already taken, NamingService silently
	*    appends "_N" (e.g., "MyFilter_1"). Per user policy (c):
	*    user can rename later via inline editor.
	*  - blueprint.id is derived from the FINAL resolved name (spaces→"_"),
	*    so it's also guaranteed unique.
	*  - If the resulting bp.id already exists in AtomRegistry, we warn
	*    but DO NOT overwrite — instead we re-suffix until both id and
	*    name are free. This prevents data loss when a user types a name
	*    that coincidentally matches an existing blueprint file.
	*/
	private function saveNewNamedAssembly(name:String):Void
	{
		var safeName = StringTools.replace(name, " ", "_");
		if (safeName.length == 0) { log("Error: Invalid assembly name."); return; }

// v2.1: Resolve a globally-unique blueprint name.
// NamingService checks AtomRegistry for duplicates against
// every existing blueprint.name (native + custom).
		var uniqueName = core.logic.NamingService.resolveUniqueBlueprintName(name);
		if (uniqueName != name)
		{
			log('Name "$name" already taken — saved as "$uniqueName"');
		}

		var uniqueSafeId = StringTools.replace(uniqueName, " ", "_");

		var bp = _editorContext.currentAssembly.blueprint;
		bp.id = uniqueSafeId;
		bp.name = uniqueName;

// Register in AtomRegistry if not already there.
// (For a freshly-created unsaved assembly, it isn't registered yet.)
		if (!library.AtomRegistry.exists(bp.id))
		{
			library.AtomRegistry.registerBlueprint(bp.id, bp);
		}

		saveCurrentContext();
	}

// =========================================================================
// v2.7: TOGGLE VIEW & STATE SYNC
// =========================================================================
	/**
	* Saves the current DevicePanel state to cache.
	* Called before switching to Editor mode.
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
	* Restores DevicePanel state from cache.
	* Called when switching to Device Panel mode.
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

	/**
	* Toggle between Editor Mode and Device Panel Mode.
	* Syncs state and manages widget lifecycle.
	*
	* v3.0: Uses DisplayConfig.toggleMode() instead of direct _isPanelMode flip.
	* The visual synchronization is handled by _onDisplayModeChanged handler.
	*/
	private function onToggleView():Void
	{
// v3.0: Toggle via DisplayConfig (emits DISPLAY_MODE_CHANGED)
		var cfg = DisplayConfig.getInstance();
		cfg.toggleMode();

		if (cfg.isDeviceMode())
		{
// --- SWITCH TO DEVICE PANEL MODE ---
			log("Mode: Device Panel");

// 1. Hide Editor and editor UI
			_editorLayer.visible = false;
			_uiLayer.visible = false;

// 2. Show Device Panel
			_devicePanel.visible = true;
			_devicePanel.setSize(stage.stageWidth, stage.stageHeight);

// 3. Pass current context (assembly)
			_devicePanel.setContext(_editorContext.currentAssembly);

// 4. Restore state from cache
			restoreDevicePanelFromCache();

// 5. Close separate window (if open)
			if (_deviceWindow != null && _deviceWindow.isOpen) _deviceWindow.close();

			#if windows
			_windowController.enableLayeredTransparency();
			#end
		}
		else {
// --- SWITCH TO EDITOR MODE ---
			log("Mode: Node Editor");

			syncDevicePanelToCache();

			if (_devicePanel != null) _devicePanel.visible = false;

			_editorLayer.visible = true;
			_uiLayer.visible = true;

			if (_devicePanel != null) _devicePanel.clearDevices();

			if (_editorContext.currentEditor != null)
			{
// Restore widgets synchronously
				_editorContext.currentEditor.restoreAllWidgets();

// v2.3 FIX: Single synchronous redraw. No timers needed.
// WireRenderer.rebuildAll() now safely skips unready nodes,
// so wires will appear as soon as NodeViews complete layout.
				_editorContext.currentEditor.forceFullRedraw();
			}
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
			_editorContext.prepareCurrentAssemblyForSave();
			saveCurrentContext();
			_windowSaveTimer = null;
			log("Device state auto-saved.");
		}, 300);
	}

// =========================================================================
// v3.0: DISPLAY EVENT HANDLERS (Impulsys subscriptions)
// =========================================================================
	/**
	* Handle DISPLAY_MODE_CHANGED event from DisplayConfig.
	* Synchronizes UI layers visibility with the new display mode.
	*
	* NOTE: The heavy logic (sync cache, restore widgets, force redraw)
	* is done in onToggleView(). This handler only does lightweight
	* visual synchronization for cases where mode changes externally
	* (e.g., from another component or future hotkey service).
	*
	* @param impulse Impulse containing {mode: DisplayMode}
	*/
	private function _onDisplayModeChanged(impulse:Impulse):Void
	{
		if (impulse == null || impulse.data == null) return;

		var mode:DisplayMode = impulse.data.mode;

// Lightweight visual sync — heavy logic is in onToggleView()
		switch (mode)
		{
			case DisplayMode.EDITOR:
// Ensure editor layers are visible
				if (_editorLayer != null) _editorLayer.visible = true;
				if (_uiLayer != null) _uiLayer.visible = true;
				if (_devicePanel != null) _devicePanel.visible = false;

			case DisplayMode.DEVICE_PANEL:
// Ensure device panel is visible
				if (_editorLayer != null) _editorLayer.visible = false;
				if (_uiLayer != null) _uiLayer.visible = false;
				if (_devicePanel != null) _devicePanel.visible = true;
		}
	}

	/**
	* Handle SCENE_RESIZED event from DisplayConfig.
	* Updates button positions and editor size when scene dimensions change.
	*
	* @param impulse Impulse containing {width: Float, height: Float}
	*/
	private function _onSceneResized(impulse:Impulse):Void
	{
		if (impulse == null || impulse.data == null) return;

		var w:Float = impulse.data.width;
		var h:Float = impulse.data.height;

// Update button positions (right-to-left layout)
		var cfg = DisplayConfig.getInstance();
		var btnSize = cfg.editorButtons.buttonSize;
		var btnPadding = cfg.buttonPadding;
		var rightEdge = w - btnPadding;

		if (_btnClose != null) _btnClose.x = rightEdge - btnSize;
		if (_btnBack != null) _btnBack.x = _btnClose.x - btnSize - btnPadding;
		if (_btnDelete != null) _btnDelete.x = _btnBack.x - btnSize - btnPadding;
		if (_btnView != null) _btnView.x = _btnDelete.x - btnSize - btnPadding;
		if (_btnNew != null) _btnNew.x = _btnView.x - btnSize - btnPadding;
		if (_btnReset != null) _btnReset.x = _btnNew.x - btnSize - btnPadding;
		if (_btnSettings != null) _btnSettings.x = _btnReset.x - btnSize - btnPadding;

// Update editor size
		if (_editorContext.currentEditor != null)
		{
			var margin = 12;
			_editorContext.currentEditor.setSize(w - margin * 2, h - margin * 2);
		}

// Update device panel size
		if (_devicePanel != null && _devicePanel.visible)
		{
			_devicePanel.setSize(w, h);
		}
	}

	/**
	* Handle FULLSCREEN_TOGGLED event from DisplayConfig.
	* Updates the DevicePanel maximize button icon when fullscreen state changes.
	*
	* @param impulse Impulse containing {isFullscreen: Bool}
	*/
	private function _onFullscreenToggled(impulse:Impulse):Void
	{
		if (impulse == null || impulse.data == null) return;

		var isFullscreen:Bool = impulse.data.isFullscreen;

// Update DevicePanel maximize button icon
		if (_devicePanel != null)
		{
			_devicePanel.setMaximizedState(isFullscreen);
		}
	}

// =========================================================================
// MAIN LOOP & SETUP
// =========================================================================
	/**
	* Main application loop.
	* Called every frame via ENTER_FRAME event.
	* Delegates to TickGenerator for unified simulation update.
	*/
	private function onMainLoop(e:Event):Void
	{
		var now = Lib.getTimer();
		var dt = (now - _lastTime) / 1000.0;
		_lastTime = now;

// Unified update via TickGenerator
		TickGenerator.getInstance().update(dt);
	}

	/**
	* Setup debug log field.
	*/
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

	/**
	* Log message to debug field with auto-hide.
	*/
	private function log(msg:String)
	{
//trace(msg);
		if (_hideTimer != null) _hideTimer.stop();

		if (_debugField != null)
		{
			_debugField.text = msg;
			_debugField.alpha = 1.0;
			_debugField.visible = true;
		}

		_hideTimer = haxe.Timer.delay(function() { fadeOutLog(); }, 5000);
	}

	/**
	* Fade out debug log.
	*/
	private function fadeOutLog() { if (_debugField != null) _debugField.visible = false; }

	/**
	* Setup UI layers.
	*/
	private function setupLayers():Void
	{
		_editorLayer = new Sprite();
		addChild(_editorLayer);

		_uiLayer = new Sprite();
		addChild(_uiLayer);

		_settingsLayer = new Sprite();
		addChild(_settingsLayer);
	}

	/**
	* Build UI elements and buttons.
	*
	* v3.0: Uses DisplayConfig for button sizes and padding.
	* Subscribes to DISPLAY_MODE_CHANGED, SCENE_RESIZED, FULLSCREEN_TOGGLED.
	*/
	private function buildUI():Void
	{
// =========================================================================
// HTML5 FULLSCREEN CHANGE LISTENER
// =========================================================================
		#if html5
		js.Browser.document.addEventListener("fullscreenchange", function(_) 
		{
			var cfg = DisplayConfig.getInstance();
			var isCurrentlyFullscreen = (js.Browser.document.fullscreenElement != null);
			
			// Sync state if it was changed externally (e.g., user pressed Esc)
			if (cfg.isFullscreen != isCurrentlyFullscreen) 
			{
				cfg.isFullscreen = isCurrentlyFullscreen; 
				// This setter automatically emits FULLSCREEN_TOGGLED via Impulsys
			}
		});
		#end

// v3.0: Use DisplayConfig instead of local variables
		var cfg = DisplayConfig.getInstance();
		var btnSize = cfg.editorButtons.buttonSize;
		var btnPadding = cfg.buttonPadding;
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
		Impulsys.subscribeToImpulse(EventType.PORT_REMOVED, onPortRemoved);

// ═══════════════════════════════════════════════════════════════════════
// v3.0: SUBSCRIBE TO DISPLAY EVENTS (Direct method references)
// ═══════════════════════════════════════════════════════════════════════
Impulsys.subscribeToImpulse(EventType.DISPLAY_MODE_CHANGED, _onDisplayModeChanged);
Impulsys.subscribeToImpulse(EventType.SCENE_RESIZED, _onSceneResized);
Impulsys.subscribeToImpulse(EventType.FULLSCREEN_TOGGLED, _onFullscreenToggled);

// v2.5: Initialize DevicePanel
		_devicePanel = new DevicePanel();
		_devicePanel.visible = false;
		addChild(_devicePanel);

		_devicePanel.onShowEditor = function()
		{
// v3.0: Use DisplayConfig instead of _isPanelMode
			if (DisplayConfig.getInstance().isDeviceMode()) onToggleView();
		};

		_devicePanel.onGetAssemblyList = getAllDevicesRecursive;

// v3.5: Flicker-free window drag — absolute position model
		var _dragWindowStartX:Int = 0;
		var _dragWindowStartY:Int = 0;

		_devicePanel.onWindowDragStart = function()
		{
			var win = Lib.current.stage.window;
			if (win != null)
			{
				_dragWindowStartX = win.x;
				_dragWindowStartY = win.y;
			}
		};

		_devicePanel.onWindowDrag = function(dx:Float, dy:Float)
		{
			var win = Lib.current.stage.window;
			if (win != null)
			{
// v3.5: Absolute position = start + delta
// No accumulation of rounding errors!
				win.x = _dragWindowStartX + Std.int(dx);
				win.y = _dragWindowStartY + Std.int(dy);
			}
		};

// DevicePanel app close callback
		_devicePanel.onCloseApp = function()
		{
			onCloseClicked();  // using existing closing method
		};

// v3.4: Move main window when dragging DevicePanel header
		_devicePanel.onWindowDrag = function(dx:Float, dy:Float)
		{
			var win = Lib.current.stage.window;
			if (win != null)
			{
				win.x = Std.int(win.x + dx);
				win.y = Std.int(win.y + dy);
			}
		};

// DevicePanel app close callback
		_devicePanel.onCloseApp = function()
		{
			onCloseClicked();  // using existing closing method
		};

		// =========================================================================
		// v3.9: CROSS-PLATFORM FULLSCREEN CALLBACK
		// =========================================================================
		// Unified fullscreen control via DisplayConfig
		// HTML5: Browser Fullscreen API (requestFullscreen on canvas)
		// Native: OS window resize/move via lime.ui.Window
		_devicePanel.onToggleMaximize = function()
		{
		var win = Lib.current.stage.window;
		var cfg = DisplayConfig.getInstance();

		// Delegate to DisplayConfig (handles both HTML5 and Native)
		cfg.toggleFullscreen(win);

		// UI update is handled by _onFullscreenToggled handler via Impulsys
		// which calls _devicePanel.setMaximizedState(cfg.isFullscreen)
		};
	}

	/**
	* Settings changed callback.
	* Updates editor configuration.
	*/
	private function onSettingsChanged():Void
	{
		if (_editorContext.currentEditor != null)
		{
			_editorContext.currentEditor.setUseEcsRender(_settingsPanel.useEcsRender);
			_editorContext.currentEditor.setWireType(_settingsPanel.wireType);
			_editorContext.currentEditor.setAllowAssembly(_settingsPanel.allowAssembly);
		}

		updateButtonStates();
		updateSettingsStats();
	}

	/**
	* Window resize handler.
	*
	* v3.0: Uses DisplayConfig for scene dimensions and fullscreen state.
	*/
	private function onResize(e:Event):Void
	{
		graphics.clear();
		graphics.beginFill(_theme.APP_BG_COLOR, 0); // Alpha = 0 (Fully transparent)
		graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
		graphics.endFill();

		_debugField.y = stage.stageHeight - 40;
		_pathField.y = stage.stageHeight - 20;

// v3.0: Use DisplayConfig for button sizes
		var cfg = DisplayConfig.getInstance();
		var btnSize = cfg.editorButtons.buttonSize;
		var btnPadding = cfg.buttonPadding;
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
// v3.0: Use DisplayConfig instead of _isPanelMode
		if (cfg.isDeviceMode() && _devicePanel != null)
		{
			_devicePanel.setSize(stage.stageWidth, stage.stageHeight);
		}

// =========================================================================
// v3.8: SYNC MAXIMIZE STATE WITH WINDOW SIZE
// =========================================================================
// If window was resized externally (e.g., user dragged to screen edge),
// update maximize state to match
// v3.0: Use DisplayConfig instead of _isWindowMaximized
		if (cfg.isDeviceMode() && _devicePanel != null)
		{
			var win = Lib.current.stage.window;
			if (win != null)
			{
				var display = win.display;
				if (display != null && display.currentMode != null)
				{
					var isFullscreen = (win.width >= display.currentMode.width - 10 &&
					win.height >= display.currentMode.height - 10);

					if (isFullscreen != cfg.isFullscreen)
					{
						cfg.isFullscreen = isFullscreen;
						_devicePanel.setMaximizedState(cfg.isFullscreen);
					}
				}
			}
		}

// v3.0: Update DisplayConfig scene dimensions
		cfg.sceneWidth = stage.stageWidth;
		cfg.sceneHeight = stage.stageHeight;
	}

	/**
	* Update button visibility based on context.
	*/
	private function updateButtonStates():Void
	{
		var isRoot = (_editorContext.getStackLength() <= 1);

		_btnBack.visible = !isRoot;
		_btnDelete.visible = !isRoot;
		_btnNew.visible = _settingsPanel.allowAssembly;
	}

	/**
	* Update navigation UI (name field, path field).
	*
	* v3.8 FIX: Passes the global name uniqueness checker to ContextMenuManager
	* so it can be forwarded to GroupAtomsCommand during atom grouping.
	*/
	private function updateNavigationUI():Void
	{
		if (_editorContext.currentAssembly != null)
		{
			_nameField.text = _editorContext.currentAssembly.blueprint.name;
			_pathField.text = "Depth: " + _editorContext.getStackLength();
		}

		if (_contextManager != null)
		{
// Pass the global uniqueness checker down the chain
			_contextManager.setContext(
				_editorContext.currentEditor,
				_editorContext.currentAssembly,
				_editorContext.isNameTakenGlobally
			);
		}
	}

// =========================================================================
// HELPERS & EVENTS
// =========================================================================
	/**
	* Open assembly request handler.
	* Navigates into nested assembly.
	*/
	private function onOpenAssemblyRequest(impulse:Impulse):Void
	{
		if (!_settingsPanel.allowAssembly)
		{
			log("Assembly editing disabled");
			return;
		}

		if (impulse == null || impulse.data == null)
		{
//trace("ERROR: Open Assembly Request has no data!");
			return;
		}

		var id = impulse.data.atomId;

//trace('DEBUG: Open Request for ID: $id');

		var obj = _editorContext.currentAssembly.internalAtoms.get(id);

		if (obj == null)
		{
			var runtimeId = _editorContext.currentAssembly.idMap.get(id);
			if (runtimeId != null)
			{
				obj = _editorContext.currentAssembly.internalAtoms.get(runtimeId);
//trace('DEBUG: Found via ID Map. RuntimeID: $runtimeId');
			}
		}

		if (obj == null)
		{
//trace('ERROR: Atom with ID $id NOT FOUND in current assembly!');
//trace('  Available keys: ${[for(k in _editorContext.currentAssembly.internalAtoms.keys()) k]}');
			return;
		}

		if (!Std.isOfType(obj, Assembly))
		{
//trace('ERROR: Object $id is NOT an Assembly. It is ${Type.getClassName(Type.getClass(obj))}');
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

	/**
	* Request new assembly context handler.
	* Creates and opens new empty assembly.
	*
	* v3.8 FIX: Ensures the new assembly gets a globally unique display name
	* to prevent naming collisions with existing assemblies in the project hierarchy.
	*/
	private function onRequestNewContext(impulse:Impulse):Void
	{
		var bp:Blueprint = impulse.data.blueprint;
		var id:String = impulse.data.id;

// v3.8 FIX: Resolve globally-unique blueprint.name via NamingService.
// NamingService delegates to AtomRegistry for blueprint-name uniqueness,
// so "New Assembly" becomes "New Assembly_1", "New Assembly_2", etc.
// when several empty assemblies are created in a row.
		bp.name = core.logic.NamingService.resolveUniqueBlueprintName(bp.name);

		var newAsm = new Assembly(id, bp);
		_editorContext.push(newAsm);

		log("Created New Assembly Context: " + bp.name);

		updateNavigationUI();
		updateButtonStates();
	}

	/**
	* Value committed handler.
	* Saves project after value change.
	*/
	private function onValueCommitted(impulse:Impulse):Void
	{
		_editorContext.prepareCurrentAssemblyForSave();
		saveCurrentContext();
		log("Data saved.");
	}

	/**
	* Properties request handler.
	* Opens properties window for atom.
	*/
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

	/**
	* New assembly button clicked.
	*/
	private function onNewAssembly():Void
	{
//	if (!_settingsPanel.allowAssembly) { log("Assembly disabled"); return; }

		var cmd = new CreateNewAssemblyCommand();
		UndoManager.getInstance().executeAndStore(cmd);
	}

	/**
	* Reset button clicked.
	* Performs hard reset and creates empty project.
	*/
	private function onResetClick():Void
	{
		hardReset();
		createEmptyProject();
		// v3.0 FIX: Restore UI context after reset
		updateNavigationUI();
		updateButtonStates();
		log("System Reset.");
	}

	/**
	* Handle PORT_REMOVED event: remove external wires connected to the deleted port.
	*/
	private function onPortRemoved(impulse:Impulse):Void
	{
		if (impulse == null || impulse.data == null) return;

		var asmId:String = impulse.data.assemblyId;
		var portName:String = impulse.data.portName;

// Get current stack
		var stack = _editorContext.getStackEntries();
		if (stack.length == 0) return;

// Find the parent assembly (the one that contains asmId as an internal atom)
		var parentAssembly:Assembly = null;

// Start from the bottom of the stack (root) upwards
		for (i in 0...stack.length)
		{
			var entry = stack[i];

// Check if this assembly contains the deleted assembly as an internal atom
			var contains = false;
			for (runtimeId in entry.assembly.internalAtoms.keys())
			{
				var atom = entry.assembly.internalAtoms.get(runtimeId);
				if (atom != null && atom.id == asmId)
				{
					contains = true;
					break;
				}
			}

// Also check via idMap (for template IDs)
			if (!contains)
			{
				for (templateId in entry.assembly.idMap.keys())
				{
					if (templateId == asmId)
					{
						contains = true;
						break;
					}
				}
			}

			if (contains)
			{
				parentAssembly = entry.assembly;
				break;
			}
		}

		if (parentAssembly == null)
		{
// No parent found (maybe it's the root itself) — nothing to do
			return;
		}

// Remove wires from parent blueprint that reference SELF.portName
		var bp = parentAssembly.blueprint;
		var toRemove:Array<core.data.Blueprint.ConnectionDef> = [];

		for (conn in bp.internalConnections)
		{
			if (conn.from.atomId == "SELF" && conn.from.contactName == portName)
			{
				toRemove.push(conn);
			}
			else if (conn.to.atomId == "SELF" && conn.to.contactName == portName)
			{
				toRemove.push(conn);
			}
		}

		if (toRemove.length > 0)
		{
			for (conn in toRemove)
			{
				bp.internalConnections.remove(conn);
			}

// Notify editor to redraw wires
			Impulsys.quickEmit(EventType.REDRAW_WIRES);

			trace('Removed ${toRemove.length} external wires connected to port "$portName" of assembly $asmId');
		}
	}

	/**
	* Hard reset - clears all state and managers.
	*
	* v3.0: Resets DisplayConfig mode and unsubscribes from display events.
	*/
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

		_devicePanel.onShowEditor = function()
		{
// v3.0: Use DisplayConfig instead of _isPanelMode
			if (DisplayConfig.getInstance().isDeviceMode()) onToggleView();
		};

		_devicePanel.onGetAssemblyList = getAllDevicesRecursive;

		addChild(_devicePanel);

// v3.0: Reset DisplayConfig mode
		DisplayConfig.getInstance().currentMode = DisplayMode.EDITOR;

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
		// v3.0 FIX: Restore RecentMenuTracker subscription after Impulsys.clear()
		ui.contextmenu.data.RecentMenuTracker.getInstance().resubscribe();

// v3.0: Re-subscribe to display events after Impulsys.clear()
		Impulsys.subscribeToImpulse(EventType.DISPLAY_MODE_CHANGED, _onDisplayModeChanged);
		Impulsys.subscribeToImpulse(EventType.SCENE_RESIZED, _onSceneResized);
		Impulsys.subscribeToImpulse(EventType.FULLSCREEN_TOGGLED, _onFullscreenToggled);

		_contextManager = new ContextMenuManager(_settingsPanel);
		_uiLayer.addChild(_contextManager.getView());

		DriverManager.getInstance().dispose();
		TickGenerator.getInstance().clear();
		UndoManager.getInstance().clear();
		ECS.reset();
	}

	/**
	* Main window close request handler.
	*/
	private function onMainWindowClose():Void
	{
		saveOnExit();
		System.exit(0);

//   _popup.showConfirm("Exit", "Do You want to close Editor?", function(confirmed:Bool)
//    {
//        if (confirmed)
//        {
//        }
//    });
	}

	/**
	* Close button clicked.
	*/
	private function onCloseClicked():Void
	{
		saveOnExit();
		System.exit(0);

//   _popup.showConfirm("Exit", "Do You want to close Editor?", function(confirmed:Bool)
//    {
//        if (confirmed)
//        {
//        }
//    });
	}

	/**
	* Keyboard handler.
	*
	* BUG 2 FIX: Added TextField focus check.
	* Before processing single-key shortcuts (D, R, E, DELETE, BACKSPACE),
	* we now check if stage.focus is a TextField. If it is, the user is
	* typing in an input field, and we should not intercept their keystrokes.
	*
	* Ctrl+key shortcuts (Ctrl+C, Ctrl+Z, etc.) are still processed even
	* when a TextField has focus, because those are deliberate editor
	* commands that should override text input.
	*/
	private function onKeyDown(e:KeyboardEvent):Void
	{
		if (_popup.visible) return;

// BUG 2 FIX: If a TextField has keyboard focus, skip
// single-key shortcuts but keep Ctrl+key shortcuts.
// This prevents 'D' from deleting atoms while typing in
// TextInputWidget, while still allowing Ctrl+C, Ctrl+Z, etc.
		var focusObj = Lib.current.stage.focus;
		var isTextFieldFocused:Bool = Std.isOfType(focusObj, TextField);

// Also check if focus is on a TextField in a DeviceWindow
// (separate native window) — we check all windows' stages.
// For simplicity, any TextField focus blocks single-key shortcuts.
		if (isTextFieldFocused && !e.ctrlKey && !e.altKey) return;

		if (e.keyCode == Keyboard.S && !e.ctrlKey) { _editorContext.prepareCurrentAssemblyForSave(); saveCurrentContext(); return; }

		if (e.ctrlKey && e.keyCode == Keyboard.C) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.copySelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.X) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.cutSelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.V) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.pasteSelection(); return; }
		if (e.ctrlKey && e.keyCode == Keyboard.A) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.selectAll(); return; }

// Reset Viewport
		if (e.ctrlKey && e.keyCode == Keyboard.NUMBER_0)
		{
			if (_editorContext.currentEditor != null)
			{
				_editorContext.currentEditor.centerOnContent();
			}
			return;
		}

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

	/**
	* Delete selected nodes or wires on canvas.
	*/
	private function deleteSelectedOnCanvas():Void
	{
		if (_editorContext.currentEditor == null) return;

		var nodeCount = _editorContext.currentEditor.getSelectedNodeCount();
		var wireIds = _editorContext.currentEditor.getSelectedWireIds();

		trace('DEBUG: nodeCount=$nodeCount, wireIds.length=${wireIds.length}');
		trace('DEBUG: selectedNodeIds=${_editorContext.currentEditor.getSelectedNodeIds()}');

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

	/**
	* Update settings panel statistics.
	*/
	private function updateSettingsStats():Void
	{
		if (_settingsPanel != null && _editorContext.currentEditor != null)
		{
			_settingsPanel.updateStats(_editorContext.currentEditor.getNodeCount(), _editorContext.currentEditor.getWireCount(),
			_settingsPanel.useEcsRender, _settingsPanel.wireType, _settingsPanel.allowAssembly);
		}
	}

	/**
	* Settings button clicked.
	*/
	private function onSettingsClick():Void
	{
		if (_settingsPanel.visible) _settingsPanel.visible = false;
		else {
			_settingsPanel.show(stage.stageWidth, stage.stageHeight);
			updateSettingsStats();
		}
	}

	/**
	* Restore editor window visibility.
	*/
	private function restoreEditorWindow():Void
	{
		var mainWin = Lib.current.stage.window;
		if (mainWin != null) mainWin.visible = true;
	}

	/**
	* Check if assembly file exists in library.
	*/
	private function isAssemblyFileExists(id:String):Bool
	{
		#if sys return sys.FileSystem.exists(_projectManager.libraryPath + "/" + id + ".atom"); #else return true; #end
	}

// =========================================================================
// DEVICE WINDOW HELPERS v2.2
// =========================================================================
	/**
	* Get all devices recursively from current assembly.
	*/
	private function getAllDevicesRecursive():Array< {id:String, name:String, atom:Atom}>
	{
		var result:Array<{id:String, name:String, atom:Atom}> = [];

		if (_editorContext.currentAssembly != null)
		{
			collectDevicesRecursive(_editorContext.currentAssembly, result);
		}

		return result;
	}

	/**
	* Recursively collect devices from assembly hierarchy.
	*/
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

	/**
	* Extract device window data for saving.
	*/
	private function extractDeviceWindowData():Array< {path:Array<String>, x:Float, y:Float, ?width:Float, ?height:Float}>
	{
// v3.0: Use DisplayConfig instead of _isPanelMode
		if (_devicePanel != null && _devicePanel.visible)
		{
			return _cachedDeviceWindowState;
		}

		return _cachedDeviceWindowState != null ? _cachedDeviceWindowState : [];
	}

	/**
	* Find device path in assembly hierarchy.
	*/
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

	/**
	* Resolve device path to atom instance.
	*/
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