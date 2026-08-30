package core.io;

// ============================================================================
// LabCLI v1.0 — лабораторный CLI ALTAURI (Этап 1, Task 132)
// ----------------------------------------------------------------------------
// Инструментальный режим редактора ДО появления кнопки [Export]: упаковка
// «прибора» (--pack) и вскрытие хвоста (--inspect) прямо из командной строки
// Станции. Вызывается из Main.new() ЗАКРЫТЫМ #if sys блоком ДО всякой
// инициализации UI; вернув true, требует немедленного Sys.exit(exitCode).
//
// Это ПРОТОТИП кнопки [Export] (Этап 3): --pack делает ровно то, что будет
// делать кнопка — берёт СЕБЯ (или --base), Схему (Selfrun.atom) и ВСЮ
// библиотеку CustomAssembly_*.atom из Documents/ALTAURI (решение планёрки
// Task 124/125: v1 = вся библиотека целиком) и клепает единый файл.
//
// ВЫВОД: ASCII-only, НАМЕРЕННО. Кириллица в cmd.exe = cp866-кракозябры;
// терминальная дисциплина лаборатории — латиница.
//
// ARGV-ДИСЦИПЛИНА: первый аргумент -- наш флаг → обрабатываем и выходим;
// аргументов нет → обычный старт редактора (нулевая регрессия: двойной
// клик и FD F5 не передают аргументов); НЕ-флаг (например, брошенный на
// exe файл .atom) → игнорируем, стартует редактор — это задел Этапа 2
// (приоритет argv-файл > хвост > Selfrun.atom).
//
// КОДЫ ВЫХОДА (доктрина Task 123 В.3, единые с читателем/писателем):
//   0 — успех («хвоста нет» для --inspect — тоже успех, это честный ответ)
//   1 — ошибка ввода-вывода или использования
//   2 — ошибка формата
//   3 — CRC-несоответствие (порча данных)
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): import sys.FileSystem — пути
// sys.io.FileSystem в std Haxe НЕ СУЩЕСТВУЕТ («Type not found» на
// Станции; эталон правильного пути — ProjectManager.hx:7). Вывод
// CLI и коды выхода не изменены.
// ============================================================================

import sys.io.File;
import sys.FileSystem;

class LabCLI
{
        /** Код выхода после обработки команды (валиден при возврате true). */
        public static var exitCode:Int = 0;

        /**
         * Главный диспетчер. true = команда обработана, вызывающий (Main)
         * обязан немедленно выйти: Sys.exit(LabCLI.exitCode).
         * false = аргументов для нас нет — стартовать редактор как обычно.
         */
        public static function maybeHandle():Bool
        {
                var args:Array<String> = Sys.args();
                if (args.length == 0) return false;

                var first:String = args[0];

                if (first == "--inspect")
                {
                        handleInspect(args.slice(1));
                        return true;
                }
                if (first == "--pack")
                {
                        handlePack(args.slice(1));
                        return true;
                }
                if (first == "--help" || first == "-h")
                {
                        printUsage();
                        exitCode = 0;
                        return true;
                }
                if (StringTools.startsWith(first, "--"))
                {
                        Sys.println("unknown option: " + first);
                        printUsage();
                        exitCode = 1;
                        return true;
                }

                // Не-флаг: не наше дело (задел Этапа 2). Редактор стартует.
                return false;
        }

        // ── --inspect [file] ──────────────────────────────────────────────

