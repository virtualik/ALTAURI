package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.FocusEvent;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT WIDGET v3.1                                  ║
* ║     (Unified: Android USB + Windows Registry + HTML5 Web Serial)          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  Scanner data format: VID|PID|friendlyName|portIdentifier                 ║
* ║    Android: "046D|C52B|Arduino Leonardo|"                                 ║
* ║    Windows: "046D|C52B|Arduino Leonardo (COM3)|COM3"                      ║
* ║    Windows (non-USB): "0000|0000|Serial Port|COM1"                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  UI: [Scan USB] [Clear] → Device List → Selected → BAUD → OPEN/CLOSE      ║
* ║  Checkbox = auto-connect on next app start (persistence stub)             ║
* ║  Click device = select + immediate connect                                ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*  * ComPortWidget is the FACE for ComPortAtom.
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   ComPortWidget                                                         │
* │                                                                         │
* │   ┌───────────────────────────────────────────────────────────────┐     │
* │   │  Title: COM PORT                                 [LED ●]      │     │
* │   ├───────────────────────────────────────────────────────────────┤     │
* │   │  [Scan USB]  [CLEAR]                                          │     │
* │   ├───────────────────────────────────────────────────────────────┤     │
* │   │  ┌──────────────────────────────────────────────────────────┐ │     │
* │   │  │  Founded Ports                                           │ │     │
* │   │  │  Founded Ports                                           │ │     │
* │   │  │  Founded Ports                                           │ │     │
* │   │  │  Founded Ports                                           │ │     │
* │   │  │  Founded Ports                                           │ │     │
* │   │  │                                                          │ │     │
* │   │  └──────────────────────────────────────────────────────────┘ │     │
* │   │  Selected: None (Auto)                                        │     │
* │   │                                                               │     │
* │   │  BAUD:                                                        │     │
* │   │  [9600           ]                                            │     │
* │   │                                                               │     │
* │   │  [  OPEN  ]  [  CLOSE  ]     DTR: [ON/OFF]                    │     │
* │   ├───────────────────────────────────────────────────────────────┤     │
* │   │  Append nothing        ○         Append CR           ○        │     │
* │   │  Append LF             ○         Append CR+LF        ○        │     │
* │   ├───────────────────────────────────────────────────────────────┤     │
* │   │  RX: ●  TX: ●  ERR: ●                                         │     │
* │   └───────────────────────────────────────────────────────────────┘     │
* │                                                                         │
* │      Widget READS state from the atom's contacts (Databank)             │
* │      Widget WRITES to contacts when interacting with the user           │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*
* v3.1 CHANGES (Event Identity — "widgets are parallelized"):
* - onComPortStatus / onComPortError / onComPortRx now filter impulses
*   by atomId: ComPortAtom v3.4 emits { atomId, text }, and this widget
*   accepts ONLY its own atom's events. Before, every widget displayed
*   every atom's status — 3 atoms looked like 3 mirrored widgets.
* - Plain-String payloads remain owner-less GLOBAL signals (e.g.
*   USB_DEVICES_CHANGED from the Android JNI side) and pass through.
*/
class ComPortWidget extends DeviceView
{
    private static var DEFAULT_BAUD_RATES:Array<Int> = [ 50, 75, 110, 150, 300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 1500000, 2000000, 3000000]; // CDC works on full speed USB 12000000

    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _baudLabel:TextField;
    private var _baudInput:TextField;
    // W-SYNC.4: editing guard — live mirror suppressed while typing
    private var _isEditingBaud:Bool = false;
    private var _openBtn:Sprite;
    private var _closeBtn:Sprite;
    private var _dtrBtn:Sprite;
    private var _dtrLabel:TextField;
    private var _deviceListMask:Sprite;
    private var _deviceScrollY:Float = 0;
    private var _deviceContentHeight:Float = 0;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    private var _rxLed:Sprite;
    private var _txLed:Sprite;
    private var _errLed:Sprite;
    private var _statusBar:TextField;
    private var _errorDisplay:TextField;

    // === APPEND MODE SECTION (4 radio buttons) ===
    private var _appendSection:Sprite;
    private var _appendNoneLabel:TextField;
    private var _appendNoneRadio:Sprite;
    private var _appendCRLabel:TextField;
    private var _appendCRRadio:Sprite;
    private var _appendLFLabel:TextField;
    private var _appendLFRadio:Sprite;
    private var _appendCRLFLabel:TextField;
    private var _appendCRLFRadio:Sprite;

    // Unified scanner variables (common across Android + Windows, not HTML5)
    private var _scanBtn:Sprite;
    private var _clearBtn:Sprite;
    private var _deviceListContainer:Sprite;
    private var _deviceListBg:Sprite;
    private var _selectedInfo:TextField;
    private var _noDevicesLabel:TextField;
    private var _deviceItems:Array<Sprite>;
    private var _deviceCheckboxes:Array<Sprite>;
    private var _deviceNameLabels:Array<TextField>;
    private var _deviceVidPidLabels:Array<TextField>;
    private var _devicePortLabels:Array<TextField>;
    private var _scannedDevices:Array<String>;
    private var _selectedDeviceIndex:Int = -1;
    private var _currentSelectedVid:Int = 0;
    private var _currentSelectedPid:Int = 0;
    private var _autoConnectFlags:Array<Bool>;
    private var _deviceClickHandlers:Array<Dynamic>;

    #if html5
    private var _selectedPortInfo:TextField;
    #end

    #if android
    private var _usbPollAccumulator:Float = 0.0;
    private var _lastScanResult:String = "";
    private var _atomUpdateAccumulator:Float = 0.0;
    #end

    #if html5
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 370;
    #else
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 370;
    #end

