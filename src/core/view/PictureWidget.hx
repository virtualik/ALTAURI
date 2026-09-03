package core.view;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.Event;
import lime.graphics.Image;
import core.base.Atom;
import core.base.Contact;
import ui.DeviceCard;
import core.view.DeviceViewRegistry;
import library.drivers.PictureAtom;

/**
 * PICTURE WIDGET v1.2 (Task 159 — the "bare canvas" dual face)
 * The Face of PictureAtom (Stage 4a-3, Task 155; hotfix Task 156).
 * Spec: SPEC_STAGE4A_PICTURE.md §5, §13.
 *
 * DUAL FACE (v1.2, the pilot's design):
 *   · EDITOR face (NodeView, "Heavy" embed): the classic framed card —
 *     header / LED / info / error lines, and the image NORMALIZED to fit
 *     the card's image area with the aspect preserved (contain fit).
 *     NO makeup contact applies here: the editor preview is passive
 *     (pos/scale/alpha of the atom's node are the node view's business).
 *   · DEVICE face (DevicePanel / DeviceWindow): the BARE bitmap — no
 *     frame, no labels, no placeholder, no drag, fully mouse-transparent
 *     (clicks fall through to the cards underneath, pilot decision D4).
 *     The contacts are the ONLY placement source: posX/posY position the
 *     phantom DeviceCard ALWAYS (0,0 = panel origin); width/height
 *     (0 = natural) * scaleX/scaleY size the bitmap exactly (aspect
 *     derivation below); visible & enabled gate it, alpha tints it;
 *     zOrder (>=1) drives the DevicePanel z-system (insert semantics,
 *     v3.12); zOrder <= 0 = "the surface" = auto order stays.
 *
 * ASPECT (v1.2, [aspect] contact): true = keep proportions — a width
 *   edit derives height (natW/natH) and a height edit derives width;
 *   the LAST size edit wins (_lastSizeEdit tracks the wire event; the
 *   widget owns the derivation because it owns the event). false or
 *   absent = width/height apply verbatim (exact control). The device
 *   face renders 0/0 sizes at NATURAL size (no auto-contain on the
 *   panel — the editor face is where normalization lives).
 *
 * MODE SWITCH: the DeviceViewRegistry container type (NodeView /
 * DeviceWindow) is the mode source. moveToDeviceWindow()/moveToNodeView()
 * set it AFTER addChild — so an Event.ADDED handler schedules a one-frame
 * deferred applyMode() (the registry record is final by then); the
 * activate()/syncFromAtom() path re-applies it immediately. The frameless
 * phantom card is requested via isFramelessWidget() (DeviceView v1.2).
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
    private var _aspectContact:Contact;
    private var _visibleContact:Contact;
    private var _enabledContact:Contact;
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
    // v1.2: the aspect derivation (width<->height) also lives here — the
    // widget owns the LAST-EDIT event, which is what the derivation needs.
    private var _tPosX:Float = 0;
    private var _tPosY:Float = 0;
    private var _tSizeW:Float = 0;
    private var _tSizeH:Float = 0;
    private var _tScaleX:Float = 1;
    private var _tScaleY:Float = 1;
    private var _tAspect:Bool = false;
    private var _tVisible:Bool = true;
    private var _tEnabled:Bool = true;
    private var _tAlpha:Float = 1;
    private var _tZOrder:Int = 0;

    /** Which size contact fired LAST ("width" | "height" | null) —
     *  the aspect-derivation tiebreaker (last edit wins). */
    private var _lastSizeEdit:String = null;

    /** Last zOrder value actually pushed into the panel z-system
     *  (dedupe guard — the panel insert renumbers the whole tail). */
    private var _appliedZ:Int = -1;

    /** One-frame deferred mode refresh is scheduled (Event.ADDED path). */
    private var _modeRefreshScheduled:Bool = false;

    /** CACHED closure for the one-frame tick: ONE object is used for both
     *  add and remove — a fresh method reference may not compare equal on
     *  eval/hxcpp (the T155 stage-listener lesson, applied to ENTER_FRAME). */
    private var _modeTickRef:Event -> Void;

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

        // v1.2: reparent awareness — moveToDeviceWindow()/moveToNodeView()
        // call addChild BEFORE setting the registry container type, so the
        // mode application is deferred by one frame (the registry record is
        // final by then). Only OUR OWN additions count (children bubble ADDED).
        _modeTickRef = onModeRefreshTick;
        addEventListener(Event.ADDED, onWidgetAdded);
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
        _aspectContact = atom.getInput("aspect");
        _visibleContact = atom.getInput("visible");
        _enabledContact = atom.getInput("enabled");
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
    // DUAL-FACE MODE (v1.2)
    // =========================================================================

    /** Registry container type drives the face: DeviceWindow (panel or
     *  separate window) = the bare device face; NodeView = the editor
     *  card face; null/unknown = the editor face (the safe default). */
    private function isDeviceMode():Bool
    {
        return getContainerType() == DeviceViewRegistry.CONTAINER_DEVICE_WINDOW;
    }

    /** Our own reparent happened — the registry record may still be the OLD
     *  one (moveToDeviceWindow sets it after addChild), so apply the mode
     *  one frame later. Children bubbling ADDED are ignored. */
    private function onWidgetAdded(e:Event):Void
    {
        if (e.target != this) return;
        if (isDisposed) return;
        if (_modeRefreshScheduled) return;
        _modeRefreshScheduled = true;
        addEventListener(Event.ENTER_FRAME, _modeTickRef);
    }

    private function onModeRefreshTick(e:Event):Void
    {
        removeEventListener(Event.ENTER_FRAME, _modeTickRef);
        _modeRefreshScheduled = false;
        if (isDisposed) return;
        applyMode();
    }

    /**
     * Apply the current face: chrome visibility, mouse transparency,
     * holder anchoring, then the full geometry pass. Cheap — called on
     * activate, on reparent (deferred) and from syncFromAtom.
     */
    private function applyMode():Void
    {
        if (isDisposed) return;
        var deviceMode:Bool = isDeviceMode();

        // Chrome: the editor face keeps the full framed card; the device
        // face is the bare bitmap (no frame, no labels, no placeholder).
        var chrome:Bool = !deviceMode;
        _bg.visible = chrome;
        _header.visible = chrome;
        _infoLabel.visible = chrome;
        _errorLabel.visible = chrome;
        showPlaceholder(_bitmap == null); // device face: suppressed inside

        // Mouse: the bare image is fully transparent for the mouse (D4) —
        // clicks fall through to the cards underneath. The editor face
        // keeps the DeviceView mouse isolation.
        this.mouseEnabled = chrome;
        this.mouseChildren = false;

        // Anchoring: the bare face starts at the card origin (the card is
        // positioned by posX/posY); the editor face uses the inset area.
        if (!deviceMode)
        {
            _imageHolder.x = AREA_X;
            _imageHolder.y = AREA_Y;
        }

        // Re-apply the geometry for the face that is now active.
        applyTransform();
        applyCardPlacement();
    }

    /** Placeholder is an EDITOR-only courtesy — the bare panel stays bare. */
    private function showPlaceholder(v:Bool):Void
    {
        _placeholder.visible = v && !isDeviceMode();
    }

    /** The device face wants a frameless phantom DeviceCard (DeviceView
     *  v1.2 contract, DeviceCard v1.1 frameless mode). */
    override public function isFramelessWidget():Bool
    {
        return true;
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

        // v1.2: no drag hooks on the image — the device face is anchored by
        // contacts (D4/D5, pilot decision); the editor face is passive.

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
        applyMode();
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
            // v1.2: a new picture re-runs the fit (editor contain / device
            // natural+scale) — the natural size changed under the mirrors.
            applyTransform();
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
            || contact == _aspectContact || contact == _visibleContact
            || contact == _enabledContact || contact == _alphaContact)
        {
            // v1.2: track the LAST size edit — the aspect-derivation
            // tiebreaker ("I set a new width → height follows", and vice
            // versa; last edit wins, SPEC §13).
            if (contact == _widthContact) _lastSizeEdit = "width";
            if (contact == _heightContact) _lastSizeEdit = "height";

            if (contact == _widthContact && newValue != null) _tSizeW = parseFloat(newValue, _tSizeW);
            if (contact == _heightContact && newValue != null) _tSizeH = parseFloat(newValue, _tSizeH);
            if (contact == _scaleXContact && newValue != null) _tScaleX = parseScale(newValue, _tScaleX);
            if (contact == _scaleYContact && newValue != null) _tScaleY = parseScale(newValue, _tScaleY);
            if (contact == _aspectContact) _tAspect = (newValue == true);
            if (contact == _visibleContact && newValue != null) _tVisible = (newValue == true);
            if (contact == _enabledContact) _tEnabled = (newValue == true);
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
            // Cleared state: the placeholder is the honest (editor) face.
            showPlaceholder(true);
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
            showPlaceholder(true);
            updateConnectionStatus(false);
            return;
        }

        _bitmap = new Bitmap(bmd);
        _imageHolder.addChild(_bitmap);
        showPlaceholder(false);
        a.clearFault();
        updateConnectionStatus(true);
        trace('PictureWidget: decoded ${bytes.length} bytes -> ${bmd.width}x${bmd.height} (path=${_lastDecodePath})');
        // v1.2: the new bitmap needs its face geometry immediately (the
        // status wave arrives before any transform contact may fire).
        applyTransform();
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

        // ── Path E: temp-file roundtrip (sys targets only) ──
        // Sys.* and sys.io.File are unavailable on html5/flash; on those
        // targets Path E is skipped entirely and decode falls back to
        // Path F (or returns null). Path E is the last-resort native
        // codec roundtrip and only makes sense where a filesystem exists.
        #if sys
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
        #else
        _decodeTrace.push("E:skip:non-sys");
        #end
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
	 *
	 * NOTE: Sys.* is available on sys targets (cpp/neko/php/python/hl/lua)
	 * but NOT on html5 (js) or flash. On non-sys targets we return an empty
	 * string: callers MUST guard Path E usage with #if sys so the roundtrip
	 * is skipped entirely in the browser (use openfl.Assets / BitmapData
	 * path instead — Path A/B/C, whichever the widget already supports).
	 */
	private function tempPicturePath(kind:String):String
	{
		var dir:String = "./";

		#if sys
		try
		{
			var t:String = Sys.getEnv("TEMP");
			if (t == null) t = Sys.getEnv("TMP");
			if (t == null) t = Sys.getEnv("TMPDIR");
			if (t != null && t != "") dir = t;
		}
		catch (e:Dynamic)
		{
			// keep dir = "./"
		}
		#end

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
    // "MAKEUP" GEOMETRY (v1.2 — the dual face)
    // =========================================================================

    /** Dispatcher: the editor face normalizes, the device face obeys
     *  the contacts (SPEC §13). */
    private function applyTransform():Void
    {
        if (isDeviceMode()) applyDeviceTransform();
        else applyEditorPreview();
    }

    /**
     * EDITOR FACE: fit the image into the card's image area with the
     * aspect preserved (contain), centered. NONE of the makeup contacts
     * applies — the editor preview is passive (the pilot's rule: the
     * editor widget "just shows the picture fitted, no parameters").
     */
    private function applyEditorPreview():Void
    {
        _imageHolder.visible = true;
        _imageHolder.alpha = 1;

        if (_bitmap == null || _bitmap.bitmapData == null)
        {
            showPlaceholder(true);
            return;
        }
        showPlaceholder(false);

        var bmd:BitmapData = _bitmap.bitmapData;
        if (bmd.width <= 0 || bmd.height <= 0) return;

        var natW:Int = (_imgW > 0) ? _imgW : bmd.width;
        var natH:Int = (_imgH > 0) ? _imgH : bmd.height;

        // Contain fit: scale to fit BOTH dimensions, keep the aspect.
        var k:Float = Math.min(AREA_W / natW, AREA_H / natH);
        if (Math.isNaN(k) || !Math.isFinite(k) || k <= 0) k = 1;

        var targetW:Float = natW * k;
        var targetH:Float = natH * k;

        // Center inside the image area
        _imageHolder.x = AREA_X + (AREA_W - targetW) / 2;
        _imageHolder.y = AREA_Y + (AREA_H - targetH) / 2;

        _bitmap.scaleX = targetW / bmd.width;
        _bitmap.scaleY = targetH / bmd.height;
    }

    /**
     * DEVICE FACE: the bare bitmap, contacts are the ONLY source:
     *   W = (width > 0 ? width : naturalW) * scaleX
     *   H = (height > 0 ? height : naturalH) * scaleY
     * with [aspect] derivation applied first (last edit wins);
     * visible AND enabled gate the holder, alpha tints it. No auto-fit
     * here — the device face is exact (0 = natural size, the pilot's
     * decision: normalization lives in the editor face).
     */
    private function applyDeviceTransform():Void
    {
        _imageHolder.x = 0;
        _imageHolder.y = 0;

        var show:Bool = _tVisible && _tEnabled; // enabled = render gate
        _imageHolder.visible = show;
        _imageHolder.alpha = _tAlpha;

        if (_bitmap == null || _bitmap.bitmapData == null) return;
        var bmd:BitmapData = _bitmap.bitmapData;
        if (bmd.width <= 0 || bmd.height <= 0) return;

        deriveAspect();

        var natW:Int = (_imgW > 0) ? _imgW : bmd.width;
        var natH:Int = (_imgH > 0) ? _imgH : bmd.height;

        var targetW:Float = ((_tSizeW > 0) ? _tSizeW : natW) * _tScaleX;
        var targetH:Float = ((_tSizeH > 0) ? _tSizeH : natH) * _tScaleY;

        _bitmap.scaleX = targetW / bmd.width;
        _bitmap.scaleY = targetH / bmd.height;
    }

    /**
     * [aspect] derivation (v1.2): true = keep the natural proportions —
     * the LAST size edit wins: a width edit derives the height, a height
     * edit derives the width (the pilot's exact rule). Without a known
     * last edit (fresh restore) both values apply verbatim — the wires
     * re-deliver them in a deterministic order and the first callback
     * sets the tiebreaker.
     */
    private function deriveAspect():Void
    {
        if (!_tAspect) return;
        if (_imgW <= 0 || _imgH <= 0) return;

        var ratio:Float = _imgW / _imgH;
        if (Math.isNaN(ratio) || !Math.isFinite(ratio) || ratio <= 0) return;

        if (_lastSizeEdit == "width" && _tSizeW > 0)
        {
            _tSizeH = _tSizeW / ratio;
        }
        else if (_lastSizeEdit == "height" && _tSizeH > 0)
        {
            _tSizeW = _tSizeH * ratio;
        }
    }

    /**
     * Apply the panel-level "makeup" — DEVICE FACE ONLY (the editor node
     * keeps its own layout business):
     *   · posX/posY place the parent (phantom) DeviceCard ALWAYS — the
     *     contacts are the only placement source (0,0 = panel origin;
     *     the panel's auto-position is overridden on the first sync);
     *   · zOrder (>=1) asks the panel z-system to INSERT the card at that
     *     slot (renumbering the tail, DevicePanel v3.12); zOrder <= 0 =
     *     "the surface itself" — auto order stays (pilot's rule).
     *
     * Reflect note: the card/panel are accessed through Reflect properties —
     * openfl geometry (x/y/parent/numChildren) may be real properties (get/set)
     * where raw Dynamic field access silently misses them.
     */
    private function applyCardPlacement():Void
    {
        if (!isDeviceMode()) return;

        var card:Dynamic = parent;
        if (card == null || !Std.isOfType(card, DeviceCard)) return;

        // ALWAYS: contacts are the placement source (v1.2 semantics —
        // the phantom card has no drag, no auto-position of its own).
        Reflect.setProperty(card, "x", _tPosX);
        Reflect.setProperty(card, "y", _tPosY);

        // Apply zOrder only if changed (dedupe guard - Picture pattern)
        if (_tZOrder >= 1 && _tZOrder != _appliedZ)
        {
            var panel:Dynamic = Reflect.getProperty(card, "parent");
            // NOTE: Reflect.hasField() does NOT see class methods on the C++
            // target — probe with Reflect.field() instead.
            var setZ:Dynamic = panel != null ? Reflect.field(panel, "setCardZOrder") : null;
            // Panel not ready yet (the card is attached after the widget's
            // activation pass) — leave the guard unconsumed so the panel's
            // refreshPlacement() hook can re-apply later.
            if (setZ == null) return;

            _appliedZ = _tZOrder;
            try
            {
                Reflect.callMethod(panel, setZ, [card, _tZOrder]);
            }
            catch (e:Dynamic)
            {
                // exotic owner (e.g. DeviceWindow without the z-system) —
                // honest no-op: the depth stays auto there
            }
        }
    }

    // Panel calls this after the card is attached — the correctly-timed
    // pass that onActivate() could not complete (see DeviceView hook).
    override public function refreshPlacement():Void
    {
        applyCardPlacement();
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
        if (_aspectContact != null && _aspectContact.value != null) _tAspect = (_aspectContact.value == true);
        if (_visibleContact != null && _visibleContact.value != null) _tVisible = (_visibleContact.value == true);
        if (_enabledContact != null && _enabledContact.value != null) _tEnabled = (_enabledContact.value == true);
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

        // v1.2: mode-refresh plumbing (cached ref — the T155 closure lesson)
        removeEventListener(Event.ADDED, onWidgetAdded);
        removeEventListener(Event.ENTER_FRAME, _modeTickRef);
        _modeRefreshScheduled = false;
        _modeTickRef = null;

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
        _aspectContact = null;
        _visibleContact = null;
        _enabledContact = null;
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
