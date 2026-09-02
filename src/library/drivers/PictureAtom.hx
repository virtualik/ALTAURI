package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;

/**
 * PICTURE ATOM v1.2 (Stage 4a-3, Task 155; hotfix Task 156; "bare canvas" Task 159)
 * ============================================================================
 * ATOM-PORTRAIT: the visual consumer of the binary pipe. Accepts picture
 * bytes on [image] (Bytes | Cargo{bytes}), validates the image HEADER
 * (magic + dimensions) and holds them for the face (PictureWidget), which
 * performs the real BitmapData decode. Spec: SPEC_STAGE4A_PICTURE.md.
 *
 * Architecture: "Atom is Databank & Compute Core"
 *   image portion → header validation → databank (bytes+kind+dims+version)
 *   transform pins (pos/size/scale/aspect/visible/enabled/alpha/zOrder) →
 *   widget geometry
 *
 * SEMANTICS (see SPEC §2-§4, §13 for the v1.2 bare-canvas rules):
 *   · image — the picture portion. Cargo{bytes} (from FileReader [bytes] /
 *     DataStorage [bytes]) is unpacked by kind; a naked Bytes is sniffed the
 *     same way. Replacement: a NEW valid picture REPLACES the old one; an
 *     INVALID portion keeps the old picture untouched (atomic swap) and
 *     reports an honest error. Consumed after accept (P1 hygiene).
 *   · clear — drop the picture back to the "no image" placeholder.
 *   · posX..zOrder — transform state (the "makeup" channel). Read EVERY
 *     frame from contacts, mirrored into atom state; the widget applies
 *     them: posX/posY place the device CARD, zOrder sets card stacking,
 *     width/height/scale/visible/alpha shape the bitmap itself.
 *   · aspect (v1.2) — "keep aspect ratio": true = a width edit derives
 *     height (natW/natH) and vice versa (last edit wins); false/absent =
 *     width and height apply verbatim. Derived in the WIDGET (it owns the
 *     last-edit event); the atom mirrors the flag for state integrity.
 *   · enabled (v1.2, family name like DataStorage) — the render gate for
 *     the bare Device-panel face: false = the panel image is hidden; the
 *     data bank and outputs keep working (a gate, not a kill switch).
 *   · Header validation is the ATOM's job; the real CODEC decode is the
 *     WIDGET's job. A codec failure latches the v7.2 fault (red frame);
 *     a bad header is a data-level error (error/errorTick channel).
 *
 * WHAT PICTURE DOES NOT DO: it does not touch the disk, does not call
 * dialogs, does not decode pixels, does not import openfl — the purest
 * atom of the data family (DataStorage sibling). All input arrives over
 * wires; the face is a separate class.
 *
 * PERSISTENCE (Stage 4a-3 decision): the image itself is NOT serialized —
 * it is runtime-derived from the graph (Reader/Storage re-feed it after
 * reload; persistent bytes are DataStorage's doctrine). Only non-default
 * transform fields ride in getPersistentState(). Known boundary: after a
 * scheme reload the portrait is empty until the graph sends bytes again.
 * ============================================================================
 */
class PictureAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;

    /** Kind: no picture loaded. */
    private static inline var KIND_NONE:String = "none";
    /** Kind: PNG magic 89 50 4E 47 0D 0A 1A 0A. */
    private static inline var KIND_PNG:String = "png";
    /** Kind: JPEG magic FF D8 FF. */
    private static inline var KIND_JPEG:String = "jpeg";
    /** Kind: BMP magic 42 4D. */
    private static inline var KIND_BMP:String = "bmp";

    /** PNG magic length. */
    private static inline var PNG_HEADER_LEN:Int = 24;
    /** BMP: minimal file length to read BITMAPINFOHEADER dims. */
    private static inline var BMP_HEADER_LEN:Int = 26;
    /** JPEG: safety cap for the SOF marker scan. */
    private static inline var JPEG_SCAN_LIMIT:Int = 4096;

    // STATE (DATABANK) — the picture bank + transform mirror
    private var _imageBytes:Bytes = null;     // null = no picture
    private var _kind:String = KIND_NONE;     // none | png | jpeg | bmp
    private var _natW:Int = 0;                // natural width from header
    private var _natH:Int = 0;                // natural height from header
    private var _imageVersion:Int = 0;        // bumped per picture change
    private var _lastError:String = "";

    // TRANSFORM STATE ("makeup" mirror; canonical values live here)
    private var _posX:Float = 0;
    private var _posY:Float = 0;
    private var _sizeW:Float = 0;             // 0 = natural width
    private var _sizeH:Float = 0;             // 0 = natural height
    private var _scaleX:Float = 1;
    private var _scaleY:Float = 1;
    private var _aspect:Bool = false;         // v1.2: keep aspect ratio
    private var _visible:Bool = true;
    private var _enabled:Bool = true;         // v1.2: device render gate
    private var _alpha:Float = 1;             // clamped 0..1
    private var _zOrder:Int = 0;

    // PULSE TIMERS
    private var _loadedTickTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [   // INPUTS
                new Contact(null, INPUT, "image"),
                new Contact(false, INPUT, "clear"),
                new Contact(0, INPUT, "posX"),
                new Contact(0, INPUT, "posY"),
                new Contact(0, INPUT, "width"),
                new Contact(0, INPUT, "height"),
                new Contact(1, INPUT, "scaleX"),
                new Contact(1, INPUT, "scaleY"),
                new Contact(false, INPUT, "aspect"),
                new Contact(true, INPUT, "visible"),
                new Contact(true, INPUT, "enabled"),
                new Contact(1, INPUT, "alpha"),
                new Contact(0, INPUT, "zOrder")
            ],
            [   // OUTPUTS
                new Contact(false, OUTPUT, "ok"),
                new Contact(KIND_NONE, OUTPUT, "kind"),
                new Contact(0, OUTPUT, "imgWidth"),
                new Contact(0, OUTPUT, "imgHeight"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "loadedTick"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "PictureAtom",
            true
        );
        init();
    }

    override public function init():Void
    {
        trace('PictureAtom: Initialized (Main Thread)');
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
        _imageBytes = null;
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // ── Portion intake ───────────────────────────────────────────────────────

    /**
     * Accept a portion on [image]. Three intake languages (family style):
     *  1. Cargo{bytes} — the pipe portion (FileReader [bytes], Storage
     *     [bytes]): unpacked by kind, atomic swap on success;
     *  2. naked Bytes — sniffed the same way;
     *  3. naked String / Cargo{text} — HONEST ERROR, never a decode attempt:
     *     text pipes mangle binary (the fft.png lesson, Stage 4a-4).
     * Empty portions (0 bytes) are wire noise — ignored silently.
     */
    private function acceptPortion(portion:Dynamic):Void
    {
        if (Cargo.isCargo(portion))
        {
            var c:Cargo = cast portion;
            if (c.kind != Cargo.KIND_BYTES)
            {
                setError('text cargo is not an image — use the [bytes] pipe: ${c}');
                return;
            }
            var body:Bytes = cast c.data;
            if (body == null || body.length == 0)
            {
                setError('empty cargo rejected: ${c}');
                return;
            }
            tryStore(body);
            return;
        }

        if (Std.isOfType(portion, Bytes))
        {
            var b:Bytes = cast portion;
            if (b.length == 0) return; // noise
            tryStore(b);
            return;
        }

        if (Std.isOfType(portion, String))
        {
            setError('String on [image] — pictures travel as Bytes/Cargo{bytes} (fft.png lesson)');
            return;
        }

        setError('unsupported portion type on [image]: ${portion}');
    }

    /**
     * Validate the header and ATOMICALLY swap the bank:
     * on success — store bytes (reference, P3), kind, dims, bump version,
     * push the status wave and pulse loadedTick; on failure — keep the old
     * picture untouched and report the honest error.
     */
    private function tryStore(b:Bytes):Void
    {
        var parsed = sniffHeader(b);
        if (parsed.error != null)
        {
            setError(parsed.error);
            return;
        }

        _imageBytes = b;                     // reference (P3: no copies in flight)
        _kind = parsed.kind;
        _natW = parsed.width;
        _natH = parsed.height;
        _imageVersion++;

        pushStatus(false);
        pulseLoaded();
        trace('PictureAtom: stored ${b.length} bytes (kind=$_kind, ${_natW}x${_natH}, v$_imageVersion)');
    }

    /**
     * Header sniffing — magic bytes decide the kind (file names are not
     * trusted), dimensions come from the structure:
     *   PNG: IHDR (bytes 16..23, big-endian);
     *   JPEG: first SOF marker scan (C0..CF except C4/C8/CC);
     *   BMP: BITMAPINFOHEADER (40+) or BITMAPCOREHEADER (12) dims, LE.
     * Returns {kind, width, height, error}; error != null = rejected.
     */
    private function sniffHeader(b:Bytes):{kind:String, width:Int, height:Int, error:String}
    {
        if (b.length < 4)
        {
            return {kind: KIND_NONE, width: 0, height: 0,
                error: 'truncated image header (${b.length} bytes)'};
        }

        // ── PNG ──
        if (b.get(0) == 0x89 && b.get(1) == 0x50 && b.get(2) == 0x4E
            && b.get(3) == 0x47)
        {
            if (b.length < PNG_HEADER_LEN)
            {
                return {kind: KIND_PNG, width: 0, height: 0,
                    error: 'truncated PNG header (${b.length} < ${PNG_HEADER_LEN} bytes)'};
            }
            var w:Int = be32(b, 16);
            var h:Int = be32(b, 20);
            if (w <= 0 || h <= 0 || w > 0x3FFFFFFF || h > 0x3FFFFFFF)
            {
                return {kind: KIND_PNG, width: 0, height: 0,
                    error: 'bad IHDR dimensions (${w}x${h})'};
            }
            return {kind: KIND_PNG, width: w, height: h, error: null};
        }

        // ── JPEG ──
        if (b.get(0) == 0xFF && b.get(1) == 0xD8 && b.get(2) == 0xFF)
        {
            var dims = jpegDimensions(b);
            // SOF not found: honest unknown (codec decides later), no error.
            return {kind: KIND_JPEG, width: dims.w, height: dims.h, error: null};
        }

        // ── BMP ──
        if (b.get(0) == 0x42 && b.get(1) == 0x4D)
        {
            if (b.length < BMP_HEADER_LEN)
            {
                return {kind: KIND_BMP, width: 0, height: 0,
                    error: 'truncated BMP header (${b.length} bytes)'};
            }
            var headerSize:Int = le32(b, 14);
            var bw:Int = 0;
            var bh:Int = 0;
            if (headerSize == 12)
            {
                bw = (b.get(19) << 8) | b.get(18);
                bh = (b.get(23) << 8) | b.get(22);
            }
            else
            {
                bw = le32(b, 18);
                bh = le32(b, 22);
            }
            if (bw <= 0 || bh <= 0)
            {
                return {kind: KIND_BMP, width: 0, height: 0,
                    error: 'bad BMP dimensions (${bw}x${bh})'};
            }
            return {kind: KIND_BMP, width: bw, height: bh, error: null};
        }

        return {kind: KIND_NONE, width: 0, height: 0,
            error: 'unrecognized image format (magic mismatch)'};
    }

    /** Big-endian 32-bit read (multiplication form avoids Int sign overflow). */
    private static function be32(b:Bytes, pos:Int):Int
    {
        return (b.get(pos) * 16777216) + (b.get(pos + 1) << 16)
            + (b.get(pos + 2) << 8) + b.get(pos + 3);
    }

    /** Little-endian 32-bit read. */
    private static function le32(b:Bytes, pos:Int):Int
    {
        return b.get(pos) + (b.get(pos + 1) << 8)
            + (b.get(pos + 2) << 16) + (b.get(pos + 3) * 16777216);
    }

    /**
     * JPEG dimension scan: walk the marker segments to the first SOF
     * (Start of Frame) marker. Standalone markers (D0-D9, 01) carry no
     * length; everything else advances by its 16-bit length field.
     */
    private function jpegDimensions(b:Bytes):{w:Int, h:Int}
    {
        var i:Int = 2;
        var steps:Int = 0;
        while (i + 4 < b.length && steps < JPEG_SCAN_LIMIT)
        {
            steps++;
            if (b.get(i) != 0xFF)
            {
                return {w: 0, h: 0}; // structure lost — unknown, codec decides
            }
            var marker:Int = b.get(i + 1);
            if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9))
            {
                i += 2;
                continue;
            }
            if (marker >= 0xC0 && marker <= 0xCF
                && marker != 0xC4 && marker != 0xC8 && marker != 0xCC)
            {
                if (i + 9 > b.length) return {w: 0, h: 0};
                var h:Int = (b.get(i + 5) << 8) | b.get(i + 6);
                var w:Int = (b.get(i + 7) << 8) | b.get(i + 8);
                return {w: w, h: h};
            }
            var segLen:Int = (b.get(i + 2) << 8) | b.get(i + 3);
            if (segLen < 2) return {w: 0, h: 0};
            i += 2 + segLen;
        }
        return {w: 0, h: 0};
    }

    // ── Clear ────────────────────────────────────────────────────────────────

    /** Drop the picture: bank empty, version bumped (the face drops the bitmap). */
    private function clearPicture():Void
    {
        if (_imageBytes == null) return; // already empty — silence

        _imageBytes = null;
        _kind = KIND_NONE;
        _natW = 0;
        _natH = 0;
        _imageVersion++;

        pushStatus(false);
        trace('PictureAtom: picture cleared (v$_imageVersion)');
    }

    // ── Per-frame input processing ───────────────────────────────────────────

    private function readInputs():Void
    {
        if (_isDisposed) return;

        // 1. clear — lives outside any gate (family style)
        var clearC = getInput("clear");
        if (clearC != null && clearC.value == true)
        {
            clearC.value = false;
            clearPicture();
        }

        // 2. image — the portion (consumed on sight, P1)
        var imageC = getInput("image");
        if (imageC != null && imageC.value != null)
        {
            var portion:Dynamic = imageC.value;
            // Wire noise: null and BARE empty bytes are silent; an EMPTY
            // CARGO is NOT noise — it gets the honest family error below.
            var noise:Bool = (portion == null)
                || (Std.isOfType(portion, Bytes) && portion.length == 0);
            if (!noise)
            {
                // P1 "accept — clear the input": consumed BEFORE processing
                imageC.setValueSilent(null);
                acceptPortion(portion);
            }
        }

        // 3. transforms — mirrored every frame (tolerant, guards below)
        _posX = readFloat(getInput("posX"), _posX);
        _posY = readFloat(getInput("posY"), _posY);
        _sizeW = readFloat(getInput("width"), _sizeW);
        _sizeH = readFloat(getInput("height"), _sizeH);
        _scaleX = readScale(getInput("scaleX"), _scaleX);
        _scaleY = readScale(getInput("scaleY"), _scaleY);
        _alpha = clamp01(readFloat(getInput("alpha"), _alpha));
        _zOrder = readInt(getInput("zOrder"), _zOrder);

        var visibleC = getInput("visible");
        if (visibleC != null && visibleC.value != null)
        {
            _visible = (visibleC.value == true);
        }

        // v1.2: aspect / enabled mirrors (inputs ride on wires; the state
        // copy exists for introspection and future persistence decisions)
        var aspectC = getInput("aspect");
        if (aspectC != null && aspectC.value != null)
        {
            _aspect = (aspectC.value == true);
        }
        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null)
        {
            _enabled = (enabledC.value == true);
        }
    }

    /** Tolerant Float read: null / NaN / non-numeric keep the current value. */
    private static function readFloat(c:Contact, current:Float):Float
    {
        if (c == null || c.value == null) return current;
        var f:Float = Std.parseFloat(Std.string(c.value));
        if (Math.isNaN(f) || !Math.isFinite(f)) return current;
        return f;
    }

    /** Scale read: additionally, non-positive values fall back to 1 (collapse-proof). */
    private static function readScale(c:Contact, current:Float):Float
    {
        var f:Float = readFloat(c, current);
        return (f <= 0) ? 1 : f;
    }

    /** Tolerant Int read (zOrder). */
    private static function readInt(c:Contact, current:Int):Int
    {
        if (c == null || c.value == null) return current;
        var f:Float = Std.parseFloat(Std.string(c.value));
        if (Math.isNaN(f) || !Math.isFinite(f)) return current;
        return Std.int(f);
    }

    private static function clamp01(v:Float):Float
    {
        if (v < 0) return 0;
        if (v > 1) return 1;
        return v;
    }

    // ── Status outputs ───────────────────────────────────────────────────────

    /**
     * Push the status wave: ok/kind/imgWidth/imgHeight.
     * silent=true — restore path: wires are not linked yet (load-symmetric
     * reconstruction, family discipline).
     */
    private function pushStatus(silent:Bool):Void
    {
        var has:Bool = (_imageBytes != null && _imageBytes.length > 0);
        setOut("ok", has, silent);
        setOut("kind", _kind, silent);
        setOut("imgWidth", has ? _natW : 0, silent);
        setOut("imgHeight", has ? _natH : 0, silent);
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
        trace('PictureAtom ERROR: $msg');
    }

    private function pulseLoaded():Void
    {
        if (_isDisposed) return;
        var c = getOutput("loadedTick");
        if (c != null)
        {
            c.value = true;
            _loadedTickTimer = PULSE_DURATION;
        }
    }

    private function updatePulseTimers(dt:Float):Void
    {
        if (_isDisposed) return;

        if (_loadedTickTimer > 0)
        {
            _loadedTickTimer -= dt;
            if (_loadedTickTimer <= 0)
            {
                var c = getOutput("loadedTick");
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

    // ── PERSISTENCE (transform state only; the image is runtime-derived) ─────

    /**
     * Save state: ONLY non-default transform fields ride into the scheme
     * JSON. The picture bytes are NOT serialized (DataStorage owns
     * persistent bytes; the graph re-feeds this atom after reload).
     */
    override public function getPersistentState():Dynamic
    {
        var state:Dynamic = super.getPersistentState();
        if (state == null) state = {};

        var dirty:Bool = false;
        if (_posX != 0) { state.posX = _posX; dirty = true; }
        if (_posY != 0) { state.posY = _posY; dirty = true; }
        if (_sizeW != 0) { state.width = _sizeW; dirty = true; }
        if (_sizeH != 0) { state.height = _sizeH; dirty = true; }
        if (_scaleX != 1) { state.scaleX = _scaleX; dirty = true; }
        if (_scaleY != 1) { state.scaleY = _scaleY; dirty = true; }
        if (!_visible) { state.visible = false; dirty = true; }
        if (_alpha != 1) { state.alpha = _alpha; dirty = true; }
        if (_zOrder != 0) { state.zOrder = _zOrder; dirty = true; }

        if (!dirty && Reflect.fields(state).length == 0) return null;
        return state;
    }

    /**
     * Restore state (tolerant): missing/garbage fields keep defaults; the
     * picture itself stays empty — the graph re-feeds it (honest boundary).
     * The status wave is pushed silently (wires build later).
     */
    override public function restoreState(state:Dynamic):Void
    {
        super.restoreState(state);
        if (state == null) return;

        _posX = restoreFloat(state, "posX", 0);
        _posY = restoreFloat(state, "posY", 0);
        _sizeW = restoreFloat(state, "width", 0);
        _sizeH = restoreFloat(state, "height", 0);
        _scaleX = restoreScale(state, "scaleX");
        _scaleY = restoreScale(state, "scaleY");
        _alpha = clamp01(restoreFloat(state, "alpha", 1));
        _zOrder = Math.round(restoreFloat(state, "zOrder", 0));

        if (Reflect.hasField(state, "visible"))
        {
            _visible = (state.visible == true);
        }

        // The bank stays empty by design; status reflects that honestly.
        _imageBytes = null;
        _kind = KIND_NONE;
        _natW = 0;
        _natH = 0;

        pushStatus(true);
        trace('PictureAtom: state restored (pos=${_posX},${_posY} scale=${_scaleX},${_scaleY} z=${_zOrder})');
    }

    private static function restoreFloat(state:Dynamic, field:String, def:Float):Float
    {
        if (!Reflect.hasField(state, field)) return def;
        var f:Float = Std.parseFloat(Std.string(Reflect.field(state, field)));
        if (Math.isNaN(f) || !Math.isFinite(f)) return def;
        return f;
    }

    private static function restoreScale(state:Dynamic, field:String):Float
    {
        var f:Float = restoreFloat(state, field, 1);
        return (f <= 0) ? 1 : f;
    }

    // ── Public access (the face reads the databank; no openfl here) ─────────

    /**
     * Codec error report from the face (PictureWidget owns the real
     * decode). The v7.2 fault latch makes the failure visible in the
     * EDITOR (red frame, FAULT plaque); THIS channel makes it visible on
     * the WIRES: the message is published to [error] and [errorTick]
     * fires — downstream atoms and the pilot's probe texts see it.
     * (Field lesson, Task 156: a FAULTed picture with a silent [error]
     * contact is a missing channel, not a feature.)
     */
    public function reportCodecError(message:String):Void
    {
        if (_isDisposed) return;
        setError((message != null) ? message : "codec decode failed");
    }

    /** The raw picture bytes (reference — the face decodes read-only). null = empty. */
    public function getImageBytes():Bytes return _imageBytes;
    /** Picture change counter: bump on every store/clear — the face's re-decode trigger. */
    public function getImageVersion():Int return _imageVersion;
    public function hasPicture():Bool return (_imageBytes != null && _imageBytes.length > 0);
    public function getPictureKind():String return _kind;
    public function getNaturalWidth():Int return _natW;
    public function getNaturalHeight():Int return _natH;

    // Transform getters (widget geometry source of truth)
    public function getPosX():Float return _posX;
    public function getPosY():Float return _posY;
    /** 0 = natural width. */
    public function getDisplayWidth():Float return _sizeW;
    /** 0 = natural height. */
    public function getDisplayHeight():Float return _sizeH;
    public function getScaleX():Float return _scaleX;
    public function getScaleY():Float return _scaleY;
    public function isVisible():Bool return _visible;
    /** 0..1 (clamped). */
    public function getAlpha():Float return _alpha;
    public function getZOrder():Int return _zOrder;
    /** v1.2: aspect mirror ([aspect] input). */
    public function getAspect():Bool return _aspect;
    /** v1.2: enabled mirror ([enabled] input, render gate). */
    public function getEnabled():Bool return _enabled;
}
