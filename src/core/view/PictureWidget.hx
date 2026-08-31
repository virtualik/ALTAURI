package core.view;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import lime.graphics.Image;
import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import ui.DeviceCard;
import library.drivers.PictureAtom;

/**
 * PICTURE WIDGET v1.1 (Task 156 field fix)
 * The Face of PictureAtom (Stage 4a-3, Task 155).
 * Spec: SPEC_STAGE4A_PICTURE.md §5.
 *
 * Architecture: "Atom is Databank & Compute Core"
 *   ┌─────────────────────────────────────────────────────────────────────────┐
 *   │   PICTURE                                                               │
 *   │   ────────────────────────────────────────────────────────────────     │
 *   │   Kind: png   120×90   45.2 KB          [LED ●]                        │
 *   │   ┌───────────────────────────────────────────────────────────────     │
 *   │   │                    (Bitmap / placeholder)                       │     │
 *   │   └───────────────────────────────────────────────────────────────     │
 *   │   Error: ___________________                                            │
 *   └─────────────────────────────────────────────────────────────────────────┘
 *
 * DIVISION OF LABOR (the honest split):
 *   · ATOM validates the image header (magic + dims) — data-level truth;
 *   · THIS WIDGET performs the real BitmapData decode via the platform
 *     codecs. A codec failure latches the v7.2 fault on the atom
 *     (markAsFaulted — red frame in the editor); a successful decode
 *     unlatches it.
 *   · Re-decode trigger: the atom's image version counter (bumped per
 *     store/clear). Status outputs are the change signal; the bytes flow
 *     through the public getter (reference — decode is read-only).
 *
 * "MAKEUP" GEOMETRY (programmatic picture):
 *   · posX/posY — position the DEVICE CARD on the panel (non-default
 *     values only: defaults must not fight the panel's auto-placement
 *     and manual card drags);
 *   · zOrder — card stacking order among panel children (non-zero only:
 *     0 = manual stacking via click-to-front stays untouched);
 *   · width/height (0 = natural) * scaleX/scaleY — the bitmap display
 *     size inside the card (W = (w>0 ? w : natW) * sx; aspect is NOT
 *     preserved — exact control stays with the user);
 *   · visible/alpha — the bitmap;
 *   · Mouse drag ON THE PICTURE moves the parent DeviceCard (the panel
 *     persists positions via DEVICE_WINDOW_CHANGED; no contact writeback
 *     in v1 — signal pins are one-way atom → widget).
 *
 * DECODE GATEWAY v1.1 (Task 156, field fix): five ordered codec paths,
 * each guarded by try/catch, each result validated (0x0 = no pixels =
 * failure). The v1.0 two-path reflection gateway relied on
 * BitmapData.fromBytes + a ByteArray.fromBytes retry that do not exist
 * in the field OpenFL build — the v1.0 stand passed because its stubs
 * were written from the ASSUMED API, not the real one (the T141 rake
 * again). The gateway is now rebuilt against the verified OpenFL/lime
 * API surface:
 *   A  BitmapData.fromBytes(bytes) — the current API accepts a
 *      haxe.io.Bytes directly (native: synchronous decode);
 *   C  lime.graphics.Image.fromBytes(bytes) → BitmapData.fromImage —
 *      lime decodes raw haxe.io.Bytes natively (the most universal
 *      route; verified: static fromBytes(bytes:Bytes):Image);
 *   B  reflective openfl.utils.ByteArray.fromBytes conversion →
 *      fromBytes(byteArray) (covers strict ByteArray-typed signatures
 *      of older OpenFL builds);
 *   D  BitmapData.fromBase64 — the string-channel fallback;
 *   E  temp-file roundtrip: saveBytes → BitmapData.fromFile →
 *      immediate delete (native last resort, no litter).
 * DCE ARMOR: the primary entry points are taken as BARE METHOD VALUES
 * (var f:Dynamic = BitmapData.fromBytes) — a static reference keeps the
 * method alive under hxcpp dead-code elimination, where a purely
 * reflective Reflect.field on an unreferenced library static may
 * return null. Signature drift between OpenFL versions is absorbed at
 * runtime: a throw or a null/0x0 result simply falls through to the
 * next path. Every attempt records a per-path trace; a total failure
 * publishes that trace (a) into the v7.2 fault latch and (b) onto the
 * atom's [error]/[errorTick] outputs via reportCodecError — the wire
 * channel the field demanded: a FAULT with a silent [error] contact
 * is a missing channel, not a feature.
 * HAXE NOTE: only single-quoted strings interpolate. The v1.0 fault
 * message used double quotes and printed a literal "${bytes.length}"
 * on the field plaque — all message strings are single-quoted or
 * concatenated now. Native targets decode synchronously; html5 may
 * deliver no pixels (async codecs) — an honest boundary, SPEC §7.
 */
