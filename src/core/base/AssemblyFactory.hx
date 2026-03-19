package core.base;
import library.AtomRegistry;
import library.electro.TextInputAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;
import library.electro.OscilloscopeAtom;
import library.drivers.UniversalGeneratorAtom;
import library.drivers.SignalGeneratorAtom;
import library.drivers.FPSMonitorAtom;
import library.drivers.FrameTimeAtom;
import library.drivers.AudioInputAtom;
import library.logic.NandAtom;
import library.logic.ConductorAtom;
import utils.UID;

/**
* ASSEMBLY FACTORY v4.3 (Fixed Native Drivers)
* Создает правильные экземпляры классов для нативных атомов.
*
* v4.3 Changes:
* - Added missing cases for SignalGen, AudioIn, FPSMonitor, FrameTime
*/
class AssemblyFactory {
	/**
	* Creates an Atom or Assembly instance.
	* If forcedId is null, generates a new UUID.
	*
	* @param typeId Blueprint ID
	* @param forcedId Optional specific instance ID
	* @param initialState Optional state to restore after creation
	*/
	public static function createAtom(typeId:String, ?forcedId:String, ?initialState:Dynamic):Atom {
		var bp = AtomRegistry.get(typeId);
		var id:String = (forcedId != null) ? forcedId : UID.generate();
		
		if (bp == null) {
			trace('ERROR: Blueprint not found: $typeId');
			return null;
		}

		var atom:Atom = null;

		// === NATIVE ATOMS ===
		switch (typeId) {
			// Active Drivers
			case "UniversalGen": atom = new UniversalGeneratorAtom(id);
			case "SignalGen": atom = new SignalGeneratorAtom(id);
			case "FPSMonitor": atom = new FPSMonitorAtom(id);
			case "FrameTime": atom = new FrameTimeAtom(id);
			case "AudioIn": atom = new AudioInputAtom(id);
			
			// Logic
			case "NAND": atom = new NandAtom(id);
			case "Conductor": atom = new ConductorAtom(id);
			
			// Electro
			case "Button": atom = new ButtonAtom(id);
			case "Toggle": atom = new library.electro.ToggleAtom(id);
			case "LED": atom = new LedAtom(id);
			case "Relay": atom = new RelayAtom(id);
			case "Oscilloscope": atom = new OscilloscopeAtom(id);
			case "TextInput": atom = new TextInputAtom(id);
			
			// Default: create Assembly for composite
			default:
				atom = new Assembly(id, bp);
		}

		// v4.2: Restore state if provided
		if (atom != null && initialState != null) {
			atom.restoreState(initialState);
		}

		return atom;
	}

	public static function createAssembly(typeId:String):Assembly {
		var atom = createAtom(typeId);
		if (Std.isOfType(atom, Assembly)) {
			return cast atom;
		} else {
			trace('WARN: $typeId is a native Atom, not an Assembly.');
			return null;
		}
	}

	/**
	* Check if a type is a composite (user-created assembly).
	*/
	public static function isComposite(typeId:String):Bool {
		var bp = AtomRegistry.get(typeId);
		if (bp == null) return false;
		// Native atoms with logic are not composites (though these drivers use _onUpdate, not logic func)
		// The key differentiator here is usually internalAtoms. Native atoms have null internalAtoms.
		if (bp.internalAtoms != null && bp.internalAtoms.length > 0) return true;
		return false;
	}
}