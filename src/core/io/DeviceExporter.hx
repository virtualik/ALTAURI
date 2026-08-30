package core.io;

// ============================================================================
// DeviceExporter v1.0 — [Export]: упаковка прибора мышкой (Этап 3, Task 137)
// ----------------------------------------------------------------------------
// Оркестратор кнопки [P] Export. Контракт с Main: Main СОХРАНЯЕТ текущую
// схему (prepareCurrentAssemblyForSave + saveCurrentContext) ДО вызова
// export() — прибор несёт то, что видит пользователь, а не прошлогодний
// Selfrun.atom с диска.
//
// ИСТОЧНИКИ (решения планёрки Task 124/125 — v1 = вся библиотека целиком):
//   base    = Sys.programPath() — работающий редактор. Экспорт из сеанса
//             прибора (редактор сам несёт хвост)? Писатель УСЕКАЕТ старый
//             хвост — анти-матрёшка (доктрина PayloadTailWriter), прибор
//             не растёт вглубь при перепаковке.
//   scheme  = Selfrun.atom с диска (Documents/ALTAURI) — только что
//             записан Main'ом. Нет файла → честный отказ (код 1).
//   library = СЛИЯНИЕ: LIBRARY-записи хвоста (TailStartup, сеанс прибора)
//             ∪ папка Library на диске. При конфликте имён ПРИОРИТЕТ ДИСКА:
//             то, что пережило сеанс (правки/новые сборки пишутся на диск),
//             свежее слепка в хвосте. Хвост гарантирует самодостаточность
//             прибора на чистой машине (T-S2.1-мир). Обычный редактор
//             (хвоста нет) вырождается в ТОЧНУЮ семантику --pack Этапа 1 —
//             вплоть до байт-тождества вывода (T-EX.6).
//             Сортировка имён — детерминизм: одинаковая библиотека =
//             байт-одинаковый хвост (доктрина LabCLI).
//
// GUARD'ы (канонические — PathCanon, урок T-EMB.7):
//   · out == Selfrun.atom → отказ: не затирать источник истины схемы
//     (перехватить диалогом можно, выкарабкаться — нельзя);
//   · out внутри папки Library → отказ: не затирать библиотеку сборок;
//   · out == base / работающий exe → отказ в писателе (канонический);
//   · перезапись существующего файла спрашивает нативный диалог
//     (OFN_OVERWRITEPROMPT) — guard не дублирует вопрос.
//
// ВЫВОД: ASCII-only в stdout, построчно в ФОРМАТЕ --pack (метрологический
// мост: T-EX.6 диффит тело вывода кнопки против вывода CLI). Отличается
// только первая строка-заголовок, честно называющая источник команды.
// ============================================================================

import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

/** Результат экспорта (зеркалит TailPackResult + статистика источников). */
typedef ExportResult = {
        ok:Bool,
        errorCode:Int,          // 0/1/2/3 — доктрина единых кодов
        errorMessage:String,
        outPath:String,
        outSize:Int,
        payloadLen:Int,
        payloadCrc:Int,
        entriesPacked:Int,
        truncatedOldTail:Bool,
        schemeSize:Int,
        libCount:Int,
        libBytes:Int
}

