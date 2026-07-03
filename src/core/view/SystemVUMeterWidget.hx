#if cpp
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
 * SYSTEM VU METER WIDGET v2.0
 * Stereo VU meter widget for visualizing system audio levels.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * SystemVUMeterWidget is the FACE of SystemVUMeterAtom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SystemVUMeterWidget                                                   │
 * │                                                                         │
 * │   ┌───────────────────────────────────────────────────────────────┐     │
 * │   │  [Title: SYSTEM STEREO VU]                        [LED ●]    │     │
 * │   ├───────────────────────────────────────────────────────────────┤     │
 * │   │                                                               │     │
 * │   │  L ┌──────────────────────────────────────────────────┐  72%  │     │
 * │   │    │ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░      │        │     │
 * │   │    └──────────────────────────────────────────────────┘        │     │
 * │   │                                                               │     │
 * │   │  R ┌──────────────────────────────────────────────────┐  68%  │     │
 * │   │    │ ██████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░     │        │     │
 * │   │    └──────────────────────────────────────────────────┘        │     │
 * │   │                                                               │     │
 * │   │  L: -2.8 dB   R: -3.4 dB   CH: 2 (Stereo)                    │     │
 * │   │                                                               │     │
 * │   │  [CLIP L]  [CLIP R]                                           │     │
 * │   │                                                               │     │
 * │   │  Source: [ Speakers ▼ ]   (mode selection)                    │     │
 * │   │                                                               │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * │   Widget READS state from atom's contacts (Databank)                    │
 * │   Atom updates contacts via WASAPI polling in update(dt)                │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Features:
 * 1. Stereo VU bars (Green/Yellow/Red gradient)
 * 2. dBFS display for L/R channels
 * 3. Clip indicators with auto-fade
 * 4. Source mode selection (Speakers / Microphone)
 * 5. Channel count display
 */
