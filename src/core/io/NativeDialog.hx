package core.io;

// ============================================================================
// NativeDialog v1.1 — нативные диалоги выбора файла (Этап 3 → Этап 4a-1)
// v1.0.1 (Task 137/138): saveFile(title, defaultName, initialDir) для кнопки
//   [P] Export (GetSaveFileNameW); модуль живёт в src/core/io (package ==
//   путь файла). Вызов Main.hx НЕ ИЗМЕНИЛСЯ: три позиционных аргумента,
//   пустые filter/defaultExt = встроенные exe-фильтр и defExt (байтовое
//   поведение Этапа 3 сохранено).
// v1.1 (Task 141): + openFile(title, filter, initialDir) — GetOpenFileNameW
//   для FileReaderAtom; + параметризованный фильтр формата
//   «Имя|маска;маска|Имя|маска» (совместим с lime-форматом); + defaultExt у
//   saveFile; + isSupported(). ПОВОД: FileWriter v1.2/FileReader v1.0 звали
//   lime.ui.FileDialog.browseForSave/browseForOpen — методов, которых в
//   РЕАЛЬНОЙ библиотеке Станции нет (выдумка Task 140; Z-стенд компиллил
//   атомы против собственного фейка с тем же выдуманным API — компилятор
//   Super A поймал). Атомы переведены на ЭТОТ мост: наш код, наша версия.
// ----------------------------------------------------------------------------
// WinAPI comdlg32 — идиомы нативного моста с боя Этапов 0.x (DevicePanel
// v3.7: @:headerCode/@:cppFileCode + untyped __cpp__; NETRadioPlayer:
// «(const char*){N}.__s» для строк В натив, «{N} = ::String(...)» ДЛЯ возврата).
//
// СВОЙСТВА ДИАЛОГОВ (осознанные решения):
//   · МОДАЛЬНЫЕ работающему окну редактора (hwndOwner = найденное главное
//     окно процесса); вызов БЛОКИРУЕТ поток до закрытия диалога: рендер-цикл
//     OpenFL стоит, аудио (нативные потоки драйверов) играет. Диалог краток —
//     v1 принимает паузу (прецедент: [P] Export, принят Станцией в Этапе 3).
//   · OFN_NOCHANGEDIR — диалогу ЗАПРЕЩЕНО менять рабочий каталог процесса
//     (PathCanon строит относительные пути от CWD).
//   · saveFile: OFN_OVERWRITEPROMPT — перезапись спрашивается нативно;
//     lpstrDefExt — имя без расширения получает дефолт (txt у Писателя,
//     exe у экспорта прибора).
//   · openFile: OFN_FILEMUSTEXIST|OFN_PATHMUSTEXIST — выбрать можно только
//     существующий файл (Читатель не откроет фантом).
//   · Возврат: путь (UTF-8) или null (отмена/ошибка/не-Windows).
//     v1-честность: отмена и системная ошибка неразличимы — обе значат
//     «пути нет», молчаливый выход без побочных эффектов.
//
// КОДИРОВКИ: Haxe-строки UTF-8 → MultiByteToWideChar(CP_UTF8) → UTF-16 для
// API; результат — WideCharToMultiByte(CP_UTF8) в СТАТИЧЕСКИЙ буфер
// _nd_resultPath[4096] (вечное хранилище: безопасен при любой семантике
// копирования ::String(const char*)).
//
// ФИЛЬТР: формат «Имя|маска;маска|Имя|маска» (| = разделитель пар,
// ; = разделитель масок внутри пары) разворачивается C-хелпером в
// double-NUL-terminated UTF-16 (контракт comdlg32). Пустой фильтр =
// встроенный дефолт: saveFile — exe-фильтр v1.0.1, openFile — All files.
//
// СДЕРЖАННЫЙ API: saveFile/openFile/isSupported. Заголовки диалогов — ASCII
// (дисциплина лаборатории: кириллица в консоли не живёт; путь и имя —
// Unicode). Диалоги ОДНОФАЙЛОВЫЕ (OFN_ALLOWMULTISELECT не ставится —
// мультивыбор ждёт своей эпохи).
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
// Результат диалога: UTF-16 → UTF-8 в вечный буфер.
// Возврат: 1 = путь записан, -1 = переполнение буфера результата.
static int _nd_storeResult(const wchar_t* w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 0 || n >= (int)sizeof(_nd_resultPath)) return -1;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, _nd_resultPath, n, NULL, NULL);
    return 1;
}
// v1.1: фильтр «Имя|маска;маска|Имя|маска» (UTF-8, код 124 = "|") →
// double-NUL-terminated UTF-16 (контракт comdlg32). Возврат: 1 = записан,
// 0 = вход пуст/повреждён (вызывающий ставит свой дефолт).
// ПРИМЕЧАНИЕ: литеральных одинарных кавычек здесь нет — код живёт внутри
// одинарной Haxe-строки @:cppFileCode.
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
    out[n] = 0; // второе NUL двойного завершения (первое дал последний сегмент)
    return 1;
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
// v1.1: фильтр и defExt — параметры; пустые = дефолты v1.0.1 (exe-фильтр,
// defExt "exe") — вызов Main.hx Этапа 3 не изменился ни на байт поведения.
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

    // Дефолтный фильтр v1.0.1 (двойное NUL-завершение — контракт comdlg32).
    wchar_t wFilterDefault[] = L"Executable (*.exe)\\0*.exe\\0All files (*.*)\\0*.*\\0";

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = _nd_findMainWindow();   // модально окну редактора
    ofn.lpstrFilter = _nd_buildFilterW(inFilter, wFilter, 1024) ? wFilter : wFilterDefault;
    ofn.lpstrFile = wFile;                  // предзаполнено именем по умолчанию
    ofn.nMaxFile = 1024;
    ofn.lpstrTitle = (inTitle != NULL && inTitle[0]) ? wTitle : NULL;
    ofn.lpstrInitialDir = (inInitialDir != NULL && inInitialDir[0]) ? wDir : NULL;
    ofn.lpstrDefExt = (inDefExt != NULL && inDefExt[0]) ? wDefExt : L"exe";
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY
              | OFN_NOCHANGEDIR | OFN_EXPLORER;

    if (!GetSaveFileNameW(&ofn)) return 0;  // отмена или ошибка — путя нет

    return _nd_storeResult(wFile);
}
// v1.1: Модальный диалог открытия существующего файла (GetOpenFileNameW).
// Возврат: как у сохранения. Без defExt (чтение, не создание), без
// предзаполнения имени; OFN_FILEMUSTEXIST — фантом не выбрать.
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
class NativeDialog
{
        /**
         * Есть ли нативный диалог на этом таргете.
         * Windows (cpp) = true; всё остальное (html5 и пр.) = false.
         * Атомы зовут это ДО диалога, чтобы честно отказать вне Windows.
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
         * Модальный диалог «Сохранить как…» (Windows).
         * БЛОКИРУЕТ вызывающий поток до закрытия диалога (рендер стоит,
         * аудио играет — прецедент [P] Export, Этап 3).
         * Возвращает ТОЛЬКО путь — ничего не пишет на диск.
         * @param title       заголовок окна диалога ("" = стандартный)
         * @param defaultName предзаполненное имя файла ("Device.exe")
         * @param initialDir  стартовый каталог ("" = системный дефолт)
         * @param filterText  фильтр «Имя|маска;маска|…» ("" = exe-дефолт
         *                    v1.0.1 — поведение Main.hx не изменилось)
         * @param defaultExt  расширение по умолчанию ("" = "exe", v1.0.1)
         * @return выбранный ПОЛНЫЙ путь (UTF-8) или null — отмена/ошибка/
         *         не-Windows таргет
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
         * Модальный диалог «Открыть файл…» (Windows), v1.1.
         * БЛОКИРУЕТ вызывающий поток до закрытия диалога.
         * OFN_FILEMUSTEXIST: выбрать можно только существующий файл.
         * Возвращает ТОЛЬКО путь — ничего не читает с диска.
         * @param title      заголовок окна диалога ("" = стандартный)
         * @param filterText фильтр «Имя|маска;маска|…» ("" = All files)
         * @param initialDir стартовый каталог ("" = системный дефолт)
         * @return выбранный ПОЛНЫЙ путь (UTF-8) или null — отмена/ошибка/
         *         не-Windows таргет
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
