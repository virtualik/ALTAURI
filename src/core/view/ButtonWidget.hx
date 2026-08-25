package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;

/**
 * BUTTON WIDGET v1.1 (Trap Probes — button press timeline forensics)
 * Push button widget for sending impulses.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ButtonAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "out" ◄─── ButtonWidget                                       │
 * │                    ┌─────────────────────────────────────────────────┐  │
 * │                    │ onMouseDown: contact.value = true               │  │
 * │                    │ onMouseUp:   contact.value = false              │  │
 * │                    └─────────────────────────────────────────────────┘  │
 * │                                                                         │
 * │   Widget WRITES to atom's contact (user input → model)                  │
 * │   Widget DOES NOT store state - atom is the Databank                    │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ButtonWidget extends DeviceView 
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _btn:Sprite;
    private var _labelField:TextField;
    private var _contact:Contact;
    private var _isPressed:Bool = false;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Widget dimensions
    public var widgetWidth:Float = 80;
    public var widgetHeight:Float = 40;

    // Widget size return (used by Reflect in DeviceView base class)
    override public function getWidgetSize():{width:Float, height:Float} 
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    public var colorNormal:Int = 0x444455;
    public var colorPressed:Int = 0x4488AA;
    public var colorOver:Int = 0x555566;
    public var label:String = "PUSH";
    private var _contactName:String;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom, ?contactName:String = "out") 
    {
        super(atom);
        _contactName = contactName;
        findContact();
        buildUI();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    private function findContact():Void 
    {
        if (atom != null) 
        {
            _contact = atom.getOutput(_contactName);
            if (_contact == null) _contact = atom.getInput(_contactName);
        }
    }

    override private function onActivate():Void 
    {
        findContact();
    }

    private function buildUI():Void 
    {
        _btn = new Sprite();
        _btn.buttonMode = true;
        _btn.useHandCursor = true;
        _btn.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _btn.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        _btn.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
        _btn.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        addChild(_btn);

        _labelField = new TextField();
        _labelField.width = widgetWidth;
        _labelField.height = widgetHeight;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        var fmt = new TextFormat("_sans", 14, 0xFFFFFF, true);
        fmt.align = TextFormatAlign.CENTER;
        _labelField.defaultTextFormat = fmt;
        _labelField.text = label;
        addChild(_labelField);

        var nameField = new TextField();
        nameField.width = widgetWidth;
        nameField.height = 18;
        nameField.y = widgetHeight + 5;
        nameField.selectable = false;
        nameField.mouseEnabled = false;
        var nameFmt = new TextFormat("_sans", 10, 0x888888);
        nameFmt.align = TextFormatAlign.CENTER;
        nameField.defaultTextFormat = nameFmt;
        nameField.text = atom != null ? atom.name : "Button";
        addChild(nameField);

        drawNormal();
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    private function onMouseDown(e:MouseEvent):Void 
    {
        e.stopPropagation();
        _isPressed = true;
        drawPressed();
        utils.Trap.log("BTN", "press");
        if (_contact != null) 
        {
            _contact.value = true;
        }
    }

    private function onMouseUp(e:MouseEvent):Void 
    {
        e.stopPropagation();
        if (_isPressed) 
        {
            _isPressed = false;
            drawNormal();
            utils.Trap.log("BTN", "release");
            if (_contact != null) 
            {
                _contact.value = false;
            }
        }
    }

    private function onMouseOver(e:MouseEvent):Void 
    {
        if (!_isPressed) 
        {
            drawOver();
        }
    }

    private function onMouseOut(e:MouseEvent):Void 
    {
        if (_isPressed) 
        {
            _isPressed = false;
            drawNormal();
            utils.Trap.log("BTN", "release(out)");
            if (_contact != null) 
            {
                _contact.value = false;
            }
        } 
        else 
        {
            drawNormal();
        }
    }

    // =========================================================================
    // DRAWING
    // =========================================================================
    private function drawNormal():Void 
    {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorNormal);
        _btn.graphics.lineStyle(2, 0x666677);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }

    private function drawPressed():Void 
    {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorPressed);
        _btn.graphics.lineStyle(2, 0x88AACC);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }

    private function drawOver():Void 
    {
        _btn.graphics.clear();
        _btn.graphics.beginFill(colorOver);
        _btn.graphics.lineStyle(2, 0x777788);
        _btn.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _btn.graphics.endFill();
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void 
    {
        // Button is an input device - normally doesn't react to contact changes.
        // If visual feedback from an external source is needed, implement here.
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void 
    {
        if (_btn != null) 
        {
            _btn.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _btn.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _btn.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            _btn.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        }
        _btn = null;
        _contact = null;
        _labelField = null;
        super.dispose();
    }
}