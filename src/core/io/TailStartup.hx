package core.io;

// ============================================================================
// TailStartup v1.1 — источник старта редактора (Этап 2 «Чтение хвоста», Task 135)
// v1.1 (Этап 3, Task 137): + tailLibrarySnapshot() — снимок байтов LIBRARY-
// записей для DeviceExporter (экспорт из сеанса прибора). Поведение старта
// не изменено ни на байт.
// ----------------------------------------------------------------------------
// ПРИОРИТЕТ СХЕМЫ ПРИ СТАРТЕ: argv > ХВОСТ > Selfrun.atom (Documents/ALTAURI):
//   argv    — первый НЕ-флаг аргумент (файл, брошенный на exe) — открыть его;
//   хвост   — ALTRPK1-контейнер в конце СОБСТВЕННОГО exe («прибор»: Device.exe
//             несёт схему и библиотеку внутри себя, машина может быть пустой);
//   Selfrun — обычный редактор, как было до Этапа 2 (нулевая регрессия).
//
// БИБЛИОТЕКА: валидный хвост с TYPE_LIBRARY-записями → библиотека ЦЕЛИКОМ из
// хвоста, папка Documents/ALTAURI/Library НЕ сканируется (прибор несёт свой
// мир — детерминизм: прибор не зависит от машины). Хвоста нет → сканирование
// папки, как раньше. Битый хвост (CRC/версия/структура) = прибор с битой
// прошивкой: предупреждение в консоль и откат на диск, НЕ падаем.
//
// ДИАГНОСТИКА: ASCII-only в stdout (терминальная дисциплина лаборатории).
// Обычный редактор без аргументов и без хвоста не печатает НИЧЕГО — нулевая
// регрессия консоли.
//
// ТОЧКА ВЫЗОВА: Main.new() — ПОСЛЕ LabCLI (CLI-команды уже вышли; --pack читает
// Documents напрямую и хвостом не затрагивается: install() не вызван,
// hasTailLibrary()==false, писатель работает как в Этапе 1) и ДО
// ProjectManager.init() (тот решает: библиотека из хвоста или скан папки).
// install() идемпотентен.
//
// ЗАВИСИМОСТИ: PayloadTail + std; единственный интеграционный шов —
// loadLibraryToRegistry() → library.AtomRegistry.loadAtomContent (прецедент
// зависимостей: LabCLI → system.managers.ProjectManager). Компилируется
// только на sys-таргетах (вызов закрыт #if sys в Main).
//
// v1-ГРАНИЦЫ (зафиксированы честно):
//   · argv-файл открывается КАК СХЕМА (Selfrun-формата .atom); истина —
//     первый не-флаг аргумент, остальные аргументы v1 игнорирует;
//   · argv меняет ТОЛЬКО схему; библиотека остаётся миром прибора (хвост);
//   · сохранение по-прежнему в Documents/ALTAURI: правка прибора пишет копию
//     на диск, но прибор остаётся носителем своей схемы («firmware»);
//   · несколько SCHEME-записей: первая — истина (писатель кладёт ровно одну);
//   · флаги трейлера совещательны, истина — entries (доктрина PayloadTail).
// ============================================================================

import sys.FileSystem;
import sys.io.File;

class TailStartup
{
        // ── Состояние (заполняется один раз в install()) ─────────────────

        private static var _installed:Bool = false;

        /** Первый НЕ-флаг аргумент (файл схемы), если был. */
        private static var _argvPath:String = null;
        /** Контент argv-файла (null = нечитаем/отсутствует). */
        private static var _argvContent:String = null;

        /** Хвост найден и валиден. */
        private static var _tailOk:Bool = false;
        /** Хвост найден, но бит (текст ошибки читателя). */
        private static var _tailError:String = null;
        private static var _tailVersion:Int = 0;
        private static var _tailEntryCount:Int = 0;
        /** Контент SCHEME-записи хвоста (первой). */
        private static var _tailScheme:String = null;
        /** LIBRARY-записи хвоста (порядок контейнера = сортировка писателя). */
        private static var _libEntries:Array<PayloadTail.TailEntry> = [];

        /** Итоговый контент схемы (argv/хвост) или null → диск (Selfrun.atom). */
        private static var _schemeContent:String = null;
        /** Откуда схема: "argv" | "tail" | "disk". */
        private static var _schemeSource:String = "disk";

