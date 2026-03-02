package core.base;

import library.AtomRegistry;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import core.data.Blueprint;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;

/**
 * ASSEMBLY FACTORY v2.3
 * Centralized factory for creating Atoms and Assemblies from Blueprints.
 * 
 * CHANGES v2.3:
 * - Fixed: Assembly now extends Atom, so cast works correctly
 * - Simplified createAtom logic
 */
class AssemblyFactory {

    private static var _uidCounter:Int = 0;

    /**
     * Creates an Atom or Assembly instance from a registered Blueprint ID.
     * 
     * Automatically creates Assembly for composite Blueprints.
     * Since Assembly extends Atom, the return type is always Atom.
     *
     * @param typeId The ID of the Blueprint definition.
     * @param forcedId Optional ID to use instead of generating a new one.
     */
    public static function createAtom(typeId:String, ?forcedId:String):Atom {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) {
            trace('ERROR: Blueprint not found: $typeId');
            return null;
        }

        // --- ID Logic ---
        var id:String = (forcedId != null) ? forcedId : "atom_" + (_uidCounter++);

        // --- Special classes (Active Atoms with custom implementation) ---
        if (typeId == "FPSMonitorAtom") {
            return new FPSMonitorAtom(id);
        }

        if (typeId == "FrameTimeAtom") {
            return new FrameTimeAtom(id);
        }

        // --- Check if composite (Assembly) ---
        // Composite = no logic AND has internal atoms
        var isComposite = (bp.logic == null && bp.internalAtoms != null && bp.internalAtoms.length > 0);

        if (isComposite) {
            // Create Assembly - it extends Atom now!
            return new Assembly(id, bp);
        }

        // --- Create standard Atom ---
        var inputs:Array<Contact> = [];
        var outputs:Array<Contact> = [];

        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }

        return new Atom(inputs, outputs, bp.logic, id, typeId);
    }

    /**
     * Creates an Assembly (Composite) from a Blueprint.
     */
    public static function createAssembly(typeId:String):Assembly {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) {
            trace("Error: Assembly Blueprint not found: " + typeId);
            return null;
        }

        var id = "asm_" + (_uidCounter++) + "_" + typeId;
        return new Assembly(id, bp);
    }

    /**
     * Checks if a Blueprint is composite.
     */
    public static function isComposite(typeId:String):Bool {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return false;
        return (bp.logic == null && bp.internalAtoms != null && bp.internalAtoms.length > 0);
    }
}