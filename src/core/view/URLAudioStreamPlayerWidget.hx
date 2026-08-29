package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.FocusEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;

/**
 * URL AUDIO STREAM PLAYER WIDGET v2.1 (Task 102, series URL_RADIO;
 * W-SYNC.1: live contact→field mirror for url/volume + edit guards)
 *
 * Reconstructed to match the standard atom face (WebSocket / ComPort style):
 * header bar with status LED + glow, URL field, PLAY/STOP action buttons,
 * volume input, NOW PLAYING panel (ICY metadata from the atom's v2.0
 * title/artist/track outputs), status bar and error display.
 *
 * ┌────────────────────────────────────────────┐
 * │  URL AUDIO PLAYER                    ● LED │  ← header (28px)
 * ├────────────────────────────────────────────┤
 * │  STREAM URL                                │
 * │  [http://..._____________________________] │
 * │                                            │
 * │  [ PLAY ]  [ STOP ]    VOL [1.0]           │
 * │  Status: Playing                           │
 * ├────────────────────────────────────────────┤
 * │  NOW PLAYING                               │  ← section panel
 * │  Artist                                    │
 * │  Track                                     │
 * ├────────────────────────────────────────────┤
 * │  Last error: (none)                        │
 * └────────────────────────────────────────────┘
 *
 * Architecture: "Atom is Databank & Compute Core"
 *   - Widget is the FACE (Component C) of the Atom
 *   - Reads all data from Atom's contacts via onContactChanged()
 *   - Writes user input to Atom's contacts (no direct backend access)
 *   - Stores NO business data — only UI state
 *
 * Default management controls (URL / PLAY / STOP / VOL) are provided until
 * the user wires their own Button and Indicator atoms — the widget is the
 * fallback control surface, wires are the primary one.
 *
 * URL field commits on ENTER (and on PLAY click / deactivation WHEN the
 * user actually edited the field) — NOT on every keystroke, so editing
 * the URL while playing does not hot-switch the stream per character.
 *
 * W-SYNC.1 doctrine ("Atom is Databank"):
 *  - url/volume contacts are mirrored LIVE into the fields (contact→field),
 *    except while the user is editing the field (focus guard);
 *  - PLAY/deactivation commit the field back (field→contact) ONLY if the
 *    user actually modified it (_urlEdited) — a stale default placeholder
 *    can never clobber a legitimate URL set through the contact by wires.
 *
 * Mouse isolation is handled automatically by DeviceView base class (v3.4).
 * Keyboard events in the URL field are stopped from bubbling to the editor.
 */
class URLAudioStreamPlayerWidget extends DeviceView
{
    // =========================================================================
    // LAYOUT
    // =========================================================================
    public var widgetWidth:Float = 320;
    public var widgetHeight:Float = 196;

    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    // ── Color palette (dark theme, matches WebSocketWidget/ComPortWidget) ──
    private var _colorBg:Int        = 0x1a1a24;
    private var _colorHeader:Int    = 0x2a2a3a;
    private var _colorAccent:Int    = 0x00AAFF;
    private var _colorActive:Int    = 0x00FF88;
    private var _colorDanger:Int    = 0xFF4444;
    private var _colorWarn:Int      = 0xFFAA00;
    private var _colorMuted:Int     = 0x888899;
    private var _colorText:Int      = 0xFFFFFF;
    private var _colorInputBg:Int   = 0x0d0d18;

    // =========================================================================
    // UI ELEMENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;

    // URL section
    private var _urlLabel:TextField;
    private var _urlInput:TextField;

    // Transport section
    private var _playBtn:Sprite;
    private var _stopBtn:Sprite;
    private var _volLabel:TextField;
    private var _volInput:TextField;

    // Now playing section
    private var _nowPlayingSection:Sprite;
    private var _npCaption:TextField;
    private var _npArtist:TextField;
    private var _npTrack:TextField;

    // Status / error
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    private var _statusBar:TextField;
    private var _errorDisplay:TextField;

    // =========================================================================
    // CONTACT REFERENCES
    // =========================================================================
    private var _urlContact:Contact;
    private var _playContact:Contact;
    private var _volumeContact:Contact;
    private var _isPlayingContact:Contact;
    private var _isBufferingContact:Contact;
    private var _errorContact:Contact;
    private var _stateContact:Contact;
    private var _titleContact:Contact;
    private var _artistContact:Contact;
    private var _trackContact:Contact;