        /**
         * Разведка источников старта. Продакшн зовёт install() без аргументов
         * из Main.new() ровно один раз; параметры — для стендовых тестов.
         * @param exePath    путь «своего» exe (умолчание: Sys.programPath())
         * @param forceArgs  подмена аргументов командной строки (тесты);
         *                   null = реальные Sys.args()
         */
        public static function install(?exePath:String, ?forceArgs:Array<String>):Void
        {
                if (_installed) return;
                _installed = true;

                // ── 1) argv: первый НЕ-флаг аргумент = файл схемы ──────────
                var args:Array<String> = forceArgs;
                if (args == null)
                {
                        try { args = Sys.args(); } catch (e:Dynamic) { args = []; }
                }
                if (args != null && args.length > 0 && !StringTools.startsWith(args[0], "--"))
                {
                        _argvPath = args[0];
                        if (FileSystem.exists(_argvPath))
                        {
                                try { _argvContent = File.getContent(_argvPath); }
                                catch (e:Dynamic) { _argvContent = null; }
                        }
                }

                // ── 2) собственный хвост ──────────────────────────────────
                var selfPath:String = exePath;
                if (selfPath == null)
                {
                        try { selfPath = Sys.programPath(); } catch (e:Dynamic) { selfPath = null; }
                }
                if (selfPath != null && FileSystem.exists(selfPath))
                {
                        var r:PayloadTail.TailReadResult = PayloadTail.read(selfPath);
                        if (r.ok && r.tail)
                        {
                                _tailOk = true;
                                _tailVersion = r.container.version;
                                _tailEntryCount = r.container.entries.length;
                                for (e in r.container.entries)
                                {
                                        if (e.type == PayloadTail.TYPE_SCHEME && _tailScheme == null)
                                                _tailScheme = e.data.toString();
                                        else if (e.type == PayloadTail.TYPE_LIBRARY)
                                                _libEntries.push(e);
                                }
                        }
                        else if (!r.ok && r.tail)
                        {
                                _tailError = r.errorMessage;  // прибор с битой прошивкой
                        }
                        // ok && !tail — обычный exe: тишина
                }

                // ── 3) приоритет схемы: argv > хвост > диск ────────────────
                if (_argvContent != null)
                {
                        _schemeContent = _argvContent;
                        _schemeSource = "argv";
                }
                else if (_tailScheme != null)
                {
                        _schemeContent = _tailScheme;
                        _schemeSource = "tail";
                }
                else
                {
                        _schemeContent = null;
                        _schemeSource = "disk";
                }

                _report();
        }

        // ── Публичный API (потребители: ProjectManager, тесты) ────────────

        /** Контент схемы по приоритету argv > хвост; null = диск (Selfrun.atom). */
        public static function readSchemeContent():Null<String>
        {
                return _schemeContent;
        }

        /** Откуда взята схема: "argv" | "tail" | "disk". */
        public static function schemeSource():String
        {
                return _schemeSource;
        }

        /** Библиотека в хвосте есть и валидна → ProjectManager.init не сканирует папку. */
        public static function hasTailLibrary():Bool
        {
                return _tailOk && _libEntries.length > 0;
        }

        /** Имена LIBRARY-записей хвоста. */
        public static function tailLibraryNames():Array<String>
        {
                var names:Array<String> = [];
                for (e in _libEntries) names.push(e.name);
                return names;
        }

        /**
         * Снимок LIBRARY-записей хвоста (имя + байты как в контейнере).
         * Потребитель: DeviceExporter (Этап 3) — слияние библиотеки при
         * экспорте из сеанса прибора. Байты передаются по ссылке —
         * потребитель обязан трактовать их как read-only.
         */
        public static function tailLibrarySnapshot():Array<{name:String, data:haxe.io.Bytes}>
        {
                var out:Array<{name:String, data:haxe.io.Bytes}> = [];
                for (e in _libEntries) out.push({ name: e.name, data: e.data });
                return out;
        }

        /**
         * Зарегистрировать библиотеку хвоста в AtomRegistry. Интеграционный
         * шов Этапа 2: вызывается из ProjectManager.init() ВМЕСТО
         * AtomRegistry.scanFolder, когда прибор несёт библиотеку в себе.
         * @return true — зарегистрирована хотя бы одна сборка
         */
        public static function loadLibraryToRegistry():Bool
        {
                if (!hasTailLibrary()) return false;
                var any:Bool = false;
                for (e in _libEntries)
                {
                        if (library.AtomRegistry.loadAtomContent(e.data.toString(), e.name)) any = true;
                }
                return any;
        }

        /** Установлен ли install() (защита обращений до вызова). */
        public static function isInstalled():Bool
        {
                return _installed;
        }

        // ── Диагностика (ASCII-only; молчание обычного редактора) ─────────

        private static function _report():Void
        {
                // Нулевая регрессия консоли: обычный редактор (нет argv,
                // нет хвоста) не печатает ничего.
                var talk:Bool = (_argvPath != null) || _tailOk || (_tailError != null);
                if (!talk) return;

                Sys.println("ALTAURI tail startup v1");
                if (_argvPath != null)
                {
                        if (_argvContent != null)
                                Sys.println("argv scheme: " + _argvPath);
                        else
                                Sys.println("argv scheme: " + _argvPath + " (unreadable - ignored)");
                }
                if (_tailOk)
                        Sys.println("tail: ALTRPK1 v" + _tailVersion + " ("
                                + _tailEntryCount + " entries)");
                else if (_tailError != null)
                        Sys.println("tail: corrupt - " + _tailError + " - ignored");
                else
                        Sys.println("tail: none");
                Sys.println("scheme source: " + _schemeSource);
                Sys.println("library source: " + (hasTailLibrary()
                        ? "tail (" + _libEntries.length + " files)" : "folder"));
        }
}
