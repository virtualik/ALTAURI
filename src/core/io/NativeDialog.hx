package core.io;

// ============================================================================
// NativeDialog v1.1 - native file selection dialogs (Stage 3 -> Stage 4a-1)
// v1.0.1 (Task 137/138): saveFile(title, defaultName, initialDir) for the
//   [P] Export button (GetSaveFileNameW); the module lives in src/core/io
//   (package == file path). The Main.hx call is UNCHANGED: three positional
//   arguments, empty filter/defaultExt = built-in exe filter and defExt (the
//   byte-level behavior of Stage 3 is preserved).
// v1.1 (Task 141): + openFile(title, filter, initialDir) — GetOpenFileNameW
//   for FileReaderAtom; + a parameterized format filter
//   "Name|mask;mask|Name|mask" (compatible with the lime format); + defaultExt for
//   saveFile; + isSupported(). REASON: FileWriter v1.2 / FileReader v1.0 called
//   lime.ui.FileDialog.browseForSave/browseForOpen - methods that do not exist in
//   the REAL Station library (an invention of Task 140; the Z bench compiled the
//   atoms against its own fake with the same invented API - the Super A compiler
//   caught it). The atoms were moved onto THIS bridge: our code, our version.
// ----------------------------------------------------------------------------
// WinAPI comdlg32 - native bridge idioms from the battles of Stages 0.x (DevicePanel
// v3.7: @:headerCode/@:cppFileCode + untyped __cpp__; NETRadioPlayer:
// "(const char*){N}.__s" for strings INTO native, "{N} = ::String(...)" FOR return).
//
// DIALOG PROPERTIES (deliberate decisions):
//   - MODAL to the running editor window (hwndOwner = the found main
//     window of the process); the call BLOCKS the thread until the dialog closes: the
//     OpenFL render loop stands, audio (native driver threads) keeps playing. The dialog is brief -
//     v1 accepts the pause (precedent: [P] Export, accepted by the Station in Stage 3).
//   - OFN_NOCHANGEDIR - the dialog is FORBIDDEN to change the process working directory
//     (PathCanon builds relative paths from the CWD).
//   - saveFile: OFN_OVERWRITEPROMPT - overwrite is asked natively;
//     lpstrDefExt - a name without an extension gets a default (txt for the Writer,
//     exe for the instrument export).
//   - openFile: OFN_FILEMUSTEXIST|OFN_PATHMUSTEXIST - only an
//     existing file can be selected (the Reader will not open a phantom).
//   - Return: a path (UTF-8) or null (cancel/error/not-Windows).
//     v1 honesty: cancel and a system error are indistinguishable - both mean
//     "no path", a silent exit with no side effects.
//
// ENCODINGS: Haxe strings UTF-8 -> MultiByteToWideChar(CP_UTF8) -> UTF-16 for
// the API; the result - WideCharToMultiByte(CP_UTF8) into the STATIC buffer
// _nd_resultPath[4096] (eternal storage: safe under any copy semantics
// of ::String(const char*)).
//
// FILTER: the format "Name|mask;mask|Name|mask" (| = pair separator,
// ; = mask separator inside a pair) is expanded by a C helper into
// double-NUL-terminated UTF-16 (the comdlg32 contract). An empty filter =
// the built-in default: saveFile - the v1.0.1 exe filter, openFile - All files.
//
// RESTRAINED API: saveFile/openFile/isSupported. Dialog titles are ASCII
// (lab discipline: Cyrillic does not live in the console; path and name are
// Unicode). The dialogs are SINGLE-FILE (OFN_ALLOWMULTISELECT is not set -
// multiselect awaits its era).
// ============================================================================

