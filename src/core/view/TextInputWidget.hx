package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * TEXT INPUT WIDGET
 * Text input field widget for entering values into TextInputAtom.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Atom (Databank)                                                       │
 * │                                                                         │
 * │   Contact "set"  ──► TextInputWidget                                    │
 * │   Contact "out"  ──► TextInputWidget                                    │
 * │                       ┌─────────────────────────────────────────────┐   │
 * │                       │ _inputField: INPUT TextField                │   │
 * │                       │ onKeyDown: push on ENTER, stopPropagation   │   │
 * │                       │ onFocusOut: push value                      │   │
 * │                       │ onContactChanged: display value             │   │
 * │                       └─────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Widget READS atom's contact value (display only)                      │
 * │   Widget WRITES to atom's "out" contact on user input                   │
 * │   Atom is the Databank - single source of truth                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class TextInputWidget extends DeviceView 
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _inputField:TextField;
    private var _outputContact:Contact;
    private var _setContact:Contact;

    // W-SYNC.5: editing guard — external mirror suppressed while typing
    private var _isEditing:Bool = false;

    // Widget dimensions
    private var widgetWidth:Float = 120;
    private var widgetHeight:Float = 24;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom) 
    {
        super(atom);
        // Find contacts
        if (atom != null) 
        {
            _outputContact = atom.getOutput("out");
            _setContact = atom.getInput("set");
        }
        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void 
    {
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
        if (_outputContact != null && _outputContact.value != null) 
        {
            _inputField.text = Std.string(_outputContact.value);
        } 
        else 
        {
            _inputField.text = "";
        }
        addChild(_inputField);

        // Events
        _inputField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
        override private function onActivate():Void 
    {
        // ЖЕЛЕЗОБЕТОННО: При активации виджета всегда перечитываем значение из атома.
        if (_outputContact != null && _outputContact.value != null) 
        {
            _inputField.text = Std.string(_outputContact.value);
        }
    }
        
    private function onFocusIn(e:FocusEvent):Void
    {
        _isEditing = true;
    }

    private function onFocusOut(e:FocusEvent):Void 
    {
        _isEditing = false;
        pushValue();
    }

    private function onKeyDown(e:KeyboardEvent):Void 
    {
        // Stop ALL key events from propagating when the input field is focused.
        // This prevents the global keyboard handler (Main.onKeyDown) from
        // intercepting single-key shortcuts (like 'D' for delete) while typing.
        e.stopImmediatePropagation();

        if (e.keyCode == Keyboard.ENTER) 
        {
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
        private function pushValue():Void
        {
                if (_outputContact != null)
                {
                        var txt = _inputField.text;
                        
                        // СТРОГАЯ ПРОВЕРКА: Вся строка целиком должна быть числом
                        var isPureNumber = ~/^\s*-?\d+(\.\d+)?\s*$/.match(txt);
                        
                        if (isPureNumber)
                        {
                                // Если в строке есть точка — передаем как Float
                                if (txt.indexOf(".") != -1)
                                {
                                        var f = Std.parseFloat(txt);
                                        if (!Math.isNaN(f)) 
                                        {
                                                _outputContact.value = f;
                                                return;
                                        }
                                }
                                // Если точки нет — передаем как Int
                                else
                                {
                                        var i = Std.parseInt(txt);
                                        if (i != null) 
                                        {
                                                _outputContact.value = i;
                                                return;
                                        }
                                }
                        }
                        
                        // Во всех остальных случаях (буквы, смешанные данные) — передаем как String
                        _outputContact.value = txt;
                }
        }

        /**
        * Rescue uncommitted text from the TextField into the Atom's Contact
        * before the widget is detached from the display list.
        */
        override private function flushTransientState():Void
        {
                pushValue();
        }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        // React to changes in "set" or "out" contact
        if ((contact == _outputContact || contact == _setContact) && newValue != null) 
        {
            // W-SYNC.5: never clobber a field the user is editing right now
            if (_isEditing) return;
            var str = Std.string(newValue);
            if (_inputField.text != str) 
            {
                _inputField.text = str;
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        if (_inputField != null) 
        {
            _inputField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            _inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        }
        _inputField = null;
        _outputContact = null;
        _setContact = null;
        super.dispose();
    }
}
