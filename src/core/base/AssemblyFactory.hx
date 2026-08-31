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
import library.electro.BufferingAtom;
import library.electro.PassThroughAtom;
import library.drivers.MiniAudioAtom;
import library.drivers.SignalGenerator;
import library.drivers.ComPortAtom;
import library.drivers.WebSocketAtom;
using StringTools;

/**
* ASSEMBLY FACTORY v1.5 (Global Naming & Paste Logic + Cycle Guard)
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
* - v1.3: Support global uniqueness checks and intelligent _N suffix parsing for Copy/Paste
* - v1.5: Construction cycle guard — a template cycle (X→Y→X) can no longer
*   drive the Assembly constructor into infinite recursion; the nested
*   instance is refused (null) and every caller already handles null
*   (the load path feeds Assembly v2.10 dead-AtomDef self-heal).
*
* ═══════════════════════════════════════════════════════════════════════════
* v1.3 ADDITIONS (Global Naming & Paste Logic):
* ═══════════════════════════════════════════════════════════════════════════
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   Display Name Generation:                                              │
* │                                                                         │
* │   generateUniqueDisplayName(typeId, isNameTaken, desiredBase, isPaste)  │
* │   ───────────────────────────────────────────────────────────────────── │
* │   Generates a unique, human-readable name for a newly created atom.     │
* │                                                                         │
* │   Algorithm:                                                            │
* │   1. Determine base name (from registry or desiredBaseName).            │
* │   2. Parse existing "_N" suffix (e.g., "Pass_1" → base:"Pass", num:1).  │
* │   3. If isPaste == true: force startNum = (parsed.num ?? 0) + 1.        │
* │   4. If isPaste == false and no suffix and name is free: return as-is.  │
* │   5. Otherwise: increment startNum until isNameTaken(candidate) is false│
* │                                                                         │
* │   Examples:                                                             │
* │   ─────────                                                             │
* │   Create "PassThrough" (free)         → "PassThrough"                   │
* │   Create "PassThrough" (taken)        → "PassThrough_1"                 │
* │   Paste "PassThrough"                 → "PassThrough_1" (forced suffix) │
* │   Paste "PassThrough_2"               → "PassThrough_3"                 │
* │   Create "Pass_1" (free, not paste)   → "Pass_1"                        │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class AssemblyFactory
{
        /**
        * v1.5 CONSTRUCTION CYCLE GUARD: blueprint ids currently being
        * constructed down the active Assembly cascade. A legitimate
        * construction cascade never repeats a blueprint id (recursive
        * templates are impossible by definition); a repeat means a
        * template cycle (X→Y→X) — refuse the nested instance instead of
        * overflowing the stack. push/remove pairs keep the stack balanced;
        * the catch clause keeps it clean even if a constructor throws.
        */
        private static var _constructionStack:Array<String> = [];

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

// ─────────────────────────────────────────────────────────────
// FILE WRITER ATOM — File i/o exchange HTML% version
// ─────────────────────────────────────────────────────────────
                                                                case "FILEWRITERATOM":
                                                                case "FILEWRITER":
                                                                case "FILE WRITER":
                                                                        normalizedTypeId = "FileWriterAtom";

                                                                        // ─────────────────────────────────────────────────────────────
                                                                        // FILE READER ATOM — mirror of File Writer (Этап 4a-1, Task 140)
                                                                        // ─────────────────────────────────────────────────────────────
                                                                case "FILEREADERATOM":
                                                                case "FILEREADER":
                                                                case "FILE READER":
                                                                normalizedTypeId = "FileReaderAtom";
                                                                // ─────────────────────────────────────────────────────────────
                                                                // DATA STORAGE ATOM — runtime-хранилище данных (Этап 4a-2, Task 145)
                                                                // ─────────────────────────────────────────────────────────────
                                                                case "DATASTORAGEATOM":
                                                                case "DATASTORAGE":
                                                                case "DATA STORAGE":
                                                                normalizedTypeId = "DataStorageAtom";
// ─────────────────────────────────────────────────────────────
// PICTURE — atom-portrait, consumer of the binary pipe (Этап 4a-3, Task 155)
// ─────────────────────────────────────────────────────────────
                                                                case "PICTUREATOM":
                                                                case "PICTURE":
                                                                normalizedTypeId = "PictureAtom";
