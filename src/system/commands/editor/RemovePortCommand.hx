package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;

/**
 * REMOVE PORT COMMAND
 * Removes a gateway port and its connections.
 * Supports Undo/Redo.
 */
class RemovePortCommand extends Command {

    private var _assembly:Assembly;
    private var _portName:String;
    
    // Snapshot for Undo
    private var _portType:ContactType;
    private var _defaultValue:Dynamic;
    private var _connectedWires:Array<Dynamic>; // Stores connection data
    private var _portIndex:Int; // To restore visual order

    public function new(assembly:Assembly, portName:String) {
        super();
        _assembly = assembly;
        _portName = portName;
    }

    override private function executeInternal():Void {
        var port = _assembly.ports.get(_portName);
        if (port == null) {
            trace("RemovePortCommand: Port not found " + _portName);
            complete();
            return;
        }

        // 1. Snapshot Data
        _portType = port.type;
        _defaultValue = port.external.value;
        
        // Snapshot Index (position in blueprint.pins) to restore order on Undo
        _portIndex = -1;
        for (i in 0..._assembly.blueprint.pins.length) {
            if (_assembly.blueprint.pins[i].name == _portName) {
                _portIndex = i;
                break;
            }
        }

        // Snapshot Connections
        _connectedWires = [];
        var bp = _assembly.blueprint;
        for (conn in bp.internalConnections) {
            if (conn.from.atomId == "SELF" && conn.from.contactName == _portName) {
                _connectedWires.push({ from: conn.from, to: conn.to });
            }
            if (conn.to.atomId == "SELF" && conn.to.contactName == _portName) {
                _connectedWires.push({ from: conn.from, to: conn.to });
            }
        }

        // 2. Remove Wires from Blueprint
        for (wireData in _connectedWires) {
            bp.internalConnections.remove(wireData);
        }

        // 3. Remove Port
        _assembly.removePort(_portName);

        Impulsys.quickEmit("ASSEMBLY_PORTS_CHANGED", { assemblyId: _assembly.id });
        complete();
    }

    override public function undo():Void {
        // 1. Restore Port
        var port = _assembly.addPort(_name, _portType, _defaultValue);
        
        // Restore position (addPort appends to end, so we need to move it back if index matters)
        // Since `addPort` adds to `blueprint.pins` array, we can reorder it.
        var bp = _assembly.blueprint;
        if (bp.pins.length > 0) {
             // The newly added pin is at the end
             var addedPin = bp.pins.pop();
             
             // Insert back at saved index, or end if index invalid
             if (_portIndex != -1 && _portIndex < bp.pins.length) {
                 bp.pins.insert(_portIndex, addedPin);
             } else {
                 bp.pins.push(addedPin);
             }
        }

        // 2. Restore Wires
        for (wireData in _connectedWires) {
            bp.internalConnections.push(wireData);
            // Physical links will be re-established by NodeEditor on rebuild
        }

        Impulsys.quickEmit("ASSEMBLY_PORTS_CHANGED", { assemblyId: _assembly.id });
    }
    
    // Helper getter to resolve _portName in undo if needed (though field is public)
    private var _name(get, never):String;
    private function get__name():String return _portName;

    override public function getDescription():String return 'Remove Port $_portName';
}