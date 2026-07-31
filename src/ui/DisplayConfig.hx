package ui;
import openfl.Lib;
import lime.ui.Window;
import core.logic.Impulsys;
import core.logic.EventType;
#if html5
import js.Browser;
import js.html.CanvasElement;
#end
/**
* DISPLAY CONFIG v1.1 (Cross-Platform Fullscreen Support)
* Centralized control of OpenFL output object configuration.
*
* ═══════════════════════════════════════════════════════════════════════════
* RESPONSIBILITY
* ═══════════════════════════════════════════════════════════════════════════
*
* Manages ALL dynamic display parameters that change at runtime:
*   - Scene dimensions and fullscreen state
*   - Active display mode (Editor vs Device Panel)
*   - Button visibility and positioning per mode
*   - Window state persistence (maximize/restore)
*   - Cross-platform fullscreen (Browser Fullscreen API / OS Window)
*
* Separation of concerns:
*   - EditorTheme → STATIC visual constants (colors, thicknesses)
*   - DisplayConfig → DYNAMIC layout/runtime configuration
*
* ═══════════════════════════════════════════════════════════════════════════
* ARCHITECTURE
* ═══════════════════════════════════════════════════════════════════════════
*
*  ┌─────────────────────────────────────────────────────────────────────┐
*  │  DisplayConfig (Singleton)                                          │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  SCENE CONFIGURATION                                          │  │
*  │  │  • sceneWidth / sceneHeight (current)                         │  │
*  │  │  • defaultWidth / defaultHeight (initial)                     │  │
*  │  │  • isFullscreen:Bool                                          │  │
*  │  │  • savedWindowRect:{x,y,w,h} (for restore)                    │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  DISPLAY MODE                                                 │  │
*  │  │  • currentMode:DisplayMode (EDITOR / DEVICE_PANEL)            │  │
*  │  │  • isEditorMode():Bool                                        │  │
*  │  │  • isDeviceMode():Bool                                        │  │
*  │  │  • toggleMode()                                               │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  EDITOR LAYOUT                                                │  │
*  │  │  • editorButtons:EditorButtons                                │  │
*  │  │    - showBack, showDelete, showNew, showView,                 │  │
*  │  │      showSettings, showClose                                  │  │
*  │  │    - buttonSize:Float (40)                                    │  │
*  │  │    - buttonPadding:Float (5)                                  │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  DEVICE PANEL LAYOUT                                          │  │
*  │  │  • deviceButtons:DeviceButtons                                │  │
*  │  │    - showEditor, showClear, showMaximize, showClose           │  │
*  │  │    - headerHeight:Float (30)                                  │  │
*  │  │    - smallButtonSize:{w:28, h:26}                             │  │
*  │  │    - closeButtonSize:{w:40, h:40}                             │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  WINDOW STATE MANAGEMENT                                      │  │
*  │  │  • saveWindowState(win)                                       │  │
*  │  │  • restoreWindowState(win)                                    │  │
*  │  │  • toggleMaximize(win)                                        │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  │  ┌───────────────────────────────────────────────────────────────┐  │
*  │  │  CROSS-PLATFORM FULLSCREEN (v1.1)                             │  │
*  │  │  • toggleFullscreen(win) → HTML5 or Native                    │  │
*  │  │  • _onBrowserFullscreenChange() → Sync state on Esc           │  │
*  │  │  • _getCanvasElement() → Find OpenFL canvas in DOM            │  │
*  │  └───────────────────────────────────────────────────────────────┘  │
*  │                                                                     │
*  └─────────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* CROSS-PLATFORM FULLSCREEN ARCHITECTURE (v1.1)
* ═══════════════════════════════════════════════════════════════════════════
*
*  ┌─────────────────────────────────────────────────────────────────────┐
*  │  toggleFullscreen(win:Window)                                       │
*  │                                                                     │
*  │  #if html5                                                          │
*  │  ──────────                                                         │
*  │  1. Get canvas element from DOM                                     │
*  │     ├── document.getElementById("openfl-content")                   │
*  │     └── fallback: document.querySelector("canvas")                  │
*  │                                                                     │
*  │  2. If NOT fullscreen:                                              │
*  │     ├── canvas.requestFullscreen()                                  │
*  │     ├── fallback: mozRequestFullScreen / webkitRequestFullscreen    │
*  │     └── isFullscreen = true (optimistic)                            │
*  │                                                                     │
*  │  3. If IS fullscreen:                                               │
*  │     ├── document.exitFullscreen()                                   │
*  │     ├── fallback: mozCancelFullScreen / webkitExitFullscreen        │
*  │     └── isFullscreen = false (optimistic)                           │
*  │                                                                     │
*  │  4. Browser fires "fullscreenchange" event:                         │
*  │     └── _onBrowserFullscreenChange() → sync isFullscreen state      │
*  │                                                                     │
*  │  #else (Windows/Native)                                             │
*  │  ──────────────────────                                             │
*  │  1. If NOT fullscreen:                                              │
*  │     ├── saveWindowState(win) → save current rect                    │
*  │     ├── win.resize(display.currentMode.width, height)               │
*  │     ├── win.move(0, 0)                                              │
*  │     └── isFullscreen = true                                         │
*  │                                                                     │
*  │  2. If IS fullscreen:                                               │
*  │     ├── restoreWindowState(win) → restore saved rect                │
*  │     └── isFullscreen = false                                        │
*  │                                                                     │
*  └─────────────────────────────────────────────────────────────────────┘
*
*  ┌─────────────────────────────────────────────────────────────────────┐
*  │  HTML5 Fullscreen Flow:                                             │
*  │                                                                     │
*  │  User clicks [□] button                                             │
*  │       │                                                             │
*  │       ▼                                                             │
*  │  Main.onToggleMaximize callback                                     │
*  │       │                                                             │
*  │       ▼                                                             │
*  │  DisplayConfig.toggleFullscreen(win)                                │
*  │       │                                                             │
*  │       ├── #if html5                                                 │
*  │       │     └── canvas.requestFullscreen()                          │
*  │       │              │                                              │
*  │       │              ▼                                              │
*  │       │         Browser enters fullscreen                           │
*  │       │              │                                              │
*  │       │              ▼                                              │
*  │       │         "fullscreenchange" event fires                      │
*  │       │              │                                              │
*  │       │              ▼                                              │
*  │       │         _onBrowserFullscreenChange()                        │
*  │       │              │                                              │
*  │       │              └── isFullscreen = true                        │
*  │       │                       │                                     │
*  │       │                       ▼                                     │
*  │       │                  setter emits FULLSCREEN_TOGGLED            │
*  │       │                                                             │
*  │       └── #else (Native)                                            │
*  │             └── saveWindowState() + win.resize()                    │
*  │                  └── isFullscreen = true                            │
*  │                       └── setter emits FULLSCREEN_TOGGLED           │
*  │                                                                     │
*  │  Impulsys.quickEmit(FULLSCREEN_TOGGLED, {isFullscreen})             │
*  │       │                                                             │
*  │       ├── Main._onFullscreenToggled()                               │
*  │       │     └── _devicePanel.setMaximizedState(isFullscreen)        │
*  │       │          └── Icon changes [□] → [◱]                         │
*  │       │                                                             │
*  │       └── (другие подписчики, если появятся)                        │
*  └─────────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* USAGE EXAMPLE
* ═══════════════════════════════════════════════════════════════════════════
*
*  // In Main.hx:
*  var config = DisplayConfig.getInstance();
*
*  // Query mode
*  if (config.isDeviceMode()) {
*      _editorLayer.visible = false;
*      _devicePanel.visible = true;
*  }
*
*  // Toggle mode
*  config.toggleMode();  // emits DISPLAY_MODE_CHANGED via Impulsys
*
*  // Query button visibility
*  if (config.editorButtons.showBack) {
*      _btnBack.visible = true;
*  }
*
*  // Fullscreen (cross-platform)
*  config.toggleFullscreen(win);  // HTML5 or Native automatically
*
*/
class DisplayConfig
{
// =====================================================================
// SINGLETON
// =====================================================================
private static var _instance:DisplayConfig;
/**
* Get singleton instance.
* @return DisplayConfig instance
*/
public static function getInstance():DisplayConfig
{
if (_instance == null) _instance = new DisplayConfig();
return _instance;
}
/**
* Reset singleton (for testing or hard reset).
*/
public static function reset():Void
{
if (_instance != null) _instance = null;
}
// =====================================================================
// SCENE CONFIGURATION
// =====================================================================
/** Current scene width (updated on resize) */
public var sceneWidth(default, set):Float;
private function set_sceneWidth(v:Float):Float
{
if (sceneWidth != v)
{
sceneWidth = v;
_notifySceneChanged();
}
return v;
}
/** Current scene height (updated on resize) */
public var sceneHeight(default, set):Float;
private function set_sceneHeight(v:Float):Float
{
if (sceneHeight != v)
{
sceneHeight = v;
_notifySceneChanged();
}
return v;
}
/** Default scene width at startup */
public var defaultWidth(default, null):Float;
/** Default scene height at startup */
public var defaultHeight(default, null):Float;
/** Is the OS window currently in fullscreen mode? */
public var isFullscreen(default, set):Bool;
private function set_isFullscreen(v:Bool):Bool
{
if (isFullscreen != v)
{
isFullscreen = v;
_notifyFullscreenChanged();
}
return v;
}
/** Saved window rectangle for restore after fullscreen */
public var savedWindowRect:{x:Float, y:Float, w:Float, h:Float};
// =====================================================================
// DISPLAY MODE
// =====================================================================
/** Current active display mode */
public var currentMode(default, set):DisplayMode;
private function set_currentMode(v:DisplayMode):DisplayMode
{
if (currentMode != v)
{
currentMode = v;
_notifyModeChanged();
}
return v;
}
/** Convenience: is Editor mode active? */
public function isEditorMode():Bool return currentMode == DisplayMode.EDITOR;
/** Convenience: is Device Panel mode active? */
public function isDeviceMode():Bool return currentMode == DisplayMode.DEVICE_PANEL;
/** Toggle between Editor and Device Panel */
public function toggleMode():Void
{
currentMode = (currentMode == DisplayMode.EDITOR)
? DisplayMode.DEVICE_PANEL
: DisplayMode.EDITOR;
}
// =====================================================================
// EDITOR LAYOUT
// =====================================================================
/** Editor mode button visibility flags */
public var editorButtons:EditorButtons;
// =====================================================================
// DEVICE PANEL LAYOUT
// =====================================================================
/** Device Panel mode button visibility flags */
public var deviceButtons:DeviceButtons;
// =====================================================================
// LAYOUT CONSTANTS (read-only)
// =====================================================================
/** Header bar height (Editor & Device) */
public var headerHeight(default, null):Float;
/** Small button width (E, C, □) */
public var smallButtonWidth(default, null):Float;
/** Small button height (E, C, □) */
public var smallButtonHeight(default, null):Float;
/** Close button size (X) — square */
public var closeButtonSize(default, null):Float;
/** Padding between buttons */
public var buttonPadding(default, null):Float;
// =====================================================================
// POSITION CALCULATORS (right-to-left layout)
// =====================================================================
/**
* Calculate X position for Nth button from right edge.
*
* Layout: [content] ... [btn3] [btn2] [btn1] [X]
*                                          ^-- rightEdge - padding
*
* @param rightEdge     Right edge coordinate (stageWidth)
* @param buttonIndex   0-based index from right (0 = rightmost before X)
* @param isSmall       true = 28×26, false = 40×40
* @return X coordinate for button
*/
public function calcButtonX(rightEdge:Float, buttonIndex:Int, isSmall:Bool = true):Float
{
var x = rightEdge - buttonPadding;
// Account for close button (always 40×40)
x -= closeButtonSize;
for (i in 0...buttonIndex)
{
x -= buttonPadding;
x -= isSmall ? smallButtonWidth : closeButtonSize;
}
x -= isSmall ? smallButtonWidth : closeButtonSize;
return x;
}
/**
* Calculate X for close button (always rightmost).
*/
public function calcCloseButtonX(rightEdge:Float):Float
{
return rightEdge - buttonPadding - closeButtonSize;
}
// =====================================================================
// WINDOW STATE MANAGEMENT
// =====================================================================
/**
* Save current window state before maximizing.
*/
public function saveWindowState(win:Window):Void
{
if (win == null) return;
savedWindowRect = {
x: win.x,
y: win.y,
w: win.width,
h: win.height
};
}
/**
* Restore window to saved state.
*/
public function restoreWindowState(win:Window):Void
{
if (win == null || savedWindowRect == null) return;
win.resize(Std.int(savedWindowRect.w), Std.int(savedWindowRect.h));
win.move(Std.int(savedWindowRect.x), Std.int(savedWindowRect.y));
isFullscreen = false;
}
/**
* Toggle maximize/restore (Native only).
* 
* @deprecated Use toggleFullscreen() instead for cross-platform support.
*/
public function toggleMaximize(win:Window):Void
{
if (win == null) return;
if (isFullscreen)
{
restoreWindowState(win);
}
else
{
saveWindowState(win);
var display = win.display;
if (display != null && display.currentMode != null)
{
win.resize(display.currentMode.width, display.currentMode.height);
win.move(0, 0);
}
isFullscreen = true;
}
}
// =====================================================================
// CROSS-PLATFORM FULLSCREEN (v1.1)
// =====================================================================
/**
* Toggle fullscreen mode (cross-platform).
* 
* HTML5: Uses Browser Fullscreen API on canvas element
* Native: Uses OS window resize/move via lime.ui.Window
* 
* @param win The Lime window instance (required for Native, optional for HTML5)
*/
public function toggleFullscreen(win:Window):Void
{
#if html5
// HTML5 TARGET: Use Browser Fullscreen API
var doc = Browser.document;
var canvas = _getCanvasElement();

if (canvas == null)
{
trace("DisplayConfig: Cannot find OpenFL canvas for fullscreen");
return;
}

if (!isFullscreen)
{
// ENTER FULLSCREEN
// Requires user gesture (click event) — we have it from button click
if (canvas.requestFullscreen != null)
{
canvas.requestFullscreen();
}
else if (untyped canvas.mozRequestFullScreen != null)
{
untyped canvas.mozRequestFullScreen();
}
else if (untyped canvas.webkitRequestFullscreen != null)
{
untyped canvas.webkitRequestFullscreen();
}
else if (untyped canvas.msRequestFullscreen != null)
{
untyped canvas.msRequestFullscreen();
}

// Optimistic update (will be confirmed by fullscreenchange event)
isFullscreen = true;
trace("DisplayConfig: Browser fullscreen requested");
}
else
{
// EXIT FULLSCREEN
if (doc.exitFullscreen != null)
{
doc.exitFullscreen();
}
else if (untyped doc.mozCancelFullScreen != null)
{
untyped doc.mozCancelFullScreen();
}
else if (untyped doc.webkitExitFullscreen != null)
{
untyped doc.webkitExitFullscreen();
}
else if (untyped doc.msExitFullscreen != null)
{
untyped doc.msExitFullscreen();
}

// Optimistic update
isFullscreen = false;
trace("DisplayConfig: Browser fullscreen exit requested");
}
#else
// NATIVE TARGET (Windows/Linux): Use OS Window API
if (win == null) return;

if (isFullscreen)
{
// RESTORE: Return to saved windowed state
restoreWindowState(win);
trace("DisplayConfig: Window restored to " + Std.int(savedWindowRect.w) + "x" + Std.int(savedWindowRect.h));
}
else
{
// MAXIMIZE: Save current state and go fullscreen
saveWindowState(win);
var display = win.display;
if (display != null && display.currentMode != null)
{
win.resize(display.currentMode.width, display.currentMode.height);
win.move(0, 0);
isFullscreen = true;
trace("DisplayConfig: Window maximized to " + display.currentMode.width + "x" + display.currentMode.height);
}
else
{
// Fallback: use stage dimensions
win.resize(Std.int(Lib.current.stage.stageWidth), Std.int(Lib.current.stage.stageHeight));
win.move(0, 0);
isFullscreen = true;
trace("DisplayConfig: Window maximized to stage size");
}
}
#end
}

#if html5
/**
* Get the OpenFL canvas element from DOM.
* 
* Tries multiple selectors:
* 1. document.getElementById("openfl-content")
* 2. document.querySelector("canvas")
* 
* @return CanvasElement or null if not found
*/
private function _getCanvasElement():CanvasElement
{
var doc = Browser.document;
var canvas:CanvasElement = cast doc.getElementById("openfl-content");
if (canvas == null)
{
canvas = cast doc.querySelector("canvas");
}
return canvas;
}

/**
* Handle browser fullscreenchange event.
* 
* Called when:
* - User presses Esc to exit fullscreen
* - Browser enters/exits fullscreen programmatically
* 
* Syncs isFullscreen state with actual browser state.
*/
private function _onBrowserFullscreenChange(_):Void
{
var doc = Browser.document;
var browserFullscreen = (doc.fullscreenElement != null);

// Sync state if changed externally (e.g., user pressed Esc)
if (isFullscreen != browserFullscreen)
{
isFullscreen = browserFullscreen;
// Setter automatically emits FULLSCREEN_TOGGLED via Impulsys
trace("DisplayConfig: Browser fullscreen state synced: " + isFullscreen);
}
}
#end
/**
* Force re-enter fullscreen mode.
* Used specifically after native browser dialogs (File Picker, Serial Port)
* which automatically exit fullscreen for security reasons.
* Since the dialog closure is a User Gesture, the browser will allow this.
* 
* @param win The Lime window instance (unused in HTML5, kept for signature consistency)
*/
public function reenterFullscreen(win:Window):Void
{
    #if html5
    var canvas = _getCanvasElement();
    if (canvas != null)
    {
        // Force request fullscreen regardless of current isFullscreen state
        if (canvas.requestFullscreen != null) canvas.requestFullscreen();
        else if (untyped canvas.mozRequestFullScreen != null) untyped canvas.mozRequestFullScreen();
        else if (untyped canvas.webkitRequestFullscreen != null) untyped canvas.webkitRequestFullscreen();
        else if (untyped canvas.msRequestFullscreen != null) untyped canvas.msRequestFullscreen();
        
        // Optimistically update state (will be confirmed by fullscreenchange event)
        isFullscreen = true;
    }
    #else
    // Native targets (Windows/Linux) do NOT exit fullscreen for file/com port dialogs.
    // So we only need to handle this for HTML5.
    #end
}
// =====================================================================
// CONSTRUCTOR
// =====================================================================
private function new()
{
// Initialize defaults
sceneWidth = 800;
sceneHeight = 600;
defaultWidth = 800;
defaultHeight = 600;
isFullscreen = false;
currentMode = DisplayMode.EDITOR;

// Editor buttons defaults
editorButtons = new EditorButtons();
deviceButtons = new DeviceButtons();

// Layout constants (from existing code)
headerHeight = 30;
smallButtonWidth = 28;
smallButtonHeight = 26;
closeButtonSize = 40;
buttonPadding = 5;

#if html5
// Listen for browser fullscreen changes (e.g., user pressed Esc)
Browser.document.addEventListener("fullscreenchange", _onBrowserFullscreenChange);
#end
}
// =====================================================================
// PRIVATE NOTIFIERS (via Impulsys)
// =====================================================================
private function _notifyModeChanged():Void
{
Impulsys.quickEmit(EventType.DISPLAY_MODE_CHANGED, {
mode: currentMode
});
}
private function _notifySceneChanged():Void
{
Impulsys.quickEmit(EventType.SCENE_RESIZED, {
width: sceneWidth,
height: sceneHeight
});
}
private function _notifyFullscreenChanged():Void
{
Impulsys.quickEmit(EventType.FULLSCREEN_TOGGLED, {
isFullscreen: isFullscreen
});
}
}
// =========================================================================
// EDITOR BUTTONS CONFIG
// =========================================================================
/**
* Visibility flags for Editor mode buttons.
*
* Layout (right-to-left):
* ┌─────────────────────────────────────────────────────────────────┐
* │  [Title]                                        [?] [R] [N] [V] │
* │                                              ↑   ↑   ↑   ↑   ↑  │
* │                                           Sett Rst New View [E] │
* └─────────────────────────────────────────────────────────────────┘
*
* Note: [E] (Editor) and [X] (Close) are managed by DevicePanel,
* not Editor. This config controls the TOP-RIGHT button row.
*/
class EditorButtons
{
    // Явный конструктор для исправления ошибки компиляции
    public function new() {}