    override public function getWidgetSize(): {width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorAccent:Int = 0x00AAFF;
    private var _colorActive:Int = 0x00FF88;
        private var _colorRadioBtAct:Int= 0xFFFFFF;
    private var _colorDanger:Int = 0xFF4444;
    private var _colorWarning:Int = 0xFFAA00;
    private var _colorInactive:Int = 0x333344;
    private var _colorText:Int = 0xFFFFFF;
    private var _colorMuted:Int = 0x888899;
    private var _colorInputBg:Int = 0x0d0d18;
    private var _portNameContact:Contact;
    private var _baudRateContact:Contact;
    private var _openContact:Contact;
    private var _closeContact:Contact;
    private var _sendContact:Contact;
    private var _txDataContact:Contact;
    private var _appendModeContact:Contact;
    private var _setDTRContact:Contact;
    private var _isOpenContact:Contact;
    private var _rxDataContact:Contact;
    private var _rxTickContact:Contact;
    private var _txTickContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;
    
    private var _lastError:String = "";
    private var _rxLedTimer:Float = 0;
    private var _txLedTimer:Float = 0;
    private var _errLedTimer:Float = 0;
    private var _ledPulseDuration:Float = 0.5;
    private var _dtrState:Bool = false;
    /** Cached append mode: "none" | "CR" | "LF" | "CRLF". */
    private var _appendMode:String = "none";

    // Impulsys callback references for proper unsubscription (Memory Optimization v1.3)
    private var _onComPortStatus: Impulse -> Void;
    private var _onComPortRx: Impulse -> Void;
    private var _onComPortError: Impulse -> Void;

    public function new(atom:Atom)
    {
        super(atom);
        _scannedDevices = [];
        _deviceItems = [];
        _deviceCheckboxes = [];
        _deviceNameLabels = [];
        _deviceVidPidLabels = [];
        _devicePortLabels = [];
        _autoConnectFlags = [];
        _deviceClickHandlers = [];
        
        _onComPortStatus = onComPortStatus;
        _onComPortRx = onComPortRx;
        _onComPortError = onComPortError;
        
        Impulsys.subscribeToImpulse(EventType.COMPORT_STATUS, _onComPortStatus);
        Impulsys.subscribeToImpulse(EventType.COMPORT_RX_DATA, _onComPortRx);
        Impulsys.subscribeToImpulse(EventType.COMPORT_ERROR, _onComPortError);
        
        findContacts();
        buildUI();
        syncFromAtom();
    }

    private function findContacts():Void
    {
        if (atom == null) return;
        _portNameContact = atom.getInput("portName");
        _baudRateContact = atom.getInput("baudRate");
        _openContact     = atom.getInput("open");
        _closeContact    = atom.getInput("close");
        _sendContact     = atom.getInput("send");
        _txDataContact   = atom.getInput("txData");
        _appendModeContact = atom.getInput("appendMode");
        _setDTRContact   = atom.getInput("setDTR");
        _isOpenContact   = atom.getOutput("isOpen");
        _rxDataContact   = atom.getOutput("rxData");
        _rxTickContact   = atom.getOutput("rxTick");
        _txTickContact   = atom.getOutput("txTick");
        _errorContact    = atom.getOutput("error");
        _errorTickContact = atom.getOutput("errorTick");
    }

    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }

    private function buildUI():Void
    {
        var yPos:Float = 0;
        _bg = new Sprite(); addChild(_bg);
        
        // === HEADER (unchanged) ===
        _header = new Sprite(); _header.y = yPos; addChild(_header);
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = "  COMPORT"; _titleLabel.width = widgetWidth - 40; _titleLabel.height = 28;
        _titleLabel.selectable = false; _titleLabel.mouseEnabled = false; _header.addChild(_titleLabel);
        _statusGlow = new Sprite(); _statusGlow.graphics.beginFill(_colorDanger, 0.2); _statusGlow.graphics.drawCircle(0, 0, 12); _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 18; _statusGlow.y = 14; _statusGlow.visible = false; _header.addChild(_statusGlow);
        _statusLed = new Sprite(); _statusLed.graphics.beginFill(0x440000); _statusLed.graphics.drawCircle(0, 0, 6); _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 18; _statusLed.y = 14; _header.addChild(_statusLed);
        yPos += 32;
        
        // === PORT SELECTOR (unified) ===
        yPos = buildPortSelector(yPos);
        
        // === OPEN / CLOSE / DTR ===
        _openBtn = createActionButton("OPEN", 0x225533, onOpenClick); _openBtn.x = 10; _openBtn.y = yPos; addChild(_openBtn);
        _closeBtn = createActionButton("CLOSE", 0x553322, onCloseClick); _closeBtn.x = 95; _closeBtn.y = yPos; addChild(_closeBtn);
        #if cpp
        _dtrBtn = new Sprite(); _dtrBtn.graphics.beginFill(_colorInactive); _dtrBtn.graphics.drawRoundRect(0, 0, 50, 26, 4, 4); _dtrBtn.graphics.endFill();
        _dtrLabel = new TextField();
        _dtrLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted, true, null, null, null, null, TextFormatAlign.CENTER);
        _dtrLabel.text = "DTR"; _dtrLabel.width = 50; _dtrLabel.height = 26; _dtrLabel.selectable = false; _dtrLabel.mouseEnabled = false;
        _dtrBtn.addChild(_dtrLabel); _dtrBtn.x = 200; _dtrBtn.y = yPos; _dtrBtn.buttonMode = true; _dtrBtn.useHandCursor = true;
        _dtrBtn.addEventListener(MouseEvent.CLICK, onDTRClick); addChild(_dtrBtn);
        #end
        yPos += 36;
        
        // === APPEND MODE SECTION (2x2 grid of label + radio pairs) ===
        _appendSection = new Sprite();
        _appendSection.y = yPos;
        addChild(_appendSection);

        // Row 1: "Append nothing" + radio, "Append CR" + radio
        _appendNoneLabel = createLabel("Append nothing");
        _appendNoneLabel.x = 5;
        _appendNoneLabel.y = 0;
        _appendNoneLabel.width = 110;
        _appendSection.addChild(_appendNoneLabel);

        _appendNoneRadio = createRadioButton();
        _appendNoneRadio.x = 122;
        _appendNoneRadio.y = 2;
        _appendNoneRadio.addEventListener(MouseEvent.CLICK, onAppendNoneClick);
        _appendSection.addChild(_appendNoneRadio);

        _appendCRLabel = createLabel("Append CR");
        _appendCRLabel.x = 160;
        _appendCRLabel.y = 0;
        _appendCRLabel.width = 75;
        _appendSection.addChild(_appendCRLabel);

        _appendCRRadio = createRadioButton();
        _appendCRRadio.x = 265;
        _appendCRRadio.y = 2;
        _appendCRRadio.addEventListener(MouseEvent.CLICK, onAppendCRClick);
        _appendSection.addChild(_appendCRRadio);

