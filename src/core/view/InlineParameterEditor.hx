package core.view;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Contact;
import core.data.Blueprint.PinDef;

/**
* InlineParameterEditor v1.0 (v3.2)
* Inline contact value editor directly on node body in Editor.
*
* Logic:
* - If contact has incoming connection → editor hidden
* - Otherwise → show default value from PinDef
* - On change → write to contact.value
*
* Architecture:
* ┌─────────────────────────────────────────────────────────────────┐
* │  NodeView (Editor Mode)                                         │
* │                                                                 │
* │  INPUTS:                                                        │
* │  ○ freq    [440.0]  ← InlineParameterEditor (if no wire)        │
* │  ○ quantum [0.10]   ← InlineParameterEditor                     │
* │  ○ in      ━━━━━━   ← port only (wire connected)                │
* └─────────────────────────────────────────────────────────────────┘
*/
class InlineParameterEditor extends Sprite
{
	private var _contact:Contact;
	private var _pinDef:PinDef;
	private var _inputField:TextField;
	private var _labelField:TextField;
	private var _isEditing:Bool = false;
	public function new(contact:Contact, pinDef:PinDef)
	{
		super();
		_contact = contact;
		_pinDef = pinDef;
// Protection against null pinDef
		if (_pinDef == null)
		{
// Create minimal pinDef for contact
			_pinDef =
			{
				name: contact.name,
				type: contact.type,
				defaultValue: contact.value,
				label: contact.name,
				priority: core.data.Blueprint.ParameterPriority.OPTIONAL,
				visibleInEditor: true,
				editable: true
			};
		}
		buildUI();
		subscribeToContact();
		updateDisplay();
	}
	private function buildUI():Void
	{
// Label (parameter name)
		_labelField = new TextField();
		_labelField.defaultTextFormat = new TextFormat("_sans", 9, 0x888888);
		_labelField.text = (_pinDef.label != null) ? _pinDef.label : _pinDef.name;
		_labelField.width = 50;
		_labelField.height = 14;
		_labelField.selectable = false;
		_labelField.mouseEnabled = false;
		addChild(_labelField);
// Input field (value editor)
		_inputField = new TextField();
		_inputField.type = TextFieldType.INPUT;
		_inputField.defaultTextFormat = new TextFormat("_sans", 10, 0x00AAFF, true);
		_inputField.width = 60;
		_inputField.height = 16;
		_inputField.y = 14;
		_inputField.border = true;
		_inputField.borderColor = 0x333344;
		_inputField.background = true;
		_inputField.backgroundColor = 0x1a1a24;
		_inputField.selectable = true;
		_inputField.mouseEnabled = true;
// Set default value
		if (_pinDef.defaultValue != null)
		{
			_inputField.text = Std.string(_pinDef.defaultValue);
		}
		_inputField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
		_inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
		_inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		addChild(_inputField);
	}
	private function subscribeToContact():Void
	{
		_contact.subscribe(function(v:Dynamic)
		{
			if (!_isEditing)
			{
				updateDisplay();
			}
		});
	}
	private function updateDisplay():Void
	{
		if (_contact.value != null)
		{
			_inputField.text = Std.string(_contact.value);
		}
		else if (_pinDef.defaultValue != null)
		{
			_inputField.text = Std.string(_pinDef.defaultValue);
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
		if (e.keyCode == Keyboard.ENTER)
		{
			pushValue();
			if (stage != null) stage.focus = null;
		}
	}
	private function pushValue():Void
	{
		var text = _inputField.text;
		var floatVal = Std.parseFloat(text);
		if (!Math.isNaN(floatVal))
		{
			_contact.value = floatVal;
		}
		else if (text.toLowerCase() == "true")
		{
			_contact.value = true;
		}
		else if (text.toLowerCase() == "false")
		{
			_contact.value = false;
		}
		else {
			_contact.value = text;
		}
	}
	/**
	* Hide editor (when wire connected).
	*/
	public function hideEditor():Void
	{
		_inputField.visible = false;
		_labelField.x = 0;
	}
	/**
	* Show editor (when wire disconnected).
	*/
	public function showEditor():Void
	{
		_inputField.visible = true;
		_labelField.x = 0;
		_inputField.x = 55;
		updateDisplay();
	}
	public function dispose():Void
	{
		_contact.unsubscribe(null);
		_inputField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
		_inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
		_inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		if (_inputField.parent != null) _inputField.parent.removeChild(_inputField);
		if (_labelField.parent != null) _labelField.parent.removeChild(_labelField);
		_inputField = null;
		_labelField = null;
	}
}