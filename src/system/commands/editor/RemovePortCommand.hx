package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;

/**
 * REMOVE PORT COMMAND v1.3
 * Removes a gateway port and its connections.
 * Supports Undo/Redo.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   RemovePortCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  1. Snapshot port data (type, default value, index)             │   │
 * │   │  2. Snapshot connected wires (original references)              │   │
 * │   │  3. Remove wires from blueprint                                 │   │
 * │   │  4. Remove port from assembly                                   │   │
 * │   │  5. Emit ASSEMBLY_PORTS_CHANGED event                           │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  1. Restore port (addPort with saved type/default)              │   │
 * │   │  2. Restore port position in blueprint.pins array               │   │
 * │   │  3. Restore connected wires (original references)               │   │
 * │   │  4. Emit ASSEMBLY_PORTS_CHANGED event                           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   v1.3 Fix (Episod G-3):                                               │
 * │   - Parent-side external wires (stored in the PARENT's blueprint      │
 * │     as <templateId>.<externalName>) are removed too: Main.onPort-      │
 * │     Removed cleans them during removePort() and hands the defs back    │
 * │     via adoptParentWires(), so undo() restores them. Previously they   │
 * │     survived deletion as permanent "hanging wires" (only the sprite    │
 * │     was hidden by WireRenderer ghost-detection — the defs stayed and   │
 * │     were saved to disk).                                              │
 * │                                                                         │
 * │   v1.2 Fix:                                                             │
 * │   - Fixed reference comparison bug. Now stores the original             │
 * │     ConnectionDef reference instead of creating a copy, ensuring        │
 * │     successful removal from the blueprint array.                        │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class RemovePortCommand extends Command {
    private var _assembly:Assembly;
    private var _portName:String;
    
    // Snapshot for Undo
    private var _portType:ContactType;
    private var _defaultValue:Dynamic;
    
    // FIX: Store array of original references to connections
    private var _connectedWires:Array<ConnectionDef>;
    private var _portIndex:Int; // To restore visual order

    // v1.3 (Episod G-3): parent-side wires removed together with the port.
    // Adopted from Main.onPortRemoved DURING execute()/redo() (the command
    // itself cannot reach the parent assembly — EditorContext lives in
    // Main), restored in undo().
    private var _parentBlueprint:Blueprint;
    private var _parentWires:Array<ConnectionDef>;
    
    public function new(assembly:Assembly, portName:String) {
        super();
        _assembly = assembly;
        _portName = portName;
    }
    
    /**
     * v1.3 (Episod G-3): called by Main.onPortRemoved DURING execute()/redo().
     *
     * Main removes the parent-side wire defs (they reference the port as
     * <templateId>.<externalName> — see onPortRemoved) and hands them here
     * so undo() can put them back. Replaces any previous snapshot: redo
     * re-runs removePort, which re-removes the wires restored by undo.
     */
    public function adoptParentWires(parentBp:Blueprint, wires:Array<ConnectionDef>):Void {
        _parentBlueprint = parentBp;
        _parentWires = wires.copy();
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
        
        // 2. Snapshot Connections
        _connectedWires = [];
        var bp = _assembly.blueprint;
        
        // FIX: Collect original references to conn objects
        for (conn in bp.internalConnections) {
            if (conn.from.atomId == "SELF" && conn.from.contactName == _portName) {
                _connectedWires.push(conn);
            }
            if (conn.to.atomId == "SELF" && conn.to.contactName == _portName) {
                _connectedWires.push(conn);
            }
        }
        
        // 3. Remove Wires from Blueprint
        // Now remove will work because we pass the original object
        for (conn in _connectedWires) {
            bp.internalConnections.remove(conn);
        }
        
        // 4. Remove Port
        _assembly.removePort(_portName);
        
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
        
        complete();
    }
    
    override public function undo():Void {
        // 1. Restore Port
        var port = _assembly.addPort(_portName, _portType, _defaultValue);
        
        // Restore position
        var bp = _assembly.blueprint;
        if (bp.pins.length > 0 && port != null) {
            var addedPin = bp.pins.pop();
            if (_portIndex != -1 && _portIndex < bp.pins.length) {
                bp.pins.insert(_portIndex, addedPin);
            } else {
                bp.pins.push(addedPin);
            }
        }
        
        // 2. Restore Wires
        // Return original connection objects to the array
        for (conn in _connectedWires) {
            bp.internalConnections.push(conn);
        }

        // 3. Restore parent-side external wires (v1.3, Episod G-3).
        //    addPort() above already emitted ASSEMBLY_PORTS_CHANGED, which
        //    makes the (possibly backgrounded) parent editor rebuild —
        //    so the restored wires reappear without any extra event.
        if (_parentWires != null && _parentWires.length > 0
                && _parentBlueprint != null && _parentBlueprint.internalConnections != null) {
            for (conn in _parentWires) {
                _parentBlueprint.internalConnections.push(conn);
            }
        }

        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
    }
    
    override public function getDescription():String return 'Remove Port $_portName';
}
