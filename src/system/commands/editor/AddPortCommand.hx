package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.types.ContactType;
import core.logic.Impulsys;

/**
 * ADD PORT COMMAND
 * Adds a new gateway port to an Assembly.
 * Supports Undo/Redo.
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
        // Generate name if not provided
        if (_name == null) {
            var prefix = (_type == INPUT) ? "In_" : "Out_";
            var count = 0;
            // Count existing ports of this type
            for (p in _assembly.ports) {
                if (p.type == _type) count++;
            }
            var candidate = prefix + Std.string(count + 1);
            
            // Ensure uniqueness (in case of deletions)
            while (_assembly.ports.exists(candidate)) {
                count++;
                candidate = prefix + Std.string(count + 1);
            }
            _name = candidate;
        }

        var port = _assembly.addPort(_name, _type, _defaultValue);

        if (port != null) {
            Impulsys.quickEmit("ASSEMBLY_PORTS_CHANGED", { assemblyId: _assembly.id });
        } else {
            trace("AddPortCommand failed: could not create port (limit reached?).");
        }
        
        complete();
    }

    override public function undo():Void {
        if (_name != null) {
            // Before removing port, we should remove connected wires to keep Blueprint clean
            removeConnectedWires(_name);
            
            _assembly.removePort(_name);
            Impulsys.quickEmit("ASSEMBLY_PORTS_CHANGED", { assemblyId: _assembly.id });
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