    /** [<] Back button — visible when nested (stack > 1) */
    public var showBack:Bool = true;
    /** [E] Erase assembly button — visible when nested */
    public var showDelete:Bool = true;
    /** [N] New Assembly button — controlled by SettingsPanel.allowAssembly */
    public var showNew:Bool = true;
    /** [V] View Toggle button (Editor ↔ Device) */
    public var showView:Bool = true;
    /** [?] Settings button */
    public var showSettings:Bool = true;
    /** [X] Close button — always visible */
    public var showClose:Bool = true;
    /** Button size (square) */
    public var buttonSize:Float = 40;
    /** Padding between buttons */
    public var buttonPadding:Float = 5;
}

// =========================================================================
// DEVICE BUTTONS CONFIG
// =========================================================================
/**
* Visibility flags for Device Panel mode buttons.
*
* Layout (right-to-left in header):
* ┌─────────────────────────────────────────────────────────────────┐
* │  [Device Panel: AssemblyName]          [E] [C] [□]        [X]   │
* │                                        ↑   ↑   ↑          ↑     │
* │                                     Edit Clr Max/Rest    Close  │
* │                                    (28×26)(28×26)(28×26) (40×40)│
* └─────────────────────────────────────────────────────────────────┘
*/
class DeviceButtons
{
    // Явный конструктор для исправления ошибки компиляции
    public function new() {}

    /** [E] Return to Editor button */
    public var showEditor:Bool = true;
    /** [C] Clear all devices button */
    public var showClear:Bool = true;
    /** [□]/[◱] Maximize/Restore button */
    public var showMaximize:Bool = true;
    /** [X] Close application button */
    public var showClose:Bool = true;
    /** Header bar height */
    public var headerHeight:Float = 30;
    /** Small button dimensions (E, C, □) */
    public var smallButtonWidth:Float = 28;
    public var smallButtonHeight:Float = 26;
    /** Close button size (X) — matches EditorButtons.buttonSize */
    public var closeButtonSize:Float = 40;
}