package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     ADD PORT COMMAND v2.1                                 ║
 * ║            (Stable Naming: Inlet/Arrival & Outlet/Departure)           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Adds a new gateway port to an Assembly with semantic naming.             ║
 * ║                                                                           ║
 * ║  v2.1 Changes:                                                            ║
 * ║  - STABLE NAMING: internal "Arrival_N"/"Departure_N" paired            ║
 * ║    with external "Inlet_N"/"Outlet_N" (same N through the wall)        ║
 * ║  - Names never drift; semantic info lives in hover tooltips            ║
 * ║                                                                           ║
 * ║  v2.0 Changes:                                                            ║
 * ║  - INPUT ports:  internal = "incoming_N", external = "incoming_N"         ║
 * ║  - OUTPUT ports: internal = "outgoing_N", external = "outgoing_N"         ║
 * ║  - N is auto-incremented based on existing port count                     ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  Adding INPUT port:                                                 │  ║
 * ║  │  Existing: incoming_1, incoming_2                                   │  ║
 * ║  │  New:      incoming_3                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  Adding OUTPUT port:                                                │  ║
 * ║  │  Existing: outgoing_1                                               │  ║
 * ║  │  New:      outgoing_2                                              │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class AddPortCommand extends Command {
    private var _assembly:Assembly;
    private var _type:ContactType;
    private var _name:String;
    private var _defaultValue:Dynamic;

    public function new(assembly:Assembly, type:ContactType, ?name:String, ?defaultValue:Dynamic) {
        super();
        _assembly = assembly;
        _type = type;
        _name = name;
        _defaultValue = defaultValue;
    }

    override private function executeInternal():Void {
        // v2.0: Generate semantic name if not provided
        // v2.1: STABLE NAMING — manual ports use the same scheme as
        // grouped assemblies: internal "Arrival_N"/"Departure_N" pairs
        // with external "Inlet_N"/"Outlet_N" (same N through the wall).
        var pairedExternalName:String = null;
        if (_name == null) {
            var internalPrefix = (_type == OUTPUT) ? "Departure_" : "Arrival_";
            var externalPrefix = (_type == OUTPUT) ? "Outlet_" : "Inlet_";
            var count = 0;
            
            // Count existing ports of this type
            for (p in _assembly.ports) {
                if (p != null && p.type == _type) count++;
            }
            var n = count + 1;
            
            // Ensure uniqueness of the INTERNAL name (ports map + pins).
            // Gaps left by removed ports are respected — stability
            // of existing names wins over compact numbering.
            while (_assembly.ports.exists(internalPrefix + n) || isPinInBlueprint(internalPrefix + n)) {
                n++;
            }
            
            _name = internalPrefix + n;
            pairedExternalName = externalPrefix + n;
        }

        // v2.1: paired external name (falls back to _name when the
        // caller supplied an explicit port name)
        var port = _assembly.addPort(_name, _type, _defaultValue, pairedExternalName);
        if (port != null) {
            Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
        } else {
            trace("AddPortCommand failed: could not create port (limit reached?).");
        }
        complete();
    }

    private function isPinInBlueprint(name:String):Bool {
        var bp = _assembly.blueprint;
        if (bp == null || bp.pins == null) return false;
        for (pin in bp.pins) {
            if (pin.name == name) return true;
        }
        return false;
    }

    override public function undo():Void {
        if (_name != null) {
            removeConnectedWires(_name);
            _assembly.removePort(_name);
            Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
        }
    }

    private function removeConnectedWires(portName:String):Void {
        var bp = _assembly.blueprint;
        var toRemove = [];
        for (conn in bp.internalConnections) {
            if (conn.from.atomId == "SELF" && conn.from.contactName == portName) toRemove.push(conn);
            if (conn.to.atomId == "SELF" && conn.to.contactName == portName) toRemove.push(conn);
        }
        for (conn in toRemove) {
            bp.internalConnections.remove(conn);
        }
    }

    override public function getDescription():String return 'Add Port $_name';
}