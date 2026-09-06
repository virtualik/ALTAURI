package core.io;

// ============================================================================
// PayloadTail v1.0 - ALTRPK1 tail (Stage 1 "Single File", Task 132)
// ----------------------------------------------------------------------------
// ALTRPK1 container reader: a payload glued to the TAIL of the
// executable file. PE/ELF/Mach-O ignore bytes after the image - the tail
// is invisible to the OS and to the app itself until the app looks for it.
//
// ═══════════════════════════════════════════════════════════════════════════
// ALTRPK1 v1 FORMAT SPECIFICATION (little-endian, all integers)
// ═══════════════════════════════════════════════════════════════════════════
//
//   FILE   := [ BASE of any length ] [ ENTRY ]* [ TRAILER 24 bytes ]
//   ENTRY  := type u8 | nameLen u16 | name nameLen bytes UTF-8 |
//             dataLen u64 | data dataLen bytes | dataCrc32 u32
//   TRAILER:= payloadLen u64 | payloadCrc32 u32 | version u16 |
//             flags u16 | magic char[8] = "ALTRPK1\0"
//                         (41 4C 54 52 50 4B 31 00)
//
//   payloadLen  - total size of all ENTRY records (without the trailer).
//   payloadCrc  - CRC32 (zlib-compatible, haxe.crypto.Crc32) of the payload block.
//   version     - format version = 1. A reader of an UNKNOWN version must
//                 refuse (code 2), not guess.
//   dataCrc32   - CRC32 of the data field of each entry (double protection:
//                 container + record; damage is localized to a single entry).
//   magic       - the last 8 bytes of the file. Tail search = O(1): seek(-24).
//
//   ENTRY TYPES: 1 SCHEME   - a schematic (.atom, JSON)
//               2 ASSET    - a user asset (the Assets Manager era)
//               3 MANIFEST - a service manifest
//               4 LIBRARY  - a CustomAssembly_*.atom assembly (tail-backed
//                            library: tail takes priority over disk)
//   An UNKNOWN type is NOT an error: the record is skipped by dataLen (a forward
//   compatibility barrier - an old reader reads a new container).
//
//   FLAGS (advisory trailer metadata; the truth is in the entries):
//     bit0 FLAG_SCHEME   the container has a schematic
//     bit1 FLAG_ASSETS   the container has assets
//     bit2 FLAG_AUTORUN  instrument: run the schematic without the editor (headless era)
//     bit3 FLAG_LOCKED   the instrument in its finished form (Device-panel groundwork)
//
//   v1 STREAM BOUNDARIES (honest, in code and in the spec):
//     - u64 fields parse as lo/hi; hi != 0 -> refuse (code 2): payloads
//       over 2 GB are not supported in v1 (our reality is KB..MB);
//     - the v1 reader additionally caps the payload at 1 GB
//       (0x40000000): guarantees unsigned-clean traversal arithmetic
//       (offset sums never reach 2^31 for any input);
//     - all bound comparisons are DIFFERENCE-form (a > b - c instead of a + c > b),
//       Int32 overflow is excluded by construction.
//
//   WRITE DOCTRINE: writing into a RUNNING exe is forbidden (Windows -
//   sharing violation, Linux - image corruption). Repacking always goes to a NEW
//   file, anti-matryoshka: a foreign tail of base is truncated (see PayloadTailWriter).
//
//   Reader error codes = lab CLI exit codes (LabCLI):
//     0 - ok (including the honest answer "no tail")
//     1 - I/O error
//     2 - format error (version, structure, sizes)
//     3 - CRC mismatch (container or entry)
//
// DEPENDENCIES: std only (sys.*, sys.io.*, haxe.io.*, haxe.crypto.Crc32).
// The class compiles on sys targets only: the single call site
// (Main.new -> LabCLI) is wrapped in #if sys, DCE keeps the file off html5.
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): 1) import sys.FileSystem —
// sys.io.FileSystem paths do not exist in std Haxe; 2) typedefs
// moved from the class body to module level (Haxe grammar).
// The ALTRPK1 format, bytes and output texts are NOT changed.
// ============================================================================

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileSeek;
import sys.FileSystem;

// - Result structures - module-level types --------------------------------
// Haxe grammar: a typedef is allowed ONLY at module level, not inside
// a class body (lesson T-EMB.0: "Unexpected keyword typedef" at line 94).
// Public by default; the external path is core.io.PayloadTail.TailEntry,
// from within core.io the short PayloadTail.TailEntry is fine.

/** One container record (crc32 computed by the reader and already verified). */
typedef TailEntry = {
        type:Int,
        name:String,
        data:Bytes,
        ?crc32:Int
}

/** Parsed container. baseSize - the size of the clean exe without the tail. */
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
 * Read result. No exceptions - an explicit result so LabCLI can map
 * errorCode directly onto the process exit code.
 *   ok=true, tail=false -> no file tail (a legitimate answer)
 *   ok=true, tail=true  -> container parsed and verified
 *   ok=false            -> error; tail=true means "magic found,
 *                         but integrity/format is broken"
 */
