// FILE: core/view/WEBSocketWidget.hx
#if cpp
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Contact;

/**
 * WEBSOCKET WIDGET v1.0
 * Interactive control panel for WebSocket communication.
 * 
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 */
class WEBSocketWidget extends DeviceView
{
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    
    private var _urlLabel:TextField;
    private var _urlInput:TextField;
    
    private var _connectBtn:Sprite;
    private var _disconnectBtn:Sprite;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    
    private var _sendSection:Sprite;
    private var _sendInput:TextField;
    private var _sendBtn:Sprite;
    
    private var _rxSection:Sprite;
    private var _rxDisplay:TextField;
    
    private var _statusBar:TextField;
    private var _errorDisplay:TextField;
    
    private var _urlContact:Contact;
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
    
    private var _lastRxData:String = "";
    private var _lastError:String = "";
    
    public var widgetWidth:Float = 300;
    public var widgetHeight:Float = 380;
    
    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }
    
    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorAccent:Int = 0x00AAFF;
    private var _colorActive:Int = 0x00FF88;
    private var _colorDanger:Int = 0xFF4444;
    private var _colorInactive:Int = 0x333344;
    private var _colorText:Int = 0xFFFFFF;
    private var _colorMuted:Int = 0x888899;
    private var _colorInputBg:Int = 0x0d0d18;
    
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
        
        _urlContact = atom.getInput("url");
        _connectContact = atom.getInput("connect");
        _disconnectContact = atom.getInput("disconnect");
        _sendContact = atom.getInput("send");
        _sendDataContact = atom.getInput("sendData");
        
        _isConnectedContact = atom.getOutput("isConnected");
        _receivedDataContact = atom.getOutput("receivedData");
        _receivedTickContact = atom.getOutput("receivedTick");
        _sentTickContact = atom.getOutput("sentTick");
        _errorContact = atom.getOutput("error");
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
        
        _bg = new Sprite();
        addChild(_bg);
        
        _header = new Sprite();
        _header.y = yPos;
        addChild(_header);
        
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = "  WEBSOCKET";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);
        
        _statusGlow = new Sprite();
        _statusGlow.graphics.beginFill(_colorDanger, 0.2);
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
        
        yPos += 32;
        
        _urlLabel = createLabel("URL");
        _urlLabel.y = yPos;
        addChild(_urlLabel);
        yPos += 18;
        
        _urlInput = createInputField("ws://localhost:8080", Std.int(widgetWidth - 20));
        _urlInput.x = 10;
        _urlInput.y = yPos;
        _urlInput.addEventListener(Event.CHANGE, onUrlChanged);
        addChild(_urlInput);
        yPos += 30;
        
        _connectBtn = createActionButton("CONNECT", 0x225533, onConnectClick);
        _connectBtn.x = 10;
        _connectBtn.y = yPos;
        addChild(_connectBtn);
        
        _disconnectBtn = createActionButton("DISCONNECT", 0x553322, onDisconnectClick);
        _disconnectBtn.x = 100;
        _disconnectBtn.y = yPos;
        addChild(_disconnectBtn);
        yPos += 36;
        
        _sendSection = new Sprite();
        _sendSection.y = yPos;
        addChild(_sendSection);
        
        var sendLabel = new TextField();
        sendLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        sendLabel.text = "SEND DATA";
        sendLabel.width = 60;
        sendLabel.height = 15;
        sendLabel.selectable = false;
        _sendSection.addChild(sendLabel);
        
        _sendInput = createInputField("", Std.int(widgetWidth - 80));
        _sendInput.x = 0;
        _sendInput.y = 15;
        _sendSection.addChild(_sendInput);
        
        _sendBtn = createActionButton("SEND", 0x224466, onSendClick);
        _sendBtn.x = widgetWidth - 62;
        _sendBtn.y = 14;
        _sendSection.addChild(_sendBtn);
        yPos += 52;
        
        _rxSection = new Sprite();
        _rxSection.y = yPos;
        addChild(_rxSection);
        
        var rxLabel = new TextField();
        rxLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        rxLabel.text = "RECEIVED DATA";
        rxLabel.width = 100;
        rxLabel.height = 15;
        rxLabel.selectable = false;
        _rxSection.addChild(rxLabel);
        
        _rxDisplay = new TextField();
        _rxDisplay.defaultTextFormat = new TextFormat("_typewriter", 11, _colorActive);
        _rxDisplay.text = "";
        _rxDisplay.width = widgetWidth - 20;
        _rxDisplay.height = 100;
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
        yPos += 125;
        
        _statusBar = new TextField();
        _statusBar.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statusBar.text = "Disconnected";
        _statusBar.width = 140;
        _statusBar.height = 16;
        _statusBar.x = 10;
        _statusBar.y = yPos;
        _statusBar.selectable = false;
        addChild(_statusBar);
        yPos += 22;
        
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
        
        _sendSection.graphics.clear();
        _sendSection.graphics.beginFill(0x0d0d18, 0.5);
        _sendSection.graphics.lineStyle(1, 0x222244);
        _sendSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 45, 4, 4);
        _sendSection.graphics.endFill();
        
        _rxSection.graphics.clear();
        _rxSection.graphics.beginFill(0x0d0d18, 0.5);
        _rxSection.graphics.lineStyle(1, 0x224422);
        _rxSection.graphics.drawRoundRect(0, 0, widgetWidth - 20, 120, 4, 4);
        _rxSection.graphics.endFill();
    }
    
    private function createLabel(text:String):TextField
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        tf.text = text;
        tf.width = 60;
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
        btn.graphics.drawRoundRect(0, 0, 80, 26, 4, 4);
        btn.graphics.endFill();
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label;
        tf.width = 80;
        tf.height = 26;
        tf.selectable = false;
        tf.mouseEnabled = false;
        btn.addChild(tf);
        btn.buttonMode = true;
        btn.useHandCursor = true;
        btn.addEventListener(MouseEvent.CLICK, callback);
        return btn;
    }
    
    override private function syncFromAtom():Void
    {
        if (_urlContact != null && _urlContact.value != null) {
            _urlInput.text = Std.string(_urlContact.value);
        }
        
        if (_isConnectedContact != null && _isConnectedContact.value != null) {
            updateConnectionStatus(_isConnectedContact.value == true);
        }
        
        if (_receivedDataContact != null && _receivedDataContact.value != null) {
            var rxStr = Std.string(_receivedDataContact.value);
            if (rxStr != "" && rxStr != _lastRxData) {
                appendRxData(rxStr);
            }
        }
        
        if (_errorContact != null && _errorContact.value != null) {
            var errStr = Std.string(_errorContact.value);
            if (errStr != "" && errStr != _lastError) {
                _errorDisplay.text = "Error: " + errStr;
                _lastError = errStr;
            }
        }
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;
        
        if (contact == _isConnectedContact) {
            updateConnectionStatus(newValue == true);
        } else if (contact == _receivedDataContact) {
            if (newValue != null && newValue != "") {
                appendRxData(Std.string(newValue));
            }
        } else if (contact == _errorContact) {
            if (newValue != null && newValue != "") {
                _errorDisplay.text = "Error: " + Std.string(newValue);
                _lastError = Std.string(newValue);
            } else {
                _errorDisplay.text = "";
                _lastError = "";
            }
        }
    }
    
    private function updateConnectionStatus(isConnected:Bool):Void
    {
        if (isConnected) {
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
        } else {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(0x440000);
            _statusLed.graphics.drawCircle(0, 0, 6);
            _statusLed.graphics.endFill();
            _statusGlow.visible = false;
            _statusBar.text = "Disconnected";
            _statusBar.textColor = _colorMuted;
        }
    }
    
    private function appendRxData(data:String):Void
    {
        if (_rxDisplay == null) return;
        _lastRxData = data;
        var currentText = _rxDisplay.text;
        
        if (currentText.length > 2000) {
            currentText = currentText.substr(currentText.length - 1000);
        }
        
        _rxDisplay.text = currentText + data + "\n";
        _rxDisplay.scrollV = _rxDisplay.maxScrollV;
    }
    
    private function onUrlChanged(e:Event):Void
    {
        if (_urlContact != null) {
            _urlContact.value = _urlInput.text;
        }
    }
    
    private function onConnectClick(e:MouseEvent):Void
    {
        if (_urlContact != null) {
            _urlContact.value = _urlInput.text;
        }
        if (_connectContact != null) {
            _connectContact.value = true;
        }
    }
    
    private function onDisconnectClick(e:MouseEvent):Void
    {
        if (_disconnectContact != null) {
            _disconnectContact.value = true;
        }
    }
    
    private function onSendClick(e:MouseEvent):Void
    {
        if (_sendDataContact != null) {
            _sendDataContact.value = _sendInput.text;
        }
        if (_sendContact != null) {
            _sendContact.value = true;
        }
    }
    
    override public function dispose():Void
    {
        if (_connectBtn != null) _connectBtn.removeEventListener(MouseEvent.CLICK, onConnectClick);
        if (_disconnectBtn != null) _disconnectBtn.removeEventListener(MouseEvent.CLICK, onDisconnectClick);
        if (_sendBtn != null) _sendBtn.removeEventListener(MouseEvent.CLICK, onSendClick);
        if (_urlInput != null) _urlInput.removeEventListener(Event.CHANGE, onUrlChanged);
        
        _bg = null;
        _header = null;
        _titleLabel = null;
        _urlLabel = null;
        _urlInput = null;
        _connectBtn = null;
        _disconnectBtn = null;
        _statusLed = null;
        _statusGlow = null;
        _sendSection = null;
        _sendInput = null;
        _sendBtn = null;
        _rxSection = null;
        _rxDisplay = null;
        _statusBar = null;
        _errorDisplay = null;
        
        _urlContact = null;
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
        
        super.dispose();
    }
}
#end