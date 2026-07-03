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
import core.logic.EventType;

/**
 * DELETE WIRES COMMAND v1.1
 * Deletes multiple wires (connections) from the assembly.
 * Supports Undo/Redo with connection restoration.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeleteWiresCommand                                                    │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  1. For each wire ID:                                           │   │
 * │   │     - Find ConnectionDef by ID                                  │   │
 * │   │     - Save to _deletedConnections array                         │   │
 * │   │     - Remove from blueprint.internalConnections                 │   │
 * │   │     - Unlink physical contacts                                  │   │
 * │   │  2. Emit REDRAW_WIRES event                                     │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  1. For each deleted connection:                                │   │
 * │   │     - Restore to blueprint.internalConnections                  │   │
 * │   │     - Re-link physical contacts                                 │   │
 * │   │  2. Emit REDRAW_WIRES event                                     │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Wire ID Format:                                                       │
 * │   ────────────────                                                      │
 * │   "{fromAtomId}_{fromContact}->{toAtomId}_{toContact}"                  │
 * │                                                                         │
 * │   Example: "id_abc123_out->id_def456_in"                                │
 * │                                                                         │
 * │   v1.1 Changes:                                                         │
 * │   - Fixed ID resolution for loaded assemblies                           │
 * │   - Uses assembly.idMap to convert Template ID → Runtime ID             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
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

                // Resolve and unlink contacts
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) {
                    cOut.unlink(cIn);
                }
            }
        }

        Impulsys.quickEmit(EventType.REDRAW_WIRES);
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

        Impulsys.quickEmit(EventType.REDRAW_WIRES);
    }

    /**
     * Find a connection definition by its wire ID.
     * Wire ID format: "{fromAtomId}_{fromContact}->{toAtomId}_{toContact}"
     */
    private function findLinkById(id:String):ConnectionDef {
        if (_blueprint.internalConnections == null) return null;

        for (conn in _blueprint.internalConnections) {
            var connId = '${conn.from.atomId}_${conn.from.contactName}->${conn.to.atomId}_${conn.to.contactName}';
            if (connId == id) return conn;
        }
        return null;
    }

    /**
     * Resolve a contact by atom ID and contact name.
     * Handles SELF (assembly ports) and regular atoms.
     *
     * v1.1 Fix: Uses assembly.idMap to convert Template ID → Runtime ID
     * for loaded assemblies where atomId in blueprint is Template ID.
     */
    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            // Try to find Runtime ID via template map
            var realAtomId = _assembly.idMap.get(atomId);

            // If not in map, assume it's already Runtime ID (newly created atom)
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