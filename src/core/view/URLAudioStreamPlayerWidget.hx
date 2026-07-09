package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;

/**
 * URL AUDIO STREAM PLAYER WIDGET v1.1 (URL Input Added)
 * 
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │  URL AUDIO PLAYER                                          [LED]    │
 * ├─────────────────────────────────────────────────────────────────────┤
 * │  URL: [________________________________________]                    │
 * │                                                                     │
 * │  [PLAY/STOP]   Vol: [____]                                          │
 * │                                                                     │
 * │  Status: ●  Error: ___________________                              │
 * └─────────────────────────────────────────────────────────────────────┘
 */
class URLAudioStreamPlayerWidget extends DeviceView
{
    private var _bg:Sprite;
    private var _titleField:TextField;
    private var _statusLed:Sprite;
    private var _errorField:TextField;
    private var _playBtn:Sprite;
    private var _playLabel:TextField;
    
    // === v1.1: URL Input ===
    private var _urlInput:TextField;
    private var _urlLabel:TextField;
    
    // === v1.1: Volume Input ===
    private var _volumeInput:TextField;
    private var _volumeLabel:TextField;
    
    private var _statusLabel:TextField;
    
    private var _urlContact:Contact;
    private var _playContact:Contact;
    private var _volumeContact:Contact;
    private var _isPlayingContact:Contact;
    private var _isBufferingContact:Contact;
    private var _errorContact:Contact;
    private var _stateContact:Contact;
    
    private var _isPlaying:Bool = false;
    private var _isBuffering:Bool = false;
    
