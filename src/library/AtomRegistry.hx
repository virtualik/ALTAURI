// FILE: library/AtomRegistry.hx
package library;
import core.data.Blueprint;
import core.types.ContactType;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     ATOM REGISTRY v3.0                                    ║
* ║          (Icon ID Support + Platform Filtering + Fixed Arguments)         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Central registry for all atom type blueprints.                           ║
* ║  Manages both native (built-in) and custom (user-created) atoms.          ║
* ║                                                                           ║
* ║  Architecture:                                                            ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │   AtomRegistry (Static Singleton)                                   │  ║
* ║  │                                                                     │  ║
* ║  │   ┌─────────────────────────────────────────────────────────────┐   │  ║
* ║  │   │  _blueprints:Map<String, Blueprint>                         │   │  ║
* ║  │   │                                                             │   │  ║
* ║  │   │  Native Atoms (registered in initialize()):                 │   │  ║
* ║  │   │  - Button, LED, Toggle, TextInput, Relay                    │   │  ║
* ║  │   │  - SignalGenerator, MiniAudioAtom, SystemVUMeterAtom        │   │  ║
* ║  │   │  - ComPortAtom, Oscilloscope                                │   │  ║
* ║  │   └─────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │   Public API:                                                       │  ║
* ║  │   - initialize()      → Register all native atoms                   │  ║
* ║  │   - get(id)           → Retrieve blueprint by ID                    │  ║
* ║  │   - getAllIds()       → Get list of all registered atom types       │  ║
* ║  │   - getFilteredIds()  → Get IDs filtered by current platform (v3.0) │  ║
* ║  │   - registerBlueprint → Add custom blueprint                        │  ║
* ║  │   - remove(id)        → Remove blueprint (for deletion)             │  ║
* ║  │   - scanFolder(path)  → Load all .atom files from directory         │  ║
* ║  │   - loadAtomFile(path)→ Parse and register single .atom file        │  ║
* ║  │   - getCurrentPlatform() → Get current target platform string       │  ║
* ║  │   - isAvailableForPlatform(bp) → Check if blueprint is available    │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ║  v3.0 Changes:                                                            ║
* ║  - Added platform filtering support                                       ║
* ║  - Added getCurrentPlatform() to detect current target                    ║
* ║  - Added getFilteredIds() to return only platform-compatible atoms        ║
* ║  - Added isAvailableForPlatform() helper                                  ║
* ║                                                                           ║
* ║  v2.4 Changes:                                                            ║
* ║  - Added `iconId` parameter to `reg()` function.                          ║
* ║  - Fixed argument shifting in `PassThroughAtom` registration.             ║
* ║  - Explicitly defined all 8 arguments in all `reg()` calls for consistency.║
* ╚═══════════════════════════════════════════════════════════════════════════╝
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
    * @param iconId      Identifier for the icon asset (e.g., "signal_generator")
    * @param platforms   Target platforms (null = all platforms)
    */
    private static function reg(
        id:String,
        name:String,
        pins:Array<core.data.Blueprint.PinDef>,
        ?logic:Dynamic = null,
        ?deviceType:String = null,
        ?isNative:Bool = true,
        ?isActive:Bool = false,
        ?iconId:String = null,
        ?platforms:Array<String> = null
    ):Void
    {
        var bp = new Blueprint(id, name, pins, null, null, null, null, platforms);
        bp.deviceType = deviceType;
        bp.isNative = isNative;
        bp.isActive = isActive;
        bp.iconId = iconId;
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

    // =========================================================================
    // v3.0: PLATFORM FILTERING API
    // =========================================================================
    /**
    * v3.0: Get current target platform string.
    *
    * Uses Haxe conditional compilation to detect the current target.
    * Returns:
    *   - "html5" for HTML5 target (browser)
    *   - "cpp" for C++ target (Windows/Linux native)
    *   - "unknown" if platform cannot be determined
    *
    * @return Current platform identifier
    */
    public static function getCurrentPlatform():String
    {
        #if html5
        return "html5";
        #elseif cpp
        return "cpp";
        #else
        return "unknown";
        #end
    }

    /**
    * v3.0: Check if a blueprint is available for a specific platform.
    *
    * A blueprint is available if:
    *   - platforms is null (available on all platforms)
    *   - platforms is empty array (available on all platforms)
    *   - platforms contains the target platform
    *
    * @param bp       Blueprint to check
    * @param platform Target platform string
    * @return true if blueprint is available for the platform
    */
    public static function isAvailableForPlatform(bp:Blueprint, platform:String):Bool
    {
        if (bp.platforms == null || bp.platforms.length == 0)
        {
            return true; // Available on all platforms
        }
        return bp.platforms.indexOf(platform) != -1;
    }

    /**
    * v3.0: Get atom type IDs filtered by current platform.
    *
    * Returns only blueprints that are available for the current target platform.
    * Blueprints with null/empty platforms array are considered available on all platforms.
    *
    * @return Array of blueprint IDs compatible with current platform
    */
    public static function getFilteredIds():Array<String>
    {
        var currentPlatform = getCurrentPlatform();
        var filteredIds:Array<String> = [];
        for (key in _blueprints.keys())
        {
            var bp = _blueprints.get(key);
            if (bp != null && isAvailableForPlatform(bp, currentPlatform))
            {
                filteredIds.push(key);
            }
        }
        return filteredIds;
    }

    /**
    * v3.0: Check if a blueprint is available for the current platform.
    *
    * Convenience method that combines getCurrentPlatform() and isAvailableForPlatform().
    *
    * @param bp Blueprint to check
    * @return true if blueprint is available for current platform
    */
    public static function isAvailableForCurrentPlatform(bp:Blueprint):Bool
    {
        return isAvailableForPlatform(bp, getCurrentPlatform());
    }
    // =========================================================================

    /**
    * Initialize the registry with all native (built-in) atoms.
    * Called once at application startup.
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
        ], null, "button", true, false, "button");

        reg("LED", "LED Indicator", [
            {name: "in", type: INPUT, dataType: "bool"}
        ], null, "led", true, false, "led");

        reg("Toggle", "Toggle Switch", [
            {name: "out", type: OUTPUT, dataType: "bool"}
        ], null, "toggle", true, false, "toggle");

        reg("TextInput", "Text Input", [
            {name: "set", type: INPUT, dataType: "string"},
            {name: "out", type: OUTPUT, dataType: "string"}
        ], null, "textinput", true, false, "textinput");

        reg("Relay", "Relay", [
            {name: "signal", type: INPUT, dataType: "any"},
            {name: "control", type: INPUT, dataType: "bool"},
            {name: "out", type: OUTPUT, dataType: "any"}
        ], null, "relay", true, false, "relay");

        reg("TextArea", "Text Area", [
            {name: "textIn",       type: INPUT,  dataType: "string", priority: CRITICAL, label: "TextIn"},
            {name: "append",     type: INPUT,  dataType: "string", priority: IMPORTANT, label: "Append"},
            {name: "clear",      type: INPUT,  dataType: "bool",   priority: OPTIONAL, label: "Clear"},
            {name: "editable",   type: INPUT,  defaultValue: true, dataType: "bool",   priority: IMPORTANT, label: "Editable", visibleInEditor: true},
            {name: "wordWrap",   type: INPUT,  defaultValue: true, dataType: "bool",   priority: OPTIONAL, label: "WordWrap", visibleInEditor: true},
            {name: "autoScroll", type: INPUT,  defaultValue: true, dataType: "bool",   priority: OPTIONAL, label: "AutoScroll", visibleInEditor: true},
            {name: "hScroll",    type: INPUT,  defaultValue: false,dataType: "bool",   priority: OPTIONAL, label: "HScroll", visibleInEditor: true},
            {name: "vScroll",    type: INPUT,  defaultValue: true, dataType: "bool",   priority: OPTIONAL, label: "VScroll", visibleInEditor: true},
            {name: "maxChars",   type: INPUT,  defaultValue: 40,   dataType: "int",    priority: IMPORTANT, label: "Width", visibleInEditor: true},
            {name: "numLines",   type: INPUT,  defaultValue: 8,    dataType: "int",    priority: IMPORTANT, label: "Lines", visibleInEditor: true},
            {name: "textOut",    type: OUTPUT, dataType: "bool",   priority: CRITICAL, label: "TextOut"},
            {name: "changed",    type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
            {name: "lineCount",  type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "Lines"},
            {name: "cursorLine", type: OUTPUT, dataType: "int",    priority: OPTIONAL, label: "Cursor"}
        ], null, "textarea", true, false, "textarea");

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
        ], null, "panel", true, true, "signal_generator");

        reg("BufferingAtom", "Audio Buffer", [
            {name: "bufferSize", type: INPUT, defaultValue: 512, dataType: "int",
             priority: IMPORTANT, label: "Size", visibleInEditor: true},
            {name: "quantum", type: INPUT, defaultValue: 0.1, dataType: "float",
             priority: OPTIONAL, visibleInEditor: false},
            {name: "mode", type: INPUT, defaultValue: 0, dataType: "int",
             priority: IMPORTANT, label: "Mode", visibleInEditor: true},
            {name: "in", type: INPUT, dataType: "float", priority: CRITICAL},
            {name: "buffer", type: OUTPUT, dataType: "array", priority: CRITICAL},
            {name: "changed", type: OUTPUT, dataType: "bool", priority: OPTIONAL},
            {name: "count", type: OUTPUT, dataType: "int", priority: IMPORTANT, label: "Count"},
            {name: "full", type: OUTPUT, dataType: "bool", priority: IMPORTANT, label: "Full"}
        ], null, "buffer", true, true, "buffering");

        // =========================================================================
        // CROSS-PLATFORM DRIVERS (C++ and HTML5)
        // =========================================================================
        // ComPortAtom is now registered for BOTH platforms, as it has dual implementation.
        reg("ComPortAtom", "Com Port", [
            {name: "portName",  type: INPUT,  defaultValue: "COM13", dataType: "string", priority: IMPORTANT, label: "Port"},
            {name: "baudRate",  type: INPUT,  defaultValue: 9600,   dataType: "int",    priority: IMPORTANT, label: "Baud"},
            {name: "bufferSize",type: INPUT,  defaultValue: 4096,   dataType: "int",    priority: OPTIONAL,  label: "BufSize"},
            {name: "chunkSize", type: INPUT,  defaultValue: 256,    dataType: "int",    priority: OPTIONAL,  label: "Chunk"},
            {name: "enabled",   type: INPUT,  defaultValue: true,   dataType: "bool",   priority: OPTIONAL,  label: "Enabled"},
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
        ], null, "comport", true, true, "comport", ["cpp", "html5"]);


		// =========================================================================
		// FILE WRITER — File System Access API
		// =========================================================================
		reg("FileWriterAtom", "File Writer", [
			{name: "open",      type: INPUT,  dataType: "bool",   priority: CRITICAL,  label: "Open"},
			{name: "close",     type: INPUT,  dataType: "bool",   priority: CRITICAL,  label: "Close"},
			{name: "write",     type: INPUT,  dataType: "string", priority: IMPORTANT, label: "Write"},
			{name: "append",    type: INPUT,  dataType: "string", priority: IMPORTANT, label: "Append"},
			{name: "clear",     type: INPUT,  dataType: "bool",   priority: OPTIONAL,  label: "Clear"},
			{name: "flush",     type: INPUT,  dataType: "bool",   priority: OPTIONAL,  label: "Flush"},
			{name: "enabled",   type: INPUT,  defaultValue: true, dataType: "bool",   priority: OPTIONAL,  label: "Enabled"},
			{name: "mode",      type: INPUT,  defaultValue: 1,    dataType: "int",    priority: IMPORTANT, label: "Mode"},
			{name: "fileName",  type: INPUT,  defaultValue: "output.txt", dataType: "string", priority: OPTIONAL, label: "File Name"},
			{name: "isOpen",    type: OUTPUT, dataType: "bool",   priority: CRITICAL},
			{name: "written",   type: OUTPUT, dataType: "bool",   priority: IMPORTANT, label: "Written"},
			{name: "writeCount",type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "Writes"},
			{name: "fileSize",  type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "Size"},
			{name: "error",     type: OUTPUT, dataType: "string", priority: IMPORTANT, label: "Error"},
			{name: "errorTick", type: OUTPUT, dataType: "bool",   priority: INTERNAL}
		], null, "filewriter", true, true, "filewriter");
		
        
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
        ], null, "miniaudio", true, true, "miniaudio", ["cpp"]);

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
        ], null, "vumeter", true, true, "vumeter", ["cpp"]);

		// ─────────────────────────────────────────────────────────────────
		// WEBSOCKET — cross-platform (HTML5 + Windows cpp; stubs on (Linux & Android not exist now)
		// Linux/Android pending libwebsockets integration).
		// Registered for BOTH platforms — Haxe #if inside the atom class
		// decides what backend to use. The "cpp" platform here includes
		// Windows / Linux / Android; Linux/Android will produce a clean
		// error on connect until libwebsockets is wired up.
		// ─────────────────────────────────────────────────────────────────
		reg("WebSocketAtom", "WebSocket", [
			// ── INPUTS ──
			{name: "url",                   type: INPUT,  defaultValue: "ws://localhost:8080", dataType: "string", priority: IMPORTANT, label: "URL",      visibleInEditor: true},
			{name: "subprotocol",           type: INPUT,  defaultValue: "",                    dataType: "string", priority: OPTIONAL,  label: "Subproto", visibleInEditor: false},
			{name: "binaryMode",            type: INPUT,  defaultValue: false,                 dataType: "bool",   priority: OPTIONAL,  label: "Binary",   visibleInEditor: false},
			{name: "connect",               type: INPUT,  dataType: "bool",   priority: CRITICAL},
			{name: "disconnect",            type: INPUT,  dataType: "bool",   priority: CRITICAL},
			{name: "send",                  type: INPUT,  dataType: "bool",   priority: CRITICAL},
			{name: "sendData",              type: INPUT,  dataType: "string", priority: IMPORTANT, label: "Data"},
			// ── AUTO-RECONNECT INPUTS ──
			{name: "autoReconnect",         type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL, label: "AutoRC",  visibleInEditor: false},
			{name: "reconnectInterval",     type: INPUT,  defaultValue: 1.0,    dataType: "float",  priority: OPTIONAL, label: "RC Int",  visibleInEditor: false},
			{name: "maxReconnectAttempts",  type: INPUT,  defaultValue: 0,      dataType: "int",    priority: OPTIONAL, label: "RC Max",  visibleInEditor: false},
			// ── OUTPUTS ──
			{name: "isConnected",           type: OUTPUT, dataType: "bool",   priority: CRITICAL,  label: "Connected"},
			{name: "receivedData",          type: OUTPUT, dataType: "string", priority: IMPORTANT, label: "RX"},
			{name: "receivedTick",          type: OUTPUT, dataType: "bool",   priority: INTERNAL},
			{name: "sentTick",              type: OUTPUT, dataType: "bool",   priority: INTERNAL},
			{name: "error",                 type: OUTPUT, dataType: "string", priority: IMPORTANT, label: "Error"},
			{name: "errorTick",             type: OUTPUT, dataType: "bool",   priority: INTERNAL},
			{name: "closeCode",             type: OUTPUT, dataType: "int",    priority: OPTIONAL,  label: "CloseCode"},
			{name: "bytesReceived",         type: OUTPUT, dataType: "int",    priority: OPTIONAL,  label: "RX bytes"},
			{name: "bytesSent",             type: OUTPUT, dataType: "int",    priority: OPTIONAL,  label: "TX bytes"},
			// ── AUTO-RECONNECT OUTPUT ──
			{name: "reconnectAttempts",     type: OUTPUT, dataType: "int",    priority: OPTIONAL,  label: "RC Tries"}
		], null, "websocket", true, true, "websocket", ["cpp", "html5"]);


        reg("NETRadioPlayerAtom", "NET Radio Player", [
            {name: "stream_url",    type: INPUT,  dataType: "string",  priority: IMPORTANT, label: "URL"},
            {name: "poll_interval", type: INPUT,  defaultValue: 5.0,   dataType: "float",   priority: OPTIONAL, label: "Poll (s)"},
            {name: "playCtrl",      type: INPUT,  defaultValue: false,  dataType: "bool",    priority: CRITICAL, label: "Play"},
            {name: "volume",        type: INPUT,  defaultValue: 1.0,   dataType: "float",   priority: IMPORTANT, label: "Volume"},
            {name: "title",         type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Title"},
            {name: "artist",        type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Artist"},
            {name: "track",         type: OUTPUT, dataType: "string",  priority: IMPORTANT, label: "Track"},
            {name: "raw_metadata",  type: OUTPUT, dataType: "string",  priority: INTERNAL},
            {name: "updated",       type: OUTPUT, dataType: "bool",    priority: OPTIONAL},
            {name: "state",         type: OUTPUT, dataType: "bool",    priority: OPTIONAL, label: "Error"},
            {name: "error",         type: OUTPUT, dataType: "string",  priority: OPTIONAL, label: "Error Msg"}
        ], null, "netradio", true, true, "netradio", ["cpp"]);

        reg("URLAudioStreamPlayer", "URL Audio Player", [
            {name: "url", type: INPUT, dataType: "string", priority: CRITICAL, visibleInEditor: true, label: "URL"},
            {name: "play", type: INPUT, dataType: "bool", priority: CRITICAL, visibleInEditor: true, label: "Play"},
            {name: "volume", type: INPUT, dataType: "float", defaultValue: 1.0, priority: OPTIONAL, visibleInEditor: true, label: "Vol"},
            {name: "isPlaying", type: OUTPUT, dataType: "bool", priority: CRITICAL, label: "Playing"},
            {name: "isBuffering", type: OUTPUT, dataType: "bool", priority: IMPORTANT, label: "Buffering"},
            {name: "error", type: OUTPUT, dataType: "string", priority: IMPORTANT, label: "Error"},
            {name: "state", type: OUTPUT, dataType: "int", priority: OPTIONAL, label: "State"}
        ], null, "urlplayer", true, true, "urlplayer", ["cpp"]);

        // =================================================================
        // LOGIC & PASSIVE
        // =================================================================
        // !!! FIX: Аргументы были сдвинуты. Добавлен `null` для `logic` и `iconId` в конец.
        reg("PassThrough", "Pass Through", [
            {name: "in",      type: INPUT,  dataType: "any",   priority: CRITICAL},
            {name: "out",     type: OUTPUT, dataType: "any",   priority: CRITICAL},
            {name: "changed", type: OUTPUT, dataType: "bool",  priority: OPTIONAL}
        ], null, "wire", true, false, "passthrough");

        reg("Oscilloscope", "Oscilloscope", [
            {name: "in", type: INPUT, dataType: "array", priority: INTERNAL, visibleInEditor: false}
        ], null, "oscilloscope", true, false, "oscilloscope");

        reg("FFTAtom", "FFT Spectrum", [
            {name: "buffer", type: INPUT, dataType: "array", priority: INTERNAL, visibleInEditor: false},
            {name: "windowSize", type: INPUT, defaultValue: 512, dataType: "int", priority: IMPORTANT, label: "Size"},
            {name: "windowType", type: INPUT, defaultValue: 1, dataType: "int", priority: OPTIONAL, label: "Window"},
            {name: "sampleRate", type: INPUT, defaultValue: 48000, dataType: "int", priority: OPTIONAL, label: "Rate"},
            {name: "spectrum", type: OUTPUT, dataType: "array", priority: CRITICAL},
            {name: "spectrumDB", type: OUTPUT, dataType: "array", priority: CRITICAL},
            {name: "peak", type: OUTPUT, dataType: "float", priority: IMPORTANT, label: "Peak Hz"},
            {name: "peakAmp", type: OUTPUT, dataType: "float", priority: OPTIONAL},
            {name: "bass", type: OUTPUT, dataType: "float", priority: IMPORTANT, label: "Bass"},
            {name: "mid", type: OUTPUT, dataType: "float", priority: IMPORTANT, label: "Mid"},
            {name: "treble", type: OUTPUT, dataType: "float", priority: IMPORTANT, label: "Treble"},
            {name: "changed", type: OUTPUT, dataType: "bool", priority: OPTIONAL}
        ], null, "fft", true, true, "fft");

        _initialized = true;
    }

    /**
    * Retrieve a blueprint by its unique ID.
    */
    public static function get(id:String):Blueprint
    {
        return _blueprints.get(id);
    }

    /**
    * Register a custom blueprint (typically loaded from .atom file).
    */
    public static function registerBlueprint(id:String, bp:Blueprint):Void
    {
        _blueprints.set(id, bp);
    }

    /**
    * Remove a blueprint from the registry.
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
    */
    public static function exists(id:String):Bool
    {
        return _blueprints.exists(id);
    }

    /**
    * Scan a directory for .atom files and register them.
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
                        var extName:String = null;
                        if (p.externalName != null)
                        {
                            extName = Std.string(p.externalName);
                            if (extName == "null") extName = null;
                        }
                        pins.push({
                            name: pinName,
                            type: _parseContactType(p.type),
                            defaultValue: p.defaultValue,
                            dataType: Std.string(p.dataType),
                            externalName: extName
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

            // v3.0: Parse platforms array
            var platforms:Array<String> = null;
            if (rawBp.platforms != null)
            {
                platforms = [];
                for (p in cast(rawBp.platforms, Array<Dynamic>))
                {
                    platforms.push(Std.string(p));
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
                Std.string(rawBp.category),
                platforms
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
