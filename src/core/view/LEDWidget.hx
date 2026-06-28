package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;

/**
 * LED WIDGET v3.0 (Databank Architecture)
 * Circular LED indicator for boolean or analog signals.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   LEDAtom (Databank)                                                    │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │   Contact "in" ──► onContactChanged() ──► callbackTargets       │   │
 * │   │                         │                                       │   │
 * │   │                         ▼                                       │   │
 * │   │   LEDWidget.onContactChanged(contact, value)                    │   │
 * │   │         │                                                       │   │
 * │   │         ▼                                                       │   │
 * │   │   updateVisual(isOn)                                            │   │
 * │   │         │                                                       │   │
 * │   │         ▼                                                       │   │
 * │   │   graphics.clear()                                              │   │
 * │   │   graphics.beginFill(isOn ? colorOn : colorOff)                 │   │
 * │   │   graphics.drawCircle(0, 0, radius)                             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Headless: Atom receives data, no widget needed.                       │
 * │   Normal: Widget displays atom's contact state.                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v3.0 Changes:
 * - Full Databank architecture compatibility
 * - No internal state storage - reads from contact
 */
class LEDWidget extends DeviceView {

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _ledSprite:Sprite;
    private var _labelField:TextField;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

	// Widget dimensions
   	public var widgetWidth:Float = 80;
	public var widgetHeight:Float = 60;
	// widget size return (из за Reflect)
	override public function getWidgetSize():{width:Float, height:Float} {
		return {width: widgetWidth, height: widgetHeight};
	}
	
	public var radius:Float = 20;
    public var colorOn:Int = 0x00FF00;
    public var colorOff:Int = 0x003300;
    public var labelOn:String = "ON";
    public var labelOff:String = "OFF";
    public var showLabel:Bool = true;
    public var threshold:Float = 0.1;
    // =========================================================================
    // STATE
    // =========================================================================

    private var _isUpdating:Bool = false;
    private var _contactName:String;

	
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom, contactName:String = "in") {
        super(atom);
        _contactName = contactName;
        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================

    private function buildUI():Void {
        _ledSprite = new Sprite();
        addChild(_ledSprite);

        if (showLabel) {
            _labelField = new TextField();
            _labelField.width = 80;
            _labelField.height = 20;
            _labelField.y = radius + 5;
            _labelField.x = -40;
            _labelField.selectable = false;
            _labelField.mouseEnabled = false;
            var fmt = new TextFormat("_sans", 11, 0xAAAAAA);
            fmt.align = TextFormatAlign.CENTER;
            _labelField.defaultTextFormat = fmt;
            addChild(_labelField);
        }

        updateVisual(false);
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================

    override private function syncFromAtom():Void {
        // Read current contact value
        if (atom != null) {
            var contact = atom.getInput(_contactName);
            if (contact == null) contact = atom.getOutput(_contactName);
            if (contact != null && contact.value != null) {
                updateVisual(isOn(contact.value));
            }
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        if (isDisposed || _isUpdating) return;

        if (contact.name == _contactName) {
            updateVisual(isOn(newValue));
        }
    }

    private function isOn(value:Dynamic):Bool {
        if (value == null) return false;
        if (Std.isOfType(value, Bool)) return cast(value, Bool);
        if (Std.isOfType(value, Float)) return cast(value, Float) > threshold;
        if (Std.isOfType(value, Int)) return cast(value, Int) > 0;
        return false;
    }

    private function updateVisual(isOn:Bool):Void {
        if (_isUpdating || isDisposed || _ledSprite == null) return;
        _isUpdating = true;

        _ledSprite.graphics.clear();
        _ledSprite.graphics.lineStyle(2, 0x444444);
        _ledSprite.graphics.beginFill(isOn ? colorOn : colorOff);
        _ledSprite.graphics.drawCircle(0 + widgetWidth / 2, 0 + widgetHeight / 2, radius);
        _ledSprite.graphics.endFill();

        // Glow effect when on
        if (isOn) {
            _ledSprite.graphics.lineStyle(0, 0, 0);
            _ledSprite.graphics.beginFill(0xFFFFFF, 0.7);
            _ledSprite.graphics.drawCircle(0 + widgetWidth / 2 -radius * 0.3, 0 + widgetHeight / 2 -radius * 0.3, radius * 0.3);
            _ledSprite.graphics.endFill();
        }

        if (_labelField != null) {
            _labelField.text = isOn ? labelOn : labelOff;
        }

        _isUpdating = false;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        _ledSprite = null;
        _labelField = null;
        super.dispose();
    }
}