        private static function handleInspect(rest:Array<String>):Void
        {
                if (rest.length > 1)
                {
                        Sys.println("error: --inspect takes at most one file argument");
                        printUsage();
                        exitCode = 1;
                        return;
                }

                var path:String = (rest.length == 1) ? rest[0] : Sys.programPath();

                Sys.println("ALTAURI payload tail inspector v1");
                Sys.println("file: " + path);

                var r:PayloadTail.TailReadResult = PayloadTail.read(path);

                if (!r.ok)
                {
                        if (r.tail) Sys.println("tail: ALTRPK1 (detected)");
                        Sys.println("error: " + r.errorMessage);
                        exitCode = r.errorCode;
                        return;
                }

                if (!r.tail)
                {
                        Sys.println("size: " + _statSize(path) + " bytes");
                        Sys.println("tail: none");
                        exitCode = 0;
                        return;
                }

                var c = r.container;
                Sys.println("size: " + c.fileSize + " bytes");
                Sys.println("tail: ALTRPK1 v" + c.version);
                Sys.println("base: " + c.baseSize + " bytes, payload: " + c.payloadLen
                        + " bytes, entries: " + c.entries.length);
                Sys.println("flags: 0x" + StringTools.hex(c.flags, 4) + " " + _flagsHuman(c.flags));
                Sys.println("payload crc32: " + PayloadTail.hexU32(c.payloadCrc) + " OK");

                var n:Int = 1;
                for (e in c.entries)
                {
                        Sys.println("  #" + n + " type=" + _typeName(e.type)
                                + " name=" + e.name
                                + " len=" + e.data.length
                                + " crc32=" + PayloadTail.hexU32(e.crc32) + " OK");
                        n++;
                }

                // Метрологическая придирчивость: флаги — совещательны,
                // entries — истина; расхождение достойно огласки.
                var hasScheme:Bool = false;
                for (e in c.entries) if (e.type == PayloadTail.TYPE_SCHEME) hasScheme = true;
                if (((c.flags & PayloadTail.FLAG_SCHEME) != 0) != hasScheme)
                        Sys.println("note: FLAG_SCHEME disagrees with entries");

                Sys.println("summary: " + c.entries.length + " entries, all crc OK");
                exitCode = 0;
        }

        // ── --pack <out.exe> [--base <file>] ─────────────────────────────

        private static function handlePack(rest:Array<String>):Void
        {
                // Разбор: ровно один позиционный <out> + опционально --base <path>
                var outPath:String = null;
                var basePath:String = null;
                var i:Int = 0;
                while (i < rest.length)
                {
                        var a:String = rest[i];
                        if (a == "--base")
                        {
                                if (i + 1 >= rest.length)
                                {
                                        Sys.println("error: --base requires a path argument");
                                        printUsage();
                                        exitCode = 1;
                                        return;
                                }
                                basePath = rest[i + 1];
                                i += 2;
                        }
                        else if (outPath == null && !StringTools.startsWith(a, "--"))
                        {
                                outPath = a;
                                i += 1;
                        }
                        else
                        {
                                Sys.println("error: unexpected argument: " + a);
                                printUsage();
                                exitCode = 1;
                                return;
                        }
                }
                if (outPath == null)
                {
                        Sys.println("error: --pack requires an output file argument");
                        printUsage();
                        exitCode = 1;
                        return;
                }
                if (basePath == null) basePath = Sys.programPath();

                Sys.println("ALTAURI payload tail packer v1");
                Sys.println("base: " + basePath);

                // Схема и библиотека — из единого источника истины путей
                var pm = system.managers.ProjectManager.getInstance();
                pm.init();

                if (!FileSystem.exists(pm.selfrunPath))
                {
                        Sys.println("error: no Selfrun.atom at " + pm.selfrunPath
                                + " — open the editor and build a scheme first");
                        exitCode = 1;
                        return;
                }

                var schemeBytes = File.getBytes(pm.selfrunPath);
                var entries:Array<PayloadTail.TailEntry> = [{
                        type: PayloadTail.TYPE_SCHEME,
                        name: "Selfrun.atom",
                        data: schemeBytes
                }];

                // Библиотека: ВСЯ (доктрина v1, Task 125). Сортировка —
                // детерминизм: одинаковая библиотека = байт-одинаковый хвост.
                var libFiles:Array<String> = [];
                if (FileSystem.exists(pm.libraryPath))
                {
                        for (f in FileSystem.readDirectory(pm.libraryPath))
                        {
                                if (StringTools.endsWith(f.toLowerCase(), ".atom")) libFiles.push(f);
                        }
                }
                libFiles.sort(function(a:String, b:String):Int
                {
                        return a < b ? -1 : (a > b ? 1 : 0);
                });

                var libBytesTotal:Int = 0;
                for (f in libFiles)
                {
                        var fb = File.getBytes(pm.libraryPath + "/" + f);
                        libBytesTotal += fb.length;
                        entries.push({ type: PayloadTail.TYPE_LIBRARY, name: f, data: fb });
                }

                Sys.println("scheme: Selfrun.atom (" + schemeBytes.length + " bytes)");
                Sys.println("library: " + libFiles.length + " file(s), " + libBytesTotal + " bytes total");

                var flags:Int = PayloadTail.FLAG_SCHEME;
                var r = PayloadTailWriter.pack(basePath, outPath, entries, flags);

                if (!r.ok)
                {
                        Sys.println("error: " + r.errorMessage);
                        exitCode = r.errorCode;
                        return;
                }

                Sys.println("payload: " + r.payloadLen + " bytes, crc32 "
                        + PayloadTail.hexU32(r.payloadCrc));
                if (r.truncatedOldTail)
                        Sys.println("old tail truncated from base: yes ("
                                + (r.baseSize - r.cleanBaseSize) + " bytes removed)");
                else
                        Sys.println("old tail truncated from base: no");
                Sys.println("output: " + outPath + " (" + r.outSize + " bytes)");
                exitCode = 0;
        }

