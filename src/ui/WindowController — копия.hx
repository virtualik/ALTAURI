package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.Lib;
import lime.ui.Window;
import lime.system.System;

// =========================================================================
// WINDOWS HEADERS
// =========================================================================
@:cppFileCode('
#include <windows.h>
#include <dwmapi.h>
#include <stdio.h>
#include <string.h>
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

static HWND g_haxeWindow = NULL;
static bool g_dwmBlurEnabled = false;

static HWND findHaxeWindow() {
    if (g_haxeWindow != NULL) return g_haxeWindow;
    
    g_haxeWindow = GetActiveWindow();
    if (g_haxeWindow != NULL) return g_haxeWindow;
    
    g_haxeWindow = GetForegroundWindow();
    if (g_haxeWindow != NULL) return g_haxeWindow;
    
    g_haxeWindow = FindWindowW(L"HXCPP_WINDOW_CLASS", NULL);
    if (g_haxeWindow != NULL) return g_haxeWindow;
    
    g_haxeWindow = FindWindowW(L"SDL_app", NULL);
    
    return g_haxeWindow;
}

static void debugLog(const char* msg) {
    OutputDebugStringA(msg);
    OutputDebugStringA("\\n");
}
')
class WindowController {

    private var _window:Window;
    private var _isDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _windowStartX:Int = 0;
    private var _windowStartY:Int = 0;

    private var _transparentEnabled:Bool = false;
    private var _dwmEnabled:Bool = false;
    private var _colorKey:Int = 0x000000;

    public function new() {
        _window = Lib.current.stage.window;

        Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);

        trace("WindowController v3.0 initialized");
        trace("  F1: Toggle borderless");
        trace("  F2: Toggle fullscreen");
        trace("  F3: Center window");
        #if windows
        trace("  F4: Toggle DWM transparency (recommended)");
        trace("  F5: Toggle classic blur-behind");
        trace("  F6: Debug window info");
        trace("  F7: Set window opacity (50%)");
        #end
        trace("  F11: Toggle maximize");
    }

    // =========================================================================
    // TRANSPARENCY METHODS (Windows only)
    // =========================================================================

    #if windows

    /**
     * Enable DWM Extended Frame transparency.
     * This is the MODERN way to get transparency on Windows Vista/7/8/10/11.
     * Works with hardware-accelerated rendering (DirectX/OpenGL).
     */
    public function enableDWMTransparency():Bool {
        if (_dwmEnabled) return true;

        var result = _enableDWMTransparencyNative();
        
        if (result) {
            _dwmEnabled = true;
            _transparentEnabled = true;
            trace("DWM Transparency enabled - use alpha=0 for transparent areas");
        } else {
            trace("Failed to enable DWM transparency");
        }
        return result;
    }

    /**
     * Disable DWM transparency.
     */
    public function disableDWMTransparency():Bool {
        if (!_dwmEnabled) return true;

        var result = _disableDWMTransparencyNative();
        if (result) {
            _dwmEnabled = false;
            _transparentEnabled = false;
            trace("DWM Transparency disabled");
        }
        return result;
    }

    public function toggleTransparency():Bool {
        if (_dwmEnabled) {
            return disableDWMTransparency();
        } else {
            return enableDWMTransparency();
        }
    }

    /**
     * Legacy: Enable blur-behind effect.
     */
    public function enableBlurBehind():Bool {
        var result = _enableBlurBehindNative();
        if (result) {
            trace("Blur-behind enabled");
        } else {
            trace("Failed to enable blur-behind");
        }
        return result;
    }

    public function disableBlurBehind():Bool {
        var result = _disableBlurBehindNative();
        trace("Blur-behind disabled");
        return result;
    }

    public function toggleBlurBehind():Bool {
        return enableBlurBehind();
    }

    /**
     * Set window opacity (0-255).
     * This makes the ENTIRE window semi-transparent.
     */
    public function setOpacity(alpha:Int):Bool {
        if (alpha < 0) alpha = 0;
        if (alpha > 255) alpha = 255;
        return _setOpacityNative(alpha);
    }

    public function debugWindowInfo():Void {
        _debugWindowInfoNative();
    }

    // =========================================================================
    // NATIVE IMPLEMENTATIONS
    // =========================================================================

    /**
     * DWM Extended Frame - the modern transparency method.
     * Extends the "glass" effect into the client area.
     * On Windows 10/11, this enables true per-pixel alpha transparency.
     */
    @:functionCode('
        HWND hWnd = findHaxeWindow();
        char buf[512];
        
        if (hWnd == NULL) {
            debugLog("ERROR: Window handle is NULL!");
            return false;
        }

        debugLog("=== Enabling DWM Extended Frame ===");

        // Method 1: DwmExtendFrameIntoClientArea
        // This extends the window frame into the client area
        MARGINS margins = { -1, -1, -1, -1 }; // Extend to entire window
        
        HRESULT hr = DwmExtendFrameIntoClientArea(hWnd, &margins);
        sprintf(buf, "DwmExtendFrameIntoClientArea result: 0x%lX", (unsigned long)hr);
        debugLog(buf);
        
        if (FAILED(hr)) {
            debugLog("DwmExtendFrameIntoClientArea failed, trying alternative...");
        }

        // Method 2: Also set DWM_BLURBEHIND for compatibility
        DWM_BLURBEHIND bb;
        memset(&bb, 0, sizeof(bb));
        bb.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
        bb.fEnable = TRUE;
        bb.hRgnBlur = CreateRectRgn(0, 0, -1, -1);
        
        hr = DwmEnableBlurBehindWindow(hWnd, &bb);
        sprintf(buf, "DwmEnableBlurBehindWindow result: 0x%lX", (unsigned long)hr);
        debugLog(buf);

        // Method 3: Ensure WS_EX_LAYERED for alpha blending
        LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        if (!(exStyle & WS_EX_LAYERED)) {
            SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
            debugLog("Added WS_EX_LAYERED");
        }

        // Method 4: Use alpha blending (not color key)
        // Alpha = 255 means fully opaque, but individual pixels can have their own alpha
        SetLayeredWindowAttributes(hWnd, 0, 255, LWA_ALPHA);
        debugLog("Set alpha blending mode");

        // Force window redraw
        SetWindowPos(hWnd, NULL, 0, 0, 0, 0, 
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        InvalidateRect(hWnd, NULL, TRUE);
        
        debugLog("DWM Transparency enabled successfully");
        debugLog("NOTE: Draw with alpha=0 for transparent pixels!");
        
        return true;
    ')
    private function _enableDWMTransparencyNative():Bool {
        return false;
    }

    @:functionCode('
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;

        // Reset margins
        MARGINS margins = { 0, 0, 0, 0 };
        DwmExtendFrameIntoClientArea(hWnd, &margins);

        // Disable blur-behind
        DWM_BLURBEHIND bb;
        memset(&bb, 0, sizeof(bb));
        bb.dwFlags = DWM_BB_ENABLE;
        bb.fEnable = FALSE;
        DwmEnableBlurBehindWindow(hWnd, &bb);

        // Force redraw
        SetWindowPos(hWnd, NULL, 0, 0, 0, 0, 
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        
        return true;
    ')
    private function _disableDWMTransparencyNative():Bool {
        return false;
    }

    @:functionCode('
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;

        DWM_BLURBEHIND bb;
        memset(&bb, 0, sizeof(bb));
        bb.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
        bb.fEnable = TRUE;
        bb.hRgnBlur = CreateRectRgn(0, 0, -1, -1);

        HRESULT hr = DwmEnableBlurBehindWindow(hWnd, &bb);

        char buf[256];
        sprintf(buf, "BlurBehind result: 0x%lX", (unsigned long)hr);
        debugLog(buf);

        return SUCCEEDED(hr);
    ')
    private function _enableBlurBehindNative():Bool {
        return false;
    }

    @:functionCode('
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;

        DWM_BLURBEHIND bb;
        memset(&bb, 0, sizeof(bb));
        bb.dwFlags = DWM_BB_ENABLE;
        bb.fEnable = FALSE;

        DwmEnableBlurBehindWindow(hWnd, &bb);
        return true;
    ')
    private function _disableBlurBehindNative():Bool {
        return false;
    }

    @:functionCode('
        HWND hWnd = findHaxeWindow();
        if (hWnd == NULL) return false;

        LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        if (!(exStyle & WS_EX_LAYERED)) {
            SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
        }

        BYTE bAlpha = (BYTE)alpha;
        BOOL result = SetLayeredWindowAttributes(hWnd, 0, bAlpha, LWA_ALPHA);

        char buf[128];
        sprintf(buf, "SetOpacity(%d) result: %d", alpha, result);
        debugLog(buf);

        return result == TRUE;
    ')
    private function _setOpacityNative(alpha:Int):Bool {
        return false;
    }

    @:functionCode('
        HWND hWnd = findHaxeWindow();
        char buf[512];
        
        if (hWnd == NULL) {
            debugLog("=== WINDOW DEBUG: No window found! ===");
            return;
        }
        
        debugLog("=== WINDOW DEBUG INFO ===");
        
        sprintf(buf, "Window Handle: 0x%p", hWnd);
        debugLog(buf);
        
        LONG style = GetWindowLong(hWnd, GWL_STYLE);
        sprintf(buf, "Style: 0x%lX", style);
        debugLog(buf);
        
        LONG exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        sprintf(buf, "Extended Style: 0x%lX", exStyle);
        debugLog(buf);
        
        sprintf(buf, "WS_EX_LAYERED: %s", (exStyle & WS_EX_LAYERED) ? "YES" : "NO");
        debugLog(buf);
        
        sprintf(buf, "WS_EX_TOPMOST: %s", (exStyle & WS_EX_TOPMOST) ? "YES" : "NO");
        debugLog(buf);
        
        RECT rect;
        GetWindowRect(hWnd, &rect);
        sprintf(buf, "Window Rect: %ld, %ld, %ld, %ld", rect.left, rect.top, rect.right, rect.bottom);
        debugLog(buf);
        
        char title[256];
        GetWindowTextA(hWnd, title, 256);
        sprintf(buf, "Window Title: %s", title);
        debugLog(buf);
        
        // Check Windows version
        DWORD build = 0;
        typedef NTSTATUS(WINAPI* RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
        HMODULE hNtDll = GetModuleHandleW(L"ntdll.dll");
        if (hNtDll) {
            RtlGetVersionPtr pRtlGetVersion = (RtlGetVersionPtr)GetProcAddress(hNtDll, "RtlGetVersion");
            if (pRtlGetVersion) {
                RTL_OSVERSIONINFOW info = { sizeof(info) };
                pRtlGetVersion(&info);
                sprintf(buf, "Windows Version: %lu.%lu (Build %lu)", info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber);
                debugLog(buf);
            }
        }
        
        debugLog("=========================");
    ')
    private function _debugWindowInfoNative():Void {}

    #else

    public function enableDWMTransparency():Bool return false;
    public function disableDWMTransparency():Bool return false;
    public function toggleTransparency():Bool return false;
    public function enableBlurBehind():Bool return false;
    public function disableBlurBehind():Bool return false;
    public function toggleBlurBehind():Bool return false;
    public function setOpacity(alpha:Int):Bool return false;
    public function debugWindowInfo():Void {}

    #end

    // =========================================================================
    // STANDARD WINDOW METHODS
    // =========================================================================

    public function toggleBorderless():Void {
        _window.borderless = !_window.borderless;
        trace("Borderless: " + _window.borderless);
    }

    public function toggleFullscreen():Void {
        _window.fullscreen = !_window.fullscreen;
        trace("Fullscreen: " + _window.fullscreen);
    }

    public function toggleMaximize():Void {
        _window.maximized = !_window.maximized;
        trace("Maximized: " + _window.maximized);
    }

    public function minimize():Void {
        _window.minimized = true;
        trace("Minimized");
    }

    public function restore():Void {
        _window.minimized = false;
        _window.maximized = false;
        trace("Restored");
    }

    public function centerWindow():Void {
        var display = System.getDisplay(0);
        if (display != null) {
            var displayWidth = Std.int(display.bounds.width);
            var displayHeight = Std.int(display.bounds.height);
            _window.x = Std.int((displayWidth - _window.width) / 2);
            _window.y = Std.int((displayHeight - _window.height) / 2);
            trace("Window centered at: " + _window.x + ", " + _window.y);
        }
    }

    public function setPosition(x:Int, y:Int):Void {
        _window.x = x;
        _window.y = y;
    }

    public function setSize(width:Int, height:Int):Void {
        _window.width = width;
        _window.height = height;
    }

    public function getState():WindowState {
        return {
            x: _window.x,
            y: _window.y,
            width: _window.width,
            height: _window.height,
            borderless: _window.borderless,
            fullscreen: _window.fullscreen,
            maximized: _window.maximized,
            minimized: _window.minimized,
            visible: _window.visible,
            transparent: _transparentEnabled,
            dwmEnabled: _dwmEnabled
        };
    }

    public function printInfo():Void {
        trace("=== Window Info ===");
        trace("Position: " + _window.x + ", " + _window.y);
        trace("Size: " + _window.width + " x " + _window.height);
        trace("Borderless: " + _window.borderless);
        trace("Fullscreen: " + _window.fullscreen);
        #if windows
        trace("DWM Transparency: " + _dwmEnabled);
        debugWindowInfo();
        #end
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.target != Lib.current.stage) return;

        switch (e.keyCode) {
            case Keyboard.F1:
                toggleBorderless();

            case Keyboard.F2:
                toggleFullscreen();

            case Keyboard.F3:
                centerWindow();

            #if windows
            case Keyboard.F4:
                toggleTransparency();

            case Keyboard.F5:
                toggleBlurBehind();
                
            case Keyboard.F6:
                debugWindowInfo();
                
            case Keyboard.F7:
                setOpacity(128); // 50% opacity
                trace("Set window opacity to 50%");
            #end

            case Keyboard.F11:
                toggleMaximize();
        }
    }

    private function onMouseDown(e:MouseEvent):Void {
        if (!_window.borderless) return;
        if (e.stageY > 40) return;

        _isDragging = true;
        _dragStartX = e.stageX;
        _dragStartY = e.stageY;
        _windowStartX = _window.x;
        _windowStartY = _window.y;
    }

    private function onMouseUp(e:MouseEvent):Void {
        _isDragging = false;
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (!_isDragging) return;

        var dx = e.stageX - _dragStartX;
        var dy = e.stageY - _dragStartY;

        _window.x = Std.int(_windowStartX + dx);
        _window.y = Std.int(_windowStartY + dy);
    }
}

typedef WindowState = {
    x:Int,
    y:Int,
    width:Int,
    height:Int,
    borderless:Bool,
    fullscreen:Bool,
    maximized:Bool,
    minimized:Bool,
    visible:Bool,
    ?transparent:Bool,
    ?dwmEnabled:Bool
};
