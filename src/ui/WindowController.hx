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
#endif
')
class WindowController {
    private var _window:Window;
    private var _dwmEnabled:Bool = false;
   
    public function new() {
        _window = Lib.current.stage.window;
        debugLog("WindowController initialized");
        debugLog("F4=Toggle F5=Blur F6=Debug F7=Opacity");
        debugLog("NOTE: Black pixels (0x000000) become transparent!");
        debugLog("Other colors with alpha=1.0 are OPAQUE");
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
    private function debugLog(msg:String):Void {}
    #end
}