        // Row 2: "Append LF" + radio, "Append CR+LF" + radio
        _appendLFLabel = createLabel("Append LF");
        _appendLFLabel.x = 5;
        _appendLFLabel.y = 16;
        _appendLFLabel.width = 110;
        _appendSection.addChild(_appendLFLabel);

        _appendLFRadio = createRadioButton();
        _appendLFRadio.x = 122;
        _appendLFRadio.y = 18;
        _appendLFRadio.addEventListener(MouseEvent.CLICK, onAppendLFClick);
        _appendSection.addChild(_appendLFRadio);

        _appendCRLFLabel = createLabel("Append CR+LF");
        _appendCRLFLabel.x = 160;
        _appendCRLFLabel.y = 16;
        _appendCRLFLabel.width = 95;
        _appendSection.addChild(_appendCRLFLabel);

        _appendCRLFRadio = createRadioButton();
        _appendCRLFRadio.x = 265;
        _appendCRLFRadio.y = 18;
        _appendCRLFRadio.addEventListener(MouseEvent.CLICK, onAppendCRLFClick);
        _appendSection.addChild(_appendCRLFRadio);

        updateAppendModeVisual();  // initial state: "none" selected

        yPos += 38;
        
        // === STATUS BAR + LEDs + ERROR ===
        var indicatorY:Float = yPos;
        _statusBar = new TextField(); _statusBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statusBar.text = "Disconnected"; _statusBar.width = 140; _statusBar.height = 16; _statusBar.x = 10; _statusBar.y = indicatorY; _statusBar.selectable = false;
        addChild(_statusBar);
        var rxLedLabel = new TextField(); rxLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        rxLedLabel.text = "RX"; rxLedLabel.width = 20; rxLedLabel.height = 14; rxLedLabel.x = 120; rxLedLabel.y = indicatorY; rxLedLabel.selectable = false;
        addChild(rxLedLabel);
        _rxLed = new Sprite(); _rxLed.graphics.beginFill(0x003300); _rxLed.graphics.drawCircle(0, 0, 5); _rxLed.graphics.endFill();
        _rxLed.x = 145; _rxLed.y = indicatorY + 7; addChild(_rxLed);
        var txLedLabel = new TextField(); txLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        txLedLabel.text = "TX"; txLedLabel.width = 20; txLedLabel.height = 14; txLedLabel.x = 160; txLedLabel.y = indicatorY; txLedLabel.selectable = false;
        addChild(txLedLabel);
        _txLed = new Sprite(); _txLed.graphics.beginFill(0x001133); _txLed.graphics.drawCircle(0, 0, 5); _txLed.graphics.endFill();
        _txLed.x = 185; _txLed.y = indicatorY + 7; addChild(_txLed);
        var errLedLabel = new TextField(); errLedLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        errLedLabel.text = "ERR"; errLedLabel.width = 25; errLedLabel.height = 14; errLedLabel.x = 200; errLedLabel.y = indicatorY; errLedLabel.selectable = false;
        addChild(errLedLabel);
        _errLed = new Sprite(); _errLed.graphics.beginFill(0x330000); _errLed.graphics.drawCircle(0, 0, 5); _errLed.graphics.endFill();
        _errLed.x = 228; _errLed.y = indicatorY + 7; addChild(_errLed);
        _errorDisplay = new TextField(); _errorDisplay.defaultTextFormat = new TextFormat("_typewriter", 9, _colorDanger);
        _errorDisplay.text = ""; _errorDisplay.width = widgetWidth - 20; _errorDisplay.height = 15; _errorDisplay.x = 10; _errorDisplay.y = indicatorY + 18; _errorDisplay.selectable = false;
        addChild(_errorDisplay);
        
