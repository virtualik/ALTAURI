package core;

/**
 * ASSEMBLY FACTORY v2.0
 * Centralized factory for creating Atoms and Assemblies from Blueprints.
 */
class AssemblyFactory {

    private static var _uidCounter:Int = 0;

    /**
     * Creates an Atom instance from a registered Blueprint ID.
     */
    public static function createAtom(typeId:String):Atom {
        var bp = AtomDefinitions.get(typeId);
        if (bp == null) {
            trace("Error: Atom Blueprint not found: " + typeId);
            return null;
        }

        // FIX: If logic is null, it's a composite, don't try to create simple Atom
        if (bp.logic == null && bp.internalAtoms.length > 0) {
             trace("Error: Blueprint " + typeId + " is composite, use createAssembly.");
             return null;
        }

        var inputs = [];
        var outputs = [];

        // FIX: Changed bp.pinDefs to bp.pins
        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }

        var atom = new Atom(inputs, outputs, bp.logic, null, typeId);
        return atom;
    }

    /**
     * Creates an Assembly (Composite) from a Blueprint.
     */
    public static function createAssembly(typeId:String):Assembly {
        var bp = AtomDefinitions.get(typeId);
        if (bp == null) {
            trace("Error: Assembly Blueprint not found: " + typeId);
            return null;
        }

        var id = "asm_" + (_uidCounter++) + "_" + typeId;
        var asm = new Assembly(id, bp);
        
        return asm;
    }
}