package core.io;

// ============================================================================
// PayloadTailWriter v1.1 — упаковщик ALTRPK1 (Этап 1, Task 132)
// v1.1 (Этап 3, Task 137): guard'ы сравнивают КАНОНИЧЕСКИЕ формы путей
// (PathCanon) — относительный путь больше не обходит строковый
// предохранитель (урок T-EMB.7). io-вызовы используют пути КАК ЕСТЬ —
// поведение записи не изменено.
// ----------------------------------------------------------------------------
// Приклеивает контейнер ALTRPK1 (см. PayloadTail.hx — спецификация) к копии
// исполняемого файла: [ BASE ] [ ENTRY ]* [ TRAILER ].
//
// ДОКТРИНЫ, зашитые в код:
//
//  1. НИКОГДА не пишем в исполняющийся exe и не пишем поверх base.
//     Guard'ы сравнивают КАНОНИЧЕСКИЕ формы (PathCanon.samePath):
//     абсолютная форма + унифицированные слэши + лексика «./..» + на
//     Windows без учёта регистра. Относительный путь, указывающий на
//     работающий exe (прошивка T-EMB.7), теперь ловится В КОДЕ с внятным
//     сообщением; предохранитель ОС (sharing violation) остаётся последней
//     линией обороны для того, что лексика доказать не может (SUBST,
//     symlinks, 8.3-имена).
//
//  2. АНТИ-МАТРЁШКА: если base несёт чужой хвост ALTRPK1 — он УСЕКАЕТСЯ
//     при копировании (копируются только чистые baseSize байт). Перепаковка
//     поверх упакованного не растёт вглубь — pack³ стабилен по размеру.
//     Хвост с неизвестной версией или битой структурой = ОТКАЗ (код 2):
//     резать «как-нибудь» чужой формат нельзя.
//
//  3. ПОТОКОВОСТЬ: base копируется чанками (64 КБ), payload собирается в
//     памяти (КБ..МБ — приемлемо в v1). Память под exe не удваивается.
//
//  4. ЧИСТОТА: writer — тупой транспорт. flags передаются КАК ЕСТЬ
//     (политика — у вызывающего: LabCLI / будущий Export-диалог). CRC
//     каждого entry и контейнера вычисляются ТОЛЬКО из data — поле
//     crc32 во входных entries игнорируется (не доверяем, а проверяем).
//
// Коды ошибок — те же 0/1/2/3, что и у читателя (LabCLI транслирует
// их в коды выхода процесса).
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): 1) import sys.FileSystem — пути
// sys.io.FileSystem в std Haxe НЕ СУЩЕСТВУЕТ; 2) typedef'ы перенесены
// на уровень модуля (грамматика Haxe). Поведение писателя НЕ изменено.
// ============================================================================

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.io.FileSeek;
import sys.FileSystem;

// ── Типы результата — уровень модуля ───────────────────────────────────
// Грамматика Haxe: typedef допустим ТОЛЬКО на уровне модуля, не внутри
// тела класса (урок T-EMB.0). Извне: core.io.PayloadTailWriter.TailPackResult.

/** Результат упаковки. */
typedef TailPackResult = {
        ok:Bool,
        errorCode:Int,
        errorMessage:String,
        baseSize:Int,          // исходный размер base (с чужим хвостом, если был)
        cleanBaseSize:Int,     // сколько байт base скопировано (без хвоста)
        truncatedOldTail:Bool, // был ли у base чужой хвост и усечён ли
        payloadLen:Int,
        payloadCrc:Int,
        outSize:Int,
        entriesPacked:Int
}

/** Разведка чужого хвоста base: magic + механика (без CRC payload). */
private typedef _Probe = { found:Bool, payloadLen:Int, code:Int, error:String }

class PayloadTailWriter
{
        private static inline var CHUNK:Int = 65536;  // 64 КБ

