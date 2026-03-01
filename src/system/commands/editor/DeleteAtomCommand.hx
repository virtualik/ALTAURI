package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.types.ContactType;
import core.logic.Impulsys;
import library.AtomRegistry;

/**
 * Command to delete an atom and its connections.
 */
class DeleteAtomCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String;

    // Snapshot for restoration
    private var _atomDef:core.data.Blueprint.AtomDef;
    private var _atomType:String;
    private var _connections:Array<core.data.Blueprint.ConnectionDef>;
    private var _posX:Float;
    private var _posY:Float;

    public function new(blueprint:Blueprint, assembly:Assembly, atomId:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _atomId = atomId;
    }

    override private function executeInternal():Void {
        // 1. Save data BEFORE deletion
        saveSnapshot();

        // 2. Remove connections from model and physically
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.remove(conn);

                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.unlink(cIn);
            }
        }

        // 3. Remove Atom from model
        if (_atomDef != null) {
            _blueprint.internalAtoms.remove(_atomDef);
        }
        _assembly.internalAtoms.remove(_atomId);

        Impulsys.quickEmit("ATOM_DELETED", {id: _atomId});
        complete();
    }

    override public function undo():Void {
        // 1. Restore Atom in Blueprint
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // 2. Recreate Atom instance
        var bp = AtomRegistry.get(_atomType);
        if (bp == null) return;

        var inputs = [];
        var outputs = [];
        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }
        var atom = new Atom(inputs, outputs, bp.logic, _atomId, _atomType);
        _assembly.internalAtoms.set(_atomId, atom);

        // 3. Restore connections
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);

                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.link(cIn);
            }
        }

        Impulsys.quickEmit("ATOM_RESTORED", {id: _atomId, x: _posX, y: _posY, atom: atom});
    }

    private function saveSnapshot():Void {
        if (_atomDef != null) return; 

        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == _atomId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);

        if (atomInst != null) {
            _atomType = atomInst.type;
            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        _connections = [];
        for (conn in _blueprint.internalConnections) {
            if (conn.from.atomId == _atomId || conn.to.atomId == _atomId) {
                _connections.push(conn);
            }
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            // ИСПРАВЛЕНИЕ: Берем внутренний контакт порта
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port != null) return port.internal;
            
            return null;
        } else {
            var atom = _assembly.internalAtoms.get(atomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}