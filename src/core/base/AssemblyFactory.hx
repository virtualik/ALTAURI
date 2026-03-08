package core.base;

import library.AtomRegistry;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;
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
        // Генерируем ID только если не передан (для Undo/Redo/Copy)
        var id:String = (forcedId != null) ? forcedId : UID.generate();

        // 1. Special Active Classes (Drivers)
        if (typeId == "FPSMonitorAtom") return new FPSMonitorAtom(id);
        if (typeId == "FrameTimeAtom") return new FrameTimeAtom(id);

        // 2. Standard Unified Assembly
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