#if windows
@:headerCode('
#ifdef _WIN32
extern "C" {
    int _nd_saveDialog(const char* inTitle, const char* inDefaultName, const char* inInitialDir, const char* inFilter, const char* inDefExt);
    int _nd_openDialog(const char* inTitle, const char* inFilter, const char* inInitialDir);
}
#endif
')
@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>
#include <wchar.h>
#include <string.h>
#pragma comment(lib, "comdlg32.lib")
// =========================================================================
// Eternal storage of the result: static - survives the call under any
// copy semantics of ::String(const char*) (hxcpp lessons).
// =========================================================================
static char _nd_resultPath[4096];
// UTF-8 (Haxe) -> UTF-16 (WinAPI) with overflow protection.
static void _nd_utf8To16(const char* in, wchar_t* out, int cap) {
    out[0] = 0;
    if (in == NULL) return;
    if (MultiByteToWideChar(CP_UTF8, 0, in, -1, out, cap) <= 0) out[0] = 0;
}
// Dialog result: UTF-16 -> UTF-8 into the eternal buffer.
// Return: 1 = path written, -1 = result buffer overflow.
static int _nd_storeResult(const wchar_t* w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 0 || n >= (int)sizeof(_nd_resultPath)) return -1;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, _nd_resultPath, n, NULL, NULL);
    return 1;
}
// v1.1: the filter "Name|mask;mask|Name|mask" (UTF-8, code 124 = "|") ->
// double-NUL-terminated UTF-16 (the comdlg32 contract). Return: 1 = written,
// 0 = input empty/damaged (the caller sets its own default).
// NOTE: there are no literal single quotes here - the code lives inside
// a single-quoted Haxe string of @:cppFileCode.
static int _nd_buildFilterW(const char* in, wchar_t* out, int cap) {
    if (in == NULL || in[0] == 0) return 0;
    int n = 0;
    const char* start = in;
    const char* p = in;
    while (1) {
        if (*p == 0 || *p == (char)124) {
            int segLen = (int)(p - start);
            if (segLen > 0) {
                if (segLen > 511) return 0;
                if (n + segLen + 2 > cap) return 0;
                char buf[512];
                for (int i = 0; i < segLen; i++) buf[i] = start[i];
                buf[segLen] = 0;
                wchar_t tmp[512];
                _nd_utf8To16(buf, tmp, 512);
                int L = (int)wcslen(tmp);
                for (int i = 0; i < L; i++) out[n++] = tmp[i];
                out[n++] = 0;
            }
            if (*p == 0) break;
            start = p + 1;
        }
        p++;
    }
    if (n == 0) return 0;
    out[n] = 0; // the second NUL of the double termination (the first came from the last segment)
    return 1;
}
// Find the main Haxe/OpenFL window by process ID.
// NOTE: the API is GetWindowThreadProcessId — it returns the thread id AND
// optionally writes the process id through the second parameter. There is
// no "GetWindowThreadId" in the Windows SDK (an old paste carried that
// phantom name, which breaks MSVC with C3861).
// (a copy of _dp_findMainWindow from DevicePanel v3.7 - verified by the Station)
static HWND _nd_findMainWindow() {
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
// Modal save dialog. Return: 1 = path selected (in _nd_resultPath),
// 0 = cancel/closed/system error, -1 = result buffer overflow.
// v1.1: filter and defExt are parameters; empty = v1.0.1 defaults (exe filter,
// defExt "exe") - the Stage 3 Main.hx call has not changed a byte of behavior.
int _nd_saveDialog(const char* inTitle, const char* inDefaultName, const char* inInitialDir, const char* inFilter, const char* inDefExt) {
    _nd_resultPath[0] = (char)0;

    wchar_t wTitle[256];
    wchar_t wDir[1024];
    wchar_t wFile[1024];
    wchar_t wFilter[1024];
    wchar_t wDefExt[32];
    _nd_utf8To16(inTitle, wTitle, 256);
    _nd_utf8To16(inInitialDir, wDir, 1024);
    _nd_utf8To16(inDefaultName, wFile, 1024);
    _nd_utf8To16(inDefExt, wDefExt, 32);

    // Default filter v1.0.1 (double NUL termination - the comdlg32 contract).
    wchar_t wFilterDefault[] = L"Executable (*.exe)\\0*.exe\\0All files (*.*)\\0*.*\\0";

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = _nd_findMainWindow();   // modal to the editor window
    ofn.lpstrFilter = _nd_buildFilterW(inFilter, wFilter, 1024) ? wFilter : wFilterDefault;
    ofn.lpstrFile = wFile;                  // pre-filled with the default name
    ofn.nMaxFile = 1024;
    ofn.lpstrTitle = (inTitle != NULL && inTitle[0]) ? wTitle : NULL;
    ofn.lpstrInitialDir = (inInitialDir != NULL && inInitialDir[0]) ? wDir : NULL;
    ofn.lpstrDefExt = (inDefExt != NULL && inDefExt[0]) ? wDefExt : L"exe";
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY
              | OFN_NOCHANGEDIR | OFN_EXPLORER;

    if (!GetSaveFileNameW(&ofn)) return 0;  // cancel or error - no path

    return _nd_storeResult(wFile);
}
// v1.1: Modal dialog for opening an existing file (GetOpenFileNameW).
// Return: same as save. No defExt (reading, not creating), no
// name pre-filling; OFN_FILEMUSTEXIST - no phantoms selectable.
int _nd_openDialog(const char* inTitle, const char* inFilter, const char* inInitialDir) {
    _nd_resultPath[0] = (char)0;

    wchar_t wTitle[256];
    wchar_t wDir[1024];
    wchar_t wFile[4096];
    wchar_t wFilter[1024];
    _nd_utf8To16(inTitle, wTitle, 256);
    _nd_utf8To16(inInitialDir, wDir, 1024);
    wFile[0] = 0;

    wchar_t wFilterDefault[] = L"All files (*.*)\\0*.*\\0";

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = _nd_findMainWindow();
    ofn.lpstrFilter = _nd_buildFilterW(inFilter, wFilter, 1024) ? wFilter : wFilterDefault;
    ofn.lpstrFile = wFile;
    ofn.nMaxFile = 4096;
    ofn.lpstrTitle = (inTitle != NULL && inTitle[0]) ? wTitle : NULL;
    ofn.lpstrInitialDir = (inInitialDir != NULL && inInitialDir[0]) ? wDir : NULL;
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY
              | OFN_NOCHANGEDIR | OFN_EXPLORER;

    if (!GetOpenFileNameW(&ofn)) return 0;

    return _nd_storeResult(wFile);
}
}
#endif
')
#end
/**
 * NATIVE DIALOG v1.1 (Stage 3, Tasks 137-138 + 141)
 * Bridge to WinAPI comdlg32: saveFile(title, defaultName, initialDir, filter,
 * defaultExt) / openFile(title, filter, initialDir) / isSupported().
 * MODAL (hwndOwner = the main window), OFN_NOCHANGEDIR; the return is a path
 * UTF-8 or null (cancel/error/not-Windows are indistinguishable, v1 honesty).
 * Replacement for the invented lime.ui.FileDialog API (lesson of Task 141).
 * Detailed specification - in the // banner of the file.
 */
