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
import library.electro.FFTAtom;
import library.electro.BufferingAtom; // ← ДОБАВЛЕНО
import library.drivers.MiniAudioAtom;
import library.drivers.SignalGenerator;
import library.drivers.ComPortAtom;
import library.drivers.ComEnumeratorAtom;
import library.logic.PassThroughAtom;

using StringTools;

/**
* ASSEMBLY FACTORY v1.2 (BufferingAtom Added)
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
* - v1.1: Generate unique displayName for new atoms
*
* ═══════════════════════════════════════════════════════════════════════════
* v1.1 ADDITIONS:
* ═══════════════════════════════════════════════════════════════════════════
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   Display Name Generation:                                              │
* │                                                                         │
* │   generateUniqueDisplayName(typeId, assembly) → String                  │
* │   ────────────────────────────────────────────────────                  │
* │   Generates a unique, human-readable name for a newly created atom.     │
* │                                                                         │
* │   Algorithm:                                                            │
* │   1. Get human-readable name from AtomRegistry (e.g., "Button")         │
* │   2. Check if name is available via assembly.hasAtomWithName()          │
* │   3. If available → return as-is                                        │
* │   4. If taken → append "_N" (Button_1, Button_2, ...)                   │
* │   5. Increment N until unique name found                                │
* │                                                                         │
* │   Usage:                                                                │
* │   ───────                                                               │
* │   // In CreateAtomCommand.executeInternal():                            │
* │   var atom = AssemblyFactory.createAtom(typeId, instanceId);            │
* │   atom.displayName = AssemblyFactory                                    │
* │       .generateUniqueDisplayName(typeId, assembly);                     │
* │                                                                         │
* │   // On project load (restoreState):                                    │
* │   // displayName is restored from saved state — generation skipped      │
* │                                                                         │
* │   Examples:                                                             │
* │   ─────────                                                             │
* │   First Button added:     "Button"                                      │
* │   Second Button added:    "Button_1"                                    │
* │   Third Button added:     "Button_2"                                    │
* │   First SignalGenerator:  "Signal Generator"                            │
* │   Second SignalGenerator: "Signal Generator_1"                          │
* │   User renamed to "MyBtn":                                              │
* │   Next Button added:      "Button_3" (skips MyBtn, finds next free)     │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
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
// NET RADIO PLAYER — Internet radio metadata driver
// ─────────────────────────────────────────────────────────────
				case "NETRADIOPLAYERATOM":
				case "NETRADIOPLAYER":
				case "NET RADIO PLAYER":
				case "NETRADIO":
					normalizedTypeId = "NETRadioPlayerAtom";
// ─────────────────────────────────────────────────────────────
// URL AUDIO STREAM PLAYER — Internet radio player
// ─────────────────────────────────────────────────────────────
				case "URLAUDIOSTREAMPLAYERATOM",
					 "URLAUDIOSTREAMPLAYER",
					 "URL STREAM PLAYER",
					 "URLPLAYER":
					normalizedTypeId = "URLAudioStreamPlayerAtom";
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
				case "FFTATOM":
				case "FFT": normalizedTypeId = "FFTAtom";
				case "TEXTINPUT": normalizedTypeId = "TextInput";
// ─────────────────────────────────────────────────────────────
// LOGIC
// ─────────────────────────────────────────────────────────────
				case "PASSTHROUGH":
				case "PASSTHROUGHLINE": normalizedTypeId = "PassThroughAtom";
// ─────────────────────────────────────────────────────────────
// BUFFERING
// ─────────────────────────────────────────────────────────────
				case "BUFFERINGATOM":
				case "BUFFERING": normalizedTypeId = "BufferingAtom";
				
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
				atom = new library.drivers.SignalGenerator(id);
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
// NET RADIO PLAYER — internet radio metadata extraction
// =============================================================
			case "NETRadioPlayerAtom":
				#if cpp
				atom = new library.drivers.NETRadioPlayerAtom(id);
				trace('📻 AssemblyFactory: Created NETRadioPlayerAtom v2.0...');
				#else
				trace('⚠️ NETRadioPlayerAtom requires C++ target');
				#end
// ─────────────────────────────────────────────────────────────
// URL AUDIO STREAM PLAYER — Internet radio player
// ─────────────────────────────────────────────────────────────
				case "URLAudioStreamPlayerAtom":
				#if cpp
					atom = new library.drivers.URLAudioStreamPlayerAtom(id);
					trace('📻 AssemblyFactory: URLAudioStreamPlayerAtom v1.0...');
				#else
					trace('⚠️ URLAudioStreamPlayerAtom requires C++ target');
				#end
// =============================================================
// SYSTEM VU METER — Windows WASAPI audio meter
// =============================================================
				#if cpp
				case "SystemVUMeterAtom":
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
			case "FFTAtom":
				atom = new FFTAtom(id);
			case "TextInput":
				atom = new TextInputAtom(id);
// =============================================================
// LOGIC
// =============================================================
			case "PassThroughAtom":
				atom = new PassThroughAtom(id);
			case "BufferingAtom": // ← ДОБАВЛЕНО
				atom = new BufferingAtom(id);
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

// =====================================================================
// DISPLAY NAME GENERATION (v1.1)
// =====================================================================
	/**
	* Generate a unique, human-readable display name for a newly created atom.
	*
	* Algorithm:
	* 1. Get human-readable name from AtomRegistry (e.g., "Signal Generator")
	* 2. Check if name is available via assembly.hasAtomWithName()
	* 3. If available → return as-is (first atom of this type)
	* 4. If taken → append "_N" and increment until unique
	*
	* Examples:
	*   First Button added:     "Button"
	*   Second Button added:    "Button_1"
	*   Third Button added:     "Button_2"
	*   First SignalGenerator:  "Signal Generator"
	*   Second SignalGenerator: "Signal Generator_1"
	*
	* Note: This method does NOT check against user-renamed atoms that
	* happen to match the pattern. It simply finds the next free slot
	* in the "BaseName_N" sequence.
	*
	* @param typeId   Atom type ID (e.g., "Button", "SignalGenerator")
	* @param assembly Parent assembly for uniqueness check
	* @return Unique display name string
	*/
	public static function generateUniqueDisplayName(typeId:String, assembly:Assembly):String
	{
		if (typeId == null) return "Unknown";
		if (assembly == null) return typeId;

// Get human-readable name from registry
		var bp = AtomRegistry.get(typeId);
		var baseName:String = (bp != null && bp.name != null && bp.name.length > 0)
		? bp.name
		: typeId;

// First try: use base name as-is
		if (!assembly.hasAtomWithName(baseName))
		{
			return baseName;
		}

// Base name taken — find next available number
		var counter:Int = 1;
		var candidate:String = baseName + "_" + counter;
		while (assembly.hasAtomWithName(candidate))
		{
			counter++;
			candidate = baseName + "_" + counter;
		}
		return candidate;
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