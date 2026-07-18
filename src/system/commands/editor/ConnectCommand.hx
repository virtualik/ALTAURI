package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * CONNECT COMMAND v1.1 (Live External Name Refresh)
 * Command to connect two contacts.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.1 CHANGES (Live External Name Refresh)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  PROBLEM:
 *  When the user connected an atom to an Assembly port that was created via
 *  addPort() (e.g., "incoming_1"), the port's externalName stayed "incoming_1"
 *  forever — even after exit. The user only saw meaningful names like
 *  "Button_out" if they happened to exit and re-enter the assembly, and only
 *  after Assembly.refreshExternalPortNames() was called in EditorContext.pop().
 *
 *  SOLUTION:
 *  After creating a connection that involves a SELF endpoint, immediately call
 *  _assembly.refreshExternalPortNames(). This updates the port's externalName
 *  to "{atomDisplayName}_{contactName}" right away, so the parent schema
 *  shows a meaningful label without waiting for exit.
 *
 *  refreshExternalPortNames() is idempotent — calling it on every ConnectCommand
 *  is safe; ports whose name is already correct are skipped.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ConnectCommand                                                        │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Resolve contacts by atomId and contactName                   │   │
 * │   │  - Check if connection already exists                           │   │
 * │   │  - Add ConnectionDef to blueprint.internalConnections           │   │
 * │   │  - Create physical link between contacts                        │   │
 * │   │  - v1.1: If SELF involved, call refreshExternalPortNames()      │   │
 * │   │  - Emit REDRAW_WIRES event                                      │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  - Remove ConnectionDef from blueprint                          │   │
 * │   │  - Unlink physical connection                                   │   │
 * │   │  - v1.1: If SELF was involved, call refreshExternalPortNames()  │   │
 * │   │  - Emit REDRAW_WIRES event                                      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Contact Resolution:                                                   │
 * │   - SELF → assembly.ports[name].internal                                │
 * │   - atomId → assembly.internalAtoms[id].getInput/getOutput              │
 * │   - Template ID → Runtime ID conversion via idMap                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ConnectCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _fromId:String;
    private var _fromContact:String;
    private var _toId:String;
    private var _toContact:String;
    private var _createdLink:core.data.Blueprint.ConnectionDef;

    public function new(blueprint:Blueprint, assembly:Assembly, fromId:String, fromContact:String, toId:String, toContact:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _fromId = fromId;
        _fromContact = fromContact;
        _toId = toId;
        _toContact = toContact;
    }

    override private function executeInternal():Void {
        var cOut = resolveContact(_fromId, _fromContact, OUTPUT);
        var cIn = resolveContact(_toId, _toContact, INPUT);

        if (cOut == null || cIn == null) {
            trace('ConnectCommand: Aborted. Contacts not found. ${_fromId}:${_fromContact} -> ${_toId}:${_toContact}');
            complete();
            return;
        }

        _createdLink = {
            from: { atomId: _fromId, contactName: _fromContact },
            to: { atomId: _toId, contactName: _toContact }
        };

        var exists = false;
        for (c in _blueprint.internalConnections) {
            if (c.from.atomId == _fromId && c.from.contactName == _fromContact &&
                c.to.atomId == _toId && c.to.contactName == _toContact) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            _blueprint.internalConnections.push(_createdLink);
            cOut.link(cIn);
            
            // === FIX: Синхронизация рантайма, если затронут порт сборки ===
            if (_fromId == "SELF" || _toId == "SELF") {
                _assembly.rebuildInternalConnections();

                // === v1.1: Live external name refresh ===
                // If this connection involves a SELF port, the port's externalName
                // may now have a meaningful value based on the connected atom.
                // Update it immediately so the parent schema shows a proper label
                // (e.g., "Button_out" instead of "incoming_1").
                _assembly.refreshExternalPortNames();
            }
        }
        Impulsys.quickEmit(EventType.REDRAW_WIRES);
        complete();
    }

    override public function undo():Void {
        if (_createdLink != null) {
            _blueprint.internalConnections.remove(_createdLink);
            var cOut = resolveContact(_fromId, _fromContact, OUTPUT);
            var cIn = resolveContact(_toId, _toContact, INPUT);
            if (cOut != null && cIn != null) {
                cOut.unlink(cIn);
            } else {
                trace('ConnectCommand Undo: Contacts missing, skipping unlink.');
            }

            // === v1.1: After undo, the SELF port may no longer have a connected
            // atom. refreshExternalPortNames() will leave its externalName
            // untouched (the user may have set a custom name previously). ===
            if (_fromId == "SELF" || _toId == "SELF") {
                _assembly.refreshExternalPortNames();
            }
            Impulsys.quickEmit(EventType.REDRAW_WIRES);
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            var obj = _assembly.internalAtoms.get(atomId);
            // FIX: If not found directly, try via ID map
            if (obj == null) {
                var realAtomId = _assembly.idMap.get(atomId);
                if (realAtomId != null) {
                    obj = _assembly.internalAtoms.get(realAtomId);
                }
            }
            if (obj == null) return null;
            var atom:Atom = cast obj;
            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Connect $_fromId -> $_toId';
}