// ─────────────────────────────────────────────────────────────
// WEBSOCKET — WebSocket Client (cross-platform)
// ─────────────────────────────────────────────────────────────
                                                                case "WebSocketAtom":
                                                                case "WEBSOCKETATOM":
                                                                case "WEBSOCKET":
                                                                        normalizedTypeId = "WebSocketAtom";
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
                                                                case "TEXTAREA": normalizedTypeId = "TextArea";
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
                                                                atom = new library.drivers.ComPortAtom(id);
                                                                trace(' AssemblyFactory: Created ComPortAtom...');
                                                                
                                                case "FileWriterAtom":
                                                                atom = new library.drivers.FileWriterAtom(id);
                                                                trace('📝 AssemblyFactory: Created FileWriterAtom...');

                                                case "FileReaderAtom":
                                                                atom = new library.drivers.FileReaderAtom(id);
                                                                trace('📖 AssemblyFactory: Created FileReaderAtom...');
                                                case "DataStorageAtom":
                                                                atom = new library.drivers.DataStorageAtom(id);
                                                                trace('💾 AssemblyFactory: Created DataStorageAtom...');
                                                case "PictureAtom":
                                                                atom = new library.drivers.PictureAtom(id);
                                                                trace('🖼 AssemblyFactory: Created PictureAtom...');
// =============================================================
// WEB SOCKET — Web Socket port
// =============================================================
                                                case "WebSocketAtom":
                                                                atom = new library.drivers.WebSocketAtom(id);
                                                                trace('🌐 AssemblyFactory: Created WebSocketAtom...');
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
                                                case "TextArea":
                                                                atom = new library.electro.TextAreaAtom(id);
// =============================================================
// LOGIC
// =============================================================
                        case "PassThroughAtom":
                                atom = new PassThroughAtom(id);
                        case "BufferingAtom":
                                atom = new BufferingAtom(id);
// =============================================================
// DEFAULT: Composite user-created Assembly
// =============================================================
                        default:
// This path is used for all user-made blueprints that contain internalAtoms
// v1.5 CONSTRUCTION CYCLE GUARD: a template cycle (X→Y→X — from a corrupted
// save or a pre-guard paste) would recurse here forever. If this blueprint
// is already under construction higher up the current cascade, skip the
// nested instance: return null. Every createAtom caller handles null — the
// load path (Assembly._createInternalInstances) feeds it into the v2.10
// dead-AtomDef self-heal, which drops the cyclic AtomDef and its dangling
// _idMap entry; the command path aborts cleanly.
                                if (_constructionStack.indexOf(bp.id) != -1)
                                {
                                        trace('AssemblyFactory: CYCLE — blueprint "${bp.id}" is already under construction; template cycle broken, nested instance skipped.');
                                        return null;
                                }
                                _constructionStack.push(bp.id);
                                try
                                {
                                        atom = new Assembly(id, bp);
                                }
                                catch (e:Dynamic)
                                {
                                        _constructionStack.remove(bp.id);
                                        throw e; // preserve the original failure
                                }
                                _constructionStack.remove(bp.id);
                }
// Restore saved state (frequency, mode, buffer settings, etc.)
                if (atom != null && initialState != null)
                {
                        atom.restoreState(initialState);
                }
                return atom;
        }

