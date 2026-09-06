package core.io;

// ============================================================================
// LabCLI v1.0 - the ALTAURI lab CLI (Stage 1, Task 132)
// ----------------------------------------------------------------------------
// The instrument mode of the editor BEFORE the [Export] button appeared: packing
// an "instrument" (--pack) and opening the tail (--inspect) right from the command line
// of the Station. Called from Main.new() wrapped in #if sys BEFORE any
// UI initialization; returning true requires an immediate Sys.exit(exitCode).
//
// This is the PROTOTYPE of the [Export] button (Stage 3): --pack does exactly what
// the button will do - takes ITSELF (or --base), the Schematic (Selfrun.atom) and the ENTIRE
// library of CustomAssembly_*.atom from Documents/ALTAURI (the decision of the Task 124/125
// planning session: v1 = the whole library) and stamps out a single file.
//
// OUTPUT: ASCII-only, DELIBERATELY. Cyrillic in cmd.exe = cp866 mojibake;
// the lab terminal discipline is Latin script.
//
// ARGV DISCIPLINE: the first argument is our flag -> process it and exit;
// no arguments -> a regular editor start (zero regression: a double
// click and FD F5 pass no arguments); a NON-flag (for example, a .atom file dropped
// onto the exe) -> ignore it, the editor starts - this is the groundwork of Stage 2
// (the priority argv-file > tail > Selfrun.atom).
//
// EXIT CODES (the doctrine of Task 123 V.3, unified with the reader/writer):
//   0 - success ("no tail" for --inspect is also success, an honest answer)
//   1 - an I/O or usage error
//   2 - a format error
//   3 - a CRC mismatch (data corruption)
//
// HOTFIX v1.0.1 (Task 133, T-EMB.0): import sys.FileSystem - the paths
// sys.io.FileSystem do not exist in std Haxe ("Type not found" on
// the Station; the reference of the correct path is ProjectManager.hx:7). The CLI output
// and exit codes are unchanged.
// ============================================================================

import sys.io.File;
import sys.FileSystem;

/**
 * LAB CLI v1.0.1 (Stage 1, Task 132 + hotfix 133)
 * The lab CLI: --pack (packing an instrument) / --inspect (opening the tail)
 * from Main.new() under #if sys, BEFORE the UI; returned true -> an immediate Sys.exit.
 * Exits: 0 success / 1 I-O / 2 format / 3 CRC. ASCII-only output.
 * Detailed specification - in the // banner of the file.
 */
class LabCLI
{
        /** The exit code after command processing (valid when true is returned). */
        public static var exitCode:Int = 0;

        /**
         * The main dispatcher. true = the command was processed, the caller (Main)
         * must exit immediately: Sys.exit(LabCLI.exitCode).
         * false = there are no arguments for us - start the editor as usual.
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

                // Not a flag: not our business (the groundwork of Stage 2). The editor starts.
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

                // Metrological meticulousness: the flags are advisory,
                // the entries are the truth; a discrepancy deserves publicity.
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
                // Parsing: exactly one positional <out> + optionally --base <path>
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

                // The schematic and the library - from the single source of truth of paths
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

                // The library: the WHOLE one (the v1 doctrine, Task 125). Sorting -
                // determinism: the same library = a byte-identical tail.
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

        // - Common ---------------------------------------------------------------

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
                // IMPORTANT: the parentheses are mandatory - in Haxe "&" binds weaker than "!="
                // (a classic precedence trap: f & FLAG != 0 reads as
                // f & (FLAG != 0) - not what we want)
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

