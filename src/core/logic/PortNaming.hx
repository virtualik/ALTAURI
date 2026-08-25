package core.logic;

import core.data.Blueprint;
import core.types.ContactType;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                        PORT NAMING v1.0                                    ║
* ║        Stable Wall-Port Naming: Inlet / Arrival / Departure / Outlet       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Central authority for the v3.0 stable naming scheme of Assembly          ║
* ║  wall ports. Names are POSITIONAL and IMMUTABLE — they never drift        ║
* ║  when wires connect, atoms rename, or assemblies nest.                    ║
* ║                                                                           ║
* ║  THE FOUR FAMILIES:                                                       ║
* ║                                                                           ║
* ║    Inlet_N       external INPUT port (visible on the parent schema)       ║
* ║    Arrival_N     internal wall contact paired with Inlet_N (same N)       ║
* ║    Outlet_N      external OUTPUT port (visible on the parent schema)      ║
* ║    Departure_N   internal wall contact paired with Outlet_N (same N)      ║
* ║                                                                           ║
* ║    ┌───────── PARENT ─────────┐       ┌──────── INSIDE ──────────────┐    ║
* ║    │   [Assembly node]        │       │  (wall)                      │    ║
* ║    │   Inlet_3   ●──────┐     │  wall │    ┌────● Arrival_3          │    ║
* ║    │                    │─────┼───────┼────┘   (feeds Button.set)    │    ║
* ║    │   Outlet_1  ●◄─────┼─────┼───────┼────┐   Departure_1 ●         │    ║
* ║    │                    │     │       │    └───► (fed by Toggle.out) │    ║
* ║    └──────────────────────────┘       └──────────────────────────────┘    ║
* ║                                                                           ║
* ║  WHY: semantic port names ("Button_out") mutated on every connect         ║
* ║  cycle and drove a whole family of wire-death bugs (suffix-chain          ║
* ║  matching, PORT-HEAL storms, frozen-name weirdness). Positional           ║
* ║  stable names kill that entire class at the root. The semantic            ║
* ║  meaning ("what does this port serve?") moved to the hover TOOLTIP        ║
* ║  (Assembly.getPortBeneficiary).                                           ║
* ║                                                                           ║
* ║  MIGRATION: migrateBlueprintInPlace() converts legacy blueprints          ║
* ║  (incoming_/outgoing_ internals + semantic externals) to the stable       ║
* ║  scheme. Idempotent. Stable pins are NEVER renumbered. Legacy names       ║
* ║  are kept as session aliases so parent blueprints that still              ║
* ║  reference them resolve — and heal themselves in place — until the        ║
* ║  next save writes clean names.                                            ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class PortNaming
{
        // ====================================================================
        // PREFIXES
        // ====================================================================

        public static inline var INLET_PREFIX:String = "Inlet_";
        public static inline var OUTLET_PREFIX:String = "Outlet_";
        public static inline var ARRIVAL_PREFIX:String = "Arrival_";
        public static inline var DEPARTURE_PREFIX:String = "Departure_";

        // ====================================================================
        // SESSION ALIAS CACHE
        // ====================================================================

        /**
        * blueprint.id -> (legacy name -> new INTERNAL port name).
        *
        * Populated once per blueprint at first migration. Lets every
        * instance constructed later in the session resolve parents that
        * still reference pre-migration names (multi-instance safety:
        * after the first instance mutates the shared blueprint, later
        * instances would otherwise see no legacy data at all).
        */
        private static var _legacyAliases:Map<String, Map<String, String>> = new Map<String, Map<String, String>>();

        // ====================================================================
        // NAME BUILDERS / MATCHERS
        // ====================================================================

        /** Stable EXTERNAL name for a port type + number ("Inlet_3"/"Outlet_1"). */
        public static function stableExternalName(type:ContactType, n:Int):String
        {
                return (type == OUTPUT) ? (OUTLET_PREFIX + n) : (INLET_PREFIX + n);
        }

        /** Stable INTERNAL name for a port type + number ("Arrival_3"/"Departure_1"). */
        public static function stableInternalName(type:ContactType, n:Int):String
        {
                return (type == OUTPUT) ? (DEPARTURE_PREFIX + n) : (ARRIVAL_PREFIX + n);
        }

        /** True for stable external names ("Inlet_N" / "Outlet_N"). */
        public static function isStableExternalName(name:String):Bool
        {
                if (name == null) return false;
                return StringTools.startsWith(name, INLET_PREFIX) || StringTools.startsWith(name, OUTLET_PREFIX);
        }

        /** True for stable internal names ("Arrival_N" / "Departure_N"). */
        public static function isStableInternalName(name:String):Bool
        {
                if (name == null) return false;
                return StringTools.startsWith(name, ARRIVAL_PREFIX) || StringTools.startsWith(name, DEPARTURE_PREFIX);
        }

        /** Parse the trailing number after a prefix; -1 if not numeric/absent. */
        private static function trailingNumber(name:String, prefix:String):Int
        {
                if (name == null || !StringTools.startsWith(name, prefix)) return -1;
                var tail = name.substring(prefix.length);
                if (tail.length == 0) return -1;
                for (i in 0...tail.length)
                {
                        var c = tail.charCodeAt(i);
                        if (c < 48 || c > 57) return -1;
                }
                return Std.parseInt(tail);
        }

        // ====================================================================
        // MIGRATION
        // ====================================================================

        /**
        * Convert a blueprint's wall ports to the stable naming scheme,
        * IN PLACE. Idempotent — a second call is a no-op.
        *
        * RULES:
        *   - Pins that are ALREADY stable (internal + external match the
        *     scheme) are never touched — stability is forever, even when
        *     number gaps exist (e.g. after removePort).
        *   - Legacy pins (incoming_/outgoing_ internals, semantic
        *     externals like "Button_out", or anything non-stable) are
        *     renumbered to the lowest FREE number of their type in
        *     blueprint.pins order.
        *   - SELF references inside blueprint.internalConnections are
        *     rewritten to the new internal names.
        *   - Old internal AND external names are recorded as session
        *     aliases (see getLegacyAliases).
        *
        * @return true if the blueprint was modified by THIS call.
        */
        public static function migrateBlueprintInPlace(bp:Blueprint):Bool
        {
                if (bp == null || bp.pins == null || bp.pins.length == 0) return false;

                // 1. Fast exit: any legacy pin at all?
                var hasLegacy:Bool = false;
                for (pin in bp.pins)
                {
                        if (pin == null || pin.name == null) continue;
                        var ext = pin.externalName;
                        if (!isStableInternalName(pin.name) || ext == null || !isStableExternalName(ext))
                        {
                                hasLegacy = true;
                                break;
                        }
                }
                if (!hasLegacy) return false;

                // 2. Numbers already occupied by stable pins (never renumbered)
                var usedInput:Array<Int> = [];
                var usedOutput:Array<Int> = [];
                for (pin in bp.pins)
                {
                        if (pin == null || pin.name == null) continue;
                        if (isStableInternalName(pin.name) && pin.externalName != null && isStableExternalName(pin.externalName))
                        {
                                var n:Int = (pin.type == OUTPUT)
                                        ? trailingNumber(pin.name, DEPARTURE_PREFIX)
                                        : trailingNumber(pin.name, ARRIVAL_PREFIX);
                                if (n > 0)
                                {
                                        if (pin.type == OUTPUT) usedOutput.push(n); else usedInput.push(n);
                                }
                        }
                }

                // 3. Renumber legacy pins to the lowest free number of their type
                var renames:Map<String, String> = new Map<String, String>(); // old internal -> new internal
                var aliases:Map<String, String> = new Map<String, String>(); // any old name -> new internal
                for (pin in bp.pins)
                {
                        if (pin == null || pin.name == null) continue;

                        var alreadyStable:Bool = isStableInternalName(pin.name)
                                && pin.externalName != null && isStableExternalName(pin.externalName);
                        if (alreadyStable) continue;

                        var oldInternal:String = pin.name;
                        var oldExternal:String = (pin.externalName != null && pin.externalName != "") ? pin.externalName : pin.name;

                        var used:Array<Int> = (pin.type == OUTPUT) ? usedOutput : usedInput;
                        var n:Int = 1;
                        while (used.indexOf(n) != -1) n++;
                        used.push(n);

                        var newInternal:String = stableInternalName(pin.type, n);
                        var newExternal:String = stableExternalName(pin.type, n);

                        pin.name = newInternal;
                        pin.externalName = newExternal;

                        if (oldInternal != newInternal)
                        {
                                renames.set(oldInternal, newInternal);
                                aliases.set(oldInternal, newInternal);
                        }
                        if (oldExternal != newExternal && oldExternal != newInternal)
                        {
                                aliases.set(oldExternal, newInternal);
                        }
                }

                // 4. Rewrite SELF references in internal connections
                if (bp.internalConnections != null)
                {
                        for (conn in bp.internalConnections)
                        {
                                if (conn == null) continue;
                                if (conn.from != null && conn.from.atomId == "SELF")
                                {
                                        var nn:String = renames.get(conn.from.contactName);
                                        if (nn != null) conn.from.contactName = nn;
                                }
                                if (conn.to != null && conn.to.atomId == "SELF")
                                {
                                        var nn:String = renames.get(conn.to.contactName);
                                        if (nn != null) conn.to.contactName = nn;
                                }
                        }
                }

                // 5. Session alias cache (multi-instance safety)
                if (bp.id != null && Lambda.count(aliases) > 0)
                {
                        _legacyAliases.set(bp.id, aliases);
                }
                return true;
        }

        /**
        * Legacy aliases for a blueprint: (old name -> new INTERNAL name).
        * Returns null when the blueprint never needed migration.
        */
        public static function getLegacyAliases(blueprintId:String):Map<String, String>
        {
                if (blueprintId == null) return null;
                return _legacyAliases.get(blueprintId);
        }
}
