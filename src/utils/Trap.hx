package utils;

// ============================================================================
// v1.4.1 HOTFIX: @:cppFileCode MUST sit at CLASS level (before "class Trap").
// In v1.4 it was written inside the class body, so the metadata attached to
// the boot() FIELD. hxcpp reads :cppFileCode from the CLASS only, so the
// whole native block (includes + SEH sentinel) never reached Trap.cpp while
// the __cpp__ code inside boot() did — MSVC: C2065/C3861 x8
// (_open/_dup2/_close/_O_*/SetUnhandledExceptionFilter/_altauri_trap_seh_filter).
// Pattern below mirrors the proven one from ComPortAtom / SystemVUMeterAtom:
// #if cpp -> @:cppFileCode(...) -> #end -> class.
// ============================================================================
#if cpp
@:cppFileCode('
#if defined(_WIN32) && !defined(ALTAURI_TRAP_SENTINEL_CODE)
#define ALTAURI_TRAP_SENTINEL_CODE

// Hygiene (same guards as ComPortAtom / SystemVUMeterAtom native blocks):
// keep aggressive windows.h macros out of the rest of this TU.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <stdint.h>
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>

// ── Native SEH sentinel (Episod H-1) ─────────────────────────────────────
// Pure WinAPI only: when the filter runs, the CRT (and anything heap-based)
// may already be corrupt. No printf, no allocations — just CreateFile/Write.
//
// ESCAPE RULE: this whole block is a single-quoted HAXE string. Haxe
// processes escape sequences, so ONE backslash here would silently change
// the emitted C code (v1.4 carried LF-escapes inside C string literals,
// Haxe turned them into real newlines, C2001 was waiting to fire).
// Rule for this block: ZERO backslashes. Newlines are written explicitly
// as buf[p++] = 10 (ASCII LF). Keep it that way.

static unsigned int _altauri_trap_copy(char* dst, const char* src)
{
        unsigned int n = 0;
        while (src != nullptr && src[n] != 0) { dst[n] = src[n]; n++; }
        return n;
}

static void _altauri_trap_hex16(char* out, unsigned long long v)
{
        static const char hx[] = "0123456789ABCDEF";
        for (int i = 0; i < 16; i++) { out[15 - i] = hx[v & 0xFULL]; v >>= 4; }
}

static void _altauri_trap_append_raw(const char* data, unsigned int len)
{
        HANDLE h = CreateFileA("crash_trap.log", FILE_APPEND_DATA,
                FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h == INVALID_HANDLE_VALUE) return;
        DWORD written = 0;
        WriteFile(h, data, len, &written, NULL);
        CloseHandle(h);
}

static LONG WINAPI _altauri_trap_seh_filter(EXCEPTION_POINTERS* ep)
{
        char buf[160];
        unsigned int p = 0;
        buf[p++] = 10; // leading LF — see ESCAPE RULE above
        p += _altauri_trap_copy(buf + p, "[TRAP-NATIVE-CRASH] exception code=0x");
        char hx[16];
        unsigned long long code = 0;
        unsigned long long addr = 0;
        if (ep != nullptr && ep->ExceptionRecord != nullptr)
        {
                code = (unsigned long long)(unsigned long)ep->ExceptionRecord->ExceptionCode;
                addr = (unsigned long long)(uintptr_t)ep->ExceptionRecord->ExceptionAddress;
        }
        _altauri_trap_hex16(hx, code);
        for (int i = 0; i < 8; i++) buf[p++] = hx[i]; // codes fit in 8 hex
        p += _altauri_trap_copy(buf + p, " addr=0x");
        _altauri_trap_hex16(hx, addr);
        for (int i = 0; i < 16; i++) buf[p++] = hx[i];
        p += _altauri_trap_copy(buf + p, " (see also stderr_capture.log)");
        buf[p++] = 10; // trailing LF — see ESCAPE RULE above
        _altauri_trap_append_raw(buf, p);
        return EXCEPTION_CONTINUE_SEARCH; // let the OS finish the crash
}

#endif // ALTAURI_TRAP_SENTINEL_CODE
#if !defined(_WIN32)
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#endif
')
#end

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                        TRAP v1.4.1                                        ║
* ║          (Crash-Proof Trace Logger — Episod H-1 «Black Box»)              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PURPOSE:                                                                 ║
* ║  stdout on Windows is BUFFERED when the app runs through "lime run"       ║
* ║  (pipe). On a hard crash (c0000005) the buffered tail is LOST —           ║
* ║  exactly the most valuable part (the last moments before death).          ║
* ║  TRAP writes every line to crash_trap.log with IMMEDIATE FLUSH.           ║
* ║  Data that was flushed before the crash survives it.                      ║
* ║                                                                           ║
* ║  v1.4.1 HOTFIX (compile, 2026-08-27):                                     ║
* ║  - v1.4 DID NOT COMPILE: @:cppFileCode sat INSIDE the class body,         ║
* ║    so the metadata attached to the boot() FIELD. hxcpp reads              ║
* ║    :cppFileCode from the CLASS only → the whole native block              ║
* ║    (io.h/fcntl.h/windows.h + _altauri_trap_seh_filter) never              ║
* ║    reached Trap.cpp, while the __cpp__ code in boot() did →               ║
* ║    C2065/C3861 x8 (_open/_dup2/_close/_O_CREAT/_O_WRONLY/_O_APPEND/       ║
* ║    SetUnhandledExceptionFilter/_altauri_trap_seh_filter).                 ║
* ║    FIX: metadata moved to class level — the exact pattern that            ║
* ║    already compiles in ComPortAtom / SystemVUMeterAtom.                   ║
* ║  - Hygiene: NOMINMAX + WIN32_LEAN_AND_MEAN guards before windows.h,       ║
* ║    #include <stdint.h> for uintptr_t.                                     ║
* ║                                                                           ║
* ║  v1.4 (Episod H-1) — THE BLACK BOX. Field report 2026-08-27:              ║
* ║  app died with lime "Done(1)", crash_trap.log ended on a BEAT             ║
* ║  ~1 s after entering a ComPort assembly, exit path never started,         ║
* ║  no exception text anywhere. Two dark channels swallow the evidence:      ║
* ║    1) hxcpp prints uncaught exceptions to STDERR — "lime run" pipe        ║
* ║       captures stdout only, stderr is lost;                               ║
* ║    2) a native crash (SEH) never prints anything at all.                  ║
* ║  v1.4 closes both channels:                                               ║
* ║    - boot(): dup2() redirects fd 2 (stderr) into stderr_capture.log —     ║
* ║      every "Uncaught exception : ..." + stack the runtime prints          ║
* ║      from now on lands in a file that survives the crash;                 ║
* ║    - boot(): SetUnhandledExceptionFilter installs a sentinel that         ║
* ║      appends "[TRAP-NATIVE-CRASH] code=0x... addr=0x..." to               ║
* ║      crash_trap.log using pure WinAPI (no CRT) before the OS kills        ║
* ║      the process — one run tells Haxe-exception vs segfault;              ║
* ║    - ex(tag, fn): guarded-call wrapper for the "dark zone" —              ║
* ║      openfl display events and haxe.Timer callbacks have NO               ║
* ║      try/catch anywhere; Trap.ex logs the exception WITH its Haxe         ║
* ║      stack and swallows it, so the app keeps running AND we get           ║
* ║      the report.                                                          ║
* ║                                                                           ║
* ║  USAGE:                                                                   ║
* ║    utils.Trap.boot();            // once, first line of Main.new()        ║
* ║    utils.Trap.log("TAG", "msg"); // as before                             ║
* ║    utils.Trap.ex("TAG", function() { ...dark-zone callback... });         ║
* ║    →  [17][2026-08-24 12:34:56][TAG] message                              ║
* ║                                                                           ║
* ║  The files are created in the working directory of the process            ║
* ║  (bin/windows/bin/ when launched via lime run). Search "crash_trap.log"   ║
* ║  in the project if unsure.                                                ║
* ║                                                                           ║
* ║  CONTACT FILTER:                                                          ║
* ║  nameMatches() gates per-contact traps (set_value probe) so the log       ║
* ║  is not flooded at 60 Hz. The default list targets the ComPort            ║
* ║  grouping test; EDIT IT for the next scenario.                            ║
* ║                                                                           ║
* ║  v1.3 CHANGES (Stable Port Naming v3.0, 2026-08-25):                      ║
* ║  - NAMES extended with Inlet/Outlet/Arrival/Departure 1-4 so              ║
* ║    wall-port hops stay visible after the naming migration.                ║
* ║  - New tags in the wild: MIG (blueprint migrated), MIG-HEAL               ║
* ║    (parent reference healed to a stable port name).                       ║
* ║                                                                           ║
* ║  v1.2 CHANGES (Deafness hunt part 2, 2026-08-25):                         ║
* ║  - nameMatches(): SUFFIX match added — chain port names ending with       ║
* ║    "_<token>" now pass the filter (gateway hops became visible).          ║
* ║                                                                           ║
* ║  v1.1 CHANGES (Naming & Integrity retest, 2026-08-24):                    ║
* ║  - NAMES extended with the first-hop leaf contacts ("out", "in",          ║
* ║    "set", "rst"). Field evidence from Test 2: a button press dying        ║
* ║    at the FIRST hop (Button.out → assembly port) was INVISIBLE in         ║
* ║    the trap log because those names were not in the filter.               ║
* ║  - New tags in the wild: BTN (ButtonWidget press/release timeline),       ║
* ║    PORT-HEAL (EditorContext parent-wire auto-heal).                       ║
* ║                                                                           ║
* ║  cpp-only: sys.io.File. On HTML5 Trap.log compiles to a no-op.            ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class Trap
{
        /** Master switch — set false to silence everything. */
        public static var ENABLE:Bool = true;

        /**
        * Contact names that pass the set_value probe filter.
        * Edit per test scenario. Defaults = ComPort grouping test:
        * assembly gateway ports (Com_Port_*), driver's own contacts,
        * and the generic incoming_N/outgoing_N gateway contacts.
        *
        * v1.1: + "out", "in", "set", "rst" — first-hop leaf visibility
        * (Button.out, LED.in, Toggle.set/rst). Remove them if the log
        * gets too noisy for a high-frequency scenario.
        */
        public static var NAMES:Array<String> = [
                "Com_Port_open", "Com_Port_close", "Com_Port_send",
                "Com_Port_txData", "Com_Port_isOpen", "Com_Port_rxData",
                "open", "close", "send", "txData", "isOpen", "rxData",
                "incoming_1", "incoming_2", "incoming_3", "incoming_4",
                "outgoing_1", "outgoing_2", "outgoing_3", "outgoing_4",
                "Inlet_1", "Inlet_2", "Inlet_3", "Inlet_4",
                "Outlet_1", "Outlet_2", "Outlet_3", "Outlet_4",
                "Arrival_1", "Arrival_2", "Arrival_3", "Arrival_4",
                "Departure_1", "Departure_2", "Departure_3", "Departure_4",
                "out", "in", "set", "rst"
        ];

#if cpp
        private static var _out:sys.io.FileOutput = null;
        private static var _booted:Bool = false;
#end
        private static var _seq:Int = 0;

        /**
        * v1.4 (Episod H-1): install the black box. Call ONCE, as the very
        * first statement of Main.new().
        *
        *  1. stderr (fd 2) is redirected into stderr_capture.log (append).
        *     hxcpp prints "Uncaught exception : <msg> + stack" to stderr;
        *     the "lime run" pipe only captures stdout, so without this the
        *     most important line of a crash run evaporates.
        *  2. Windows: a native SEH sentinel is installed. ANY unhandled
        *     native exception (segfault c0000005, abort, C++ exception
        *     escaping the runtime) appends one raw line to crash_trap.log
        *     before the process dies.
        *
        * Never throws — trapping must not change program behavior.
        */
        public static function boot():Void
        {
#if cpp
                if (_booted) return;
                _booted = true;
                try
                {
                        untyped __cpp__('
                                #ifdef _WIN32
                                {
                                        int _trap_fd = _open("stderr_capture.log",
                                                _O_CREAT | _O_WRONLY | _O_APPEND,
                                                _S_IREAD | _S_IWRITE);
                                        if (_trap_fd >= 0)
                                        {
                                                _dup2(_trap_fd, 2);
                                                if (_trap_fd != 2) _close(_trap_fd);
                                        }
                                        SetUnhandledExceptionFilter(_altauri_trap_seh_filter);
                                }
                                #else
                                {
                                        int _trap_fd = open("stderr_capture.log",
                                                O_CREAT | O_WRONLY | O_APPEND, 0644);
                                        if (_trap_fd >= 0)
                                        {
                                                dup2(_trap_fd, 2);
                                                if (_trap_fd != 2) close(_trap_fd);
                                        }
                                }
                                #endif
                        ');
                        log("TRAP", "v1.4.1 boot: stderr -> stderr_capture.log, native SEH sentinel armed (Windows)");
                }
                catch (e:Dynamic)
                {
                        // Swallow — traps must never break the app.
                }
#end
        }

        /**
        * v1.4 (Episod H-1): guarded call for the DARK ZONE — openfl
        * display-list event handlers and haxe.Timer callbacks have no
        * try/catch anywhere on their path; an exception thrown there
        * kills the process with exit code 1 and (before v1.4) no trace.
        *
        * Trap.ex runs fn() and, if it throws, logs the exception WITH its
        * Haxe stack and SWALLOWS it — the app keeps running and the report
        * lands in crash_trap.log. Returns true if fn completed normally.
        */
        public static function ex(tag:String, fn:Void -> Void):Bool
        {
#if cpp
                if (!ENABLE) { fn(); return true; }
                try
                {
                        fn();
                        return true;
                }
                catch (e:Dynamic)
                {
                        var msg:String;
                        try
                        {
                                msg = Std.string(e) + "\n"
                                        + haxe.CallStack.toString(haxe.CallStack.exceptionStack());
                        }
                        catch (e2:Dynamic)
                        {
                                msg = Std.string(e) + " (stack unavailable)";
                        }
                        log("EX", tag + " THREW: " + msg);
                        return false;
                }
#else
                fn();
                return true;
#end
        }

        /**
        * Append one line to crash_trap.log and FLUSH immediately.
        * Never throws — trapping must not change program behavior.
        */
        public static function log(tag:String, msg:String = ""):Void
        {
                        // Блокиратор ловушки лога
                        return;
#if cpp
                if (!ENABLE) return;
                try
                {
                        if (_out == null)
                        {
                                _out = sys.io.File.append("crash_trap.log", true);
                        }
                        _seq++;
                        _out.writeString('[' + _seq + '][' + Date.now().toString() + '][' + tag + '] ' + msg + '\n');
                        _out.flush();
                }
                catch (e:Dynamic)
                {
                        // Swallow — traps must never break the app.
                }
#end
        }

        /**
        * Contact-name filter for the set_value probe (see TRAP_PLAN_v1.md).
        */
        public static function nameMatches(n:String):Bool
        {
                if (!ENABLE || n == null) return false;
                for (t in NAMES)
                {
                        if (t == n) return true;
// v1.2: SUFFIX match. Gateway port external names are CHAINS that end
// with the leaf semantic ("Custom_Assembly_Custom_Assembly_2_Toggle_Switch_2_rst").
// Without the suffix match every gateway hop between the parent wire
// and the wall contact was INVISIBLE to the probes — the deafness hunt
// (2026-08-25) could not see where the signal died. Now a name passes
// if it ends with "_<token>" for any token in NAMES.
                        if (t.length > 0 && n.length > t.length + 1
                                && StringTools.endsWith(n, "_" + t)) return true;
                }
                return false;
        }

        /** Close the handle (optional; OS closes it on exit anyway). */
        public static function close():Void
        {
#if cpp
                if (_out != null)
                {
                        try { _out.close(); } catch (e:Dynamic) {}
                        _out = null;
                }
#end
        }
}