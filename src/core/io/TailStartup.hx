package core.io;

// ============================================================================
// TailStartup v1.1 - the schematic startup source (Stage 2 "Tail Read", Task 135)
// v1.1 (Stage 3, Task 137): + tailLibrarySnapshot() - a snapshot of the LIBRARY-
// record bytes for DeviceExporter (export from an instrument session). Startup
// behavior unchanged to the byte.
// ----------------------------------------------------------------------------
// SCHEMATIC PRIORITY AT START: argv > TAIL > Selfrun.atom (Documents/ALTAURI):
//   argv    - the first NON-flag argument (a file dropped onto the exe) - open it;
//   tail    - an ALTRPK1 container at the end of the OWN exe (an "instrument": Device.exe
//             carries the schematic and the library inside itself, the machine can be empty);
//   Selfrun - a regular editor, as it was before Stage 2 (zero regression).
//
// LIBRARY: a valid tail with TYPE_LIBRARY records -> the library comes ENTIRELY from
// the tail; the Documents/ALTAURI/Library folder is NOT scanned (the instrument carries
// its own world - determinism: the instrument does not depend on the machine). No tail -> scan
// the folder as before. A broken tail (CRC/version/structure) = an instrument with broken
// firmware: a console warning and a fallback to disk, we do NOT crash.
//
// DIAGNOSTICS: ASCII-only in stdout (the lab terminal discipline).
// A regular editor without arguments and without a tail prints NOTHING - zero
// console regression.
//
// CALL POINT: Main.new() - AFTER LabCLI (CLI commands have already exited; --pack reads
// Documents directly and is not touched by the tail: install() was not called,
// hasTailLibrary()==false, the writer works as in Stage 1) and BEFORE
// ProjectManager.init() (it decides: the library from the tail or a folder scan).
// install() is idempotent.
//
// DEPENDENCIES: PayloadTail + std; the only integration seam is
// loadLibraryToRegistry() -> library.AtomRegistry.loadAtomContent (a precedent
// of dependencies: LabCLI -> system.managers.ProjectManager). Compiles
// on sys targets only (the call is wrapped in #if sys in Main).
//
// v1 BOUNDARIES (recorded honestly):
//   - the argv file opens AS A SCHEMATIC (a Selfrun-format .atom); the truth is
//     the first non-flag argument, the rest of the arguments are ignored in v1;
//   - argv changes ONLY the schematic; the library remains the world of the instrument (the tail);
//   - saving still goes to Documents/ALTAURI: editing the instrument writes a copy
//     to disk, but the instrument remains the carrier of its schematic ("firmware");
//   - several SCHEME records: the first one is the truth (the writer puts exactly one);
//   - trailer flags are advisory, the truth is in the entries (the PayloadTail doctrine).
// ============================================================================

import sys.FileSystem;
import sys.io.File;

/**
 * TAIL STARTUP v1.1 (Stage 2, Task 135; v1.1 - Stage 3, Task 137)
 * The schematic source at startup: argv > TAIL > Selfrun.atom. The instrument carries
 * the library ENTIRELY from the tail (the Documents folder is not scanned); a broken
 * tail = fallback to disk, we do NOT crash. install() is idempotent; called from
 * Main.new() between LabCLI and ProjectManager.init().
 * v1.1: + tailLibrarySnapshot() - a snapshot of the LIBRARY bytes for DeviceExporter
 * (export from an instrument session); startup behavior unchanged.
 * Detailed specification - in the // banner of the file.
 */
class TailStartup
{
        // - State (filled once in install()) ---------------------------------

        private static var _installed:Bool = false;

        /** The first NON-flag argument (a schematic file), if there was one. */
        private static var _argvPath:String = null;
        /** The content of the argv file (null = unreadable/absent). */
        private static var _argvContent:String = null;

        /** The tail was found and is valid. */
        private static var _tailOk:Bool = false;
        /** The tail was found but is broken (the reader error text). */
        private static var _tailError:String = null;
        private static var _tailVersion:Int = 0;
        private static var _tailEntryCount:Int = 0;
        /** The content of the first SCHEME record of the tail. */
        private static var _tailScheme:String = null;
        /** The LIBRARY records of the tail (container order = writer sort order). */
        private static var _libEntries:Array<PayloadTail.TailEntry> = [];

        /** The final schematic content (argv/tail) or null -> disk (Selfrun.atom). */
        private static var _schemeContent:String = null;
        /** Where the schematic came from: "argv" | "tail" | "disk". */
        private static var _schemeSource:String = "disk";

        /**
         * Reconnaissance of the startup sources. Production calls install() with no arguments
         * from Main.new() exactly once; the parameters are for bench tests.
         * @param exePath    the path of the own exe (default: Sys.programPath())
         * @param forceArgs  a substitution of the command line arguments (tests);
         *                   null = the real Sys.args()
         */
        public static function install(?exePath:String, ?forceArgs:Array<String>):Void
        {
                if (_installed) return;
                _installed = true;

                // - 1) argv: the first NON-flag argument = a schematic file ---------
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

                // - 2) the own tail ---------------------------------------------------
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
                                _tailError = r.errorMessage;  // an instrument with broken firmware
                        }
                        // ok && !tail - a regular exe: silence
                }

                // - 3) schematic priority: argv > tail > disk -----------------------
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

        // - Public API (consumers: ProjectManager, tests) ---------------------

        /** The schematic content by the priority argv > tail; null = disk (Selfrun.atom). */
        public static function readSchemeContent():Null<String>
        {
                return _schemeContent;
        }

        /** Where the schematic came from: "argv" | "tail" | "disk". */
        public static function schemeSource():String
        {
                return _schemeSource;
        }

        /** The library is in the tail and valid -> ProjectManager.init does not scan the folder. */
        public static function hasTailLibrary():Bool
        {
                return _tailOk && _libEntries.length > 0;
        }

        /** The names of the LIBRARY records of the tail. */
        public static function tailLibraryNames():Array<String>
        {
                var names:Array<String> = [];
                for (e in _libEntries) names.push(e.name);
                return names;
        }

        /**
         * A snapshot of the LIBRARY records of the tail (name + bytes as in the container).
         * Consumer: DeviceExporter (Stage 3) - merging the library during
         * export from an instrument session. The bytes are passed by reference -
         * the consumer must treat them as read-only.
         */
        public static function tailLibrarySnapshot():Array<{name:String, data:haxe.io.Bytes}>
        {
                var out:Array<{name:String, data:haxe.io.Bytes}> = [];
                for (e in _libEntries) out.push({ name: e.name, data: e.data });
                return out;
        }

        /**
         * Register the tail library in AtomRegistry. The integration
         * seam of Stage 2: called from ProjectManager.init() INSTEAD OF
         * AtomRegistry.scanFolder when the instrument carries its library inside.
         * @return true - at least one assembly registered
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

        /** Whether install() has run (guards calls before it). */
        public static function isInstalled():Bool
        {
                return _installed;
        }

        // - Diagnostics (ASCII-only; the silence of a regular editor) ----------

        private static function _report():Void
        {
                // Zero console regression: a regular editor (no argv,
                // no tail) prints nothing.
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

