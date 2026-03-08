// =========================================================================
// THIS CLASS NOT USED IN APP. NEEDED FOR EXAMPLE FOR THE NATIVE EXTENSIONS
// =========================================================================
package ui.virtual;
import flash.display.Sprite;

@:headerCode('
extern "C" {
    void nativewindow_create(int width, int height, const char* title);
    void nativewindow_destroy();
	void nativewindow_updateFromSprite();
    void nativewindow_center();
}
')

@:cppFileCode('
#include <windows.h>
#include <windowsx.h>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

static HWND g_overlayHwnd = NULL;
static int g_overlayWidth = 400;
static int g_overlayHeight = 500;
static bool g_overlayDragging = false;
static int g_overlayDragStartX = 0;
static int g_overlayDragStartY = 0;
static int g_overlayWindowX = 0;
static int g_overlayWindowY = 0;

LRESULT CALLBACK OverlayWndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam);
void centerOverlayWindowImpl();

static HINSTANCE hInstance = (HINSTANCE)GetModuleHandle(NULL);

LRESULT CALLBACK OverlayWndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_CREATE:
            g_overlayHwnd = hWnd;
			SetLayeredWindowAttributes(hWnd, 0x000000, 255, LWA_COLORKEY); // window transparency
            centerOverlayWindowImpl();
            break;
            
        case WM_LBUTTONDOWN:
            g_overlayDragging = true;
            {
                RECT rect;
                GetWindowRect(hWnd, &rect);
                g_overlayWindowX = rect.left;
                g_overlayWindowY = rect.top;
                
                POINT pt;
                GetCursorPos(&pt);
                g_overlayDragStartX = pt.x;
                g_overlayDragStartY = pt.y;
                
                SetCapture(hWnd);
            }
            break;
            
        case WM_MOUSEMOVE:
            if (g_overlayDragging) {
                POINT pt;
                GetCursorPos(&pt);
                
                int dx = pt.x - g_overlayDragStartX;
                int dy = pt.y - g_overlayDragStartY;
                
                SetWindowPos(g_overlayHwnd, NULL, 
                    g_overlayWindowX + dx,
                    g_overlayWindowY + dy,
                    0, 0, SWP_NOSIZE | SWP_NOZORDER);
            }
            break;
            
        case WM_LBUTTONUP:
            g_overlayDragging = false;
            ReleaseCapture();
            break;
            
        case WM_CLOSE:
            DestroyWindow(g_overlayHwnd);
            g_overlayHwnd = NULL;
            break;
            
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
            
        default:
            return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

HWND createOverlayWindowImpl(int width, int height, const char* title) {
    g_overlayWidth = width;
    g_overlayHeight = height;
    
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = OverlayWndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"OverlayWindowClass";
    wc.hbrBackground = CreateSolidBrush(RGB(30, 30, 30));
    
    RegisterClassExW(&wc);
    
    wchar_t wtitle[256];
    MultiByteToWideChar(CP_UTF8, 0, title, -1, wtitle, 256);

    HWND hWnd = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOPMOST,
        L"OverlayWindowClass",
        wtitle,
        WS_POPUP | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT,
        width, height,
        NULL, NULL,
        hInstance,
        NULL
    );
    
    return hWnd;
}

void destroyOverlayWindowImpl() {
    if (g_overlayHwnd != NULL) {
        DestroyWindow(g_overlayHwnd);
        g_overlayHwnd = NULL;
    }
}

void nativewindow_updateFromSpriteImpl() {
    if (g_overlayHwnd == NULL) return;
}


void centerOverlayWindowImpl() {
    if (g_overlayHwnd == NULL) return;
    
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    
    g_overlayWindowX = (screenWidth - g_overlayWidth) / 2;
    g_overlayWindowY = (screenHeight - g_overlayHeight) / 2;
    
    SetWindowPos(g_overlayHwnd, NULL, g_overlayWindowX, g_overlayWindowY, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_SHOWWINDOW);
}

extern "C" {
    void nativewindow_create(int width, int height, const char* title) {
        createOverlayWindowImpl(width, height, title);
    }
    void nativewindow_destroy() {
        destroyOverlayWindowImpl();
    }
    void nativewindow_updateFromSprite() {
        nativewindow_updateFromSpriteImpl();
    }
    void nativewindow_center() {
        centerOverlayWindowImpl();
    }
}
')
class NativeWindowExtension {
    
    @:native("nativewindow_create")
    public static extern function createWindow(width:Int, height:Int, title:String):Void;
    
    @:native("nativewindow_destroy")
    public static extern function destroyWindow():Void;
    
    @:native("nativewindow_updateFromSprite")
    public static extern function updateFromSprite():Void;
	
    @:native("nativewindow_center")
    public static extern function centerWindow():Void;
    
    public function new() {}
}