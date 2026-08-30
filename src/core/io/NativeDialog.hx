package core.io;

// ============================================================================
// NativeDialog v1.0 — нативный диалог сохранения файла (Этап 3, Task 137)
// ----------------------------------------------------------------------------
// WinAPI GetSaveFileNameW (comdlg32) — модальный диалог выбора пути для
// кнопки [P] Export. Идиомы нативного моста — с боя Этапов 0.x (DevicePanel
// v3.7: @:headerCode/@:cppFileCode + untyped __cpp__; NETRadioPlayer:
// «(const char*){N}.__s» для строк В натив, «{N} = ::String(...)» ДЛЯ возврата).
//
// СВОЙСТВА ДИАЛОГА (осознанные решения):
//   · МОДАЛЬНЫЙ работающему окну редактора (hwndOwner = найденное главное
//     окно процесса — прецедент _dp_findMainWindow); вызов БЛОКИРУЕТ поток
//     до закрытия диалога: рендер-цикл OpenFL стоит, аудио (нативные потоки
//     драйверов) играет. Диалог краток — v1 принимает паузу; инъекция
//     тиков (как при нативном drag'е) не делается: накопленная очередь
//     событий разрядится после закрытия диалога.
//   · OFN_NOCHANGEDIR — диалогу ЗАПРЕЩЕНО менять рабочий каталог процесса:
//     PathCanon строит относительные пути от CWD, мутация CWD посреди сеанса
//     была бы миной (и ломала бы относительную семантику --pack).
//   · OFN_OVERWRITEPROMPT — перезапись существующего файла спрашивается
//     нативно (наш guard не дублирует вопрос).
//   · lpstrDefExt = "exe" — имя без расширения получает ".exe".
//   · Возврат: путь (UTF-8) или null (отмена/ошибка/не-Windows).
//     v1-честность: отмена и системная ошибка неразличимы — обе значат
//     «пути нет», молчаливый выход без побочных эффектов.
//
// КОДИРОВКИ: Haxe-строки UTF-8 → MultiByteToWideChar(CP_UTF8) → UTF-16 для
// API; результат — WideCharToMultiByte(CP_UTF8) в СТАТИЧЕСКИЙ буфер
// _nd_resultPath[4096] (вечное хранилище: безопасен при любой семантике
// копирования ::String(const char*)).
//
// СДЕРЖАННЫЙ API: один метод saveFile(title, defaultName, initialDir).
// Заголовок диалога — ASCII (дисциплина лаборатории: кириллица в консоли
// не живёт, а исходник в чужой кодировке — риск; путь и имя — Unicode).
// ============================================================================

#if windows
@:headerCode('
#ifdef _WIN32
extern "C" {
    int _nd_saveDialog(const char* inTitle, const char* inDefaultName, const char* inInitialDir);
}
#endif
')
@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>
#pragma comment(lib, "comdlg32.lib")
// =========================================================================
// Вечное хранилище результата: static — переживает вызов при любой
// семантике копирования ::String(const char*) (уроки hxcpp).
// =========================================================================
static char _nd_resultPath[4096];
// UTF-8 (Haxe) → UTF-16 (WinAPI) с защитой от переполнения.
static void _nd_utf8To16(const char* in, wchar_t* out, int cap) {
    out[0] = 0;
    if (in == NULL) return;
    if (MultiByteToWideChar(CP_UTF8, 0, in, -1, out, cap) <= 0) out[0] = 0;
}
// Find the main Haxe/OpenFL window by process ID.
// NOTE: the API is GetWindowThreadProcessId — it returns the thread id AND
// optionally writes the process id through the second parameter. There is
// no "GetWindowThreadId" in the Windows SDK (an old paste carried that
// phantom name, which breaks MSVC with C3861).
// (копия _dp_findMainWindow из DevicePanel v3.7 — проверено Станцией)
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
// Модальный диалог сохранения. Возврат: 1 = путь выбран (в _nd_resultPath),
// 0 = отмена/закрыто/системная ошибка, -1 = переполнение буфера результата.
int _nd_saveDialog(const char* inTitle, const char* inDefaultName, const char* inInitialDir) {
    _nd_resultPath[0] = (char)0;

    wchar_t wTitle[256];
    wchar_t wDir[1024];
    wchar_t wFile[1024];
    _nd_utf8To16(inTitle, wTitle, 256);
    _nd_utf8To16(inInitialDir, wDir, 1024);
    _nd_utf8To16(inDefaultName, wFile, 1024);

    // Фильтр: двойное NUL-завершение обязательно (comdlg32-контракт).
    wchar_t filter[] = L"Executable (*.exe)\\0*.exe\\0All files (*.*)\\0*.*\\0";

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = _nd_findMainWindow();   // модально окну редактора
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = wFile;                  // предзаполнено именем по умолчанию
    ofn.nMaxFile = 1024;
    ofn.lpstrTitle = (inTitle != NULL && inTitle[0]) ? wTitle : NULL;
    ofn.lpstrInitialDir = (inInitialDir != NULL && inInitialDir[0]) ? wDir : NULL;
    ofn.lpstrDefExt = L"exe";               // без расширения → ".exe"
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY
              | OFN_NOCHANGEDIR | OFN_EXPLORER;

    if (!GetSaveFileNameW(&ofn)) return 0;  // отмена или ошибка — путя нет

    // UTF-16 → UTF-8 в вечный буфер
    int n = WideCharToMultiByte(CP_UTF8, 0, wFile, -1, NULL, 0, NULL, NULL);
    if (n <= 0 || n >= (int)sizeof(_nd_resultPath)) return -1;
    WideCharToMultiByte(CP_UTF8, 0, wFile, -1, _nd_resultPath, n, NULL, NULL);
    return 1;
}
}
#endif
')
#end
class NativeDialog
{
        /**
         * Модальный диалог «Сохранить как…» (Windows).
         * БЛОКИРУЕТ вызывающий поток до закрытия диалога.
         * @param title       заголовок окна диалога ("" = стандартный)
         * @param defaultName предзаполненное имя файла ("Device.exe")
         * @param initialDir  стартовый каталог (папка работающего exe)
         * @return выбранный ПОЛНЫЙ путь (UTF-8) или null — отмена/ошибка/
         *         не-Windows таргет (html5 и пр.)
         */
        public static function saveFile(title:String, defaultName:String,
                        initialDir:String):Null<String>
        {
                #if windows
                if (title == null) title = "";
                if (defaultName == null) defaultName = "";
                if (initialDir == null) initialDir = "";
                var picked:Int = 0;
                var resultPath:String = null;
                untyped __cpp__('
                        {0} = (int)::_nd_saveDialog((const char*){1}.__s, (const char*){2}.__s, (const char*){3}.__s);
                        if ({0} == 1) { {4} = ::String((const char*)::_nd_resultPath); }
                ', picked, title, defaultName, initialDir, resultPath);
                return resultPath;
                #else
                return null;
                #end
        }
}
