package core.base;

import core.data.Blueprint;
import core.data.Blueprint.ConnectionPoint;
import core.base.Contact;
import core.base.Atom;
import core.base.IDisposable;
import core.types.ContactType;

/**
 * ASSEMBLY v3.2 (Memory Leak Fixed)
 * Composite structure containing Atoms and internal connections.
 * Extends Atom for full compatibility.
 *
 * CHANGES v3.2:
 * - Fixed: Memory leak in dispose() - now properly clears all references
 * - Fixed: ConductorPort disposal now unlinks contacts before clearing
 * - Added: Deep disposal of internal atoms with null checks
 */
class Assembly extends Atom {

    public var blueprint(default, null):Blueprint;
    public var ports(default, null):Map<String, ConductorPort>;
    public var internalAtoms(default, null):Map<String, Dynamic>;

    // Public getters for external access (DevicePanel, NodeEditor, etc.)
    public var inputs(get, null):Map<String, Contact>;
    public var outputs(get, null):Map<String, Contact>;

    private function get_inputs():Map<String, Contact> {
        var map = new Map<String, Contact>();
        for (p in ports) if (p.type == INPUT) map.set(p.name, p.external);
        return map;
    }

    private function get_outputs():Map<String, Contact> {
        var map = new Map<String, Contact>();
        for (p in ports) if (p.type == OUTPUT) map.set(p.name, p.external);
        return map;
    }

    public function new(id:String, blueprint:Blueprint) {
        this.blueprint = blueprint;
        this.ports = new Map();
        this.internalAtoms = new Map();

        // Create interface ports first
        _createInterface();

        // Build inputs/outputs arrays from ports for Atom constructor
        var inputsArr:Array<Contact> = [];
        var outputsArr:Array<Contact> = [];

        for (p in ports) {
            if (p.type == INPUT) {
                inputsArr.push(p.external);
            } else {
                outputsArr.push(p.external);
            }
        }

        // Call Atom constructor
        // type = blueprint.id, isActive = false
        var typeName = blueprint != null ? blueprint.id : "Assembly";
        super(inputsArr, outputsArr, null, id, typeName, false);

        // Now create internal structure
        _createInternalInstances();
        _createInternalConnections();
    }

    private function _createInterface():Void {
        if (blueprint == null || blueprint.pins == null) return;

        for (pinDef in blueprint.pins) {
            var port = new ConductorPort(pinDef.name, pinDef.type, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
    }

    private function _createInternalInstances():Void {
        if (blueprint == null || blueprint.internalAtoms == null) return;

        for (atomDef in blueprint.internalAtoms) {
            var instance = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
            if (instance != null) {
                internalAtoms.set(atomDef.instanceId, instance);
            }
        }
    }

    private function _createInternalConnections():Void {
        if (blueprint == null || blueprint.internalConnections == null) return;

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
            var port = ports.get(point.contactName);
            if (port == null) return null;
            return port.internal;
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
     * Override dispose to clean up internal atoms properly.
     * FIX v3.2: Complete cleanup of all references.
     */
    override public function dispose():Void {
        // 1. Dispose all internal atoms FIRST
        // Collect keys to avoid concurrent modification
        var keys = [for (k in internalAtoms.keys()) k];
        
        for (key in keys) {
            var obj = internalAtoms.get(key);
            if (obj != null) {
                if (Std.isOfType(obj, IDisposable)) {
                    try {
                        cast(obj, IDisposable).dispose();
                    } catch (e:Dynamic) {
                        trace('Assembly.dispose: Error disposing atom $key: $e');
                    }
                }
            }
        }
        internalAtoms.clear();
        internalAtoms = null;

        // 2. Dispose all ports (this clears external and internal contacts)
        var portKeys = [for (k in ports.keys()) k];
        for (key in portKeys) {
            var port = ports.get(key);
            if (port != null) {
                port.dispose();
            }
        }
        ports.clear();
        ports = null;

        // 3. Clear blueprint reference (optional - keep if needed elsewhere)
        // blueprint = null;  // Commented out - Blueprint might be shared

        // 4. Call parent dispose (clears inputs/outputs)
        super.dispose();
        
        #if debug
        trace('Assembly "$id" disposed');
        #end
    }
}
