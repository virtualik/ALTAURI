package core.io;

// ============================================================================
// DeviceExporter v1.0 - [Export]: packing the instrument with a mouse click (Stage 3, Task 137)
// ----------------------------------------------------------------------------
// The orchestrator of the [P] Export button. The contract with Main: Main SAVES the current
// schematic (prepareCurrentAssemblyForSave + saveCurrentContext) BEFORE calling
// export() - the instrument carries what the user sees, not last year
// Selfrun.atom from the disk.
//
// SOURCES (decisions of the Task 124/125 planning session - v1 = the whole library):
//   base    = Sys.programPath() - the running editor. An export from an instrument
//             session (the editor carries its own tail)? The writer TRUNCATES the old
//             tail - anti-matryoshka (the PayloadTailWriter doctrine), the instrument
//             does not grow deeper on repacking.
//   scheme  = Selfrun.atom from disk (Documents/ALTAURI) - just written
//             by Main. No file -> an honest refusal (code 1).
//   library = a MERGE: the LIBRARY records of the tail (TailStartup, an instrument session)
//             union the Library folder on disk. On a name conflict the DISK has priority:
//             what survived the session (edits/new assemblies are written to disk) is
//             fresher than the tail snapshot. The tail guarantees self-sufficiency
//             of the instrument on a clean machine (the T-S2.1 world). A regular editor
//             (no tail) degenerates into the EXACT semantics of --pack of Stage 1 -
//             up to byte-identity of the output (T-EX.6).
//             Name sorting - determinism: the same library = a byte-identical tail (the LabCLI doctrine).
//             byte-identical to the tail (the LabCLI doctrine).
//
// GUARDS (canonical - PathCanon, lesson T-EMB.7):
//   - out == Selfrun.atom -> refuse: do not overwrite the source of truth of the schematic
//     (you can intercept it with a dialog, but you cannot climb out);
//   - out inside the Library folder -> refuse: do not overwrite the assembly library;
//   - out == base / the running exe -> refuse in the writer (canonical);
//   - overwriting an existing file asks the native dialog
//     (OFN_OVERWRITEPROMPT) - the guard does not duplicate the question.
//
// OUTPUT: ASCII-only in stdout, line by line in the --pack FORMAT (a metrological
// bridge: T-EX.6 diffed the body of the button output against the CLI output). The only
// difference is the first header line, honestly naming the command source.
// ============================================================================

import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

/** The export result (mirrors TailPackResult + source statistics). */
typedef ExportResult = {
        ok:Bool,
        errorCode:Int,          // 0/1/2/3 - the unified code doctrine
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

/**
 * DEVICE EXPORTER v1.0 (Stage 3, Task 137)
 * The orchestrator of the [P] Export button: base = the running editor (anti-matryoshka:
 * the writer TRUNCATES a foreign tail) + scheme = Selfrun.atom from disk (Main
 * SAVES the schematic BEFORE the call; no file -> an honest refusal, code 1) +
 * library = tail-session union disk (name conflict: disk priority).
 * Detailed specification and sources - in the // banner of the file.
 */
class DeviceExporter
{
        /**
         * Pack the instrument: base = the running exe, scheme = Selfrun.atom,
         * library = tail union disk (disk priority). Call AFTER
         * saving the schematic (Main.saveCurrentContext).
         * @param outPath the destination path (full, from the native dialog)
         */
        public static function export(outPath:String):ExportResult
        {
                if (outPath == null || outPath.length == 0)
                        return _fail(1, "output path is empty", outPath);

                // - base = the running exe (resolved BEFORE the output: the header and
                //    the base are the first lines, as in --pack) ----------------------
                var basePath:String = null;
                try { basePath = Sys.programPath(); } catch (e:Dynamic) { basePath = null; }
                if (basePath == null)
                        return _fail(1, "cannot resolve the running executable path", outPath);

                Sys.println("ALTAURI device export v1");
                Sys.println("base: " + basePath);

                // PM is initialized by the startup; init() here is a defensive
                // call for non-standard consumers (idempotency of
                // init() is NOT guaranteed - a repeated library scan;
                // therefore only when the paths are empty)
                var pm = system.managers.ProjectManager.getInstance();
                if (pm.libraryPath == null || pm.selfrunPath == null) pm.init();

                // - Guards of the sources of truth ------------------------------------
                if (PathCanon.samePath(outPath, pm.selfrunPath))
                        return _fail(1, "output path equals Selfrun.atom"
                                + " — refusing to overwrite the scheme source", outPath);
                if (PathCanon.isInsideDir(outPath, pm.libraryPath))
                        return _fail(1, "output path is inside the library folder"
                                + " — refusing to overwrite the library", outPath);

                // - Schematic: what Main has just saved -------------------------------
                if (!FileSystem.exists(pm.selfrunPath))
                        return _fail(1, "no Selfrun.atom at " + pm.selfrunPath
                                + " — save the scheme first", outPath);
                var schemeBytes:Bytes = File.getBytes(pm.selfrunPath);

                // - Library: tail union disk, the disk is prioritized ------------------
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
                                // the disk overrides the tail: session edits are fresher than the snapshot
                                merged.set(f, File.getBytes(pm.libraryPath + "/" + f));
                                diskCount++;
                        }
                }

                // determinism: name sorting on top of the merge
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

        /** Export failure: an honest line in the console (the --pack discipline),
         *  no file is created - there are no side effects. */
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

