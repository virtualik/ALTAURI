package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;
import library.electro.ToggleAtom;

/**
 * TOGGLE WIDGET v2.1 (Set Input Support)
 * Toggle switch widget with two states.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "out" ◄──► ToggleWidget                                       │
 * │   Contact "rst"  ◄─── (Wired externally)                                │
 * │   Contact "set"  ◄─── (Wired externally)                                │
 * │                    ┌─────────────────────────────────────────────────┐  │
 * │                    │ onClick:    contact.value = !contact.value      │  │
 * │                    │ onActivate: syncFromAtom() → read current state │  │
 * │                    │ onContactChanged: update visual from Databank   │  │
 * │                    └─────────────────────────────────────────────────┘  │
 * │                                                                         │
 * │   Widget READS atom's contact state (for display)                       │
 * │   Widget WRITES to atom's contact (user input)                          │
 * │   Atom is the Databank - single source of truth                         │
 * │                                                                         │
 * │   v2.1: Added _setContact reference for consistency.                    │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ToggleWidget extends DeviceView {

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _btn:Sprite;
    private var _labelField:TextField;
    private var _stateField:TextField;
    
    // Atom Contacts References
    private var _outContact:Contact;
    private var _rstContact:Contact;
    private var _setContact:Contact; // Added in v2.1

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    public var widgetWidth:Float = 80;
    public var widgetHeight:Float = 30;
    public var colorOn:Int = 0x448844;
    public var colorOff:Int = 0x444444;
    public var colorOver:Int = 0x555555;
    public var labelOn:String = "ON";
    public var labelOff:String = "OFF";
    public var initialState:Bool = false;
    private var _contactName:String;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom, contactName:String = "out") {
        super(atom);
        _contactName = contactName;
        findContacts();
        buildUI();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================

    private function findContacts():Void {
        if (atom != null) {
            _outContact = atom.getOutput(_contactName);
            if (_outContact == null) _outContact = atom.getOutput("out");

            _rstContact = atom.getInput("rst");
            _setContact = atom.getInput("set"); // Find the new input
        }
    }

    override private function onActivate():Void {
        findContacts();
        // Sync visual with current Databank state
        updateVisual();
    }

    private function buildUI():Void {
        _btn = new Sprite();
        _btn.buttonMode = true;
        _btn.useHandCursor = true;
        _btn.addEventListener(MouseEvent.CLICK, onClick);
        _btn.addEventListener(MouseEvent.MOUSE_OVER, onOver);
        _btn.addEventListener(MouseEvent.MOUSE_OUT, onOut);
        addChild(_btn);

        _stateField = new TextField();
        _stateField.width = widgetWidth;
        _stateField.height = widgetHeight;
        _stateField.selectable = false;
        _stateField.mouseEnabled = false;

        var fmt = new TextFormat("_sans", 14, 0xFFFFFF, true);
        fmt.align = TextFormatAlign.CENTER;
        _stateField.defaultTextFormat = fmt;
        addChild(_stateField);

        _labelField = new TextField();
        _labelField.width = widgetWidth;
        _labelField.height = 20;
        _labelField.y = widgetHeight + 5;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;

        var fmt2 = new TextFormat("_sans", 10, 0x888888);
        fmt2.align = TextFormatAlign.CENTER;
        _labelField.defaultTextFormat = fmt2;
        _labelField.text = atom != null ? atom.name : "Toggle";

        addChild(_labelField);

        updateVisual();
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    /**
     * Reaction to contact change.
     * v2.1: Updates visual if "out" changes.
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _outContact) {
            updateVisual();
        } else if (contact == _rstContact || contact == _setContact) {
            // If rst or set changes, the output might change, but usually
            // the output change event fires separately.
            // We can force a visual update here just in case.
            updateVisual();
        }
    }

    /**
     * Click - toggle state.
     * v2.1: Delegates logic to Atom.
     */
    private function onClick(e:MouseEvent):Void {
        // Read current state FROM CONTACT
        var currentState = (_outContact != null && _outContact.value == true);
        var newState = !currentState;

        // Use the Atom's API to ensure immunity timer is set correctly
        if (atom != null && Std.isOfType(atom, library.electro.ToggleAtom)) {
            cast(atom, library.electro.ToggleAtom).setState(newState);
        } else if (_outContact != null) {
            // Fallback: direct write
            _outContact.value = newState;
        }
    }

    private function onOver(e:MouseEvent):Void {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorOver);
        _btn.graphics.lineStyle(2, 0x666666);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();
    }

    private function onOut(e:MouseEvent):Void {
        updateVisual();
    }

    /**
     * Update visual representation.
     * Reads state DIRECTLY from contact.
     */
    private function updateVisual():Void {
        // Read from contact
        var isOn = (_outContact != null && _outContact.value == true);
        var color = isOn ? colorOn : colorOff;

        _btn.graphics.clear();
        _btn.graphics.beginFill(color);
        _btn.graphics.lineStyle(2, isOn ? 0x66AA66 : 0x555555);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();

        _stateField.text = isOn ? labelOn : labelOff;
    }

    /**
     * Get current toggle state.
     */
    public function getState():Bool {
        return (_outContact != null && _outContact.value == true);
    }

    /**
     * Set state programmatically.
     */
    public function setState(value:Bool):Void {
        if (atom != null && Std.isOfType(atom, library.electro.ToggleAtom)) {
            cast(atom, library.electro.ToggleAtom).setState(value);
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        if (_btn != null) {
            _btn.removeEventListener(MouseEvent.CLICK, onClick);
            _btn.removeEventListener(MouseEvent.MOUSE_OVER, onOver);
            _btn.removeEventListener(MouseEvent.MOUSE_OUT, onOut);
        }
        _btn = null;
        _outContact = null;
        _rstContact = null;
        _setContact = null;
        _labelField = null;
        _stateField = null;
        super.dispose();
    }
}