        redrawBackground();
    }

    private function buildPortSelector(yPos:Float):Float
    {
        // --- Scan Button ---
        #if html5
        _scanBtn = createActionButton("Select Port", 0x224466, onSelectPortClick);
        #else
        _scanBtn = createActionButton("Scan USB", 0x224466, onScanClick);
        #end
        _scanBtn.x = 10; _scanBtn.y = yPos; addChild(_scanBtn);
        
        // --- Clear Button (not needed on HTML5 - browser dialog handles it) ---
        #if !html5
        _clearBtn = createActionButton("Clear", 0x443322, onClearClick);
        _clearBtn.x = 95; _clearBtn.y = yPos; addChild(_clearBtn);
        #end
        yPos += 30;
        
        // --- Device List (Android + Windows) or Placeholder (HTML5) ---
        #if html5
        _selectedPortInfo = createInputField("Click [Select Port] to connect", Std.int(widgetWidth - 20));
        _selectedPortInfo.type = TextFieldType.DYNAMIC;
        _selectedPortInfo.x = 10; _selectedPortInfo.y = yPos; addChild(_selectedPortInfo);
        yPos += 30;
        #else
        _deviceListContainer = new Sprite(); _deviceListContainer.x = 10; _deviceListContainer.y = yPos; addChild(_deviceListContainer);
        _deviceListBg = new Sprite();
        _deviceListBg.graphics.beginFill(_colorInputBg, 0.7); _deviceListBg.graphics.lineStyle(1, 0x222233);
        _deviceListBg.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4); _deviceListBg.graphics.endFill();
        _deviceListContainer.addChild(_deviceListBg);

        // Scroll mask
        _deviceListMask = new Sprite();
        _deviceListMask.graphics.beginFill(0xFF0000);
        _deviceListMask.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4);
        _deviceListMask.graphics.endFill();
        _deviceListContainer.addChild(_deviceListMask);
        _deviceListContainer.mask = _deviceListMask;
        _deviceListContainer.addEventListener(MouseEvent.MOUSE_WHEEL, onDeviceListWheel);
        
        _noDevicesLabel = new TextField();
        _noDevicesLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted, null, null, null, null, null, TextFormatAlign.CENTER);
        #if android
        _noDevicesLabel.text = "Click [Scan USB] to find devices";
        #else
        _noDevicesLabel.text = "Click [Scan USB] to find COM ports";
        #end
        _noDevicesLabel.width = widgetWidth - 40; _noDevicesLabel.height = 30;
        _noDevicesLabel.x = 10; _noDevicesLabel.y = 45; _noDevicesLabel.selectable = false;
        _deviceListContainer.addChild(_noDevicesLabel);
        yPos += 125;
        #end
        
        // --- Selected Info Line ---
        _selectedInfo = new TextField();
        _selectedInfo.defaultTextFormat = new TextFormat("_typewriter", 10, _colorAccent);
        #if html5
        _selectedInfo.text = "Selected: None";
        #else
        _selectedInfo.text = "Selected: None (Auto)";
        #end
        _selectedInfo.width = widgetWidth - 20; _selectedInfo.height = 16;
        _selectedInfo.x = 10; _selectedInfo.y = yPos; _selectedInfo.selectable = false; addChild(_selectedInfo);
        yPos += 20;
        
        // --- BAUD Rate ---
        _baudLabel = createLabel("BAUD"); _baudLabel.x = 10; _baudLabel.y = yPos; addChild(_baudLabel);
        yPos += 18;
        _baudInput = createInputField("9600", Std.int(widgetWidth - 20)); _baudInput.x = 10; _baudInput.y = yPos;
        _baudInput.addEventListener(Event.CHANGE, onBaudRateChanged);
        _baudInput.addEventListener(FocusEvent.FOCUS_IN, onBaudFocusIn);
        _baudInput.addEventListener(FocusEvent.FOCUS_OUT, onBaudFocusOut);
        addChild(_baudInput);
        yPos += 30;
        
        return yPos;
    }

    private function updateDeviceList():Void
    {
        #if html5 return; #end
        
        for (item in _deviceItems) { if (item.parent != null) item.parent.removeChild(item); }
        _deviceItems = []; _deviceCheckboxes = []; _deviceNameLabels = []; _deviceVidPidLabels = []; _devicePortLabels = []; _deviceClickHandlers = [];
        _deviceScrollY = 0; _deviceContentHeight = 0;
        
        if (_scannedDevices.length == 0) {
            _noDevicesLabel.visible = true;
            _selectedInfo.text = "Selected: None (Auto)";
            return;
        }
        _noDevicesLabel.visible = false;
        
        var itemY:Float = 5;
        var listWidth:Float = widgetWidth - 40;
        
        for (i in 0..._scannedDevices.length)
        {
            var deviceStr = _scannedDevices[i];
            var parts = deviceStr.split("|");
            if (parts.length < 3) continue;
            var vid = parts[0];
            var pid = parts[1];
            var friendlyName = parts[2];
            var portId = (parts.length > 3) ? parts[3] : "";
            
            var showVidPid = (vid != "0000" || pid != "0000");
            var itemHeight:Float = showVidPid ? 36 : 22;
            
            var item = new Sprite();
            item.graphics.beginFill(i == _selectedDeviceIndex ? 0x225533 : 0x151528);
            item.graphics.drawRoundRect(0, 0, listWidth, itemHeight, 3, 3); item.graphics.endFill();
            item.x = 5; item.y = itemY; item.buttonMode = true; item.useHandCursor = true;
            
            // Checkbox (auto-connect marker)
            var checkbox = new Sprite();
            checkbox.graphics.lineStyle(1, 0x666688); checkbox.graphics.drawRect(0, 0, 14, 14);
            checkbox.x = 8; checkbox.y = showVidPid ? 11 : 4;
            if (_autoConnectFlags.length > i && _autoConnectFlags[i]) {
                checkbox.graphics.beginFill(_colorWarning);
                checkbox.graphics.drawRect(2, 2, 10, 10); checkbox.graphics.endFill();
            }
            item.addChild(checkbox);
            
            // Line 1: Friendly name
            var nameLabel = new TextField();
            nameLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText);
            nameLabel.text = friendlyName;
            nameLabel.width = listWidth - 90; nameLabel.height = 16; nameLabel.x = 28; nameLabel.y = showVidPid ? 2 : 3;
            nameLabel.selectable = false; nameLabel.mouseEnabled = false;
            item.addChild(nameLabel);
            
            // Line 2: VID:PID (only if non-zero)
            var vidPidLabel:TextField = null;
            if (showVidPid) {
                vidPidLabel = new TextField();
                vidPidLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
                vidPidLabel.text = "VID:" + vid + "  PID:" + pid;
                vidPidLabel.width = listWidth - 90; vidPidLabel.height = 14; vidPidLabel.x = 28; vidPidLabel.y = 19;
                vidPidLabel.selectable = false; vidPidLabel.mouseEnabled = false;
                item.addChild(vidPidLabel);
            }
            
            // Port badge (right side, only if portId exists)
            var portLabel:TextField = null;
            if (portId != "" && portId != null) {
                portLabel = new TextField();
                portLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorAccent, true);
                portLabel.text = portId;
                portLabel.width = 55; portLabel.height = 16; portLabel.x = listWidth - 55; portLabel.y = showVidPid ? 2 : 3;
                portLabel.selectable = false; portLabel.mouseEnabled = false;
                item.addChild(portLabel);
            }
            
            var capturedIndex = i;
            var capturedDeviceStr = deviceStr;
            var capturedHeight = itemHeight;
            
            // Checkbox click = toggle auto-connect (stopPropagation to prevent item click)
            checkbox.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
                e.stopPropagation();
                toggleAutoConnect(capturedIndex);
            });
            
            // Item click = select + connect
            var clickHandler:MouseEvent->Void = function(e:MouseEvent) { onDeviceClick(capturedIndex); };
            item.addEventListener(MouseEvent.CLICK, clickHandler);
            _deviceClickHandlers.push(clickHandler);
            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) {
                if (capturedIndex != _selectedDeviceIndex) {
                    item.graphics.clear(); item.graphics.beginFill(0x252545);
                    item.graphics.drawRoundRect(0, 0, listWidth, capturedHeight, 3, 3); item.graphics.endFill();
                }
            });
            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) {
                if (capturedIndex != _selectedDeviceIndex) {
                    item.graphics.clear(); item.graphics.beginFill(0x151528);
                    item.graphics.drawRoundRect(0, 0, listWidth, capturedHeight, 3, 3); item.graphics.endFill();
                }
            });
            
            _deviceListContainer.addChild(item);
            _deviceItems.push(item);
            _deviceCheckboxes.push(checkbox);
            _deviceNameLabels.push(nameLabel);
            _deviceVidPidLabels.push(vidPidLabel);
            _devicePortLabels.push(portLabel);
            itemY += itemHeight + 3;
        }
        
        _deviceContentHeight = itemY;
        
        // Update selected info line
        if (_selectedDeviceIndex >= 0 && _selectedDeviceIndex < _scannedDevices.length) {
            var sel = _scannedDevices[_selectedDeviceIndex].split("|");
            var selText = "";
            if (sel.length >= 3) {
                selText = sel[2]; // friendly name
                if (sel.length > 3 && sel[3] != "") selText += " (" + sel[3] + ")";
            }
            _selectedInfo.text = "Selected: " + selText;
        } else {
            _selectedInfo.text = "Selected: None (Auto)";
        }
    }

    #if !html5
    private function onDeviceListWheel(e:MouseEvent):Void
    {
        var maxScroll = Math.max(0, _deviceContentHeight - 115);
        var newY = _deviceScrollY + (-e.delta * 25);
        newY = newY < 0 ? 0 : (newY > maxScroll ? maxScroll : newY);
        var actualDelta = newY - _deviceScrollY;
        _deviceScrollY = newY;
        for (item in _deviceItems) { if (item != null) item.y -= actualDelta; }
    }
    #end

    private function onDeviceClick(index:Int):Void
    {
        _selectedDeviceIndex = index;
        var deviceStr = _scannedDevices[index];
        var parts = deviceStr.split("|");
        
        #if android
        if (parts.length >= 2) {
            var vid = Std.parseInt("0x" + parts[0]);
            var pid = Std.parseInt("0x" + parts[1]);
            _currentSelectedVid = vid; _currentSelectedPid = pid;
            if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
                var comAtom:library.drivers.ComPortAtom = cast atom;
                comAtom.setSelectedDevice(vid, pid);
                if (_portNameContact != null) _portNameContact.value = parts[0] + ":" + parts[1];
            }
        }
        #elseif (cpp && !android)
        // Windows: set port name from parts[3] (portIdentifier)
        if (parts.length > 3 && parts[3] != "") {
            if (_portNameContact != null) _portNameContact.value = parts[3];
            if (parts.length >= 2) {
                var vid = Std.parseInt("0x" + parts[0]);
                var pid = Std.parseInt("0x" + parts[1]);
                _currentSelectedVid = (vid != null) ? vid : 0;
                _currentSelectedPid = (pid != null) ? pid : 0;
            }
        }
        #end
        
        updateDeviceList();
        
        // Auto-connect: immediately open after selection
        onOpenClick(null);
    }

    #if !html5
    private function onScanClick(e:MouseEvent):Void
    {
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            #if android
            _scannedDevices = comAtom.scanUSBDevices();
            #else
            _scannedDevices = comAtom.scanCOMPorts();
            #end
            _selectedDeviceIndex = -1;
            _currentSelectedVid = 0; _currentSelectedPid = 0;
            // Initialize autoConnect flags
            _autoConnectFlags = [];
            for (i in 0..._scannedDevices.length) _autoConnectFlags.push(false);
            updateDeviceList();
            
            // Check auto-connect preference
            checkAutoConnect();
        }
    }
    #end

    #if html5
    private function onSelectPortClick(e:MouseEvent):Void
    {
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            comAtom.openDevice();
        } else if (_openContact != null) {
            _openContact.value = true;
        }
    }
    #end

    #if !html5
    private function onClearClick(e:MouseEvent):Void
    {
        _scannedDevices = []; _selectedDeviceIndex = -1;
        _currentSelectedVid = 0; _currentSelectedPid = 0;
        _autoConnectFlags = []; _deviceClickHandlers = [];
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            #if android
            comAtom.setSelectedDevice(0, 0);
            #end
        }
        updateDeviceList();
    }
    #end

    // === Auto-connect stubs ===

    private function loadAutoConnect():String
    {
        // TODO: Stub — implement persistence (file/registry/localStorage)
        return "";
    }

    private function saveAutoConnect(deviceData:String):Void
    {
        // TODO: Stub — implement persistence
    }

    private function clearAutoConnect():Void
    {
        // TODO: Stub — implement persistence
    }

    private function toggleAutoConnect(index:Int):Void
    {
        while (_autoConnectFlags.length <= index) _autoConnectFlags.push(false);
        _autoConnectFlags[index] = !_autoConnectFlags[index];
        if (_autoConnectFlags[index]) {
            saveAutoConnect(_scannedDevices[index]);
        } else {
            clearAutoConnect();
        }
        updateDeviceList();
    }

    private function checkAutoConnect():Void
    {
        var saved = loadAutoConnect();
        if (saved == "" || saved == null) return;
        for (i in 0..._scannedDevices.length) {
            if (_scannedDevices[i] == saved) {
                _autoConnectFlags[i] = true;
                _selectedDeviceIndex = i;
                // Auto-select and connect
                onDeviceClick(i);
                return;
            }
        }
    }

    // === Drawing helpers ===

    private function redrawBackground():Void
    {
        _bg.graphics.clear(); _bg.graphics.beginFill(_colorBg, 0.95); _bg.graphics.lineStyle(1, _colorAccent);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8); _bg.graphics.endFill();
        _header.graphics.clear(); _header.graphics.beginFill(_colorHeader);
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 28, 8, 8, 0, 0); _header.graphics.endFill();

    }

    private function createLabel(text:String):TextField
    {
        var tf = new TextField(); tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        tf.text = text; tf.width = 60; tf.height = 16; tf.x = 10; tf.selectable = false; tf.mouseEnabled = false;
        return tf;
    }

    private function createInputField(defaultText:String, width:Int):TextField
    {
        var tf = new TextField(); tf.defaultTextFormat = new TextFormat("_typewriter", 12, _colorText);
        tf.text = defaultText; tf.width = width; tf.height = 22; tf.background = true; tf.backgroundColor = _colorInputBg;
        tf.border = true; tf.borderColor = 0x333355; tf.type = TextFieldType.INPUT; tf.selectable = true; tf.mouseEnabled = true;
        return tf;
    }

    private function createActionButton(label:String, color:Int, callback:MouseEvent -> Void):Sprite
    {
        var btn = new Sprite(); btn.graphics.beginFill(color); btn.graphics.drawRoundRect(0, 0, 75, 26, 4, 4); btn.graphics.endFill();
        var tf = new TextField(); tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label; tf.width = 75; tf.height = 26; tf.selectable = false; tf.mouseEnabled = false; btn.addChild(tf);
        btn.buttonMode = true; btn.useHandCursor = true; btn.addEventListener(MouseEvent.CLICK, callback);
        return btn;
    }

    /** Create a radio button sprite (12x12 hollow circle). */
    private function createRadioButton():Sprite
    {
        var r = new Sprite();
        r.buttonMode = true;
        r.useHandCursor = true;
        drawRadioVisual(r, false);
        return r;
    }

    /** Redraw a radio button: hollow circle when unselected,
     *  hollow circle + filled inner dot when selected. */
    private function drawRadioVisual(r:Sprite, selected:Bool):Void
    {
        r.graphics.clear();
        r.graphics.beginFill(_colorInputBg);
        r.graphics.lineStyle(1, 0x333555);
        r.graphics.drawCircle(6, 6, 6);
        r.graphics.endFill();
        if (selected)
        {
            r.graphics.beginFill(_colorRadioBtAct);
            r.graphics.drawCircle(6, 6, 3);
            r.graphics.endFill();
        }
    }

    /** Update all 4 append-mode radio buttons to reflect _appendMode. */
    private function updateAppendModeVisual():Void
    {
        if (_appendNoneRadio != null) drawRadioVisual(_appendNoneRadio, _appendMode == "none");
        if (_appendCRRadio   != null) drawRadioVisual(_appendCRRadio,   _appendMode == "CR");
        if (_appendLFRadio   != null) drawRadioVisual(_appendLFRadio,   _appendMode == "LF");
        if (_appendCRLFRadio != null) drawRadioVisual(_appendCRLFRadio, _appendMode == "CRLF");
    }

    /** Set append mode with mutual exclusion, update visuals, push to atom contact. */
    private function setAppendMode(mode:String):Void
    {
        _appendMode = mode;
        updateAppendModeVisual();
        if (_appendModeContact != null) _appendModeContact.value = mode;
    }

    // === Atom sync ===

    override private function syncFromAtom():Void
    {
        if (_baudRateContact != null && _baudRateContact.value != null) _baudInput.text = Std.string(_baudRateContact.value);
        if (_isOpenContact != null && _isOpenContact.value != null) updateConnectionStatus(_isOpenContact.value == true);
        if (_errorContact != null && _errorContact.value != null) {
            var errStr = Std.string(_errorContact.value);
            if (errStr != "" && errStr != _lastError) { _errorDisplay.text = "Error: " + errStr; _lastError = errStr; }
        }
        // ── Append mode ──
        if (_appendModeContact != null && _appendModeContact.value != null)
        {
            var amStr = Std.string(_appendModeContact.value);
            if (amStr != _appendMode)
            {
                _appendMode = amStr;
                updateAppendModeVisual();
            }
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;
        if (contact == _isOpenContact) {
            var isOpen:Bool = (newValue == true);
            updateConnectionStatus(isOpen);
            if (isOpen) { if (_errorDisplay != null) _errorDisplay.text = ""; _lastError = ""; }
            #if android
            if (!isOpen) {
                _currentSelectedVid = 0; _currentSelectedPid = 0;
                _selectedDeviceIndex = -1;
                _scannedDevices = [];
                if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
                    var comAtom:library.drivers.ComPortAtom = cast atom;
                    comAtom.setSelectedDevice(0, 0);
                }
                updateDeviceList();
            }
            #end
        }
        // RX data contact (no display widget)
        else if (contact == _rxTickContact && newValue == true) { pulseLed(_rxLed, 0x00FF00, 0x003300); _rxLedTimer = _ledPulseDuration; }
        else if (contact == _txTickContact && newValue == true) { pulseLed(_txLed, 0x00AAFF, 0x001133); _txLedTimer = _ledPulseDuration; }
        else if (contact == _errorTickContact && newValue == true) { pulseLed(_errLed, 0xFF4444, 0x330000); _errLedTimer = _ledPulseDuration; }
        else if (contact == _errorContact) {
            if (newValue != null && newValue != "") { _errorDisplay.text = "Error: " + Std.string(newValue); _lastError = Std.string(newValue); }
            else { _errorDisplay.text = ""; _lastError = ""; }
        }
        else if (contact == _appendModeContact)
        {
            if (newValue != null)
            {
                var amStr = Std.string(newValue);
                if (amStr != _appendMode)
                {
                    _appendMode = amStr;
                    updateAppendModeVisual();
                }
            }
        }
        // W-SYNC.4: LIVE MIRROR input contacts → UI ("Atom is Databank")
        else if (contact == _baudRateContact)
        {
            // baudRate → field; suppressed while the user is editing it
            if (!_isEditingBaud && _baudInput != null && newValue != null)
            {
                var baudStr = Std.string(newValue);
                if (_baudInput.text != baudStr) _baudInput.text = baudStr;
            }
        }
        else if (contact == _portNameContact)
        {
            // portName → device selection: highlight the matching scanned
            // device; if not in the list, show the external port name.
            if (newValue != null && newValue != "")
            {
                var portStr = Std.string(newValue);
                var foundIdx = -1;
                if (_scannedDevices != null)
                {
                    for (i in 0..._scannedDevices.length)
                    {
                        var parts = _scannedDevices[i].split("|");
                        var matches = false;
                        #if android
                        if (parts.length >= 2 && (parts[0] + ":" + parts[1]) == portStr) matches = true;
                        #else
                        if (parts.length > 3 && parts[3] == portStr) matches = true;
                        #end
                        if (matches) { foundIdx = i; break; }
                    }
                }
                if (foundIdx >= 0)
                {
                    if (foundIdx != _selectedDeviceIndex)
                    {
                        _selectedDeviceIndex = foundIdx;
                        updateDeviceList();
                    }
                }
                else if (_selectedInfo != null)
                {
                    _selectedInfo.text = "Selected: " + portStr + " (external)";
                }
            }
        }
    }

    // === Connection status ===

    private function updateConnectionStatus(isOpen:Bool):Void
    {
        if (isOpen)
        {
            _statusLed.graphics.clear(); _statusLed.graphics.beginFill(_colorActive); _statusLed.graphics.drawCircle(0, 0, 6); _statusLed.graphics.endFill();
            _statusGlow.graphics.clear(); _statusGlow.graphics.beginFill(_colorActive, 0.2); _statusGlow.graphics.drawCircle(0, 0, 12); _statusGlow.graphics.endFill();
            _statusGlow.visible = true; _statusBar.text = "Connected"; _statusBar.textColor = _colorActive;
        }
        else
        {
            _statusLed.graphics.clear(); _statusLed.graphics.beginFill(0x440000); _statusLed.graphics.drawCircle(0, 0, 6); _statusLed.graphics.endFill();
            _statusGlow.visible = false; _statusBar.text = "Disconnected"; _statusBar.textColor = _colorMuted;
        }
    }

    // === LED helpers ===

    private function pulseLed(led:Sprite, onColor:Int, offColor:Int):Void
    {
        if (led == null) return;
        led.graphics.clear(); led.graphics.beginFill(onColor); led.graphics.drawCircle(0, 0, 5); led.graphics.endFill();
    }

    private function resetLed(led:Sprite, offColor:Int):Void
    {
        if (led == null) return;
        led.graphics.clear(); led.graphics.beginFill(offColor); led.graphics.drawCircle(0, 0, 5); led.graphics.endFill();
    }

    // === Button handlers ===

    private function onBaudRateChanged(e:Event):Void
    {
        if (_baudRateContact != null) {
            var baud = Std.parseInt(_baudInput.text);
            if (baud != null && baud > 0) _baudRateContact.value = baud;
        }
    }

    /** W-SYNC.4: focus guards — the live mirror is suppressed while typing. */
    private function onBaudFocusIn(e:FocusEvent):Void
    {
        _isEditingBaud = true;
    }

    private function onBaudFocusOut(e:FocusEvent):Void
    {
        _isEditingBaud = false;
        // Leaving the field: normalize display to the committed value
        if (_baudInput != null && _baudRateContact != null && _baudRateContact.value != null)
        {
            var baudStr = Std.string(_baudRateContact.value);
            if (_baudInput.text != baudStr) _baudInput.text = baudStr;
        }
    }

    private function onOpenClick(e:MouseEvent):Void
    {
        var baud = Std.parseInt(_baudInput.text);
        if (_baudRateContact != null && baud != null && baud > 0) _baudRateContact.value = baud;
        #if html5
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            comAtom.openDevice();
        } else if (_openContact != null) { _openContact.value = true; }
        #else
        if (_openContact != null) _openContact.value = true;
        #end
    }

    private function onCloseClick(e:MouseEvent):Void { if (_closeContact != null) _closeContact.value = true; }

    #if cpp
    private function onDTRClick(e:MouseEvent):Void
    {
        _dtrState = !_dtrState;
        if (_setDTRContact != null) _setDTRContact.value = _dtrState;
        _dtrBtn.graphics.clear();
        if (_dtrState) { _dtrBtn.graphics.beginFill(_colorActive); _dtrLabel.textColor = 0x000000; }
        else { _dtrBtn.graphics.beginFill(_colorInactive); _dtrLabel.textColor = _colorMuted; }
        _dtrBtn.graphics.drawRoundRect(0, 0, 50, 26, 4, 4); _dtrBtn.graphics.endFill();
    }
    #end

    // === Append mode radio click handlers ===

    private function onAppendNoneClick(e:MouseEvent):Void  { setAppendMode("none"); }
    private function onAppendCRClick(e:MouseEvent):Void    { setAppendMode("CR"); }
    private function onAppendLFClick(e:MouseEvent):Void    { setAppendMode("LF"); }
    private function onAppendCRLFClick(e:MouseEvent):Void  { setAppendMode("CRLF"); }

    // === Impulsys Handlers ===

    private function onComPortStatus(impulse: Impulse): Void
    {
        if (impulse.data == null || _statusBar == null) return;

        // v3.1 (identity fix): COMPORT_* impulses carry { atomId, text }
        // (ComPortAtom v3.4). Accept only OUR atom's events; plain String
        // payloads are owner-less GLOBAL signals (USB_DEVICES_CHANGED
        // from the Android JNI side has no owning atom).
        var statusStr:String;
        if (Std.isOfType(impulse.data, String))
        {
            statusStr = cast impulse.data;
        }
        else
        {
            var ownerId:String = Reflect.field(impulse.data, "atomId");
            if (ownerId == null) return;
            if (atom == null || ownerId != atom.id) return;
            var txt:String = Reflect.field(impulse.data, "text");
            if (txt == null) return;
            statusStr = txt;
        }

        #if android
            if (statusStr == "USB_DEVICES_CHANGED") {
                trace("ComPortWidget: Received USB_DEVICES_CHANGED signal!");
                if (_isOpenContact != null && _isOpenContact.value != true) {
                    if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
                        var comAtom:library.drivers.ComPortAtom = cast atom;
                        _scannedDevices = comAtom.scanUSBDevices();
                        _selectedDeviceIndex = -1; 
                        _currentSelectedVid = 0; 
                        _currentSelectedPid = 0;
                        updateDeviceList();
                        trace("ComPortWidget: Device list updated automatically.");
                    }
                }
                return; // Don't write this to status bar
            }
            #end

            _statusBar.text = statusStr;
            if (statusStr.indexOf("Connected") >= 0) updateConnectionStatus(true);
            else updateConnectionStatus(false);
    }

    private function onComPortRx(impulse: Impulse): Void
    {
        // RX data received (no display widget).
        // v3.1 (identity fix): payload is { atomId, text } — events from
        // OTHER atoms are ignored so any future display path starts with
        // the correct per-atom binding.
        if (impulse == null || impulse.data == null) return;
        if (Std.isOfType(impulse.data, String)) return; // owner-less global signal
        var ownerId:String = Reflect.field(impulse.data, "atomId");
        if (ownerId == null) return;
        if (atom == null || ownerId != atom.id) return;
        // (reserved: per-atom RX display / RX LED trigger)
    }

    private function onComPortError(impulse: Impulse): Void
    {
        if (impulse.data == null || _errorDisplay == null) return;

        // v3.1 (identity fix): same filtering as onComPortStatus.
        var errStr:String;
        if (Std.isOfType(impulse.data, String))
        {
            errStr = cast impulse.data;
        }
        else
        {
            var ownerId:String = Reflect.field(impulse.data, "atomId");
            if (ownerId == null) return;
            if (atom == null || ownerId != atom.id) return;
            var txt:String = Reflect.field(impulse.data, "text");
            if (txt == null) return;
            errStr = txt;
        }
        _errorDisplay.text = "Error: " + errStr;
        _lastError = errStr;
    }

    // === Lifecycle ===

    override public function activate():Void
    {
        super.activate();
        if (stage != null) stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
        else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
    }

    override public function deactivate():Void
    {
        super.deactivate();
        if (stage != null) stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function onAddedToStage(e:Event):Void
    {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function onEnterFrame(e:Event):Void
    {
        var dt:Float = 1.0 / 60.0;
        if (_rxLedTimer > 0) { _rxLedTimer -= dt; if (_rxLedTimer <= 0) resetLed(_rxLed, 0x003300); }
        if (_txLedTimer > 0) { _txLedTimer -= dt; if (_txLedTimer <= 0) resetLed(_txLed, 0x001133); }
        if (_errLedTimer > 0) { _errLedTimer -= dt; if (_errLedTimer <= 0) resetLed(_errLed, 0x330000); }
        
        #if android
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            
            // 1. Atom update throttling
            _atomUpdateAccumulator += dt;
            if (_atomUpdateAccumulator >= 0.1) {
                try {
                    comAtom.update(_atomUpdateAccumulator);
                } catch(e:Dynamic) {
                    trace("ComPortWidget: Exception in comAtom.update() -> " + e);
                    pulseLed(_errLed, 0xFF4444, 0x330000); _errLedTimer = _ledPulseDuration;
                }
                _atomUpdateAccumulator = 0.0;
            }
            
            // 2. Auto-detect USB (poll once per second)
            var isOpen = (comAtom.getOutput("isOpen") != null && comAtom.getOutput("isOpen").value == true);
            
            if (!isOpen) {
                _usbPollAccumulator += dt;
                if (_usbPollAccumulator >= 1.0) {
                    _usbPollAccumulator = 0.0;
                    
                    try {
                        var currentScan:Array<String> = comAtom.scanUSBDevices(true);
                        var currentStr = currentScan.join("|");
                        
                        if (currentStr != _lastScanResult) {
                            pulseLed(_rxLed, 0x00FF00, 0x003300); _rxLedTimer = _ledPulseDuration;
                            _scannedDevices = currentScan;
                            _selectedDeviceIndex = -1; 
                            _currentSelectedVid = 0; 
                            _currentSelectedPid = 0;
                            updateDeviceList();
                            _lastScanResult = currentStr;
                            
                            // Check auto-connect after scan update
                            checkAutoConnect();
                        }
                    } catch(e:Dynamic) {
                        pulseLed(_errLed, 0xFF4444, 0x330000); _errLedTimer = _ledPulseDuration;
                    }
                }
            }
        }
        #end
    }

    override public function dispose():Void
    {
        if (stage != null) stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        if (_onComPortStatus != null) Impulsys.removeImpulse(EventType.COMPORT_STATUS, _onComPortStatus);
        if (_onComPortRx != null) Impulsys.removeImpulse(EventType.COMPORT_RX_DATA, _onComPortRx);
        if (_onComPortError != null) Impulsys.removeImpulse(EventType.COMPORT_ERROR, _onComPortError);
        if (_openBtn != null) _openBtn.removeEventListener(MouseEvent.CLICK, onOpenClick);
        if (_closeBtn != null) _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);
        if (_baudInput != null)
        {
            _baudInput.removeEventListener(Event.CHANGE, onBaudRateChanged);
            _baudInput.removeEventListener(FocusEvent.FOCUS_IN, onBaudFocusIn);
            _baudInput.removeEventListener(FocusEvent.FOCUS_OUT, onBaudFocusOut);
        }
        if (_appendNoneRadio != null) _appendNoneRadio.removeEventListener(MouseEvent.CLICK, onAppendNoneClick);
        if (_appendCRRadio != null) _appendCRRadio.removeEventListener(MouseEvent.CLICK, onAppendCRClick);
        if (_appendLFRadio != null) _appendLFRadio.removeEventListener(MouseEvent.CLICK, onAppendLFClick);
        if (_appendCRLFRadio != null) _appendCRLFRadio.removeEventListener(MouseEvent.CLICK, onAppendCRLFClick);
        #if cpp
        if (_dtrBtn != null) _dtrBtn.removeEventListener(MouseEvent.CLICK, onDTRClick);
        #end
        #if !html5
        if (_deviceListContainer != null) _deviceListContainer.removeEventListener(MouseEvent.MOUSE_WHEEL, onDeviceListWheel);
        if (_scanBtn != null) _scanBtn.removeEventListener(MouseEvent.CLICK, onScanClick);
        if (_clearBtn != null) _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        for (i in 0..._deviceItems.length) {
            if (_deviceItems[i] != null && i < _deviceClickHandlers.length && _deviceClickHandlers[i] != null)
                _deviceItems[i].removeEventListener(MouseEvent.CLICK, _deviceClickHandlers[i]);
        }
        #else
        if (_scanBtn != null) _scanBtn.removeEventListener(MouseEvent.CLICK, onSelectPortClick);
        #end
        
        // Nullify all references
        _bg = null; _header = null; _titleLabel = null; _baudLabel = null; _baudInput = null;
        _openBtn = null; _closeBtn = null; _dtrBtn = null; _dtrLabel = null;

        _statusLed = null; _statusGlow = null; _rxLed = null; _txLed = null; _errLed = null;
        _statusBar = null; _errorDisplay = null;
        _appendSection = null;
        _appendNoneLabel = null; _appendNoneRadio = null;
        _appendCRLabel = null; _appendCRRadio = null;
        _appendLFLabel = null; _appendLFRadio = null;
        _appendCRLFLabel = null; _appendCRLFRadio = null;
        _portNameContact = null; _baudRateContact = null; _openContact = null; _closeContact = null;
        _sendContact = null; _txDataContact = null; _appendModeContact = null; _setDTRContact = null; _isOpenContact = null;
        _rxDataContact = null; _rxTickContact = null; _txTickContact = null; _errorContact = null; _errorTickContact = null;
        _scanBtn = null; _clearBtn = null; _deviceListContainer = null; _deviceListBg = null; _deviceListMask = null;
        _selectedInfo = null; _noDevicesLabel = null;
        _deviceItems = null; _deviceCheckboxes = null; _deviceNameLabels = null;
        _deviceVidPidLabels = null; _devicePortLabels = null;
        _scannedDevices = null; _autoConnectFlags = null; _deviceClickHandlers = null;
        #if html5
        _selectedPortInfo = null;
        #end
        super.dispose();
    }
}
