package core.io;

// ============================================================================
// PathCanon v1.0 - canonicalization of write paths (Stage 3 "The [Export] Button", Task 137)
// ----------------------------------------------------------------------------
// A LEXICAL canonicalizer: brings a path to a comparable form BEFORE matching
// it against Sys.programPath()/base/the sources of truth.
//
// HISTORICAL REASON (lesson T-EMB.7, Stage 1): the string guard of the writer
// let a RELATIVE path through - "ALTAURI_Windows.exe" typed in the folder
// of the exe itself is not string-equal to "C:\...\bin\ALTAURI_Windows.exe"; the OS
// saved the day (a sharing violation, code 1 with a vague "io error"). Now the
// canonical guard fires IN CODE, with a clear message.
//
// CANONICALIZATION RULES (pure lexics, no filesystem queries):
//   1. null/empty -> "";
//   2. Win32 namespace prefixes "\\\\?\" / "\\\\.\\" are cut off
//      («\\?\UNC\» → «\\»);
//   3. separators unified to "/";
//   4. a relative path is completed from Sys.getCwd() (or the cwd argument
//      of a test);
//   5. "." segments and empty ones (double slashes) are dropped; ".." eats
//      the previous segment, above the root it eats itself;
//   6. trailing slashes are cut (except the roots "C:/" and "/");
//   7. CASE: samePath() on Windows compares case-insensitively, on
//      other targets honestly (the ci argument overrides for tests).
//      canonical() NEVER changes the case - the form stays lossless.
//
// WHAT THE CANONICALIZER DOES NOT DO (v1 honesty, documented):
//   - does NOT resolve 8.3 names (PROGRA~1), symlinks/junctions, SUBST drives -
//     that is a filesystem query; the OS guard (the ban on writing
//     into a running exe) remains the last line of defense;
//   - does NOT check path existence - text only.
//
// Discipline: a pure function of a string (+ an optional cwd). Does not compile
// on non-sys targets (not referenced outside #if sys code).
// ============================================================================

/**
 * PATH CANON v1.0 (Stage 3, Task 137)
 * A lexical canonicalizer of write paths: brings a path to a comparable form BEFORE
 * matching it against Sys.programPath()/the sources of truth. The historical
 * reason - lesson T-EMB.7: the string guard let a RELATIVE path through ->
 * a sharing violation from the OS; now the canonical guard lives in code.
 * A pure function of a string (+ an optional cwd); the rules are in the // banner.
 */
class PathCanon
{
        /**
         * The canonical form: absolute, "/" separators, no "./..",
         * no trailing slashes. Case preserved (comparison - samePath).
         * @param path the original path (null/empty -> "")
         * @param cwd  the working directory for completing relative paths;
         *             null = Sys.getCwd() (tests substitute their own)
         */
        public static function canonical(path:String, ?cwd:String):String
        {
                if (path == null || path.length == 0) return "";

                var p:String = path;

                // - 1) Win32 namespace prefixes ---------------------------
                if (StringTools.startsWith(p, "\\\\?\\UNC\\"))
                        p = "\\" + p.substr(8);
                else if (StringTools.startsWith(p, "\\\\?\\"))
                        p = p.substr(4);
                else if (StringTools.startsWith(p, "\\\\.\\"))
                        p = p.substr(4);

                // - 2) separator unification -------------------------------
                p = StringTools.replace(p, "\\", "/");

                // - 3) completing relative paths ---------------------------
                if (!_isAbsolute(p))
                {
                        var base:String = (cwd != null) ? cwd : _sysCwd();
                        base = StringTools.replace(base, "\\", "/");
                        if (base.length > 0 && !StringTools.endsWith(base, "/")) base += "/";
                        p = base + p;
                }

                // - 4) segment parsing -------------------------------------
                var parts:Array<String> = p.split("/");

                // the root: "C:/..." -> the prefix "C:/"; "/..." -> "/"; "//srv/..." -> "//"
                var prefix:String = "";
                var first:Int = 0;
                if (parts.length > 0 && _isDrive(parts[0]))
                {
                        prefix = parts[0] + "/";
                        first = 1;
                }
                else if (StringTools.startsWith(p, "//"))
                {
                        prefix = "//";
                        first = 1;   // parts[0] == "" - eaten by the prefix
                }
                else if (StringTools.startsWith(p, "/"))
                {
                        prefix = "/";
                        first = 1;   // parts[0] == "" - eaten by the prefix
                }

                var out:Array<String> = [];
                var i:Int = first;
                while (i < parts.length)
                {
                        var seg:String = parts[i];
                        if (seg == "" || seg == ".")
                        {
                                // empty segments and "." are garbage
                        }
                        else if (seg == "..")
                        {
                                if (out.length > 0) out.pop();
                                // ".." above the root - eaten silently: there is
                                // nothing above the root
                        }
                        else
                        {
                                out.push(seg);
                        }
                        i++;
                }

                var joined:String = out.join("/");
                if (prefix == "")
                {
                        // theory: a non-absolute path with an empty cwd - stays
                        // as is (trailing slashes already cut by split/join)
                        return joined;
                }
                return prefix + joined;
        }

