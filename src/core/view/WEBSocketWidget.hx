// ============================================================================
//  WebSocketWidget.hx
//  Cross-platform interactive control panel for WebSocketAtom.
//
//  Architecture: "Atom is Databank & Compute Core"
//  - Widget is the FACE (Component C) of the Atom
//  - Reads all data from Atom's contacts via onContactChanged()
//  - Writes user input to Atom's contacts (no direct backend access)
//  - Stores NO business data — only UI state (text field contents,
//    selected indices, animation timers)
//
//  Compiles on ALL targets (HTML5 / Windows / Linux / Android).
//  No #if cpp wrapper — the entire file is shared.
//
//  Layout:
//  ┌────────────────────────────────────────────────────┐
//  │  WEBSOCKET                              ●  (LED)   │  ← Header
//  ├────────────────────────────────────────────────────┤
//  │  URL                                               │
//  │  [ws://localhost:8080_________________________]    │
//  │                                                    │
//  │  Subprotocol (optional)    [Binary: ☐]             │
//  │  [__________________________________________]      │
//  │                                                    │
//  │  [ CONNECT ]  [ DISCONNECT ]   Status: Disconnected│
//  ├────────────────────────────────────────────────────┤
//  │  SEND DATA                                         │
//  │  [________________________________________] [SEND] │
//  ├────────────────────────────────────────────────────┤
//  │  RECEIVED DATA                          [CLEAR]    │
//  │  ┌──────────────────────────────────────────────┐  │
//  │  │ (multiline text area, autoscroll)            │  │
//  │  │                                              │  │
//  │  └──────────────────────────────────────────────┘  │
//  ├────────────────────────────────────────────────────┤
//  │  RX: 0 bytes  TX: 0 bytes  Close: -                │  ← Status bar
//  │  Last error: (none)                                │
//  └────────────────────────────────────────────────────┘
// ============================================================================

package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;

/**
 * WEBSOCKET CLIENT WIDGET v1.0
 * Interactive control panel for WebSocketAtom.
 *
 * Cross-platform: compiles on HTML5 and all C++ targets.
 *
 * Features:
 *   - URL input with persistence
 *   - Subprotocol input (optional, for Sec-WebSocket-Protocol header)
 *   - Binary mode toggle (send as text or binary)
 *   - Connect / Disconnect buttons with status LED
 *   - Send section with input field + SEND button + Enter-to-send
 *   - Send history (arrow up/down to recall previous messages)
 *   - Received data area with autoscroll and CLEAR button
 *   - Status bar with byte counters and close code
 *   - Error display
 *
 * Mouse isolation is handled automatically by DeviceView base class
 * (v3.4) — no need to stopPropagation here.
 */
class WebSocketWidget extends DeviceView
{
    // =========================================================================
    // LAYOUT CONSTANTS
    // =========================================================================
    /** Default widget width. Can be overridden by setting widgetWidth. */

    #if html5
    public var widgetWidth:Float = 320;
    public var widgetHeight:Float = 500;
    #else
    public var widgetWidth:Float = 320;
    public var widgetHeight:Float = 500;
    #end

