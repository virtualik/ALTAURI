package ui;
import openfl.Lib;
import lime.ui.Window;

// =========================================================================
// WINDOWS HEADERS - Layered Window with Color Key
// =========================================================================
@:cppFileCode('
#if defined(_WIN32)
    #include <windows.h>
    #include <dwmapi.h>
    #include <stdio.h>
    #include <string.h>
    #pragma comment(lib, "dwmapi.lib")
    #pragma comment(lib, "user32.lib")
    #pragma comment(lib, "gdi32.lib")

    // wglGetCurrentDC is in opengl32.dll — declare manually since
    // WIN32_LEAN_AND_MEAN excludes GL headers (same trick as DevicePanel)
    extern "C" __declspec(dllimport) HDC __stdcall wglGetCurrentDC(void);
    #pragma comment(lib, "opengl32.lib")

    // =====================================================================
    // v1.1 FIX: Defensive WS_THICKBOX definition
    // =====================================================================
    // WS_THICKBOX (== WS_SIZEBOX == 0x00040000) enables the native sizing
    // border used by _wc_nativeStartResize(). Some Windows SDK / hxcpp
    // include-order combinations do not expose it from winuser.h, which
    // breaks compilation (C2065 + cascade C2660 on SetWindowLongA).
    // Defining it locally when missing is safe: the value is frozen by
    // Windows ABI compatibility forever.
    #ifndef WS_THICKBOX
    #define WS_THICKBOX 0x00040000L
    #endif

    static HWND g_haxeWindow = NULL;
    static DWORD g_ourProcessId = 0;
    static BOOL g_transparencyEnabled = FALSE;

    static void debugLogNative(const char* msg) {
        OutputDebugStringA("[WC] ");
        OutputDebugStringA(msg);
        OutputDebugStringA("\\n");
    }

    static HWND findHaxeWindow() {
        if (g_haxeWindow != NULL && IsWindow(g_haxeWindow)) {
            return g_haxeWindow;
        }

        g_haxeWindow = NULL;

        if (g_ourProcessId == 0) {
            g_ourProcessId = GetCurrentProcessId();
        }

        HWND hWnd = GetTopWindow(NULL);
        char buf[512];

        while (hWnd != NULL) {
            DWORD pid = 0;
            GetWindowThreadProcessId(hWnd, &pid);

            if (pid == g_ourProcessId) {
                HWND owner = GetWindow(hWnd, GW_OWNER);
                LONG style = GetWindowLong(hWnd, GWL_STYLE);

                if ((style & WS_VISIBLE) && owner == NULL) {
                    char className[256] = {0};
                    GetClassNameA(hWnd, className, 255);

                    if (strstr(className, "SDL") != NULL ||
                        strstr(className, "HXCPP") != NULL ||
                        strstr(className, "OpenFL") != NULL) {
                        g_haxeWindow = hWnd;
                        return g_haxeWindow;
                    }

                    if (g_haxeWindow == NULL) {
                        g_haxeWindow = hWnd;
                    }
                }
            }

            hWnd = GetNextWindow(hWnd, GW_HWNDNEXT);
        }

        return g_haxeWindow;
    }

    // =====================================================================
    // v1.1: NATIVE WINDOW CONTROL BRIDGE (drag / resize / minimize)
    // =====================================================================
    // Same architecture as DevicePanel v3.7 tick injection, but owned by
    // WindowController so BOTH TitleBar and DevicePanel can delegate here.
    //
    //  ┌───────────────────────────────────────────────────────────────┐
    //  │  SetTimer(15ms) → _wc_TimerProc → _wc_tickFn() (Haxe static)  │
    //  │  SendMessage(WM_NCLBUTTONDOWN, HT*)  ← modal loop, blocks     │
    //  │  KillTimer() after mouse-up                                   │
    //  └───────────────────────────────────────────────────────────────┘
    //
    // Timer ID differs from DevicePanel (0xD4A6) to avoid any clash if
    // both mechanisms ever run concurrently (they cannot — both are modal).
    typedef void (*_wc_TickFn)();
    static _wc_TickFn   _wc_tickFn   = NULL;
    static const UINT_PTR _wc_TIMER_ID = 0xD4B1;
    static const UINT     _wc_TIMER_MS = 15; // ~60 Hz

    static VOID CALLBACK _wc_TimerProc(HWND hWnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime)
    {
        if (_wc_tickFn != NULL) {
            _wc_tickFn();
        }
    }

    // =====================================================================
    // v1.3: LIVE RESIZE — WM_SIZE subclass bridge during modal resize
    // =====================================================================
    // The Lime/SDL event pump is blocked inside the modal resize loop, so
    // SDL_WINDOWEVENT size changes pile up unprocessed and the presented
    // frame is a frozen stretched image. During the loop we temporarily
    // subclass the window proc: every WM_SIZE is forwarded to Haxe
    // (_wc_sizeFn) which pushes the size into the cached Lime window fields
    // and re-dispatches onResize — making the whole OpenFL re-layout pipe
    // run LIVE while the user is still dragging the resize grip.
    typedef void (*_wc_SizeFn)(int, int);
    static _wc_SizeFn _wc_sizeFn   = NULL;
    static WNDPROC    _wc_origProc = NULL;

    // =====================================================================
    // v1.4: MINIMUM TRACKING SIZE for the native resize loop
    // =====================================================================
    // Enforced via WM_GETMINMAXINFO while the subclass is installed (that
    // is exactly when the modal sizing loop queries its constraints).
    // Defaults mirror ResizeGrip.MIN_WIDTH / MIN_HEIGHT (Haxe fallback).
    static int _wc_minTrackW = 640;
    static int _wc_minTrackH = 400;

    static LRESULT CALLBACK _wc_SubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
    {
        // Forward live size to Haxe FIRST, then let the original proc run
        if (uMsg == WM_SIZE && _wc_sizeFn != NULL) {
            _wc_sizeFn(LOWORD(lParam), HIWORD(lParam));
        }

        // v1.4: clamp minimum tracking size inside the native sizing loop.
        // Let the original proc fill the MINMAXINFO defaults first, then
        // raise the floor and return 0 (message fully handled).
        if (uMsg == WM_GETMINMAXINFO) {
            if (_wc_origProc != NULL) {
                CallWindowProc(_wc_origProc, hWnd, uMsg, wParam, lParam);
            }
            MINMAXINFO* mmi = (MINMAXINFO*)lParam;
            if (mmi->ptMinTrackSize.x < _wc_minTrackW) mmi->ptMinTrackSize.x = _wc_minTrackW;
            if (mmi->ptMinTrackSize.y < _wc_minTrackH) mmi->ptMinTrackSize.y = _wc_minTrackH;
            return 0;
        }

        return CallWindowProc(_wc_origProc, hWnd, uMsg, wParam, lParam);
    }

    extern "C" {

    // Start native window DRAG. Blocks until mouse-up.
    bool _wc_nativeStartDrag() {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;
        SetTimer(hWnd, _wc_TIMER_ID, _wc_TIMER_MS, _wc_TimerProc);
        ReleaseCapture();
        SendMessage(hWnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        KillTimer(hWnd, _wc_TIMER_ID);
        return true;
    }

    // Start native window RESIZE from the given edge
    // (HTLEFT/HTMLRIGHT/HTTOP/... /HTBOTTOMRIGHT, see WinUser.h).
    // The app window is borderless (WS_POPUP without WS_THICKBOX), so the
    // style is temporarily augmented with WS_THICKBOX to let DefWindowProc
    // enter the modal sizing loop, and restored right after mouse-up.
    //
    // v1.2 CRITICAL REQUIREMENT: the SDL window MUST carry the RESIZABLE flag
    // (<window resizable="true" /> in project.xml, or window.resizable = true
    // at runtime — WindowController constructor does the latter as a safety
    // net). SDL2 clamps WM_GETMINMAXINFO track sizes to the CURRENT window
    // size when the flag is absent, which turns the modal resize loop into
    // a silent no-op: the window cannot change by a single pixel.
    // The HTCAPTION drag path is NOT affected by this clamping, which is why
    // drag worked while resize appeared dead.
    bool _wc_nativeStartResize(int edge) {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;

        LONG style = GetWindowLong(hWnd, GWL_STYLE);
        BOOL addedThickbox = FALSE;
        if (!(style & WS_THICKBOX)) {
            SetWindowLong(hWnd, GWL_STYLE, style | WS_THICKBOX);
            addedThickbox = TRUE;
        }

        // v1.2: Pass REAL cursor screen coordinates. The sizing loop of
        // DefWindowProc anchors on this point. lParam=0 left the anchor at
        // the screen origin, which broke the loop on some Windows builds.
        POINT pt;
        GetCursorPos(&pt);

        // v1.3: subclass the window proc to receive live WM_SIZE events
        // while the modal loop runs (only if a Haxe callback is registered)
        if (_wc_origProc == NULL && _wc_sizeFn != NULL) {
            _wc_origProc = (WNDPROC)SetWindowLongPtr(hWnd, GWLP_WNDPROC, (LONG_PTR)_wc_SubclassProc);
        }

        SetTimer(hWnd, _wc_TIMER_ID, _wc_TIMER_MS, _wc_TimerProc);
        ReleaseCapture();
        SendMessage(hWnd, WM_NCLBUTTONDOWN, (WPARAM)edge, MAKELPARAM(pt.x, pt.y));
        KillTimer(hWnd, _wc_TIMER_ID);

        // v1.3: remove the subclass — normal SDL proc takes over again
        if (_wc_origProc != NULL) {
            SetWindowLongPtr(hWnd, GWLP_WNDPROC, (LONG_PTR)_wc_origProc);
            _wc_origProc = NULL;
        }

        if (addedThickbox) {
            SetWindowLong(hWnd, GWL_STYLE, style);
            SetWindowPos(hWnd, NULL, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
        return true;
    }

    // Minimize the window to the taskbar.
    bool _wc_minimize() {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;
        return ShowWindow(hWnd, SW_MINIMIZE) != 0;
    }

    // v1.5: OS-aware maximize and restore. SW_MAXIMIZE makes the OS treat
    // the window as truly zoomed: work-area sizing, taskbar overlay,
    // Win+arrow snapping, native restore-under-cursor during caption drag,
    // and IsZoomed() truth for state sync.
    bool _wc_maximize() {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;
        return ShowWindow(hWnd, SW_MAXIMIZE) != 0;
    }

    // Restore from zoomed or minimized state to the pre-maximize rect.
    bool _wc_restoreWindow() {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;
        return ShowWindow(hWnd, SW_RESTORE) != 0;
    }

    // True when the window is currently zoomed (WS_MAXIMIZE style bit).
    bool _wc_isZoomed() {
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;
        return IsZoomed(hWnd) != 0;
    }

    // Register the Haxe tick callback (called from WindowController.ensureTickRegistered).
    void _wc_registerTick(void* inTick) {
        _wc_tickFn = (_wc_TickFn)inTick;
    }

    // v1.3: Register the Haxe live-size callback (WM_SIZE bridge).
    void _wc_registerSizeCallback(void* inFn) {
        _wc_sizeFn = (_wc_SizeFn)inFn;
    }

    // v1.4: Configure minimum window size enforced by the native resize loop
    void _wc_setMinTrackSize(int w, int h) {
        if (w > 0) _wc_minTrackW = w;
        if (h > 0) _wc_minTrackH = h;
    }

    // v1.3: Screen-space cursor position helper.
    // Used by TitleBar/DevicePanel to reposition a restored window under
    // the cursor (Windows 10 restore-before-drag UX).
    bool _wc_getCursorPos(int* outX, int* outY) {
        POINT pt;
        if (!GetCursorPos(&pt)) return false;
        *outX = (int)pt.x;
        *outY = (int)pt.y;
        return true;
    }

    } // extern "C"

#else
    // =========================================================================
    // STUB IMPLEMENTATION FOR NON-WINDOWS PLATFORMS (Android, iOS, Linux)
    // Prevents "windows.h file not found" errors during cross-platform compilation.
    // =========================================================================
    static void* g_haxeWindow = nullptr;
    static void debugLogNative(const char* msg) {
        // Stub: Do nothing on non-Windows platforms
    }
    static void* findHaxeWindow() {
        // Stub: Return null on non-Windows platforms
        return nullptr;
    }
    // v1.1 stubs: native window control (no-ops outside Windows)
    extern "C" {
        inline bool _wc_nativeStartDrag()   { return false; }
        inline bool _wc_nativeStartResize(int edge) { return false; }
        inline bool _wc_minimize()          { return false; }
        inline bool _wc_maximize()          { return false; }
        inline bool _wc_restoreWindow()     { return false; }
        inline bool _wc_isZoomed()          { return false; }
        inline void _wc_registerTick(void* inTick) { }
        inline void _wc_registerSizeCallback(void* inFn) { }
        inline void _wc_setMinTrackSize(int w, int h) { }
        inline bool _wc_getCursorPos(int* outX, int* outY) { return false; }
    }
#endif
')
/**
 * WINDOW CONTROLLER v1.5 (Transparency + Native Window Control)
 * Platform-layer facade for OS window operations.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.5 CHANGES (True SW_MAXIMIZE)
 * ═══════════════════════════════════════════════════════════════════════════
 *  - ADDED: maximize() / restoreWindow() / isZoomed() — the OS now treats
 *    the window as truly zoomed (work area, taskbar, Win+arrow snapping,
 *    native restore-under-cursor on caption drag, IsZoomed truth).
 *  - Consumers: DisplayConfig.toggleFullscreen (Windows branch),
 *    Main.onResize state sync, and (upcoming) window state persistence.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.4 CHANGES (Min tracking size)
 * ═══════════════════════════════════════════════════════════════════════════
 *  - ADDED: WM_GETMINMAXINFO clamping in the resize subclass — the native
 *    modal sizing loop can no longer shrink the window below the floor
 *    (defaults 640x400, runtime-tunable via setMinTrackSize()).
 *  - NOTE: comments inside native code blocks are now written WITHOUT
 *    apostrophes — @:cppFileCode is a single-quoted Haxe string, so any
 *    unescaped apostrophe breaks the build.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.3 CHANGES (Live resize + cursor-aware restore)
 * ═══════════════════════════════════════════════════════════════════════════
 *  - ADDED: LIVE RESIZE — during the modal resize loop the window proc is
 *    temporarily subclassed; every WM_SIZE is forwarded to Haxe
 *    (_onLiveSize), which pushes the size into Lime and re-dispatches
 *    onResize. The OpenFL re-layout pipe runs WHILE the user drags the
 *    grip (content is no longer a frozen stretched image).
 *  - ADDED: getCursorPos() — screen cursor helper for the Windows 10
 *    restore-under-cursor UX in TitleBar/DevicePanel.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.2 CHANGES (Resize fixes after Windows field test)
 * ═══════════════════════════════════════════════════════════════════════════
 *  - FIXED: nativeStartResize() was a silent no-op: (a) SDL2 clamps
 *    WM_GETMINMAXINFO track sizes to the current window size unless the
 *    window has the RESIZABLE flag — constructor now force-enables
 *    window.resizable at runtime (safety net for project.xml);
 *    (b) SendMessage passed lParam=0 instead of real cursor coords —
 *    DefWindowProc's sizing loop anchors on that point.
 *  - HTCAPTION drag is unaffected by the clamping — that is why drag
 *    worked perfectly while resize appeared dead.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.1 CHANGES (Native Window Control + Singleton)
 * ═══════════════════════════════════════════════════════════════════════════
 *  - ADDED: Singleton access (getInstance) — Main and TitleBar/ResizeGrip
 *    share ONE controller instance instead of ad-hoc `new` everywhere.
 *  - ADDED: nativeStartDrag() — native modal window drag with 15ms tick
 *    injection (renders ~60 FPS during drag, same trick as DevicePanel v3.7).
 *  - ADDED: nativeStartResize(edge) — native modal window resize from any
 *    edge (HT* codes). Temporarily adds WS_THICKBOX for the borderless
 *    window, restores style after mouse-up.
 *  - ADDED: minimize() — ShowWindow(SW_MINIMIZE) to taskbar.
 *  - ADDED: HT edge constants (EDGE_LEFT ... EDGE_BOTTOM_RIGHT).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * RESPONSIBILITY MAP
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ┌─────────────────────────────────────────────────────────────────────┐
 *  │  WindowController (Platform Layer — OS Integration)                 │
 *  │                                                                     │
 *  │  ┌───────────────────────────────────────────────────────────────┐  │
 *  │  │  TRANSPARENCY (v1.0)                                          │  │
 *  │  │  • enableLayeredTransparency()  (color key 0xFF00FF)          │  │
 *  │  │  • toggleTransparency / toggleBlurBehind / setOpacity         │  │
 *  │  │  • debugWindowInfo()                                          │  │
 *  │  └───────────────────────────────────────────────────────────────┘  │
 *  │                                                                     │
 *  │  ┌───────────────────────────────────────────────────────────────┐  │
 *  │  │  NATIVE WINDOW CONTROL (v1.1)                                 │  │
 *  │  │  • nativeStartDrag()      → WM_NCLBUTTONDOWN + HTCAPTION      │  │
 *  │  │  • nativeStartResize(edge)→ WM_NCLBUTTONDOWN + HT<edge>       │  │
 *  │  │  • minimize()             → ShowWindow(SW_MINIMIZE)           │  │
 *  │  │  • tick injection         → SetTimer(15ms) → Haxe _onTick     │  │
 *  │  │                              → Lime update + render + swap    │  │
 *  │  └───────────────────────────────────────────────────────────────┘  │
 *  └─────────────────────────────────────────────────────────────────────┘
 */
class WindowController {
    // =========================================================================
    // SINGLETON (v1.1)
    // =========================================================================
    private static var _instance:WindowController;

    /**
     * Get the shared WindowController instance.
     * Main.initTransparency() must use this instead of `new WindowController()`
     * so TitleBar/ResizeGrip can reach the same instance.
     */
    public static function getInstance():WindowController {
        if (_instance == null) _instance = new WindowController();
        return _instance;
    }

    // =========================================================================
    // HT EDGE CONSTANTS (WinUser.h hit-test codes)
    // =========================================================================
    /** Resize from the left edge */
    public static inline var EDGE_LEFT:Int = 10;
    /** Resize from the right edge */
    public static inline var EDGE_RIGHT:Int = 11;
    /** Resize from the top edge */
    public static inline var EDGE_TOP:Int = 12;
    /** Resize from the top-left corner */
    public static inline var EDGE_TOP_LEFT:Int = 13;
    /** Resize from the top-right corner */
    public static inline var EDGE_TOP_RIGHT:Int = 14;
    /** Resize from the bottom edge */
    public static inline var EDGE_BOTTOM:Int = 15;
    /** Resize from the bottom-left corner */
    public static inline var EDGE_BOTTOM_LEFT:Int = 16;
    /** Resize from the bottom-right corner (classic grip) */
    public static inline var EDGE_BOTTOM_RIGHT:Int = 17;

    // =========================================================================
    // v1.4: MINIMUM TRACKING SIZE (native resize loop floor)
    // =========================================================================
    /** Minimum window width enforced by the native resize loop (WM_GETMINMAXINFO).
     *  Mirrors ResizeGrip.MIN_WIDTH — keep the two in sync. */
    public static inline var MIN_TRACK_W:Int = 640;

    /** Minimum window height enforced by the native resize loop (WM_GETMINMAXINFO).
     *  Mirrors ResizeGrip.MIN_HEIGHT — keep the two in sync. */
    public static inline var MIN_TRACK_H:Int = 400;

    private var _window:Window;
    private var _dwmEnabled:Bool = false;

    /**
     * v1.1: Drag tick registered flag (one-time registration per app run).
     * Static because the C++ callback pointer is global.
     */
    private static var _tickRegistered:Bool = false;

    private function new() {
        _window = Lib.current.stage.window;
        debugLog("WindowController initialized (v1.2: drag/resize/minimize)");
        debugLog("F4=Toggle F5=Blur F6=Debug F7=Opacity");
        debugLog("NOTE: Black pixels (0x000000) become transparent!");
        debugLog("Other colors with alpha=1.0 are OPAQUE");

        #if windows
        // =====================================================================
        // v1.2 SAFETY NET: ensure SDL_WINDOW_RESIZABLE is set at runtime.
        // =====================================================================
        // Without this flag SDL2 clamps WM_GETMINMAXINFO track sizes to the
        // current window size, making nativeStartResize() a silent no-op.
        // Static source of truth is project.xml <window resizable="true" />;
        // this call guards configs built without it. Runs before the window
        // becomes visible (project.xml visible="false"), so no visual flash.
        // try/catch guards older lime versions lacking the resizable setter.
        // Reflect (not untyped field access) so a missing property degrades
        // gracefully at runtime instead of breaking compilation.
        try {
            if (_window != null) Reflect.setProperty(_window, "resizable", true);
        } catch (e:Dynamic) {
            debugLog("WARNING: window.resizable setter unavailable "
                + "— add resizable=\"true\" to project.xml <window if=\"cpp\"/>");
        }
        #end
    }

    #if windows
    public function enableLayeredTransparency():Bool {
        return _enableLayeredNative();
    }

    public function enableDWMTransparency():Bool {
        return enableLayeredTransparency();
    }

    public function toggleTransparency():Bool {
        if (_dwmEnabled) {
            var result = _disableLayeredNative();
            _dwmEnabled = false;
            debugLog("Transparency OFF");
            return result;
        } else {
            var result = _enableLayeredNative();
            if (result) _dwmEnabled = true;
            return result;
        }
    }

    public function toggleBlurBehind():Bool {
        return _enableBlurNative();
    }

    public function setOpacity(alpha:Int):Bool {
        return _setOpacityNative(alpha);
    }

    public function debugWindowInfo():Void {
        _debugNative();
    }

    // =========================================================================
    // v1.1: NATIVE WINDOW CONTROL API
    // =========================================================================

    /**
     * Start native modal window drag (blocks Haxe thread until mouse-up).
     * Tick injection keeps the render alive (~60 FPS) during the modal loop.
     * @return true if native drag was performed, false if failed
     */
    public function nativeStartDrag():Bool {
        ensureTickRegistered();
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_nativeStartDrag();", result);
        return result;
    }

    /**
     * Start native modal window resize from the given edge.
     * Use EDGE_* constants (e.g. EDGE_BOTTOM_RIGHT for the corner grip).
     * @return true if native resize was performed, false if failed
     */
    public function nativeStartResize(edge:Int):Bool {
        ensureTickRegistered();
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_nativeStartResize((int){1});", result, edge);
        return result;
    }

    /**
     * Minimize the window to the OS taskbar.
     * @return true if the command was sent
     */
    public function minimize():Bool {
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_minimize();", result);
        return result;
    }

    /**
     * v1.5: Maximize the window the OS-NATIVE way (SW_MAXIMIZE).
     *
     * Unlike the former fake-fullscreen (win.resize to screen size), the OS
     * now KNOWS the window is zoomed, which enables:
     *   - work-area sizing (taskbar stays visible and usable)
     *   - Win+Arrow snapping, Win+D behavior
     *   - native restore-under-cursor when dragging a zoomed caption
     *   - IsZoomed() as the authoritative state source (see isZoomed())
     *
     * @return true if the command was sent
     */
    public function maximize():Bool {
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_maximize();", result);
        return result;
    }

    /**
     * v1.5: Restore the window from zoomed/minimized state (SW_RESTORE).
     * Returns the window to the pre-maximize rectangle.
     * @return true if the command was sent
     */
    public function restoreWindow():Bool {
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_restoreWindow();", result);
        return result;
    }

    /**
     * v1.5: Is the window currently zoomed (SW_MAXIMIZE)?
     * Authoritative state source for Main.onResize sync — replaces the old
     * size-heuristic (win.width vs screen mode), which is wrong under real
     * maximize because the work area is smaller than the screen mode.
     * @return true if zoomed (always false on non-Windows)
     */
    public function isZoomed():Bool {
        var result:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_isZoomed();", result);
        return result;
    }

    /**
     * One-time registration of the Haxe tick callback with the C++ layer.
     * v1.3: also registers the live-size (WM_SIZE) callback.
     * Mirrors DevicePanel._ensureDragTickRegistered() but for _wc_ bridge.
     */
    private static function ensureTickRegistered():Void {
        if (_tickRegistered) return;
        _tickRegistered = true;
        untyped __cpp__("::_wc_registerTick((void*){0});", cpp.Function.fromStaticFunction(_onTick));
        untyped __cpp__("::_wc_registerSizeCallback((void*){0});", cpp.Function.fromStaticFunction(_onLiveSize));
    }

    /**
     * Called ~60 times/second WHILE a native modal loop (drag or resize) is
     * active. Forces the full Lime/OpenFL pipeline so the UI does not freeze:
     *  1. app.onUpdate.dispatch(15)   — Lime logic cycle (ENTER_FRAME analog)
     *  2. stage.__renderDirty = true  — mark stage dirty
     *  3. win.onRender.dispatch(ctx)  — draw GL back buffer
     *  4. SwapBuffers(...)            — present frame
     */
    private static function _onTick():Void {
        var stage = openfl.Lib.current.stage;
        if (stage == null) return;

        // 1. Force Lime logic cycle
        try {
            var app = lime.app.Application.current;
            if (app != null && app.onUpdate != null) {
                untyped app.onUpdate.dispatch(15);
            }
        } catch(e:Dynamic) {}

        // 2. Mark stage dirty to force render
        try {
            untyped stage.__renderDirty = true;
            untyped stage.__clearDirty = true;
            stage.invalidate();
        } catch(e:Dynamic) {}

        // 3. Force draw to GL back buffer
        try {
            var win = stage.window;
            var ctx = untyped win.context;
            if (ctx == null) ctx = untyped stage.__context;
            if (win != null && ctx != null) {
                untyped win.onRender.dispatch(ctx);
            }
        } catch(e:Dynamic) {}

        // 4. Present frame
        untyped __cpp__('
            HDC hDC = wglGetCurrentDC();
            if (hDC != NULL) {
                SwapBuffers(hDC);
            } else {
                HWND hWnd = findHaxeWindow();
                if (hWnd != NULL) {
                    hDC = GetDC(hWnd);
                    if (hDC != NULL) {
                        SwapBuffers(hDC);
                        ReleaseDC(hWnd, hDC);
                    }
                }
            }
        ');
    }

    /**
     * v1.4: Configure the minimum window size enforced by the native modal
     * resize loop (WM_GETMINMAXINFO clamping in the temporary subclass).
     *
     * The C++ statics default to 640x400 even before this is called; use this
     * method to change the floor at runtime (for example from SettingsPanel
     * in the future). The Haxe-side fallback drag in ResizeGrip keeps its own
     * copy of the constants (ResizeGrip.MIN_WIDTH / MIN_HEIGHT).
     *
     * No-op on non-Windows platforms.
     *
     * @param w Minimum width in pixels (ignored if <= 0)
     * @param h Minimum height in pixels (ignored if <= 0)
     */
    public function setMinTrackSize(w:Int, h:Int):Void {
        #if windows
        untyped __cpp__("::_wc_setMinTrackSize((int){0}, (int){1});", w, h);
        #end
    }

    /**
     * v1.3: Screen-space cursor position (Windows; (-1,-1) elsewhere/failed).
     * Used by TitleBar/DevicePanel to reposition a restored window under
     * the cursor — the Windows 10 restore-before-drag UX: the user grabs
     * a fullscreen caption near the top of the screen, the window restores
     * to its saved rect, and instead of leaving the cursor stranded far
     * above the caption, the restored window slides so the cursor keeps
     * holding the caption at the same relative grab point.
     */
    public function getCursorPos():{x:Int, y:Int} {
        #if windows
        var x:Int = 0;
        var y:Int = 0;
        var ok:Bool = false;
        untyped __cpp__("{0} = (bool)::_wc_getCursorPos(&{1}, &{2});", ok, x, y);
        if (ok) return {x: x, y: y};
        #end
        return {x: -1, y: -1};
    }

    /**
     * v1.3: Called on every WM_SIZE while the native modal resize loop is
     * active (via the temporary window-proc subclass).
     *
     * WHY THIS EXISTS:
     * The Lime/SDL event pump is blocked inside the modal resize loop
     * (SendMessage has not returned yet), so SDL's size events pile up
     * unprocessed and the presented frame stays a frozen stretched image.
     *
     * WHAT WE DO:
     * 1. Push the fresh client size into Lime's cached window fields
     *    (window.width/height getters now return live values).
     * 2. Re-dispatch window.onResize manually — OpenFL listens to it and
     *    updates stage dimensions → Event.RESIZE → Main.onResize /
     *    layoutChrome → NodeEditor/DevicePanel/TitleBar re-layout.
     * 3. As a belt-and-suspenders measure also call stage.__resize()
     *    directly (guarded — exists in current OpenFL versions).
     *
     * Combined with the render tick (_onTick → SwapBuffers) this produces
     * LIVE resize feedback: content re-flows while the grip is dragged.
     *
     * After mouse-up, Lime finally pumps the queued SDL events and lands
     * on the same final size — consistent, no drift.
     */
    private static function _onLiveSize(w:Int, h:Int):Void {
        // Zero-size happens on minimize — ignore
        if (w <= 0 || h <= 0) return;

        try {
            var stage = openfl.Lib.current.stage;
            if (stage == null) return;
            var win = stage.window;
            if (win == null) return;

            // 1. Live size into Lime's cached fields
            untyped win.__width = w;
            untyped win.__height = h;

            // 2. Re-dispatch the resize signal
            // NOTE: lime Window.onResize is Event<Int->Int->Void> — dispatch
            // carries (width, height). Calling it with no args is a compile
            // error even under `untyped` (Haxe 4 still arity-checks calls).
            try untyped win.onResize.dispatch(w, h) catch (e:Dynamic) {}

            // 3. Direct OpenFL stage resize (guarded, idempotent)
            try untyped stage.__resize() catch (e:Dynamic) {}
        } catch (e:Dynamic) {
            // Degrade gracefully: frame stays stretched until mouse-up
        }
    }

    // =========================================================================
    // NATIVE CODE - Layered Window with Color Key
    // =========================================================================
    @:functionCode('
        #if defined(_WIN32)
            HWND hWnd = findHaxeWindow();
            char buf[512];

            if (hWnd == NULL) {
                debugLogNative("ERROR: Window handle is NULL");
                return false;
            }

            debugLogNative("=== ENABLE LAYERED WINDOW (Black=Transparent) ===");

            sprintf(buf, "Window: 0x%p", hWnd);
            debugLogNative(buf);

            LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if (!(exStyle & WS_EX_LAYERED)) {
                SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
                debugLogNative("Added WS_EX_LAYERED");
            }

            BOOL result = SetLayeredWindowAttributes(hWnd, 0xFF00FF, 255, LWA_COLORKEY);

            sprintf(buf, "SetLayeredWindowAttributes: %s", result ? "SUCCESS" : "FAILED");
            debugLogNative(buf);

            SetWindowPos(hWnd, NULL, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
            InvalidateRect(hWnd, NULL, TRUE);
            UpdateWindow(hWnd);

            g_transparencyEnabled = TRUE;

            debugLogNative("=== LAYERED WINDOW ENABLED ===");
            debugLogNative("BLACK (0x000000) = FULLY TRANSPARENT");
            debugLogNative("All other colors with alpha=1.0 = OPAQUE");

            return result != 0;
        #else
            return false;
        #endif
    ')
    private function _enableLayeredNative():Bool {
        return false;
    }

    @:functionCode('
        #if defined(_WIN32)
            HWND hWnd = findHaxeWindow();
            if (hWnd == NULL) return false;

            LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if (exStyle & WS_EX_LAYERED) {
                SetWindowLong(hWnd, GWL_EXSTYLE, exStyle & ~WS_EX_LAYERED);
            }

            SetWindowPos(hWnd, NULL, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
            InvalidateRect(hWnd, NULL, TRUE);

            g_transparencyEnabled = FALSE;
            debugLogNative("Layered window disabled");

            return true;
        #else
            return false;
        #endif
    ')
    private function _disableLayeredNative():Bool {
        return false;
    }

    @:functionCode('
        #if defined(_WIN32)
            HWND hWnd = findHaxeWindow();
            if (hWnd == NULL) return false;

            LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
            SetLayeredWindowAttributes(hWnd, 0, (BYTE)alpha, LWA_ALPHA);

            char buf[64];
            sprintf(buf, "Opacity set to %d", alpha);
            debugLogNative(buf);

            return true;
        #else
            return false;
        #endif
    ')
    private function _setOpacityNative(alpha:Int):Bool {
        return false;
    }

    @:functionCode('
        #if defined(_WIN32)
            HWND hWnd = findHaxeWindow();
            char buf[512];

            if (hWnd == NULL) {
                debugLogNative("ERROR: No window!");
                return;
            }

            debugLogNative("=== WINDOW DEBUG ===");

            sprintf(buf, "Handle: 0x%p", hWnd);
            debugLogNative(buf);

            char className[256] = {0};
            GetClassNameA(hWnd, className, 255);
            sprintf(buf, "Class: %s", className);
            debugLogNative(buf);

            LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            sprintf(buf, "ExStyle: 0x%lX", exStyle);
            debugLogNative(buf);

            sprintf(buf, "WS_EX_LAYERED: %s", (exStyle & WS_EX_LAYERED) ? "YES" : "NO");
            debugLogNative(buf);

            sprintf(buf, "Transparency enabled: %s", g_transparencyEnabled ? "YES" : "NO");
            debugLogNative(buf);

            debugLogNative("===================");
        #else
            // Stub for non-Windows
        #endif
    ')
    private function _debugNative():Void {}

    @:functionCode('
        #if defined(_WIN32)
            HWND hWnd = findHaxeWindow();
            if (hWnd == NULL) return false;

            LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if (!(exStyle & WS_EX_LAYERED)) {
                SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
            }

            DWM_BLURBEHIND bb;
            memset(&bb, 0, sizeof(bb));
            bb.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
            bb.fEnable = TRUE;
            bb.hRgnBlur = NULL;

            HRESULT hr = DwmEnableBlurBehindWindow(hWnd, &bb);

            char buf[64];
            sprintf(buf, "Blur: 0x%lX", (unsigned long)hr);
            debugLogNative(buf);

            InvalidateRect(hWnd, NULL, TRUE);

            return SUCCEEDED(hr);
        #else
            return false;
        #endif
    ')
    private function _enableBlurNative():Bool {
        return false;
    }

    @:functionCode('
        #if defined(_WIN32)
            const char* cstr = msg.__s;
            if (cstr == NULL) cstr = "(null)";
            debugLogNative(cstr);
        #else
            // Stub for non-Windows
        #endif
    ')
    private function debugLog(msg:String):Void {}

    #else
    public function enableLayeredTransparency():Bool return false;
    public function enableDWMTransparency():Bool return false;
    public function toggleTransparency():Bool return false;
    public function toggleBlurBehind():Bool return false;
    public function setOpacity(alpha:Int):Bool return false;
    public function debugWindowInfo():Void {}
    public function nativeStartDrag():Bool return false;
    public function nativeStartResize(edge:Int):Bool return false;
    public function minimize():Bool return false;
    public function maximize():Bool return false;
    public function restoreWindow():Bool return false;
    public function isZoomed():Bool return false;
    private function debugLog(msg:String):Void {}
    #end
}
