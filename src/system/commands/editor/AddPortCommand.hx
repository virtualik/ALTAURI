package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     ADD PORT COMMAND v2.0                                 ║
 * ║                (Semantic Naming: incoming_N / outgoing_N)                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Adds a new gateway port to an Assembly with semantic naming.             ║
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
        if (_name == null) {
            var prefix = (_type == INPUT) ? "incoming_" : "outgoing_";
            var count = 0;
            
            // Count existing ports of this type
            for (p in _assembly.ports) {
                if (p.type == _type) count++;
            }
            
            var candidate = prefix + Std.string(count + 1);
            
            // Ensure uniqueness in both ports map and blueprint pins
            while (_assembly.ports.exists(candidate) || isPinInBlueprint(candidate)) {
                count++;
                candidate = prefix + Std.string(count + 1);
            }
            
            _name = candidate;
        }

        // v2.0: For manually added ports, external = internal name
        var port = _assembly.addPort(_name, _type, _defaultValue);
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