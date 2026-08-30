package core.io;

// ============================================================================
// PayloadTail v1.0 — ALTRPK1 «хвост» (Этап 1 «Единый файл», Task 132)
// ----------------------------------------------------------------------------
// Читатель контейнера ALTRPK1: полезная нагрузка, приклеенная в ХВОСТ
// исполняемого файла. PE/ELF/Mach-O игнорируют байты после образа — хвост
// невидим для ОС и для самого приложения, пока приложение не ищет его само.
//
// ═══════════════════════════════════════════════════════════════════════════
// СПЕЦИФИКАЦИЯ ФОРМАТА ALTRPK1 v1 (little-endian, все целые)
// ═══════════════════════════════════════════════════════════════════════════
//
//   ФАЙЛ   := [ BASE любой длины ] [ ENTRY ]* [ TRAILER 24 байта ]
//   ENTRY  := type u8 | nameLen u16 | name nameLen байт UTF-8 |
//             dataLen u64 | data dataLen байт | dataCrc32 u32
//   TRAILER:= payloadLen u64 | payloadCrc32 u32 | version u16 |
//             flags u16 | magic char[8] = "ALTRPK1\0"
//                         (41 4C 54 52 50 4B 31 00)
//
//   payloadLen  — суммарный размер всех ENTRY (без трейлера).
//   payloadCrc  — CRC32 (zlib-совместимый, haxe.crypto.Crc32) блока payload.
//   version     — версия формата = 1. Читатель НЕЗНАКОМОЙ версии обязан
//                 отказать (код 2), а не угадывать.
//   dataCrc32   — CRC32 поля data каждого entry (двойная защита: контейнер +
//                 запись; повреждение локализуется до конкретного entry).
//   magic       — последние 8 байт файла. Поиск хвоста = O(1): seek(-24).
//
//   ТИПЫ ENTRY: 1 SCHEME   — схема (.atom, JSON)
//               2 ASSET    — пользовательский ассет (эпоха Assets Manager)
//               3 MANIFEST — служебный манифест
//               4 LIBRARY  — сборка CustomAssembly_*.atom (tail-backed
//                            библиотека: приоритет хвост > диск)
//   НЕИЗВЕСТНЫЙ тип НЕ ошибка: запись пропускается по dataLen (барьер прямой
//   совместимости — старый читатель читает новый контейнер).
//
//   ФЛАГИ (совещательные метаданные трейлера; истина — в entries):
//     bit0 FLAG_SCHEME   в контейнере есть схема
//     bit1 FLAG_ASSETS   в контейнере есть ассеты
//     bit2 FLAG_AUTORUN  прибор: исполнять схему без редактора (headless-эпоха)
//     bit3 FLAG_LOCKED   «прибор» в завершённом виде (задел Device-панели)
//
//   ПОТОКОВЫЕ ГРАНИЦЫ v1 (честные, в коде и в спеке):
//     — u64-поля парсятся как lo/hi; hi != 0 → отказ (код 2): полезная
//       нагрузка > 2 ГБ в v1 не поддерживается (наша реальность — КБ..МБ);
//     — читатель v1 дополнительно ограничивает payload СВЕРХУ 1 ГБ
//       (0x40000000): гарантия беззнаковой чистоты всей арифметики обхода
//       (суммы смещений не достигают 2^31 ни при каких входах);
//     — все сравнения границ — РАЗНОСТНЫЕ (a > b - c вместо a + c > b),
//       переполнение Int32 исключено по построению.
//
//   ДОКТРИНА ЗАПИСИ: писать в ИСПОЛНЯЮЩИЙСЯ exe запрещено (Windows —
//   sharing violation, Linux — порча образа). Перепаковка всегда в НОВЫЙ
//   файл, анти-матрёшка: чужой хвост base усекается (см. PayloadTailWriter).
//
//   Коды ошибок читателя = коды выхода лабораторного CLI (LabCLI):
//     0 — ок (включая честный ответ «хвоста нет»)
//     1 — ошибка ввода-вывода
//     2 — ошибка формата (версия, структура, размеры)
//     3 — CRC-несоответствие (контейнер или entry)
//
// ЗАВИСИМОСТИ: только std (sys.*, sys.io.*, haxe.io.*, haxe.crypto.Crc32).
// Класс компилируется исключительно на sys-таргетах: единственный вызов
// (Main.new → LabCLI) закрыт #if sys, DCE не тянет файл на html5.
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): 1) import sys.FileSystem —
// пути sys.io.FileSystem в std Haxe НЕ СУЩЕСТВУЕТ; 2) typedef'ы
// перенесены из тела класса на уровень модуля (грамматика Haxe).
// Формат ALTRPK1, байты и тексты вывода НЕ изменены.
// ============================================================================

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileSeek;
import sys.FileSystem;

