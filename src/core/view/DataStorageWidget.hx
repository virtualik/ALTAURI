package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;

/**
 * DATA STORAGE WIDGET v1.0
 * Interactive control panel for DataStorageAtom (зеркало FileReaderWidget).
 * Этап 4a-2, Task 145. Spec: SPEC_STAGE4A_DATASTORAGE.md §3.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DataStorageWidget                                                     │
 * │                                                                         │
 * │   ────────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: Data Storage]                             [LED ●]    │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                               │     │
 * │   │  Name: [ —                  ]                                 │     │
 * │   │                                                               │     │
 * │   │  [ READ ]  [ CLEAR ]  [ LOCK ]                                │     │
 * │   │                                                               │     │
 * │   │  Kind: text   Stores: 1   Size: 9 B                           │     │
 * │   │                                                               │     │
 * │   │  Error: ___________________                                   │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget READS state from atom's contacts (Databank)                    │
 * │   Widget WRITES to atom's contacts on user interaction                  │
 * │                                                                         │
 * │   Отличия от Читателя: нет [Select] и диалогов вовсе — Хранилищу нечего │
 * │   выбирать на диске (весь ввод приходит по проводам); третья кнопка —   │
 * │   [ARM]/[LOCK]: впускной гейт [enabled] (default false — «карман        │
 * │   застёгнут», решение автора). Кнопка показывает действие: LOCK когда    │
 * │   гейт открыт, ARM когда закрыт.                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DataStorageWidget extends DeviceView
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;

    private var _nameLabel:TextField;
    private var _nameDisplay:TextField;       // только показ (выход fileName)

    private var _readBtn:Sprite;
    private var _clearBtn:Sprite;
    private var _armBtn:Sprite;
    private var _armBtnLabel:TextField;       // ARM / LOCK — динамическая метка

    private var _statsLabel:TextField;
    private var _errorLabel:TextField;

    // =========================================================================
    // CONTACTS
    // =========================================================================
    private var _enabledContact:Contact;
    private var _dataContact:Contact;         // не рисуется: тяжёлый груз (П2)
    private var _isBytesContact:Contact;
    private var _clearContact:Contact;
    private var _readContact:Contact;

    private var _hasDataContact:Contact;
    private var _kindContact:Contact;
    private var _textContact:Contact;
    private var _bytesContact:Contact;
    private var _fileNameContact:Contact;
    private var _sizeContact:Contact;
    private var _storeCountContact:Contact;
    private var _errorContact:Contact;
    private var _errorTickContact:Contact;

    // =========================================================================
    // STATE (только UI-зеркало; истина — в банке атома)
    // =========================================================================
    private var _hasData:Bool = false;
    private var _kind:String = "empty";
    private var _fileSize:Int = 0;
    private var _storeCount:Int = 0;
    private var _displayedName:String = "";
    private var _armed:Bool = false;
    private var _lastError:String = "";

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

        _enabledContact = atom.getInput("enabled");
        _dataContact = atom.getInput("data");
        _isBytesContact = atom.getInput("isBytes");
        _clearContact = atom.getInput("clear");
        _readContact = atom.getInput("read");

        _hasDataContact = atom.getOutput("hasData");
        _kindContact = atom.getOutput("kind");
        _textContact = atom.getOutput("text");
        _bytesContact = atom.getOutput("bytes");
        _fileNameContact = atom.getOutput("fileName");
        _sizeContact = atom.getOutput("size");
        _storeCountContact = atom.getOutput("storeCount");
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
        _titleLabel.text = "  DATA STORAGE";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 28;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // Status LED (зелёный = банк непустой)
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

        // === NAME (только показ — это ВЫХОД атома, из Cargo) ===
        _nameLabel = createLabel("Name:");
        _nameLabel.y = yPos;
        addChild(_nameLabel);

        _nameDisplay = createDisplayField("—", 180);
        _nameDisplay.x = 50;
        _nameDisplay.y = yPos;
        addChild(_nameDisplay);

        yPos += 34;

        // === CONTROL BUTTONS (все — через контакты: диалогов нет,
        //     зависимости от user gesture нет) ===
        _readBtn = createActionButton("READ", 0x225533, onReadClick);
        _readBtn.x = 10;
        _readBtn.y = yPos;
        addChild(_readBtn);

        _clearBtn = createActionButton("CLEAR", 0x553322, onClearClick);
        _clearBtn.x = 75;
        _clearBtn.y = yPos;
        addChild(_clearBtn);

        _armBtn = createActionButton("ARM", 0x333344, onArmClick);
        _armBtn.x = 140;
        _armBtn.y = yPos;
        addChild(_armBtn);

        yPos += 36;

        // === STATISTICS ===
        _statsLabel = new TextField();
        _statsLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        _statsLabel.text = "Kind: empty   Stores: 0   Size: 0 B";
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
        updateArmButton();
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

    /** Поле-показ: выглядит как поле ввода, но не редактируется. */
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

    /** Кнопка-гейт: LOCK (гейт открыт — нажатие застегнёт) / ARM (закрыт). */
    private function updateArmButton():Void
    {
        if (_armBtn == null) return;
        _armBtn.graphics.clear();
        _armBtn.graphics.beginFill(_armed ? 0x116688 : _colorInactive);
        _armBtn.graphics.drawRoundRect(0, 0, 60, 26, 4, 4);
        _armBtn.graphics.endFill();

        if (_armBtnLabel == null)
        {
            _armBtnLabel = new TextField();
            _armBtnLabel.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
            _armBtnLabel.width = 60;
            _armBtnLabel.height = 26;
            _armBtnLabel.selectable = false;
            _armBtnLabel.mouseEnabled = false;
            _armBtn.addChild(_armBtnLabel);
        }
        _armBtnLabel.text = _armed ? "LOCK" : "ARM";
    }

    // =========================================================================
    // ATOM SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void
    {
        if (_hasDataContact != null && _hasDataContact.value != null)
        {
            _hasData = (_hasDataContact.value == true);
            updateConnectionStatus(_hasData);
        }

        if (_kindContact != null && _kindContact.value != null)
        {
            _kind = Std.string(_kindContact.value);
        }

        if (_storeCountContact != null && _storeCountContact.value != null)
        {
            _storeCount = Std.int(_storeCountContact.value);
        }

        if (_sizeContact != null && _sizeContact.value != null)
        {
            _fileSize = Std.int(_sizeContact.value);
        }

        if (_fileNameContact != null && _fileNameContact.value != null)
        {
            updateNameDisplay(Std.string(_fileNameContact.value));
        }

        if (_enabledContact != null && _enabledContact.value != null)
        {
            _armed = (_enabledContact.value == true);
            updateArmButton();
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

        // data/isBytes — не рисуются: тяжёлый груз и настройка трактовки
        if (contact == _hasDataContact)
        {
            _hasData = (newValue == true);
            updateConnectionStatus(_hasData);
        }
        else if (contact == _kindContact)
        {
            _kind = Std.string(newValue);
            updateStatsDisplay();
        }
        else if (contact == _storeCountContact)
        {
            _storeCount = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _sizeContact)
        {
            _fileSize = Std.int(newValue);
            updateStatsDisplay();
        }
        else if (contact == _fileNameContact)
        {
            if (newValue != null) updateNameDisplay(Std.string(newValue));
        }
        else if (contact == _enabledContact)
        {
            _armed = (newValue == true);
            updateArmButton();
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
    private function updateNameDisplay(rawName:String):Void
    {
        var name:String = rawName;
        if (name == "") name = "—";
        if (_nameDisplay != null && _nameDisplay.text != name)
        {
            _nameDisplay.text = name;
        }
        _displayedName = name;
    }

    private function updateConnectionStatus(hasData:Bool):Void
    {
        if (hasData)
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
        _statsLabel.text = 'Kind: $_kind   Stores: $_storeCount   Size: $sizeStr';
    }

    private function formatFileSize(bytes:Int):String
    {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return _toFixed(bytes / 1024, 1) + " KB";
        return _toFixed(bytes / (1024 * 1024), 1) + " MB";
    }

    // =========================================================================
    // EVENT HANDLERS (все — через контакты: диалогов и user-gesture нет)
    // =========================================================================
    private function onReadClick(e:MouseEvent):Void
    {
        if (_readContact != null)
        {
            _readContact.value = true;
        }
    }

    private function onClearClick(e:MouseEvent):Void
    {
        if (_clearContact != null)
        {
            _clearContact.value = true;
        }
    }

    private function onArmClick(e:MouseEvent):Void
    {
        if (_enabledContact != null)
        {
            _enabledContact.value = !_armed;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLOAT FORMATTING HELPER (копия FileReaderWidget — идентичное поведение)
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
        if (_readBtn != null) _readBtn.removeEventListener(MouseEvent.CLICK, onReadClick);
        if (_clearBtn != null) _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        if (_armBtn != null) _armBtn.removeEventListener(MouseEvent.CLICK, onArmClick);

        _bg = null;
        _header = null;
        _titleLabel = null;
        _statusLed = null;
        _statusGlow = null;
        _nameLabel = null;
        _nameDisplay = null;
        _readBtn = null;
        _clearBtn = null;
        _armBtn = null;
        _armBtnLabel = null;
        _statsLabel = null;
        _errorLabel = null;

        _enabledContact = null;
        _dataContact = null;
        _isBytesContact = null;
        _clearContact = null;
        _readContact = null;
        _hasDataContact = null;
        _kindContact = null;
        _textContact = null;
        _bytesContact = null;
        _fileNameContact = null;
        _sizeContact = null;
        _storeCountContact = null;
        _errorContact = null;
        _errorTickContact = null;

        super.dispose();
    }
}
