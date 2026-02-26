package editor.commands;

import core.Command;
import core.Blueprint;
import core.Assembly;
import core.Atom;
import core.Contact;
import core.ContactType;
import core.Impulsys;

class ConnectCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;

    private var _fromId:String;
    private var _fromContact:String;
    private var _toId:String;
    private var _toContact:String;

    private var _createdLink:core.Blueprint.ConnectionDef;

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
        }

        Impulsys.quickEmit("REDRAW_WIRES");
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

            Impulsys.quickEmit("REDRAW_WIRES");
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var map = (type == INPUT) ? _assembly.inputs : _assembly.outputs;
            return map.get(contactName);
        } else {
            var obj = _assembly.internalAtoms.get(atomId);
            if (obj == null) return null;

            var atom:Atom = cast obj;
            if (atom.getInputs() == null) return null; // Защита от удаленных

            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Connect $_fromId -> $_toId';
}