typedef TailReadResult = {
        ok:Bool,
        tail:Bool,
        container:TailContainer,
        errorCode:Int,
        errorMessage:String
}

/** Trailer read result. */
private typedef _TrailerInfo = {
        found:Bool,          // magic matched
        error:String,        // io error (then found=false)
        fileSize:Int,
        payloadLenLo:Int,
        payloadLenHi:Int,
        payloadCrc:Int,
        version:Int,
        flags:Int
}

class PayloadTail
{
        // - Format constants -------------------------------------------------
        public static inline var TRAILER_SIZE:Int = 24;
        public static inline var VERSION:Int = 1;

        // Entry types
        public static inline var TYPE_SCHEME:Int = 1;
        public static inline var TYPE_ASSET:Int = 2;
        public static inline var TYPE_MANIFEST:Int = 3;
        public static inline var TYPE_LIBRARY:Int = 4;

        // Trailer flags
        public static inline var FLAG_SCHEME:Int = 0x0001;
        public static inline var FLAG_ASSETS:Int = 0x0002;
        public static inline var FLAG_AUTORUN:Int = 0x0004;
        public static inline var FLAG_LOCKED:Int = 0x0008;

        // - Public API -------------------------------------------------------

        /**
         * Fast tail presence check: reads the last 8 bytes and
         * compares them with the magic "ALTRPK1" (no marker byte). No full parse, no CRC.
         */
        public static function hasTail(path:String):Bool
        {
                var r = readTrailer(path);
                return r.found;
        }

        /**
         * Full read and verification of the file tail.
         * The whole payload is read into memory (v1: KB..MB is acceptable;
         * re-evaluation in the Assets era).
         */
        public static function read(path:String):TailReadResult
        {
                // 1. Trailer (stat + read of the last 24 bytes)
                var tr = readTrailer(path);
                if (tr.error != null)
                        return _res(false, false, null, 1, tr.error);
                if (!tr.found)
                        return _res(true, false, null, 0, null);

                // 2. Version (magic already matched - strict parsing from here)
                if (tr.version != VERSION)
                        return _res(false, true, null, 2,
                                "unsupported tail version " + tr.version +
                                " (reader supports " + VERSION + ")");

                // 3. Payload size: u64 -> lo/hi, hi must be zero.
                //    Additionally: the v1 reader limit - 1 GB (unsigned
                //    cleanliness of the traversal arithmetic).
                if (tr.payloadLenHi != 0)
                        return _res(false, true, null, 2,
                                "payload size exceeds 2 GB (unsupported in v1)");
                if (tr.payloadLenLo < 0)
                        return _res(false, true, null, 2,
                                "payload size low word has high bit set (corrupt)");
                if (tr.payloadLenLo > 0x40000000)
                        return _res(false, true, null, 2,
                                "payload size exceeds 1 GB (v1 reader limit)");

                // 4. The trailer must not point past the file.
                //    Difference form: Int32 overflow is excluded.
                if (tr.payloadLenLo > tr.fileSize - TRAILER_SIZE)
                        return _res(false, true, null, 2,
                                "trailer points beyond file (payloadLen " +
                                tr.payloadLenLo + " + 24 > fileSize " + tr.fileSize + ")");

                // 5. Payload read
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

                // 6. Container CRC
                var calcCrc = Crc32.make(payload);
                if (calcCrc != tr.payloadCrc)
                        return _res(false, true, null, 3,
                                "payload crc32 mismatch (stored " + hexU32(tr.payloadCrc) +
                                ", computed " + hexU32(calcCrc) + ")");

                // 7. Entry traversal (overflow excluded: every operand
                // is in [0, 2^31), no sums are formed - comparisons are difference-form)
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

                // 8. Done
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

        // - Utilities ----------------------------------------------------------

        /** Hex without a sign, exactly 8 chars, deterministic on all targets. */
        public static function hexU32(v:Int):String
        {
                var out = "";
                var shifts = [24, 16, 8, 0];
                for (sh in shifts)
                        out += StringTools.hex((v >>> sh) & 0xFF, 2);
                return out;
        }

        // - Internal kitchen ---------------------------------------------------

        /**
         * Trailer read and parse (the last 24 bytes). Knows nothing about
         * the "legality" of the other fields - only the magic and byte mechanics.
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
                        return none;  // shorter than the trailer - no tail, not an error

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

                // magic: the last 8 bytes = the ALTRPK1 marker
                if (t.get(16) != 0x41 || t.get(17) != 0x4C || t.get(18) != 0x54 ||
                    t.get(19) != 0x52 || t.get(20) != 0x50 || t.get(21) != 0x4B ||
                    t.get(22) != 0x31 || t.get(23) != 0x00)
                        return none;  // not our magic - no tail, not an error

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

        /** Exact read of len bytes (FileInput may return fewer per call). */
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

        /** Little-endian u16 from Bytes (manual assembly - zero ambiguity). */
        private static inline function _rdU16(b:Bytes, o:Int):Int
        {
                return b.get(o) | (b.get(o + 1) << 8);
        }

        /** Little-endian u32 from Bytes (bit pattern; Int may be < 0 - that is normal). */
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
