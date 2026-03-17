package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType; // <--- IMPORT
import core.data.Blueprint.ConnectionDef;

/**
 * REMOVE PORT COMMAND v1.2
 * Removes a gateway port and its connections.
 * Supports Undo/Redo.
 *
 * v1.2 Fix: Fixed reference comparison bug. Now stores the original ConnectionDef reference
 * instead of creating a copy, ensuring successful removal from the blueprint array.
 */
class RemovePortCommand extends Command {

    private var _assembly:Assembly;
    private var _portName:String;

    // Snapshot for Undo
    private var _portType:ContactType;
    private var _defaultValue:Dynamic;

    // ИСПРАВЛЕНИЕ: Храним массив оригинальных ссылок на связи
    private var _connectedWires:Array<ConnectionDef>;

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

        // 2. Snapshot Connections
        _connectedWires = [];
        var bp = _assembly.blueprint;

        // ИСПРАВЛЕНИЕ: Собираем оригинальные ссылки на объекты conn
        for (conn in bp.internalConnections) {
            if (conn.from.atomId == "SELF" && conn.from.contactName == _portName) {
                _connectedWires.push(conn);
            }
            if (conn.to.atomId == "SELF" && conn.to.contactName == _portName) {
                _connectedWires.push(conn);
            }
        }

        // 3. Remove Wires from Blueprint
        // Теперь remove сработает, так как мы передаем оригинальный объект
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
        // Возвращаем оригинальные объекты связей в массив
        for (conn in _connectedWires) {
            bp.internalConnections.push(conn);
        }

        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
    }

    override public function getDescription():String return 'Remove Port $_portName';
}