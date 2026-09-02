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
 * TOGGLE WIDGET
 * Toggle switch widget with two states.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "out"  ◄──► ToggleWidget                                      │
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
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ToggleWidget extends DeviceView 
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _btn:Sprite;
    private var _labelField:TextField;
    private var _stateField:TextField;

    // Atom Contacts References
    private var _outContact:Contact;
    private var _rstContact:Contact;
    private var _setContact:Contact;
    private var _zOrderContact:Contact;

    // Transform mirror (UI state)
    private var _tZOrder:Int = 0;
    private var _appliedZ:Int = -1;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Widget dimensions
    public var widgetWidth:Float = 80;
    public var widgetHeight:Float = 30;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: widgetWidth, height: widgetHeight};
    }

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
    public function new(atom:Atom, contactName:String = "out") 
    {
        super(atom);
        _contactName = contactName;
        findContacts();
        buildUI();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    private function findContacts():Void 
    {
        if (atom != null) 
        {
            _outContact = atom.getOutput(_contactName);
            if (_outContact == null) _outContact = atom.getOutput("out");
            _rstContact = atom.getInput("rst");
            _setContact = atom.getInput("set");
            _zOrderContact = atom.getInput("zOrder");
        }
    }

    override private function onActivate():Void 
    {
        findContacts();
        // Activation reads the DATABANK (Picture pattern): restored zOrder
        // lives in the atom until the contact is driven externally.
        if (atom != null && Std.isOfType(atom, ToggleAtom))
        {
            _tZOrder = cast(atom, ToggleAtom).getZOrder();
        }
        syncTransformMirror(); // live contact value wins if already driven
        applyCardPlacement();
        updateVisual();
    }

    private function buildUI():Void 
    {
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
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        if (contact == _outContact) 
        {
            updateVisual();
        } 
        else if (contact == _rstContact || contact == _setContact) 
        {
            // If rst or set changes, the output might change, but usually
            // the output change event fires separately.
            // Force a visual update here just in case.
            updateVisual();
        }
        else if (contact == _zOrderContact)
        {
            if (newValue != null) _tZOrder = Math.round(parseFloat(newValue, _tZOrder));
            applyCardPlacement();
        }
    }

    private function parseFloat(v:Dynamic, current:Float):Float
    {
        var f:Float = Std.parseFloat(Std.string(v));
        if (Math.isNaN(f) || !Math.isFinite(f)) return current;
        return f;
    }

    private function onClick(e:MouseEvent):Void 
    {
        // Read current state FROM CONTACT
        var currentState = (_outContact != null && _outContact.value == true);
        var newState = !currentState;

        // === OPTIMISTIC UI UPDATE ===
        // Update visual instantly, ignoring any potential graph delays
        updateVisual(newState);

        // Use the Atom's API to ensure immunity timer is set correctly
        if (atom != null && Std.isOfType(atom, ToggleAtom)) 
        {
            cast(atom, ToggleAtom).setState(newState);
        } 
        else if (_outContact != null)
        {
            // Fallback: direct write
            _outContact.value = newState;
        }
    }

    private function onOver(e:MouseEvent):Void 
    {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorOver);
        _btn.graphics.lineStyle(2, 0x666666);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();
    }

    private function onOut(e:MouseEvent):Void 
    {
        updateVisual();
    }

    /**
     * Updates the visual representation of the toggle.
     * 
     * @param forcedState Optional. If provided, uses this state instead of reading from contact.
     *                    This enables "Optimistic UI Updates" for instant HTML5 responsiveness.
     */
    private function updateVisual(?forcedState:Bool = null):Void 
    {
        // Use forcedState if provided (for optimistic updates), otherwise read from contact
        var isOn = forcedState != null ? forcedState : (_outContact != null && _outContact.value == true);
        var color = isOn ? colorOn : colorOff;

        _btn.graphics.clear();
        _btn.graphics.beginFill(color);
        _btn.graphics.lineStyle(2, isOn ? 0x66AA66 : 0x555555);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _btn.graphics.endFill();

        _stateField.text = isOn ? labelOn : labelOff;
    }

    public function getState():Bool 
    {
        return (_outContact != null && _outContact.value == true);
    }

    public function setState(value:Bool):Void 
    {
        if (atom != null && Std.isOfType(atom, ToggleAtom)) 
        {
            cast(atom, ToggleAtom).setState(value);
        }
    }

    // =========================================================================
    // TRANSFORM MIRROR & CARD PLACEMENT (Picture pattern)
    // =========================================================================
    private function syncTransformMirror():Void
    {
        if (_zOrderContact != null && _zOrderContact.value != null)
        {
            _tZOrder = Math.round(parseFloat(_zOrderContact.value, _tZOrder));
        }
    }

    private function applyCardPlacement():Void
    {
        if (!isDeviceMode()) return;

        var card:Dynamic = parent;
        if (card == null) return;

        // Apply zOrder only if changed (dedupe guard - Picture pattern)
        if (_tZOrder >= 1 && _tZOrder != _appliedZ)
        {
            _appliedZ = _tZOrder;
            var panel:Dynamic = Reflect.getProperty(card, "parent");
            if (panel != null && Reflect.hasField(panel, "setCardZOrder"))
            {
                try
                {
                    Reflect.callMethod(panel, Reflect.field(panel, "setCardZOrder"), [card, _tZOrder]);
                }
                catch (e:Dynamic)
                {
                    // exotic owner (e.g. DeviceWindow without the z-system) -
                    // honest no-op: the depth stays auto there
                }
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        if (_btn != null) 
        {
            _btn.removeEventListener(MouseEvent.CLICK, onClick);
            _btn.removeEventListener(MouseEvent.MOUSE_OVER, onOver);
            _btn.removeEventListener(MouseEvent.MOUSE_OUT, onOut);
        }
        _btn = null;
        _outContact = null;
        _rstContact = null;
        _setContact = null;
        _zOrderContact = null;
        _labelField = null;
        _stateField = null;
        super.dispose();
    }
}