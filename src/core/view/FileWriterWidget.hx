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

/**
 * FILE WRITER WIDGET v1.1
 * Interactive control panel for FileWriterAtom (HTML5 File System Access API).
 * W-SYNC.2: live mirror fileName/mode contacts → UI ("Atom is Databank").
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   FileWriterWidget                                                      │
 * │                                                                         │
 * │   ────────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: File Writer]                              [LED ●]    │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                               │     │
 * │   │  File: [output.txt        ]  [Select]                         │     │
 * │   │  Mode: [Write ▼]                                              │     │
 * │   │                                                               │     │
 * │   │  [OPEN]  [CLOSE]  [FLUSH]  [CLEAR]                            │     │
 * │   │                                                               │     │
 * │   │  Writes: 123    Size: 4.5 KB                                  │     │
 * │   │                                                               │     │
 * │   │  Error: ___________________                                   │     │
 * │   │                                                               │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget READS state from atom's contacts (Databank)                    │
 * │   Widget WRITES to atom's contacts on user interaction                  │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Внёс извещение:
 * FileWriter Web API in Chrome Desktop on Android systems needs Chrome 130–132+ and Android 10+ (recommended)
 * 
 */
class FileWriterWidget extends DeviceView
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;
    
    private var _fileNameLabel:TextField;
    private var _fileNameInput:TextField;
    private var _selectBtn:Sprite;
    
    private var _modeLabel:TextField;
    private var _modeBtn:Sprite;
    private var _modeText:TextField;
    
    private var _openBtn:Sprite;
    private var _closeBtn:Sprite;
    private var _flushBtn:Sprite;
    private var _clearBtn:Sprite;
    
    private var _statsLabel:TextField;
    private var _errorLabel:TextField;
        
    private var _suggestedFileName:String = "output.txt";
    // =========================================================================
    // CONTACTS
    // =========================================================================
    private var _openContact:Contact;
    private var _closeContact:Contact;
    private var _flushContact:Contact;
    private var _clearContact:Contact;
    private var _fileNameContact:Contact;
    private var _modeContact:Contact;
    private var _isOpenContact:Contact;
    private var _writeCountContact:Contact;
    private var _fileSizeContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;
    
    // =========================================================================
    // STATE
    // =========================================================================
    // W-SYNC.2: editing guard — live mirror suppressed while typing
    private var _isEditingFileName:Bool = false;

    private var _isOpen:Bool = false;
    private var _writeCount:Int = 0;
    private var _fileSize:Int = 0;
    private var _currentMode:Int = 1; // 0=Write, 1=Append
    private var _lastError:String = "";
    
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 280;
    public var widgetHeight:Float = 220;
    
    override public function getWidgetSize():{width:Float, height:Float}
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
        
        _openContact = atom.getInput("open");
        _closeContact = atom.getInput("close");
        _flushContact = atom.getInput("flush");
        _clearContact = atom.getInput("clear");
        _fileNameContact = atom.getInput("fileName");
        _modeContact = atom.getInput("mode");
        
        _isOpenContact = atom.getOutput("isOpen");
        _writeCountContact = atom.getOutput("writeCount");
        _fileSizeContact = atom.getOutput("fileSize");
        _errorContact = atom.getOutput("error");
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
        var yPos:Float = 0;
        
        // === BACKGROUND ===
        _bg = new Sprite();
        addChild(_bg);
        
        // === HEADER ===
        _header = new Sprite();
        _header.y = yPos;
        addChild(_header);
        
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 13, _colorText, true);
        _titleLabel.text = "  FILE WRITER";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);
        
        // Status LED
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
        
        // === FILE NAME ===
        _fileNameLabel = createLabel("File:");
        _fileNameLabel.y = yPos;
        addChild(_fileNameLabel);
        
        _fileNameInput = createInputField("output.txt", 140);
        _fileNameInput.x = 50;
        _fileNameInput.y = yPos;
        _fileNameInput.addEventListener(Event.CHANGE, onFileNameChanged);
        _fileNameInput.addEventListener(FocusEvent.FOCUS_IN, onFileNameFocusIn);
        _fileNameInput.addEventListener(FocusEvent.FOCUS_OUT, onFileNameFocusOut);
        addChild(_fileNameInput);
        
        _selectBtn = createActionButton("Select", 0x224466, onSelectClick);
        _selectBtn.x = 195;
        _selectBtn.y = yPos;
        addChild(_selectBtn);
        
        yPos += 30;
        
        // === MODE ===
        _modeLabel = createLabel("Mode:");
        _modeLabel.y = yPos;
        addChild(_modeLabel);
        
        _modeBtn = new Sprite();
        _modeBtn.graphics.beginFill(_colorInactive);
        _modeBtn.graphics.drawRoundRect(0, 0, 100, 26, 4, 4);
        _modeBtn.graphics.endFill();
        _modeBtn.x = 50;
        _modeBtn.y = yPos;
        _modeBtn.buttonMode = true;
        _modeBtn.useHandCursor = true;
        _modeBtn.addEventListener(MouseEvent.CLICK, onModeClick);
        addChild(_modeBtn);
        
        _modeText = new TextField();
        _modeText.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        _modeText.text = "Append";
        _modeText.width = 100;
        _modeText.height = 26;
        _modeText.selectable = false;
        _modeText.mouseEnabled = false;
        _modeBtn.addChild(_modeText);
        
        yPos += 36;
        
        // === CONTROL BUTTONS ===
        _openBtn = createActionButton("OPEN", 0x225533, onOpenClick);
        _openBtn.x = 10;
        _openBtn.y = yPos;
        addChild(_openBtn);
        
        _closeBtn = createActionButton("CLOSE", 0x553322, onCloseClick);
        _closeBtn.x = 75;
        _closeBtn.y = yPos;
        addChild(_closeBtn);
        
                // FLUSH в html5 не нужен (не будет)
        #if !html5
        _flushBtn = createActionButton("FLUSH", 0x334455, onFlushClick);
        _flushBtn.x = 140;
        _flushBtn.y = yPos;
        addChild(_flushBtn);
        #end
        
        _clearBtn = createActionButton("CLEAR", 0x553333, onClearClick);
        _clearBtn.x = 205;
        _clearBtn.y = yPos;
        addChild(_clearBtn);
        
        yPos += 36;
        
        // === STATISTICS ===
        _statsLabel = new TextField();
        _statsLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statsLabel.text = "Writes: 0    Size: 0 B";
        _statsLabel.width = widgetWidth - 20;
        _statsLabel.height = 16;
        _statsLabel.x = 10;
        _statsLabel.y = yPos;
        _statsLabel.selectable = false;
        addChild(_statsLabel);
        
        yPos += 22;
        
        // === ERROR ===
        _errorLabel = new TextField();
        _errorLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorDanger);
        _errorLabel.text = "";
        _errorLabel.width = widgetWidth - 20;
        _errorLabel.height = 15;
        _errorLabel.x = 10;
        _errorLabel.y = yPos;
        _errorLabel.selectable = false;
        addChild(_errorLabel);
        
        // Final background rendering
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
    // UI HELPERS
    // =========================================================================
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
        btn.graphics.drawRoundRect(0, 0, 60, 26, 4, 4);
        btn.graphics.endFill();
        
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label;
        tf.width = 60;
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
    // ATOM SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
            if (_fileNameContact != null && _fileNameContact.value != null)
                {
                        _suggestedFileName = Std.string(_fileNameContact.value);
                        _fileNameInput.text = _suggestedFileName;
                }
        
        if (_modeContact != null && _modeContact.value != null)
        {
            _currentMode = Std.int(_modeContact.value);
            updateModeDisplay();
        }
        
        if (_isOpenContact != null && _isOpenContact.value != null)
        {
            _isOpen = (_isOpenContact.value == true);
            updateConnectionStatus(_isOpen);
        }
        
        if (_writeCountContact != null && _writeCountContact.value != null)
        {
            _writeCount = Std.int(_writeCountContact.value);
        }
        
        if (_fileSizeContact != null && _fileSizeContact.value != null)
        {
            _fileSize = Std.int(_fileSizeContact.value);
        }
        
        updateStatsDisplay();
        
        if (_errorContact != null && _errorContact.value != null)
        {
            var errStr = Std.string(_errorContact.value);
            if (errStr != "" && errStr != _lastError)
            {
                _errorLabel.text = "Error: " + errStr;
                _lastError = errStr;
            }
        }
    }
    
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;
        
        if (contact == _isOpenContact)
        {
            _isOpen = (newValue == true);
            updateConnectionStatus(_isOpen);
        }
        else if (contact == _writeCountContact)
        {
            _writeCount = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _fileSizeContact)
        {
            _fileSize = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _errorContact)
        {
            if (newValue != null && newValue != "")
            {
                _errorLabel.text = "Error: " + Std.string(newValue);
                _lastError = Std.string(newValue);
            }
            else
            {
                _errorLabel.text = "";
                _lastError = "";
            }
        }
        // W-SYNC.2: LIVE MIRROR input contacts → UI ("Atom is Databank")
        else if (contact == _fileNameContact)
        {
            // fileName → field; suppressed while the user is editing it
            if (!_isEditingFileName && newValue != null)
            {
                var fnStr = Std.string(newValue);
                if (_fileNameInput != null && _fileNameInput.text != fnStr)
                {
                    _fileNameInput.text = fnStr;
                    _suggestedFileName = fnStr;
                }
            }
        }
        else if (contact == _modeContact)
        {
            // mode → Mode button label (Write/Append)
            if (newValue != null)
            {
                var m:Int = Std.int(newValue);
                if (m != _currentMode)
                {
                    _currentMode = m;
                    updateModeDisplay();
                }
            }
        }
    }
    
    // =========================================================================
    // UI UPDATES
    // =========================================================================
    private function updateConnectionStatus(isOpen:Bool):Void
    {
        if (isOpen)
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
    
    private function updateModeDisplay():Void
    {
        if (_modeText != null)
        {
            _modeText.text = (_currentMode == 0) ? "Write" : "Append";
        }
    }
    
    private function updateStatsDisplay():Void
    {
        var sizeStr = formatFileSize(_fileSize);
        _statsLabel.text = 'Writes: $_writeCount    Size: $sizeStr';
    }
    
    private function formatFileSize(bytes:Int):String
    {
        if (bytes < 1024) return bytes + " B";
                if (bytes < 1024 * 1024) return _toFixed(bytes / 1024, 1) + " KB";
                return _toFixed(bytes / (1024 * 1024), 1) + " MB";
    }
    
    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    private function onFileNameChanged(e:Event):Void
    {
        if (_fileNameContact != null)
        {
            _fileNameContact.value = _fileNameInput.text;
        }
    }

    /** W-SYNC.2: focus guards — the live mirror is suppressed while typing. */
    private function onFileNameFocusIn(e:FocusEvent):Void
    {
        _isEditingFileName = true;
    }

    private function onFileNameFocusOut(e:FocusEvent):Void
    {
        _isEditingFileName = false;
        // Leaving the field: normalize display to the committed value
        if (_fileNameInput != null && _fileNameContact != null && _fileNameContact.value != null)
        {
            var fnStr = Std.string(_fileNameContact.value);
            if (_fileNameInput.text != fnStr)
            {
                _fileNameInput.text = fnStr;
                _suggestedFileName = fnStr;
            }
        }
    }
    
        private function onSelectClick(e:MouseEvent):Void
        {
                // CRITICAL FIX: Direct synchronous call to preserve user gesture context.
                // Do NOT use _openContact.value = true, as it destroys user gesture on older Android Chrome.
                if (atom != null && Std.isOfType(atom, library.drivers.FileWriterAtom))
                {
                        var writerAtom:library.drivers.FileWriterAtom = cast atom;
                        writerAtom.showFilePicker(_suggestedFileName);
                }
                else
                {
                        trace('FileWriterWidget: Atom is not FileWriterAtom or is null');
                }
        }
    
    private function onModeClick(e:MouseEvent):Void
    {
        _currentMode = (_currentMode == 0) ? 1 : 0;
        updateModeDisplay();
        
        if (_modeContact != null)
        {
            _modeContact.value = _currentMode;
        }
    }
    
        private function onOpenClick(e:MouseEvent):Void
        {
                // CRITICAL: Direct synchronous call to preserve user gesture context.
                // Do NOT use _openContact.value = true — that goes through readInputs() 
                // which loses the user gesture context.
                if (atom != null && Std.isOfType(atom, library.drivers.FileWriterAtom))
                {
                        var writerAtom:library.drivers.FileWriterAtom = cast atom;
                        writerAtom.showFilePicker(_suggestedFileName);
                }
                else
                {
                        trace('FileWriterWidget: Atom is not FileWriterAtom or is null');
                }
        }
    
    private function onCloseClick(e:MouseEvent):Void
    {
        if (_closeContact != null)
        {
            _closeContact.value = true;
        }
    }
    
    private function onFlushClick(e:MouseEvent):Void
    {
        if (_flushContact != null)
        {
            _flushContact.value = true;
        }
    }
    
    private function onClearClick(e:MouseEvent):Void
    {
        if (_clearContact != null)
        {
            _clearContact.value = true;
        }
    }
        
    // ═══════════════════════════════════════════════════════════════════════════
        // FLOAT FORMATTING HELPER (replaces JS-specific toFixed)
        // ═══════════════════════════════════════════════════════════════════════════
        // Haxe's Float type has no toFixed() method. This helper provides identical
        // behaviour: rounds to N decimal places and guarantees the decimal point is
        // present (e.g., 2 → "2.0", 1.567 → "1.6").
        //
        // Algorithm:
        //   1. Multiply by 10^decimals
        //   2. Math.round() to nearest integer
        //   3. Divide back
        //   4. Convert to string
        //   5. If no "." in string → append ".0"
        //   6. If fractional part shorter than `decimals` → pad with trailing zeros
        // ═══════════════════════════════════════════════════════════════════════════
        private static function _toFixed(value:Float, decimals:Int = 1):String
        {
                if (Math.isNaN(value) || !Math.isFinite(value)) return "0.0";

                var multiplier:Float = Math.pow(10, decimals);
                var rounded:Float = Math.round(value * multiplier) / multiplier;
                var s:String = Std.string(rounded);

                // Ensure decimal point exists (integer case: 2 → "2.0")
                if (s.indexOf(".") == -1)
                {
                        s += ".";
                        for (_ in 0...decimals) s += "0";
                        return s;
                }

                // Pad with trailing zeros if needed (e.g., "1.5" → "1.50" for decimals=2)
                var parts:Array<String> = s.split(".");
                var frac:String = parts[1];
                while (frac.length < decimals) frac += "0";

                return parts[0] + "." + frac;
        }
        
    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_fileNameInput != null)
        {
            _fileNameInput.removeEventListener(Event.CHANGE, onFileNameChanged);
            _fileNameInput.removeEventListener(FocusEvent.FOCUS_IN, onFileNameFocusIn);
            _fileNameInput.removeEventListener(FocusEvent.FOCUS_OUT, onFileNameFocusOut);
        }
        if (_selectBtn != null) _selectBtn.removeEventListener(MouseEvent.CLICK, onSelectClick);
        if (_modeBtn != null) _modeBtn.removeEventListener(MouseEvent.CLICK, onModeClick);
        if (_openBtn != null) _openBtn.removeEventListener(MouseEvent.CLICK, onOpenClick);
        if (_closeBtn != null) _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);
        #if !html5
        if (_flushBtn != null) _flushBtn.removeEventListener(MouseEvent.CLICK, onFlushClick);
        _flushBtn = null;
        #end
        if (_clearBtn != null) _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        
        _bg = null;
        _header = null;
        _titleLabel = null;
        _statusLed = null;
        _statusGlow = null;
        _fileNameLabel = null;
        _fileNameInput = null;
        _selectBtn = null;
        _modeLabel = null;
        _modeBtn = null;
        _modeText = null;
        _openBtn = null;
        _closeBtn = null;
        _flushBtn = null;
        _clearBtn = null;
        _statsLabel = null;
        _errorLabel = null;
        
        _openContact = null;
        _closeContact = null;
        _flushContact = null;
        _clearContact = null;
        _fileNameContact = null;
        _modeContact = null;
        _isOpenContact = null;
        _writeCountContact = null;
        _fileSizeContact = null;
        _errorContact = null;
        _errorTickContact = null;
        
        super.dispose();
    }
}
