package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Contact;
import library.logic.ConductorAtom;

/**
 * CONDUCTOR WIDGET v1.1 (Databank Architecture)
 * Multi-input OR gate widget with dynamic port management.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ConductorAtom (Databank)                                              │
 * │                                                                         │
 * │   Contact "in0", "in1", ... "out" ◄──► ConductorWidget                  │
 * │                                        ┌───────────────────────────────┐│
 * │                                        │ Shows:                        ││
 * │                                        │ - Current ON/OFF state        ││
 * │                                        │ - Input count                 ││
 * │                                        │ - Add/Remove buttons          ││
 * │                                        └───────────────────────────────┘│
 * │                                                                         │
 * │   Widget READS atom's output state (from Databank)                      │
 * │   Widget CALLS atom methods to modify inputs                            │
 * │   Atom is the Databank - stores input count                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ConductorWidget extends DeviceView {

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _bg:Sprite;
    private var _stateField:TextField;
    private var _countField:TextField;
    private var _addBtn:Sprite;
    private var _removeBtn:Sprite;
    private var _outContact:Contact;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    public var widgetWidth:Float = 100;
    public var widgetHeight:Float = 60;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom) {
        super(atom);

        if (atom != null) {
            _outContact = atom.getOutput("out");
        }

        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================

    private function buildUI():Void {
        _bg = new Sprite();
        addChild(_bg);

        _stateField = new TextField();
        _stateField.width = widgetWidth;
        _stateField.height = 25;
        _stateField.y = 5;
        _stateField.selectable = false;
        _stateField.mouseEnabled = false;
        var fmt = new TextFormat("_sans", 14, 0xFFFFFF, true);
        fmt.align = TextFormatAlign.CENTER;
        _stateField.defaultTextFormat = fmt;
        addChild(_stateField);

        _countField = new TextField();
        _countField.width = widgetWidth;
        _countField.height = 15;
        _countField.y = 28;
        _countField.selectable = false;
        _countField.mouseEnabled = false;
        var fmt2 = new TextFormat("_sans", 10, 0x88AACC);
        fmt2.align = TextFormatAlign.CENTER;
        _countField.defaultTextFormat = fmt2;
        addChild(_countField);

        // Remove button (-)
        _removeBtn = createButton("−", 0x663333, onRemoveClick);
        _removeBtn.x = 10;
        _removeBtn.y = widgetHeight - 22;
        addChild(_removeBtn);

        // Add button (+)
        _addBtn = createButton("+", 0x336633, onAddClick);
        _addBtn.x = widgetWidth - 35;
        _addBtn.y = widgetHeight - 22;
        addChild(_addBtn);

        updateCountDisplay();
        updateVisual();
    }

    private function createButton(label:String, color:Int, callback:MouseEvent -> Void):Sprite {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRoundRect(0, 0, 25, 18, 4, 4);
        btn.graphics.endFill();
        btn.buttonMode = true;
        btn.useHandCursor = true;

        var tf = new TextField();
        tf.text = label;
        tf.width = 25;
        tf.height = 18;
        tf.selectable = false;
        tf.mouseEnabled = false;
        tf.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, "center");
        btn.addChild(tf);

        btn.addEventListener(MouseEvent.CLICK, callback);
        return btn;
    }

    private function updateCountDisplay():Void {
        var count = 2;
        if (atom != null && Std.isOfType(atom, ConductorAtom)) {
            count = cast(atom, ConductorAtom).getInputCount();
        }
        _countField.text = 'Inputs: $count';
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (contact == _outContact) {
            updateVisual();
        }
    }

    private function updateVisual():Void {
        var isOn = false;
        if (_outContact != null && _outContact.value == true) {
            isOn = true;
        }

        _bg.graphics.clear();
        _bg.graphics.beginFill(isOn ? 0x2A5A3A : 0x2A3A4A);
        _bg.graphics.lineStyle(2, isOn ? 0x4AAA6A : 0x4A6A8A);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 8, 8);
        _bg.graphics.endFill();

        _stateField.text = isOn ? "ON" : "OFF";
        _stateField.textColor = isOn ? 0x00FF88 : 0xAAAAAA;
    }

    // =========================================================================
    // BUTTON HANDLERS
    // =========================================================================

    private function onAddClick(e:MouseEvent):Void {
        e.stopPropagation();
        if (atom != null && Std.isOfType(atom, ConductorAtom)) {
            cast(atom, ConductorAtom).addInput();
            updateCountDisplay();
        }
    }

    private function onRemoveClick(e:MouseEvent):Void {
        e.stopPropagation();
        if (atom != null && Std.isOfType(atom, ConductorAtom)) {
            cast(atom, ConductorAtom).removeLastInput();
            updateCountDisplay();
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        if (_addBtn != null) {
            _addBtn.removeEventListener(MouseEvent.CLICK, onAddClick);
        }
        if (_removeBtn != null) {
            _removeBtn.removeEventListener(MouseEvent.CLICK, onRemoveClick);
        }
        _addBtn = null;
        _removeBtn = null;
        _outContact = null;
        _bg = null;
        _stateField = null;
        _countField = null;
        super.dispose();
    }
}
