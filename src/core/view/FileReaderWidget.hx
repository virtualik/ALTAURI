package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Contact;

/**
 * FILE READER WIDGET v1.0
 * An interactive control panel for FileReaderAtom (a mirror of FileWriterWidget).
 * Stage 4a-1, Task 140. Spec: SPEC_STAGE4A_FILEREADER.md §3.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   FileReaderWidget                                                      │
 * │                                                                         │
 * │   ────────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: File Reader]                              [LED ●]    │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                               │     │
 * │   │  File: [ report.txt          ]  [Select]                      │     │
 * │   │                                                               │     │
 * │   │  [ READ ]  [ CLOSE ]                                          │     │
 * │   │                                                               │     │
 * │   │  Reads: 1    Size: 2.3 KB                                     │     │
 * │   │                                                               │     │
 * │   │  Error: ___________________                                   │     │
 * │   │                                                               │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget READS state from atom's contacts (Databank)                    │
 * │   Widget WRITES to atom's contacts on user interaction                  │
 * │                                                                         │
 * │   Differences from the Writer: the file name is DISPLAY ONLY (it is the atom OUTPUT,       │
 * │   not an input field); no mode button - the Reader has nothing to configure.        │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class FileReaderWidget extends DeviceView
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
    private var _fileNameDisplay:TextField;   // display only (the atom output)
    private var _selectBtn:Sprite;

    private var _readBtn:Sprite;
    private var _closeBtn:Sprite;

    private var _statsLabel:TextField;
    private var _errorLabel:TextField;

    // =========================================================================
    // CONTACTS
    // =========================================================================
    private var _openContact:Contact;
    private var _closeContact:Contact;
    private var _readContact:Contact;
    private var _enabledContact:Contact;

    private var _isOpenContact:Contact;
    private var _dataContact:Contact;
    private var _fileNameContact:Contact;
    private var _sizeContact:Contact;
    private var _readCountContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _isOpen:Bool = false;
    private var _readCount:Int = 0;
    private var _fileSize:Int = 0;
    private var _lastError:String = "";
    private var _displayedName:String = "";

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 280;
    public var widgetHeight:Float = 175;

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
        _readContact = atom.getInput("read");
        _enabledContact = atom.getInput("enabled");

        _isOpenContact = atom.getOutput("isOpen");
        _dataContact = atom.getOutput("data");
        _fileNameContact = atom.getOutput("fileName");
        _sizeContact = atom.getOutput("size");
        _readCountContact = atom.getOutput("readCount");
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
        _titleLabel.text = "  FILE READER";
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

        // === FILE NAME (display only — this is the atom OUTPUT) ===
        _fileNameLabel = createLabel("File:");
        _fileNameLabel.y = yPos;
        addChild(_fileNameLabel);

        _fileNameDisplay = createDisplayField("—", 140);
        _fileNameDisplay.x = 50;
        _fileNameDisplay.y = yPos;
        addChild(_fileNameDisplay);

        _selectBtn = createActionButton("Select", 0x224466, onSelectClick);
        _selectBtn.x = 195;
        _selectBtn.y = yPos;
        addChild(_selectBtn);

        yPos += 34;

        // === CONTROL BUTTONS ===
        _readBtn = createActionButton("READ", 0x225533, onReadClick);
        _readBtn.x = 10;
        _readBtn.y = yPos;
        addChild(_readBtn);

        _closeBtn = createActionButton("CLOSE", 0x553322, onCloseClick);
        _closeBtn.x = 75;
        _closeBtn.y = yPos;
        addChild(_closeBtn);

        yPos += 36;

        // === STATISTICS ===
        _statsLabel = new TextField();
        _statsLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statsLabel.text = "Reads: 0    Size: 0 B";
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

    /** A display field: looks like the Writer's input field but is not editable. */
    private function createDisplayField(defaultText:String, width:Int):TextField
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
        tf.selectable = false;
        tf.mouseEnabled = false;
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
            updateNameDisplay(Std.string(_fileNameContact.value));
        }

        if (_isOpenContact != null && _isOpenContact.value != null)
        {
            _isOpen = (_isOpenContact.value == true);
            updateConnectionStatus(_isOpen);
        }

        if (_readCountContact != null && _readCountContact.value != null)
        {
            _readCount = Std.int(_readCountContact.value);
        }

        if (_sizeContact != null && _sizeContact.value != null)
        {
            _fileSize = Std.int(_sizeContact.value);
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
        else if (contact == _readCountContact)
        {
            _readCount = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _sizeContact)
        {
            _fileSize = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _fileNameContact)
        {
            // fileName - the atom OUTPUT: showing only the name (without the directory)
            if (newValue != null) updateNameDisplay(Std.string(newValue));
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
    }

    // =========================================================================
    // UI UPDATES
    // =========================================================================
    private function updateNameDisplay(fullPath:String):Void
    {
        // The widget shows only the file name; the full path lives in the contact
        var name:String = haxe.io.Path.withoutDirectory(fullPath);
        if (name == "") name = "—";
        if (_fileNameDisplay != null && _fileNameDisplay.text != name)
        {
            _fileNameDisplay.text = name;
        }
        _displayedName = name;
    }

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

    private function updateStatsDisplay():Void
    {
        var sizeStr = formatFileSize(_fileSize);
        _statsLabel.text = 'Reads: $_readCount    Size: $sizeStr';
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
    private function onSelectClick(e:MouseEvent):Void
    {
        // CRITICAL: Direct synchronous call to preserve user gesture context.
        // Do NOT use _openContact.value = true — that loses the gesture
        // (the FileWriterWidget.onOpenClick idiom).
        if (atom != null && Std.isOfType(atom, library.drivers.FileReaderAtom))
        {
            var readerAtom:library.drivers.FileReaderAtom = cast atom;
            readerAtom.showFilePicker();
        }
        else
        {
            trace('FileReaderWidget: Atom is not FileReaderAtom or is null');
        }
    }

    private function onReadClick(e:MouseEvent):Void
    {
        // Re-read the file from disk: there is no dialog -> no user gesture dependency,
        // a direct synchronous call (the Writer idiom).
        if (atom != null && Std.isOfType(atom, library.drivers.FileReaderAtom))
        {
            var readerAtom:library.drivers.FileReaderAtom = cast atom;
            readerAtom.rereadFile();
        }
        else
        {
            trace('FileReaderWidget: Atom is not FileReaderAtom or is null');
        }
    }

    private function onCloseClick(e:MouseEvent):Void
    {
        if (_closeContact != null)
        {
            _closeContact.value = true;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // A FLOAT FORMATTING HELPER (a copy of FileWriterWidget - identical behavior)
    // ═══════════════════════════════════════════════════════════════════════════
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
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_selectBtn != null) _selectBtn.removeEventListener(MouseEvent.CLICK, onSelectClick);
        if (_readBtn != null) _readBtn.removeEventListener(MouseEvent.CLICK, onReadClick);
        if (_closeBtn != null) _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);

        _bg = null;
        _header = null;
        _titleLabel = null;
        _statusLed = null;
        _statusGlow = null;
        _fileNameLabel = null;
        _fileNameDisplay = null;
        _selectBtn = null;
        _readBtn = null;
        _closeBtn = null;
        _statsLabel = null;
        _errorLabel = null;

        _openContact = null;
        _closeContact = null;
        _readContact = null;
        _enabledContact = null;
        _isOpenContact = null;
        _dataContact = null;
        _fileNameContact = null;
        _sizeContact = null;
        _readCountContact = null;
        _errorContact = null;
        _errorTickContact = null;

        super.dispose();
    }
}
