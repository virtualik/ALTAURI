package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;

/**
 *  * DATA STORAGE ATOM v1.0 (Stage 4a-2, Task 145)
 * ============================================================================
 *  * THE STORAGE ATOM: it ingests data portions arriving on the [data] input
 *  * FROM THE GRAPH (the author decision, Task 143), keeps them in a single canonical
 *  * buffer (haxe.io.Bytes) and issues them on the [read] command - non-destructively (ROM).
 * Spec: SPEC_STAGE4A_DATASTORAGE.md.
 *
 * Architecture: "Atom is Databank & Compute Core"
 *  *   data portions (String|Bytes|Cargo) -> the bank -> status always, the body on [read]
 *
 *  * SEMANTICS (see SPEC §2):
 *  *   - enabled - an INLET GATE, default FALSE (the author decision: "the pocket is
 *  *     buttoned up by default"). It mutes ONLY the intake; [clear] and [read] stay alive.
 *  *   - data - a single portion. A bare value is interpreted by the [isBytes] contact
 *  *     (false = text, true = bytes - the author switch, the "mode" idiom of
 *  *     FileWriter); Cargo unpacks itself (kind inside, fileName as a gift).
 *  *     Replacement: a NEW portion REPLACES the old one (append - a future era).
 *  *   - clear - the buffer back to empty (kind=empty, size=0, storeCount=0 - a mirror
 *  *     of FileWriter.clearFile: clearing resets the counters too).
 *  *   - read - issue the body: text (UTF-8, kind=text only) + bytes (a copy -
 *  *     the consumer cannot spoil the bank) + readTick. Non-destructively.
 *  *   - In-frame order: enabled -> clear -> data -> read (wipe first,
 *  *     then accept, then issue).
 *
 *  * WHAT STORAGE DOES NOT DO (important): it does NOT touch the disk, does NOT call dialogs, knows NO
 *  * paths - not a single platform-dependent branch, the cleanest atom of the family.
 *  * All input arrives over wires; FileReader v1.0 already feeds it text.
 *
 *  * PERSISTENCE (the [P] Export tail - the author decision, Task 143): the first
 *  * persisting atom of the file triple. getPersistentState -> {enabled, kind,
 * size, storeCount, fileName, data:base64} → atomDef.values → blueprint JSON
 *  * -> the tail over the EXISTING rails of Stages 1-3 (the exporter was not changed at all).
 *  * P4 hygiene: over maxTailPayload (8 MB) only the metadata +
 *  * truncated:true ride into the tail - a bottomless pocket is dangerous (the lesson of TextArea v1.3
 *  * "Memory exhausted"); the data lives in the runtime until a restart.
 * ============================================================================
 */
class DataStorageAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;

    /** Kind: the bank is empty. */
    private static inline var KIND_EMPTY:String = "empty";
    /** Kind: the content is treated as UTF-8 text. */
    private static inline var KIND_TEXT:String = "text";
    /** Kind: the content is bytes (opaque binary). */
    private static inline var KIND_BINARY:String = "binary";

    /**
     * The [P] tail CAP in RAW bytes (~1.37x in base64). A public static -
     * controlled from tests and future settings; over it - state.truncated=true.
     */
    public static var maxTailPayload:Int = 8 * 1024 * 1024;

    // STATE (DATABANK) - a single canonical buffer
    private var _buffer:Bytes = null;        // null = the bank is empty
    private var _kind:String = KIND_EMPTY;   // empty | text | binary
    private var _fileName:String = "";       // from Cargo (if there was one); "" for bare portions
    private var _storeCount:Int = 0;         // the number of accepted portions (reset by clear)
    private var _enabled:Bool = false;       // the intake gate; DEFAULT FALSE (the author)
    private var _lastError:String = "";

    // PULSE TIMERS
    private var _storedTickTimer:Float = 0.0;
    private var _readTickTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [   // INPUTS
                new Contact(false, INPUT, "enabled"),
                new Contact(null, INPUT, "data"),
                new Contact(false, INPUT, "isBytes"),
                new Contact(false, INPUT, "clear"),
                new Contact(false, INPUT, "read")
            ],
            [   // OUTPUTS
                new Contact(false, OUTPUT, "hasData"),
                new Contact(KIND_EMPTY, OUTPUT, "kind"),
                new Contact("", OUTPUT, "text"),
                new Contact(null, OUTPUT, "bytes"),
                new Contact("", OUTPUT, "fileName"),
                new Contact(0, OUTPUT, "size"),
                new Contact(0, OUTPUT, "storeCount"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "storedTick"),
                new Contact(false, OUTPUT, "readTick"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "DataStorageAtom",
            true
        );
        init();
    }

    override public function init():Void
    {
        trace('DataStorageAtom: Initialized (Main Thread)');

        // Register the atom so DriverManager calls update(dt) and readInputs()
        DriverManager.getInstance().register(this);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        readInputs();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        _buffer = null;
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // - Portion intake ----------------------------------------------------------

    /**
     * Accept a portion into the bank. Three input languages:
     *  1. Cargo - a self-contained parcel: kind inside, fileName as a gift,
     *     [isBytes] is ignored;
     *  2. bare Bytes - interpreted by [isBytes] (the flag says WHAT these bytes are);
     *  3. a bare String (and the rest via Std.string) - by [isBytes];
     *     a string in byte mode is honestly converted to UTF-8 bytes.
     * Empty portions ("" / 0 bytes) are wire noise, silently ignored.
     */
    private function storePortion(portion:Dynamic):Void
    {
        if (Cargo.isCargo(portion))
        {
            var c:Cargo = cast portion;
            if (c.data == null || c.size == 0)
            {
                setError('empty cargo rejected: ${c}');
                return;
            }
            if (c.kind == Cargo.KIND_BYTES)
            {
                _buffer = cast c.data;                 // a reference (P3: no copies on the way)
                _kind = KIND_BINARY;
            }
            else
            {
                _buffer = Bytes.ofString(Std.string(c.data)); // fresh UTF-8 bytes
                _kind = KIND_TEXT;
            }
            _fileName = c.fileName;
            acceptPortion();
            return;
        }

        var isBytesC = getInput("isBytes");
        var asBytes:Bool = (isBytesC != null && isBytesC.value == true);

        if (Std.isOfType(portion, Bytes))
        {
            _buffer = cast portion;                    // a reference (P3)
            _kind = asBytes ? KIND_BINARY : KIND_TEXT; // the flag INTERPRETS the bytes (the author)
        }
        else if (Std.isOfType(portion, String))
        {
            if (asBytes)
            {
                // Tolerant conversion: a string in byte mode -> UTF-8 bytes
                trace('DataStorageAtom: String portion in bytes mode — converting to UTF-8 bytes');
            }
            _buffer = Bytes.ofString(cast portion);
            _kind = asBytes ? KIND_BINARY : KIND_TEXT;
        }
        else
        {
            // Tolerance: numbers/etc - a string representation as text
            var s:String = Std.string(portion);
            if (s == "") return;
            trace('DataStorageAtom: non-string portion (${portion}) — stored as text');
            _buffer = Bytes.ofString(s);
            _kind = KIND_TEXT;
        }

        _fileName = ""; // a bare portion carries no name
        acceptPortion();
    }

    /** Finalize the intake: the counter, the status wave, the impulse. */
    private function acceptPortion():Void
    {
        _storeCount++;
        pushStatus(false);
        pulseStored();
        trace('DataStorageAtom: stored ${_buffer.length} bytes (kind=$_kind, stores=$_storeCount)');
    }

    // - Issue and clear ------------------------------------------------------

    /** Issue the bank content: text (UTF-8, kind=text only) + bytes (a copy). */
    private function emitContents():Void
    {
        if (_buffer == null || _buffer.length == 0)
        {
            setError("storage is empty — nothing to read");
            return;
        }

        var textOut = getOutput("text");
        if (textOut != null)
        {
            var s:String = (_kind == KIND_TEXT) ? _buffer.getString(0, _buffer.length) : "";
            textOut.setValueSilent(s);
            textOut.propagateCurrentValue();
        }

        var bytesOut = getOutput("bytes");
        if (bytesOut != null)
        {
            // P3: a copy on issue - the consumer cannot spoil the bank, and a repeated
            // issue of the same body will not be swallowed by the reference dedup.
            // (a copy - sub(0, length): haxe.io.Bytes in 4.3 has no copy())
            bytesOut.setValueSilent(_buffer.sub(0, _buffer.length));
            bytesOut.propagateCurrentValue();
        }

        pulseRead();
    }

    /** Empty the buffer. A mirror of FileWriter.clearFile: the counters are reset too. */
    private function clearBuffer():Void
    {
        if (_buffer == null) return; // already empty - silence

        _buffer = null;
        _kind = KIND_EMPTY;
        _fileName = "";
        _storeCount = 0;

        var textOut = getOutput("text");
        if (textOut != null) { textOut.setValueSilent(""); textOut.propagateCurrentValue(); }
        var bytesOut = getOutput("bytes");
        if (bytesOut != null) { bytesOut.setValueSilent(Bytes.alloc(0)); bytesOut.propagateCurrentValue(); }

        pushStatus(false);
        trace('DataStorageAtom: buffer cleared');
    }

    // - Input processing (every frame) --------------------------------------

    private function readInputs():Void
    {
        if (_isDisposed) return;

        // 1. enabled - the intake gate (mutes ONLY the intake)
        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null)
        {
            _enabled = (enabledC.value == true);
        }

        // 2. clear - alive even with the gate closed
        var clearC = getInput("clear");
        if (clearC != null && clearC.value == true)
        {
            clearC.value = false;
            clearBuffer();
        }

        // 3. data - portion intake (gated by enabled)
        var dataC = getInput("data");
        if (dataC != null && dataC.value != null)
        {
            var portion:Dynamic = dataC.value;
            var noise:Bool = (portion == null)
                || (Std.isOfType(portion, String) && portion == "")
                || (Std.isOfType(portion, Bytes) && portion.length == 0);
            if (!noise)
            {
                // The P1 idiom "accepted - clear": mute BEFORE processing so
                // the next frame does not accept the portion twice (the lesson of FileWriter.write)
                dataC.setValueSilent(null);
                if (_enabled)
                {
                    storePortion(portion);
                }
                else
                {
                    trace('DataStorageAtom: gate closed — portion passed by');
                }
            }
        }

        // 4. read - alive even with the gate closed; in the frame AFTER the intake
        var readC = getInput("read");
        if (readC != null && readC.value == true)
        {
            readC.value = false;
            emitContents();
        }
    }

    // - Status outputs -------------------------------------------------------

    /**
     * Spread the status: hasData/kind/size/storeCount/fileName.
     * silent=true - a restore: the wires are not linked yet, link() will
     * spread the values itself when built (the Load-Symmetric Reconstruction discipline).
     */
    private function pushStatus(silent:Bool):Void
    {
        var has:Bool = (_buffer != null && _buffer.length > 0);
        setOut("hasData", has, silent);
        setOut("kind", _kind, silent);
        setOut("size", has ? _buffer.length : 0, silent);
        setOut("storeCount", _storeCount, silent);
        setOut("fileName", _fileName, silent);
    }

    private function setOut(name:String, value:Dynamic, silent:Bool):Void
    {
        var c = getOutput(name);
        if (c == null) return;
        c.setValueSilent(value);
        if (!silent) c.propagateCurrentValue();
    }

    private function setError(msg:String):Void
    {
        if (_isDisposed) return;
        _lastError = msg;
        var errorOut = getOutput("error");
        if (errorOut != null)
        {
            errorOut.setValueSilent(msg);
            errorOut.propagateCurrentValue();
        }
        var errorTickOut = getOutput("errorTick");
        if (errorTickOut != null)
        {
            errorTickOut.value = true;
            _errorTimer = PULSE_DURATION;
        }
        trace('DataStorageAtom ERROR: $msg');
    }

    private function pulseStored():Void
    {
        if (_isDisposed) return;
        var c = getOutput("storedTick");
        if (c != null)
        {
            c.value = true;
            _storedTickTimer = PULSE_DURATION;
        }
    }

    private function pulseRead():Void
    {
        if (_isDisposed) return;
        var c = getOutput("readTick");
        if (c != null)
        {
            c.value = true;
            _readTickTimer = PULSE_DURATION;
        }
    }

    private function updatePulseTimers(dt:Float):Void
    {
        if (_isDisposed) return;

        if (_storedTickTimer > 0)
        {
            _storedTickTimer -= dt;
            if (_storedTickTimer <= 0)
            {
                var c = getOutput("storedTick");
                if (c != null) c.value = false;
            }
        }
        if (_readTickTimer > 0)
        {
            _readTickTimer -= dt;
            if (_readTickTimer <= 0)
            {
                var c = getOutput("readTick");
                if (c != null) c.value = false;
            }
        }
        if (_errorTimer > 0)
        {
            _errorTimer -= dt;
            if (_errorTimer <= 0)
            {
                var c = getOutput("errorTick");
                if (c != null) c.value = false;
            }
        }
    }

    // - PERSISTENCE (the [P] tail; the Atom.hx:375 seam) ----------------------

    /**
     * Saving the state into the values-JSON of the schematic -> the instrument tail.
     * All fields are JSON-safe (bool/int/string); data is a base64 string.
     * Over maxTailPayload - only metadata + truncated:true (P4 hygiene).
     */
    override public function getPersistentState():Dynamic
    {
        var state:Dynamic = super.getPersistentState();
        if (state == null) state = {};

        state.enabled = _enabled;
        state.storeCount = _storeCount;
        state.kind = _kind;
        state.size = (_buffer != null) ? _buffer.length : 0;
        state.fileName = _fileName;

        if (_buffer != null && _buffer.length > 0)
        {
            if (_buffer.length <= maxTailPayload)
            {
                state.data = haxe.crypto.Base64.encode(_buffer);
            }
            else
            {
                state.truncated = true;
            }
        }
        return state;
    }

    /**
     * Restore from the values-JSON (tolerant): no field - the bank is empty;
     * broken base64 - the bank is empty + an honest error, the instrument does NOT crash.
     * The status is spread QUIETLY (silent) - the wires will be built later.
     */
    override public function restoreState(state:Dynamic):Void
    {
        super.restoreState(state);
        if (state == null) return;

        if (Reflect.hasField(state, "enabled")) _enabled = (state.enabled == true);
        if (Reflect.hasField(state, "storeCount")) _storeCount = Std.int(state.storeCount);
        _fileName = Reflect.hasField(state, "fileName") ? Std.string(state.fileName) : "";

        _buffer = null;
        _kind = KIND_EMPTY;

        if (Reflect.hasField(state, "data"))
        {
            try
            {
                var b:Bytes = haxe.crypto.Base64.decode(Std.string(state.data));
                if (b.length > 0)
                {
                    _buffer = b;
                    var k:String = Std.string(state.kind);
                    _kind = (k == KIND_TEXT || k == KIND_BINARY) ? k : KIND_BINARY;
                }
            }
            catch (e:Dynamic)
            {
                _buffer = null;
                _kind = KIND_EMPTY;
                setError('restore failed: corrupt base64 payload');
            }
        }
        else if (Reflect.hasField(state, "truncated"))
        {
            setError('payload was truncated on export — data not restored');
        }

        pushStatus(true);
        trace('DataStorageAtom: state restored (kind=$_kind, size=${_buffer != null ? _buffer.length : 0})');
    }

    // - Public access (the family mirror) ------------------------------------
    public function hasData():Bool return (_buffer != null && _buffer.length > 0);
    public function getStoreCount():Int return _storeCount;
    public function getKind():String return _kind;
    public function getFileName():String return _fileName;
    public function isEnabled():Bool return _enabled;
    /** A copy of the bank body (for future consumers like PictureAtom); null if empty. */
    public function getBufferCopy():Bytes return (_buffer != null) ? _buffer.sub(0, _buffer.length) : null;
}
