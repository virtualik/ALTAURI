package core.io;

// ============================================================================
// PayloadTailWriter v1.1 - the ALTRPK1 packer (Stage 1, Task 132)
// v1.1 (Stage 3, Task 137): the guards compare CANONICAL path forms
// (PathCanon) - a relative path no longer bypasses the string
// guard (lesson T-EMB.7). The io calls use the paths AS IS -
// the write behavior is unchanged.
// ----------------------------------------------------------------------------
// Glues the ALTRPK1 container (see PayloadTail.hx - the specification) to a copy
// of the executable file: [ BASE ] [ ENTRY ]* [ TRAILER ].
//
// DOCTRINES wired into the code:
//
//  1. NEVER write into a running exe and never write over base.
//     The guards compare CANONICAL forms (PathCanon.samePath):
//     the absolute form + unified slashes + "./.." lexics + on
//     Windows case-insensitively. A relative path pointing to the
//     running exe (the T-EMB.7 firmware) is now caught IN CODE with a clear
//     message; the OS guard (sharing violation) remains the last
//     line of defense for what lexics cannot prove (SUBST,
//     symlinks, 8.3 names).
//
//  2. ANTI-MATRYOSHKA: if base carries a foreign ALTRPK1 tail - it is TRUNCATED
//     when copying (only the clean baseSize bytes are copied). Repacking
//     on top of a packed one does not grow deeper - pack3 is stable in size.
//     A tail with an unknown version or a broken structure = REFUSAL (code 2):
//     cutting a foreign format "somehow" is not allowed.
//
//  3. STREAMING: base is copied in chunks (64 KB), the payload is assembled in
//     memory (KB..MB - acceptable in v1). The exe memory is not doubled.
//
//  4. PURITY: the writer is a dumb transport. The flags are passed AS IS
//     (the policy belongs to the caller: LabCLI / a future Export dialog). The CRC
//     of each entry and of the container is computed ONLY from data - the
//     crc32 field of the input entries is ignored (we do not trust, we verify).
//
// Error codes - the same 0/1/2/3 as the reader has (LabCLI translates
// them into process exit codes).
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): 1) import sys.FileSystem - the paths
// sys.io.FileSystem do not exist in std Haxe; 2) typedefs moved
// to module level (Haxe grammar). The writer behavior is NOT changed.
// ============================================================================

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.io.FileSeek;
import sys.FileSystem;

// - Result types - module level ------------------------------------------
// Haxe grammar: a typedef is allowed ONLY at module level, not inside
// a class body (lesson T-EMB.0). From outside: core.io.PayloadTailWriter.TailPackResult.

/** The packing result. */
typedef TailPackResult = {
        ok:Bool,
        errorCode:Int,
        errorMessage:String,
        baseSize:Int,          // the original size of base (with a foreign tail, if any)
        cleanBaseSize:Int,     // how many bytes of base were copied (without the tail)
        truncatedOldTail:Bool, // whether base had a foreign tail and whether it was truncated
        payloadLen:Int,
        payloadCrc:Int,
        outSize:Int,
        entriesPacked:Int
}

/** Reconnaissance of the foreign tail of base: magic + mechanics (without payload CRC). */
private typedef _Probe = { found:Bool, payloadLen:Int, code:Int, error:String }

class PayloadTailWriter
{
        private static inline var CHUNK:Int = 65536;  // 64 KB

        /**
         * Assemble out = base (without a foreign tail) + entries + the trailer.
         * basePath - the source (we read, do not touch); outPath - the target (we create).
         */
        public static function pack(basePath:String, outPath:String,
                        entries:Array<PayloadTail.TailEntry>, flags:Int):TailPackResult
        {
                // - Write guards ------------------------------------------------------
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

                // - Anti-matryoshka: how much clean base to copy ----------------------
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

                // - Assembling the payload in memory -----------------------------------
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
                        _wU32(buf, 0);               // hi (v1: the length is < 2 GB by the construction of Bytes)
                        buf.write(e.data);
                        _wU32(buf, Crc32.make(e.data));
                }
                var payload:Bytes = buf.getBytes();
                var payloadCrc:Int = Crc32.make(payload);

                // - Streaming write: base chunks -> payload -> trailer -----------------
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

        // - Internal kitchen -----------------------------------------------------

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
                        return none;  // no foreign tail - copy base entirely

                // The tail is present - its mechanics must be impeccable, otherwise refusal
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
                // Difference form: Int32 overflow is excluded (size >= 24 is guaranteed here)
                if (plLo > size - PayloadTail.TRAILER_SIZE)
                        return { found: true, payloadLen: 0, code: 2,
                                error: "base tail points beyond file — refusing (corrupt)" };

                return { found: true, payloadLen: plLo, code: 0, error: null };
        }

        /** Reading exactly want bytes; the return is how many were actually read. */
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

        // - Little-endian write primitives (Output is the common ancestor
        //    of BytesOutput and FileOutput; manual assembly - zero ambiguities)

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

        /** The magic marker of the tail - 8 bytes, the last one NUL. */
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

        /** Deleting an unfinished out after an error (best effort). */
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
