package core.base;

import library.AtomRegistry;
import core.data.Blueprint;
import utils.UID;

/**
 * ASSEMBLY FACTORY v4.0 (UUID Support)
 * Uses UID for unique identification.
 */
class AssemblyFactory {

    /**
     * Creates an Atom or Assembly instance.
     * If forcedId is null, generates a new UUID.
     */
    public static function createAtom(typeId:String, ?forcedId:String):Atom {
        var bp = AtomRegistry.get(typeId);
        var id:String = (forcedId != null) ? forcedId : UID.generate();

        // Standard Unified Assembly
        if (bp != null) {
            return new Assembly(id, bp);
        }

        trace('ERROR: Blueprint not found: $typeId');
        return null;
    }

    public static function createAssembly(typeId:String):Assembly {
        var atom = createAtom(typeId);
        return cast atom;
    }

    public static function isComposite(typeId:String):Bool {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return false;
        return (bp.logic == null && bp.internalAtoms != null && bp.internalAtoms.length > 0);
    }
}
