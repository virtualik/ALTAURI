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
 * TOGGLE WIDGET v2.0 (Databank Architecture)
 * Toggle switch widget with two states.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "out" ◄──► ToggleWidget                                       │
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
 * │   v2.0: REMOVED _currentState - now reads directly from contact!        │
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
    private var _outContact:Contact;
    private var _rstContact:Contact;

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
        }
    }

    override private function onActivate():Void {
        findContacts();
        // Синхронизируем визуал с текущим состоянием Databank
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
     * Реакция на изменение контакта.
     * v2.0: Просто обновляем визуал, всё состояние в контакте.
     */
	override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
		if (contact == _outContact) {
			// Просто обновляем визуал, состояние в контакте
			updateVisual();
		} else if (contact == _rstContact) {
			if (newValue == true) {
				updateVisual();
			}
		}
	}

    /**
     * Клик по кнопке - переключаем состояние.
     * v2.0: Пишем прямо в контакт, без локального состояния.
     */
	private function onClick(e:MouseEvent):Void {
		// Читать текущее состояние ИЗ КОНТАКТА
		var currentState = (_outContact != null && _outContact.value == true);
		var newState = !currentState;
		
		// Писать в контакт
		if (_outContact != null) {
			_outContact.value = newState;
		}
		
		// Вызвать toggle на атоме
		if (atom != null && Std.isOfType(atom, library.electro.ToggleAtom)) {
			cast(atom, library.electro.ToggleAtom).setState(newState);
		}
		
		// Визуал обновится через onContactChanged()
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
     * Обновить визуальное представление.
     * v2.0: Читаем состояние НАПРЯМУЮ из контакта.
     */
    private function updateVisual():Void {

		// Читать из контакта
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
     * Получить текущее состояние ИЗ DATABANK (контакта).
     * v2.0: Единственный источник истины - контакт атома.
     */
    private function getCurrentState():Bool {
        if (_outContact != null && _outContact.value == true) {
            return true;
        }
        return false;
    }

    /**
     * Get current toggle state.
     * v2.0: Делегирует к контакту.
     */
    public function getState():Bool {
        return getCurrentState();
    }

    /**
     * Set state programmatically.
     * v2.0: Пишет в контакт.
     */
    public function setState(value:Bool):Void {
        if (_outContact != null) {
            _outContact.value = value;
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
        _labelField = null;
        _stateField = null;
        super.dispose();
    }
}