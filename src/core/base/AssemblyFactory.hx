package core.base;

import library.AtomRegistry;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import library.logic.NandAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;
import core.data.Blueprint;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;

/**
 * ASSEMBLY FACTORY v2.1
 * Centralized factory for creating Atoms and Assemblies from Blueprints.
 */
class AssemblyFactory {

    private static var _uidCounter:Int = 0;

    /**
     * Creates an Atom instance from a registered Blueprint ID.
     *
     * @param typeId The ID of the Blueprint definition.
     * @param forcedId Optional. If provided, this ID will be used instead of generating a new one.
     *                 Crucial for loading saved schemes to maintain link references.
     */
    public static function createAtom(typeId:String, ?forcedId:String):Atom {
        var bp = AtomRegistry.get(typeId); // Updated reference
        if (bp == null) return null;

        // --- ID Logic: Use forced or generate new ---
        var id:String = (forcedId != null) ? forcedId : "atom_" + (_uidCounter++);

        // 1. Special classes (Active Atoms)
        if (typeId == "FPSMonitorAtom") {
            return new FPSMonitorAtom(id);
        }

        if (typeId == "FrameTimeAtom") {
            return new FrameTimeAtom(id);
        }

        // If logic is null, it is a composite, don't try to create simple Atom
        if (bp.logic == null && bp.internalAtoms.length > 0) {
             trace("Error: Blueprint " + typeId + " is composite, use createAssembly.");
             return null;
        }

        var inputs = [];
        var outputs = [];

        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }

        // Passing generated or forced ID
        var atom = new Atom(inputs, outputs, bp.logic, id, typeId);
        return atom;
    }

    /**
     * Creates an Assembly (Composite) from a Blueprint.
     */
    public static function createAssembly(typeId:String):Assembly {
        var bp = AtomRegistry.get(typeId); // Updated reference
        if (bp == null) {
            trace("Error: Assembly Blueprint not found: " + typeId);
            return null;
        }

        var id = "asm_" + (_uidCounter++) + "_" + typeId;
        var asm = new Assembly(id, bp);

        return asm;
    }
}