// ── Структуры результата — типы уровня модуля ──────────────────────────
// Грамматика Haxe: typedef допустим ТОЛЬКО на уровне модуля, не внутри
// тела класса (урок T-EMB.0: «Unexpected keyword typedef» на строке 94).
// Публичные по умолчанию; извне путь — core.io.PayloadTail.TailEntry,
// из пакета core.io допустимо короткое PayloadTail.TailEntry.

/** Одна запись контейнера (crc32 вычислен читателем и уже сверен). */
typedef TailEntry = {
        type:Int,
        name:String,
        data:Bytes,
        ?crc32:Int
}

/** Разобранный контейнер. baseSize — размер «чистого» exe без хвоста. */
typedef TailContainer = {
        version:Int,
        flags:Int,
        payloadLen:Int,
        payloadCrc:Int,
        baseSize:Int,
        fileSize:Int,
        entries:Array<TailEntry>
}

/**
 * Результат чтения. Без исключений — явный результат, чтобы LabCLI
 * мог отобразить errorCode напрямую в код выхода процесса.
 *   ok=true, tail=false → файла-хвоста нет (легальный ответ)
 *   ok=true, tail=true  → контейнер разобран и проверен
 *   ok=false            → ошибка; tail=true значит «magic найден,
 *                         но целостность/формат нарушены»
 */
typedef TailReadResult = {
        ok:Bool,
        tail:Bool,
        container:TailContainer,
        errorCode:Int,
        errorMessage:String
}

/** Результат чтения трейлера. */
private typedef _TrailerInfo = {
        found:Bool,          // magic совпал
        error:String,        // io-ошибка (тогда found=false)
        fileSize:Int,
        payloadLenLo:Int,
        payloadLenHi:Int,
        payloadCrc:Int,
        version:Int,
        flags:Int
}

class PayloadTail
{
        // ── Константы формата ─────────────────────────────────────────────
        public static inline var TRAILER_SIZE:Int = 24;
        public static inline var VERSION:Int = 1;

        // Типы entry
        public static inline var TYPE_SCHEME:Int = 1;
        public static inline var TYPE_ASSET:Int = 2;
        public static inline var TYPE_MANIFEST:Int = 3;
        public static inline var TYPE_LIBRARY:Int = 4;

        // Флаги трейлера
        public static inline var FLAG_SCHEME:Int = 0x0001;
        public static inline var FLAG_ASSETS:Int = 0x0002;
        public static inline var FLAG_AUTORUN:Int = 0x0004;
        public static inline var FLAG_LOCKED:Int = 0x0008;

        // ── Публичное API ─────────────────────────────────────────────────

        /**
         * Быстрая проверка наличия хвоста: читает последние 8 байт и
         * сравнивает с magic "ALTRPK1\0". Без полного разбора и без CRC.
         */
        public static function hasTail(path:String):Bool
        {
                var r = readTrailer(path);
                return r.found;
        }