// =====================================================================
// DISPLAY NAME GENERATION (v1.3 — Global + Paste-aware)
// =====================================================================
        /**
        * Generate a globally-unique display name for a newly created atom.
        *
        * v1.3 CHANGES:
        * ──────────────
        *  - Signature changed from (typeId, assembly) to
        *    (typeId, isNameTaken, ?desiredBaseName, ?isPaste).
        *  - Caller now passes a String → Bool predicate for global
        *    uniqueness check, instead of a parent Assembly.
        *  - This decouples the factory from the Assembly class and
        *    allows it to work in any context (root, sub-assembly,
        *    brand-new empty Assembly not yet constructed, etc.).
        *  - Supports intelligent "_N" suffix parsing for paste:
        *    pasting "Foo_2" yields "Foo_3", not "Foo_2_1".
        *
        * Algorithm:
        *  1. Determine base name:
        *     - If desiredBaseName provided and non-empty → use it
        *     - Else if AtomRegistry has a name for typeId → use it
        *     - Else → use typeId as-is
        *  2. Parse existing "_N" suffix (e.g., "Pass_1" → base:"Pass", num:1)
        *  3. If isPaste == true:
        *       startNum = (parsed.num ?? 0) + 1
        *       forced to append suffix (even if base is free)
        *  4. If isPaste == false:
        *       If no suffix AND base name is free → return as-is
        *       Else: startNum = (parsed.num ?? 0) + 1
        *  5. Loop: candidate = base + "_" + startNum, increment until free
        *
        * @param typeId            Atom type ID (used to look up human-readable name
        *                          when desiredBaseName is null)
        * @param isNameTaken       Predicate: returns true if name is taken globally.
        *                          Signature is (String, ?String) -> Bool so it can
        *                          receive NamingService.isInstanceNameTaken or
        *                          EditorContext.isNameTakenGlobally directly without
        *                          any adapter. The optional excludeId is ignored
        *                          by this factory (the factory never excludes).
        * @param desiredBaseName   Optional override for the base name
        *                          (e.g., "CustomAssembly" for grouped assemblies)
        * @param isPaste           If true, force "_N" suffix and bump from parsed num
        * @return Globally-unique display name string (never null, never empty)
        */
        public static function generateUniqueDisplayName(
                typeId:String,
                isNameTaken:(String, ?String) -> Bool,
                ?desiredBaseName:String = null,
                ?isPaste:Bool = false
        ):String
        {
                if (isNameTaken == null)
                {
// Defensive fallback: assume nothing is taken
                        isNameTaken = function(s:String, ?ex:String) return false;
                }

// ─── Step 1: Determine base name ───
                var baseName:String;
                if (desiredBaseName != null && desiredBaseName.length > 0)
                {
                        baseName = desiredBaseName;
                }
                else if (typeId != null)
                {
                        var bp = AtomRegistry.get(typeId);
                        baseName = (bp != null && bp.name != null && bp.name.length > 0)
                                ? bp.name
                                : typeId;
                }
                else
                {
                        baseName = "Atom";
                }

// ─── Step 2: Parse existing _N suffix ───
                var parsed = parseName(baseName);
                var coreBase:String = parsed.base;
                var parsedNum:Null<Int> = parsed.number;

// ─── Step 3: Decide starting candidate ───
                var candidate:String;
                if (isPaste)
                {
// Paste: ALWAYS force a suffix, starting from parsed.num + 1
                        var startNum:Int = (parsedNum != null) ? parsedNum + 1 : 1;
                        candidate = coreBase + "_" + startNum;
                        while (isNameTaken(candidate))
                        {
                                startNum++;
                                candidate = coreBase + "_" + startNum;
                        }
                        return candidate;
                }
                else
                {
// v1.4 FIX: use base name as-is whenever it is FREE — even when it already
// carries a "_N" suffix. The old condition (parsedNum == null && ...) forced
// a bump for every numbered base: GroupAtomsCommand resolved blueprint name
// "Custom Assembly_2" (unique among blueprints), then the instance got
// "Custom Assembly_3" (bumped from parsed num 2). Result: node label in the
// parent said "Custom Assembly_3" while the editor title (blueprint.name)
// said "Custom Assembly_2" — "мы внутри Custom Assembly_3, но индицируется
// Custom Assembly_2". The paste flow (isPaste=true) still forces a bump in
// the branch above and is NOT affected by this change.
                        if (!isNameTaken(baseName))
                        {
                                return baseName;
                        }
// Otherwise: bump from parsed.num (or 0) until free
                        var startNum:Int = (parsedNum != null) ? parsedNum + 1 : 1;
                        candidate = coreBase + "_" + startNum;
                        while (isNameTaken(candidate))
                        {
                                startNum++;
                                candidate = coreBase + "_" + startNum;
                        }
                        return candidate;
                }
        }

        /**
        * Parse a name into its core part and optional trailing number.
        * e.g., "Pass_1" -> {base: "Pass", number: 1}
        *      "Pass" -> {base: "Pass", number: null}
        *      "My_Button_2" -> {base: "My_Button", number: 2}
        */
        private static function parseName(name:String): {base:String, number:Null<Int>}
        {
                // Match everything up to the last underscore, followed by digits at the end of the string
                var regex = ~/(.*)_(\d+)$/;
                if (regex.match(name))
                {
                        return
                        {
                                base: regex.matched(1),
                                number: Std.parseInt(regex.matched(2))
                        };
                }
                return { base: name, number: null };
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

