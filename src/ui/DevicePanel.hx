package ui;

import editor.EditorTheme;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;
import ui.ButtonComponent;

#if windows
@:headerCode('
#ifdef _WIN32
extern "C" {
    bool _dp_nativeStartDrag();
    void _dp_registerDragTick(void* inTick);
}
#endif
')
@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
// wglGetCurrentDC is in opengl32.dll — declare manually since WIN32_LEAN_AND_MEAN excludes GL headers
extern "C" __declspec(dllimport) HDC __stdcall wglGetCurrentDC(void);
#pragma comment(lib, "opengl32.lib")
// =========================================================================
// v3.7: TICK INJECTION DURING NATIVE DRAG
// =========================================================================
typedef void (*DragTickFn)();
static DragTickFn   _dp_dragTickFn   = NULL;
static const UINT_PTR DP_DRAG_TIMER_ID = 0xD4A6;
static const UINT     DP_DRAG_TIMER_MS = 15; // ~60 Hz
// Called directly by DispatchMessage INSIDE the modal drag loop,
// on the same thread as SendMessage - reentrancy is safe.
static VOID CALLBACK _dp_DragTimerProc(HWND hWnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime)
{
    if (_dp_dragTickFn != NULL)
    {
        _dp_dragTickFn();
    }
}
// Find the main Haxe/OpenFL window by process ID.
// NOTE: the API is GetWindowThreadProcessId — it returns the thread id AND
// optionally writes the process id through the second parameter. There is
// no "GetWindowThreadId" in the Windows SDK (an old paste carried that
// phantom name, which breaks MSVC with C3861).
static HWND _dp_findMainWindow() {
    DWORD pid = GetCurrentProcessId();
    HWND best = NULL;
    HWND hWnd = GetTopWindow(NULL);
    while (hWnd != NULL) {
        DWORD wpid = 0;
        GetWindowThreadProcessId(hWnd, &wpid);
        if (wpid == pid) {
            LONG style = GetWindowLong(hWnd, GWL_STYLE);
            if ((style & WS_VISIBLE)) {
                HWND owner = GetWindow(hWnd, GW_OWNER);
                if (owner == NULL) {
                    char cls[256] = {0};
                    GetClassNameA(hWnd, cls, 255);
                    if (strstr(cls, "SDL") || strstr(cls, "HXCPP") || strstr(cls, "OpenFL")) {
                        return hWnd;
                    }
                    if (best == NULL) best = hWnd;
                }
            }
        }
        hWnd = GetNextWindow(hWnd, GW_HWNDNEXT);
    }
    return best;
}
// =========================================================================
// EXTERN "C" API — called from Haxe via untyped __cpp__()
// =========================================================================
extern "C" {
// Start native drag. Blocks until mouse-up.
// Returns true if drag was performed, false if failed.
bool _dp_nativeStartDrag() {
    HWND hWnd = _dp_findMainWindow();
    if (hWnd == NULL) return false;
    // Set timer with callback - fires from nested message loop
    SetTimer(hWnd, DP_DRAG_TIMER_ID, DP_DRAG_TIMER_MS, _dp_DragTimerProc);
    ReleaseCapture();
    SendMessage(hWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0); // blocks until mouse-up
    KillTimer(hWnd, DP_DRAG_TIMER_ID);
    return true;
}
// Register Haxe tick callback.
// inTick is a function pointer passed from Haxe via cpp.Function.fromStaticFunction.
void _dp_registerDragTick(void* inTick) {
    _dp_dragTickFn = (DragTickFn)inTick;
}
} // extern "C"
#endif
')
#end

/**
* DEVICE PANEL v3.12 (Vector Icons + Restore-Before-Drag + Native Drag + Force Render + Z-System)
* Full-size device display panel inside the Main Window.
*
* Architecture: "ATOM IS DATABANK & COMPUTE CORE"
*
* DevicePanel — built-in device dashboard inside the main window.
* An alternative to the separate DeviceWindow.
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   SCHEMATIC                         DEVICE PANEL                        │
* │                                                                         │
* │   [Editor Hidden]                   ┌────────────────────────────┐      │
* │                                     │       DevicePanel          │      │
* │                                     │   ┌────────────────────┐   │      │
* │                                     │   │   DeviceCard       │   │      │
* │                                     │   │ ┌────────────────┐ │   │      │
* │                                     │   │ │   DeviceView   │   │      │
* │                                     │   │ │   (Widget)     │   │      │
* │                                     │   │ └────────────────┘ │   │      │
* │                                     │   └────────────────────┘   │      │
* │                                     │                            │      │
* │                                     │ [E][C][□]          [X]     │      │
* │                                     │  ↑  ↑  ↑           ↑       │      │
* │                                     │ Ed Cl Max/         Close   │      │
* │                                     │ it ar Restore      (40x40) │      │
* │                                     │    (28x26)                 │      │
* │                                     └────────────────────────────┘      │
* │                                              │                          │
* │                                              │                          │
* │                                              ▼                          │
* │                               Main Window Color - DEVICE_CANVAS_BG_COLOR│
* └─────────────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* VERSION HISTORY
* ═══════════════════════════════════════════════════════════════════════════
*
* v3.12 Changes:
* - ADDED: the Z-ORDER SYSTEM (Task 158/159, pilot design). Every card on
*   the panel carries a 1-based zOrder slot; the _deviceCards array order
*   IS the z numbering (index i = zOrder i+1). API:
*     · setCardZOrder(card, z) — INSERT semantics: z>=1 pulls the card to
*       slot z, widgets below keep their slots, the tail is renumbered
*       upward one-by-one (the pilot's exact rule); z<=0 = "surface" = the
*       contact does not manage depth (auto order stays);
*     · bringCardToFront(card) — the click-to-front route for framed cards
*       (DeviceCard asks the owner first; legacy owners fall back to
*       addChild);
*     · reapplyZOrder() — renumbers 1..N and mirrors the order into the
*       DisplayList (cards sit right above the panel header).
*   Consumers: PictureWidget [zOrder] contact (v1.2 bare canvas); future
*   atoms get the same channel for free.
*
* v3.11 Changes:
* - REMOVED: manual restore-under-cursor block (v3.10) — with real
*   SW_MAXIMIZE (WindowController v1.5) DefWindowProc performs the restore
*   dance natively during caption drag of a zoomed window.
*
* v3.10 Changes:
* - IMPROVED: restore-before-drag now REPOSITIONS the restored window under
*   the cursor (Windows 10 caption behavior) — the cursor keeps holding the
*   header at the same relative grab point instead of being stranded near
*   the top edge of the screen.
*
* v3.9 Changes:
* - REPLACED: Text glyph maximize icon "□"/"◱" → vector icons (WindowGlyphs).
*   "◱" (U+25F1) is missing from Arial and renders as tofu on C++ targets —
*   Lime/FreeType has no font fallback chain.
* - FIXED: createHeaderButton() applied defaultTextFormat AFTER setting
*   text (Flash semantics: the format does not restyle existing text).
* - ADDED: _maximizeIcon sprite field (redrawn by setMaximizedState).
* - ADDED: onHeaderMouseDown() restores the window FIRST when dragging
*   while fullscreen (standard OS behavior; icon syncs via FULLSCREEN_TOGGLED).
*
* v3.8 Changes:
* - ADDED: Maximize/Restore button [□]/[◱] in header (28x26, same style as [E]/[C])
* - ADDED: Double-click on header to toggle maximize/restore
* - ADDED: onToggleMaximize callback for Main.hx to handle OS window resize
* - ADDED: setMaximizedState(isMaximized) for Main.hx to update button icon
* - ADDED: _maximizeBtn and _maximizeBtnLabel fields
* - ADDED: onHeaderDoubleClick() handler
* - UPDATED: setSize() repositions maximize button on resize
* - UPDATED: dispose() cleans up maximize button
*
* v3.7.2 Changes:
* - ADDED: Force render via stage.__renderDirty + stage.__clearDirty flags
* - ADDED: Direct win.onRender.dispatch(ctx) to trigger GL back buffer draw
* - ADDED: SwapBuffers via wglGetCurrentDC() for correct OpenGL context
* - FIXED: UI animations now work during native drag (VU meters, LEDs, etc.)
*
* v3.7.1 Changes:
* - ADDED: Tick injection during native Windows drag via SetTimer
* - ADDED: _onDragTick() called ~60 times/second during drag modal loop
* - ADDED: app.onUpdate.dispatch(15) to run Lime logic cycle
* - FIXED: Window content no longer freezes during drag
*
* v3.7 Changes:
* - ADDED: Native Windows drag via SendMessage(WM_NCLBUTTONDOWN, HTCAPTION)
* - ADDED: C++ bridge functions _dp_nativeStartDrag() and _dp_registerDragTick()
* - ADDED: @:headerCode and @:cppFileCode for Win32 API integration
* - FIXED: Perfect 1:1 cursor tracking with zero Haxe frame lag
* - ADDED: Fallback to Haxe-side drag on non-Windows platforms
*
* v3.6 Changes:
* - ADDED: Header drag functionality for moving the main application window
* - ADDED: Absolute position model to prevent flicker (delta from START)
* - ADDED: onWindowDragStart and onWindowDrag callbacks for Main.hx
* - FIXED: Button click detection to prevent unwanted drag initiation
*
* v3.5 Changes:
* - ADDED: Editor-style close button (ButtonComponent 40x40) in top-right
* - ADDED: Button triggers application close with save confirmation
* - SHIFTED: [E] and [C] buttons moved left to avoid overlap with [X]
* - ADDED: Proper resize handling for close button position
* - ADDED: Proper cleanup in dispose() method
*
* v3.4 Changes:
* - FIXED: Header buttons [E], [C] now stop MOUSE_DOWN propagation
* - FIXED: Prevents buttons from interfering with header drag
*
* v3.3 Changes:
* - ADDED: Context menu for adding devices via right-click
* - ADDED: Device list from onGetAssemblyList callback
* - ADDED: Auto-positioning with findFreePosition()
*
* v3.2 Changes:
* - ADDED: DEVICE_WINDOW_CHANGED event emission on add/remove
* - ADDED: State persistence support via Main.hx cache sync
*
* v3.1 Changes:
* - ADDED: clearDevices() method for bulk removal
* - FIXED: Event emission control to prevent cache wipe during mode switch
*
* v3.0 Changes:
* - Initial implementation of DevicePanel as Main Window embedded panel
* - Alternative to separate DeviceWindow for better UX
*
* ═══════════════════════════════════════════════════════════════════════════
* USAGE EXAMPLE (Main.hx)
* ═══════════════════════════════════════════════════════════════════════════
*
* // In Main.hx:
* _devicePanel = new DevicePanel();
* _devicePanel.visible = false;
* addChild(_devicePanel);
*
* _devicePanel.onShowEditor = function() {
*     if (DisplayConfig.getInstance().isDeviceMode()) onToggleView();
* };
*
* _devicePanel.onGetAssemblyList = getAllDevicesRecursive;
*
* _devicePanel.onCloseApp = function() {
*     onCloseClicked();
* };
*
* // v3.9: Maximize/Restore callback — delegate to DisplayConfig
* _devicePanel.onToggleMaximize = function() {
*     var win = Lib.current.stage.window;
*     DisplayConfig.getInstance().toggleFullscreen(win);
* };
*
* @author ALTAURI Team
* @version 3.11
* @since 3.0
*/
class DevicePanel extends Sprite
{
    // =========================================================================
    // CALLBACKS
    // =========================================================================

    /**
    * Callback to request switching back to Editor Mode.
    * Called when [E] button is pressed.
    *
    * Usage: Main.hx assigns onToggleView() to switch from Device Panel to Editor.
    */
    public var onShowEditor:Void -> Void;

    /**
    * Callback to get the list of available devices.
    * Used to populate the context menu when user right-clicks.
    *
    * Returns: Array of {id, name, atom} objects representing available atoms.
    *
    * Usage: Main.hx assigns getAllDevicesRecursive() to provide device list.
    */
    public var onGetAssemblyList:Void -> Array< {id:String, name:String, atom:Atom}>;

    /**
    * Callback for closing the application.
    * Called when [X] button is pressed.
    *
    * Usage: Main.hx assigns onCloseClicked() to show save confirmation dialog.
    */
    public var onCloseApp:Void -> Void;

    /**
    * v3.6: Called when drag starts.
    * Main.hx must capture current window position for absolute delta calculation.
    *
    * Usage: Main.hx stores win.x and win.y in _dragWindowStartX/Y.
    */
    public var onWindowDragStart:Void -> Void;

    /**
    * v3.6: Called during drag with DELTA from START position (not previous frame).
    *
    * @param dx Delta X from drag start (stage coordinates)
    * @param dy Delta Y from drag start (stage coordinates)
    *
    * Usage: Main.hx computes win.x = startX + dx, win.y = startY + dy
    *
    * Why absolute delta: Prevents accumulated rounding errors that cause flicker.
    */
    public var onWindowDrag:Float -> Float -> Void;

    /**
    * v3.8: Callback for toggling maximize/restore of the main OS window.
    *
    * Triggered by:
    *   - Click on [□]/restore button in header
    *   - Double-click on header background
    *   - v3.9: Drag start while fullscreen (restore-before-drag)
    *
    * Main.hx implementation:
    *   - Delegates to DisplayConfig.toggleFullscreen(win) (cross-platform)
    *
    * Why callback?
    *   DevicePanel is a Sprite inside Main Window — it cannot resize the OS
    *   window directly. Only Main.hx has access to lime.ui.Window.
    */
    public var onToggleMaximize:Void -> Void;

    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================

    /** Current assembly context (set via setContext()) */
    private var _assembly:Assembly;

    /** Array of all DeviceCard instances currently displayed */
    private var _deviceCards:Array<DeviceCard>;

    /** Header bar sprite (contains title and buttons) */
    private var _header:Sprite;

    /** Title text field showing "Device Panel: [assembly name]" */
    private var _titleLabel:TextField;

    /** Context menu sprite (shown on right-click) */
    private var _contextMenu:Sprite;

    /** Flag indicating if context menu is currently visible */
    private var _menuVisible:Bool = false;

    /** Background sprite (drawn with DEVICE_CANVAS_BG_COLOR) */
    private var _bg:Sprite;

    /** Reference to EditorTheme singleton for color constants */
    private var _theme:EditorTheme;

    // =========================================================================
    // v3.5: EDITOR-STYLE CLOSE BUTTON
    // =========================================================================

    /**
    * Large close button (40x40) in the top-right corner.
    * Same style and position as Main.hx _btnClose.
    * Triggers application close with save confirmation via onCloseApp callback.
    *
    * Position: x = stageWidth - 45, y = 5
    * Size: 40x40 pixels (ButtonComponent standard)
    */
    private var _btnClose:ButtonComponent;

    // =========================================================================
    // v3.8: MAXIMIZE/RESTORE BUTTON
    // =========================================================================

    /**
    * Maximize/Restore button sprite (28x26, same style as [E] and [C]).
    * v3.9: Icon is a VECTOR drawing (WindowGlyphs), not a text glyph:
    *   windowed  → single outlined square (maximize)
    *   fullscreen→ two stacked squares (restore)
    *
    * Triggers onToggleMaximize callback when clicked.
    */
    private var _maximizeBtn:Sprite;

    /**
    * TextField inside _maximizeBtn.
    * v3.9: Kept for API compatibility, but no longer used for the icon —
    * the icon is drawn into _maximizeIcon instead.
    */
    private var _maximizeBtnLabel:TextField;

    /**
    * v3.9: Icon sprite inside _maximizeBtn (font-independent vector icon).
    * Redrawn by setMaximizedState() via WindowGlyphs painter:
    *   windowed  → single square (maximize)
    *   fullscreen→ stacked squares (restore)
    */
    private var _maximizeIcon:Sprite;

    // =========================================================================
    // v3.6: DRAG STATE (Absolute Position Model)
    // =========================================================================

    /**
    * Drag state for header movement (Haxe-side fallback).
    *
    * Uses absolute position model to prevent flicker:
    * - _mouseStartX/Y: Mouse position at drag start (stage coords)
    * - _dragging: Is drag active?
    *
    * The window's initial position is stored in Main.hx via onWindowDragStart.
    * On each mouse move, we compute: windowPos = startPos + (currentMouse - startMouse)
    * This avoids accumulated rounding errors that cause visual jitter.
    *
    * Note: On Windows, native drag is used instead (see _nativeStartDrag).
    * This fallback is only used on non-Windows platforms or if native drag fails.
    */
    private var _dragging:Bool = false;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;

    // =========================================================================
    // v3.7: NATIVE DRAG STATE
    // =========================================================================

    /**
    * Flag indicating whether drag tick callback has been registered.
    * Ensures registration happens only once per application lifetime.
    *
    * Static because the C++ callback is global (not per-instance).
    */
    private static var _dragTickRegistered:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
    * Create a new DevicePanel instance.
    *
    * Initializes:
    * - Empty device cards array
    * - EditorTheme reference
    * - Native drag tick registration (Windows only)
    * - ADDED_TO_STAGE listener for deferred UI setup
    */
    public function new()
    {
        super();
        _deviceCards = new Array();
        _theme = EditorTheme.getInstance();

        #if windows
        _ensureDragTickRegistered();
        #end

        addEventListener(Event.ADDED_TO_STAGE, onAdded);
    }

    /**
    * Called when panel is added to stage.
    * Removes listener and calls setupUI() to build visual elements.
    */
    private function onAdded(e:Event):Void
    {
        removeEventListener(Event.ADDED_TO_STAGE, onAdded);
        setupUI();
    }

    // =========================================================================
    // v3.7: DRAG TICK REGISTRATION
    // =========================================================================

    /**
    * Register the drag tick callback with C++ layer.
    * Called once per application lifetime (static flag prevents duplicates).
    *
    * Process:
    * 1. Check if already registered (_dragTickRegistered flag)
    * 2. Convert Haxe function to C++ function pointer via cpp.Function.fromStaticFunction
    * 3. Pass pointer to C++ via _registerDragTickBridge (untyped __cpp__)
    * 4. C++ stores pointer in _dp_dragTickFn for later use in TimerProc
    *
    * Windows only: Wrapped in #if windows conditional compilation.
    */
    private static function _ensureDragTickRegistered():Void
    {
        #if windows
        if (_dragTickRegistered) return;
        _dragTickRegistered = true;
        _registerDragTickBridge(untyped __cpp__('(void*){0}', cpp.Function.fromStaticFunction(_onDragTick)));
        #end
    }

    /**
    * Called ~60 times/second WHILE native drag is active.
    *
    * This function is invoked by Windows TimerProc inside the modal drag loop.
    * It forces OpenFL to update logic and render a new frame, preventing UI freeze.
    *
    * Execution flow:
    * 1. Force Lime to run logic cycle (app.onUpdate.dispatch)
    * 2. Mark stage as dirty (stage.__renderDirty = true)
    * 3. Force OpenFL to draw to GL back buffer (win.onRender.dispatch)
    * 4. Swap buffers to present frame (SwapBuffers via wglGetCurrentDC)
    *
    * Why this works:
    * - SendMessage blocks Haxe thread, but Windows still dispatches WM_TIMER
    * - TimerProc runs on same thread (reentrant), so it's safe
    * - We manually trigger the render pipeline that would normally run in ENTER_FRAME
    *
    * Performance: ~60 FPS (15ms interval), sufficient for smooth UI updates.
    */
    private static function _onDragTick():Void
    {
        var stage = openfl.Lib.current.stage;
        if (stage == null) return;

        // 1. Force Lime to run logic cycle (Event.ENTER_FRAME equivalent)
        try {
            var app = lime.app.Application.current;
            if (app != null && app.onUpdate != null) {
                untyped app.onUpdate.dispatch(15); // 15 ms ~ 60 FPS
            }
        } catch(e:Dynamic) {}

        // 2. Mark stage as dirty to force render
        // Without this, OpenFL sees no changes and skips rendering
        try {
            untyped stage.__renderDirty = true;
            untyped stage.__clearDirty = true; // Forces clear of old frame in buffer
            stage.invalidate();
        } catch(e:Dynamic) {}

        // 3. Force OpenFL to physically draw new frame to BACK buffer
        try {
            var win = stage.window;
            // Try to get correct rendering context
            var ctx = untyped win.context;
            if (ctx == null) ctx = untyped stage.__context;

            if (win != null && ctx != null) {
                // Call Lime render event that OpenFL listens to
                untyped win.onRender.dispatch(ctx);
            }
        } catch(e:Dynamic) {}

        // 4. Swap buffers (present back buffer to screen)
        #if windows
        untyped __cpp__('
            HDC hDC = wglGetCurrentDC();
            if (hDC != NULL) {
                SwapBuffers(hDC);
            } else {
                HWND hWnd = _dp_findMainWindow();
                if (hWnd != NULL) {
                    hDC = GetDC(hWnd);
                    if (hDC != NULL) {
                        SwapBuffers(hDC);
                        ReleaseDC(hWnd, hDC);
                    }
                }
            }
        ');
        #end
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================

    /**
    * Resize the panel to fit the stage.
    *
    * Called by Main.hx on:
    * - Initial setup (after ADDED_TO_STAGE)
    * - Window resize events (Event.RESIZE)
    * - Mode switch (Editor ↔ Device Panel)
    * - Maximize/Restore operations (v3.8)
    *
    * Process:
    * 1. Redraw background with new dimensions
    * 2. Resize header bar
    * 3. Reposition buttons ([X] at right edge, [□], [E], [C] shifted left)
    *
    * @param w New width (typically stage.stageWidth)
    * @param h New height (typically stage.stageHeight)
    */
    public function setSize(w:Float, h:Float):Void
    {
        drawBackground(w, h);

        // Resize header
        if (_header != null)
        {
            _header.graphics.clear();
            _header.graphics.beginFill(0x2a2a34);
            _header.graphics.drawRect(0, 0, w, 30);
            _header.graphics.endFill();

            // =========================================================================
            // v3.5: REPOSITION BUTTONS ON RESIZE
            // =========================================================================
            // Keep buttons in the same positions as Main.hx
            if (_btnClose != null)
            {
                _btnClose.x = w - 45;
                _btnClose.y = 5;

                // Update visibility on resize / mode switch
                var cfg = DisplayConfig.getInstance();
                _btnClose.visible = cfg.deviceButtons.showClose;
            }

            // Recalculate positions for [E], [C], [□]
            var btnX = w - 45; // Start from close button position
            for (i in 0..._header.numChildren)
            {
                var child = _header.getChildAt(_header.numChildren - 1 - i);
                if (Std.isOfType(child, Sprite) && child != _titleLabel && child != _btnClose)
                {
                    btnX -= (child.width + 10);
                    child.x = btnX;
                }
            }
        }
    }

    /**
    * Set the current assembly context.
    * Updates the title to show "Device Panel: [assembly name]".
    *
    * Called by Main.hx when switching to Device Panel mode.
    *
    * @param assembly The assembly to display devices from
    */
    public function setContext(assembly:Assembly):Void
    {
        _assembly = assembly;
        _titleLabel.text = "Device Panel: " + assembly.blueprint.name;
    }

    /**
    * v3.9: Update the maximize button VECTOR icon based on window state.
    * Called by Main._onFullscreenToggled() (FULLSCREEN_TOGGLED impulse).
    *
    * @param isMaximized true = "restore" stacked squares, false = "maximize" square
    */
    public function setMaximizedState(isMaximized:Bool):Void
    {
        if (_maximizeIcon == null) return;

        _maximizeIcon.graphics.clear();
        if (isMaximized)
        {
            WindowGlyphs.drawRestore(_maximizeIcon.graphics, 28, 26, 0xFFFFFF, 0x555500);
        }
        else
        {
            WindowGlyphs.drawMaximize(_maximizeIcon.graphics, 28, 26, 0xFFFFFF);
        }
    }

    /**
    * Add a device (atom) to the panel.
    *
    * Process:
    * 1. Check for duplicates (same atom already added)
    * 2. Create DeviceCard wrapping the atom
    * 3. Add to _deviceCards array
    * 4. Position card (use provided x/y or auto-find free position)
    * 5. Emit DEVICE_WINDOW_CHANGED for state persistence
    *
    * @param atom The atom to display (must have a DeviceView widget)
    * @param x Optional X position (if null, auto-positioned)
    * @param y Optional Y position (if null, auto-positioned)
    *
    * Emits: DEVICE_WINDOW_CHANGED (for Main.hx cache sync)
    */
    public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void
    {
        if (atom == null) return;

        // Avoid duplicates
        for (card in _deviceCards)
        {
            if (card.atom == atom) return;
        }

        var card = new DeviceCard(atom, this);
        card.alpha = 1.0;
        _deviceCards.push(card);
        addChild(card);

        if (x != null && y != null)
        {
            card.x = x;
            card.y = y;
        }
        else {
            var pos = findFreePosition(card);
            card.x = pos.x;
            card.y = pos.y;
        }

        // v3.12: keep the z numbering honest for the newcomer (it is
        // appended last → topmost slot).
        reapplyZOrder();

        // Emit save signal when adding a new device
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    /**
    * Remove a device card from the panel.
    *
    * Process:
    * 1. Remove from _deviceCards array
    * 2. Remove from display list
    * 3. Dispose card (releases widget back to registry)
    * 4. Emit DEVICE_WINDOW_CHANGED for state persistence
    *
    * @param card The DeviceCard to remove
    *
    * Emits: DEVICE_WINDOW_CHANGED (for Main.hx cache sync)
    */
    public function removeDevice(card:DeviceCard):Void
    {
        if (_deviceCards.remove(card))
        {
            if (this.contains(card)) removeChild(card);
            card.dispose();
            reapplyZOrder(); // v3.12: compact the numbering 1..N-1
            Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
        }
    }

    // =========================================================================
    // Z-ORDER SYSTEM (v3.12, Task 158/159 — the pilot's design)
    // =========================================================================

    /**
    * The array order IS the z numbering: index i = zOrder i+1.
    *
    * INSERT semantics (the pilot's exact rule): setting a widget's zOrder
    * to 1 makes ALL other widgets get zOrder > 1 in turn; setting it to 3
    * keeps the widgets with 1 and 2 untouched, places this one at 3, and
    * renumbers the tail (old 3 becomes 4, old 4 becomes 5, ...). z <= 0
    * is "the surface itself" — the caller does not manage depth and the
    * current auto order stays untouched.
    */
    public function setCardZOrder(card:DeviceCard, z:Int):Void
    {
        if (card == null || z < 1) return;
        if (_deviceCards.indexOf(card) == -1) return;

        _deviceCards.remove(card);

        var idx:Int = z - 1;
        if (idx > _deviceCards.length) idx = _deviceCards.length;
        _deviceCards.insert(idx, card);

        reapplyZOrder();
    }

    /**
    * Click-to-front route for framed cards: moves the card to the topmost
    * slot and renumbers. DeviceCard prefers this over the legacy
    * addChild-to-top so the numbering never lies.
    */
    public function bringCardToFront(card:DeviceCard):Void
    {
        if (card == null) return;
        if (_deviceCards.indexOf(card) == -1) return;

        _deviceCards.remove(card);
        _deviceCards.push(card);

        reapplyZOrder();
    }

    /** Current 1-based z slot of the card (0 = not on this panel). */
    public function getCardZOrder(card:DeviceCard):Int
    {
        var idx:Int = _deviceCards.indexOf(card);
        return (idx == -1) ? 0 : idx + 1;
    }

    /**
    * Renumber 1..N and mirror the array order into the DisplayList.
    * Cards sit right above the panel header (header first, then cards in
    * z order). O(N) on a few dozen cards — cheap enough per mutation.
    */
    private function reapplyZOrder():Void
    {
        var base:Int = 1;
        if (_header != null && this.contains(_header))
        {
            try { base = getChildIndex(_header) + 1; } catch (e:Dynamic) { base = 1; }
        }

        for (i in 0..._deviceCards.length)
        {
            var card:DeviceCard = _deviceCards[i];
            card.zOrder = i + 1;
            if (!this.contains(card)) continue;
            try
            {
                setChildIndex(card, base + i);
            }
            catch (e:Dynamic)
            {
                // exotic container state — the array order still rules the
                // numbering; the visual slot catches up on the next pass
            }
        }
    }

    /**
    * Remove all devices from the panel.
    *
    * IMPORTANT: Does NOT emit DEVICE_WINDOW_CHANGED.
    *
    * Reason: If called during mode switch (after syncing cache), emitting here
    * would cause the cache to be wiped immediately. Emission is handled manually
    * in the [C] button callback for explicit clears.
    *
    * Usage:
    * - Mode switch: Main.hx calls clearDevices() then syncs cache manually
    * - [C] button: Calls clearDevices() then emits DEVICE_WINDOW_CHANGED
    */
    public function clearDevices():Void
    {
        while (_deviceCards.length > 0)
        {
            var card = _deviceCards.pop();
            if (this.contains(card)) removeChild(card);
            card.dispose();
        }
        // Do NOT emit event here to prevent cache wipe during mode switch
    }

    /**
    * Returns the list of current device cards.
    * Used by Main.hx to sync state to cache before saving.
    *
    * @return Array of DeviceCard instances
    */
    public function getDeviceCards():Array<DeviceCard>
    {
        return _deviceCards;
    }

    // =========================================================================
    // SETUP UI
    // =========================================================================

    /**
    * Initialize UI elements and event listeners.
    * Called once when panel is added to stage.
    *
    * Creates:
    * - Background (drawBackground)
    * - Header with title and buttons (createHeader)
    *
    * Listeners:
    * - CLICK on stage → hide context menu
    * - RIGHT_CLICK on stage → show context menu
    * - ATOM_DELETED impulse → remove deleted atom's card
    */
    private function setupUI():Void
    {
        drawBackground(800, 600);
        createHeader();

        // Listeners
        stage.addEventListener(MouseEvent.CLICK, onStageClick);
        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, onAtomDeleted);
    }

    /**
    * Draw the panel background.
    * Uses DEVICE_CANVAS_BG_COLOR from EditorTheme.
    *
    * @param w Width to draw
    * @param h Height to draw
    */
    private function drawBackground(w:Float, h:Float):Void
    {
        graphics.clear();
        graphics.beginFill(_theme.DEVICE_CANVAS_BG_COLOR, 1.0);
        graphics.drawRect(0, 0, w, h);
        graphics.endFill();
    }
    /**
    * Create the header bar with title and control buttons.
    *
    * Layout (right to left):
    * - [X] Close button (40x40, ButtonComponent) at x = stageWidth - 45
    * - [□] Maximize button (28x26) at x = stageWidth - 88
    * - [C] Clear button (28x26) at x = stageWidth - 126
    * - [E] Editor button (28x26) at x = stageWidth - 164
    * - Title text field (left-aligned)
    *
    * All buttons stop MOUSE_DOWN propagation to prevent unwanted drag.
    *
    * v3.8: Added maximize button and double-click handler for header.
    * v3.9: Maximize icon is a vector drawing (WindowGlyphs), not a text glyph.
    */
    private function createHeader():Void
    {
        var headerWidth = (stage != null) ? stage.stageWidth : 800;

        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, headerWidth, 30);
        _header.graphics.endFill();
        addChild(_header);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "Device Panel";
                _titleLabel.x = 7;
                _titleLabel.y = 7;
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // =========================================================================
        // v3.5: SHIFTED BUTTONS — moved left to avoid overlap with large [X]
        // =========================================================================
        // Large close button occupies x: headerWidth-45 .. headerWidth-5
        // [□] button: headerWidth-88 .. headerWidth-60 (safe gap)
        // [C] button: headerWidth-126 .. headerWidth-98 (safe gap)
        // [E] button: headerWidth-164 .. headerWidth-136 (safe gap)

        // Button [E] - Editor Mode (leftmost of the group)
        var editorBtn = createHeaderButton("E", 0x005500, function(_)
        {
            if (onShowEditor != null) onShowEditor();
        });
        editorBtn.x = headerWidth - 164;
        _header.addChild(editorBtn);

        // Button [C] - Clear
        var clearBtn = createHeaderButton("C", 0x555500, function(_)
        {
            clearDevices();
            Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
        });
        clearBtn.x = headerWidth - 126;
    //    _header.addChild(clearBtn);

        // =========================================================================
        // v3.9: MAXIMIZE/RESTORE BUTTON — VECTOR ICON (no text glyph → no tofu risk)
        // =========================================================================
        // "◱" (U+25F1) is missing from Arial; Lime/FreeType has no font fallback
        // on C++ targets. The icon is drawn via WindowGlyphs instead and redrawn
        // by setMaximizedState() on every fullscreen state change.
        _maximizeBtn = createHeaderButton("", 0x555500, function(_)
        {
            if (onToggleMaximize != null) onToggleMaximize();
        });
        _maximizeBtn.x = headerWidth - 88;
        _header.addChild(_maximizeBtn);

        // Vector icon sprite (mouse-transparent), redrawn by setMaximizedState()
        _maximizeIcon = new Sprite();
        _maximizeIcon.mouseEnabled = false;
        WindowGlyphs.drawMaximize(_maximizeIcon.graphics, 28, 26, 0xFFFFFF);
        _maximizeBtn.addChild(_maximizeIcon);

        // =========================================================================
        // v3.5: CREATE EDITOR-STYLE CLOSE BUTTON
        // =========================================================================
        _btnClose = new ButtonComponent("x", function()
        {
            if (onCloseApp != null) onCloseApp();
        });
        _btnClose.x = headerWidth - 45;
        _btnClose.y = -5;
        _header.addChild(_btnClose);

        // Read initial visibility state from DisplayConfig
        var cfg = DisplayConfig.getInstance();
        _btnClose.visible = cfg.deviceButtons.showClose;

        // =========================================================================
        // v3.6: HEADER DRAG FUNCTIONALITY
        // =========================================================================
        _header.addEventListener(MouseEvent.MOUSE_DOWN, onHeaderMouseDown);
        _header.buttonMode = true;

        // =========================================================================
        // v3.8: DOUBLE-CLICK HEADER TO TOGGLE MAXIMIZE
        // =========================================================================
        // Standard OS behavior: double-click title bar to maximize/restore.
        // Enabled on header sprite; handler checks if click was on a button.
        _header.doubleClickEnabled = true;
        _header.addEventListener(MouseEvent.DOUBLE_CLICK, onHeaderDoubleClick);
    }

    /**
    * Create a header button with label and click handler.
    *
    * IMPORTANT: Stops MOUSE_DOWN propagation to prevent bubbling to header,
    * which would trigger unwanted drag initiation.
    *
    * v3.9 FIX: defaultTextFormat is assigned BEFORE setting text.
    * Flash/OpenFL semantics: defaultTextFormat only applies to text assigned
    * AFTER it — setting text first leaves the label with default formatting
    * (no bold, no center alignment).
    *
    * @param label Button text (single character: "E", "C", etc.; "" for icon-only buttons)
    * @param color Background color (hex)
    * @param onClick Click handler function
    * @return Sprite containing button graphics and text
    */
    private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite
    {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRect(0, 0, 28, 26);
        btn.graphics.endFill();

        var txt = new TextField();
        txt.width = 28;
        txt.height = 26;
        txt.selectable = false;
        txt.mouseEnabled = false;
        txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
        txt.text = label;
        btn.addChild(txt);

        btn.buttonMode = true;
        btn.addEventListener(MouseEvent.CLICK, onClick);

        // Stop MOUSE_DOWN from propagating to header (prevents unwanted drag)
        btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());

        return btn;
    }

    // =========================================================================
    // v3.7: NATIVE DRAG BRIDGE
    // =========================================================================

    /**
    * Start native OS-level window drag (Windows only).
    *
    * Uses SendMessage(WM_NCLBUTTONDOWN, HTCAPTION) to hand control to DWM compositor.
    * Achieves perfect 1:1 cursor tracking with zero Haxe frame lag.
    *
    * Process:
    * 1. SetTimer(15ms) → registers _dp_DragTimerProc callback
    * 2. ReleaseCapture() → releases mouse capture from Haxe
    * 3. SendMessage(WM_NCLBUTTONDOWN, HTCAPTION) → starts native drag
    *    - BLOCKS Haxe thread until user releases mouse
    *    - Windows dispatches WM_TIMER every 15ms during drag
    *    - TimerProc calls _onDragTick() to update UI
    * 4. KillTimer() → unregisters callback after drag ends
    *
    * @return true if native drag was performed, false if failed or non-Windows
    *
    * Implementation: Uses untyped __cpp__() to call global extern "C" function
    * declared in @:cppFileCode, avoiding namespace resolution issues.
    */
    private static function _nativeStartDrag():Bool
    {
        #if windows
        var result:Bool = false;
        untyped __cpp__('{0} = (bool)::_dp_nativeStartDrag();', result);
        return result;
        #else
        return false;
        #end
    }

    /**
    * Register Haxe function pointer with C++ layer.
    * Called once during initialization via _ensureDragTickRegistered().
    *
    * @param inTick Function pointer to _onDragTick (converted via cpp.Function.fromStaticFunction)
    *
    * Implementation: Uses untyped __cpp__() to call global extern "C" function
    * declared in @:cppFileCode, avoiding namespace resolution issues.
    */
    #if windows
        private static function _registerDragTickBridge(inTick:cpp.RawPointer<cpp.Void>):Void
    {

        untyped __cpp__('::_dp_registerDragTick((void*){0});', inTick);

    }
     #end
    // =========================================================================
    // v3.6: HEADER DRAG HANDLERS
    // =========================================================================

    /**
    * Handle MOUSE_DOWN on header to initiate window drag.
    *
    * Strategy:
    * 1. Check if click was on a button (skip drag if so)
    * 2. v3.9: If window is fullscreen — restore it FIRST (standard OS behavior)
    * 3. Try native OS drag first (Windows only) — perfect smoothness
    * 4. If native drag fails or non-Windows — fall back to Haxe-side drag
    *
    * Native drag blocks the thread until mouse-up, so no Haxe listeners are needed.
    * Haxe-side drag uses absolute position model to prevent flicker.
    *
    * @param e Mouse event containing click coordinates
    */
    private function onHeaderMouseDown(e:MouseEvent):Void
    {
        if (_dragging) return;

        // Check if click was on a button (walk up display list)
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != _header)
        {
            if (Std.isOfType(targetObj, Sprite))
            {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == _header) return; // Clicked button, skip drag
            }
            targetObj = targetObj.parent;
        }

        // =========================================================================
        // v3.11 NOTE: With true SW_MAXIMIZE (WindowController v1.5) the native
        // caption drag performs the restore-under-cursor dance AUTOMATICALLY
        // when the user drags a zoomed window — the former manual reposition
        // block (v3.10) was removed because it would fight the OS behavior
        // (double restore, lost cursor ratio).
        // DisplayConfig.isFullscreen is re-synced by Main.onResize (IsZoomed)
        // right after the modal loop returns.
        // =========================================================================

        // =========================================================================
        // v3.7: TRY NATIVE OS DRAG FIRST (Windows only)
        // =========================================================================
        if (_nativeStartDrag())
        {
            // Native drag completed (user released mouse).
            // Window is now at its final position. Done.
            return;
        }

        // =========================================================================
        // FALLBACK: Haxe-side absolute-position drag (non-Windows or native failed)
        // =========================================================================
        _dragging = true;

        // Store START mouse position (absolute, not delta)
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;

        // Notify Main.hx to capture current window position
        if (onWindowDragStart != null) onWindowDragStart();

        if (stage != null)
        {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onHeaderMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onHeaderMouseUp);
        }
    }

    /**
    * Handle MOUSE_MOVE during Haxe-side drag.
    * Computes delta from START position (not previous frame) to prevent flicker.
    *
    * @param e Mouse event containing current coordinates
    */
    private function onHeaderMouseMove(e:MouseEvent):Void
    {
        if (!_dragging) return;

        // Delta from START position (absolute model)
        var dx = e.stageX - _mouseStartX;
        var dy = e.stageY - _mouseStartY;

        // Notify Main.hx with absolute delta
        if (onWindowDrag != null)
        {
            onWindowDrag(dx, dy);
        }
    }

    /**
    * Handle MOUSE_UP to end Haxe-side drag.
    * Removes move/up listeners and resets _dragging flag.
    *
    * @param e Mouse event (unused)
    */
    private function onHeaderMouseUp(e:MouseEvent):Void
    {
        _dragging = false;

        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onHeaderMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onHeaderMouseUp);
        }
    }

    // =========================================================================
    // v3.8: DOUBLE-CLICK HANDLER (Maximize/Restore)
    // =========================================================================

    /**
    * Handle double-click on header to toggle maximize/restore.
    *
    * Standard OS behavior: double-clicking the title bar toggles between
    * maximized and restored window states.
    *
    * Protection: If the double-click was on a button (e.g., [E], [C], [□], [X]),
    * the maximize toggle is skipped to avoid conflicting with button actions.
    *
    * @param e Mouse event containing click coordinates
    */
    private function onHeaderDoubleClick(e:MouseEvent):Void
    {
        // Check if double-click was on a button (walk up display list)
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != _header)
        {
            if (Std.isOfType(targetObj, Sprite))
            {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == _header) return; // Clicked button, skip maximize
            }
            targetObj = targetObj.parent;
        }

        // Double-click was on header background — toggle maximize
        if (onToggleMaximize != null) onToggleMaximize();
    }

    // =========================================================================
    // CONTEXT MENU
    // =========================================================================

    /**
    * Handle RIGHT_CLICK to show/hide context menu.
    * Toggles menu visibility at click coordinates.
    *
    * @param e Mouse event containing click coordinates
    */
    private function onRightClick(e:MouseEvent):Void
    {
        if (_menuVisible) hideContextMenu();
        else showContextMenu(e.stageX, e.stageY);
    }

    /**
    * Show context menu with list of available devices.
    *
    * Process:
    * 1. Hide any existing menu
    * 2. Create new menu sprite
    * 3. Add "Add Device:" header
    * 4. Get device list from onGetAssemblyList callback
    * 5. Filter out "selfrun" (root assembly)
    * 6. Create menu items for each device
    * 7. Position menu at click coordinates (clamped to stage bounds)
    *
    * @param x X coordinate for menu position
    * @param y Y coordinate for menu position
    */
    private function showContextMenu(x:Float, y:Float):Void
    {
        hideContextMenu(); // Clean previous

        _contextMenu = new Sprite();
        var yPos = 5;

        var headerItem = createMenuItem("Add Device:", null, true);
        headerItem.y = yPos;
        _contextMenu.addChild(headerItem);
        yPos += 28;

        // Get list from Main
        var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
        devices = [for (d in devices) if (d.id != "selfrun") d];

        if (devices.length == 0)
        {
            var emptyItem = createMenuItem("(No devices)", null, true);
            emptyItem.y = yPos;
            _contextMenu.addChild(emptyItem);
            yPos += 26;
        }
        else {
            for (item in devices)
            {
                var displayName = item.atom.displayName != null ? item.atom.displayName : item.atom.name;
                var menuItem = createMenuItem(displayName, item.atom, false);
                menuItem.y = yPos;
                _contextMenu.addChild(menuItem);
                yPos += 26;
            }
        }

        // Draw background
        _contextMenu.graphics.beginFill(0x333344, 0.98);
        _contextMenu.graphics.lineStyle(1, 0x555566);
        _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 10, 6, 6);
        _contextMenu.graphics.endFill();

        // Clamp to stage bounds
        _contextMenu.x = Math.min(x, stage.stageWidth - 200);
        _contextMenu.y = Math.min(Math.max(y - 30, 0), stage.stageHeight - yPos - 20);

        addChild(_contextMenu);
        _menuVisible = true;
    }

    /**
    * Hide and remove context menu from display list.
    */
    private function hideContextMenu():Void
    {
        if (_contextMenu != null && _contextMenu.parent != null)
        {
            removeChild(_contextMenu);
        }
        _contextMenu = null;
        _menuVisible = false;
    }

    /**
    * Handle CLICK on stage to hide context menu if clicked outside.
    *
    * @param e Mouse event containing click coordinates
    */
    private function onStageClick(e:MouseEvent):Void
    {
        if (_menuVisible && _contextMenu != null)
        {
            if (!_contextMenu.hitTestPoint(e.stageX, e.stageY))
            {
                hideContextMenu();
            }
        }
    }

    /**
    * Create a context menu item with label and optional atom reference.
    *
    * @param label Display text
    * @param atom Atom to add when clicked (null for disabled items)
    * @param disabled If true, item is non-interactive (grayed out)
    * @return Sprite containing menu item graphics and text
    */
    private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite
    {
        var item = new Sprite();
        item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
        item.graphics.drawRect(0, 0, 180, 24);
        item.graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
        txt.text = (disabled || atom == null) ? label : "+ " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);

        if (!disabled && atom != null)
        {
            item.buttonMode = true;
            final capturedAtom = atom;

            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent)
            {
                addDevice(capturedAtom);
                hideContextMenu();
            });

            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent)
            {
                item.graphics.clear();
                item.graphics.beginFill(0x556677);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });

            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
            {
                item.graphics.clear();
                item.graphics.beginFill(0x444455);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
        }

        return item;
    }

    // =========================================================================
    // EVENTS & HELPERS
    // =========================================================================

    /**
    * Handle ATOM_DELETED impulse to remove deleted atom's card.
    *
    * Called automatically when an atom is deleted from the assembly.
    * Finds and removes all DeviceCards referencing the deleted atom.
    *
    * @param impulse Impulse containing {assemblyId: String, atomId: String} of deleted atom
    */
    private function onAtomDeleted(impulse:Impulse):Void
    {
        if (impulse.data == null) return;
        // v1.6 Identity Contract: atomId (was `id`)
        var deletedId:String = impulse.data.atomId;

        var toRemove:Array<DeviceCard> = [];
        for (card in _deviceCards)
        {
            if (card.atom != null && card.atom.id == deletedId)
            {
                toRemove.push(card);
            }
        }

        for (card in toRemove)
        {
            removeDevice(card);
        }
    }

    /**
    * Find a free position for a new device card.
    * Uses grid-based search with fallback to random position.
    *
    * Grid parameters:
    * - Start: (10, 50) — below header
    * - Step: (120, 100) — card width + gap, card height + gap
    * - Search: 10 rows × 5 columns
    *
    * @param card The card to position (used for size reference)
    * @return {x: Float, y: Float} position coordinates
    */
    private function findFreePosition(card:DeviceCard):{x:Float, y:Float}
    {
        var startX = 10;
        var startY = 50; // Below header
        var stepX = 120;
        var stepY = 100;

        for (y in 0...10)
        {
            for (x in 0...5)
            {
                var px = startX + x * stepX;
                var py = startY + y * stepY;
                if (isPositionFree(px, py)) return {x: px, y: py};
            }
        }

        // Fallback: random position
        return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
    }

    /**
    * Check if a position is free (no overlapping cards).
    *
    * @param x X coordinate to check
    * @param y Y coordinate to check
    * @return true if position is free, false if occupied
    */
    private function isPositionFree(x:Float, y:Float):Bool
    {
        for (card in _deviceCards)
        {
            if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
        }
        return true;
    }

    /**
    * Clean up all resources and event listeners.
    *
    * Process:
    * 1. Clear all device cards (clearDevices)
    * 2. Remove close button from display list
    * 3. v3.8: Remove maximize button references
    * 4. Remove stage event listeners
    * 5. Unsubscribe from ATOM_DELETED impulse
    *
    * Called by Main.hx when switching modes or shutting down.
    */
    public function dispose():Void
    {
        clearDevices();

        // Cleanup close button
        if (_btnClose != null)
        {
            if (_btnClose.parent != null)
            {
                _btnClose.parent.removeChild(_btnClose);
            }
            _btnClose = null;
        }

        // =========================================================================
        // v3.8: CLEANUP MAXIMIZE BUTTON
        // =========================================================================
        _maximizeBtn = null;
        _maximizeBtnLabel = null;
        _maximizeIcon = null; // v3.9
        // =========================================================================

        stage.removeEventListener(MouseEvent.CLICK, onStageClick);
        stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        Impulsys.removeImpulse(EventType.ATOM_DELETED, onAtomDeleted);
    }
}