class SystemVUMeterWidget extends DeviceView
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var BAR_WIDTH:Float   = 200;
    private static inline var BAR_HEIGHT:Float  = 14;
    private static inline var CLIP_TIMEOUT:Float = 0.3;

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    // Widget dimensions
    public var widgetWidth:Float  = 280;
    public var widgetHeight:Float = 200;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return { width: widgetWidth, height: widgetHeight };
    }

    // Background & Header
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleLabel:TextField;

    // LED indicator
    private var _statusLed:Sprite;
    private var _statusGlow:Sprite;

    // STEREO bars
    private var _barBgL:Sprite;
    private var _barFillGreenL:Sprite;
    private var _barFillYellowL:Sprite;
    private var _barFillRedL:Sprite;
    private var _barPercentLabelL:TextField;
    private var _barLabelL:TextField;

    private var _barBgR:Sprite;
    private var _barFillGreenR:Sprite;
    private var _barFillYellowR:Sprite;
    private var _barFillRedR:Sprite;
    private var _barPercentLabelR:TextField;
    private var _barLabelR:TextField;

    // dB Text fields
    private var _dbLabelL:TextField;
    private var _dbValueL:TextField;
    private var _dbLabelR:TextField;
    private var _dbValueR:TextField;
    private var _channelsLabel:TextField;

    // Clip indicators
    private var _clipIndicatorL:Sprite;
    private var _clipLabelL:TextField;
    private var _clipTimerL:Float = 0;

    private var _clipIndicatorR:Sprite;
    private var _clipLabelR:TextField;
    private var _clipTimerR:Float = 0;

    // Mode buttons
    private var _btnSpeakers:Sprite;
    private var _btnMic:Sprite;
    private var _sourceLabel:TextField;

    // =========================================================================
    // CONTACTS
    // =========================================================================
    private var _peakLContact:Contact;
    private var _peakRContact:Contact;
    private var _percentLContact:Contact;
    private var _percentRContact:Contact;
    private var _dB_LContact:Contact;
    private var _dB_RContact:Contact;
    private var _channelsContact:Contact;
    private var _activeContact:Contact;
    private var _clipLContact:Contact;
    private var _clipRContact:Contact;
    private var _modeContact:Contact;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _currentMode:Int = 0;

    // =========================================================================
    // COLORS
    // =========================================================================
    private var _colorBg:Int        = 0x1a1a24;
    private var _colorHeader:Int    = 0x2a2a3a;
    private var _colorAccent:Int    = 0x00AAFF;
    private var _colorText:Int      = 0xFFFFFF;
    private var _colorMuted:Int     = 0x888899;
    private var _colorGreen:Int     = 0x00CC44;
    private var _colorYellow:Int    = 0xCCAA00;
    private var _colorRed:Int       = 0xCC2222;
    private var _colorClipOff:Int   = 0x331111;
    private var _colorClipOn:Int    = 0xFF0000;
    private var _colorBtnActive:Int = 0x00AAFF;
    private var _colorBtnOff:Int    = 0x333344;

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
        _peakLContact    = atom.getOutput("peakL");
        _peakRContact    = atom.getOutput("peakR");
        _percentLContact = atom.getOutput("percentL");
        _percentRContact = atom.getOutput("percentR");
        _dB_LContact     = atom.getOutput("dB_L");
        _dB_RContact     = atom.getOutput("dB_R");
        _channelsContact = atom.getOutput("channels");
        _activeContact   = atom.getOutput("active");
        _clipLContact    = atom.getOutput("clipL");
        _clipRContact    = atom.getOutput("clipR");
        _modeContact     = atom.getInput("mode");
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
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 11, _colorText, true);
        _titleLabel.text = "  SYSTEM STEREO VU";
        _titleLabel.width = widgetWidth - 40;
        _titleLabel.height = 26;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // LED
        _statusGlow = new Sprite();
        _statusGlow.graphics.beginFill(_colorAccent, 0.15);
        _statusGlow.graphics.drawCircle(0, 0, 10);
        _statusGlow.graphics.endFill();
        _statusGlow.x = widgetWidth - 16;
        _statusGlow.y = 13;
        _statusGlow.visible = false;
        _header.addChild(_statusGlow);

        _statusLed = new Sprite();
        _statusLed.graphics.beginFill(0x003344);
        _statusLed.graphics.drawCircle(0, 0, 4);
        _statusLed.graphics.endFill();
        _statusLed.x = widgetWidth - 16;
        _statusLed.y = 13;
        _header.addChild(_statusLed);
        yPos += 30;

        // === STEREO BARS ===
        // --- LEFT CHANNEL ---
        _barLabelL = createLabel("L", 10, yPos + 2);
        addChild(_barLabelL);

        var barYL:Float = yPos;
        _barBgL = new Sprite();
        _barBgL.graphics.beginFill(0x0d0d18);
        _barBgL.graphics.lineStyle(1, 0x333344);
        _barBgL.graphics.drawRect(0, 0, BAR_WIDTH, BAR_HEIGHT);
        _barBgL.graphics.endFill();
        _barBgL.x = 25;
        _barBgL.y = barYL;
        addChild(_barBgL);

        _barFillGreenL = new Sprite();
        _barFillGreenL.x = _barBgL.x + 1;
        _barFillGreenL.y = barYL + 1;
        addChild(_barFillGreenL);

        _barFillYellowL = new Sprite();
        _barFillYellowL.y = barYL + 1;
        addChild(_barFillYellowL);

        _barFillRedL = new Sprite();
        _barFillRedL.y = barYL + 1;
        addChild(_barFillRedL);

        _barPercentLabelL = new TextField();
        _barPercentLabelL.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText, true);
        _barPercentLabelL.text = "0%";
        _barPercentLabelL.width = 35;
        _barPercentLabelL.height = BAR_HEIGHT;
        _barPercentLabelL.x = _barBgL.x + BAR_WIDTH + 4;
        _barPercentLabelL.y = barYL;
        _barPercentLabelL.selectable = false;
        _barPercentLabelL.mouseEnabled = false;
        addChild(_barPercentLabelL);
        yPos += BAR_HEIGHT + 6;

        // --- RIGHT CHANNEL ---
        _barLabelR = createLabel("R", 10, yPos + 2);
        addChild(_barLabelR);

        var barYR:Float = yPos;
        _barBgR = new Sprite();
        _barBgR.graphics.beginFill(0x0d0d18);
        _barBgR.graphics.lineStyle(1, 0x333344);
        _barBgR.graphics.drawRect(0, 0, BAR_WIDTH, BAR_HEIGHT);
        _barBgR.graphics.endFill();
        _barBgR.x = 25;
        _barBgR.y = barYR;
        addChild(_barBgR);

        _barFillGreenR = new Sprite();
        _barFillGreenR.x = _barBgR.x + 1;
        _barFillGreenR.y = barYR + 1;
        addChild(_barFillGreenR);

        _barFillYellowR = new Sprite();
        _barFillYellowR.y = barYR + 1;
        addChild(_barFillYellowR);

        _barFillRedR = new Sprite();
        _barFillRedR.y = barYR + 1;
        addChild(_barFillRedR);

        _barPercentLabelR = new TextField();
        _barPercentLabelR.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText, true);
        _barPercentLabelR.text = "0%";
        _barPercentLabelR.width = 35;
        _barPercentLabelR.height = BAR_HEIGHT;
        _barPercentLabelR.x = _barBgR.x + BAR_WIDTH + 4;
        _barPercentLabelR.y = barYR;
        _barPercentLabelR.selectable = false;
        _barPercentLabelR.mouseEnabled = false;
        addChild(_barPercentLabelR);
        yPos += BAR_HEIGHT + 10;

        // === dB VALUES ===
        _dbLabelL = createLabel("L:", 10, yPos);
        addChild(_dbLabelL);

        _dbValueL = createValueField("-120.0 dB", 25, yPos);
        addChild(_dbValueL);

        _dbLabelR = createLabel("R:", 130, yPos);
        addChild(_dbLabelR);

        _dbValueR = createValueField("-120.0 dB", 145, yPos);
        addChild(_dbValueR);

        _channelsLabel = createValueField("CH: --", 220, yPos);
        _channelsLabel.textColor = _colorMuted;
        addChild(_channelsLabel);
        yPos += 22;

        // === CLIP INDICATORS ===
        var clipY:Float = yPos;

        _clipIndicatorL = new Sprite();
        _clipIndicatorL.graphics.beginFill(_colorClipOff);
        _clipIndicatorL.graphics.drawCircle(0, 0, 5);
        _clipIndicatorL.graphics.endFill();
        _clipIndicatorL.x = 14;
        _clipIndicatorL.y = clipY;
        addChild(_clipIndicatorL);

        _clipLabelL = new TextField();
        _clipLabelL.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted, true);
        _clipLabelL.text = "CLIP L";
        _clipLabelL.width = 40;
        _clipLabelL.height = 12;
        _clipLabelL.x = 22;
        _clipLabelL.y = clipY - 6;
        _clipLabelL.selectable = false;
        _clipLabelL.mouseEnabled = false;
        addChild(_clipLabelL);

        _clipIndicatorR = new Sprite();
        _clipIndicatorR.graphics.beginFill(_colorClipOff);
        _clipIndicatorR.graphics.drawCircle(0, 0, 5);
        _clipIndicatorR.graphics.endFill();
        _clipIndicatorR.x = 80;
        _clipIndicatorR.y = clipY;
        addChild(_clipIndicatorR);

        _clipLabelR = new TextField();
        _clipLabelR.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted, true);
        _clipLabelR.text = "CLIP R";
        _clipLabelR.width = 40;
        _clipLabelR.height = 12;
        _clipLabelR.x = 88;
        _clipLabelR.y = clipY - 6;
        _clipLabelR.selectable = false;
        _clipLabelR.mouseEnabled = false;
        addChild(_clipLabelR);

        // === SOURCE SELECTION ===
        _sourceLabel = new TextField();
        _sourceLabel.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _sourceLabel.text = "Source:";
        _sourceLabel.width = 50;
        _sourceLabel.height = 14;
        _sourceLabel.x = 140;
        _sourceLabel.y = clipY - 6;
        _sourceLabel.selectable = false;
        _sourceLabel.mouseEnabled = false;
        addChild(_sourceLabel);

        _btnSpeakers = createModeButton("SPK", 0, 190, clipY - 8);
        _btnSpeakers.addEventListener(MouseEvent.CLICK, onSpeakersClick);
        addChild(_btnSpeakers);

        _btnMic = createModeButton("MIC", 1, 235, clipY - 8);
        _btnMic.addEventListener(MouseEvent.CLICK, onMicClick);
        addChild(_btnMic);

        // Final background rendering
        redrawBackground();
        updateBar(_barFillGreenL, _barFillYellowL, _barFillRedL, _barBgL, 0);
        updateBar(_barFillGreenR, _barFillYellowR, _barFillRedR, _barBgR, 0);
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
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 26, 8, 8, 0, 0);
        _header.graphics.endFill();
    }

    // =========================================================================
    // UI HELPERS
    // =========================================================================
    private function createLabel(text:String, x:Float, y:Float):TextField 
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 10, _colorMuted);
        tf.text = text;
        tf.width = 20;
        tf.height = 14;
        tf.x = x;
        tf.y = y;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createValueField(text:String, x:Float, y:Float):TextField 
    {
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 10, _colorGreen, true);
        tf.text = text;
        tf.width = 80;
        tf.height = 14;
        tf.x = x;
        tf.y = y;
        tf.selectable = false;
        tf.mouseEnabled = false;
        return tf;
    }

    private function createModeButton(label:String, mode:Int, x:Float, y:Float):Sprite 
    {
        var btn = new Sprite();
        btn.graphics.beginFill(_colorBtnOff);
        btn.graphics.drawRoundRect(0, 0, 40, 18, 3, 3);
        btn.graphics.endFill();

        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_typewriter", 8, _colorText, true, null, null, null, null, TextFormatAlign.CENTER);
        tf.text = label;
        tf.width = 40;
        tf.height = 18;
        tf.selectable = false;
        tf.mouseEnabled = false;
        btn.addChild(tf);

        btn.x = x;
        btn.y = y;
        btn.buttonMode = true;
        btn.useHandCursor = true;
        btn.name = Std.string(mode);
        return btn;
    }

    // =========================================================================
    // ATOM SYNCHRONIZATION
    // =========================================================================
    override private function syncFromAtom():Void 
    {
        //trace('SystemVUMeterWidget: syncFromAtom called');

        if (_modeContact != null && _modeContact.value != null) 
        {
            _currentMode = Std.int(_modeContact.value);
            updateModeButtons();
        }

        if (_channelsContact != null && _channelsContact.value != null) 
        {
            var ch = Std.int(_channelsContact.value);
            _channelsLabel.text = "CH: " + ch;
        }

        // === FIX: Force read current values on initialization ===
        if (_percentLContact != null) 
        {
            var percentL = (_percentLContact.value != null) ? Std.int(_percentLContact.value) : 0;
            //trace('SystemVUMeterWidget: Initial percentL = ${percentL}');
            updateBar(_barFillGreenL, _barFillYellowL, _barFillRedL, _barBgL, percentL);
            _barPercentLabelL.text = percentL + "%";
        }

        if (_percentRContact != null) 
        {
            var percentR = (_percentRContact.value != null) ? Std.int(_percentRContact.value) : 0;
            //trace('SystemVUMeterWidget: Initial percentR = ${percentR}');
            updateBar(_barFillGreenR, _barFillYellowR, _barFillRedR, _barBgR, percentR);
            _barPercentLabelR.text = percentR + "%";
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        if (isDisposed) return;

        if (contact == _percentLContact) 
        {
            var percent:Int = (newValue != null) ? Std.int(newValue) : 0;
            updateBar(_barFillGreenL, _barFillYellowL, _barFillRedL, _barBgL, percent);
            _barPercentLabelL.text = percent + "%";
            updateBarColor(_barPercentLabelL, percent);
        } 
        else if (contact == _percentRContact) 
        {
            var percent:Int = (newValue != null) ? Std.int(newValue) : 0;
            updateBar(_barFillGreenR, _barFillYellowR, _barFillRedR, _barBgR, percent);
            _barPercentLabelR.text = percent + "%";
            updateBarColor(_barPercentLabelR, percent);
        } 
        else if (contact == _dB_LContact) 
        {
            if (newValue != null) 
            {
                var db:Float = newValue;
                _dbValueL.text = (db <= -120) ? "-inf dB" : (Math.round(db * 10) / 10) + " dB";
                updateDbColor(_dbValueL, db);
            }
        } 
        else if (contact == _dB_RContact) 
        {
            if (newValue != null) 
            {
                var db:Float = newValue;
                _dbValueR.text = (db <= -120) ? "-inf dB" : (Math.round(db * 10) / 10) + " dB";
                updateDbColor(_dbValueR, db);
            }
        } 
        else if (contact == _channelsContact) 
        {
            if (newValue != null) 
            {
                var ch = Std.int(newValue);
                _channelsLabel.text = "CH: " + ch + ((ch >= 2) ? " Stereo" : " Mono");
            }
        } 
        else if (contact == _clipLContact) 
        {
            if (newValue == true) triggerClipL();
        } 
        else if (contact == _clipRContact) 
        {
            if (newValue == true) triggerClipR();
        } 
        else if (contact == _activeContact) 
        {
            updateActiveLed(newValue == true);
        } 
        else if (contact == _modeContact) 
        {
            if (newValue != null) 
            {
                _currentMode = Std.int(newValue);
                updateModeButtons();
            }
        }
    }

    // =========================================================================
    // VU BAR UPDATE (universal for L and R)
    // =========================================================================
    /**
     * Draws the 3-segment VU bar (Green 0-60%, Yellow 60-80%, Red 80-100%).
     * Clears all segments first to prevent visual artifacts.
     */
    private function updateBar(green:Sprite, yellow:Sprite, red:Sprite, bg:Sprite, percent:Int):Void 
    {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        //trace('SystemVUMeterWidget.updateBar: percent=${percent}, green=${green}, yellow=${yellow}, red=${red}');

        // === Clear ALL segments ===
        green.graphics.clear();
        yellow.graphics.clear();
        red.graphics.clear();

        // Green segment: 0% .. 60%
        var greenEnd:Int = Std.int(Math.min(percent, 60));
        var greenWidth:Float = (greenEnd / 100.0) * BAR_WIDTH;
        if (greenWidth > 0) 
        {
            green.graphics.beginFill(_colorGreen);
            green.graphics.drawRect(0, 0, greenWidth, BAR_HEIGHT - 2);
            green.graphics.endFill();
            //trace('SystemVUMeterWidget: Drew green bar, width=${greenWidth}');
        }

        // Yellow segment: 60% .. 80%
        if (percent > 60) 
        {
            var yellowEnd:Int = Std.int(Math.min(percent, 80));
            var yellowWidth:Float = ((yellowEnd - 60) / 100.0) * BAR_WIDTH;
            var yellowX:Float = (60.0 / 100.0) * BAR_WIDTH;
            yellow.x = yellowX;
            yellow.graphics.beginFill(_colorYellow);
            yellow.graphics.drawRect(0, 0, yellowWidth, BAR_HEIGHT - 2);
            yellow.graphics.endFill();
            //trace('SystemVUMeterWidget: Drew yellow bar, width=${yellowWidth}, x=${yellowX}');
        }

        // Red segment: 80% .. 100%
        if (percent > 80) 
        {
            var redWidth:Float = ((percent - 80) / 100.0) * BAR_WIDTH;
            var redX:Float = (80.0 / 100.0) * BAR_WIDTH;
            red.x = redX;
            red.graphics.beginFill(_colorRed);
            red.graphics.drawRect(0, 0, redWidth, BAR_HEIGHT - 2);
            red.graphics.endFill();
            //trace('SystemVUMeterWidget: Drew red bar, width=${redWidth}, x=${redX}');
        }
    }

    private function updateBarColor(tf:TextField, percent:Int):Void 
    {
        if (percent >= 80) tf.textColor = _colorRed;
        else if (percent >= 60) tf.textColor = _colorYellow;
        else tf.textColor = _colorGreen;
    }

    private function updateDbColor(tf:TextField, db:Float):Void 
    {
        if (db > -3) tf.textColor = _colorRed;
        else if (db > -12) tf.textColor = _colorYellow;
        else tf.textColor = _colorGreen;
    }

    // =========================================================================
    // CLIP INDICATORS
    // =========================================================================
    private function triggerClipL():Void 
    {
        _clipTimerL = CLIP_TIMEOUT;
        _clipIndicatorL.graphics.clear();
        _clipIndicatorL.graphics.beginFill(_colorClipOn);
        _clipIndicatorL.graphics.drawCircle(0, 0, 5);
        _clipIndicatorL.graphics.endFill();
    }

    private function triggerClipR():Void 
    {
        _clipTimerR = CLIP_TIMEOUT;
        _clipIndicatorR.graphics.clear();
        _clipIndicatorR.graphics.beginFill(_colorClipOn);
        _clipIndicatorR.graphics.drawCircle(0, 0, 5);
        _clipIndicatorR.graphics.endFill();
    }

    private function resetClipL():Void 
    {
        _clipIndicatorL.graphics.clear();
        _clipIndicatorL.graphics.beginFill(_colorClipOff);
        _clipIndicatorL.graphics.drawCircle(0, 0, 5);
        _clipIndicatorL.graphics.endFill();
    }

    private function resetClipR():Void 
    {
        _clipIndicatorR.graphics.clear();
        _clipIndicatorR.graphics.beginFill(_colorClipOff);
        _clipIndicatorR.graphics.drawCircle(0, 0, 5);
        _clipIndicatorR.graphics.endFill();
    }

    // =========================================================================
    // ACTIVITY LED
    // =========================================================================
    private function updateActiveLed(active:Bool):Void 
    {
        if (active) 
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(_colorAccent);
            _statusLed.graphics.drawCircle(0, 0, 4);
            _statusLed.graphics.endFill();
            _statusGlow.visible = true;
        } 
        else 
        {
            _statusLed.graphics.clear();
            _statusLed.graphics.beginFill(0x003344);
            _statusLed.graphics.drawCircle(0, 0, 4);
            _statusLed.graphics.endFill();
            _statusGlow.visible = false;
        }
    }

    // =========================================================================
    // MODE BUTTONS
    // =========================================================================
    private function updateModeButtons():Void 
    {
        _btnSpeakers.graphics.clear();
        _btnSpeakers.graphics.beginFill(_currentMode == 0 ? _colorBtnActive : _colorBtnOff);
        _btnSpeakers.graphics.drawRoundRect(0, 0, 40, 18, 3, 3);
        _btnSpeakers.graphics.endFill();

        _btnMic.graphics.clear();
        _btnMic.graphics.beginFill(_currentMode == 1 ? _colorBtnActive : _colorBtnOff);
        _btnMic.graphics.drawRoundRect(0, 0, 40, 18, 3, 3);
        _btnMic.graphics.endFill();
    }

    private function onSpeakersClick(e:MouseEvent):Void 
    {
        if (_modeContact != null) _modeContact.value = 0;
    }

    private function onMicClick(e:MouseEvent):Void 
    {
        if (_modeContact != null) _modeContact.value = 1;
    }

    // =========================================================================
    // ANIMATION
    // =========================================================================
    override public function activate():Void 
    {
        super.activate();
        if (stage != null) 
        {
            stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
        } 
        else 
        {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
    }

    override public function deactivate():Void 
    {
        super.deactivate();
        if (stage != null) 
        {
            stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        }
    }

    private function onAddedToStage(e:Event):Void 
    {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function onEnterFrame(e:Event):Void 
    {
        // Clip indicator fade-out animation
        if (_clipTimerL > 0) 
        {
            _clipTimerL -= 1.0 / 60.0;
            if (_clipTimerL <= 0) { _clipTimerL = 0; resetClipL(); }
        }
        if (_clipTimerR > 0) 
        {
            _clipTimerR -= 1.0 / 60.0;
            if (_clipTimerR <= 0) { _clipTimerR = 0; resetClipR(); }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        if (stage != null) 
        {
            stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        }

        if (_btnSpeakers != null) _btnSpeakers.removeEventListener(MouseEvent.CLICK, onSpeakersClick);
        if (_btnMic != null) _btnMic.removeEventListener(MouseEvent.CLICK, onMicClick);

        _bg = null;
        _header = null;
        _titleLabel = null;
        _statusLed = null;
        _statusGlow = null;
        _barBgL = null;
        _barFillGreenL = null;
        _barFillYellowL = null;
        _barFillRedL = null;
        _barPercentLabelL = null;
        _barLabelL = null;
        _barBgR = null;
        _barFillGreenR = null;
        _barFillYellowR = null;
        _barFillRedR = null;
        _barPercentLabelR = null;
        _barLabelR = null;
        _dbLabelL = null;
        _dbValueL = null;
        _dbLabelR = null;
        _dbValueR = null;
        _channelsLabel = null;
        _clipIndicatorL = null;
        _clipLabelL = null;
        _clipIndicatorR = null;
        _clipLabelR = null;
        _btnSpeakers = null;
        _btnMic = null;
        _sourceLabel = null;
        _peakLContact = null;
        _peakRContact = null;
        _percentLContact = null;
        _percentRContact = null;
        _dB_LContact = null;
        _dB_RContact = null;
        _channelsContact = null;
        _activeContact = null;
        _clipLContact = null;
        _clipRContact = null;
        _modeContact = null;
        super.dispose();
    }
}
#end