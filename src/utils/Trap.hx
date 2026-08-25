package utils;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                        TRAP v1.3                                          ║
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
* ║  Data that was flushed before the crash survives it.                       ║
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
* ║  v1.3 CHANGES (Stable Port Naming v3.0, 2026-08-25):
* ║  - NAMES extended with Inlet/Outlet/Arrival/Departure 1-4 so
* ║    wall-port hops stay visible after the naming migration.
* ║  - New tags in the wild: MIG (blueprint migrated), MIG-HEAL
* ║    (parent reference healed to a stable port name).
* ║                                                                           ║
* ║  v1.2 CHANGES (Deafness hunt part 2, 2026-08-25):                         ║
* ║  - nameMatches(): SUFFIX match added — chain port names ending with       ║
* ║    "_<token>" now pass the filter (gateway hops became visible).         ║
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
#end
        private static var _seq:Int = 0;

        /**
        * Append one line to crash_trap.log and FLUSH immediately.
        * Never throws — trapping must not change program behavior.
        */
        public static function log(tag:String, msg:String = ""):Void
        {
			// Блокиратор ловушки лога
			//return;
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