        // ── Общие ─────────────────────────────────────────────────────────

        private static function printUsage():Void
        {
                Sys.println("ALTAURI lab CLI v1 (ALTRPK1 payload tail)");
                Sys.println("usage:");
                Sys.println("  ALTAURI_Windows.exe --inspect [file]");
                Sys.println("      Print payload tail manifest (default file: this executable).");
                Sys.println("  ALTAURI_Windows.exe --pack <out.exe> [--base <file>]");
                Sys.println("      Pack scheme (Selfrun.atom) + library (CustomAssembly *.atom)");
                Sys.println("      from Documents/ALTAURI into a copy of this executable.");
                Sys.println("  No arguments: normal editor start.");
                Sys.println("exit codes: 0 ok, 1 io/usage, 2 format, 3 crc mismatch");
        }

        private static function _typeName(t:Int):String
        {
                return switch (t)
                {
                        case PayloadTail.TYPE_SCHEME: "SCHEME";
                        case PayloadTail.TYPE_ASSET: "ASSET";
                        case PayloadTail.TYPE_MANIFEST: "MANIFEST";
                        case PayloadTail.TYPE_LIBRARY: "LIBRARY";
                        default: "UNKNOWN(" + t + ")";
                };
        }

        private static function _flagsHuman(f:Int):String
        {
                var parts:Array<String> = [];
                // ВАЖНО: скобки обязательны — в Haxe «&» связывает слабее «!=»
                // (классическая ловушка приоритета: f & FLAG != 0 читается как
                // f & (FLAG != 0) — не то, что мы хотим)
                if ((f & PayloadTail.FLAG_SCHEME) != 0) parts.push("SCHEME");
                if ((f & PayloadTail.FLAG_ASSETS) != 0) parts.push("ASSETS");
                if ((f & PayloadTail.FLAG_AUTORUN) != 0) parts.push("AUTORUN");
                if ((f & PayloadTail.FLAG_LOCKED) != 0) parts.push("LOCKED");
                return parts.length > 0 ? "[" + parts.join(" ") + "]" : "[]";
        }

        private static function _statSize(path:String):Int
        {
                try
                {
                        if (FileSystem.exists(path)) return FileSystem.stat(path).size;
                }
                catch (e:Dynamic) {}
                return 0;
        }
}