        /**
         * Собрать out = base (без чужого хвоста) + entries + трейлер.
         * basePath — источник (читаем, не трогаем); outPath — цель (создаём).
         */
        public static function pack(basePath:String, outPath:String,
                        entries:Array<PayloadTail.TailEntry>, flags:Int):TailPackResult
        {
                // ── Guard'ы записи ─────────────────────────────────────────
                if (basePath == null || basePath.length == 0 || outPath == null || outPath.length == 0)
                        return _fail(1, "base and output paths must be non-empty");

                if (PathCanon.samePath(outPath, basePath))
                        return _fail(1, "output path equals base path — refusing to overwrite source");

                var selfPath:String = null;
                try { selfPath = Sys.programPath(); } catch (e:Dynamic) { selfPath = null; }
                if (selfPath != null && PathCanon.samePath(outPath, selfPath))
                        return _fail(1, "output path is the running executable — write to own exe is forbidden");

                if (!FileSystem.exists(basePath))
                        return _fail(1, "base file not found: " + basePath);

                // ── Анти-матрёшка: сколько чистого base копировать ─────────
                var baseSize:Int;
                try { baseSize = FileSystem.stat(basePath).size; }
                catch (e:Dynamic) { return _fail(1, "cannot stat base: " + e); }

                var cleanBaseSize:Int = baseSize;
                var truncatedOldTail:Bool = false;
                if (baseSize >= PayloadTail.TRAILER_SIZE)
                {
                        var probe = _probeTail(basePath, baseSize);
                        if (probe.error != null)
                                return _fail(probe.code, probe.error);
                        if (probe.found)
                        {
                                truncatedOldTail = true;
                                cleanBaseSize = baseSize - PayloadTail.TRAILER_SIZE - probe.payloadLen;
                                if (cleanBaseSize < 0)
                                        return _fail(2, "base tail declares payload longer than file — corrupt base tail");
                        }
                }

                // ── Сборка payload в памяти ────────────────────────────────
                var buf:BytesOutput = new BytesOutput();
                for (e in entries)
                {
                        if (e == null || e.data == null)
                                return _fail(2, "null entry or entry data in pack list");

                        var nameB:Bytes = Bytes.ofString(e.name);
                        if (nameB.length > 0xFFFF)
                                return _fail(2, "entry name too long (>" + 0xFFFF + " bytes): "
                                        + (e.name.length > 64 ? e.name.substr(0, 64) + "..." : e.name));

                        _wU8(buf, e.type);
                        _wU16(buf, nameB.length);
                        buf.write(nameB);
                        _wU32(buf, e.data.length);   // lo
                        _wU32(buf, 0);               // hi (v1: длина < 2 ГБ по построению Bytes)
                        buf.write(e.data);
                        _wU32(buf, Crc32.make(e.data));
                }
                var payload:Bytes = buf.getBytes();
                var payloadCrc:Int = Crc32.make(payload);

                // ── Потоковая запись: base-чанки → payload → трейлер ──────
                var fin:FileInput = null;
                var fout:FileOutput = null;
                var outSize:Int = cleanBaseSize + payload.length + PayloadTail.TRAILER_SIZE;
                try
                {
                        fin = File.read(basePath, true);
                        fout = File.write(outPath, true);

                        var chunk:Bytes = Bytes.alloc(CHUNK);
                        var remaining:Int = cleanBaseSize;
                        while (remaining > 0)
                        {
                                var want:Int = remaining < CHUNK ? remaining : CHUNK;
                                var got:Int = _readExactCount(fin, chunk, want);
                                if (got < want)
                                {
                                        fin.close(); fout.close();
                                        _bestEffortDelete(outPath);
                                        return _fail(2, "base truncated during copy (expected "
                                                + cleanBaseSize + " clean bytes, EOF at "
                                                + (cleanBaseSize - remaining + got) + ")");
                                }
                                fout.writeFullBytes(chunk, 0, got);
                                remaining -= got;
                        }

                        fout.write(payload);
                        _wU32(fout, payload.length);   // payloadLen lo
                        _wU32(fout, 0);                 // payloadLen hi
                        _wU32(fout, payloadCrc);        // payloadCrc32
                        _wU16(fout, PayloadTail.VERSION);
                        _wU16(fout, flags & 0xFFFF);
                        _wMagic(fout);

                        fin.close();
                        fout.close();
                }
                catch (e:Dynamic)
                {
                        if (fin != null) { try { fin.close(); } catch (d:Dynamic) {} }
                        if (fout != null) { try { fout.close(); } catch (d:Dynamic) {} }
                        _bestEffortDelete(outPath);
                        return _fail(1, "io error during pack: " + e);
                }

                return {
                        ok: true,
                        errorCode: 0,
                        errorMessage: null,
                        baseSize: baseSize,
                        cleanBaseSize: cleanBaseSize,
                        truncatedOldTail: truncatedOldTail,
                        payloadLen: payload.length,
                        payloadCrc: payloadCrc,
                        outSize: outSize,
                        entriesPacked: entries.length
                };
        }

        // ── Внутренняя кухня ──────────────────────────────────────────────

