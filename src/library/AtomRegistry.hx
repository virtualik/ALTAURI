package library;

import core.data.Blueprint;
import core.types.ContactType;

/**
 * ATOM REGISTRY v2.3 (Inline Editor Metadata)
 * 
 * Central registry for all atom type blueprints.
 * Manages both native (built-in) and custom (user-created) atoms.
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   AtomRegistry (Static Singleton)                                       │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  _blueprints:Map<String, Blueprint>                             │   │
 * │   │                                                                 │   │
 * │   │  Native Atoms (registered in initialize()):                     │   │
 * │   │  - Button, LED, Toggle, TextInput, Relay                        │   │
 * │   │  - SignalGenerator, MiniAudioAtom, SystemVUMeterAtom            │   │
 * │   │  - ComPortAtom, ComEnumeratorAtom, Oscilloscope                 │   │
 * │   │                                                                 │   │
 * │   │  Custom Atoms (loaded from .atom files):                        │   │
 * │   │  - User-created assemblies stored in library/ folder            │   │
 * │   │  - Loaded via scanFolder() and loadAtomFile()                   │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Public API:                                                           │
 * │   - initialize()      → Register all native atoms                       │
 * │   - get(id)           → Retrieve blueprint by ID                        │
 * │   - getAllIds()       → Get list of all registered atom types           │
 * │   - registerBlueprint → Add custom blueprint                            │
 * │   - remove(id)        → Remove blueprint (for deletion)                 │
 * │   - scanFolder(path)  → Load all .atom files from directory             │
 * │   - loadAtomFile(path)→ Parse and register single .atom file            │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * v2.3 Changes:
 * - Added ParameterPriority metadata to PinDef for inline editor visibility
 * - Added label and visibleInEditor fields support
 */
class AtomRegistry
{
    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();
    
    /**
     * Custom library path for user-created assemblies.
     * Set during ProjectManager.init().
     */
    public static var customLibraryPath:String = "";
    
    /**
     * Internal helper to register a blueprint with common parameters.
     * 
     * @param id          Unique identifier (e.g., "Button", "SignalGenerator")
     * @param name        Human-readable name
     * @param pins        Array of PinDef describing inputs/outputs
     * @param logic       Optional processing function (for native atoms)
     * @param deviceType  DeviceView type hint (e.g., "button", "oscilloscope")
     * @param isNative    True if this is a built-in atom (cannot be edited)
     * @param isActive    True if this atom requires DriverManager updates
     */
    private static function reg(
        id:String, 
        name:String, 
        pins:Array<core.data.Blueprint.PinDef>, 
        ?logic, 
        ?deviceType:String = null, 
        ?isNative:Bool = true, 
        ?isActive:Bool = false
    )
    {
        var bp = new Blueprint(id, name, pins, null);
        bp.deviceType = deviceType;
        bp.isNative = isNative;
        bp.isActive = isActive;
        _blueprints.set(id, bp);
    }
    
    /**
     * Get all registered atom type IDs.
     * 
     * @return Array of blueprint IDs (both native and custom)
     */
    public static function getAllIds():Array<String>
    {
        return [for (key in _blueprints.keys()) key];
    }
    
