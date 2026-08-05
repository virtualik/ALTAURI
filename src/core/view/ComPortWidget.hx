package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT WIDGET v2.1                                  ║
* ║     (Tri-Platform: C++ WinAPI + Android USB Scanner + HTML5 Web)          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    COMPILATION FLOW                                 │  ║
* ║  │  haxe -cpp (Windows) ──► #if cpp ──► Port name text field           │  ║
* ║  │  haxe -cpp (Android) ──► #if android ──► USB Scanner + List         │  ║
* ║  │  haxe -html5         ──► #if html5 ──► "Select Port" button         │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     ANDROID USB SCANNER ARCHITECTURE                      ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Android UI Layout:                                                 │  ║
* ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
* ║  │  │  [Scan USB] [Clear]                                          │  │  ║
* ║  │  ├───────────────────────────────────────────────────────────────┤  │  ║
* ║  │  │  ┌─────────────────────────────────────────────────────────┐  │  │  ║
* ║  │  │  │ ● 067B:2303 - Prolific PL2303                           │  │  │  ║
* ║  │  │  │   1A86:7523 - WCH CH340                                 │  │  │  ║
* ║  │  │  │   0403:6001 - FTDI FT232R                               │  │  │  ║
* ║  │  │  └─────────────────────────────────────────────────────────┘  │  │  ║
* ║  │  │  Selected: 067B:2303                                          │  │  ║
* ║  │  ├───────────────────────────────────────────────────────────────┤  │  ║
* ║  │  │  [OPEN] [CLOSE] [DTR]                                        │  │  ║
* ║  │  │  [TX DATA] [SEND]                                            │  │  ║
* ║  │  │  [RX DATA]                                                   │  │  ║
* ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class ComPortWidget extends DeviceView
{
    private static var DEFAULT_BAUD_RATES:Array<Int> = [9600, 19200, 38400, 57600, 115200];

    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _portLabel:TextField;
    private var _portInput:TextField;
    private var _baudLabel:TextField;
    private var _baudInput:TextField;
    private var _openBtn:Sprite;
    private var _closeBtn:Sprite;
    private var _dtrBtn:Sprite;
    private var _dtrLabel:TextField;
    private var _txSection:Sprite;
    private var _txInput:TextField;
    private var _sendBtn:Sprite;
    private var _rxSection:Sprite;
    private var _rxDisplay:TextField;
    private var _rxScrollPos:Int = 0;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    private var _rxLed:Sprite;
    private var _txLed:Sprite;
    private var _errLed:Sprite;
    private var _statusBar:TextField;
    private var _errorDisplay:TextField;

    #if html5
    private var _selectPortBtn:Sprite;
    private var _selectedPortInfo:TextField;
    private var _bufferSizeInput:TextField;
    private var _chunkSizeInput:TextField;
    private var _enabledBtn:Sprite;
    private var _enabledLabel:TextField;
    private var _bufferSizeLabel:TextField;
    private var _chunkSizeLabel:TextField;
    #end

    #if android
    private var _scanBtn:Sprite;
    private var _clearBtn:Sprite;
    private var _deviceListContainer:Sprite;
    private var _deviceListBg:Sprite;
    private var _selectedInfo:TextField;
    private var _noDevicesLabel:TextField;
    private var _deviceItems:Array<Sprite>;
    private var _deviceCheckboxes:Array<Sprite>;
    private var _deviceLabels:Array<TextField>;
    private var _scannedDevices:Array<String>;
    private var _selectedDeviceIndex:Int = -1;
    #end

    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 380;

    override public function getWidgetSize(): {width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorAccent:Int = 0x00AAFF;
    private var _colorActive:Int = 0x00FF88;
    private var _colorDanger:Int = 0xFF4444;
    private var _colorWarning:Int = 0xFFAA00;
    private var _colorInactive:Int = 0x333344;
    private var _colorText:Int = 0xFFFFFF;
    private var _colorMuted:Int = 0x888899;
    private var _colorInputBg:Int = 0x0d0d18;
    private var _colorRxGreen:Int = 0x00CC66;

    private var _portNameContact:Contact;
    private var _baudRateContact:Contact;
    private var _openContact:Contact;
    private var _closeContact:Contact;
    private var _sendContact:Contact;
    private var _txDataContact:Contact;
    private var _setDTRContact:Contact;
    private var _isOpenContact:Contact;
    private var _rxDataContact:Contact;
    private var _rxTickContact:Contact;
    private var _txTickContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;
    
    private var _lastRxData:String = "";
    private var _lastError:String = "";
    private var _rxLedTimer:Float = 0;
    private var _txLedTimer:Float = 0;
    private var _errLedTimer:Float = 0;
    private var _ledPulseDuration:Float = 0.15;
    private var _dtrState:Bool = false;

    #if html5
    private var _bufferSizeContact:Contact;
    private var _chunkSizeContact:Contact;
    private var _enabledContact:Contact;
    private var _currentBufferSize:Int = 4096;
    private var _currentChunkSize:Int = 256;
    private var _currentEnabled:Bool = true;
    #end

    #if android
    private var _currentSelectedVid:Int = 0;
    private var _currentSelectedPid:Int = 0;
    #end

    // Impulsys callback references for proper unsubscription (Memory Optimization v1.3)
    private var _onComPortStatus: Impulse -> Void;
    private var _onComPortRx: Impulse -> Void;
    private var _onComPortError: Impulse -> Void;

    public function new(atom:Atom)
    {
        super(atom);
        #if android
        _scannedDevices = [];
        _deviceItems = [];
        _deviceCheckboxes = [];
        _deviceLabels = [];
        #end
        
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
        _setDTRContact   = atom.getInput("setDTR");
        _isOpenContact   = atom.getOutput("isOpen");
        _rxDataContact   = atom.getOutput("rxData");
        _rxTickContact   = atom.getOutput("rxTick");
        _txTickContact   = atom.getOutput("txTick");
        _errorContact    = atom.getOutput("error");
        _errorTickContact = atom.getOutput("errorTick");
        
        #if html5
        _bufferSizeContact = atom.getInput("bufferSize");
        _chunkSizeContact  = atom.getInput("chunkSize");
        _enabledContact    = atom.getInput("enabled");
        #end
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
        _header = new Sprite(); _header.y = yPos; addChild(_header);
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = "  COM PORT"; _titleLabel.width = widgetWidth - 40; _titleLabel.height = 28;
        _titleLabel.selectable = false; _titleLabel.mouseEnabled = false; _header.addChild(_titleLabel);
        
        _statusGlow = new Sprite(); _statusGlow.graphics.beginFill(_colorDanger, 0.2); _statusGlow.graphics.drawCircle(0, 0, 12); _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 18; _statusGlow.y = 14; _statusGlow.visible = false; _header.addChild(_statusGlow);
        _statusLed = new Sprite(); _statusLed.graphics.beginFill(0x440000); _statusLed.graphics.drawCircle(0, 0, 6); _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 18; _statusLed.y = 14; _header.addChild(_statusLed);
        yPos += 32;
        
        #if android
        yPos = buildAndroidUI(yPos);
        #elseif cpp
        _portLabel = createLabel("PORT"); _portLabel.y = yPos; addChild(_portLabel);
        _baudLabel = createLabel("BAUD"); _baudLabel.x = 150; _baudLabel.y = yPos; addChild(_baudLabel);
        yPos += 18;
        _portInput = createInputField("COM1", 130); _portInput.x = 10; _portInput.y = yPos;
        _portInput.addEventListener(Event.CHANGE, onPortNameChanged); addChild(_portInput);
        #elseif html5
        _selectPortBtn = createActionButton("Select Port", 0x224466, onSelectPortClick); _selectPortBtn.x = 10; _selectPortBtn.y = yPos; addChild(_selectPortBtn);
        _baudLabel = createLabel("BAUD"); _baudLabel.x = 150; _baudLabel.y = yPos; addChild(_baudLabel);
        yPos += 18;
        _selectedPortInfo = createInputField("No port selected", 130); _selectedPortInfo.type = TextFieldType.DYNAMIC;
        _selectedPortInfo.x = 10; _selectedPortInfo.y = yPos; addChild(_selectedPortInfo);
        #end
        
        _baudInput = createInputField("9600", 100); _baudInput.x = 150; _baudInput.y = yPos;
        _baudInput.addEventListener(Event.CHANGE, onBaudRateChanged); addChild(_baudInput);
        yPos += 30;
        
        _openBtn = createActionButton("OPEN", 0x225533, onOpenClick); _openBtn.x = 10; _openBtn.y = yPos; addChild(_openBtn);
        _closeBtn = createActionButton("CLOSE", 0x553322, onCloseClick); _closeBtn.x = 95; _closeBtn.y = yPos; addChild(_closeBtn);
        
        #if cpp
        _dtrBtn = new Sprite(); _dtrBtn.graphics.beginFill(_colorInactive); _dtrBtn.graphics.drawRoundRect(0, 0, 50, 26, 4, 4); _dtrBtn.graphics.endFill();
        _dtrLabel = new TextField();
        _dtrLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted, true, null, null, null, null, TextFormatAlign.CENTER);
        _dtrLabel.text = "DTR"; _dtrLabel.width = 50; _dtrLabel.height = 26; _dtrLabel.selectable = false; _dtrLabel.mouseEnabled = false;
        _dtrBtn.addChild(_dtrLabel); _dtrBtn.x = 200; _dtrBtn.y = yPos; _dtrBtn.buttonMode = true; _dtrBtn.useHandCursor = true;
        _dtrBtn.addEventListener(MouseEvent.CLICK, onDTRClick); addChild(_dtrBtn);
        #elseif html5
        _dtrBtn = null; _dtrLabel = null;
        #end
        yPos += 36;
        
        #if html5
        _bufferSizeLabel = createLabel("Buffer:"); _bufferSizeLabel.y = yPos; addChild(_bufferSizeLabel);
        _bufferSizeInput = createInputField("4096", 60); _bufferSizeInput.x = 60; _bufferSizeInput.y = yPos;
        _bufferSizeInput.addEventListener(Event.CHANGE, onBufferSizeChanged); addChild(_bufferSizeInput);
        _chunkSizeLabel = createLabel("Chunk:"); _chunkSizeLabel.x = 130; _chunkSizeLabel.y = yPos; addChild(_chunkSizeLabel);
        _chunkSizeInput = createInputField("256", 50); _chunkSizeInput.x = 180; _chunkSizeInput.y = yPos;
        _chunkSizeInput.addEventListener(Event.CHANGE, onChunkSizeChanged); addChild(_chunkSizeInput);
        _enabledBtn = new Sprite(); _enabledBtn.graphics.beginFill(_colorActive); _enabledBtn.graphics.drawRoundRect(0, 0, 70, 26, 4, 4); _enabledBtn.graphics.endFill();
        _enabledBtn.x = 240; _enabledBtn.y = yPos; _enabledBtn.buttonMode = true; _enabledBtn.useHandCursor = true;
        _enabledBtn.addEventListener(MouseEvent.CLICK, onEnabledClick); addChild(_enabledBtn);
        _enabledLabel = new TextField();
        _enabledLabel.defaultTextFormat = new TextFormat("_typewriter", 10, 0x000000, true, null, null, null, null, TextFormatAlign.CENTER);
        _enabledLabel.text = "ON"; _enabledLabel.width = 70; _enabledLabel.height = 26; _enabledLabel.selectable = false; _enabledLabel.mouseEnabled = false;
        _enabledBtn.addChild(_enabledLabel);
        yPos += 36;
        #end
        
        _txSection = new Sprite(); _txSection.y = yPos; addChild(_txSection);
        var txLabel = new TextField(); txLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        txLabel.text = "TX DATA"; txLabel.width = 60; txLabel.height = 15; txLabel.selectable = false; _txSection.addChild(txLabel);
        _txInput = createInputField("", Std.int(widgetWidth - 80)); _txInput.x = 0; _txInput.y = 15;
        _txInput.addEventListener(KeyboardEvent.KEY_DOWN, onTxKeyDown); _txSection.addChild(_txInput);
        _sendBtn = createActionButton("SEND", 0x224466, onSendClick); _sendBtn.x = widgetWidth - 62; _sendBtn.y = 14; _txSection.addChild(_sendBtn);
        yPos += 52;
        
        _rxSection = new Sprite(); _rxSection.y = yPos; addChild(_rxSection);
        var rxLabel = new TextField(); rxLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        rxLabel.text = "RX DATA"; rxLabel.width = 60; rxLabel.height = 15; rxLabel.selectable = false; _rxSection.addChild(rxLabel);
        _rxDisplay = new TextField();
        _rxDisplay.defaultTextFormat = new TextFormat("_typewriter", 11, _colorRxGreen);
        _rxDisplay.text = ""; _rxDisplay.width = widgetWidth - 20; _rxDisplay.height = 100; _rxDisplay.x = 5; _rxDisplay.y = 15;
        _rxDisplay.background = true; _rxDisplay.backgroundColor = _colorInputBg; _rxDisplay.border = true; _rxDisplay.borderColor = 0x222233;
        _rxDisplay.multiline = true; _rxDisplay.wordWrap = true; _rxDisplay.selectable = true; _rxDisplay.mouseEnabled = true;
        _rxSection.addChild(_rxDisplay);
        yPos += 125;
        
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
        _txLed = new Sprite(); _txLed.graphics.beginFill(0x003300); _txLed.graphics.drawCircle(0, 0, 5); _txLed.graphics.endFill();
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

    #if android
    private function buildAndroidUI(yPos:Float):Float
    {
        _scanBtn = createActionButton("Scan USB", 0x224466, onScanClick); _scanBtn.x = 10; _scanBtn.y = yPos; addChild(_scanBtn);
        _clearBtn = createActionButton("Clear", 0x443322, onClearClick); _clearBtn.x = 95; _clearBtn.y = yPos; addChild(_clearBtn);
        yPos += 30;
        
        _deviceListContainer = new Sprite(); _deviceListContainer.x = 10; _deviceListContainer.y = yPos; addChild(_deviceListContainer);
        _deviceListBg = new Sprite(); _deviceListBg.graphics.beginFill(_colorInputBg, 0.7); _deviceListBg.graphics.lineStyle(1, 0x222233);
        _deviceListBg.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4); _deviceListBg.graphics.endFill();
        _deviceListContainer.addChild(_deviceListBg);
        
        _noDevicesLabel = new TextField();
        _noDevicesLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted, null, null, null, null, null, TextFormatAlign.CENTER);
        _noDevicesLabel.text = "Click [Scan USB] to find devices"; _noDevicesLabel.width = widgetWidth - 40; _noDevicesLabel.height = 30;
        _noDevicesLabel.x = 10; _noDevicesLabel.y = 45; _noDevicesLabel.selectable = false; _deviceListContainer.addChild(_noDevicesLabel);
        yPos += 125;
        
        _selectedInfo = new TextField(); _selectedInfo.defaultTextFormat = new TextFormat("_typewriter", 10, _colorAccent);
        _selectedInfo.text = "Selected: None (Auto)"; _selectedInfo.width = widgetWidth - 20; _selectedInfo.height = 16;
        _selectedInfo.x = 10; _selectedInfo.y = yPos; _selectedInfo.selectable = false; addChild(_selectedInfo);
        yPos += 20;
        return yPos;
    }

    private function updateDeviceList():Void
    {
        for (item in _deviceItems) { if (item.parent != null) item.parent.removeChild(item); }
        _deviceItems = []; _deviceCheckboxes = []; _deviceLabels = [];
        
        if (_scannedDevices.length == 0) { _noDevicesLabel.visible = true; _selectedInfo.text = "Selected: None (Auto)"; return; }
        _noDevicesLabel.visible = false;
        
        var itemY:Float = 5; var itemHeight:Float = 24;
        for (i in 0..._scannedDevices.length)
        {
            var deviceStr = _scannedDevices[i];
            var parts = deviceStr.split(":");
            if (parts.length < 2) continue;
            var vid = parts[0]; var pid = parts[1];
            var devicePath = (parts.length > 2) ? parts.slice(2).join(":") : "";
            
            var item = new Sprite();
            item.graphics.beginFill(i == _selectedDeviceIndex ? 0x225533 : 0x151528);
            item.graphics.drawRoundRect(0, 0, widgetWidth - 40, itemHeight, 3, 3); item.graphics.endFill();
            item.x = 5; item.y = itemY; item.buttonMode = true; item.useHandCursor = true;
            
            var checkbox = new Sprite(); checkbox.graphics.lineStyle(1, 0x666688); checkbox.graphics.drawRect(0, 0, 14, 14);
            checkbox.x = 8; checkbox.y = 5;
            if (i == _selectedDeviceIndex) { checkbox.graphics.beginFill(_colorActive); checkbox.graphics.drawRect(2, 2, 10, 10); checkbox.graphics.endFill(); }
            item.addChild(checkbox);
            
            var label = new TextField(); label.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText);
            label.text = '$vid:$pid'; if (devicePath != "") label.text += ' - $devicePath';
            label.width = widgetWidth - 80; label.height = itemHeight; label.x = 28; label.selectable = false; label.mouseEnabled = false;
            item.addChild(label);
            
            var capturedIndex = i;
            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) { onDeviceClick(capturedIndex); });
            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) {
                if (capturedIndex != _selectedDeviceIndex) { item.graphics.clear(); item.graphics.beginFill(0x252545); item.graphics.drawRoundRect(0, 0, widgetWidth - 40, itemHeight, 3, 3); item.graphics.endFill(); }
            });
            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) {
                if (capturedIndex != _selectedDeviceIndex) { item.graphics.clear(); item.graphics.beginFill(0x151528); item.graphics.drawRoundRect(0, 0, widgetWidth - 40, itemHeight, 3, 3); item.graphics.endFill(); }
            });
            
            _deviceListContainer.addChild(item); _deviceItems.push(item); _deviceCheckboxes.push(checkbox); _deviceLabels.push(label);
            itemY += itemHeight + 3;
        }
        
        if (_selectedDeviceIndex >= 0 && _selectedDeviceIndex < _scannedDevices.length)
        {
            var selectedStr = _scannedDevices[_selectedDeviceIndex];
            var parts = selectedStr.split(":");
            _selectedInfo.text = 'Selected: ${parts[0]}:${parts[1]}';
        }
        else { _selectedInfo.text = "Selected: None (Auto)"; }
    }

    private function onDeviceClick(index:Int):Void
    {
        _selectedDeviceIndex = index;
        var deviceStr = _scannedDevices[index];
        var parts = deviceStr.split(":");
        if (parts.length >= 2)
        {
            var vid = Std.parseInt("0x" + parts[0]);
            var pid = Std.parseInt("0x" + parts[1]);
            _currentSelectedVid = vid; _currentSelectedPid = pid;
            if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom))
            {
                var comAtom:library.drivers.ComPortAtom = cast atom;
                comAtom.setSelectedDevice(vid, pid);
                if (_portNameContact != null) _portNameContact.value = '$vid:$pid';
            }
            trace('ComPortWidget: Selected device VID:PID = ${StringTools.hex(vid, 4)}:${StringTools.hex(pid, 4)}');
        }
        updateDeviceList();
    }

    private function onScanClick(e:MouseEvent):Void
    {
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom))
        {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            _scannedDevices = comAtom.scanUSBDevices();
            _selectedDeviceIndex = -1; _currentSelectedVid = 0; _currentSelectedPid = 0;
            updateDeviceList();
        }
    }

    private function onClearClick(e:MouseEvent):Void
    {
        _scannedDevices = []; _selectedDeviceIndex = -1; _currentSelectedVid = 0; _currentSelectedPid = 0;
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom))
        {
            var comAtom:library.drivers.ComPortAtom = cast atom;
            comAtom.setSelectedDevice(0, 0);
        }
        updateDeviceList();
    }
    #end

    private function redrawBackground():Void
    {
        _bg.graphics.clear(); _bg.graphics.beginFill(_colorBg, 0.95); _bg.graphics.lineStyle(1, _colorAccent);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8); _bg.graphics.endFill();
        _header.graphics.clear(); _header.graphics.beginFill(_colorHeader);
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 28, 8, 8, 0, 0); _header.graphics.endFill();
        _txSection.graphics.clear(); _txSection.graphics.beginFill(0x0d0d18, 0.5); _txSection.graphics.lineStyle(1, 0x222244);
        _txSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 45, 4, 4); _txSection.graphics.endFill();
        _rxSection.graphics.clear(); _rxSection.graphics.beginFill(0x0d0d18, 0.5); _rxSection.graphics.lineStyle(1, 0x224422);
        _rxSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4); _rxSection.graphics.endFill();
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

    override private function syncFromAtom():Void
    {
        #if (cpp && !android)
        if (_portNameContact != null && _portNameContact.value != null && _portInput != null) _portInput.text = Std.string(_portNameContact.value);
        #elseif html5
        if (_portNameContact != null && _portNameContact.value != null && _selectedPortInfo != null) _selectedPortInfo.text = Std.string(_portNameContact.value);
        #end
        if (_baudRateContact != null && _baudRateContact.value != null) _baudInput.text = Std.string(_baudRateContact.value);
        if (_isOpenContact != null && _isOpenContact.value != null) updateConnectionStatus(_isOpenContact.value == true);
        if (_rxDataContact != null && _rxDataContact.value != null)
        {
            var rxStr = Std.string(_rxDataContact.value);
            if (rxStr != "" && rxStr != _lastRxData) appendRxData(rxStr);
        }
        if (_errorContact != null && _errorContact.value != null)
        {
            var errStr = Std.string(_errorContact.value);
            if (errStr != "" && errStr != _lastError) { _errorDisplay.text = "Error: " + errStr; _lastError = errStr; }
        }
        #if html5
        if (_bufferSizeContact != null && _bufferSizeContact.value != null) { _currentBufferSize = Std.int(_bufferSizeContact.value); _bufferSizeInput.text = Std.string(_currentBufferSize); }
        if (_chunkSizeContact != null && _chunkSizeContact.value != null) { _currentChunkSize = Std.int(_chunkSizeContact.value); _chunkSizeInput.text = Std.string(_currentChunkSize); }
        if (_enabledContact != null && _enabledContact.value != null) { _currentEnabled = (_enabledContact.value == true); updateEnabledButton(); }
        #end
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;
        if (contact == _isOpenContact) updateConnectionStatus(newValue == true);
        else if (contact == _rxDataContact && newValue != null && newValue != "") appendRxData(Std.string(newValue));
        else if (contact == _rxTickContact && newValue == true) { pulseLed(_rxLed, 0x00FF00, 0x003300); _rxLedTimer = _ledPulseDuration; }
        else if (contact == _txTickContact && newValue == true) { pulseLed(_txLed, 0x00AAFF, 0x001133); _txLedTimer = _ledPulseDuration; }
        else if (contact == _errorTickContact && newValue == true) { pulseLed(_errLed, 0xFF4444, 0x330000); _errLedTimer = _ledPulseDuration; }
        else if (contact == _portNameContact)
        {
            #if (cpp && !android)
            if (_portInput != null && newValue != null) _portInput.text = Std.string(newValue);
            #elseif html5
            if (_selectedPortInfo != null && newValue != null) _selectedPortInfo.text = Std.string(newValue);
            #end
        }
        else if (contact == _errorContact)
        {
            if (newValue != null && newValue != "") { _errorDisplay.text = "Error: " + Std.string(newValue); _lastError = Std.string(newValue); }
            else { _errorDisplay.text = ""; _lastError = ""; }
        }
    }

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

    private function appendRxData(data:String):Void
    {
        if (_rxDisplay == null) return;
        _lastRxData = data;
        var currentText = _rxDisplay.text;
        if (currentText.length > 2000) currentText = currentText.substr(currentText.length - 1000);
        _rxDisplay.text = currentText + data;
        _rxDisplay.scrollV = _rxDisplay.maxScrollV;
    }

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

    #if cpp
    private function onPortNameChanged(e:Event):Void { if (_portNameContact != null) _portNameContact.value = _portInput.text; }
    #end

    #if html5
    private function onSelectPortClick(e:MouseEvent):Void
    {
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) { var comAtom:library.drivers.ComPortAtom = cast atom; comAtom.openDevice(); }
        else if (_openContact != null) _openContact.value = true;
    }
    private function onBufferSizeChanged(e:Event):Void
    {
        if (_bufferSizeContact != null) {
            var size = Std.parseInt(_bufferSizeInput.text);
            if (size != null && size >= 256 && size <= 65536) { _currentBufferSize = size; _bufferSizeContact.value = size; }
        }
    }
    private function onChunkSizeChanged(e:Event):Void
    {
        if (_chunkSizeContact != null) {
            var size = Std.parseInt(_chunkSizeInput.text);
            if (size != null && size >= 1 && size <= 4096) { _currentChunkSize = size; _chunkSizeContact.value = size; }
        }
    }
    private function onEnabledClick(e:MouseEvent):Void
    {
        _currentEnabled = !_currentEnabled; updateEnabledButton();
        if (_enabledContact != null) _enabledContact.value = _currentEnabled;
    }
    private function updateEnabledButton():Void
    {
        if (_enabledBtn == null || _enabledLabel == null) return;
        if (_currentEnabled) {
            _enabledBtn.graphics.clear(); _enabledBtn.graphics.beginFill(_colorActive); _enabledBtn.graphics.drawRoundRect(0, 0, 70, 26, 4, 4); _enabledBtn.graphics.endFill();
            _enabledLabel.textColor = 0x000000; _enabledLabel.text = "ON";
        } else {
            _enabledBtn.graphics.clear(); _enabledBtn.graphics.beginFill(_colorInactive); _enabledBtn.graphics.drawRoundRect(0, 0, 70, 26, 4, 4); _enabledBtn.graphics.endFill();
            _enabledLabel.textColor = _colorMuted; _enabledLabel.text = "OFF";
        }
    }
    #end

    private function onBaudRateChanged(e:Event):Void
    {
        if (_baudRateContact != null) {
            var baud = Std.parseInt(_baudInput.text);
            if (baud != null && baud > 0) _baudRateContact.value = baud;
        }
    }

    private function onOpenClick(e:MouseEvent):Void
    {
        #if (cpp && !android)
        if (_portNameContact != null && _portInput != null) _portNameContact.value = _portInput.text;
        #end
        var baud = Std.parseInt(_baudInput.text);
        if (_baudRateContact != null && baud != null && baud > 0) _baudRateContact.value = baud;
        #if html5
        if (atom != null && Std.isOfType(atom, library.drivers.ComPortAtom)) { var comAtom:library.drivers.ComPortAtom = cast atom; comAtom.openDevice(); }
        else if (_openContact != null) _openContact.value = true;
        #else
        if (_openContact != null) _openContact.value = true;
        #end
    }

    private function onCloseClick(e:MouseEvent):Void { if (_closeContact != null) _closeContact.value = true; }
    private function onSendClick(e:MouseEvent):Void { sendTxData(); }
    private function onTxKeyDown(e:KeyboardEvent):Void { if (e.keyCode == Keyboard.ENTER) sendTxData(); }
    
    private function sendTxData():Void
    {
        if (_txDataContact != null) _txDataContact.value = _txInput.text;
        if (_sendContact != null) _sendContact.value = true;
    }

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

    // Impulsys Handlers
    private function onComPortStatus(impulse: Impulse): Void
    {
        if (impulse.data != null && _statusBar != null)
        {
            _statusBar.text = Std.string(impulse.data);
            var statusStr = Std.string(impulse.data);
            if (statusStr.indexOf("Connected") >= 0) updateConnectionStatus(true);
            else updateConnectionStatus(false);
        }
    }

    private function onComPortRx(impulse: Impulse): Void
    {
        if (impulse.data != null) appendRxData(Std.string(impulse.data));
    }

    private function onComPortError(impulse: Impulse): Void
    {
        if (impulse.data != null && _errorDisplay != null)
        {
            _errorDisplay.text = "Error: " + Std.string(impulse.data);
            _lastError = Std.string(impulse.data);
        }
    }

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
    }

    override public function dispose():Void
    {
        if (stage != null) stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        
        if (_onComPortStatus != null) Impulsys.removeImpulse(EventType.COMPORT_STATUS, _onComPortStatus);
        if (_onComPortRx != null) Impulsys.removeImpulse(EventType.COMPORT_RX_DATA, _onComPortRx);
        if (_onComPortError != null) Impulsys.removeImpulse(EventType.COMPORT_ERROR, _onComPortError);
        
        if (_openBtn != null) _openBtn.removeEventListener(MouseEvent.CLICK, onOpenClick);
        if (_closeBtn != null) _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);
        if (_sendBtn != null) _sendBtn.removeEventListener(MouseEvent.CLICK, onSendClick);
        
        #if cpp
        if (_dtrBtn != null) _dtrBtn.removeEventListener(MouseEvent.CLICK, onDTRClick);
        if (_portInput != null) _portInput.removeEventListener(Event.CHANGE, onPortNameChanged);
        #elseif html5
        if (_selectPortBtn != null) _selectPortBtn.removeEventListener(MouseEvent.CLICK, onSelectPortClick);
        if (_bufferSizeInput != null) _bufferSizeInput.removeEventListener(Event.CHANGE, onBufferSizeChanged);
        if (_chunkSizeInput != null) _chunkSizeInput.removeEventListener(Event.CHANGE, onChunkSizeChanged);
        if (_enabledBtn != null) _enabledBtn.removeEventListener(MouseEvent.CLICK, onEnabledClick);
        #elseif android
        if (_scanBtn != null) _scanBtn.removeEventListener(MouseEvent.CLICK, onScanClick);
        if (_clearBtn != null) _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        for (item in _deviceItems) item.removeEventListener(MouseEvent.CLICK, onDeviceClick);
        _deviceItems = null; _deviceCheckboxes = null; _deviceLabels = null; _scannedDevices = null;
        #end
        
        if (_baudInput != null) _baudInput.removeEventListener(Event.CHANGE, onBaudRateChanged);
        if (_txInput != null) _txInput.removeEventListener(KeyboardEvent.KEY_DOWN, onTxKeyDown);
        
        _bg = null; _header = null; _titleLabel = null; _portLabel = null; _portInput = null;
        _baudLabel = null; _baudInput = null; _openBtn = null; _closeBtn = null; _dtrBtn = null; _dtrLabel = null;
        _txSection = null; _txInput = null; _sendBtn = null; _rxSection = null; _rxDisplay = null;
        _statusLed = null; _statusGlow = null; _rxLed = null; _txLed = null; _errLed = null;
        _statusBar = null; _errorDisplay = null;
        _portNameContact = null; _baudRateContact = null; _openContact = null; _closeContact = null;
        _sendContact = null; _txDataContact = null; _setDTRContact = null; _isOpenContact = null;
        _rxDataContact = null; _rxTickContact = null; _txTickContact = null; _errorContact = null; _errorTickContact = null;
        
        #if html5
        _selectPortBtn = null; _selectedPortInfo = null; _bufferSizeInput = null; _chunkSizeInput = null;
        _enabledBtn = null; _enabledLabel = null; _bufferSizeLabel = null; _chunkSizeLabel = null;
        _bufferSizeContact = null; _chunkSizeContact = null; _enabledContact = null;
        #end
        #if android
        _scanBtn = null; _clearBtn = null; _deviceListContainer = null; _deviceListBg = null;
        _selectedInfo = null; _noDevicesLabel = null;
        #end
        
        super.dispose();
    }
}