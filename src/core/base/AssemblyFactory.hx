package core.base;

import core.base.Assembly;
import core.base.Atom;
import core.data.Blueprint;
import utils.UID;
import library.AtomRegistry;
import library.electro.TextInputAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;
import library.electro.OscilloscopeAtom;
import library.drivers.UniversalGeneratorAtom;
import library.drivers.AudioInputAtom;

using StringTools;

/**
 * ASSEMBLY FACTORY v4.6 (Clean Logic Gate Fix)
 * Создает правильные экземпляры классов для нативных атомов.
 *
 * v4.6 Changes:
 * - Added missing imports for FPSMonitorAtom and FrameTimeAtom.
 * - Removed redirection logic for deleted native Logic Gates (ORGateAtom, etc).
 * - Logic Gate types now default to creating an Assembly (composite).
 */
class AssemblyFactory
{
    /**
     * Creates an Atom or Assembly instance.
     * If forcedId is null, generates a new UUID.
     */
    public static function createAtom(typeId:String, ?forcedId:String, ?initialState:Dynamic):Atom
    {
        var bp = AtomRegistry.get(typeId);
        var id:String = (forcedId != null) ? forcedId : UID.generate();
        
        if (bp == null)
        {
            trace('ERROR: Blueprint not found: $typeId');
            return null;
        }
        
        // trace('AssemblyFactory: Creating ${bp.name} (typeId: $typeId, id: $id)');

        // === FIX: Нормализация typeId для совместимости ===
        var normalizedTypeId:String = typeId;
        if (typeId != null)
        {
            var upperId:String = typeId.toUpperCase().replace(" ", "");
            
            switch (upperId)
            {
                // === NATIVE ATOMS REDIRECTS ===
                case "BUTTON": normalizedTypeId = "Button";
                case "PUSHBUTTON": normalizedTypeId = "Button";
                
                case "TOGGLE": normalizedTypeId = "Toggle";
                case "TOGGLESWITCH": normalizedTypeId = "Toggle";
                
                case "LED": normalizedTypeId = "LED";
                case "LEDINDICATOR": normalizedTypeId = "LED";
                
                case "RELAY": normalizedTypeId = "Relay";
                case "OSCILLOSCOPE": normalizedTypeId = "Oscilloscope";
                case "TEXTINPUT": normalizedTypeId = "TextInput";
                
                case "UNIVERSALGEN": normalizedTypeId = "UniversalGen";
                case "UNIVERSALGENERATOR": normalizedTypeId = "UniversalGen";
             
                case "AUDIOIN": normalizedTypeId = "AudioIn";
                case "AUDIOINPUT": normalizedTypeId = "AudioIn";

                // === REMOVED LOGIC GATES REDIRECTS ===
                // ORGateAtom class has been removed.
                // Types like OR_GATE, NAND will fall to 'default' and become Assembly.
                
                default: 
                    // Keep original if no match
                    normalizedTypeId = typeId;
            }
        }

        var atom:Atom = null;

        // === INSTANTIATION ===
        switch (normalizedTypeId)
        {
            // Active Drivers
            case "UniversalGen": atom = new UniversalGeneratorAtom(id);
            case "AudioIn": atom = new AudioInputAtom(id);

            // Electro
            case "Button": atom = new ButtonAtom(id);
            case "Toggle": atom = new library.electro.ToggleAtom(id);
            case "LED": atom = new LedAtom(id);
            case "Relay": atom = new RelayAtom(id);
            case "Oscilloscope": atom = new OscilloscopeAtom(id);
            case "TextInput": atom = new TextInputAtom(id);

            // Default: create Assembly for composite or missing native types
            default:
                atom = new Assembly(id, bp);
                // trace('AssemblyFactory: Created Assembly for type $normalizedTypeId');
        }

        // Restore state if provided
        if (atom != null && initialState != null)
        {
            atom.restoreState(initialState);
        }
        
        return atom;
    }

    public static function createAssembly(typeId:String):Assembly
    {
        var atom = createAtom(typeId);
        if (Std.isOfType(atom, Assembly))
        {
            return cast atom;
        }
        else
        {
            trace('WARN: $typeId is a native Atom, not an Assembly.');
            return null;
        }
    }

    /**
     * Check if a type is a composite (user-created assembly).
     */
    public static function isComposite(typeId:String):Bool
    {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return false;
        
        // Native atoms with logic are not composites
        if (bp.internalAtoms != null && bp.internalAtoms.length > 0) return true;
        return false;
    }
}