    /**
     * Initialize the registry with all native (built-in) atoms.
     * Called once at application startup.
     * 
     * Registered atoms:
     * - Electro/UI: Button, LED, Toggle, TextInput, Relay
     * - Active Drivers: SignalGenerator, MiniAudioAtom, SystemVUMeterAtom,
     *                   ComPortAtom, ComEnumeratorAtom
     * - Passive Displays: Oscilloscope
     */
    public static function initialize():Void
    {
        if (_initialized) return;
        
        // =================================================================
        // NATIVE ATOMS REGISTRATION
        // =================================================================
        
        // --- Electro / UI ---
        reg("Button", "Push Button", [
            {name: "out", type: OUTPUT, dataType: "bool"}
        ], null, "button");
        
        reg("LED", "LED Indicator", [
            {name: "in", type: INPUT, dataType: "bool"}
        ], null, "led", true, false);
        
        reg("Toggle", "Toggle Switch", [
            {name: "out", type: OUTPUT, dataType: "bool"}
        ], null, "toggle");
        
        reg("TextInput", "Text Input", [
            {name: "set", type: INPUT, dataType: "string"},
            {name: "out", type: OUTPUT, dataType: "string"}
        ], null, "textinput");
        
        reg("Relay", "Relay", [
            {name: "signal", type: INPUT, dataType: "any"},
            {name: "control", type: INPUT, dataType: "bool"},
            {name: "out", type: OUTPUT, dataType: "any"}
        ], null, "relay");
        
        // =================================================================
        // ACTIVE DRIVERS (require DriverManager updates)
        // =================================================================
        
        reg("SignalGenerator", "Signal Generator", [
            {name: "freq", type: INPUT, defaultValue: 1.0, dataType: "float", 
             priority: IMPORTANT, label: "Freq", visibleInEditor: true},
            {name: "quantum", type: INPUT, defaultValue: 0.1, dataType: "float", 
             priority: OPTIONAL, visibleInEditor: false},
            {name: "mode", type: INPUT, defaultValue: 3, dataType: "int", 
             priority: IMPORTANT, label: "Mode", visibleInEditor: true},
            {name: "out", type: OUTPUT, dataType: "float", priority: CRITICAL},
            {name: "changed", type: OUTPUT, dataType: "bool", priority: OPTIONAL}
        ], null, "panel", true, true);
        
        reg("MiniAudioAtom", "Mini Audio Capture", [
            {name: "mode",     type: INPUT,  defaultValue: 1,    dataType: "int",     priority: IMPORTANT, label: "Mode"},
            {name: "quantum",  type: INPUT,  defaultValue: 0.01, dataType: "float",   priority: OPTIONAL},
            {name: "gain",     type: INPUT,  defaultValue: 1.0,  dataType: "float",   priority: IMPORTANT, label: "Gain"},
            {name: "channel",  type: INPUT,  defaultValue: 0,    dataType: "int",     priority: OPTIONAL},
            {name: "rate",     type: INPUT,  defaultValue: 0,    dataType: "int",     priority: OPTIONAL},
            {name: "sample",   type: OUTPUT, dataType: "float",  priority: CRITICAL},
            {name: "changed",  type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
            {name: "rms",      type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "RMS"},
            {name: "clip",     type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
            {name: "tick",     type: OUTPUT, dataType: "bool",   priority: INTERNAL},
            {name: "level",    type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "Level"},
            {name: "device",   type: OUTPUT, dataType: "string", priority: OPTIONAL}
        ], null, "miniaudio", true, true);
        
        reg("SystemVUMeterAtom", "System Stereo VU Meter", [
            {name: "mode",     type: INPUT,  defaultValue: 0,    dataType: "int",   priority: IMPORTANT, label: "Source"},
            {name: "peakL",    type: OUTPUT, dataType: "float",  priority: CRITICAL, label: "Peak L"},
            {name: "peakR",    type: OUTPUT, dataType: "float",  priority: CRITICAL, label: "Peak R"},
            {name: "peakMono", type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "Peak Mono"},
            {name: "percentL", type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "% L"},
            {name: "percentR", type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "% R"},
            {name: "dB_L",     type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "dB L"},
            {name: "dB_R",     type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "dB R"},
            {name: "channels", type: OUTPUT, dataType: "int",    priority: OPTIONAL, label: "Channels"},
            {name: "active",   type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
            {name: "clipL",    type: OUTPUT, dataType: "bool",   priority: OPTIONAL, label: "Clip L"},
            {name: "clipR",    type: OUTPUT, dataType: "bool",   priority: OPTIONAL, label: "Clip R"}
        ], null, "vumeter", true, true);
        
        reg("ComPortAtom", "COM Port", [
            {name: "portName",  type: INPUT,  defaultValue: "COM1", dataType: "string", priority: IMPORTANT, label: "Port"},
            {name: "baudRate",  type: INPUT,  defaultValue: 9600,   dataType: "int",    priority: IMPORTANT, label: "Baud"},
            {name: "open",      type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
            {name: "close",     type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
            {name: "send",      type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
            {name: "txData",    type: INPUT,  defaultValue: "",     dataType: "string", priority: OPTIONAL},
            {name: "setDTR",    type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
            {name: "isOpen",    type: OUTPUT, dataType: "bool",     priority: CRITICAL},
            {name: "rxData",    type: OUTPUT, dataType: "string",   priority: IMPORTANT, label: "RX"},
            {name: "rxTick",    type: OUTPUT, dataType: "bool",     priority: INTERNAL},
            {name: "txTick",    type: OUTPUT, dataType: "bool",     priority: INTERNAL},
            {name: "error",     type: OUTPUT, dataType: "string",   priority: IMPORTANT, label: "Error"},
            {name: "errorTick", type: OUTPUT, dataType: "bool",     priority: INTERNAL}
        ], null, "comport", true, true);
        
        reg("ComEnumeratorAtom", "COM Enumerator", [
            {name: "ports", type: OUTPUT, dataType: "string", priority: CRITICAL}
        ], null, "comenumerator", true, true);
        
		reg("NETRadioPlayerAtom", "NET Radio Player", [
			{name: "stream_url",    type: INPUT,  dataType: "string",  priority: IMPORTANT, label: "URL"},
			{name: "poll_interval", type: INPUT,  defaultValue: 5.0,   dataType: "float",   priority: OPTIONAL, label: "Poll (s)"},
			{name: "playCtrl",      type: INPUT,  defaultValue: false,  dataType: "bool",    priority: CRITICAL, label: "Play"},
			{name: "title",         type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Title"},
			{name: "artist",        type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Artist"},
			{name: "track",         type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Track"},
			{name: "raw_metadata",  type: OUTPUT, dataType: "string",  priority: INTERNAL},
			{name: "updated",       type: OUTPUT, dataType: "bool",    priority: OPTIONAL},
			{name: "state",         type: OUTPUT, dataType: "bool",    priority: OPTIONAL, label: "Error"},
			{name: "error",         type: OUTPUT, dataType: "string",  priority: OPTIONAL, label: "Error Msg"}
		], null, "netradio", true, true);

        // =================================================================
        // PASSIVE DISPLAYS (no active processing)
        // =================================================================
        
        reg("Oscilloscope", "Oscilloscope", [
            {name: "in", type: INPUT, dataType: "array", priority: CRITICAL}
        ], null, "oscilloscope");
        
        _initialized = true;
    }
    
    /**
     * Retrieve a blueprint by its unique ID.
     * 
     * @param id Blueprint ID (e.g., "Button", "SignalGenerator", "CustomAssembly_abc1")
     * @return Blueprint instance or null if not found
     */
    public static function get(id:String):Blueprint
    {
        return _blueprints.get(id);
    }
    
    /**
     * Register a custom blueprint (typically loaded from .atom file).
     * 
     * @param id Unique identifier
     * @param bp Blueprint instance
     */
    public static function registerBlueprint(id:String, bp:Blueprint):Void
    {
        _blueprints.set(id, bp);
    }
    
    /**
     * Remove a blueprint from the registry.
     * Used when deleting custom assemblies.
     * 
     * @param id Blueprint ID to remove
     * @return True if removed, false if not found
     */
    public static function remove(id:String):Bool
    {
        if (_blueprints.exists(id))
        {
            _blueprints.remove(id);
            trace('AtomRegistry: Removed $id');
            return true;
        }
        trace('AtomRegistry: $id not found for removal');
        return false;
    }
    
    /**
     * Check if a blueprint with given ID exists.
     * 
     * @param id Blueprint ID
     * @return True if registered
     */
    public static function exists(id:String):Bool
    {
        return _blueprints.exists(id);
    }
    
    /**
     * Scan a directory for .atom files and register them.
     * Called during ProjectManager.init() to load user library.
     * 
     * @param path Directory path to scan
     */
    public static function scanFolder(path:String):Void
    {
        #if sys
        if (!sys.FileSystem.exists(path))
        {
            try
            {
                sys.FileSystem.createDirectory(path);
            }
            catch (e:Dynamic)
            {
                trace("Error creating library dir: " + e);
            }
            return;
        }
        
        trace("Scanning library folder: " + path);
        
        for (file in sys.FileSystem.readDirectory(path))
        {
            if (StringTools.endsWith(file, ".atom"))
            {
                var fullPath = path + "/" + file;
                loadAtomFile(fullPath);
            }
        }
        #end
    }
    
    /**
     * Load and parse a single .atom file, then register its blueprint.
     * 
     * File format (JSON):
     * {
     *   "version": "1.0",
     *   "blueprint": {
     *     "id": "CustomAssembly_abc1",
     *     "name": "My Assembly",
     *     "category": "General",
     *     "pins": [...],
     *     "internalAtoms": [...],
     *     "internalConnections": [...]
     *   }
     * }
     * 
     * @param fullPath Absolute path to .atom file
     * @return True if successfully loaded and registered
     */
    public static function loadAtomFile(fullPath:String):Bool
    {
        #if sys
        try {
            var content = sys.io.File.getContent(fullPath);
            var json = haxe.Json.parse(content);
            var rawBp:Dynamic = json.blueprint;
            
            // Parse pins
            var pins:Array<core.data.Blueprint.PinDef> = [];
            if (rawBp.pins != null)
            {
                var seenNames = new Map<String, Bool>();
                for (p in (cast(rawBp.pins, Array<Dynamic>)))
                {
                    var pinName = Std.string(p.name);
                    if (!seenNames.exists(pinName))
                    {
                        pins.push({
                            name: pinName,
                            type: _parseContactType(p.type),
                            defaultValue: p.defaultValue,
                            dataType: Std.string(p.dataType)
                        });
                        seenNames.set(pinName, true);
                    }
                }
            }
            
            // Parse connections
            var conns:Array<core.data.ConnectionDef> = [];
            if (rawBp.internalConnections != null)
            {
                for (c in (cast(rawBp.internalConnections, Array<Dynamic>)))
                {
                    conns.push({
                        from: { 
                            atomId: Std.string(c.from.atomId), 
                            contactName: Std.string(c.from.contactName) 
                        },
                        to: { 
                            atomId: Std.string(c.to.atomId), 
                            contactName: Std.string(c.to.contactName) 
                        }
                    });
                }
            }
            
            // Parse atom definitions
            var atoms:Array<core.data.AtomDef> = [];
            if (rawBp.internalAtoms != null)
            {
                for (a in (cast(rawBp.internalAtoms, Array<Dynamic>)))
                {
                    atoms.push({
                        instanceId: Std.string(a.instanceId),
                        typeId: Std.string(a.typeId),
                        x: a.x,
                        y: a.y,
                        values: a.values
                    });
                }
            }
            
            // Create blueprint
            var bp = new Blueprint(
                Std.string(rawBp.id),
                Std.string(rawBp.name),
                pins,
                null,
                atoms,
                conns,
                Std.string(rawBp.category)
            );
            
            if (rawBp.deviceType != null)
            {
                bp.deviceType = Std.string(rawBp.deviceType);
            }
            
            bp.isNative = false;
            
            registerBlueprint(bp.id, bp);
            trace("Library loaded: " + bp.id);
            return true;
        }
        catch (e:Dynamic)
        {
            trace("Failed to load atom: " + fullPath + " | Error: " + e);
            return false;
        }
        #else
        return false;
        #end
    }
    
    /**
     * Parse ContactType from dynamic value (String or Int).
     * Handles both JSON string format ("INPUT") and numeric format (0).
     * 
     * @param val Dynamic value from JSON
     * @return Parsed ContactType
     */
    private static function _parseContactType(val:Dynamic):ContactType
    {
        if (Std.isOfType(val, ContactType)) return val;
        
        if (Std.isOfType(val, String))
        {
            switch (Std.string(val))
            {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        if (Std.isOfType(val, Int) || Std.isOfType(val, Float))
        {
            switch (Std.int(val))
            {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        return UNDEFINED;
    }
}