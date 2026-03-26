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
import library.logic.ORGateAtom;
import utils.UID;
// === FIX: Добавить using StringTools для метода replace() ===
using StringTools;

/**
* ASSEMBLY FACTORY v4.4 (TypeId Normalization)
* Создает правильные экземпляры классов для нативных атомов.
*
* v4.4 Changes:
* - Added typeId normalization for compatibility with JSON-loaded blueprints
* - Added missing cases for SignalGen, AudioIn, FPSMonitor, FrameTime
*/
class AssemblyFactory
{
	/**
	* Creates an Atom or Assembly instance.
	* If forcedId is null, generates a new UUID.
	*
	* @param typeId Blueprint ID
	* @param forcedId Optional specific instance ID
	* @param initialState Optional state to restore after creation
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
		trace('AssemblyFactory: Creating ${bp.name} (typeId: $typeId, id: $id, internalAtoms: ${bp.internalAtoms != null ? bp.internalAtoms.length : 0})');

// === FIX: Нормализация typeId для совместимости ===
// JSON может загружать typeId как "NAND Gate" вместо "NAND"
		var normalizedTypeId:String = typeId;
		if (typeId != null)
		{
// Приводим к верхнему регистру и удаляем пробелы для сравнения
			var upperId:String = typeId.toUpperCase().replace(" ", "");
			switch (upperId)
			 {
                case "NAND": normalizedTypeId = "NAND";
                case "NANDGATE": normalizedTypeId = "NAND";
                
                // === FIX: Перенаправляем старые и новые имена на ORGateAtom ===
                case "CONDUCTOR": normalizedTypeId = "ORGateAtom";
                case "OR_GATE": normalizedTypeId = "ORGateAtom";
                case "OR_GATE_MULTI": normalizedTypeId = "ORGateAtom";
                case "ORGATE": normalizedTypeId = "ORGateAtom";
                case "ORGATEATOM": normalizedTypeId = "ORGateAtom";
                // ==============================================================

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
                case "SIGNALGEN": normalizedTypeId = "SignalGen";
                case "SIGNALGENERATOR": normalizedTypeId = "SignalGen";
                case "FPSMONITOR": normalizedTypeId = "FPSMonitor";
                case "FRAMETIME": normalizedTypeId = "FrameTime";
                case "AUDIOIN": normalizedTypeId = "AudioIn";
                case "AUDIOINPUT": normalizedTypeId = "AudioIn";
                case "NOT_GATE": normalizedTypeId = "NOT_Gate";
                case "NOTGATE": normalizedTypeId = "NOT_Gate";
                case "AND_GATE": normalizedTypeId = "AND_Gate";
                case "ANDGATE": normalizedTypeId = "AND_Gate";
                case "OR_GATE_STD": normalizedTypeId = "OR_Gate";
                case "NOR_GATE": normalizedTypeId = "NOR_Gate";
                case "T_TRIGGER": normalizedTypeId = "T-TRIGGER";
                case "TTRIGGER": normalizedTypeId = "T-TRIGGER";
                default: normalizedTypeId = typeId;
            }
		}
// ================================================================

		var atom:Atom = null;
// === NATIVE ATOMS ===
// === FIX: Используем normalizedTypeId вместо typeId ===
		switch (normalizedTypeId)
		{
// Active Drivers
			case "UniversalGen": atom = new UniversalGeneratorAtom(id);
			case "SignalGen": atom = new SignalGeneratorAtom(id);
			case "FPSMonitor": atom = new FPSMonitorAtom(id);
			case "FrameTime": atom = new FrameTimeAtom(id);
			case "AudioIn": atom = new AudioInputAtom(id);
// Logic
			case "NAND": atom = new NandAtom(id);
			case "ORGateAtom": atom = new ORGateAtom(id);
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
				trace('AssemblyFactory: Created Assembly, isLogic=${atom.isLogic}');
		}

// v4.2: Restore state if provided
		if (atom != null && initialState != null)
		{
			atom.restoreState(initialState);
			trace('AssemblyFactory: Restored state, isLogic=${atom.isLogic}');
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
		else {
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
// Native atoms with logic are not composites (though these drivers use _onUpdate, not logic func)
// The key differentiator here is usually internalAtoms. Native atoms have null internalAtoms.
		if (bp.internalAtoms != null && bp.internalAtoms.length > 0) return true;
		return false;
	}
}