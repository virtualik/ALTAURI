package;

#if !html5
import sys.io.File;
#end
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
import ui.TitleBar;
import ui.ResizeGrip;
import system.commands.editor.CreateNewAssemblyCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.editor.RemovePortCommand;
import system.commands.base.MacroCommand;
import ecs.ECS;
import library.AtomRegistry;
import utils.UID;
using StringTools;

/**
* MAIN v3.1 (DisplayConfig Integration + Crash Traps)
* Application entry point and main coordinator.
*
* ═══════════════════════════════════════════════════════════════════════════
* ═══════════════════════════════════════════════════════════════════════════
* v3.1 CHANGES (Crash Traps — BUG-A hunt)
* ═══════════════════════════════════════════════════════════════════════════
*
*  - onBackClicked(): entry breadcrumb (all exit paths funnel here).
*  - closeCurrentEditor(): breadcrumbs around pop() and
*    updateNavigationUI() (layoutChrome runs right after pop —
*    prime crash candidate zone).
*  - onMainLoop(): 1 Hz BEAT heartbeat to crash_trap.log — the last
*    BEAT timestamp marks the exact death second even when stdout
*    buffering eats the tail on a hard crash.
*
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
*  │  TRYDENT Architecture - Windows | Android | HTML5                   │
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
        private var _trapBeatFrames:Int = 0; // v3.1: BEAT heartbeat counter
        private var _theme:EditorTheme;
        private var _deviceWindow:DeviceWindow;

// v2.5: Device Panel & Transparency
        private var _devicePanel:DevicePanel;
        private var _windowController:WindowController;

// --- v4.0: Editor chrome (title bar + corner resize grip) ---
        private var _titleBar:TitleBar;
        private var _resizeGrip:ResizeGrip;

// --- v4.3: startup-complete guard for fullscreen autosave ---
        private var _uiReady:Bool = false;
        
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
				
				// v1.4 (Episod H-1): black box FIRST — stderr capture + native SEH sentinel
				utils.Trap.boot();
				
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
                        canvas.oncontextmenu = function(e:js.html.Event) { e.preventDefault(); return false; };
                        
                        // ═══════════════════════════════════════════════════════════════
                        // Жёсткий запрет на браузерную обработку тач-событий
                        // Предотвращает рассинхрон между JS-потоком и Compositor Thread Chrome
                        // ═══════════════════════════════════════════════════════════════
                        untyped canvas.style.touchAction = "none";
                        
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
                        canvas.oncontextmenu = function(e:js.html.Event) { e.preventDefault(); return false; };
                        
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
                
                log("System initialized");

                removeEventListener(Event.ADDED_TO_STAGE, init);
                
// v4.3: Restore window rect + maximized state from the previous session
// BEFORE the window becomes visible (project.xml starts it hidden → no flash)
                #if !html5
                restoreMainWindowState();
                #end
                
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
// HTML5 Target - Load blueprint based on DOM data-attribute
                loadHTML5Blueprint();
                #end
                
                #if windows
// WiNDOWS Target - Load project from file
                //createDemoProject();
                loadProject();
                #end
                
                #if android
// ANDROID Target - Creation method
                createDemoProject(); 
                //loadProject();
                #end
                
                #if linux
// HTML5 Target - Load blueprint based on DOM data-attribute
                createDemoProject(); 
                //loadHTML5Blueprint();
                #end
                
                
// Pass control of the limit to TickGenerator
                TickGenerator.getInstance().maxStepsPerFrame = 100;
                
// v4.3: Startup complete — enable fullscreen-toggle autosave
                _uiReady = true;
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
                // v1.1: Singleton — TitleBar and ResizeGrip share this instance
                _windowController = WindowController.getInstance();

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

                var demoBlueprint = new Blueprint("demo", "demo", [
                //{name: "IN", type: INPUT},
                //{name: "OUT", type: OUTPUT}
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
                                // Center the viewport on the content after initial layout is ready
                                _editorContext.currentEditor.centerOnContent();
                        }
// v3.0: Switch to Device mode
                        if (DisplayConfig.getInstance().isEditorMode())
                        {
                                DisplayConfig.getInstance().currentMode = DisplayMode.DEVICE_PANEL;
                                onToggleView();
                        }
                }, 1);

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
//                      var comportledAtom:Atom = cast rootAssembly.internalAtoms.get(comportStatusLedId);
//                      var openPortBtAtom:Atom = cast rootAssembly.internalAtoms.get(openPortButtonId);
//                      var closePortBtAtom:Atom = cast rootAssembly.internalAtoms.get(closePortButtonId);
                        var sendBtAtom:Atom = cast rootAssembly.internalAtoms.get(sendTxDataButtonId);
                        var filewriter1Atom:Atom = cast rootAssembly.internalAtoms.get(fileWriterId);
                        var openFileBtAtom:Atom = cast rootAssembly.internalAtoms.get(openFileButtonId);
                        var closeFileBtAtom:Atom = cast rootAssembly.internalAtoms.get(closeFileButtonId);
                        var fileLedAtom:Atom = cast rootAssembly.internalAtoms.get(fileWriterStatusLedId);

                        if (comport1Atom != null) _devicePanel.addDevice(comport1Atom, 20, 150);

                        if (txAtom != null) _devicePanel.addDevice(txAtom, 450, 450);
                        if (sendBtAtom != null) _devicePanel.addDevice(sendBtAtom, 600, 450);
                        
                        if (textArea != null) _devicePanel.addDevice(textArea, 400, 200);
//                      if (comportledAtom != null) _devicePanel.addDevice(comportledAtom, 250, 270);
//                      if (openPortBtAtom != null) _devicePanel.addDevice(openPortBtAtom, 50, 280);
//                      if (closePortBtAtom != null) _devicePanel.addDevice(closePortBtAtom, 150, 280);

                        if (filewriter1Atom != null) _devicePanel.addDevice(filewriter1Atom, 800, 150);
                        //if (openFileBtAtom != null) _devicePanel.addDevice(openFileBtAtom, 800, 250);
                        //if (closeFileBtAtom != null) _devicePanel.addDevice(closeFileBtAtom, 900, 250);
                        //if (fileLedAtom != null) _devicePanel.addDevice(fileLedAtom, 850, 140);

// 3. SYNC CACHE
// Crucial: saves the current panel layout to _cachedDeviceWindowState.
// Without this, toggling back to Editor and then to Panel again would
// result in an empty screen because the cache would be empty.
                        syncDevicePanelToCache();
                }, 1);
                
                updateNavigationUI();
                updateButtonStates();
                
                //Видимость кнопок Button Visibility
                var cfg = DisplayConfig.getInstance();
                cfg.deviceButtons.showClose = false;     // Скрыть [X] с Device панели
                
                // v3.0: Switch to Editor mode ПРОВЕРИТЬ ПОЧЕМУ НЕ ПЕРЕКЛЮЧАЕТСЯ В РЕДАКТОР?
                        if (!DisplayConfig.getInstance().isEditorMode())
                        {
                                DisplayConfig.getInstance().currentMode = DisplayMode.EDITOR;
                                onToggleView();
                        }

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
                                                // Center the viewport on the loaded content
                                                _editorContext.currentEditor.centerOnContent();
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

    /**
    * HTML5 specific loader.
    * Reads "data-blueprint" attribute from the parent DOM element 
    * and fetches the .atom file via HTTP.
    */
    private function loadHTML5Blueprint():Void
    {
        #if html5
        var blueprintUrl:String = null;

        // Получаем канвас текущего OpenFL-инстанса
        var canvas:js.html.CanvasElement = untyped openfl.Lib.current.stage.window.element;
        
        // Поднимаемся вверх по DOM-дереву, пока не найдем data-blueprint
        var el:js.html.Element = canvas;
        while (el != null && blueprintUrl == null)
        {
            blueprintUrl = el.getAttribute("data-blueprint");
            el = el.parentElement;
        }

        if (blueprintUrl != null && blueprintUrl != "")
        {
            log("Loading HTML5 blueprint: " + blueprintUrl);
            
            // Защита от кэша
            var http = new haxe.Http(blueprintUrl + "?t=" + Date.now().getTime());
            
            http.onData = function(data:String)
            {
                try {
                    var json = haxe.Json.parse(data);
                    buildProjectFromJSON(json);
                } catch (err:Dynamic) {
                    log("Blueprint parse error: " + err);
                    createDemoProject(); // Fallback
                }
            };
            
            http.onError = function(err:String)
            {
                log("Failed to load blueprint file: " + err);
                createDemoProject(); // Fallback
            };
            
            http.request();
        }
        else
        {
            log("No data-blueprint attribute found. Creating default demo.");
            createDemoProject();
        }
        #end
    }

    /**
    * Builds the project from parsed JSON data.
    * Works identically to loadProject(), but takes Dynamic JSON 
    * instead of reading from local file system.
    */
    private function buildProjectFromJSON(json:Dynamic):Void
    {
        var rawBp = json.blueprint;
        
        // Используем наш новый публичный метод из ProjectIO
        var bp = system.io.ProjectIO.parseBlueprint(rawBp);
        
        core.logic.NamingService.clearInstanceNames();
        var rootAssembly = new Assembly("main_asm", bp);
        _editorContext.push(rootAssembly, true);

        _cachedDeviceWindowState = [];

        // Парсим устройства
        if (json.deviceWindow != null && json.deviceWindow.devices != null)
        {
            for (d in (json.deviceWindow.devices : Array<Dynamic>))
            {
                var w:Float = (d.width != null) ? Std.parseFloat(Std.string(d.width)) : 100.0;
                var h:Float = (d.height != null) ? Std.parseFloat(Std.string(d.height)) : 80.0;
                _cachedDeviceWindowState.push({
                    path: d.path,
                    x: Std.parseFloat(Std.string(d.x)),
                    y: Std.parseFloat(Std.string(d.y)),
                    width: w,
                    height: h
                });
            }
        }

        // Парсим состояние вьюпорта
        var viewState = { x: 0.0, y: 0.0, zoom: 1.0 };
        if (json.editor != null)
        {
            viewState.x = json.editor.x != null ? Std.parseFloat(Std.string(json.editor.x)) : 0.0;
            viewState.y = json.editor.y != null ? Std.parseFloat(Std.string(json.editor.y)) : 0.0;
            viewState.zoom = json.editor.zoom != null ? Std.parseFloat(Std.string(json.editor.zoom)) : 1.0;
        }
        _editorContext.currentEditor.setViewState(viewState);

        // Принудительная перерисовка
        haxe.Timer.delay(function()
        {
            if (_editorContext.currentEditor != null)
            {
                _editorContext.currentEditor.forceFullRedraw();
                _editorContext.currentEditor.centerOnContent();
            }
        }, 100);

       // if (json.deviceWindow != null && json.deviceWindow.isOpen)
        {
            DisplayConfig.getInstance().currentMode = DisplayMode.EDITOR;
            onToggleView();
        }

        updateNavigationUI();
        updateButtonStates();
        log("Project loaded from JSON successfully.");
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
                                _cachedWindowY, collectMainWindowState()
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
                utils.Trap.log("EXIT", "prepareForSave done");
                
                saveCurrentContext();
                utils.Trap.log("EXIT", "saveCurrentContext done");
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
                utils.Trap.log("EXIT", "onBackClicked: enter stack=" + _editorContext.getStackLength());
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
                                        utils.Trap.log("EXIT", "prepareForSave done");
                                        
                                        saveNewNamedAssembly(name);
                                        closeCurrentEditor(true);
                                        utils.Trap.log("EXIT", "closeCurrentEditor returned");
                                }
                        });
                }
                else {
// v2.2: Sync blueprint BEFORE save so disk matches memory.
// Without this, renamed atoms and semantic port names are lost
// on app restart.
                        _editorContext.prepareCurrentAssemblyForSave();
                        utils.Trap.log("EXIT", "prepareForSave done");
                        
                        saveCurrentContext();
                        utils.Trap.log("EXIT", "saveCurrentContext done");
                        
                        closeCurrentEditor(true);
                        utils.Trap.log("EXIT", "closeCurrentEditor returned");
                }
        }

        /**
        * Close current editor and return to parent.
        */
        private function closeCurrentEditor(updateInstances:Bool):Void
        {
                utils.Trap.log("EXIT", "closeCurrentEditor: pre-pop updateInstances=" + updateInstances);
                _editorContext.pop(updateInstances);
                utils.Trap.log("EXIT", "pop returned; updateNavigationUI next");
                updateNavigationUI();
                updateButtonStates();
                utils.Trap.log("EXIT", "closeCurrentEditor: done");
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
                utils.Trap.log("EXIT", "saveCurrentContext done");
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
                                // Reset gesture flags before redrawing
                                editor.EditorState.setIsZooming(false);
                                editor.EditorState.setIsPanning(false);
                                
                                // Restore widgets to NodeViews
                                _editorContext.currentEditor.restoreAllWidgets();
                                
                                /**
                                * Defer the full redraw to the next frame cycle.
                                * restoreAllWidgets() traverses all nodes and re-acquires their
                                * DeviceViews, which is heavy on low-end devices. By deferring
                                * the redraw, the browser presents the editor layer immediately,
                                * and the wire/node redraw happens asynchronously.
                                */
                                haxe.Timer.delay(function() {
                                        if (_editorContext.currentEditor != null && !_editorContext.currentEditor.isDisposed)
                                        {
                                                _editorContext.currentEditor.forceFullRedraw();
                                                
                                                // Force WebGL context to refresh cached layer states
                                                if (stage != null) {
                                                        stage.invalidate();
                                                }
                                        }
                                }, 50);
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
                        utils.Trap.log("EXIT", "prepareForSave done");
                        
                        saveCurrentContext();
                        utils.Trap.log("EXIT", "saveCurrentContext done");
                        
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
                // v4.0: Unified chrome layout (TitleBar + buttons + editor offset + grip)
                layoutChrome();

// Update device panel size
                if (_devicePanel != null && _devicePanel.visible)
                {
                        _devicePanel.setSize(w, h);
                }
        }

        /**
        * Handle FULLSCREEN_TOGGLED event from DisplayConfig.
        * Updates maximize icons (TitleBar + DevicePanel), resize grip visibility,
        * and v4.3: persists the window state (agreed cadence: exit + toggle).
        *
        * @param impulse Impulse containing {isFullscreen: Bool}
        */
        private function _onFullscreenToggled(impulse:Impulse):Void
        {
                        if (impulse == null || impulse.data == null) return;

                        var isFullscreen:Bool = impulse.data.isFullscreen;

                        if (_devicePanel != null) _devicePanel.setMaximizedState(isFullscreen);
                        if (_titleBar != null) _titleBar.setMaximizedState(isFullscreen);
                        if (_resizeGrip != null) _resizeGrip.visible = !isFullscreen;

// v4.3: persist window state on every fullscreen toggle.
// _uiReady guards the startup maximize (restoreMainWindowState) from
// triggering a save BEFORE the project is fully loaded.
                        #if !html5
                        if (_uiReady)
                        {
                                        _editorContext.prepareCurrentAssemblyForSave();
                                        utils.Trap.log("EXIT", "prepareForSave done");
                                        
                                        saveCurrentContext();
                                        utils.Trap.log("EXIT", "saveCurrentContext done");
                        }
                        #end
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
			// v1.4 (Episod H-1): the whole frame body is guarded — an exception here
			// killed the process silently (exit code 1, stderr lost in the lime pipe).
			utils.Trap.ex("LOOP", function() {
			TickGenerator.getInstance().update(dt);
			});

			// v3.1: 1 Hz heartbeat — last BEAT marks the death second.
			_trapBeatFrames++;
			if (_trapBeatFrames >= 60)
			{
					_trapBeatFrames = 0;
					utils.Trap.log("BEAT", "alive");
			}
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

                // =========================================================================
// v4.0: EDITOR TITLE BAR (top chrome: drag + [-] minimize + [□] maximize)
// =========================================================================
// Created FIRST so it renders behind every other _uiLayer child.
// Main's editor buttons are re-parented INTO the bar (see M5), the bar
// owns their layout via setSize(); the three duplicated positioning
// blocks (buildUI / onResize / _onSceneResized) collapse into layoutChrome().
                _titleBar = new TitleBar();
                _uiLayer.addChild(_titleBar);

// Maximize/Restore → DisplayConfig (cross-platform; emits FULLSCREEN_TOGGLED,
// which updates BOTH TitleBar and DevicePanel icons — single source of truth)
                _titleBar.onToggleMaximize = function()
                {
                                var win = Lib.current.stage.window;
                                DisplayConfig.getInstance().toggleFullscreen(win);
                };

// Minimize → OS taskbar (button is hidden on HTML5 inside TitleBar itself)
                _titleBar.onMinimize = function()
                {
                                _windowController.minimize();
                };

// Haxe-side drag fallback (absolute position model — same as DevicePanel v3.5)
        {
                        var dragStartX:Int = 0;
                        var dragStartY:Int = 0;

                        _titleBar.onWindowDragStart = function()
                        {
                                        var win = Lib.current.stage.window;
                                        if (win != null)
                                        {
                                                        dragStartX = win.x;
                                                        dragStartY = win.y;
                                        }
                        };

                        _titleBar.onWindowDrag = function(dx:Float, dy:Float)
                        {
                                        var win = Lib.current.stage.window;
                                        if (win != null)
                                        {
                                                        // Absolute position = start + delta (no rounding drift)
                                                        win.x = dragStartX + Std.int(dx);
                                                        win.y = dragStartY + Std.int(dy);
                                        }
                        };
        }

                _popup = new TextInputPopup();
                addChild(_popup);
// Registration order matters: [X] first (rightmost), then <, E, V, N, R, ? —
// TitleBar places them right-to-left AFTER the native [-][□] pair:
// [ Selfrun ... ]                   [?][R][N][V][E][<]   [-]    [□]    [X]
//  └ drag zone ┘                   └──── Main 40×40 ──┘└28×26┘└28×26┘└40×40┘
                _btnClose = new ButtonComponent("X", onCloseClicked);
                _btnClose.x = startX - btnSize; _btnClose.y = startY;
                _titleBar.addControlButton(_btnClose);

                _btnBack = new ButtonComponent("<", onBackClicked);
                _btnBack.x = _btnClose.x - btnSize - btnPadding; _btnBack.y = startY;
                _titleBar.addControlButton(_btnBack);

                _btnDelete = new ButtonComponent("E", onDeleteCurrentAssembly);
                _btnDelete.x = _btnBack.x - btnSize - btnPadding; _btnDelete.y = startY;
                _titleBar.addControlButton(_btnDelete);

                _btnView = new ButtonComponent("V", onToggleView);
                _btnView.x = _btnDelete.x - btnSize - btnPadding; _btnView.y = startY;
                _titleBar.addControlButton(_btnView);

                _btnNew = new ButtonComponent("N", onNewAssembly);
                _btnNew.x = _btnView.x - btnSize - btnPadding; _btnNew.y = startY;
                _titleBar.addControlButton(_btnNew);

                _btnReset = new ButtonComponent("R", onResetClick);
                _btnReset.x = _btnNew.x - btnSize - btnPadding; _btnReset.y = startY;
                _titleBar.addControlButton(_btnReset);

                _btnSettings = new ButtonComponent("?", onSettingsClick);
                _btnSettings.x = _btnReset.x - btnSize - btnPadding; _btnSettings.y = startY;
                 _titleBar.addControlButton(_btnSettings);

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

                // v3.2 (Episod F-bold): all 9 init subscriptions (6 core + 3
                // display) now live in resubscribeImpulses(). The method is
                // registered with Impulsys v2.0, so after any Impulsys.clear()
                // the bus restores these subscriptions by itself — hardReset()
                // no longer needs a manual recovery block.
                resubscribeImpulses();
                Impulsys.registerResubscriber(resubscribeImpulses);

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
                // =========================================================================
                // v4.0: RESIZE GRIP (manual window resize — works in BOTH display modes)
                // =========================================================================
                // Added to Main ROOT after all layers → always on top, never clipped.
                // Hidden on HTML5 (browser owns canvas size).
                #if !html5
                _resizeGrip = new ResizeGrip();
                _resizeGrip.windowController = _windowController;
                addChild(_resizeGrip);
                #end
                // v4.0: Initial chrome layout (bar + buttons + editor offset + grip position)
                layoutChrome();
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
    * v4.2: fullscreen state sync uses IsZoomed (OS truth) on Windows;
    * the old size heuristic stays only for non-Windows native targets.
    */
    private function onResize(e:Event):Void
    {
        graphics.clear();
        graphics.beginFill(_theme.APP_BG_COLOR, 0); // Alpha = 0 (Fully transparent)
        graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
        graphics.endFill();

        _debugField.y = stage.stageHeight - 40;
        _pathField.y = stage.stageHeight - 20;

        var cfg = DisplayConfig.getInstance();

// v4.0: Unified chrome layout (TitleBar + buttons + editor offset + grip)
        layoutChrome();

// v2.5: Resize DevicePanel if active
        if (cfg.isDeviceMode() && _devicePanel != null)
        {
            _devicePanel.setSize(stage.stageWidth, stage.stageHeight);
        }

// =========================================================================
// v3.8 / v4.2: SYNC MAXIMIZE STATE WITH THE OS
// =========================================================================
// Windows: IsZoomed is the authoritative source (SW_MAXIMIZE).
// Other native: legacy size heuristic.
// Icon updates happen automatically via the isFullscreen setter, which
// emits FULLSCREEN_TOGGLED → _onFullscreenToggled() → both bars + grip.
        if (_devicePanel != null || _titleBar != null)
        {
            var win = Lib.current.stage.window;
            if (win != null)
            {
                #if windows
                var isFullscreen = _windowController.isZoomed();
                #else
                var isFullscreen = false;
                var display = win.display;
                if (display != null && display.currentMode != null)
                {
                    isFullscreen = (win.width >= display.currentMode.width - 10 &&
                        win.height >= display.currentMode.height - 10);
                }
                #end

                if (isFullscreen != cfg.isFullscreen)
                {
                    cfg.isFullscreen = isFullscreen; // setter emits FULLSCREEN_TOGGLED
                }
            }
        }

// v3.0: Update DisplayConfig scene dimensions
        cfg.sceneWidth = stage.stageWidth;
        cfg.sceneHeight = stage.stageHeight;
    }
        
        /**
        * v4.0: Unified top-chrome layout.
        * Single place that positions:
        *   1. TitleBar background + ALL control buttons (native + editor row)
        *   2. Editor layer vertical offset (content starts below the bar)
        *   3. Current editor forced size (stage minus bar minus margins)
        *   4. Resize grip pinned to the bottom-right corner
        *
        * Called from: buildUI, onResize, _onSceneResized, updateNavigationUI
        * (updateNavigationUI ensures freshly pushed NodeEditors — created when
        *  the user enters an assembly — also receive the bar offset).
        */
        private function layoutChrome():Void
        {
                        if (stage == null) return;
                        var w:Float = stage.stageWidth;
                        var h:Float = stage.stageHeight;

                        // 1. Title bar + all control buttons inside it
                        if (_titleBar != null) _titleBar.setSize(w, h);

                        // 2. Editor content starts below the bar
                        if (_editorLayer != null) _editorLayer.y = TitleBar.BAR_HEIGHT;

                        if (_editorContext != null && _editorContext.currentEditor != null)
                        {
                                        var margin = 12;
                                        _editorContext.currentEditor.setSize(
                                                        w - margin * 2,
                                                        h - TitleBar.BAR_HEIGHT - margin * 2);
                        }

                        // 3. Resize grip pinned to bottom-right corner
                        if (_resizeGrip != null)
                        {
                                        _resizeGrip.x = w - ResizeGrip.SIZE;
                                        _resizeGrip.y = h - ResizeGrip.SIZE;
                        }
        }

    /**
        * v4.3: Restore the main window rect + maximized state from the previous
        * session (Selfrun.atom → "mainWindow" section).
        *
        * v4.3.2 FIXES:
        * - Saved rect sanitized BEFORE applying: an entry covering >= 98% of the
        *   target display (corrupt "fullscreen stored as windowed" — the bug
        *   where restore produced a taskbar-covering windowed window) is
        *   self-healed to 90% of the display.
        * - cfg.saveWindowState(win) is called AFTER positioning and BEFORE
        *   SW_MAXIMIZE, seeding DisplayConfig.savedWindowRect with the TRUE
        *   pre-maximize rect. Previously a session that STARTED maximized and
        *   never toggled [□] could exit with a stale/null savedWindowRect and
        *   persist the fullscreen rect as the windowed one.
        */
        private function restoreMainWindowState():Void
        {
                #if !html5
                var st = _projectManager.loadMainWindowStateEarly();
                var win = Lib.current.stage.window;
                if (st == null || win == null) return;

                var bounds = _currentDisplayBounds(win, st.screen);
                if (bounds == null) bounds = new lime.math.Rectangle(0, 0, 1920, 1080);

                var w = Math.min(Math.max(st.width, WindowController.MIN_TRACK_W), bounds.width);
                var h = Math.min(Math.max(st.height, WindowController.MIN_TRACK_H), bounds.height);

// v4.3.2: self-heal a corrupt fullscreen-sized windowed rect
                if (w >= bounds.width * 0.98 && h >= bounds.height * 0.98)
                {
                                w = bounds.width * 0.9;
                                h = bounds.height * 0.9;
                }

                var x = Math.min(Math.max(st.x, bounds.x), bounds.x + bounds.width - 100);
                var y = Math.min(Math.max(st.y, bounds.y), bounds.y + bounds.height - 40);

                win.resize(Std.int(w), Std.int(h));
                win.move(Std.int(x), Std.int(y));

// v4.3.2: seed savedWindowRect with the TRUE pre-maximize rect
                DisplayConfig.getInstance().saveWindowState(win);

                #if windows
                if (st.maximized && _windowController != null)
                {
                                _windowController.maximize();
                                // cfg.isFullscreen is synced by onResize (IsZoomed) — icons follow
                }
                #end
                #end
        }

  /**
        * v4.3: Collect the current main window state for persistence.
        *
        * v4.3.2: while zoomed, the pre-maximize rect is taken from
        * DisplayConfig.savedWindowRect ONLY when it is sane (>= min track size
        * and < 98% of the display). Otherwise it is synthesized as 90% of the
        * display, centered — a corrupt/stale savedWindowRect can no longer
        * poison the save file with a fullscreen-sized windowed rect.
        */
        private function collectMainWindowState():{x:Float, y:Float, width:Float, height:Float, screen:Int, maximized:Bool}
        {
                var win = Lib.current.stage.window;
                var cfg = DisplayConfig.getInstance();
                var maximized:Bool = false;
                #if windows
                if (_windowController != null) maximized = _windowController.isZoomed();
                #end

                var x:Float = win.x;
                var y:Float = win.y;
                var w:Float = win.width;
                var h:Float = win.height;

                if (maximized)
                {
                                var bounds = _currentDisplayBounds(win, -1);
                                if (bounds == null) bounds = new lime.math.Rectangle(0, 0, 1920, 1080);

                                var r = cfg.savedWindowRect;
                                var sane:Bool = (r != null
                                                && r.w >= WindowController.MIN_TRACK_W && r.h >= WindowController.MIN_TRACK_H
                                                && r.w <= bounds.width * 0.98 && r.h <= bounds.height * 0.98);

                                if (sane)
                                {
                                                x = r.x; y = r.y; w = r.w; h = r.h;
                                }
                                else
                                {
                                                // v4.3.2: synthesize 90% of the display, centered
                                                x = bounds.x + bounds.width * 0.05;
                                                y = bounds.y + bounds.height * 0.05;
                                                w = bounds.width * 0.9;
                                                h = bounds.height * 0.9;
                                }
                }

                return { x: x, y: y, width: w, height: h, screen: findScreenIndex(win), maximized: maximized };
        }

        /**
        * v4.3.2: Index of the display the window currently sits on.
        * Reference comparison of win.display is NOT reliable on C++ (Lime may
        * return a different instance), so the check is geometric: which display
        * bounds CONTAIN the window center; ties resolved by max overlap area.
        * Fallback: 0 (primary).
        */
        private function findScreenIndex(win:lime.ui.Window):Int
        {
                var displays = _getDisplayList();
                if (displays == null || displays.length == 0) return 0;

                var cx = win.x + win.width / 2;
                var cy = win.y + win.height / 2;

                // Pass 1: center containment
                for (i in 0...displays.length)
                {
                                var d = displays[i];
                                if (d == null || d.bounds == null) continue;
                                var b = d.bounds;
                                if (cx >= b.x && cx <= b.x + b.width && cy >= b.y && cy <= b.y + b.height)
                                {
                                                return i;
                                }
                }

                // Pass 2: max overlap area (window between monitors)
                var best = 0;
                var bestArea:Float = -1;
                for (i in 0...displays.length)
                {
                                var d = displays[i];
                                if (d == null || d.bounds == null) continue;
                                var b = d.bounds;
                                var ox = Math.max(0, Math.min(win.x + win.width, b.x + b.width) - Math.max(win.x, b.x));
                                var oy = Math.max(0, Math.min(win.y + win.height, b.y + b.height) - Math.max(win.y, b.y));
                                var area = ox * oy;
                                if (area > bestArea) { bestArea = area; best = i; }
                }
                return best;
        }

        /**
        * v4.3.2: Bounds of a display by saved index (or of the window current
        * display when index < 0). Fallback chain: display list → win.display.
        */
        private function _currentDisplayBounds(win:lime.ui.Window, screenIdx:Int):lime.math.Rectangle
        {
                        var displays = _getDisplayList();
                        if (displays != null && displays.length > 0)
                        {
                                        if (screenIdx >= 0 && screenIdx < displays.length && displays[screenIdx] != null)
                                        {
                                                        return displays[screenIdx].bounds;
                                        }
                        }
                        if (win != null && win.display != null) return win.display.bounds;
                        return null;
        }
                
    /**
    * v4.3.3 FIX: Enumerate connected displays version-safely.
    * The display-list API shape differs across Lime builds and NONE of the
    * static paths can be referenced directly at compile time:
    *   - lime.system.DisplayManager.displays  (static var, Lime 7.x)
    *   - lime.system.Display.getDisplays()    (static method, some builds)
    * Neither exists in this Lime build (both produced compile errors), so
    * EVERYTHING goes through reflection. When no static list is resolvable
    * the method returns null and all callers fall back to win.display
    * (the instance getter that provably works in this project — it was
    * used by the pre-v4.x onResize fullscreen heuristic).
    */
    private function _getDisplayList():Array<lime.system.Display>
    {
        // Path 1: DisplayManager.displays (Lime 7.x)
        try
        {
            var dm = Type.resolveClass("lime.system.DisplayManager");
            if (dm != null)
            {
                var list = Reflect.field(dm, "displays");
                if (list != null) return cast list;
            }
        }
        catch (e:Dynamic) {}

        // Path 2: Display.getDisplays() (static, some builds)
        try
        {
            var d = Type.resolveClass("lime.system.Display");
            if (d != null)
            {
                var fn = Reflect.field(d, "getDisplays");
                if (fn != null)
                {
                    var list = Reflect.callMethod(d, fn, []);
                    if (list != null) return cast list;
                }
            }
        }
        catch (e:Dynamic) {}

        // Path 3: Display internals + static var (last resort)
        try
        {
            var d = Type.resolveClass("lime.system.Display");
            if (d != null)
            {
                for (fieldName in ["displayList", "__displayList", "displays"])
                {
                    var list = Reflect.field(d, fieldName);
                    if (list != null) return cast list;
                }
            }
        }
        catch (e:Dynamic) {}

        // Path 4: lime.system.System.displays (if the build exposes it there)
        try
        {
            var s = Type.resolveClass("lime.system.System");
            if (s != null)
            {
                var list = Reflect.field(s, "displays");
                if (list != null) return cast list;
            }
        }
        catch (e:Dynamic) {}

        return null;
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
                        // FIX (title identity): show the instance displayName — the name the
                        // user sees on the assembly node in the parent schema. blueprint.name
                        // is the library-level identity and only syncs to displayName inside
                        // prepareCurrentAssemblyForSave() (on pop/exit), so it lags behind
                        // while the user is INSIDE the assembly ("внутри Custom Assembly_3,
                        // заголовок Custom Assembly_2").
                        var titleAsm = _editorContext.currentAssembly;
                        _nameField.text = (titleAsm.displayName != null && titleAsm.displayName != "")
                                ? titleAsm.displayName
                                : titleAsm.blueprint.name;
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
                // v4.0: Re-apply chrome layout so a freshly pushed NodeEditor (created on
                // entering an assembly) immediately receives the bar offset and size.
                layoutChrome();
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
                utils.Trap.log("EXIT", "prepareForSave done");
                
                saveCurrentContext();
                utils.Trap.log("EXIT", "saveCurrentContext done");
                
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
//      if (!_settingsPanel.allowAssembly) { log("Assembly disabled"); return; }

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
        *
        * v3.3 (Episod G-3) — the matcher is fixed. Parent-side wires never
        * reference the port as SELF.portName (that would mean the PARENT's
        * own wall): they store the child as <templateId>.<externalName>
        * ("Inlet_N"), so the old matcher could not hit a single wire. The
        * removed defs are handed to the executing RemovePortCommand so
        * undo() can restore them (the command cannot reach the parent
        * assembly itself — EditorContext lives here in Main).
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

// v3.3 (Episod G-3): match wires by TEMPLATE-resolved child + EXTERNAL name.
// Wires were created against "Inlet_N"/"Outlet_N" (the name shown on the
// parent side of the wall) — never against the internal "Arrival_N".
                var externalName:String = impulse.data.externalName;
                if (externalName == null) externalName = portName;
                var childBlueprintId:String = impulse.data.blueprintId;

                var bp = parentAssembly.blueprint;
                var toRemove:Array<core.data.Blueprint.ConnectionDef> = [];

                for (conn in bp.internalConnections)
                {
                        if (endpointHitsDeletedPort(conn.from, parentAssembly, asmId, childBlueprintId, externalName)
                         || endpointHitsDeletedPort(conn.to, parentAssembly, asmId, childBlueprintId, externalName))
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

// v3.3 (Episod G-3): hand the removed wires to the executing command so
// undo() can put them back. Runs inside RemovePortCommand.execute()/redo()
// — UndoManager tracks which command is executing right now.
                        var executing = UndoManager.getInstance().getExecutingCommand();
                        if (executing != null && Std.isOfType(executing, RemovePortCommand))
                        {
                                cast(executing, RemovePortCommand).adoptParentWires(bp, toRemove);
                        }

// Notify editor to redraw wires
                        Impulsys.quickEmit(EventType.REDRAW_WIRES);

                        trace('Removed ${toRemove.length} external wires connected to port "$externalName" of assembly $asmId');
                }
        }

        /**
        * v3.3 (Episod G-3): does this wire endpoint point at the deleted port?
        *
        * Blueprint connections store the child's TEMPLATE id; idMap resolves
        * template -> runtime. A hit requires BOTH:
        *  - the endpoint resolves to the deleted instance (runtime id match)
        *    or to ANY instance of the deleted blueprint (blueprints are
        *    shared — the pin is gone for every sibling instance too);
        *  - the endpoint's contact name equals the port's EXTERNAL name
        *    (that is the name wires were created with on the parent side).
        */
        private function endpointHitsDeletedPort(point:core.data.Blueprint.ConnectionPoint, parentAssembly:Assembly, asmId:String, childBlueprintId:String, externalName:String):Bool
        {
                if (point == null || point.contactName != externalName) return false;
                var runtimeId:String = parentAssembly.idMap.get(point.atomId);
                if (runtimeId == null) runtimeId = point.atomId;
                var atom:Atom = parentAssembly.internalAtoms.get(runtimeId);
                if (atom == null) return false;
                if (atom.id == asmId) return true;
                if (childBlueprintId != null && Std.isOfType(atom, Assembly))
                {
                        var asm:Assembly = cast(atom, Assembly);
                        return asm.blueprint != null && asm.blueprint.id == childBlueprintId;
                }
                return false;
        }

        /**
        * v3.2 (Episod F-bold): Re-subscribes all persistent Main callbacks
        * to Impulsys (6 core + 3 display events).
        *
        * Called once at init, and then automatically by Impulsys.clear()
        * (registered via registerResubscriber) — which is why hardReset()
        * contains no manual recovery block anymore. Impulsys' duplicate
        * protection makes repeat invocations safe.
        */
        private function resubscribeImpulses():Void
        {
                Impulsys.subscribeToImpulse(EventType.ATOM_PROPERTIES_REQUEST, onPropertiesRequest);
                Impulsys.subscribeToImpulse(EventType.OPEN_ASSEMBLY_REQUEST, onOpenAssemblyRequest);
                Impulsys.subscribeToImpulse(EventType.REQUEST_NEW_ASSEMBLY_CONTEXT, onRequestNewContext);
                Impulsys.subscribeToImpulse(EventType.VALUE_COMMITTED, onValueCommitted);
                Impulsys.subscribeToImpulse(EventType.DEVICE_WINDOW_CHANGED, onDeviceWindowChanged);
                Impulsys.subscribeToImpulse(EventType.PORT_REMOVED, onPortRemoved);
                Impulsys.subscribeToImpulse(EventType.DISPLAY_MODE_CHANGED, _onDisplayModeChanged);
                Impulsys.subscribeToImpulse(EventType.SCENE_RESIZED, _onSceneResized);
                Impulsys.subscribeToImpulse(EventType.FULLSCREEN_TOGGLED, _onFullscreenToggled);
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

                // v3.2 (Episod F-bold): the manual recovery block that lived
                // here (9 re-subscriptions + RecentMenuTracker.resubscribe() +
                // _editorContext.resubscribe(), patched twice after v3.0/v3.1
                // fixes) is gone. Impulsys v2.0 clear() now restores every
                // registered persistent resubscriber by itself.
                Impulsys.clear();

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

                if (e.keyCode == Keyboard.S && !e.ctrlKey) { _editorContext.prepareCurrentAssemblyForSave(); utils.Trap.log("EXIT", "prepareForSave done"); saveCurrentContext(); utils.Trap.log("EXIT", "saveCurrentContext done"); return; }

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
                        if (_editorContext.getStackLength() > 1) onBackClicked(); utils.Trap.log("EXIT", "onBackClicked: stack=" + _editorContext.getStackLength());
                        return;
                }

                if (e.ctrlKey && e.keyCode == Keyboard.Z) { UndoManager.getInstance().undo(); return; }
                if (e.ctrlKey && e.keyCode == Keyboard.Y) { UndoManager.getInstance().redo(); return; }

                if (e.keyCode == Keyboard.R) { onResetClick(); return; }
                if (e.keyCode == Keyboard.D || e.keyCode == Keyboard.DELETE) { deleteSelectedOnCanvas(); return; }
                if (e.keyCode == Keyboard.E) { if (_editorContext.getStackLength() > 1) onDeleteCurrentAssembly(); else log("Cannot erase root assembly."); return; }
                if (e.keyCode == Keyboard.BACKSPACE) { if (_editorContext.getStackLength() > 1) onBackClicked(); utils.Trap.log("EXIT", "onBackClicked: stack=" + _editorContext.getStackLength()); return; }
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