    override public function getWidgetSize(): {width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    // ── Color palette (dark theme, matches ComPortWidget style) ──
    private var _colorBg:Int        = 0x1a1a24;
    private var _colorHeader:Int    = 0x2a2a3a;
    private var _colorAccent:Int    = 0x00AAFF;
    private var _colorActive:Int    = 0x00FF88;
    private var _colorDanger:Int    = 0xFF4444;
    private var _colorInactive:Int  = 0x333344;
    private var _colorText:Int      = 0xFFFFFF;
    private var _colorMuted:Int     = 0x888899;
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

    // Subprotocol + binary mode section
    private var _subprotoLabel:TextField;
    private var _subprotoInput:TextField;
    private var _binaryLabel:TextField;
    private var _binaryToggle:Sprite;       // checkbox-style toggle
    private var _binaryToggleMark:TextField; // "X" or empty

    // Connect / disconnect / status
    private var _connectBtn:Sprite;
    private var _disconnectBtn:Sprite;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    private var _statusBar:TextField;

    // Send section
    private var _sendSection:Sprite;
    private var _sendLabel:TextField;
    private var _sendInput:TextField;
    private var _sendBtn:Sprite;

    // Received section
    private var _rxSection:Sprite;
    private var _rxLabel:TextField;
    private var _clearBtn:Sprite;
    private var _rxDisplay:TextField;

    // Stats / error display
    private var _statsBar:TextField;
    private var _errorDisplay:TextField;

    // Auto-reconnect section
    private var _reconnectSection:Sprite;
    private var _reconnectLabel:TextField;
    private var _reconnectToggle:Sprite;        // checkbox-style toggle
    private var _reconnectToggleMark:TextField; // "X" or empty
    private var _intervalLabel:TextField;
    private var _intervalInput:TextField;       // float: seconds between attempts
    private var _maxAttemptsLabel:TextField;
    private var _maxAttemptsInput:TextField;    // int: 0 = unlimited
    private var _attemptsDisplay:TextField;     // read-only: "Attempts: N"

    // =========================================================================
    // CONTACT REFERENCES
    // =========================================================================
    private var _urlContact:Contact;
    private var _subprotoContact:Contact;
    private var _binaryModeContact:Contact;
    private var _connectContact:Contact;
    private var _disconnectContact:Contact;
    private var _sendContact:Contact;
    private var _sendDataContact:Contact;
    private var _isConnectedContact:Contact;
    private var _receivedDataContact:Contact;
    private var _receivedTickContact:Contact;
    private var _sentTickContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;
    private var _closeCodeContact:Contact;
    private var _bytesReceivedContact:Contact;
    private var _bytesSentContact:Contact;
    private var _autoReconnectContact:Contact;
    private var _reconnectIntervalContact:Contact;
    private var _maxReconnectAttemptsContact:Contact;
    private var _reconnectAttemptsContact:Contact;

    // =========================================================================
    // UI STATE (not business data — just display/cache)
    // =========================================================================
    /** Cached last received data — used to detect changes from atom side. */
    private var _lastRxData:String = "";
    /** Cached last error — used to detect changes from atom side. */
    private var _lastError:String = "";
    /** Send history for arrow-up/down recall. */
    private var _sendHistory:Array<String> = [];
    /** Max items in send history. */
    private static inline var MAX_HISTORY:Int = 50;
    /** Current position in history (-1 = not browsing history). */
    private var _historyIndex:Int = -1;
    /** Cached binary mode state. */
    private var _binaryMode:Bool = false;
    /** Cached byte counters. */
    private var _bytesReceived:Int = 0;
    private var _bytesSent:Int = 0;
    /** Cached close code. */
    private var _closeCode:Int = 0;
    /** Cached auto-reconnect state. */
    private var _autoReconnect:Bool = false;
    /** Cached reconnect interval. */
    private var _reconnectInterval:Float = 1.0;
    /** Cached max reconnect attempts. */
    private var _maxReconnectAttempts:Int = 0;
    /** Cached current reconnect attempts. */
    private var _reconnectAttempts:Int = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
     * Create a new WebSocketWidget for the given atom.
     *
     * @param atom The WebSocketAtom instance this widget represents.
     */
    public function new(atom:Atom)
    {
        super(atom);
        findContacts();
        buildUI();
        syncFromAtom();
    }

    /**
     * Find and cache references to all atom contacts.
     * Called from constructor and onActivate().
     */
    private function findContacts():Void
    {
        if (atom == null) return;

        _urlContact            = atom.getInput("url");
        _subprotoContact       = atom.getInput("subprotocol");
        _binaryModeContact     = atom.getInput("binaryMode");
        _connectContact        = atom.getInput("connect");
        _disconnectContact     = atom.getInput("disconnect");
        _sendContact           = atom.getInput("send");
        _sendDataContact       = atom.getInput("sendData");
        _autoReconnectContact       = atom.getInput("autoReconnect");
        _reconnectIntervalContact   = atom.getInput("reconnectInterval");
        _maxReconnectAttemptsContact = atom.getInput("maxReconnectAttempts");

        _isConnectedContact    = atom.getOutput("isConnected");
        _receivedDataContact   = atom.getOutput("receivedData");
        _receivedTickContact   = atom.getOutput("receivedTick");
        _sentTickContact       = atom.getOutput("sentTick");
        _errorContact          = atom.getOutput("error");
        _errorTickContact      = atom.getOutput("errorTick");
        _closeCodeContact      = atom.getOutput("closeCode");
        _bytesReceivedContact  = atom.getOutput("bytesReceived");
        _bytesSentContact      = atom.getOutput("bytesSent");
        _reconnectAttemptsContact = atom.getOutput("reconnectAttempts");
    }

    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }

    /**
     * Flush transient UI state to atom's databank before deactivation.
     *
     * This is critical: if the user typed a new URL but didn't click Connect
     * yet, we must push the URL to the atom's contact, otherwise the typed
     * value is lost when the widget is detached from the display list.
     */
    override private function flushTransientState():Void
    {
        if (_urlContact != null && _urlInput != null)
        {
            _urlContact.value = _urlInput.text;
        }
        if (_subprotoContact != null && _subprotoInput != null)
        {
            _subprotoContact.value = _subprotoInput.text;
        }
        if (_binaryModeContact != null)
        {
            _binaryModeContact.value = _binaryMode;
        }
        if (_autoReconnectContact != null)
        {
            _autoReconnectContact.value = _autoReconnect;
        }
        if (_reconnectIntervalContact != null && _intervalInput != null)
        {
            var parsed:Float = Std.parseFloat(_intervalInput.text);
            if (Math.isNaN(parsed)) parsed = 1.0;
            _reconnectIntervalContact.value = parsed;
        }
        if (_maxReconnectAttemptsContact != null && _maxAttemptsInput != null)
        {
            var parsed:Null<Int> = Std.parseInt(_maxAttemptsInput.text);
            if (parsed == null || parsed < 0) parsed = 0;
            _maxReconnectAttemptsContact.value = parsed;
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
        _titleLabel.text = " WEBSOCKET";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // Status glow (behind LED, visible when connected)
        _statusGlow = new Sprite();
        _statusGlow.graphics.beginFill(_colorDanger, 0.2);
        _statusGlow.graphics.drawCircle(0, 0, 12);
        _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 18;
        _statusGlow.y = 14;
        _statusGlow.visible = false;
        _header.addChild(_statusGlow);

        // Status LED
        _statusLed = new Sprite();
        _statusLed.graphics.beginFill(0x440000);
        _statusLed.graphics.drawCircle(0, 0, 6);
        _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 18;
        _statusLed.y = 14;
        _header.addChild(_statusLed);

        yPos += 32;

        // ── URL section ──
        _urlLabel = createLabel("URL", Std.int(widgetWidth - 20));
        _urlLabel.y = yPos;
        addChild(_urlLabel);
        yPos += 18;

        _urlInput = createInputField("ws://localhost:8080", Std.int(widgetWidth - 20));
        _urlInput.x = 10;
        _urlInput.y = yPos;
        _urlInput.addEventListener(Event.CHANGE, onUrlChanged);
        addChild(_urlInput);
        yPos += 30;

        // ── Subprotocol + Binary mode section ──
        _subprotoLabel = createLabel("SUBPROTOCOL (optional)", (Std.int(widgetWidth - 20)) >> 1);
        _subprotoLabel.y = yPos;
        addChild(_subprotoLabel);
        yPos += 18;

        _subprotoInput = createInputField("", Std.int(widgetWidth - 100));
        _subprotoInput.x = 10;
        _subprotoInput.y = yPos;
        _subprotoInput.addEventListener(Event.CHANGE, onSubprotoChanged);
        addChild(_subprotoInput);

        // Binary mode toggle (right side)
        _binaryLabel = new TextField();
        _binaryLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _binaryLabel.text = "BIN";
        _binaryLabel.width = 25;
        _binaryLabel.height = 14;
        _binaryLabel.x = widgetWidth - 85;
        _binaryLabel.y = yPos + 4;
        _binaryLabel.selectable = false;
        _binaryLabel.mouseEnabled = false;
        addChild(_binaryLabel);

        _binaryToggle = new Sprite();
        _binaryToggle.graphics.beginFill(_colorInputBg);
        _binaryToggle.graphics.lineStyle(1, 0x333355);
        _binaryToggle.graphics.drawRoundRect(3, 0, 18, 18, 3, 3);
        _binaryToggle.graphics.endFill();
        _binaryToggle.x = widgetWidth - 58;
        _binaryToggle.y = yPos + 2;
        _binaryToggle.buttonMode = true;
        _binaryToggle.useHandCursor = true;
        _binaryToggle.addEventListener(MouseEvent.CLICK, onBinaryToggleClick);
        addChild(_binaryToggle);

        _binaryToggleMark = new TextField();
        _binaryToggleMark.defaultTextFormat = new TextFormat("_typewriter", 11, _colorActive, true);
        _binaryToggleMark.text = "";
        _binaryToggleMark.width = 18;
        _binaryToggleMark.height = 18;
        _binaryToggleMark.x = widgetWidth - 58 + 4;
        _binaryToggleMark.y = yPos + 2;
        _binaryToggleMark.selectable = false;
        _binaryToggleMark.mouseEnabled = false;
        addChild(_binaryToggleMark);

        yPos += 28;

        // ── Connect / Disconnect / Status ──
        _connectBtn = createActionButton("CONNECT", 0x225533, onConnectClick);
        _connectBtn.x = 10;
        _connectBtn.y = yPos;
        addChild(_connectBtn);

        _disconnectBtn = createActionButton("DISCONNECT", 0x553322, onDisconnectClick);
        _disconnectBtn.x = 100;
        _disconnectBtn.y = yPos;
        addChild(_disconnectBtn);

        _statusBar = new TextField();
        _statusBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statusBar.text = "Disconnected";
        _statusBar.width = widgetWidth - 200;
        _statusBar.height = 16;
        _statusBar.x = 195;
        _statusBar.y = yPos + 7;
        _statusBar.selectable = false;
        addChild(_statusBar);

        yPos += 36;

        // ── Send section ──
        _sendSection = new Sprite();
        _sendSection.y = yPos;
        addChild(_sendSection);

        _sendLabel = new TextField();
        _sendLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _sendLabel.text = "SEND DATA";
        _sendLabel.x = 5;
        _sendLabel.width = 80;
        _sendLabel.height = 15;
        _sendLabel.selectable = false;
        _sendSection.addChild(_sendLabel);

        _sendInput = createInputField("", Std.int(widgetWidth - 90));
        _sendInput.x = 5;
        _sendInput.y = 15;
        // Enter-to-send (only when not multiline)
        _sendInput.addEventListener(KeyboardEvent.KEY_DOWN, onSendInputKeyDown);
        _sendSection.addChild(_sendInput);

        _sendBtn = createActionButton("SEND", 0x224466, onSendClick);
        _sendBtn.x = widgetWidth - 81;
        _sendBtn.y = 13;
		_sendBtn.width = 77;
        _sendSection.addChild(_sendBtn);

        yPos += 50;

        // ── Received section ──
        _rxSection = new Sprite();
        _rxSection.y = yPos;
        addChild(_rxSection);

        _rxLabel = new TextField();
        _rxLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _rxLabel.text = "RECEIVED DATA";
        _rxLabel.x = 5;
		_rxLabel.width = 100;
        _rxLabel.height = 15;
        _rxLabel.selectable = false;
        _rxSection.addChild(_rxLabel);

        _clearBtn = createActionButton("CLS", 0x442222, onClearClick);
        _clearBtn.x = widgetWidth - 81;
        _clearBtn.y = -2;
		_clearBtn.width = 76;
        _rxSection.addChild(_clearBtn);

        _rxDisplay = new TextField();
        _rxDisplay.defaultTextFormat = new TextFormat("_typewriter", 11, _colorActive);
        _rxDisplay.text = "";
        _rxDisplay.width = widgetWidth -11;
        _rxDisplay.height = 130;
        _rxDisplay.x = 5;
        _rxDisplay.y = 15;
        _rxDisplay.background = true;
        _rxDisplay.backgroundColor = _colorInputBg;
        _rxDisplay.border = true;
        _rxDisplay.borderColor = 0x222233;
        _rxDisplay.multiline = true;
        _rxDisplay.wordWrap = true;
        _rxDisplay.selectable = true;
        _rxDisplay.mouseEnabled = true;
        _rxSection.addChild(_rxDisplay);

        yPos += 152;

        // ── Stats bar ──
        _statsBar = new TextField();
        _statsBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statsBar.text = "RX: 0 bytes   TX: 0 bytes   Close: -";
        _statsBar.width = widgetWidth - 20;
        _statsBar.height = 16;
        _statsBar.x = 10;
        _statsBar.y = yPos;
        _statsBar.selectable = false;
        addChild(_statsBar);
        yPos += 22;

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
        yPos += 22;

        // ── Auto-reconnect section ──
        // Layout:
        //   [X] Auto-Reconnect     Interval: [1.0]
        //   Max attempts: [0]      Attempts: 0
        _reconnectSection = new Sprite();
        _reconnectSection.y = yPos;
        addChild(_reconnectSection);

        _reconnectLabel = new TextField();
        _reconnectLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText, true);
        _reconnectLabel.text = "Auto-Reconnect";
        _reconnectLabel.width = 110;
        _reconnectLabel.height = 16;
        _reconnectLabel.x = 24;
        _reconnectLabel.y = 4;
        _reconnectLabel.selectable = false;
        _reconnectLabel.mouseEnabled = false;
        _reconnectSection.addChild(_reconnectLabel);

        _reconnectToggle = new Sprite();
        _reconnectToggle.graphics.beginFill(_colorInputBg);
        _reconnectToggle.graphics.lineStyle(1, 0x333355);
        _reconnectToggle.graphics.drawRoundRect(0, 0, 18, 18, 3, 3);
        _reconnectToggle.graphics.endFill();
        _reconnectToggle.x = 5;
        _reconnectToggle.y = 4;
        _reconnectToggle.buttonMode = true;
        _reconnectToggle.useHandCursor = true;
        _reconnectToggle.addEventListener(MouseEvent.CLICK, onReconnectToggleClick);
        _reconnectSection.addChild(_reconnectToggle);

        _reconnectToggleMark = new TextField();
        _reconnectToggleMark.defaultTextFormat = new TextFormat("_typewriter", 11, _colorActive, true);
        _reconnectToggleMark.text = "";
        _reconnectToggleMark.width = 18;
        _reconnectToggleMark.height = 18;
        _reconnectToggleMark.x = 9;
        _reconnectToggleMark.y = 4;
        _reconnectToggleMark.selectable = false;
        _reconnectToggleMark.mouseEnabled = false;
        _reconnectSection.addChild(_reconnectToggleMark);

        // Interval label + input (right side of row 1)
        _intervalLabel = new TextField();
        _intervalLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _intervalLabel.text = "Interval (s):";
        _intervalLabel.width = 70;
        _intervalLabel.height = 14;
        _intervalLabel.x = 140;
        _intervalLabel.y = 6;
        _intervalLabel.selectable = false;
        _intervalLabel.mouseEnabled = false;
        _reconnectSection.addChild(_intervalLabel);

        _intervalInput = createInputField("1.0", 60);
        _intervalInput.x = 210;
        _intervalInput.y = 2;
        _intervalInput.addEventListener(Event.CHANGE, onIntervalChanged);
        _reconnectSection.addChild(_intervalInput);

        // Row 2: Max attempts + current attempts display
        _maxAttemptsLabel = new TextField();
        _maxAttemptsLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _maxAttemptsLabel.text = "Max retries:";
        _maxAttemptsLabel.width = 75;
        _maxAttemptsLabel.height = 14;
        _maxAttemptsLabel.x = 5;
        _maxAttemptsLabel.y = 26;
        _maxAttemptsLabel.selectable = false;
        _maxAttemptsLabel.mouseEnabled = false;
        _reconnectSection.addChild(_maxAttemptsLabel);

        _maxAttemptsInput = createInputField("0", 40);
        _maxAttemptsInput.x = 80;
        _maxAttemptsInput.y = 22;
        _maxAttemptsInput.addEventListener(Event.CHANGE, onMaxAttemptsChanged);
        _reconnectSection.addChild(_maxAttemptsInput);

        _attemptsDisplay = new TextField();
        _attemptsDisplay.defaultTextFormat = new TextFormat("_typewriter", 10, _colorAccent, true);
        _attemptsDisplay.text = "Attempts: 0";
        _attemptsDisplay.width = 130;
        _attemptsDisplay.height = 16;
        _attemptsDisplay.x = 140;
        _attemptsDisplay.y = 26;
        _attemptsDisplay.selectable = false;
        _attemptsDisplay.mouseEnabled = false;
        _reconnectSection.addChild(_attemptsDisplay);

        yPos += 50;

        redrawBackground();
    }

