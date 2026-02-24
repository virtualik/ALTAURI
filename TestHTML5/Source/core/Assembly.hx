package core;

import core.Blueprint.ConnectionPoint;

/**
 * ASSEMBLY v2.3
 * Implements IDisposable.
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
            var contact = new Contact(pinDef.defaultValue, pinDef.type, pinDef.name);
            if (pinDef.type == ContactType.INPUT) inputs.set(pinDef.name, contact);
            else outputs.set(pinDef.name, contact);
        }
    }

    private function _createInternalInstances():Void {
        if (blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms) {
            var instance = AssemblyFactory.createAtom(atomDef.typeId);
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

    /**
     * Cleanup: Destroys all internal atoms and pins.
     */
    public function dispose():Void {
        // Dispose internal atoms
        for (key in internalAtoms.keys()) {
            var atom:IDisposable = cast internalAtoms.get(key);
            if (atom != null) atom.dispose();
        }
        internalAtoms.clear();

        // Dispose external pins
        for (pin in inputs) pin.dispose();
        for (pin in outputs) pin.dispose();
        
        inputs.clear();
        outputs.clear();
    }
}