        /**
         * Полное чтение и верификация хвоста файла.
         * Весь payload читается в память (v1: КБ..МБ — приемлемо;
         * переоценка — в эпоху Assets).
         */
        public static function read(path:String):TailReadResult
        {
                // 1. Трейлер (stat + чтение последних 24 байт)
                var tr = readTrailer(path);
                if (tr.error != null)
                        return _res(false, false, null, 1, tr.error);
                if (!tr.found)
                        return _res(true, false, null, 0, null);

                // 2. Версия (magic уже сошёлся — дальше только строгий разбор)
                if (tr.version != VERSION)
                        return _res(false, true, null, 2,
                                "unsupported tail version " + tr.version +
                                " (reader supports " + VERSION + ")");

                // 3. Размер payload: u64 → lo/hi, hi обязан быть нулём.
                //    Дополнительно: лимит читателя v1 — 1 ГБ (беззнаковая
                //    чистота арифметики обхода entries).
                if (tr.payloadLenHi != 0)
                        return _res(false, true, null, 2,
                                "payload size exceeds 2 GB (unsupported in v1)");
                if (tr.payloadLenLo < 0)
                        return _res(false, true, null, 2,
                                "payload size low word has high bit set (corrupt)");
                if (tr.payloadLenLo > 0x40000000)
                        return _res(false, true, null, 2,
                                "payload size exceeds 1 GB (v1 reader limit)");

                // 4. Трейлер не должен указывать за пределы файла.
                //    Разностная форма: переполнение Int32 исключено.
                if (tr.payloadLenLo > tr.fileSize - TRAILER_SIZE)
                        return _res(false, true, null, 2,
                                "trailer points beyond file (payloadLen " +
                                tr.payloadLenLo + " + 24 > fileSize " + tr.fileSize + ")");

                // 5. Чтение payload
                var payloadLen = tr.payloadLenLo;
                var payload = Bytes.alloc(payloadLen);
                var fin:FileInput = null;
                try
                {
                        fin = File.read(path, true);
                        fin.seek(tr.fileSize - TRAILER_SIZE - payloadLen, SeekBegin);
                        if (!_readExact(fin, payload, 0, payloadLen))
                        {
                                fin.close();
                                return _res(false, true, null, 2, "payload truncated (unexpected EOF)");
                        }
                        fin.close();
                }
                catch (e:Dynamic)
                {
                        if (fin != null) { try { fin.close(); } catch (d:Dynamic) {} }
                        return _res(false, true, null, 1, "io error reading payload: " + e);
                }

                // 6. CRC контейнера
                var calcCrc = Crc32.make(payload);
                if (calcCrc != tr.payloadCrc)
                        return _res(false, true, null, 3,
                                "payload crc32 mismatch (stored " + hexU32(tr.payloadCrc) +
                                ", computed " + hexU32(calcCrc) + ")");

                // 7. Обход entries (переполнение исключено: каждый операнд
                // в [0, 2^31), суммы не образуются — сравнения разностные)
                var entries:Array<TailEntry> = [];
                var o:Int = 0;
                var idx:Int = 1;
                while (o < payloadLen)
                {
                        if (o + 3 > payloadLen)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + ": truncated entry header at offset " + o);

                        var type:Int = payload.get(o);
                        var nameLen:Int = _rdU16(payload, o + 1);
                        var nameOff:Int = o + 3;

                        if (nameOff + nameLen + 8 > payloadLen)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + ": header runs past payload at offset " + o);

                        var name:String = payload.getString(nameOff, nameLen);
                        var dLenLo:Int = _rdU32(payload, nameOff + nameLen);
                        var dLenHi:Int = _rdU32(payload, nameOff + nameLen + 4);