        private static function _probeTail(path:String, size:Int):_Probe
        {
                var none:_Probe = { found: false, payloadLen: 0, code: 0, error: null };

                var t:Bytes = Bytes.alloc(PayloadTail.TRAILER_SIZE);
                var fin:FileInput = null;
                try
                {
                        fin = File.read(path, true);
                        fin.seek(size - PayloadTail.TRAILER_SIZE, SeekBegin);
                        var done:Int = 0;
                        while (done < PayloadTail.TRAILER_SIZE)
                        {
                                var n:Int = fin.readBytes(t, done, PayloadTail.TRAILER_SIZE - done);
                                if (n <= 0) { fin.close(); return none; }
                                done += n;
                        }
                        fin.close();
                }
                catch (e:Dynamic)
                {
                        if (fin != null) { try { fin.close(); } catch (d:Dynamic) {} }
                        return { found: false, payloadLen: 0, code: 1, error: "io error probing base tail: " + e };
                }

                if (t.get(16) != 0x41 || t.get(17) != 0x4C || t.get(18) != 0x54 ||
                    t.get(19) != 0x52 || t.get(20) != 0x50 || t.get(21) != 0x4B ||
                    t.get(22) != 0x31 || t.get(23) != 0x00)
                        return none;  // чужого хвоста нет — копируем base целиком

                // Хвост есть — его механика обязана быть безупречна, иначе отказ
                var plLo:Int = t.get(0) | (t.get(1) << 8) | (t.get(2) << 16) | (t.get(3) << 24);
                var plHi:Int = t.get(4) | (t.get(5) << 8) | (t.get(6) << 16) | (t.get(7) << 24);
                var ver:Int = t.get(12) | (t.get(13) << 8);

                if (ver != PayloadTail.VERSION)
                        return { found: true, payloadLen: 0, code: 2,
                                error: "base carries ALTRPK1 tail of unknown version " + ver
                                        + " — refusing to truncate a foreign format" };
                if (plHi != 0 || plLo < 0)
                        return { found: true, payloadLen: 0, code: 2,
                                error: "base tail declares payload >= 2 GB or corrupt — refusing" };
                // Разностная форма: переполнение Int32 исключено (size >= 24 здесь гарантирован)
                if (plLo > size - PayloadTail.TRAILER_SIZE)
                        return { found: true, payloadLen: 0, code: 2,
                                error: "base tail points beyond file — refusing (corrupt)" };

                return { found: true, payloadLen: plLo, code: 0, error: null };
        }

        /** Чтение ровно want байт; возврат — сколько реально прочитано. */
        private static function _readExactCount(i:FileInput, buf:Bytes, want:Int):Int
        {
                var done:Int = 0;
                while (done < want)
                {
                        var n:Int = i.readBytes(buf, done, want - done);
                        if (n <= 0) break;
                        done += n;
                }
                return done;
        }

        // ── Little-endian примитивы записи (Output — общий предок
        //    BytesOutput и FileOutput; ручная сборка — ноль неоднозначностей)

        private static inline function _wU8(o:haxe.io.Output, v:Int):Void
        {
                o.writeByte(v & 0xFF);
        }

        private static inline function _wU16(o:haxe.io.Output, v:Int):Void
        {
                o.writeByte(v & 0xFF);
                o.writeByte((v >>> 8) & 0xFF);
        }

        private static inline function _wU32(o:haxe.io.Output, v:Int):Void
        {
                o.writeByte(v & 0xFF);
                o.writeByte((v >>> 8) & 0xFF);
                o.writeByte((v >>> 16) & 0xFF);
                o.writeByte((v >>> 24) & 0xFF);
        }

        /** magic "ALTRPK1\0" — 8 байт, последний NUL. */
        private static inline function _wMagic(o:haxe.io.Output):Void
        {
                o.writeByte(0x41); // A
                o.writeByte(0x4C); // L
                o.writeByte(0x54); // T
                o.writeByte(0x52); // R
                o.writeByte(0x50); // P
                o.writeByte(0x4B); // K
                o.writeByte(0x31); // 1
                o.writeByte(0x00); // NUL
        }

        /** Удаление недописанного out после ошибки (лучшее усилие). */
        private static function _bestEffortDelete(path:String):Void
        {
                try { if (FileSystem.exists(path)) FileSystem.deleteFile(path); } catch (e:Dynamic) {}
        }

        private static function _fail(code:Int, msg:String):TailPackResult
        {
                return { ok: false, errorCode: code, errorMessage: msg,
                        baseSize: 0, cleanBaseSize: 0, truncatedOldTail: false,
                        payloadLen: 0, payloadCrc: 0, outSize: 0, entriesPacked: 0 };
        }
}
