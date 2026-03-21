package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * TEXT INPUT WIDGET v1.2 (Databank Architecture)
 * Widget for text or number input.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   TextInputAtom (Databank)                                              │
 * │                                                                         │
 * │   Contact "out" ◄─── TextInputWidget                                    │
 * │   Contact "set"  ───► TextInputWidget (updates display)                 │
 * │                     ┌─────────────────────────────────────────────────┐ │
 * │                     │ pushValue(): contact.value = input.text         │ │
 * │                     │ onContactChanged("set"): update display         │ │
 * │                     │ onActivate(): syncFromAtom()                    │ │
 * │                     └─────────────────────────────────────────────────┘ │
 * │                                                                         │
 * │   Widget READS atom's contact state (for display sync)                  │
 * │   Widget WRITES to atom's contact (user input)                          │
 * │   Atom is the Databank - single source of truth                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.2 Changes:
 * - Emits VALUE_COMMITTED impulse on Enter key
 * - This triggers automatic save in Main.hx
 */
class TextInputWidget extends DeviceView {

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _inputField:TextField;
    private var _outputContact:Contact;
    private var _setContact:Contact;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    public var widgetWidth:Float = 120;
    public var widgetHeight:Float = 30;

    // =========================================================================
    // STATE
    // =========================================================================

    private var _isEditing:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom) {
        super(atom);

        // Find contacts
        if (atom != null) {
            _outputContact = atom.getOutput("out");
            _setContact = atom.getInput("set");
        }

        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================

    private function buildUI():Void {
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x00AAFF);
        graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 4, 4);
        graphics.endFill();

        _inputField = new TextField();
        _inputField.type = TextFieldType.INPUT;
        _inputField.width = widgetWidth - 4;
        _inputField.height = widgetHeight - 4;
        _inputField.x = 2;
        _inputField.y = 2;
        _inputField.border = false;
        _inputField.background = false;
        _inputField.textColor = 0xFFFFFF;
        _inputField.mouseEnabled = true;

        var fmt = new TextFormat("_sans", 12, 0xFFFFFF);
        _inputField.defaultTextFormat = fmt;

        // Set initial value
        if (_outputContact != null && _outputContact.value != null) {
            _inputField.text = Std.string(_outputContact.value);
        } else {
            _inputField.text = "";
        }

        addChild(_inputField);

        // Events
        _inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    override private function onActivate():Void {
        // Read current state from atom
        if (_outputContact != null && _outputContact.value != null) {
            _inputField.text = Std.string(_outputContact.value);
        }
    }

    private function onFocusOut(e:FocusEvent):Void {
        pushValue();
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        if (e.keyCode == Keyboard.ENTER) {
            pushValue();

            // Remove focus
            if (stage != null) stage.focus = null;

            // Signal to save project
            Impulsys.quickEmit(EventType.VALUE_COMMITTED);
        }
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================

    /**
     * Push entered value to atom's output contact.
     */
    private function pushValue():Void {
        if (_outputContact != null) {
            var txt = _inputField.text;

            // Try to parse number
            var f = Std.parseFloat(txt);
            if (!Math.isNaN(f) && (txt.indexOf(".") != -1 || Std.parseInt(txt) != null && txt.length > 0 && !Math.isNaN(f))) {
                _outputContact.value = f;
            } else {
                _outputContact.value = txt;
            }
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // React to changes in "set" or "out" contact
        if ((contact == _outputContact || contact == _setContact) && newValue != null) {
            var str = Std.string(newValue);
            if (_inputField.text != str) {
                _inputField.text = str;
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        if (_inputField != null) {
            _inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        }
        _inputField = null;
        _outputContact = null;
        _setContact = null;
        super.dispose();
    }
}