class PictureWidget extends DeviceView
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;

    private var _infoLabel:TextField;
    private var _errorLabel:TextField;

    /** Container of the decoded Bitmap; geometry target of visible/alpha. */
    private var _imageHolder:Sprite;
    /** Placeholder shown while the bank is empty ("no image"). */
    private var _placeholder:Sprite;
    private var _placeholderLabel:TextField;
    /** The decoded picture. */
    private var _bitmap:Bitmap;

    // =========================================================================
    // CONTACTS
    // =========================================================================
    private var _imageContact:Contact;      // not drawn: the heavy cargo (P2)
    private var _clearContact:Contact;
    private var _posXContact:Contact;
    private var _posYContact:Contact;
    private var _widthContact:Contact;
    private var _heightContact:Contact;
    private var _scaleXContact:Contact;
    private var _scaleYContact:Contact;
    private var _visibleContact:Contact;
    private var _alphaContact:Contact;
    private var _zOrderContact:Contact;

    private var _okContact:Contact;
    private var _kindContact:Contact;
    private var _imgWidthContact:Contact;
    private var _imgHeightContact:Contact;
    private var _errorContact:Contact;
    private var _loadedTickContact:Contact;
    private var _errorTickContact:Contact;

    // =========================================================================
    // STATE (UI mirror only; the truth lives in the atom's Databank)
    // =========================================================================
    /** Atom image version already decoded (re-decode guard). */
    private var _decodedVersion:Int = -1;
    private var _kind:String = "none";
    private var _imgW:Int = 0;
    private var _imgH:Int = 0;
    private var _byteSize:Int = 0;
    private var _lastError:String = "";

    // Transform mirror (UI state — DeviceView doctrine allows it). The
    // CONTACT VALUE is the single source of truth here: contact callbacks
    // fire BEFORE the atom mirrors them into its own fields (next frame),
    // so the widget parses contact values directly — no race, no gap.
    private var _tPosX:Float = 0;
    private var _tPosY:Float = 0;
    private var _tSizeW:Float = 0;
    private var _tSizeH:Float = 0;
    private var _tScaleX:Float = 1;
    private var _tScaleY:Float = 1;
    private var _tVisible:Bool = true;
    private var _tAlpha:Float = 1;
    private var _tZOrder:Int = 0;

    // Card drag state (mouse on the picture moves the DeviceCard)
    private var _cardDragging:Bool = false;
    private var _cardStartX:Float = 0;
    private var _cardStartY:Float = 0;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;

    // Cached stage listener refs: ONE closure object is used for both
    // add and remove — identity is guaranteed on every target (a fresh
    // method reference may not compare equal).
    private var _stageMoveRef:MouseEvent -> Void;
    private var _stageUpRef:MouseEvent -> Void;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 240;
    public var widgetHeight:Float = 190;

    /** Image area geometry (inside the card, below the info line). */
    private static inline var AREA_X:Float = 10;
    private static inline var AREA_Y:Float = 54;
    private static inline var AREA_W:Float = 220;
    private static inline var AREA_H:Float = 108;

    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorAccent:Int = 0xAA66FF;
    private var _colorActive:Int = 0x00FF88;
    private var _colorDanger:Int = 0xFF4444;
    private var _colorText:Int = 0xFFFFFF;
    private var _colorMuted:Int = 0x888899;
    private var _colorAreaBg:Int = 0x0d0d18;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom)
    {
        super(atom);
        findContacts();
        buildUI();
        syncFromAtom();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    private function findContacts():Void
    {
        if (atom == null) return;

        _imageContact = atom.getInput("image");
        _clearContact = atom.getInput("clear");
        _posXContact = atom.getInput("posX");
        _posYContact = atom.getInput("posY");
        _widthContact = atom.getInput("width");
        _heightContact = atom.getInput("height");
        _scaleXContact = atom.getInput("scaleX");
        _scaleYContact = atom.getInput("scaleY");
        _visibleContact = atom.getInput("visible");
        _alphaContact = atom.getInput("alpha");
        _zOrderContact = atom.getInput("zOrder");

        _okContact = atom.getOutput("ok");
        _kindContact = atom.getOutput("kind");
        _imgWidthContact = atom.getOutput("imgWidth");
        _imgHeightContact = atom.getOutput("imgHeight");
        _errorContact = atom.getOutput("error");
        _loadedTickContact = atom.getOutput("loadedTick");
        _errorTickContact = atom.getOutput("errorTick");
    }

    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        // === BACKGROUND ===
        _bg = new Sprite();
        addChild(_bg);

        // === HEADER ===
        _header = new Sprite();
        addChild(_header);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = "  PICTURE";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // Status LED (green = picture decoded and held)
        _statusGlow = new Sprite();
        _statusGlow.graphics.beginFill(_colorActive, 0.2);
        _statusGlow.graphics.drawCircle(0, 0, 12);
        _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 18;
        _statusGlow.y = 14;
        _statusGlow.visible = false;
        _header.addChild(_statusGlow);

        _statusLed = new Sprite();
        _statusLed.graphics.beginFill(0x440000);
        _statusLed.graphics.drawCircle(0, 0, 6);
        _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 18;
        _statusLed.y = 14;
        _header.addChild(_statusLed);

        // === INFO LINE ===
        _infoLabel = new TextField();
        _infoLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _infoLabel.text = "Kind: none   0x0   0 B";
        _infoLabel.width = widgetWidth - 20;
        _infoLabel.height = 16;
        _infoLabel.x = 10;
        _infoLabel.y = 34;
        _infoLabel.selectable = false;
        _infoLabel.mouseEnabled = false;
        addChild(_infoLabel);

        // === IMAGE HOLDER (geometry target; the Bitmap lives inside) ===
        _imageHolder = new Sprite();
        _imageHolder.x = AREA_X;
        _imageHolder.y = AREA_Y;
        addChild(_imageHolder);

        // === PLACEHOLDER ===
        _placeholder = new Sprite();
        _placeholder.graphics.beginFill(_colorAreaBg);
        _placeholder.graphics.lineStyle(1, 0x333355);
        _placeholder.graphics.drawRect(0, 0, AREA_W, AREA_H);
        _placeholder.graphics.endFill();

        _placeholderLabel = new TextField();
        _placeholderLabel.defaultTextFormat = new TextFormat("_typewriter", 12, _colorMuted, true,
            null, null, null, null, TextFormatAlign.CENTER);
        _placeholderLabel.text = "no image";
        _placeholderLabel.width = AREA_W;
        _placeholderLabel.height = 20;
        _placeholderLabel.x = 0;
        _placeholderLabel.y = (AREA_H - 20) / 2;
        _placeholderLabel.selectable = false;
        _placeholderLabel.mouseEnabled = false;
        _placeholder.addChild(_placeholderLabel);

        _imageHolder.addChild(_placeholder);

        // Grab-the-picture drag (moves the parent DeviceCard, see class docs)
        _imageHolder.buttonMode = true;
        _imageHolder.useHandCursor = true;
        _stageMoveRef = onStageMouseMove;
        _stageUpRef = onStageMouseUp;
        _imageHolder.addEventListener(MouseEvent.MOUSE_DOWN, onImageMouseDown);

        // === ERROR ===
        _errorLabel = new TextField();
        _errorLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorDanger);
        _errorLabel.text = "";
        _errorLabel.width = widgetWidth - 20;
        _errorLabel.height = 15;
        _errorLabel.x = 10;
        _errorLabel.y = widgetHeight - 22;
        _errorLabel.selectable = false;
        _errorLabel.mouseEnabled = false;
        addChild(_errorLabel);

        redrawBackground();
    }

    private function redrawBackground():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(_colorBg, 0.95);
        _bg.graphics.lineStyle(1, _colorAccent);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _bg.graphics.endFill();

        _header.graphics.clear();
        _header.graphics.beginFill(_colorHeader);
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 28, 8, 8, 0, 0);
        _header.graphics.endFill();
    }

    // =========================================================================
    // ATOM SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
        if (isDisposed) return;

        if (_kindContact != null && _kindContact.value != null)
        {
            _kind = Std.string(_kindContact.value);
        }
        if (_imgWidthContact != null && _imgWidthContact.value != null)
        {
            _imgW = Std.int(_imgWidthContact.value);
        }
        if (_imgHeightContact != null && _imgHeightContact.value != null)
        {
            _imgH = Std.int(_imgHeightContact.value);
        }
        if (_errorContact != null && _errorContact.value != null)
        {
            var errStr:String = Std.string(_errorContact.value);
            if (errStr != _lastError)
            {
                _errorLabel.text = (errStr != "") ? "Error: " + errStr : "";
                _lastError = errStr;
            }
        }

        checkAndDecode();
        syncTransformMirror();
        applyTransform();
        applyCardPlacement();
        updateInfo();
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;

        // [image] itself is NOT drawn: the atom consumes the portion and
        // bumps the version — the status outputs below are the change signal.
        if (contact == _okContact || contact == _kindContact
            || contact == _imgWidthContact || contact == _imgHeightContact
            || contact == _loadedTickContact)
        {
            if (contact == _kindContact && newValue != null) _kind = Std.string(newValue);
            if (contact == _imgWidthContact && newValue != null) _imgW = Std.int(newValue);
            if (contact == _imgHeightContact && newValue != null) _imgH = Std.int(newValue);

            checkAndDecode();
            updateInfo();
        }
        else if (contact == _errorContact)
        {
            var errStr:String = Std.string(newValue);
            if (errStr != "" && errStr != "null")
            {
                _errorLabel.text = "Error: " + errStr;
                _lastError = errStr;
            }
            else
            {
                _errorLabel.text = "";
                _lastError = "";
            }
        }
        else if (contact == _posXContact || contact == _posYContact
            || contact == _zOrderContact)
        {
            if (contact == _posXContact && newValue != null) _tPosX = parseFloat(newValue, _tPosX);
            if (contact == _posYContact && newValue != null) _tPosY = parseFloat(newValue, _tPosY);
            if (contact == _zOrderContact && newValue != null) _tZOrder = Math.round(parseFloat(newValue, _tZOrder));
            applyCardPlacement();
        }
        else if (contact == _widthContact || contact == _heightContact
            || contact == _scaleXContact || contact == _scaleYContact
            || contact == _visibleContact || contact == _alphaContact)
        {
            if (contact == _widthContact && newValue != null) _tSizeW = parseFloat(newValue, _tSizeW);
            if (contact == _heightContact && newValue != null) _tSizeH = parseFloat(newValue, _tSizeH);
            if (contact == _scaleXContact && newValue != null) _tScaleX = parseScale(newValue, _tScaleX);
            if (contact == _scaleYContact && newValue != null) _tScaleY = parseScale(newValue, _tScaleY);
            if (contact == _visibleContact && newValue != null) _tVisible = (newValue == true);
            if (contact == _alphaContact && newValue != null) _tAlpha = clamp01(parseFloat(newValue, _tAlpha));
            applyTransform();
        }
    }

    // =========================================================================
    // DECODE (the real codec — reflection boundary, see class docs)
    // =========================================================================

    /**
     * Re-decode when the atom's image version moved (store, replace, clear).
     * The atom state is already final when this runs: the status wave is
     * pushed AFTER the bank is updated.
     */
    private function checkAndDecode():Void
    {
        if (isDisposed) return;
        var a:PictureAtom = pictureAtom();
        if (a == null) return;

        var ver:Int = a.getImageVersion();
        if (ver == _decodedVersion) return;
        _decodedVersion = ver;

        // Drop the previous bitmap (its BitmapData is ours to dispose)
        disposeBitmap();

        var bytes = a.getImageBytes();
        if (bytes == null || bytes.length == 0)
        {
            // Cleared state: the placeholder is the honest face.
            _placeholder.visible = true;
            updateConnectionStatus(false);
            return;
        }

        var bmd:BitmapData = decodeToBitmapData(bytes, a.getPictureKind());
        if (bmd == null || bmd.width <= 0 || bmd.height <= 0)
        {
            var msg:String = 'codec decode failed (${bytes.length} bytes, kind=${a.getPictureKind()}): '
                + ((_decodeTrace.length > 0) ? _decodeTrace.join(", ") : "no codec path available");
            // Fresh latch per attempt (attempts are bounded by version
            // changes, not frames): clear + re-mark re-emits the honest
            // CURRENT message instead of the stale first one.
            if (a.isFaulted) a.clearFault();
            a.markAsFaulted("CODEC", msg);
            a.reportCodecError(msg); // the wire channel: [error] + [errorTick]
            _placeholder.visible = true;
            updateConnectionStatus(false);
            return;
        }

        _bitmap = new Bitmap(bmd);
        _imageHolder.addChild(_bitmap);
        _placeholder.visible = false;
        a.clearFault();
        updateConnectionStatus(true);
        trace('PictureWidget: decoded ${bytes.length} bytes -> ${bmd.width}x${bmd.height} (path=${_lastDecodePath})');
    }

    /** Which decode path succeeded (diagnostics for the field protocol). */
    private var _lastDecodePath:String = "-";

    /** Per-attempt decode diagnostics (one entry per tried path). */
    private var _decodeTrace:Array<String> = [];

    /**
     * Decode bytes into BitmapData via the platform codec.
     * Five ordered paths (see the class doc): A fromBytes → C lime image →
     * B ByteArray conversion → D base64 → E temp-file roundtrip.
     * Anchored bare-method references survive hxcpp DCE; signature drift
     * is absorbed at runtime (throw / null / 0x0 → next path).
     * Returns null only when EVERY path failed — the caller then owns the
     * honest fault + error publication.
     */
    private function decodeToBitmapData(bytes:Dynamic, kind:String):BitmapData
    {
        _lastDecodePath = "-";
        _decodeTrace = [];
        var mime:String = (kind != null && kind != "none") ? "image/" + kind : "image/png";

        // ── Path A: BitmapData.fromBytes (anchored static reference) ──
        try
        {
            var fn:Dynamic = BitmapData.fromBytes; // bare method value: DCE anchor
            if (fn != null)
            {
                var bmd:BitmapData = callCodec(BitmapData, fn, [bytes]);
                if (validPixels(bmd))
                {
                    _lastDecodePath = "A:fromBytes";
                    return bmd;
                }
                _decodeTrace.push((bmd == null) ? "A:no-result" : "A:no-pixels");
            }
            else
            {
                _decodeTrace.push("A:absent");
            }
        }
        catch (e:Dynamic)
        {
            _decodeTrace.push("A:threw:" + briefOf(e));
        }

        // ── Path C: lime Image.fromBytes → BitmapData.fromImage (anchored) ──
        try
        {
            var imageFn:Dynamic = Image.fromBytes; // DCE anchor (lime)
            var wrapFn:Dynamic = BitmapData.fromImage; // DCE anchor
            if (imageFn != null && wrapFn != null)
            {
                var image:Dynamic = callCodec(Image, imageFn, [bytes]);
                if (image != null && Reflect.getProperty(image, "buffer") != null)
                {
                    var bmd:BitmapData = callCodec(BitmapData, wrapFn, [image]);
                    if (validPixels(bmd))
                    {
                        _lastDecodePath = "C:lime-image";
                        return bmd;
                    }
                    _decodeTrace.push((bmd == null) ? "C:no-result" : "C:no-pixels");
                }
                else
                {
                    _decodeTrace.push("C:image-empty");
                }
            }
            else
            {
                _decodeTrace.push("C:absent");
            }
        }
        catch (e:Dynamic)
        {
            _decodeTrace.push("C:threw:" + briefOf(e));
        }

        // ── Path B: reflective ByteArray conversion → fromBytes(byteArray) ──
        try
        {
            var baClass:Dynamic = Type.resolveClass("openfl.utils.ByteArray");
            var conv:Dynamic = (baClass != null) ? Reflect.field(baClass, "fromBytes") : null;
            if (baClass != null && conv != null)
            {
                var ba:Dynamic = Reflect.callMethod(baClass, conv, [bytes]);
                var fn:Dynamic = BitmapData.fromBytes; // anchored
                if (ba != null && fn != null)
                {
                    var bmd:BitmapData = callCodec(BitmapData, fn, [ba]);
                    if (validPixels(bmd))
                    {
                        _lastDecodePath = "B:bytearray";
                        return bmd;
                    }
                    _decodeTrace.push((bmd == null) ? "B:no-result" : "B:no-pixels");
                }
                else
                {
                    _decodeTrace.push("B:no-convert");
                }
            }
            else
            {
                _decodeTrace.push("B:absent");
            }
        }
        catch (e:Dynamic)
        {
            _decodeTrace.push("B:threw:" + briefOf(e));
        }

        // ── Path D: base64 string channel (two historical call shapes) ──
        try
        {
            var fn:Dynamic = BitmapData.fromBase64; // anchored
            if (fn != null)
            {
                var b64:String = haxe.crypto.Base64.encode(bytes);
                var bmd:BitmapData = null;
                try
                {
                    bmd = callCodec(BitmapData, fn, [b64, mime]);
                }
                catch (e1:Dynamic)
                {
                    bmd = callCodec(BitmapData, fn, [b64]); // older signature
                }
                if (validPixels(bmd))
                {
                    _lastDecodePath = "D:base64";
                    return bmd;
                }
                _decodeTrace.push((bmd == null) ? "D:no-result" : "D:no-pixels");
            }
            else
            {
                _decodeTrace.push("D:absent");
            }
        }
        catch (e:Dynamic)
        {
            _decodeTrace.push("D:threw:" + briefOf(e));
        }

        // ── Path E: temp-file roundtrip (native only; no litter) ──
        var tmpPath:String = tempPicturePath(kind);
        if (tmpPath == null)
        {
            _decodeTrace.push("E:no-tempdir");
        }
        else
        {
            try
            {
                var fileClass:Dynamic = Type.resolveClass("sys.io.File");
                var fn:Dynamic = BitmapData.fromFile; // anchored
                if (fileClass != null && fn != null)
                {
                    var bmd:BitmapData = null;
                    try
                    {
                        Reflect.callMethod(fileClass, Reflect.field(fileClass, "saveBytes"), [tmpPath, bytes]);
                        bmd = callCodec(BitmapData, fn, [tmpPath]);
                    }
                    catch (inner:Dynamic)
                    {
                        deleteQuietly(tmpPath); // cleanup first — Haxe has no finally
                        throw inner; // outer catch records it
                    }
                    deleteQuietly(tmpPath);
                    if (validPixels(bmd))
                    {
                        _lastDecodePath = "E:tempfile";
                        return bmd;
                    }
                    _decodeTrace.push((bmd == null) ? "E:no-result" : "E:no-pixels");
                }
                else
                {
                    deleteQuietly(tmpPath);
                    _decodeTrace.push("E:absent");
                }
            }
            catch (e:Dynamic)
            {
                _decodeTrace.push("E:threw:" + briefOf(e));
            }
        }

        return null;
    }

    // ── Decode gateway helpers ───────────────────────────────────────────

    /** Call a codec entry point dynamically; a throw is the path's business. */
    private static function callCodec(owner:Dynamic, fn:Dynamic, args:Array<Dynamic>):BitmapData
    {
        var r:Dynamic = Reflect.callMethod(owner, fn, args);
        return (r == null) ? null : cast r;
    }

    /** Validate a decode result: real dimensions, real pixels. */
    private static function validPixels(bmd:Dynamic):Bool
    {
        if (bmd == null) return false;
        // width/height are PROPERTIES on real openfl — Reflect, not field access
        var w:Dynamic = Reflect.getProperty(bmd, "width");
        var h:Dynamic = Reflect.getProperty(bmd, "height");
        if (w == null || h == null) return false;
        var wf:Float = Std.parseFloat(Std.string(w));
        var hf:Float = Std.parseFloat(Std.string(h));
        return !Math.isNaN(wf) && !Math.isNaN(hf) && wf > 0 && hf > 0;
    }

    /** Compact exception summary for the decode trace (bounded length). */
    private static function briefOf(e:Dynamic):String
    {
        var s:String = (e == null) ? "null" : Std.string(e);
        s = StringTools.replace(s, "\n", " ");
        s = StringTools.replace(s, "\r", " ");
        if (s.length > 48) s = s.substr(0, 48) + "...";
        return s;
    }

    /**
     * A temp path for the native file-roundtrip decode (Path E):
     * <tmpdir>/altauri_picture_<atomId>.<ext>. kind picks the extension
     * (cosmetic — lime sniffs the magic bytes, not the name).
     */
    private function tempPicturePath(kind:String):String
    {
        var dir:String = null;
        try
        {
            dir = Sys.getEnv("TEMP");
            if (dir == null) dir = Sys.getEnv("TMP");
            if (dir == null) dir = Sys.getEnv("TMPDIR");
        }
        catch (e:Dynamic)
        {
            dir = null;
        }
        if (dir == null || dir == "") dir = "./";
        if (!StringTools.endsWith(dir, "/") && !StringTools.endsWith(dir, "\\")) dir += "/";

        var safeId:String = "x";
        if (atom != null && atom.id != null)
        {
            safeId = "";
            for (i in 0...atom.id.length)
            {
                var ch:String = atom.id.charAt(i);
                var okCh:Bool = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z")
                    || (ch >= "0" && ch <= "9") || ch == "_" || ch == "-";
                safeId += okCh ? ch : "_";
            }
        }

        var ext:String = switch (kind)
        {
            case "png": ".png";
            case "jpeg": ".jpg";
            case "bmp": ".bmp";
            default: ".img";
        }
        return dir + "altauri_picture_" + safeId + ext;
    }

    /** Best-effort temp file removal (Path E hygiene — decode or not). */
    private static function deleteQuietly(path:String):Void
    {
        try
        {
            var fs:Dynamic = Type.resolveClass("sys.FileSystem");
            if (fs != null) Reflect.callMethod(fs, Reflect.field(fs, "deleteFile"), [path]);
        }
        catch (e:Dynamic)
        {
            // best effort — a stale temp file is not worth a fault
        }
    }

    private function disposeBitmap():Void
    {
        if (_bitmap != null)
        {
            if (_imageHolder.contains(_bitmap)) _imageHolder.removeChild(_bitmap);
            if (_bitmap.bitmapData != null) _bitmap.bitmapData.dispose();
            _bitmap = null;
        }
    }

    // =========================================================================
    // "MAKEUP" GEOMETRY
    // =========================================================================

    /**
     * Apply the transform pins to the bitmap:
     *   W = (width > 0 ? width : naturalW) * scaleX
     *   H = (height > 0 ? height : naturalH) * scaleY
     * (aspect is NOT preserved — exact control by design, SPEC §4);
     * visible/alpha apply to the holder.
     */
    private function applyTransform():Void
    {
        _imageHolder.visible = _tVisible;
        _imageHolder.alpha = _tAlpha;

        if (_bitmap == null || _bitmap.bitmapData == null) return;
        var bmd:BitmapData = _bitmap.bitmapData;
        if (bmd.width <= 0 || bmd.height <= 0) return;

        var natW:Int = (_imgW > 0) ? _imgW : bmd.width;
        var natH:Int = (_imgH > 0) ? _imgH : bmd.height;

        var targetW:Float = ((_tSizeW > 0) ? _tSizeW : natW) * _tScaleX;
        var targetH:Float = ((_tSizeH > 0) ? _tSizeH : natH) * _tScaleY;

        _bitmap.scaleX = targetW / bmd.width;
        _bitmap.scaleY = targetH / bmd.height;
    }

    /**
     * Apply the panel-level "makeup": posX/posY place the parent DeviceCard,
     * zOrder sets its stacking among panel children. NON-DEFAULT values only:
     * defaults must not fight the panel's auto-placement, manual drags and
     * click-to-front stacking (SPEC §4.2).
     *
     * Reflect note: the card/panel are accessed through Reflect properties —
     * openfl geometry (x/y/parent/numChildren) may be real properties (get/set)
     * where raw Dynamic field access silently misses them.
     */
    private function applyCardPlacement():Void
    {
        var card:Dynamic = parent;
        if (card == null || !Std.isOfType(card, DeviceCard)) return;

        if (_tPosX != 0 || _tPosY != 0)
        {
            Reflect.setProperty(card, "x", _tPosX);
            Reflect.setProperty(card, "y", _tPosY);
        }

        if (_tZOrder != 0)
        {
            var panel:Dynamic = Reflect.getProperty(card, "parent");
            if (panel != null)
            {
                var nChildren:Dynamic = Reflect.getProperty(panel, "numChildren");
                if (nChildren != null)
                {
                    var idx:Int = _tZOrder;
                    if (idx < 0) idx = 0;
                    var max:Int = Std.int(nChildren) - 1;
                    if (idx > max) idx = max;
                    try
                    {
                        panel.setChildIndex(card, idx);
                    }
                    catch (e:Dynamic)
                    {
                        // exotic container — keep manual order (honest no-op)
                    }
                }
            }
        }
    }

    // =========================================================================
    // PICTURE DRAG (moves the parent DeviceCard)
    // =========================================================================
    private function onImageMouseDown(e:MouseEvent):Void
    {
        if (isDisposed) return;

        var card:Dynamic = parent;
        if (card == null || !Std.isOfType(card, DeviceCard)) return;
        if (stage == null) return;

        e.stopPropagation();

        _cardDragging = true;
        _cardStartX = Reflect.getProperty(card, "x");
        _cardStartY = Reflect.getProperty(card, "y");
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;

        // Bring the card to front (layers: the grabbed picture wins)
        var panel:Dynamic = Reflect.getProperty(card, "parent");
        if (panel != null) panel.addChild(card);

        stage.addEventListener(MouseEvent.MOUSE_MOVE, _stageMoveRef);
        stage.addEventListener(MouseEvent.MOUSE_UP, _stageUpRef);
    }

    private function onStageMouseMove(e:MouseEvent):Void
    {
        if (!_cardDragging || isDisposed) return;

        var card:Dynamic = parent;
        if (card == null) return;

        Reflect.setProperty(card, "x", _cardStartX + (e.stageX - _mouseStartX));
        Reflect.setProperty(card, "y", _cardStartY + (e.stageY - _mouseStartY));
    }

    private function onStageMouseUp(e:MouseEvent):Void
    {
        _cardDragging = false;

        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, _stageMoveRef);
            stage.removeEventListener(MouseEvent.MOUSE_UP, _stageUpRef);
        }

        // The panel persists card positions on this signal (family style)
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    // =========================================================================
    // UI UPDATES
    // =========================================================================
    private function updateInfo():Void
    {
        var a:PictureAtom = pictureAtom();
        var sizeStr:String = "0 B";
        if (a != null && a.getImageBytes() != null)
        {
            sizeStr = formatFileSize(a.getImageBytes().length);
        }
        _infoLabel.text = 'Kind: $_kind   ${_imgW}x${_imgH}   $sizeStr';

        if (a != null && a.isFaulted)
        {
            _errorLabel.text = "Fault: " + a.faultMessage;
        }
    }

    private function updateConnectionStatus(hasPicture:Bool):Void
    {
        if (hasPicture)
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(_colorActive);
            _statusLed.graphics.drawCircle(0, 0, 6);
            _statusLed.graphics.endFill();
            _statusGlow.visible = true;
        }
        else
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(0x440000);
            _statusLed.graphics.drawCircle(0, 0, 6);
            _statusLed.graphics.endFill();
            _statusGlow.visible = false;
        }
    }

    private function formatFileSize(bytes:Int):String
    {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return _toFixed(bytes / 1024, 1) + " KB";
        return _toFixed(bytes / (1024 * 1024), 1) + " MB";
    }

    /** Typed atom accessor (null when the atom is foreign/disposed). */
    private function pictureAtom():PictureAtom
    {
        if (atom == null || isDisposed) return null;
        if (!Std.isOfType(atom, PictureAtom)) return null;
        return cast(atom, PictureAtom);
    }

    private static function _toFixed(value:Float, decimals:Int = 1):String
    {
        if (Math.isNaN(value) || !Math.isFinite(value)) return "0.0";

        var multiplier:Float = Math.pow(10, decimals);
        var rounded:Float = Math.round(value * multiplier) / multiplier;
        var s:String = Std.string(rounded);

        if (s.indexOf(".") == -1)
        {
            s += ".";
            for (_ in 0...decimals) s += "0";
            return s;
        }

        var parts:Array<String> = s.split(".");
        var frac:String = parts[1];
        while (frac.length < decimals) frac += "0";

        return parts[0] + "." + frac;
    }

    // =========================================================================
    // TRANSFORM PARSING (contact value -> UI mirror; tolerant, same guards
    // as the atom: NaN/garbage keep the current value, scale<=0 -> 1,
    // alpha clamped 0..1)
    // =========================================================================

    /** Read all transform contacts into the UI mirror (activate path). */
    private function syncTransformMirror():Void
    {
        if (_posXContact != null && _posXContact.value != null) _tPosX = parseFloat(_posXContact.value, _tPosX);
        if (_posYContact != null && _posYContact.value != null) _tPosY = parseFloat(_posYContact.value, _tPosY);
        if (_widthContact != null && _widthContact.value != null) _tSizeW = parseFloat(_widthContact.value, _tSizeW);
        if (_heightContact != null && _heightContact.value != null) _tSizeH = parseFloat(_heightContact.value, _tSizeH);
        if (_scaleXContact != null && _scaleXContact.value != null) _tScaleX = parseScale(_scaleXContact.value, _tScaleX);
        if (_scaleYContact != null && _scaleYContact.value != null) _tScaleY = parseScale(_scaleYContact.value, _tScaleY);
        if (_visibleContact != null && _visibleContact.value != null) _tVisible = (_visibleContact.value == true);
        if (_alphaContact != null && _alphaContact.value != null) _tAlpha = clamp01(parseFloat(_alphaContact.value, _tAlpha));
        if (_zOrderContact != null && _zOrderContact.value != null) _tZOrder = Math.round(parseFloat(_zOrderContact.value, _tZOrder));
    }

    private static function parseFloat(v:Dynamic, current:Float):Float
    {
        var f:Float = Std.parseFloat(Std.string(v));
        if (Math.isNaN(f) || !Math.isFinite(f)) return current;
        return f;
    }

    private static function parseScale(v:Dynamic, current:Float):Float
    {
        var f:Float = parseFloat(v, current);
        return (f <= 0) ? 1 : f;
    }

    private static function clamp01(v:Float):Float
    {
        if (v < 0) return 0;
        if (v > 1) return 1;
        return v;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (isDisposed) return;

        if (_imageHolder != null)
        {
            _imageHolder.removeEventListener(MouseEvent.MOUSE_DOWN, onImageMouseDown);
        }
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onStageMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onStageMouseUp);
        }

        disposeBitmap();

        _bg = null;
        _header = null;
        _titleLabel = null;
        _statusLed = null;
        _statusGlow = null;
        _infoLabel = null;
        _errorLabel = null;
        _imageHolder = null;
        _placeholder = null;
        _placeholderLabel = null;
        _bitmap = null;

        _imageContact = null;
        _clearContact = null;
        _posXContact = null;
        _posYContact = null;
        _widthContact = null;
        _heightContact = null;
        _scaleXContact = null;
        _scaleYContact = null;
        _visibleContact = null;
        _alphaContact = null;
        _zOrderContact = null;
        _okContact = null;
        _kindContact = null;
        _imgWidthContact = null;
        _imgHeightContact = null;
        _errorContact = null;
        _loadedTickContact = null;
        _errorTickContact = null;

        super.dispose();
    }
}
