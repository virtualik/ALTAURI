package core.logic;

/**
* EVENT TYPE v1.4 (Display & Window State Events)
*
* Type-safe enumeration of all system events (Impulse types).
*
* Using abstract enum ensures:
* - Compile-time type checking
* - No string typos in event names
* - Efficient string representation at runtime
*
* ═══════════════════════════════════════════════════════════════════════════
* v1.4 CHANGES (Display & Window State — DisplayConfig Integration)
* ═══════════════════════════════════════════════════════════════════════════
*
*  ADDED: Three new event types for DisplayConfig singleton:
*
*  ┌────────────────────────┬──────────────────────────────────────────────┐
*  │ Event                  │ Purpose                                      │
*  ├────────────────────────┼──────────────────────────────────────────────┤
*  │ DISPLAY_MODE_CHANGED   │ Editor ↔ DevicePanel mode switch             │
*  │ SCENE_RESIZED          │ Stage/scene dimensions changed               │
*  │ FULLSCREEN_TOGGLED     │ Fullscreen/windowed state changed            │
*  └────────────────────────┴──────────────────────────────────────────────┘
*
*  CROSS-PLATFORM PAYLOAD CONTRACT:
*  ═══════════════════════════════════════════════════════════════════════
*
*  All three events carry a Dynamic payload object. The payload structure
*  is IDENTICAL on both C++ and HTML5 targets — the platform-specific
*  logic is encapsulated inside DisplayConfig, NOT in the event consumers.
*
*  ┌────────────────────────┬────────────────────────────────────────────┐
*  │ Event                  │ Payload Structure                          │
*  ├────────────────────────┼────────────────────────────────────────────┤
*  │ DISPLAY_MODE_CHANGED   │ { mode: DisplayMode }                      │
*  │                        │   mode = EDITOR | DEVICE_PANEL             │
*  │                        │                                            │
*  │ SCENE_RESIZED          │ { width: Float, height: Float }            │
*  │                        │   width/height = new scene dimensions      │
*  │                        │                                            │
*  │ FULLSCREEN_TOGGLED     │ { isFullscreen: Bool,                      │
*  │                        │   ?screenWidth: Float,                     │
*  │                        │   ?screenHeight: Float }                   │
*  │                        │                                            │
*  │                        │   CPP:   screenWidth/Height = display mode │
*  │                        │   HTML5: screenWidth/Height = window.inner │
*  │                        │          (may differ from screen on mobile)│
*  └────────────────────────┴────────────────────────────────────────────┘
*
*  PLATFORM-SPECIFIC NOTES:
*  ════════════════════════
*
*  C++ Target (Windows/Linux):
*  ───────────────────────────
*  - FULLSCREEN_TOGGLED uses lime.ui.Window.resize() + move()
*  - Screen dimensions come from win.display.currentMode
*  - Window state (maximized/restored) is managed by OS
*
*  HTML5 Target (Browser):
*  ───────────────────────
*  - FULLSCREEN_TOGGLED uses Fullscreen API (requestFullscreen/exitFullscreen)
*  - Screen dimensions come from window.innerWidth/innerHeight
*  - May require user gesture (button click) to enter fullscreen
*  - Mobile browsers may not support true fullscreen
*
*  CONSUMER GUIDELINES:
*  ════════════════════
*
*  1. NEVER access platform-specific APIs in event handlers.
*     All platform logic is in DisplayConfig.
*
*  2. ALWAYS check payload fields for null before use.
*     Optional fields (screenWidth/Height) may be absent on some platforms.
*
*  3. USE DisplayConfig.getInstance() to query current state.
*     Events notify about CHANGES, not current state.
*
*  4. SUBSCRIBE in activate(), UNSUBSCRIBE in deactivate().
*     Follow Listener Reference Identity pattern (ARHITECTURE_PATTERNS.md §2).
*
* ═══════════════════════════════════════════════════════════════════════════
* EVENT TAXONOMY
* ═══════════════════════════════════════════════════════════════════════════
*
*  ┌─────────────────────────┬────────────────────────────────────────────┐
*  │ Category                │ Events                                     │
*  ├─────────────────────────┼────────────────────────────────────────────┤
*  │ SYSTEM & LIFECYCLE      │ ATOM_DELETED, ATOM_RESTORED,               │
*  │                         │ REDRAW_WIRES, ASSEMBLY_PORTS_CHANGED,      │
*  │                         │ VALUE_COMMITTED, DEVICE_WINDOW_CHANGED,    │
*  │                         │ OSCILLOSCOPE_SHAPE_CHANGED,                │
*  │                         │ OSCILLOSCOPE_FRAME_READY,                  │
*  │                         │ FFT_SPECTRUM_READY, PORT_REMOVED           │
*  │                         │                                            │
*  │ DISPLAY & WINDOW STATE  │ DISPLAY_MODE_CHANGED, SCENE_RESIZED,       │
*  │ (v1.4 NEW)              │ FULLSCREEN_TOGGLED                         │
*  │                         │                                            │
*  │ INTERACTION             │ PORT_DRAG_START, NODE_CLICKED,             │
*  │ (Mouse/Click)           │ NODE_RIGHT_CLICKED, WIRE_RIGHT_CLICKED,    │
*  │                         │ PORT_RIGHT_CLICKED, CANVAS_RIGHT_CLICKED   │
*  │                         │                                            │
*  │ EDITOR STATE            │ EDITOR_NODE_MOVED, NODE_DRAG_FINISHED,     │
*  │                         │ FORCE_UPDATE_NODE_POSITION,                │
*  │                         │ CLOSE_CONTEXT_MENU                         │
*  │                         │                                            │
*  │ NAVIGATION & COMMANDS   │ OPEN_ASSEMBLY_REQUEST,                     │
*  │                         │ REQUEST_NEW_ASSEMBLY_CONTEXT,              │
*  │                         │ REQUEST_CLOSE_CURRENT_CONTEXT,             │
*  │                         │ ATOM_PROPERTIES_REQUEST                    │
*  │                         │                                            │
*  │ CONTEXT MENU            │ CONTEXT_MENU_ACTION                        │
*  │                         │                                            │
*  │ CONTEXT MENU v2.0       │ MENU_ENTRY_ACTIVATED, MENU_CLOSED          │
*  └─────────────────────────┴────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* USAGE EXAMPLE
* ═══════════════════════════════════════════════════════════════════════════
*
*  // In Main.hx (subscriber):
*  Impulsys.subscribeToImpulse(EventType.DISPLAY_MODE_CHANGED, function(impulse) {
*      var mode = impulse.data.mode;
*      switch (mode) {
*          case DisplayMode.EDITOR:
*              _editorLayer.visible = true;
*              _devicePanel.visible = false;
*          case DisplayMode.DEVICE_PANEL:
*              _editorLayer.visible = false;
*              _devicePanel.visible = true;
*      }
*  });
*
*  // In DisplayConfig.hx (emitter):
*  Impulsys.quickEmit(EventType.DISPLAY_MODE_CHANGED, {
*      mode: currentMode
*  });
*
* ═══════════════════════════════════════════════════════════════════════════
* VERSION HISTORY
* ═══════════════════════════════════════════════════════════════════════════
*
*  v1.4 — Display & Window State Events (DisplayConfig Integration)
*  ──────────────────────────────────────────────────────────────────────
*  - ADDED: DISPLAY_MODE_CHANGED, SCENE_RESIZED, FULLSCREEN_TOGGLED
*  - ADDED: Cross-platform payload contract documentation
*  - ADDED: Event taxonomy table for quick reference
*
*  v1.3 — Port Removal Event
*  ─────────────────────────
*  - ADDED: PORT_REMOVED for handling external wire cleanup
*
*  v1.0 — Initial Implementation
*  ─────────────────────────────
*  - Base event types for system lifecycle, interaction, editor state
*
*/
abstract EventType(String) from String to String {

    public inline function new(s: String) this = s;

    // =====================================================================
    // SYSTEM & LIFECYCLE
    // =====================================================================

    /** Atom instance was deleted from assembly */
    public static var ATOM_DELETED(default, never) = new EventType("ATOM_DELETED");

    /** Atom instance was restored (created or undo) */
    public static var ATOM_RESTORED(default, never) = new EventType("ATOM_RESTORED");

    /** Request to redraw all wires (topology changed) */
    public static var REDRAW_WIRES(default, never) = new EventType("REDRAW_WIRES");

    /** Assembly ports changed (added/removed) */
    public static var ASSEMBLY_PORTS_CHANGED(default, never) = new EventType("ASSEMBLY_PORTS_CHANGED");

    /** User committed a value change (save trigger) */
    public static var VALUE_COMMITTED(default, never) = new EventType("VALUE_COMMITTED");

    /** Device window state changed (position/size/devices) */
    public static var DEVICE_WINDOW_CHANGED(default, never) = new EventType("DEVICE_WINDOW_CHANGED");

    /** Oscilloscope display shape changed (rect/square/circle) */
    public static var OSCILLOSCOPE_SHAPE_CHANGED(default, never) = new EventType("OSCILOSCOPE_SHAPE_CHANGED");

    /** Oscilloscope has a new frame ready for rendering */
    public static var OSCILLOSCOPE_FRAME_READY(default, never) = new EventType("OSCILOSCOPE_FRAME_READY");

    /** FFT spectrum data is ready for visualization */
    public static var FFT_SPECTRUM_READY(default, never) = new EventType("FFT_SPECTRUM_READY");

    // =====================================================================
    // v1.3: PORT REMOVAL NOTIFICATION
    // =====================================================================

    /**
    * Port was removed from assembly.
    *
    * Payload: { assemblyId: String, portName: String }
    *
    * Used by Main.hx to clean up external wires connected to the deleted port.
    * Prevents "ghost" wires that point to non-existent ports.
    */
    public static var PORT_REMOVED(default, never) = new EventType("PORT_REMOVED");

    // =====================================================================
    // v1.4: DISPLAY & WINDOW STATE (DisplayConfig Integration)
    // =====================================================================

    /**
    * Display mode changed (Editor ↔ DevicePanel).
    *
    * Payload: { mode: DisplayMode }
    *   - mode = DisplayMode.EDITOR | DisplayMode.DEVICE_PANEL
    *
    * Emitted by: DisplayConfig.toggleMode() or DisplayConfig.currentMode setter
    *
    * Consumers:
    *   - Main.hx: Toggle visibility of _editorLayer and _devicePanel
    *   - NodeEditor: Restore widgets to NodeViews when switching to Editor
    *   - DevicePanel: Clear devices when switching to Editor
    *
    * Cross-platform: IDENTICAL payload on C++ and HTML5.
    */
    public static var DISPLAY_MODE_CHANGED(default, never) = new EventType("DISPLAY_MODE_CHANGED");

    /**
    * Scene dimensions changed (stage resize or window resize).
    *
    * Payload: { width: Float, height: Float }
    *   - width/height = new scene dimensions in pixels
    *
    * Emitted by: DisplayConfig.sceneWidth/sceneHeight setter
    *
    * Consumers:
    *   - Main.hx: Reposition UI buttons, resize editor container
    *   - DevicePanel: Resize background and header
    *   - NodeEditor: Update viewport bounds
    *
    * Cross-platform: IDENTICAL payload on C++ and HTML5.
    *
    * Note: This event fires on EVERY pixel change during resize.
    *       Consumers should debounce if expensive operations are needed.
    */
    public static var SCENE_RESIZED(default, never) = new EventType("SCENE_RESIZED");

    /**
    * Fullscreen/windowed state toggled.
    *
    * Payload: {
    *   isFullscreen: Bool,
    *   ?screenWidth: Float,   // Optional: screen/display width
    *   ?screenHeight: Float   // Optional: screen/display height
    * }
    *
    * Emitted by: DisplayConfig.toggleMaximize() or DisplayConfig.isFullscreen setter
    *
    * Consumers:
    *   - Main.hx: Update window state, reposition UI
    *   - DevicePanel: Update maximize button icon ([□] ↔ [◱])
    *
    * Cross-platform differences:
    * ┌──────────┬─────────────────────────────────────────────────────────┐
    * │ Platform │ Implementation                                          │
    * ├──────────┼─────────────────────────────────────────────────────────┤
    * │ C++      │ Uses lime.ui.Window.resize() + move()                   │
    * │          │ screenWidth/Height = win.display.currentMode            │
    * │          │ Window state managed by OS (maximized/restored)         │
    * │          │                                                         │
    * │ HTML5    │ Uses Fullscreen API (requestFullscreen/exitFullscreen)  │
    * │          │ screenWidth/Height = window.innerWidth/innerHeight      │
    * │          │ May require user gesture (button click)                 │
    * │          │ Mobile browsers may not support true fullscreen         │
    * └──────────┴─────────────────────────────────────────────────────────┘
    *
    * IMPORTANT: screenWidth/Height are OPTIONAL fields.
    *            Always check for null before use.
    *            On some platforms (e.g., mobile HTML5), they may be absent.
    */
    public static var FULLSCREEN_TOGGLED(default, never) = new EventType("FULLSCREEN_TOGGLED");

    // =====================================================================
    // INTERACTION (Mouse/Click)
    // =====================================================================

    /** Port drag started (wire creation begin) */
    public static var PORT_DRAG_START(default, never) = new EventType("PORT_DRAG_START");

    /** Node clicked (selection) */
    public static var NODE_CLICKED(default, never) = new EventType("NODE_CLICKED");

    /** Node right-clicked (context menu) */
    public static var NODE_RIGHT_CLICKED(default, never) = new EventType("NODE_RIGHT_CLICKED");

    /** Wire right-clicked (context menu) */
    public static var WIRE_RIGHT_CLICKED(default, never) = new EventType("WIRE_RIGHT_CLICKED");

    /** Port right-clicked (context menu) */
    public static var PORT_RIGHT_CLICKED(default, never) = new EventType("PORT_RIGHT_CLICKED");

    /** Canvas right-clicked (context menu for adding atoms) */
    public static var CANVAS_RIGHT_CLICKED(default, never) = new EventType("CANVAS_RIGHT_CLICKED");

	// =====================================================================
	// EDITOR STATE
	// =====================================================================
	/** Node moved during drag (continuous updates) */
	public static var EDITOR_NODE_MOVED(default, never) = new EventType("EDITOR_NODE_MOVED");
	/** Node drag finished (position commit) */
	public static var NODE_DRAG_FINISHED(default, never) = new EventType("NODE_DRAG_FINISHED");
	/** Force update node position (programmatic move) */
	public static var FORCE_UPDATE_NODE_POSITION(default, never) = new EventType("FORCE_UPDATE_NODE_POSITION");
	/** Close context menu (click outside or ESC) */
	public static var CLOSE_CONTEXT_MENU(default, never) = new EventType("CLOSE_CONTEXT_MENU");
	/** 
	 * v2.0: Node visual representation mode changed (Light/Medium/Heavy).
	 * Payload: { mode: ui.NodeVisualMode }
	 */
	public static var NODE_VISUAL_MODE_CHANGED(default, never) = new EventType("NODE_VISUAL_MODE_CHANGED");

    // =====================================================================
    // NAVIGATION & COMMANDS
    // =====================================================================

    /** Request to open nested assembly (double-click) */
    public static var OPEN_ASSEMBLY_REQUEST(default, never) = new EventType("OPEN_ASSEMBLY_REQUEST");

    /** Request to create new assembly context */
    public static var REQUEST_NEW_ASSEMBLY_CONTEXT(default, never) = new EventType("REQUEST_NEW_ASSEMBLY_CONTEXT");

    /** Request to close current editor context */
    public static var REQUEST_CLOSE_CURRENT_CONTEXT(default, never) = new EventType("REQUEST_CLOSE_CURRENT_CONTEXT");

    /** Request to show atom properties window */
    public static var ATOM_PROPERTIES_REQUEST(default, never) = new EventType("ATOM_PROPERTIES_REQUEST");

    // =====================================================================
    // CONTEXT MENU
    // =====================================================================

    /** Context menu action triggered (item clicked) */
    public static var CONTEXT_MENU_ACTION(default, never) = new EventType("CONTEXT_MENU_ACTION");

    // =====================================================================
    // CONTEXT MENU v2.0
    // =====================================================================

    /** Menu entry activated (new context menu system) */
    public static var MENU_ENTRY_ACTIVATED(default, never) = new EventType("MENU_ENTRY_ACTIVATED");

    /** Menu closed (new context menu system) */
    public static var MENU_CLOSED(default, never) = new EventType("MENU_CLOSED");
	
    // =====================================================================
    // v1.5: COM PORT EVENTS (Added for ComPortAtom/Widget integration)
    // =====================================================================

    /**
     * ComPort connection status changed.
     * Payload: String (e.g., "Connected to COM3", "Disconnected", "Requesting USB permission...")
     */
    public static var COMPORT_STATUS(default, never) = new EventType("COMPORT_STATUS");

    /**
     * ComPort received new data chunk.
     * Payload: String (the received data)
     */
    public static var COMPORT_RX_DATA(default, never) = new EventType("COMPORT_RX_DATA");

    /**
     * ComPort encountered an error.
     * Payload: String (error message, e.g., "Android Rx Err:-1 (check cable/driver)")
     */
    public static var COMPORT_ERROR(default, never) = new EventType("COMPORT_ERROR");
}