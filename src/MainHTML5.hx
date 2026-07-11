package;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.Lib;

import core.base.Assembly;
import core.base.Atom;
import core.data.Blueprint;
import core.logic.TickGenerator;
import core.logic.Impulsys;

import editor.EditorContext;
import editor.EditorTheme;
import editor.NodeEditor;
import editor.ContextMenuManager;

import library.AtomRegistry;
import ecs.ECS;

import system.managers.DriverManager;
import system.managers.UndoManager;
import ui.SettingsPanel;

/**
 * MAIN HTML5 v1.0 (Showcase Entry Point)
 * 
 * Lightweight entry point for web showcase/demo.
 * 
 * Features:
 * - Editor with node canvas (drag, connect, delete)
 * - Demo atoms pre-loaded (Button, LED, Toggle, SignalGenerator)
 * - No file system operations
 * - No native drivers (audio, COM ports, etc.)
 * - Responsive layout support
 * - Localization support (optional)
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────┐
 * │  MainHTML5                                                  │
 * │                                                             │
 * │  ┌───────────────────────────────────────────────────────┐  │
 * │  │  Initialization:                                      │  │
 * │  │  1. AtomRegistry.initialize()  (UI atoms only)        │  │
 * │  │  2. ECS.init()                                        │  │
 * │  │  3. TickGenerator.init()                              │  │
 * │  │  4. Create demo project                               │  │
 * │  │  5. Setup EditorContext                               │  │
 * │  └───────────────────────────────────────────────────────┘  │
 * │                                                             │
 * │  ┌───────────────────────────────────────────────────────┐  │
 * │  │  UI Layers:                                           │  │
 * │  │  - _editorLayer  → NodeEditor (main canvas)           │  │
 * │  │  - _uiLayer      → Buttons, panels (optional)         │  │
 * │  └───────────────────────────────────────────────────────┘  │
 * │                                                             │
 * │  Main Loop:                                                 │
 * │  onEnterFrame() {                                           │
 * │      TickGenerator.getInstance().update(dt);                │
 * │  }                                                          │
 * │                                                             │
 * └─────────────────────────────────────────────────────────────┘
 */
class MainHTML5 extends Sprite
{
    // =========================================================================
    // UI LAYERS
    // =========================================================================
    private var _editorLayer:Sprite;
    private var _uiLayer:Sprite;
    
    // =========================================================================
    // MANAGERS
    // =========================================================================
    private var _editorContext:EditorContext;
    private var _contextManager:ContextMenuManager;
    private var _settingsPanel:SettingsPanel;
    
	// =========================================================================
    // STATE
    // =========================================================================
    private var _lastTime:Int = 0;
    private var _theme:EditorTheme;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new()
    {
        super();
        
        _theme = EditorTheme.getInstance();
        
        // Disable right-click context menu (browser default)
        #if html5
        var canvas:js.html.CanvasElement = cast js.Browser.document.getElementById("openfl-content");
        if (canvas == null) canvas = cast js.Browser.document.querySelector("canvas");
        if (canvas != null) canvas.oncontextmenu = function(e) { 
            e.preventDefault(); 
            return false; 
        };
        #end
        
        // Initialize systems
        initSystems();
        
        // Setup UI layers
        setupLayers();
        
        // Wait for stage
        if (stage != null) init();
        else addEventListener(Event.ADDED_TO_STAGE, init);
    }
    
    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    private function init(e:Event = null):Void
    {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        
        // Configure stage for HTML5
        stage.color = _theme.APP_BG_BLACK;
        stage.quality = HIGH;
        
        // Initialize editor context
        _editorContext = new EditorContext(_editorLayer);
        
		// === ИНИЦИАЛИЗАЦИЯ МЕНЮ ===
        _settingsPanel = new SettingsPanel();
        _settingsPanel.visible = false;
        _uiLayer.addChild(_settingsPanel);

        _contextManager = new ContextMenuManager(_settingsPanel);
        _uiLayer.addChild(_contextManager.getView());

        addEventListener(Event.ENTER_FRAME, onMainLoop);
        stage.addEventListener(Event.RESIZE, onResize);
		
        // Start main loop
        addEventListener(Event.ENTER_FRAME, onMainLoop);
        
        // Handle resize
        stage.addEventListener(Event.RESIZE, onResize);
        
        // Create demo project
        createDemoProject();
        
		// Передаём контекст меню
        _contextManager.setContext(_editorContext.currentEditor, _editorContext.currentAssembly);
        
		trace("MainHTML5: Showcase initialized");
    }
    
    // =========================================================================
    // SYSTEMS INITIALIZATION
    // =========================================================================
    private function initSystems():Void
    {
        // 1. Initialize AtomRegistry (UI atoms only, no native drivers)
        AtomRegistry.initialize();
        
        // 2. Initialize ECS render layer
        ECS.init();
        
        // 3. Initialize managers
        DriverManager.getInstance();
        UndoManager.getInstance();
        
        // 4. Initialize TickGenerator
        TickGenerator.getInstance();
        TickGenerator.getInstance().targetHz = 60;
        TickGenerator.getInstance().maxStepsPerFrame = 100;
        
        trace("MainHTML5: Systems initialized");
    }
    
    // =========================================================================
    // UI SETUP
    // =========================================================================
    private function setupLayers():Void
    {
        _editorLayer = new Sprite();
        addChild(_editorLayer);
        
        _uiLayer = new Sprite();
        addChild(_uiLayer);
    }
    
    // =========================================================================
    // DEMO PROJECT
    // =========================================================================
    private function createDemoProject():Void
    {
        // Create empty blueprint
        var demoBlueprint = new Blueprint("demo", "Demo Showcase", [
            {name: "IN", type: INPUT},
            {name: "OUT", type: OUTPUT}
        ]);
        
        var rootAssembly = new Assembly("main_asm", demoBlueprint);
        
        // Open in editor context
        _editorContext.push(rootAssembly, true);
        
        // Add demo atoms
        var editor = _editorContext.currentEditor;
        
        // Button → LED connection
        editor.createAtom("Button", 200, 200);
        editor.createAtom("LED", 400, 200);
        
        // Toggle → Relay → LED chain
        editor.createAtom("Toggle", 200, 350);
        editor.createAtom("Relay", 400, 350);
        editor.createAtom("LED", 600, 350);
        
        // SignalGenerator → Oscilloscope
        editor.createAtom("SignalGenerator", 200, 500);
        editor.createAtom("Oscilloscope", 500, 500);
        
        trace("MainHTML5: Demo project created with 7 atoms");
    }
    
    // =========================================================================
    // MAIN LOOP
    // =========================================================================
    private function onMainLoop(e:Event):Void
    {
        var now = Lib.getTimer();
        var dt = (now - _lastTime) / 1000.0;
        _lastTime = now;
        
        // Update simulation
        TickGenerator.getInstance().update(dt);
    }
    
    // =========================================================================
    // RESIZE HANDLER
    // =========================================================================
    private function onResize(e:Event):Void
    {
        if (_editorContext.currentEditor != null)
        {
            var margin = 12;
            _editorContext.currentEditor.setSize(
                stage.stageWidth - margin * 2,
                stage.stageHeight - margin * 2
            );
        }
    }
}