class DeviceExporter
{
        /**
         * Упаковать прибор: base = работающий exe, scheme = Selfrun.atom,
         * library = хвост ∪ диск (диск приоритетен). Вызывать ПОСЛЕ
         * сохранения схемы (Main.saveCurrentContext).
         * @param outPath путь назначения (полный, из нативного диалога)
         */
        public static function export(outPath:String):ExportResult
        {
                if (outPath == null || outPath.length == 0)
                        return _fail(1, "output path is empty", outPath);

                // ── base = работающий exe (резолвим ДО вывода: заголовок и
                //    база — первыми строками, как у --pack) ─────────────
                var basePath:String = null;
                try { basePath = Sys.programPath(); } catch (e:Dynamic) { basePath = null; }
                if (basePath == null)
                        return _fail(1, "cannot resolve the running executable path", outPath);

                Sys.println("ALTAURI device export v1");
                Sys.println("base: " + basePath);

                // PM в GUI инициализирован стартапом; init() здесь — защитный
                // вызов для нестандартных потребителей (идемпотентность
                // init() НЕ гарантируется — повторный скан библиотеки;
                // поэтому только при пустых путях)
                var pm = system.managers.ProjectManager.getInstance();
                if (pm.libraryPath == null || pm.selfrunPath == null) pm.init();

                // ── Guard'ы источников истины ────────────────────────────
                if (PathCanon.samePath(outPath, pm.selfrunPath))
                        return _fail(1, "output path equals Selfrun.atom"
                                + " — refusing to overwrite the scheme source", outPath);
                if (PathCanon.isInsideDir(outPath, pm.libraryPath))
                        return _fail(1, "output path is inside the library folder"
                                + " — refusing to overwrite the library", outPath);

                // ── Схема: то, что только что сохранил Main ───────────────
                if (!FileSystem.exists(pm.selfrunPath))
                        return _fail(1, "no Selfrun.atom at " + pm.selfrunPath
                                + " — save the scheme first", outPath);
                var schemeBytes:Bytes = File.getBytes(pm.selfrunPath);

                // ── Библиотека: хвост ∪ диск, диск приоритетен ────────────
                var merged:Map<String, Bytes> = new Map<String, Bytes>();
                for (t in TailStartup.tailLibrarySnapshot())
                        merged.set(t.name, t.data);

                var diskCount:Int = 0;
                if (FileSystem.exists(pm.libraryPath))
                {
                        var files:Array<String> = [];
                        for (f in FileSystem.readDirectory(pm.libraryPath))
                                if (StringTools.endsWith(f.toLowerCase(), ".atom")) files.push(f);
                        files.sort(function(a:String, b:String):Int
                        {
                                return a < b ? -1 : (a > b ? 1 : 0);
                        });
                        for (f in files)
                        {
                                // диск перекрывает хвост: правки сеанса живее слепка
                                merged.set(f, File.getBytes(pm.libraryPath + "/" + f));
                                diskCount++;
                        }
                }

                // детерминизм: сортировка имён поверх слияния
                var names:Array<String> = [for (k in merged.keys()) k];
                names.sort(function(a:String, b:String):Int
                {
                        return a < b ? -1 : (a > b ? 1 : 0);
                });

                var libBytesTotal:Int = 0;
                var entries:Array<PayloadTail.TailEntry> =
                [{
                        type: PayloadTail.TYPE_SCHEME,
                        name: "Selfrun.atom",
                        data: schemeBytes
                }];
                for (n in names)
                {
                        var b:Bytes = merged.get(n);
                        libBytesTotal += b.length;
                        entries.push({ type: PayloadTail.TYPE_LIBRARY, name: n, data: b });
                }

                Sys.println("scheme: Selfrun.atom (" + schemeBytes.length + " bytes)");
                Sys.println("library: " + names.length + " file(s), " + libBytesTotal
                        + " bytes total");

                var r = PayloadTailWriter.pack(basePath, outPath, entries,
                        PayloadTail.FLAG_SCHEME);

                if (!r.ok)
                        return _fail(r.errorCode, r.errorMessage, outPath);

                Sys.println("payload: " + r.payloadLen + " bytes, crc32 "
                        + PayloadTail.hexU32(r.payloadCrc));
                if (r.truncatedOldTail)
                        Sys.println("old tail truncated from base: yes ("
                                + (r.baseSize - r.cleanBaseSize) + " bytes removed)");
                else
                        Sys.println("old tail truncated from base: no");
                Sys.println("output: " + outPath + " (" + r.outSize + " bytes)");

                return {
                        ok: true,
                        errorCode: 0,
                        errorMessage: null,
                        outPath: outPath,
                        outSize: r.outSize,
                        payloadLen: r.payloadLen,
                        payloadCrc: r.payloadCrc,
                        entriesPacked: r.entriesPacked,
                        truncatedOldTail: r.truncatedOldTail,
                        schemeSize: schemeBytes.length,
                        libCount: names.length,
                        libBytes: libBytesTotal
                };
        }

        /** Провал экспорта: честная строка в консоль (дисциплина --pack),
         *  файл не создаётся — побочных эффектов нет. */
        private static function _fail(code:Int, msg:String, outPath:String):ExportResult
        {
                Sys.println("error: " + msg);
                return {
                        ok: false,
                        errorCode: code,
                        errorMessage: msg,
                        outPath: outPath,
                        outSize: 0,
                        payloadLen: 0,
                        payloadCrc: 0,
                        entriesPacked: 0,
                        truncatedOldTail: false,
                        schemeSize: 0,
                        libCount: 0,
                        libBytes: 0
                };
        }
}