                        if (dLenHi != 0)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + " (" + name + "): data size exceeds 2 GB");
                        if (dLenLo < 0)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + " (" + name + "): data size low word corrupt");

                        var dataStart:Int = nameOff + nameLen + 8;

                        if (dLenLo >= payloadLen)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + " (" + name + "): data length " +
                                        dLenLo + " >= payload length " + payloadLen);
                        if (dataStart > payloadLen - dLenLo - 4)
                                return _res(false, true, null, 2,
                                        "entry #" + idx + " (" + name + "): data runs past payload");

                        var data:Bytes = payload.sub(dataStart, dLenLo);
                        var storedCrc:Int = _rdU32(payload, dataStart + dLenLo);
                        var calcCrcE:Int = Crc32.make(data);
                        if (calcCrcE != storedCrc)
                                return _res(false, true, null, 3,
                                        "entry #" + idx + " (" + name + ") crc32 mismatch (stored " +
                                        hexU32(storedCrc) + ", computed " + hexU32(calcCrcE) + ")");

                        entries.push({ type: type, name: name, data: data, crc32: calcCrcE });
                        o = dataStart + dLenLo + 4;
                        idx++;
                }

                // 8. Готово
                var baseSize:Int = tr.fileSize - TRAILER_SIZE - payloadLen;
                var c:TailContainer = {
                        version: tr.version,
                        flags: tr.flags,
                        payloadLen: payloadLen,
                        payloadCrc: tr.payloadCrc,
                        baseSize: baseSize,
                        fileSize: tr.fileSize,
                        entries: entries
                };
                return _res(true, true, c, 0, null);
        }

        // ── Утилиты ───────────────────────────────────────────────────────

        /** hex без знака, ровно 8 символов, детерминированно на всех таргетах. */
        public static function hexU32(v:Int):String
        {
                var out = "";
                var shifts = [24, 16, 8, 0];
                for (sh in shifts)
                        out += StringTools.hex((v >>> sh) & 0xFF, 2);
                return out;
        }

        // ── Внутренняя кухня ──────────────────────────────────────────────

        /**
         * Чтение и разбор трейлера (последних 24 байт). Не знает про
         * «законность» остальных полей — только magic и байтовую механику.
         */
        private static function readTrailer(path:String):_TrailerInfo
        {
                var none:_TrailerInfo = { found: false, error: null, fileSize: 0,
                                payloadLenLo: 0, payloadLenHi: 0, payloadCrc: 0,
                                version: 0, flags: 0 };

                if (!FileSystem.exists(path))
                {
                        none.error = "file not found: " + path;
                        return none;
                }

                var size:Int;
                try { size = FileSystem.stat(path).size; }
                catch (e:Dynamic)
                {
                        none.error = "cannot stat file: " + e;
                        return none;
                }

                if (size < TRAILER_SIZE)
                        return none;  // короче трейлера — хвоста нет, это не ошибка

                var t:Bytes = Bytes.alloc(TRAILER_SIZE);
                var fin:FileInput = null;
                try
                {
                        fin = File.read(path, true);
                        fin.seek(size - TRAILER_SIZE, SeekBegin);
                        if (!_readExact(fin, t, 0, TRAILER_SIZE))
                        {
                                fin.close();
                                none.error = "trailer truncated (unexpected EOF)";
                                return none;
                        }
                        fin.close();
                }
                catch (e:Dynamic)
                {
                        if (fin != null) { try { fin.close(); } catch (d:Dynamic) {} }
                        none.error = "io error reading trailer: " + e;
                        return none;
                }

                // magic: последние 8 байт = "ALTRPK1\0"
                if (t.get(16) != 0x41 || t.get(17) != 0x4C || t.get(18) != 0x54 ||
                    t.get(19) != 0x52 || t.get(20) != 0x50 || t.get(21) != 0x4B ||
                    t.get(22) != 0x31 || t.get(23) != 0x00)
                        return none;  // не наш magic — хвоста нет, это не ошибка

                return {
                        found: true,
                        error: null,
                        fileSize: size,
                        payloadLenLo: _rdU32(t, 0),
                        payloadLenHi: _rdU32(t, 4),
                        payloadCrc: _rdU32(t, 8),
                        version: _rdU16(t, 12),
                        flags: _rdU16(t, 14)
                };
        }

        /** Точное чтение len байт (FileInput может вернуть меньше за вызов). */
        private static function _readExact(i:FileInput, buf:Bytes, pos:Int, len:Int):Bool
        {
                var done:Int = 0;
                while (done < len)
                {
                        var n:Int = i.readBytes(buf, pos + done, len - done);
                        if (n <= 0) return false;
                        done += n;
                }
                return true;
        }

        /** Little-endian u16 из Bytes (ручная сборка — ноль неоднозначностей). */
        private static inline function _rdU16(b:Bytes, o:Int):Int
        {
                return b.get(o) | (b.get(o + 1) << 8);
        }

        /** Little-endian u32 из Bytes (битовый образ; Int может быть < 0 — это норма). */
        private static inline function _rdU32(b:Bytes, o:Int):Int
        {
                return b.get(o) | (b.get(o + 1) << 8) |
                       (b.get(o + 2) << 16) | (b.get(o + 3) << 24);
        }

        private static function _res(ok:Bool, tail:Bool, c:TailContainer, code:Int, msg:String):TailReadResult
        {
                return { ok: ok, tail: tail, container: c, errorCode: code, errorMessage: msg };
        }
}