    public var widgetWidth:Float = 280;
    public var widgetHeight:Float = 140;
    
    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }
    
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
        _playContact = atom.getInput("play");
        _volumeContact = atom.getInput("volume");
        _isPlayingContact = atom.getOutput("isPlaying");
        _isBufferingContact = atom.getOutput("isBuffering");
        _errorContact = atom.getOutput("error");
        _stateContact = atom.getOutput("state");
    }
    
    override private function onActivate():Void
    {
        findContacts();
        syncFromAtom();
    }
    
    private function buildUI():Void
    {
        var yPos:Float = 0;
        
        // Background
        _bg = new Sprite();
        _bg.graphics.beginFill(0x1a1a24);
        _bg.graphics.lineStyle(1, 0x333344);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _bg.graphics.endFill();
        addChild(_bg);
        
        // Title
        _titleField = new TextField();
        _titleField.defaultTextFormat = new TextFormat("_sans", 10, 0x888888, true);
        _titleField.text = "URL AUDIO PLAYER";
        _titleField.width = widgetWidth - 30;
        _titleField.height = 16;
        _titleField.x = 5;
        _titleField.y = 4;
        addChild(_titleField);
        
        // Status LED
        _statusLed = new Sprite();
        _statusLed.graphics.beginFill(0x444444);
        _statusLed.graphics.drawCircle(0, 0, 4);
        _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 14;
        _statusLed.y = 12;
        addChild(_statusLed);
        
        yPos = 24;
        
        // === v1.1: URL Input ===
        _urlLabel = new TextField();
        _urlLabel.defaultTextFormat = new TextFormat("_sans", 9, 0x666688);
        _urlLabel.text = "URL:";
        _urlLabel.width = 30;
        _urlLabel.height = 16;
        _urlLabel.x = 5;
        _urlLabel.y = yPos;
        addChild(_urlLabel);
        
        _urlInput = new TextField();
        _urlInput.type = TextFieldType.INPUT;
        _urlInput.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        _urlInput.width = widgetWidth - 45;
        _urlInput.height = 18;
        _urlInput.x = 35;
        _urlInput.y = yPos;
        _urlInput.border = true;
        _urlInput.borderColor = 0x00AAFF;
        _urlInput.background = true;
        _urlInput.backgroundColor = 0x0d0d18;
        _urlInput.text = "";
        _urlInput.addEventListener(Event.CHANGE, onUrlChanged);
        _urlInput.addEventListener(KeyboardEvent.KEY_DOWN, onUrlKeyDown);
        addChild(_urlInput);
        
        yPos += 24;
        
        // Play Button
        _playBtn = new Sprite();
        _playBtn.buttonMode = true;
        _playBtn.useHandCursor = true;
        _playBtn.graphics.beginFill(0x2a2a3a);
        _playBtn.graphics.lineStyle(1, 0x00AAFF);
        _playBtn.graphics.drawRoundRect(0, 0, 70, 24, 4, 4);
        _playBtn.graphics.endFill();
        _playBtn.x = 10;
        _playBtn.y = yPos;
        _playBtn.addEventListener(MouseEvent.CLICK, onPlayClick);
        addChild(_playBtn);
        
        _playLabel = new TextField();
        _playLabel.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true);
        _playLabel.text = "PLAY";
        _playLabel.width = 70;
        _playLabel.height = 24;
        _playLabel.x = 10;
        _playLabel.y = yPos + 2;
        _playLabel.selectable = false;
        _playLabel.mouseEnabled = false;
        addChild(_playLabel);
        
        // === v1.1: Volume Input ===
        _volumeLabel = new TextField();
        _volumeLabel.defaultTextFormat = new TextFormat("_sans", 9, 0x666688);
        _volumeLabel.text = "Vol:";
        _volumeLabel.width = 30;
        _volumeLabel.height = 16;
        _volumeLabel.x = 90;
        _volumeLabel.y = yPos + 4;
        addChild(_volumeLabel);
        
        _volumeInput = new TextField();
        _volumeInput.type = TextFieldType.INPUT;
        _volumeInput.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        _volumeInput.width = 50;
        _volumeInput.height = 18;
        _volumeInput.x = 120;
        _volumeInput.y = yPos + 2;
        _volumeInput.border = true;
        _volumeInput.borderColor = 0x00AAFF;
        _volumeInput.background = true;
        _volumeInput.backgroundColor = 0x0d0d18;
        _volumeInput.text = "1.0";
        _volumeInput.addEventListener(Event.CHANGE, onVolumeChanged);
        addChild(_volumeInput);
        
        yPos += 30;
        
        // Status label
        _statusLabel = new TextField();
        _statusLabel.defaultTextFormat = new TextFormat("_sans", 9, 0x666688);
        _statusLabel.text = "Status: Idle";
        _statusLabel.width = widgetWidth - 10;
        _statusLabel.height = 14;
        _statusLabel.x = 5;
        _statusLabel.y = yPos;
        addChild(_statusLabel);
        
        yPos += 16;
        
        // Error field
        _errorField = new TextField();
        _errorField.defaultTextFormat = new TextFormat("_sans", 9, 0xFF5555);
        _errorField.text = "";
        _errorField.width = widgetWidth - 10;
        _errorField.height = 28;
        _errorField.x = 5;
        _errorField.y = yPos;
        _errorField.wordWrap = true;
        addChild(_errorField);
    }
    
    private function onUrlChanged(e:Event):Void
    {
        if (_urlContact != null)
        {
            _urlContact.value = _urlInput.text;
        }
    }
    
    private function onUrlKeyDown(e:KeyboardEvent):Void
    {
        if (e.keyCode == Keyboard.ENTER)
        {
            if (_urlContact != null)
            {
                _urlContact.value = _urlInput.text;
            }
            if (stage != null) stage.focus = null;
        }
        e.stopPropagation();
    }
    
    private function onVolumeChanged(e:Event):Void
    {
        if (_volumeContact != null)
        {
            var vol = Std.parseFloat(_volumeInput.text);
            if (!Math.isNaN(vol) && vol >= 0.0 && vol <= 2.0)
            {
                _volumeContact.value = vol;
            }
        }
    }
    
    private function onPlayClick(e:MouseEvent):Void
    {
        e.stopPropagation();
        
        // === v1.1: Push URL before play ===
        if (_urlContact != null && _urlInput.text != "")
        {
            _urlContact.value = _urlInput.text;
        }
        
        if (_playContact != null)
        {
            _playContact.value = !_isPlaying;
        }
    }
    
    override private function syncFromAtom():Void
    {
        // Sync URL from atom
        if (_urlContact != null && _urlContact.value != null)
        {
            var url = Std.string(_urlContact.value);
            if (_urlInput.text != url)
            {
                _urlInput.text = url;
            }
        }
        
        // Sync volume from atom
        if (_volumeContact != null && _volumeContact.value != null)
        {
            _volumeInput.text = Std.string(_volumeContact.value);
        }
        
        updateState();
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        updateState();
    }
    
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
        
        // Update LED
        var ledColor:Int = 0x444444;
        if (_isBuffering) ledColor = 0xFFAA00;
        else if (_isPlaying) ledColor = 0x00FF00;
        _statusLed.graphics.clear();
        _statusLed.graphics.beginFill(ledColor);
        _statusLed.graphics.drawCircle(0, 0, 4);
        _statusLed.graphics.endFill();
        
        // Update play button label
        _playLabel.text = _isPlaying ? "STOP" : "PLAY";
        
        // Update status
        if (_isBuffering)
        {
            _statusLabel.text = "Status: Buffering...";
            _statusLabel.textColor = 0xFFAA00;
        }
        else if (_isPlaying)
        {
            _statusLabel.text = "Status: Playing";
            _statusLabel.textColor = 0x00FF00;
        }
        else
        {
            _statusLabel.text = "Status: Idle";
            _statusLabel.textColor = 0x666688;
        }
        
        // Update error
        if (_errorContact != null && _errorContact.value != null)
        {
            var err:String = Std.string(_errorContact.value);
            _errorField.text = (err.length > 0) ? "⚠ " + err : "";
        }
        else
        {
            _errorField.text = "";
        }
    }
    
    override private function flushTransientState():Void
    {
        // Push URL and volume before deactivation
        if (_urlContact != null && _urlInput.text != "")
        {
            _urlContact.value = _urlInput.text;
        }
        if (_volumeContact != null)
        {
            var vol = Std.parseFloat(_volumeInput.text);
            if (!Math.isNaN(vol)) _volumeContact.value = vol;
        }
    }
    
    override public function dispose():Void
    {
        if (_playBtn != null)
        {
            _playBtn.removeEventListener(MouseEvent.CLICK, onPlayClick);
        }
        if (_urlInput != null)
        {
            _urlInput.removeEventListener(Event.CHANGE, onUrlChanged);
            _urlInput.removeEventListener(KeyboardEvent.KEY_DOWN, onUrlKeyDown);
        }
        if (_volumeInput != null)
        {
            _volumeInput.removeEventListener(Event.CHANGE, onVolumeChanged);
        }
        _bg = null;
        _titleField = null;
        _statusLed = null;
        _errorField = null;
        _playBtn = null;
        _playLabel = null;
        _urlInput = null;
        _urlLabel = null;
        _volumeInput = null;
        _volumeLabel = null;
        _statusLabel = null;
        _urlContact = null;
        _playContact = null;
        _volumeContact = null;
        _isPlayingContact = null;
        _isBufferingContact = null;
        _errorContact = null;
        _stateContact = null;
        super.dispose();
    }
}