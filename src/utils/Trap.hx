package utils;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                        TRAP v1.0                                          ║
* ║          (Crash-Proof Trace Logger — BUG-A Hunt)                          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PURPOSE:                                                                 ║
* ║  stdout on Windows is BUFFERED when the app runs through "lime run"       ║
* ║  (pipe). On a hard crash (c0000005) the buffered tail is LOST —           ║
* ║  exactly the most valuable part (the last moments before death).          ║
* ║  Field evidence: the exit-crash log ended with NO pop() traces at         ║
* ║  all, neither "Saved camera state" nor "Closed serial device", so         ║
* ║  the death location is currently invisible.                               ║
* ║                                                                           ║
* ║  TRAP writes every line to crash_trap.log with IMMEDIATE FLUSH.           ║
* ║  Data that was flushed before the crash survives it.                      ║
* ║                                                                           ║
* ║  USAGE:                                                                   ║
* ║    utils.Trap.log("TAG", "message");                                      ║
* ║    →  [17][2026-08-24 12:34:56][TAG] message                              ║
* ║                                                                           ║
* ║  The file is created in the working directory of the process              ║
* ║  (bin/windows/bin/ when launched via lime run). Search "crash_trap.log"   ║
* ║  in the project if unsure.                                                ║
* ║                                                                           ║
* ║  CONTACT FILTER:                                                          ║
* ║  nameMatches() gates per-contact traps (set_value probe) so the log       ║
* ║  is not flooded at 60 Hz. The default list targets the ComPort            ║
* ║  grouping test; EDIT IT for the next scenario.                            ║
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
        */
        public static var NAMES:Array<String> = [
                "Com_Port_open", "Com_Port_close", "Com_Port_send",
                "Com_Port_txData", "Com_Port_isOpen", "Com_Port_rxData",
                "open", "close", "send", "txData", "isOpen", "rxData",
                "incoming_1", "incoming_2", "incoming_3", "incoming_4",
                "outgoing_1", "outgoing_2", "outgoing_3", "outgoing_4"
        ];

#if cpp
        private static var _out:sys.io.FileOutput = null;
#end
        private static var _seq:Int = 0;

        /**
        * Append one line to crash_trap.log and FLUSH immediately.
        * Never throws — trapping must not change program behavior.
        */
        public static function log(tag:String, msg:String = ""):Void
        {
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
