package core.base;

import library.AtomRegistry;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;

/**
 * ASSEMBLY FACTORY v3.0 (Unified)
 * Теперь создает Assembly для всех типов, кроме специальных Active-драйверов.
 */
class AssemblyFactory {

    private static var _uidCounter:Int = 0;

    /**
     * Creates an Atom or Assembly instance.
     */
    public static function createAtom(typeId:String, ?forcedId:String):Atom {
        var bp = AtomRegistry.get(typeId);
        var id:String = (forcedId != null) ? forcedId : "atom_" + (_uidCounter++);

        // 1. Special Active Classes (Drivers)
        // Они остаются классами, так как требуют update(dt) и специальных флагов isActive.
        if (typeId == "FPSMonitorAtom") return new FPSMonitorAtom(id);
        if (typeId == "FrameTimeAtom") return new FrameTimeAtom(id);

        // 2. Standard Unified Assembly
        // Если Blueprint найден, создаем Assembly (она сама разберется, это Native logic или Custom container).
        if (bp != null) {
            return new Assembly(id, bp);
        }

        // 3. Fallback (should not happen if Registry is correct)
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
        // Composite = Custom Assembly (no logic, has internals)
        return (bp.logic == null && bp.internalAtoms != null && bp.internalAtoms.length > 0);
    }
}