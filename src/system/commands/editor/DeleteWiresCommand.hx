package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;

/**
 * DELETE WIRES COMMAND v1.1
 * Fixed: ID resolution for loaded assemblies.
 */
class DeleteWiresCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _wireIds:Array<String>;

    private var _deletedConnections:Array<ConnectionDef>;

    public function new(blueprint:Blueprint, assembly:Assembly, wireIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _wireIds = wireIds.copy();
        _deletedConnections = [];
    }

    override private function executeInternal():Void {
        _deletedConnections = [];

        for (id in _wireIds) {
            var conn = findLinkById(id);
            if (conn != null) {
                _deletedConnections.push(conn);
                _blueprint.internalConnections.remove(conn);

                // Исправленная логика разрешения контактов
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);

                if (cOut != null && cIn != null) {
                    cOut.unlink(cIn);
                }
            }
        }

        Impulsys.quickEmit("REDRAW_WIRES");
        complete();
    }

    override public function undo():Void {
        for (conn in _deletedConnections) {
            _blueprint.internalConnections.push(conn);

            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);

            if (cOut != null && cIn != null) {
                cOut.link(cIn);
            }
        }

        Impulsys.quickEmit("REDRAW_WIRES");
    }

    private function findLinkById(id:String):ConnectionDef {
        if (_blueprint.internalConnections == null) return null;
        for (conn in _blueprint.internalConnections) {
            var connId = '${conn.from.atomId}_${conn.from.contactName}->${conn.to.atomId}_${conn.to.contactName}';
            if (connId == id) return conn;
        }
        return null;
    }

    // ИСПРАВЛЕННЫЙ МЕТОД
    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            // ИСПРАВЛЕНИЕ: Сначала пытаемся найти Runtime ID через карту шаблонов
            var realAtomId = _assembly.idMap.get(atomId);
            
            // Если в карте нет, значит это уже Runtime ID (новосозданный атом)
            if (realAtomId == null) {
                realAtomId = atomId;
            }

            var obj = _assembly.internalAtoms.get(realAtomId);
            if (obj == null) return null;
            
            var atom:Atom = cast obj;
            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete ${_wireIds.length} Wires';
}