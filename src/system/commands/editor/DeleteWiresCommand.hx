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
 * DELETE WIRES COMMAND
 * Supports Undo/Redo for wire deletion.
 */
class DeleteWiresCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _wireIds:Array<String>;

    // Snapshot for undo
    private var _deletedConnections:Array<ConnectionDef>;

    public function new(blueprint:Blueprint, assembly:Assembly, wireIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _wireIds = wireIds.copy(); // Копируем массив, чтобы ссылка не изменилась извне
        _deletedConnections = [];
    }

    override private function executeInternal():Void {
        // Очищаем снапшот на случай повторного выполнения (Redo)
        _deletedConnections = [];

        for (id in _wireIds) {
            var conn = findLinkById(id);
            if (conn != null) {
                // 1. Сохраняем в снапшот
                _deletedConnections.push(conn);

                // 2. Удаляем из модели (Blueprint)
                _blueprint.internalConnections.remove(conn);

                // 3. Разрываем физическую связь
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
            // 1. Возвращаем в модель
            _blueprint.internalConnections.push(conn);

            // 2. Восстанавливаем физическую связь
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

    // Вспомогательный метод для поиска контактов (аналогичный ConnectCommand)
    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            var obj = _assembly.internalAtoms.get(atomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete ${_wireIds.length} Wires';
}