    /**
     * Redraw the widget background panels.
     * Called once during buildUI() and could be re-called if dimensions
     * change at runtime.
     */
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

        _sendSection.graphics.clear();
        _sendSection.graphics.beginFill(0x0d0d18, 0.5);
        _sendSection.graphics.lineStyle(1, 0x003a63);
        _sendSection.graphics.drawRoundRect(2, 0, widgetWidth - 4, 45, 4, 4);
        _sendSection.graphics.endFill();

        _rxSection.graphics.clear();
        _rxSection.graphics.beginFill(0x0d0d18, 0.5);
        _rxSection.graphics.lineStyle(1, 0x224422);
        _rxSection.graphics.drawRoundRect(2, 0, widgetWidth - 4, 148, 4, 4);
        _rxSection.graphics.endFill();

        // Auto-reconnect section background (matches dark theme)
        if (_reconnectSection != null)
        {
            _reconnectSection.graphics.clear();
            _reconnectSection.graphics.beginFill(0x0d0d18, 0.5);
            _reconnectSection.graphics.lineStyle(1, 0x224466);
            _reconnectSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 45, 4, 4);
            _reconnectSection.graphics.endFill();
        }
    }

    // =========================================================================
    // UI HELPERS
    // =========================================================================
    private function createLabel(text:String, width:Int):TextField
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        tf.text = text;
        tf.width = width;
        tf.height = 16;
        tf.x = 10;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createInputField(defaultText:String, width:Int):TextField
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 12, _colorText);
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
        tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
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
    // DATA SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
        if (isDisposed || atom == null) return;

        // ── URL ──
        if (_urlContact != null && _urlContact.value != null)
        {
            var urlStr = Std.string(_urlContact.value);
            if (urlStr != _urlInput.text)
            {
                _urlInput.text = urlStr;
            }
        }

        // ── Subprotocol ──
        if (_subprotoContact != null && _subprotoContact.value != null)
        {
            var spStr = Std.string(_subprotoContact.value);
            if (spStr != _subprotoInput.text)
            {
                _subprotoInput.text = spStr;
            }
        }

        // ── Binary mode ──
        if (_binaryModeContact != null && _binaryModeContact.value != null)
        {
            _binaryMode = (_binaryModeContact.value == true);
            updateBinaryToggleVisual();
        }

        // ── Connection status ──
        if (_isConnectedContact != null && _isConnectedContact.value != null)
        {
            updateConnectionStatus(_isConnectedContact.value == true);
        }

        // ── Received data ──
        if (_receivedDataContact != null && _receivedDataContact.value != null)
        {
            var rxStr = Std.string(_receivedDataContact.value);
            if (rxStr != "" && rxStr != _lastRxData)
            {
                appendRxData(rxStr);
            }
        }

        // ── Error ──
        if (_errorContact != null && _errorContact.value != null)
        {
            var errStr = Std.string(_errorContact.value);
            if (errStr != _lastError)
            {
                if (errStr == "")
                {
                    _errorDisplay.text = "";
                }
                else
                {
                    _errorDisplay.text = "Error: " + errStr;
                }
                _lastError = errStr;
            }
        }

        // ── Byte counters ──
        if (_bytesReceivedContact != null && _bytesReceivedContact.value != null)
        {
            _bytesReceived = cast _bytesReceivedContact.value;
        }
        if (_bytesSentContact != null && _bytesSentContact.value != null)
        {
            _bytesSent = cast _bytesSentContact.value;
        }

        // ── Close code ──
        if (_closeCodeContact != null && _closeCodeContact.value != null)
        {
            _closeCode = cast _closeCodeContact.value;
        }

        // ── Auto-reconnect config ──
        if (_autoReconnectContact != null && _autoReconnectContact.value != null)
        {
            _autoReconnect = (_autoReconnectContact.value == true);
            updateReconnectToggleVisual();
        }
        if (_reconnectIntervalContact != null && _reconnectIntervalContact.value != null)
        {
            _reconnectInterval = cast(_reconnectIntervalContact.value, Float);
            if (_intervalInput != null)
            {
                var formatted = Std.string(_reconnectInterval);
                // Trim to max 4 chars to keep input field tidy (e.g. "1", "0.5")
                if (formatted.length > 5) formatted = formatted.substr(0, 5);
                if (_intervalInput.text != formatted) _intervalInput.text = formatted;
            }
        }
        if (_maxReconnectAttemptsContact != null && _maxReconnectAttemptsContact.value != null)
        {
            _maxReconnectAttempts = cast(_maxReconnectAttemptsContact.value, Int);
            if (_maxAttemptsInput != null)
            {
                var s = Std.string(_maxReconnectAttempts);
                if (_maxAttemptsInput.text != s) _maxAttemptsInput.text = s;
            }
        }
        if (_reconnectAttemptsContact != null && _reconnectAttemptsContact.value != null)
        {
            _reconnectAttempts = cast(_reconnectAttemptsContact.value, Int);
            updateAttemptsDisplay();
        }

        updateStatsBar();
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;

        if (contact == _isConnectedContact)
        {
            updateConnectionStatus(newValue == true);
        }
        else if (contact == _receivedDataContact)
        {
            if (newValue != null && newValue != "")
            {
                appendRxData(Std.string(newValue));
            }
        }
        else if (contact == _errorContact)
        {
            if (newValue != null && newValue != "")
            {
                _errorDisplay.text = "Error: " + Std.string(newValue);
                _lastError = Std.string(newValue);
            }
            else
            {
                _errorDisplay.text = "";
                _lastError = "";
            }
        }
        else if (contact == _bytesReceivedContact)
        {
            _bytesReceived = (newValue != null) ? cast newValue : 0;
            updateStatsBar();
        }
        else if (contact == _bytesSentContact)
        {
            _bytesSent = (newValue != null) ? cast newValue : 0;
            updateStatsBar();
        }
        else if (contact == _closeCodeContact)
        {
            _closeCode = (newValue != null) ? cast newValue : 0;
            updateStatsBar();
        }
        else if (contact == _binaryModeContact)
        {
            _binaryMode = (newValue == true);
            updateBinaryToggleVisual();
        }
        else if (contact == _urlContact)
        {
            if (newValue != null && _urlInput != null)
            {
                var urlStr = Std.string(newValue);
                if (urlStr != _urlInput.text) _urlInput.text = urlStr;
            }
        }
        else if (contact == _subprotoContact)
        {
            if (newValue != null && _subprotoInput != null)
            {
                var spStr = Std.string(newValue);
                if (spStr != _subprotoInput.text) _subprotoInput.text = spStr;
            }
        }
        else if (contact == _autoReconnectContact)
        {
            _autoReconnect = (newValue == true);
            updateReconnectToggleVisual();
        }
        else if (contact == _reconnectIntervalContact)
        {
            if (newValue != null)
            {
                _reconnectInterval = cast(newValue, Float);
                if (_intervalInput != null)
                {
                    var s = Std.string(_reconnectInterval);
                    if (s.length > 5) s = s.substr(0, 5);
                    if (_intervalInput.text != s) _intervalInput.text = s;
                }
            }
        }
        else if (contact == _maxReconnectAttemptsContact)
        {
            if (newValue != null)
            {
                _maxReconnectAttempts = cast(newValue, Int);
                if (_maxAttemptsInput != null)
                {
                    var s = Std.string(_maxReconnectAttempts);
                    if (_maxAttemptsInput.text != s) _maxAttemptsInput.text = s;
                }
            }
        }
        else if (contact == _reconnectAttemptsContact)
        {
            if (newValue != null)
            {
                _reconnectAttempts = cast(newValue, Int);
                updateAttemptsDisplay();
            }
        }
    }

    // =========================================================================
    // VISUAL UPDATES
    // =========================================================================
    /**
     * Update the connection status LED + status text.
     */
    private function updateConnectionStatus(isConnected:Bool):Void
    {
        if (isConnected)
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(_colorActive);
            _statusLed.graphics.drawCircle(0, 0, 6);
            _statusLed.graphics.endFill();

            _statusGlow.graphics.clear();
            _statusGlow.graphics.beginFill(_colorActive, 0.2);
            _statusGlow.graphics.drawCircle(0, 0, 12);
            _statusGlow.graphics.endFill();
            _statusGlow.visible = true;

            _statusBar.text = "Connected";
            _statusBar.textColor = _colorActive;

            // Clear error on successful connect
            _errorDisplay.text = "";
            _lastError = "";
        }
        else
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(0x440000);
            _statusLed.graphics.drawCircle(0, 0, 6);
            _statusLed.graphics.endFill();
            _statusGlow.visible = false;

            _statusBar.text = "Disconnected";
            _statusBar.textColor = _colorMuted;
        }
    }

    /**
     * Update the binary mode checkbox visual.
     */
    private function updateBinaryToggleVisual():Void
    {
        _binaryToggleMark.text = _binaryMode ? "X" : "";
    }

    /**
     * Update the auto-reconnect checkbox visual.
     */
    private function updateReconnectToggleVisual():Void
    {
        if (_reconnectToggleMark != null)
        {
            _reconnectToggleMark.text = _autoReconnect ? "X" : "";
        }
    }

    /**
     * Update the attempts display text (read-only field showing current count).
     */
    private function updateAttemptsDisplay():Void
    {
        if (_attemptsDisplay != null)
        {
            var limit = _maxReconnectAttempts > 0 ? '/${_maxReconnectAttempts}' : '';
            _attemptsDisplay.text = 'Attempts: ${_reconnectAttempts}${limit}';
        }
    }

    /**
     * Update the stats bar (byte counters + close code).
     */
    private function updateStatsBar():Void
    {
        var closeStr = _closeCode > 0 ? Std.string(_closeCode) : "-";
        _statsBar.text = 'RX: ${_bytesReceived} bytes   TX: ${_bytesSent} bytes   Close: ${closeStr}';
    }

    /**
     * Append received data to the display area.
     * Auto-scrolls to the bottom. Truncates if too long (>5000 chars).
     */
    private function appendRxData(data:String):Void
    {
        if (_rxDisplay == null) return;
        _lastRxData = data;
        var currentText = _rxDisplay.text;

        // Truncate if accumulated text is too long
        if (currentText.length > 5000)
        {
            currentText = currentText.substr(currentText.length - 3000);
        }

        _rxDisplay.text = currentText + data + "\n";
        _rxDisplay.scrollV = _rxDisplay.maxScrollV;
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    /**
     * URL input changed — push to atom's url contact.
     */
    private function onUrlChanged(e:Event):Void
    {
        if (_urlContact != null)
        {
            _urlContact.value = _urlInput.text;
        }
    }

    /**
     * Subprotocol input changed — push to atom's subprotocol contact.
     */
    private function onSubprotoChanged(e:Event):Void
    {
        if (_subprotoContact != null)
        {
            _subprotoContact.value = _subprotoInput.text;
        }
    }

    /**
     * Binary mode toggle clicked — flip state and push to atom.
     */
    private function onBinaryToggleClick(e:MouseEvent):Void
    {
        _binaryMode = !_binaryMode;
        updateBinaryToggleVisual();
        if (_binaryModeContact != null)
        {
            _binaryModeContact.value = _binaryMode;
        }
    }

    /**
     * Auto-reconnect toggle clicked — flip state and push to atom.
     */
    private function onReconnectToggleClick(e:MouseEvent):Void
    {
        _autoReconnect = !_autoReconnect;
        updateReconnectToggleVisual();
        if (_autoReconnectContact != null)
        {
            _autoReconnectContact.value = _autoReconnect;
        }
    }

    /**
     * Interval input changed — parse as Float and push to atom.
     * Invalid input is silently replaced with the previous valid value.
     */
    private function onIntervalChanged(e:Event):Void
    {
        if (_intervalInput == null || _reconnectIntervalContact == null) return;
        var parsed:Float = Std.parseFloat(_intervalInput.text);
        if (Math.isNaN(parsed)) return;  // ignore invalid input
        // Clamp to reasonable range (matches atom-side clamp)
        if (parsed < 0.1) parsed = 0.1;
        if (parsed > 60.0) parsed = 60.0;
        _reconnectInterval = parsed;
        _reconnectIntervalContact.value = parsed;
    }

    /**
     * Max attempts input changed — parse as Int and push to atom.
     * Negative values are clamped to 0 (unlimited).
     */
    private function onMaxAttemptsChanged(e:Event):Void
    {
        if (_maxAttemptsInput == null || _maxReconnectAttemptsContact == null) return;
        var parsed:Null<Int> = Std.parseInt(_maxAttemptsInput.text);
        if (parsed == null) return;  // ignore invalid input
        if (parsed < 0) parsed = 0;
        _maxReconnectAttempts = parsed;
        _maxReconnectAttemptsContact.value = parsed;
        // Refresh attempts display to show new "/N" suffix
        updateAttemptsDisplay();
    }

    /**
     * Connect button clicked — push URL + subproto to atom, then pulse connect.
     */
    private function onConnectClick(e:MouseEvent):Void
    {
        // Flush transient state first (defensive — flushTransientState also does this)
        if (_urlContact != null)
        {
            _urlContact.value = _urlInput.text;
        }
        if (_subprotoContact != null)
        {
            _subprotoContact.value = _subprotoInput.text;
        }
        if (_binaryModeContact != null)
        {
            _binaryModeContact.value = _binaryMode;
        }
        // Push auto-reconnect config before pulsing connect — atom will
        // pick it up in readInputs() on the same frame.
        if (_autoReconnectContact != null)
        {
            _autoReconnectContact.value = _autoReconnect;
        }
        if (_reconnectIntervalContact != null && _intervalInput != null)
        {
            var parsed:Float = Std.parseFloat(_intervalInput.text);
            if (!Math.isNaN(parsed))
            {
                if (parsed < 0.1) parsed = 0.1;
                if (parsed > 60.0) parsed = 60.0;
                _reconnectIntervalContact.value = parsed;
            }
        }
        if (_maxReconnectAttemptsContact != null && _maxAttemptsInput != null)
        {
            var parsed:Null<Int> = Std.parseInt(_maxAttemptsInput.text);
            if (parsed != null && parsed >= 0)
            {
                _maxReconnectAttemptsContact.value = parsed;
            }
        }
        if (_connectContact != null)
        {
            _connectContact.value = true;
        }
    }

    /**
     * Disconnect button clicked — pulse disconnect.
     */
    private function onDisconnectClick(e:MouseEvent):Void
    {
        if (_disconnectContact != null)
        {
            _disconnectContact.value = true;
        }
    }

    /**
     * Send button clicked — push sendData + pulse send.
     * Also stores the message in send history.
     */
    private function onSendClick(e:MouseEvent):Void
    {
        var data = _sendInput.text;
        if (data == null || data == "") return;

        // Push to history (avoid duplicates of last entry)
        if (_sendHistory.length == 0 || _sendHistory[_sendHistory.length - 1] != data)
        {
            _sendHistory.push(data);
            if (_sendHistory.length > MAX_HISTORY)
            {
                _sendHistory.shift();
            }
        }
        _historyIndex = -1; // reset history browsing

        if (_sendDataContact != null)
        {
            _sendDataContact.value = data;
        }
        if (_sendContact != null)
        {
            _sendContact.value = true;
        }
        // Clear input after send
        _sendInput.text = "";
    }

    /**
     * Send input keyboard handler — Enter to send, Up/Down for history.
     */
    private function onSendInputKeyDown(e:KeyboardEvent):Void
    {
        if (e.keyCode == Keyboard.ENTER)
        {
            onSendClick(null);
            e.preventDefault();
        }
        else if (e.keyCode == Keyboard.UP)
        {
            // Browse history backwards
            if (_sendHistory.length > 0)
            {
                if (_historyIndex == -1)
                {
                    _historyIndex = _sendHistory.length - 1;
                }
                else if (_historyIndex > 0)
                {
                    _historyIndex--;
                }
                _sendInput.text = _sendHistory[_historyIndex];
            }
            e.preventDefault();
        }
        else if (e.keyCode == Keyboard.DOWN)
        {
            // Browse history forwards
            if (_historyIndex != -1 && _historyIndex < _sendHistory.length - 1)
            {
                _historyIndex++;
                _sendInput.text = _sendHistory[_historyIndex];
            }
            else
            {
                _historyIndex = -1;
                _sendInput.text = "";
            }
            e.preventDefault();
        }
    }

    /**
     * Clear button clicked — empty the received data display.
     */
    private function onClearClick(e:MouseEvent):Void
    {
        _rxDisplay.text = "";
        _lastRxData = "";
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        // Remove event listeners
        if (_connectBtn != null) _connectBtn.removeEventListener(MouseEvent.CLICK, onConnectClick);
        if (_disconnectBtn != null) _disconnectBtn.removeEventListener(MouseEvent.CLICK, onDisconnectClick);
        if (_sendBtn != null) _sendBtn.removeEventListener(MouseEvent.CLICK, onSendClick);
        if (_clearBtn != null) _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        if (_binaryToggle != null) _binaryToggle.removeEventListener(MouseEvent.CLICK, onBinaryToggleClick);
        if (_reconnectToggle != null) _reconnectToggle.removeEventListener(MouseEvent.CLICK, onReconnectToggleClick);
        if (_urlInput != null) _urlInput.removeEventListener(Event.CHANGE, onUrlChanged);
        if (_subprotoInput != null) _subprotoInput.removeEventListener(Event.CHANGE, onSubprotoChanged);
        if (_sendInput != null) _sendInput.removeEventListener(KeyboardEvent.KEY_DOWN, onSendInputKeyDown);
        if (_intervalInput != null) _intervalInput.removeEventListener(Event.CHANGE, onIntervalChanged);
        if (_maxAttemptsInput != null) _maxAttemptsInput.removeEventListener(Event.CHANGE, onMaxAttemptsChanged);

        // Null out references
        _bg = null;
        _header = null;
        _titleLabel = null;
        _urlLabel = null;
        _urlInput = null;
        _subprotoLabel = null;
        _subprotoInput = null;
        _binaryLabel = null;
        _binaryToggle = null;
        _binaryToggleMark = null;
        _connectBtn = null;
        _disconnectBtn = null;
        _statusLed = null;
        _statusGlow = null;
        _statusBar = null;
        _sendSection = null;
        _sendLabel = null;
        _sendInput = null;
        _sendBtn = null;
        _rxSection = null;
        _rxLabel = null;
        _clearBtn = null;
        _rxDisplay = null;
        _statsBar = null;
        _errorDisplay = null;
        // Auto-reconnect UI
        _reconnectSection = null;
        _reconnectLabel = null;
        _reconnectToggle = null;
        _reconnectToggleMark = null;
        _intervalLabel = null;
        _intervalInput = null;
        _maxAttemptsLabel = null;
        _maxAttemptsInput = null;
        _attemptsDisplay = null;

        // Contact references
        _urlContact = null;
        _subprotoContact = null;
        _binaryModeContact = null;
        _connectContact = null;
        _disconnectContact = null;
        _sendContact = null;
        _sendDataContact = null;
        _isConnectedContact = null;
        _receivedDataContact = null;
        _receivedTickContact = null;
        _sentTickContact = null;
        _errorContact = null;
        _errorTickContact = null;
        _closeCodeContact = null;
        _bytesReceivedContact = null;
        _bytesSentContact = null;
        // Auto-reconnect contacts
        _autoReconnectContact = null;
        _reconnectIntervalContact = null;
        _maxReconnectAttemptsContact = null;
        _reconnectAttemptsContact = null;

        // History
        _sendHistory = null;

        super.dispose();
    }
}
