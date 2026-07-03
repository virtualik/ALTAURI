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
import library.drivers.MiniAudioAtom;
import library.drivers.SignalGenerator;
import library.drivers.ComPortAtom;
import library.drivers.ComEnumeratorAtom;
using StringTools;

/**
 * ASSEMBLY FACTORY
 * 
 * Central factory that creates every Atom in the system.
 * It decides whether to instantiate a native C++ driver (SignalGenerator, MiniAudioAtom, etc.)
 * or a composite Assembly (user-created blueprints).
 * 
 * This is the single place where you add new native atoms.
 * 
 * Responsibilities:
 * - Normalize type IDs (handle different spellings/cases)
 * - Instantiate native drivers (C++ specific)
 * - Instantiate electro/UI atoms
 * - Create composite Assemblies from Blueprints
 * - Restore initial state after creation
 */
class AssemblyFactory
{
    /**
     * Creates an Atom or Assembly instance.
     * If forcedId is null, a new UUID is generated automatically.
     * 
     * @param typeId       Blueprint ID from AtomRegistry (e.g., "Mini Audio Capture")
     * @param forcedId     Optional runtime ID (used during deserialization)
     * @param initialState Optional saved state to restore
     * @return Atom instance or null if blueprint not found
     */
    public static function createAtom(typeId:String, ?forcedId:String, ?initialState:Dynamic):Atom
    {
        var bp = AtomRegistry.get(typeId);
        var id:String = (forcedId != null) ? forcedId : UID.generate();
        
        if (bp == null)
        {
            trace('ERROR: Blueprint not found: ${typeId}');
            return null;
        }
        
        // =====================================================================
        // NORMALIZATION: Make type names robust against different spellings
        // =====================================================================
        var normalizedTypeId:String = typeId;
        if (typeId != null)
        {
            var upperId:String = typeId.toUpperCase().replace(" ", "");
            switch (upperId)
            {
                // === ACTIVE DRIVERS (C++ native atoms) ===
                case "SIGNALGENERATOR": normalizedTypeId = "SignalGenerator";
                
                // ─────────────────────────────────────────────────────────────
                // SYSTEM VU METER — Windows WASAPI audio meter
                // ─────────────────────────────────────────────────────────────
                case "SYSTEMVUMETERATOM":
                case "SYSTEMVUMETER":
                case "SYSTEM VU METER":
                case "VUMETER": normalizedTypeId = "SystemVUMeterAtom";
                
                // ─────────────────────────────────────────────────────────────
                // MINI AUDIO ATOM — real microphone capture driver
                // ─────────────────────────────────────────────────────────────
                case "MINIAUDIOATOM":
                case "MINI AUDIO CAPTURE":
                case "MINIAUDIOPLAYER":        // in case you add playback later
                    normalizedTypeId = "MiniAudioAtom";
                
                // ─────────────────────────────────────────────────────────────
                // COM PORT ATOM — Serial port exchange
                // ─────────────────────────────────────────────────────────────
                case "COMPORTATOM":
                case "COM PORT":
                case "COMPORT":
                    normalizedTypeId = "ComPortAtom";
                case "COMENUMERATORATOM":
                case "COM ENUMERATOR":
                case "COMENUMERATOR":
                    normalizedTypeId = "ComEnumeratorAtom";
                
                // ─────────────────────────────────────────────────────────────
                // === ELECTRO / UI ATOMS ===
                // ─────────────────────────────────────────────────────────────
                case "BUTTON":
                case "PUSHBUTTON": normalizedTypeId = "Button";
                case "TOGGLE":
                case "TOGGLESWITCH": normalizedTypeId = "Toggle";
                case "LED":
                case "LEDINDICATOR": normalizedTypeId = "LED";
                case "RELAY": normalizedTypeId = "Relay";
                case "OSCILLOSCOPE": normalizedTypeId = "Oscilloscope";
                case "TEXTINPUT": normalizedTypeId = "TextInput";
                
                default:
                    // Keep original name if no special mapping is needed
                    normalizedTypeId = typeId;
            }
        }
        
        var atom:Atom = null;
        
        // =====================================================================
        // INSTANTIATION SWITCH — this is where real objects are born
        // =====================================================================
        switch (normalizedTypeId)
        {
            // =============================================================
            // ACTIVE DRIVERS (real C++ code, registered in DriverManager)
            // =============================================================
            case "SignalGenerator":
                #if cpp
                atom = new library.drivers.SignalGenerator(id);
                #end
            
            // =============================================================
            // MINI AUDIO ATOM — your microphone capture engine
            // =============================================================
            case "MiniAudioAtom":
                #if cpp
                atom = new library.drivers.MiniAudioAtom(id);
                trace('🔊 AssemblyFactory: Created MiniAudioAtom...');
                #else
                trace('⚠️ MiniAudioAtom requires C++ target');
                #end
            
            case "ComPortAtom":
                #if cpp
                atom = new library.drivers.ComPortAtom(id);
                trace('📡 AssemblyFactory: Created ComPortAtom...');
                #end
            
            case "ComEnumeratorAtom":
                #if cpp
                atom = new library.drivers.ComEnumeratorAtom(id);
                trace('🔍 AssemblyFactory: Created ComEnumeratorAtom...');
                #end
            
            // =============================================================
            // SYSTEM VU METER — Windows WASAPI audio meter
            // =============================================================
            case "SystemVUMeterAtom":
                #if cpp
                atom = new library.drivers.SystemVUMeterAtom(id);
                trace('🔊 AssemblyFactory: Created SystemVUMeterAtom...');
                #else
                trace('⚠️ SystemVUMeterAtom requires C++ target');
                #end
            
            // =============================================================
            // ELECTRO / UI ATOMS
            // =============================================================
            case "Button":
                atom = new ButtonAtom(id);
            case "Toggle":
                atom = new library.electro.ToggleAtom(id);
            case "LED":
                atom = new LedAtom(id);
            case "Relay":
                atom = new RelayAtom(id);
            case "Oscilloscope":
                atom = new OscilloscopeAtom(id);
            case "TextInput":
                atom = new TextInputAtom(id);
            
            // =============================================================
            // DEFAULT: Composite user-created Assembly
            // =============================================================
            default:
                // This path is used for all user-made blueprints that contain internalAtoms
                atom = new Assembly(id, bp);
        }
        
        // Restore saved state (frequency, mode, buffer settings, etc.)
        if (atom != null && initialState != null)
        {
            atom.restoreState(initialState);
        }
        
        return atom;
    }
    
    /**
     * Convenience method — always returns an Assembly (never a native atom).
     * Used when you explicitly want a composite node.
     */
    public static function createAssembly(typeId:String):Assembly
    {
        var atom = createAtom(typeId);
        if (Std.isOfType(atom, Assembly))
        {
            return cast atom;
        }
        else
        {
            trace('WARN: ${typeId} is a native Atom, not an Assembly.');
            return null;
        }
    }
    
    /**
     * Returns true if the given typeId is a user-created composite blueprint
     * (contains internalAtoms and connections).
     */
    public static function isComposite(typeId:String):Bool
    {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return false;
        return (bp.internalAtoms != null && bp.internalAtoms.length > 0);
    }
}