class NativeDialog
{
        /**
         * Whether a native dialog exists on this target.
         * Windows (cpp) = true; everything else (html5 etc.) = false.
         * Atoms call this BEFORE the dialog, to honestly refuse outside Windows.
         */
        public static function isSupported():Bool
        {
                #if windows
                return true;
                #else
                return false;
                #end
        }

        /**
         * Modal "Save as..." dialog (Windows).
         * BLOCKS the calling thread until the dialog closes (the render stands,
         * audio plays - the [P] Export precedent, Stage 3).
         * Returns ONLY the path - writes nothing to disk.
         * @param title       the dialog window title ("" = standard)
         * @param defaultName the pre-filled file name ("Device.exe")
         * @param initialDir  the starting directory ("" = system default)
         * @param filterText  the filter "Name|mask;mask|..." ("" = the exe default
         *                    v1.0.1 - Main.hx behavior unchanged)
         * @param defaultExt  the default extension ("" = "exe", v1.0.1)
         * @return the selected FULL path (UTF-8) or null - cancel/error/
         *         a non-Windows target
         */
        public static function saveFile(title:String, defaultName:String,
                        initialDir:String, ?filterText:String = null,
                        ?defaultExt:String = null):Null<String>
        {
                #if windows
                if (title == null) title = "";
                if (defaultName == null) defaultName = "";
                if (initialDir == null) initialDir = "";
                if (filterText == null) filterText = "";
                if (defaultExt == null) defaultExt = "";
                var picked:Int = 0;
                var resultPath:String = null;
                untyped __cpp__('
                        {0} = (int)::_nd_saveDialog((const char*){1}.__s, (const char*){2}.__s, (const char*){3}.__s, (const char*){4}.__s, (const char*){5}.__s);
                        if ({0} == 1) { {6} = ::String((const char*)::_nd_resultPath); }
                ', picked, title, defaultName, initialDir, filterText, defaultExt, resultPath);
                return resultPath;
                #else
                return null;
                #end
        }

        /**
         * Modal "Open file..." dialog (Windows), v1.1.
         * BLOCKS the calling thread until the dialog closes.
         * OFN_FILEMUSTEXIST: only an existing file can be selected.
         * Returns ONLY the path - reads nothing from disk.
         * @param title      the dialog window title ("" = standard)
         * @param filterText the filter "Name|mask;mask|..." ("" = All files)
         * @param initialDir the starting directory ("" = system default)
         * @return the selected FULL path (UTF-8) or null - cancel/error/
         *         a non-Windows target
         */
        public static function openFile(title:String, ?filterText:String = null,
                        ?initialDir:String = null):Null<String>
        {
                #if windows
                if (title == null) title = "";
                if (filterText == null) filterText = "";
                if (initialDir == null) initialDir = "";
                var picked:Int = 0;
                var resultPath:String = null;
                untyped __cpp__('
                        {0} = (int)::_nd_openDialog((const char*){1}.__s, (const char*){2}.__s, (const char*){3}.__s);
                        if ({0} == 1) { {4} = ::String((const char*)::_nd_resultPath); }
                ', picked, title, filterText, initialDir, resultPath);
                return resultPath;
                #else
                return null;
                #end
        }
}

