package core.base;

import core.data.Blueprint;
import core.data.Blueprint.ConnectionPoint;
import core.base.Contact;
import core.base.Atom;
import core.base.IDisposable;
import core.types.ContactType;

/**
 * ASSEMBLY v2.5
 * Composite structure containing Atoms and internal connections.
 */
class Assembly implements IDisposable {
    public var id(default, null):String;
    public var blueprint(default, null):Blueprint;

    public var inputs(default, null):Map<String, Contact>;
    public var outputs(default, null):Map<String, Contact>;
    public var internalAtoms(default, null):Map<String, Dynamic>;

    public function new(id:String, blueprint:Blueprint) {
        this.id = id;
        this.blueprint = blueprint;

        this.inputs = new Map();
        this.outputs = new Map();
        this.internalAtoms = new Map();

        _createInterface();
        _createInternalInstances();
        _createInternalConnections();
    }

    private function _createInterface():Void {
        if (blueprint == null) return;
        for (pinDef in blueprint.pins) {
            var type:ContactType = ContactType.UNDEFINED;

            if (Std.isOfType(pinDef.type, String)) {
                switch(cast(pinDef.type, String)) {
                    case "INPUT": type = INPUT;
                    case "OUTPUT": type = OUTPUT;
                    case "BIDIRECTIONAL": type = BIDIRECTIONAL;
                    default: type = UNDEFINED;
                }
            } else if (Std.isOfType(pinDef.type, ContactType)) {
                type = cast(pinDef.type, ContactType);
            }

            var contact = new Contact(pinDef.defaultValue, type, pinDef.name);

            if (type == INPUT) inputs.set(pinDef.name, contact);
            else if (type == OUTPUT) outputs.set(pinDef.name, contact);
        }
    }

    private function _createInternalInstances():Void {
        if (blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms) {
            // FIX: Passing instanceId as the second argument
            var instance = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
            if (instance != null) {
                internalAtoms.set(atomDef.instanceId, instance);
            }
        }
    }

    private function _createInternalConnections():Void {
        if (blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections) {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);

            if (fromContact != null && toContact != null) {
                fromContact.link(toContact);
            } else {
                trace('WARN: Assembly resolve failed for link: ${conn.from.atomId} -> ${conn.to.atomId}');
            }
        }
    }

    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var pin = inputs.get(point.contactName);
            if (pin == null) pin = outputs.get(point.contactName);
            return pin;
        } else {
            var obj = internalAtoms.get(point.atomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            for (c in atom.getInputs()) if (c.name == point.contactName) return c;
            for (c in atom.getOutputs()) if (c.name == point.contactName) return c;
        }
        return null;
    }

    public function dispose():Void {
        for (key in internalAtoms.keys()) {
            var obj = internalAtoms.get(key);
            if (Std.isOfType(obj, IDisposable)) {
                cast(obj, IDisposable).dispose();
            }
        }
        internalAtoms.clear();

        for (pin in inputs) pin.dispose();
        for (pin in outputs) pin.dispose();

        inputs.clear();
        outputs.clear();
    }
}