    // =========================================================================
    // UI STATE (display cache only — no business data)
    // =========================================================================
    // W-SYNC.1: editing guards (focus) + dirty flag (user actually typed)
    private var _isEditingUrl:Bool = false;
    private var _isEditingVol:Bool = false;
    private var _urlEdited:Bool = false;

    private var _isPlaying:Bool = false;
    private var _isBuffering:Bool = false;
    private var _stateInt:Int = 0;
    private var _title:String = "";
    private var _artist:String = "";
    private var _track:String = "";

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

    private function findContacts():Void
    {
        if (atom == null) return;

        _urlContact        = atom.getInput("url");
        _playContact       = atom.getInput("play");
        _volumeContact     = atom.getInput("volume");

        _isPlayingContact  = atom.getOutput("isPlaying");
        _isBufferingContact = atom.getOutput("isBuffering");
        _errorContact      = atom.getOutput("error");
        _stateContact      = atom.getOutput("state");
        _titleContact      = atom.getOutput("title");
        _artistContact     = atom.getOutput("artist");
        _trackContact      = atom.getOutput("track");
    }

    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }

    /**
     * Flush transient UI state to the atom's databank before deactivation:
     * a typed-but-not-committed URL / volume must not be lost.
     */
    override private function flushTransientState():Void
    {
        // W-SYNC.1: commit the field ONLY when the user actually edited it —
        // an untouched placeholder ("http://") must never clobber a
        // legitimate URL set through the contact by wires.
        if (_urlContact != null && _urlInput != null && _urlEdited && _urlInput.text != "")
        {
            _urlContact.value = _urlInput.text;
            _urlEdited = false;
        }
        if (_volumeContact != null && _volInput != null)
        {
            var vol:Float = Std.parseFloat(_volInput.text);
            if (!Math.isNaN(vol) && vol >= 0.0 && vol <= 2.0)
            {
                _volumeContact.value = vol;
            }
        }
    }

    // =========================================================================
    // UI BUILDING
    // =========================================================================
    private function buildUI():Void
    {
        var yPos:Float = 0;

        // ── Background ──
        _bg = new Sprite();
        addChild(_bg);

        // ── Header ──
        _header = new Sprite();
        _header.y = yPos;
        addChild(_header);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = " URL AUDIO PLAYER";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // Status glow (behind LED, visible when playing)
        _statusGlow = new Sprite();
        _statusGlow.graphics.beginFill(_colorActive, 0.2);
        _statusGlow.graphics.drawCircle(0, 0, 12);
        _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 18;
        _statusGlow.y = 14;
        _statusGlow.visible = false;
        _header.addChild(_statusGlow);

        // Status LED
        _statusLed = new Sprite();
        _statusLed.graphics.beginFill(0x444444);
        _statusLed.graphics.drawCircle(0, 0, 6);
        _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 18;
        _statusLed.y = 14;
        _header.addChild(_statusLed);

        yPos += 32;

        // ── URL section ──
        _urlLabel = createLabel("STREAM URL", Std.int(widgetWidth - 20));
        _urlLabel.y = yPos;
        addChild(_urlLabel);
        yPos += 16;

        _urlInput = createInputField("http://", Std.int(widgetWidth - 20));
        _urlInput.x = 10;
        _urlInput.y = yPos;
        _urlInput.addEventListener(KeyboardEvent.KEY_DOWN, onUrlKeyDown);
        _urlInput.addEventListener(Event.CHANGE, onUrlTextChanged);
        _urlInput.addEventListener(FocusEvent.FOCUS_IN, onUrlFocusIn);
        _urlInput.addEventListener(FocusEvent.FOCUS_OUT, onUrlFocusOut);
        addChild(_urlInput);
        yPos += 30;

        // ── Transport: PLAY / STOP / VOL ──
        _playBtn = createActionButton("PLAY", 0x225533, onPlayClick);
        _playBtn.x = 10;
        _playBtn.y = yPos;
        addChild(_playBtn);

        _stopBtn = createActionButton("STOP", 0x553322, onStopClick);
        _stopBtn.x = 95;
        _stopBtn.y = yPos;
        addChild(_stopBtn);

        _volLabel = new TextField();
        _volLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _volLabel.text = "VOL:";
        _volLabel.width = 30;
        _volLabel.height = 14;
        _volLabel.x = 182;
        _volLabel.y = yPos + 6;
        _volLabel.selectable = false;
        _volLabel.mouseEnabled = false;
        addChild(_volLabel);

        _volInput = createInputField("1.0", 56);
        _volInput.x = 214;
        _volInput.y = yPos + 2;
        _volInput.addEventListener(Event.CHANGE, onVolumeChanged);
        _volInput.addEventListener(FocusEvent.FOCUS_IN, onVolFocusIn);
        _volInput.addEventListener(FocusEvent.FOCUS_OUT, onVolFocusOut);
        addChild(_volInput);

        // Status bar (right of transport row, below buttons)
        yPos += 32;

        _statusBar = new TextField();
        _statusBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statusBar.text = "Status: Idle";
        _statusBar.width = widgetWidth - 20;
        _statusBar.height = 15;
        _statusBar.x = 10;
        _statusBar.y = yPos;
        _statusBar.selectable = false;
        addChild(_statusBar);

        yPos += 18;

        // ── NOW PLAYING section ──
        _nowPlayingSection = new Sprite();
        _nowPlayingSection.y = yPos;
        addChild(_nowPlayingSection);

        _npCaption = new TextField();
        _npCaption.defaultTextFormat = new TextFormat("_typewriter", 8, _colorMuted);
        _npCaption.text = " NOW PLAYING";
        _npCaption.width = widgetWidth - 20;
        _npCaption.height = 12;
        _npCaption.x = 5;
        _npCaption.y = 3;
        _npCaption.selectable = false;
        _npCaption.mouseEnabled = false;
        _nowPlayingSection.addChild(_npCaption);

        _npArtist = new TextField();
        _npArtist.defaultTextFormat = new TextFormat("_typewriter", 10, _colorActive, true);
        _npArtist.text = "—";
        _npArtist.width = widgetWidth - 20;
        _npArtist.height = 14;
        _npArtist.x = 10;
        _npArtist.y = 14;
        _npArtist.selectable = false;
        _npArtist.mouseEnabled = false;
        _nowPlayingSection.addChild(_npArtist);

        _npTrack = new TextField();
        _npTrack.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _npTrack.text = "";
        _npTrack.width = widgetWidth - 20;
        _npTrack.height = 13;
        _npTrack.x = 10;
        _npTrack.y = 28;
        _npTrack.selectable = false;
        _npTrack.mouseEnabled = false;
        _nowPlayingSection.addChild(_npTrack);

        yPos += 44;

        // ── Error display ──
        _errorDisplay = new TextField();
        _errorDisplay.defaultTextFormat = new TextFormat("_typewriter", 9, _colorDanger);
        _errorDisplay.text = "";
        _errorDisplay.width = widgetWidth - 20;
        _errorDisplay.height = 15;
        _errorDisplay.x = 10;
        _errorDisplay.y = yPos;
        _errorDisplay.selectable = false;
        addChild(_errorDisplay);

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

        _nowPlayingSection.graphics.clear();
        _nowPlayingSection.graphics.beginFill(_colorInputBg, 0.5);
        _nowPlayingSection.graphics.lineStyle(1, 0x224466);
        _nowPlayingSection.graphics.drawRoundRect(5, 0, widgetWidth - 10, 41, 4, 4);
        _nowPlayingSection.graphics.endFill();
    }

    // =========================================================================
    // UI HELPERS (WebSocketWidget pattern)
    // =========================================================================
    private function createLabel(text:String, width:Int):TextField
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        tf.text = text;
        tf.width = width;
        tf.height = 14;
        tf.x = 10;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createInputField(defaultText:String, width:Int):TextField
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText);
        tf.text = defaultText;
        tf.width = width;
        tf.height = 22;
        tf.background = true;
        tf.backgroundColor = _colorInputBg;
        tf.border = true;
        tf.borderColor = 0x333355;
        tf.type = TextFieldType.INPUT;
        tf.selectable = true;
        tf.mouseEnabled = true;
        return tf;
    }

    private function createActionButton(label:String, color:Int, callback:MouseEvent -> Void):Sprite
    {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRoundRect(0, 0, 77, 26, 4, 4);
        btn.graphics.endFill();
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true);
        tf.text = label;
        tf.width = 77;
        tf.height = 26;
        tf.selectable = false;
        tf.mouseEnabled = false;
        btn.addChild(tf);
        btn.buttonMode = true;
        btn.useHandCursor = true;
        btn.addEventListener(MouseEvent.CLICK, callback);
        return btn;
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    /**
     * URL field: commit on ENTER. All key events are stopped from bubbling
     * to the editor so typing a URL never triggers editor hotkeys.
     */
    private function onUrlKeyDown(e:KeyboardEvent):Void
    {
        if (e.keyCode == Keyboard.ENTER)
        {
            if (_urlContact != null)
            {
                _urlContact.value = _urlInput.text;
            }
            _urlEdited = false;
            if (stage != null) stage.focus = null;
        }
        e.stopPropagation();
    }

    /** W-SYNC.1: user modified the URL field (gate for PLAY/flush commits). */
    private function onUrlTextChanged(e:Event):Void
    {
        _urlEdited = true;
    }

    /** W-SYNC.1: focus guards — the live mirror is suppressed while typing. */
    private function onUrlFocusIn(e:FocusEvent):Void
    {
        _isEditingUrl = true;
    }

    private function onUrlFocusOut(e:FocusEvent):Void
    {
        _isEditingUrl = false;
    }

    private function onVolFocusIn(e:FocusEvent):Void
    {
        _isEditingVol = true;
    }

    private function onVolFocusOut(e:FocusEvent):Void
    {
        _isEditingVol = false;
        // Leaving the volume field: normalize display to the committed value
        if (_volInput != null && _volumeContact != null && _volumeContact.value != null)
        {
            var volStr:String = Std.string(_volumeContact.value);
            if (_volInput.text != volStr) _volInput.text = volStr;
        }
    }

    /**
     * Volume input changed — parse as Float, clamp 0.0..2.0, push to atom.
     */
    private function onVolumeChanged(e:Event):Void
    {
        if (_volInput == null || _volumeContact == null) return;
        var vol:Float = Std.parseFloat(_volInput.text);
        if (Math.isNaN(vol)) return;
        if (vol < 0.0) vol = 0.0;
        if (vol > 2.0) vol = 2.0;
        _volumeContact.value = vol;
    }

    /**
     * PLAY clicked — commit the typed URL first, then raise the play contact.
     */
    private function onPlayClick(e:MouseEvent):Void
    {
        // W-SYNC.1: commit ONLY a user-edited field. The atom's url contact
        // is the source of truth — PLAY must never clobber a legitimate URL
        // (set through the contact by wires) with a stale field placeholder.
        if (_urlContact != null && _urlInput != null && _urlEdited && _urlInput.text != "")
        {
            _urlContact.value = _urlInput.text;
            _urlEdited = false;
        }
        if (_playContact != null)
        {
            _playContact.value = true;
        }
    }

    /**
     * STOP clicked — lower the play contact (intentional stop; the atom
     * resets its fault latch and clears stale metadata).
     */
    private function onStopClick(e:MouseEvent):Void
    {
        if (_playContact != null)
        {
            _playContact.value = false;
        }
    }

    // =========================================================================
    // DATA SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
        if (_urlContact != null && _urlContact.value != null)
        {
            var url:String = Std.string(_urlContact.value);
            if (_urlInput != null && _urlInput.text != url && url != "")
            {
                _urlInput.text = url;
                _urlEdited = false;
            }
        }

        if (_volumeContact != null && _volumeContact.value != null && _volInput != null)
        {
            var volStr:String = Std.string(_volumeContact.value);
            if (_volInput.text != volStr)
            {
                _volInput.text = volStr;
            }
        }

        updateState();
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;

        // W-SYNC.1: LIVE MIRROR contact → field ("Atom is Databank").
        // Guard: never clobber a field the user is editing right now.
        if (contact == _urlContact && !_isEditingUrl)
        {
            if (newValue != null)
            {
                var urlStr:String = Std.string(newValue);
                if (urlStr != "" && _urlInput != null && _urlInput.text != urlStr)
                {
                    _urlInput.text = urlStr;
                    _urlEdited = false;
                }
            }
        }
        else if (contact == _volumeContact && !_isEditingVol)
        {
            if (newValue != null && _volInput != null)
            {
                var volStr:String = Std.string(newValue);
                if (_volInput.text != volStr) _volInput.text = volStr;
            }
        }

        updateState();
    }

    /**
     * Project all cached atom outputs onto the visual state:
     * LED + glow, status bar, now-playing panel, error display.
     */
    private function updateState():Void
    {
        if (_isPlayingContact != null && _isPlayingContact.value != null)
        {
            _isPlaying = (_isPlayingContact.value == true);
        }
        if (_isBufferingContact != null && _isBufferingContact.value != null)
        {
            _isBuffering = (_isBufferingContact.value == true);
        }
        if (_stateContact != null && _stateContact.value != null)
        {
            _stateInt = Std.int(_stateContact.value);
        }
        if (_titleContact != null && _titleContact.value != null)
        {
            _title = Std.string(_titleContact.value);
        }
        if (_artistContact != null && _artistContact.value != null)
        {
            _artist = Std.string(_artistContact.value);
        }
        if (_trackContact != null && _trackContact.value != null)
        {
            _track = Std.string(_trackContact.value);
        }

        updateLed();
        updateStatusBar();
        updateNowPlaying();
        updateError();
    }

    private function updateLed():Void
    {
        var ledColor:Int = 0x444444;
        if (_isBuffering || _stateInt == 1 || _stateInt == 3) ledColor = _colorWarn;
        else if (_isPlaying) ledColor = _colorActive;
        else if (_stateInt == 4) ledColor = _colorDanger;

        _statusLed.graphics.clear();
        _statusLed.graphics.beginFill(ledColor);
        _statusLed.graphics.drawCircle(0, 0, 6);
        _statusLed.graphics.endFill();

        _statusGlow.visible = _isPlaying;
        if (_isPlaying)
        {
            _statusGlow.graphics.clear();
            _statusGlow.graphics.beginFill(_colorActive, 0.2);
            _statusGlow.graphics.drawCircle(0, 0, 12);
            _statusGlow.graphics.endFill();
        }
    }

    private function updateStatusBar():Void
    {
        if (_isBuffering)
        {
            _statusBar.text = "Status: Buffering...";
            _statusBar.textColor = _colorWarn;
        }
        else if (_isPlaying)
        {
            _statusBar.text = "Status: Playing";
            _statusBar.textColor = _colorActive;
        }
        else if (_stateInt == 1)
        {
            _statusBar.text = "Status: Connecting...";
            _statusBar.textColor = _colorWarn;
        }
        else if (_stateInt == 3)
        {
            _statusBar.text = "Status: Stopping...";
            _statusBar.textColor = _colorWarn;
        }
        else if (_stateInt == 4)
        {
            _statusBar.text = "Status: Error";
            _statusBar.textColor = _colorDanger;
        }
        else
        {
            _statusBar.text = "Status: Idle";
            _statusBar.textColor = _colorMuted;
        }
    }

    /**
     * NOW PLAYING panel: ICY StreamTitle is "Artist - Track"; the atom
     * splits it. Show artist (bright) and track (muted); fall back to the
     * full title when the stream sends no " - " separator; "…" while
     * playing without metadata yet, "—" when idle.
     */
    private function updateNowPlaying():Void
    {
        var artistLine:String = "";
        var trackLine:String = "";

        if (_artist != "")
        {
            artistLine = _artist;
            if (_track != "") trackLine = _track;
        }
        else if (_title != "")
        {
            artistLine = _title;
        }
        else
        {
            artistLine = _isPlaying ? "..." : "—";
        }

        _npArtist.text = artistLine;
        _npTrack.text = trackLine;
    }

    private function updateError():Void
    {
        if (_errorContact != null && _errorContact.value != null)
        {
            var err:String = Std.string(_errorContact.value);
            _errorDisplay.text = (err.length > 0) ? " " + err : "";
        }
        else
        {
            _errorDisplay.text = "";
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_playBtn != null)
        {
            _playBtn.removeEventListener(MouseEvent.CLICK, onPlayClick);
        }
        if (_stopBtn != null)
        {
            _stopBtn.removeEventListener(MouseEvent.CLICK, onStopClick);
        }
        if (_urlInput != null)
        {
            _urlInput.removeEventListener(KeyboardEvent.KEY_DOWN, onUrlKeyDown);
            _urlInput.removeEventListener(Event.CHANGE, onUrlTextChanged);
            _urlInput.removeEventListener(FocusEvent.FOCUS_IN, onUrlFocusIn);
            _urlInput.removeEventListener(FocusEvent.FOCUS_OUT, onUrlFocusOut);
        }
        if (_volInput != null)
        {
            _volInput.removeEventListener(Event.CHANGE, onVolumeChanged);
            _volInput.removeEventListener(FocusEvent.FOCUS_IN, onVolFocusIn);
            _volInput.removeEventListener(FocusEvent.FOCUS_OUT, onVolFocusOut);
        }

        _bg = null;
        _header = null;
        _titleLabel = null;
        _urlLabel = null;
        _urlInput = null;
        _playBtn = null;
        _stopBtn = null;
        _volLabel = null;
        _volInput = null;
        _nowPlayingSection = null;
        _npCaption = null;
        _npArtist = null;
        _npTrack = null;
        _statusLed = null;
        _statusGlow = null;
        _statusBar = null;
        _errorDisplay = null;
        _urlContact = null;
        _playContact = null;
        _volumeContact = null;
        _isPlayingContact = null;
        _isBufferingContact = null;
        _errorContact = null;
        _stateContact = null;
        _titleContact = null;
        _artistContact = null;
        _trackContact = null;
        super.dispose();
    }
}