        /**
         * Comparing write paths in canonical forms.
         * @param caseInsensitive null = auto (#if windows -> yes); tests on
         *                         Linux substitute true for Windows forms
         * @param cwd             the working directory for both sides (tests)
         */
        public static function samePath(a:String, b:String,
                        ?caseInsensitive:Null<Bool>, ?cwd:String):Bool
        {
                if (a == null || b == null) return false;
                // Null<Bool> -> Bool WITHOUT a null literal: on static
                // platforms (cpp/hl) null for the base type Bool
                // is illegal (a Station field: PathCanon 139/160, Task 138).
                var ci:Bool = (caseInsensitive != null) ? caseInsensitive : _isWindows();
                var x:String = canonical(a, cwd);
                var y:String = canonical(b, cwd);
                if (ci)
                {
                        x = x.toLowerCase();
                        y = y.toLowerCase();
                }
                return x == y;
        }

        /**
         * Whether the path is INSIDE the directory (strictly below, not the directory itself).
         * Comparison of canonical forms with a trailing separator - the
         * prefix trap ("C:/xlib" is not inside "C:/x/lib") is excluded.
         */
        public static function isInsideDir(path:String, dir:String,
                        ?caseInsensitive:Null<Bool>, ?cwd:String):Bool
        {
                if (path == null || dir == null) return false;
                // Null<Bool> -> Bool WITHOUT a null literal: on static
                // platforms (cpp/hl) null for the base type Bool
                // is illegal (a Station field: PathCanon 139/160, Task 138).
                var ci:Bool = (caseInsensitive != null) ? caseInsensitive : _isWindows();
                var p:String = canonical(path, cwd);
                var d:String = canonical(dir, cwd);
                if (ci)
                {
                        p = p.toLowerCase();
                        d = d.toLowerCase();
                }
                if (d == "" || d == "/") return true;  // the root embraces everything
                if (!StringTools.endsWith(d, "/")) d += "/";
                return StringTools.startsWith(p, d);
        }

        /**
         * The directory of a path WITHOUT canonicalization (the spelling is preserved - fit
         * for native APIs). Finds the last separator of any kind.
         * «C:\a\b\c.exe» → «C:\a\b»; «c.exe» → «»; «/x» → «/».
         */
        public static function dirname(path:String):String
        {
                if (path == null) return "";
                var i1:Int = path.lastIndexOf("/");
                var i2:Int = path.lastIndexOf("\\");
                var idx:Int = (i1 > i2) ? i1 : i2;
                if (idx < 0) return "";
                if (idx == 0) return path.charAt(0);   // «/x» → «/»
                return path.substr(0, idx);
        }

        // - Internal kitchen ---------------------------------------------------

        /** Absolute after slash unification: "/..." or "X:/...". */
        private static function _isAbsolute(p:String):Bool
        {
                if (StringTools.startsWith(p, "/")) return true;   // including UNC "//"
                if (p.length >= 3 && _isDrive(p.substr(0, 2)) && p.charAt(2) == "/")
                        return true;
                // "C:file" (drive-relative, a Windows curiosity) is canonicalized
                // as relative - v1 honesty documented
                return false;
        }

        /** A segment of the form "C:" (a Latin letter + a colon). */
        private static inline function _isDrive(s:String):Bool
        {
                if (s == null || s.length != 2) return false;
                var c:Int = s.charCodeAt(0);
                var d:Int = s.charCodeAt(1);
                var letter:Bool = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
                return letter && d == 58;   // ':'
        }

        private static function _sysCwd():String
        {
                try { return Sys.getCwd(); } catch (e:Dynamic) { return ""; }
        }

        private static inline function _isWindows():Bool
        {
                #if windows
                return true;
                #else
                return false;
                #end
        }
}

