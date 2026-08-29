#if cpp
package core.view;

import core.base.Atom;
import core.base.Contact;
import library.drivers.MiniAudioAtom;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.FocusEvent;

/**
 * MINI AUDIO WIDGET
 * Specific "Face" (DeviceView) for the MiniAudioAtom.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * Responsibilities:
 * - Visualize signal level (VU Meter based on RMS)
 * - Display clipping alerts
 * - Control parameters (Gain, Quantum)
 * - Restart the audio device
 *
 * Subscription Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   MiniAudioAtom (Databank)                                              │
 * │     ├─ out("rms")   ──subscribe()──► VU Meter Bar (UI Update)           │
 * │     ├─ out("level") ──subscribe()──► dBFS Text (UI Update)              │
 * │     └─ out("clip")  ──subscribe()──► Clip Indicator (UI Update)         │
 * │                                                                         │
 * │   MiniAudioWidget (Control)                                             │
 * │     ├─ Gain Input   ───value=──────► in("gain") (Atom reads in update)  │
 * │     └─ Restart Btn  ───restart()───► MiniAudioAtom.restart()            │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class MiniAudioWidget extends DeviceView
{
    private var _atom:Atom;

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    // Widget dimensions
    public var widgetWidth:Float = 240;
    public var widgetHeight:Float = 150;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    private var _vuMeterBg:Sprite;
    private var _vuMeterFg:Sprite;
    private var _clipIndicator:Sprite;
    private var _levelText:TextField;
    private var _deviceText:TextField;
    private var _gainInput:TextField;
    private var _quantumInput:TextField;
    private var _restartBtn:Sprite;
    private var _restartLabel:TextField;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _maxVUWidth:Float = 150;
    private var _clipTimeout:haxe.Timer;

    // W-SYNC.3: editing guards — live mirror suppressed while typing
    private var _isEditingGain:Bool = false;
    private var _isEditingQuantum:Bool = false;

    public function new(atom:Atom)
    {
        _atom = atom;
        super(atom);
        buildUI();
        subscribeToOutputs();
        applyDefaults();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        var y:Float = 0;
        var padX:Float = 5;

        // --- Title ---
        var title = createLabel("AUDIO CAPTURE", 0xFFAA00, 12, true);
        title.x = padX; title.y = y;
        addChild(title);
        y += 20;

        // --- Device Name ---
        _deviceText = createLabel("Device: ---", 0x888888, 10);
        _deviceText.x = padX; _deviceText.y = y;
        addChild(_deviceText);
        y += 18;

        // --- VU Meter ---
        var vuLabel = createLabel("RMS:", 0xFFFFFF, 10);
        vuLabel.x = padX; vuLabel.y = y + 2;
        addChild(vuLabel);

        _vuMeterBg = new Sprite();
        _vuMeterBg.graphics.lineStyle(1, 0x555555);
        _vuMeterBg.graphics.drawRect(0, 0, _maxVUWidth, 14);
        _vuMeterBg.x = padX + 35; _vuMeterBg.y = y;
        addChild(_vuMeterBg);

        _vuMeterFg = new Sprite();
        _vuMeterFg.graphics.beginFill(0x00FF00);
        _vuMeterFg.graphics.drawRect(0, 0, 1, 12); // Initial width 1
        _vuMeterFg.graphics.endFill();
        _vuMeterFg.x = _vuMeterBg.x + 1; _vuMeterFg.y = y + 1;
        addChild(_vuMeterFg);
        y += 20;

        // --- dBFS and Clip ---
        _levelText = createLabel("-inf dBFS", 0xAAAAAA, 10);
        _levelText.x = padX + 35; _levelText.y = y;
        addChild(_levelText);

        _clipIndicator = new Sprite();
        _clipIndicator.graphics.beginFill(0x333333);
        _clipIndicator.graphics.drawCircle(10, 6, 6);
        _clipIndicator.graphics.endFill();
        _clipIndicator.x = padX; _clipIndicator.y = y;
        addChild(_clipIndicator);
        y += 20;

        // --- Settings (Simple TextFields for input) ---
        var gainLabel = createLabel("Gain:", 0xFFFFFF, 10);
        gainLabel.x = padX; gainLabel.y = y + 2;
        addChild(gainLabel);

        _gainInput = createInputField("1.0");
        _gainInput.x = padX + 45; _gainInput.y = y;
        _gainInput.width = 50;
        addChild(_gainInput);
        y += 20;

        var qLabel = createLabel("Quant:", 0xFFFFFF, 10);
        qLabel.x = padX; qLabel.y = y + 2;
        addChild(qLabel);

        _quantumInput = createInputField("0.01");
        _quantumInput.x = padX + 45; _quantumInput.y = y;
        _quantumInput.width = 50;
        addChild(_quantumInput);
        y += 25;

        // --- Restart Button ---
        _restartBtn = new Sprite();
        _restartBtn.graphics.lineStyle(1, 0xFF6666);
        _restartBtn.graphics.beginFill(0x442222);
        _restartBtn.graphics.drawRect(0, 0, 80, 22);
        _restartBtn.graphics.endFill();
        _restartBtn.x = padX; _restartBtn.y = y;
        _restartBtn.buttonMode = true;
        addChild(_restartBtn);

        _restartLabel = createLabel("RESTART", 0xFF6666, 10, true);
        _restartLabel.x = padX + 15; _restartLabel.y = y + 5;
        addChild(_restartLabel);

        // Event Listeners
        _restartBtn.addEventListener(MouseEvent.CLICK, onRestartClick);
        _gainInput.addEventListener(Event.CHANGE, onGainChanged);
        _quantumInput.addEventListener(Event.CHANGE, onQuantumChanged);
        _gainInput.addEventListener(FocusEvent.FOCUS_IN, onGainFocusIn);
        _gainInput.addEventListener(FocusEvent.FOCUS_OUT, onGainFocusOut);
        _quantumInput.addEventListener(FocusEvent.FOCUS_IN, onQuantumFocusIn);
        _quantumInput.addEventListener(FocusEvent.FOCUS_OUT, onQuantumFocusOut);
    }

    // =========================================================================
    // ATOM OUTPUT SUBSCRIPTION
    // =========================================================================
    private function subscribeToOutputs():Void
    {
        var rms = _atom.getOutput("rms");
        if (rms != null) rms.subscribe(onRmsUpdate);
        
        var level = _atom.getOutput("level");
        if (level != null) level.subscribe(onLevelUpdate);
        
        var clip = _atom.getOutput("clip");
        if (clip != null) clip.subscribe(onClipUpdate);
        
        var device = _atom.getOutput("device");
        if (device != null) device.subscribe(onDeviceUpdate);
    }

    // =========================================================================
    // ATOM DATA HANDLERS
    // =========================================================================
    private function onRmsUpdate(val:Dynamic):Void
    {
        if (val == null) return;
        var rms:Float = val;

        // Update bar width
        var newWidth = Math.max(1, rms * _maxVUWidth);
        _vuMeterFg.graphics.clear();

        // Color gradient: Green -> Yellow -> Red
        var color:Int = 0x00FF00;
        if (rms > 0.8) color = 0xFF0000;
        else if (rms > 0.5) color = 0xFFFF00;

        _vuMeterFg.graphics.beginFill(color);
        _vuMeterFg.graphics.drawRect(0, 0, newWidth, 12);
        _vuMeterFg.graphics.endFill();
    }

    private function onLevelUpdate(val:Dynamic):Void
    {
        if (val == null) return;
        var db:Float = val;
        _levelText.text = (db <= -120) ? "-inf dBFS" : (Math.round(db * 10) / 10) + " dBFS";

        var color:Int = 0x00FF00;
        if (db > -3) color = 0xFF0000;
        else if (db > -12) color = 0xFFFF00;
        _levelText.textColor = color;
    }

    private function onClipUpdate(val:Dynamic):Void
    {
        if (val == true)
        {
            _clipIndicator.graphics.clear();
            _clipIndicator.graphics.beginFill(0xFF0000);
            _clipIndicator.graphics.drawCircle(10, 6, 6);
            _clipIndicator.graphics.endFill();

            // Fade out after 100ms
            if (_clipTimeout != null) _clipTimeout.stop();
            _clipTimeout = haxe.Timer.delay(function() {
                _clipIndicator.graphics.clear();
                _clipIndicator.graphics.beginFill(0x333333);
                _clipIndicator.graphics.drawCircle(10, 6, 6);
                _clipIndicator.graphics.endFill();
            }, 100);
        }
    }

    private function onDeviceUpdate(val:Dynamic):Void
    {
        if (val != null && val != "") _deviceText.text = "Device: " + val;
    }

    // =========================================================================
    // ATOM CONTROL FROM WIDGET
    // =========================================================================
    private function onGainChanged(e:Event):Void
    {
        var val = Std.parseFloat(_gainInput.text);
        if (Math.isNaN(val)) return;
        var gainC = _atom.getInput("gain");
        if (gainC != null) gainC.value = val;
    }

    private function onQuantumChanged(e:Event):Void
    {
        var val = Std.parseFloat(_quantumInput.text);
        if (Math.isNaN(val)) return;
        var qC = _atom.getInput("quantum");
        if (qC != null) qC.value = val;
    }

    private function onRestartClick(e:MouseEvent):Void
    {
        // Write current field values to the atom BEFORE restarting
        onGainChanged(null);
        onQuantumChanged(null);

        // Trigger hardware re-initialization
        if (Std.isOfType(_atom, MiniAudioAtom))
        {
            cast(_atom, MiniAudioAtom).restart();
        }
    }

    // =========================================================================
    // DEFAULT VALUES INITIALIZATION
    // =========================================================================
    private function applyDefaults():Void
    {
        // On widget creation, read current values from the atom
        // (in case they are already set in the Blueprint)
        var gainC = _atom.getInput("gain");
        if (gainC != null && gainC.value != null) _gainInput.text = Std.string(gainC.value);
        
        var qC = _atom.getInput("quantum");
        if (qC != null && qC.value != null) _quantumInput.text = Std.string(qC.value);
    }

    // =========================================================================
    // LIVE MIRROR: input contacts → parameter fields (W-SYNC.3)
    // =========================================================================
    /**
     * The DeviceView base subscribes this widget to ALL atom contacts.
     * Mirror external changes of "gain" / "quantum" into the fields
     * ("Atom is Databank"), suppressed while the user is editing a field.
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed || newValue == null) return;

        var gainC = _atom.getInput("gain");
        var qC = _atom.getInput("quantum");

        if (contact == gainC && !_isEditingGain && _gainInput != null)
        {
            var s = Std.string(newValue);
            if (_gainInput.text != s) _gainInput.text = s;
        }
        else if (contact == qC && !_isEditingQuantum && _quantumInput != null)
        {
            var s = Std.string(newValue);
            if (_quantumInput.text != s) _quantumInput.text = s;
        }
    }

    /** W-SYNC.3: focus guards — the live mirror is suppressed while typing. */
    private function onGainFocusIn(e:FocusEvent):Void
    {
        _isEditingGain = true;
    }

    private function onGainFocusOut(e:FocusEvent):Void
    {
        _isEditingGain = false;
        // Leaving the field: normalize display to the committed value
        if (_gainInput != null)
        {
            var gainC = _atom.getInput("gain");
            if (gainC != null && gainC.value != null)
            {
                var s = Std.string(gainC.value);
                if (_gainInput.text != s) _gainInput.text = s;
            }
        }
    }

    private function onQuantumFocusIn(e:FocusEvent):Void
    {
        _isEditingQuantum = true;
    }

    private function onQuantumFocusOut(e:FocusEvent):Void
    {
        _isEditingQuantum = false;
        // Leaving the field: normalize display to the committed value
        if (_quantumInput != null)
        {
            var qC = _atom.getInput("quantum");
            if (qC != null && qC.value != null)
            {
                var s = Std.string(qC.value);
                if (_quantumInput.text != s) _quantumInput.text = s;
            }
        }
    }

    // =========================================================================
    // UI UTILITIES
    // =========================================================================
    private function createLabel(text:String, color:Int, size:Int = 10, bold:Bool = false):TextField
    {
        var tf = new TextField();
        tf.text = text;
        tf.textColor = color;
        tf.width = 200; tf.height = 20;
        tf.selectable = false;
        
        #if openfl
        var fmt = new openfl.text.TextFormat("_sans", size, color, bold);
        tf.defaultTextFormat = fmt;
        tf.setTextFormat(fmt);
        #end
        return tf;
    }

    private function createInputField(defaultText:String):TextField
    {
        var tf = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.text = defaultText;
        tf.textColor = 0xFFFFFF;
        tf.borderColor = 0x666666;
        tf.border = true;
        tf.height = 18;
        tf.background = true;
        tf.backgroundColor = 0x222222;
        
        #if openfl
        tf.defaultTextFormat = new openfl.text.TextFormat("_sans", 10);
        #end
        return tf;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_clipTimeout != null) _clipTimeout.stop();
        
        _restartBtn.removeEventListener(MouseEvent.CLICK, onRestartClick);
        _gainInput.removeEventListener(Event.CHANGE, onGainChanged);
        _quantumInput.removeEventListener(Event.CHANGE, onQuantumChanged);
        _gainInput.removeEventListener(FocusEvent.FOCUS_IN, onGainFocusIn);
        _gainInput.removeEventListener(FocusEvent.FOCUS_OUT, onGainFocusOut);
        _quantumInput.removeEventListener(FocusEvent.FOCUS_IN, onQuantumFocusIn);
        _quantumInput.removeEventListener(FocusEvent.FOCUS_OUT, onQuantumFocusOut);

        // Unsubscribe from contacts (crucial for cleanup!)
        var rms = _atom.getOutput("rms"); if (rms != null) rms.unsubscribe(onRmsUpdate);
        var level = _atom.getOutput("level"); if (level != null) level.unsubscribe(onLevelUpdate);
        var clip = _atom.getOutput("clip"); if (clip != null) clip.unsubscribe(onClipUpdate);
        var device = _atom.getOutput("device"); if (device != null) device.unsubscribe(onDeviceUpdate);
        
        super.dispose();
    }
}
#end
