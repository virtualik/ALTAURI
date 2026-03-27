package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT INPUT ATOM v1.3 (Correctness Pass)
 * Пассивный атом для ввода строковых или числовых значений.
 *
 * v1.3 Changes:
 * - FIXED: _calculate() now uses getInput()/getOutput() by name instead of
 *   direct index access — safer against future contact order changes.
 * - FIXED: getPersistentState() merges with super result to preserve base
 *   class fields (isLogic) alongside the text value.
 * - FIXED: restoreState() calls super.restoreState() first so base class
 *   fields are restored before subclass-specific logic runs.
 *
 * v1.2 Changes:
 * - Fix: Correctly resets _isScheduled flag.
 * - New: Implements State Serialization.
 */
class TextInputAtom extends Atom
{

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================

	public function new(id:String)
	{
		super(
			[
				new Contact(null, INPUT, "set")
			],
			[
				new Contact("", OUTPUT, "out")
			],
			null,
			id,
			"TextInput"
		);
	}

	// =========================================================================
	// COMPUTE MODULE
	// =========================================================================

	/**
	 * Если на вход "set" пришло значение — транслируем его на выход "out".
	 *
	 * Примечание: _isScheduled сбрасывается здесь явно для надёжности,
	 * хотя базовый класс Atom._calculate() также сбрасывает его в первой строке.
	 * Двойной сброс безвреден — это страховка на случай прямого вызова.
	 */
	override private function _calculate():Void
	{
		_isScheduled = false;

		var setContact = getInput("set");
		var outContact = getOutput("out");

		if (setContact == null || outContact == null) return;

		var val = setContact.value;
		if (val != null)
		{
			outContact.value = val;
		}
	}

	// =========================================================================
	// STATE SERIALIZATION v1.3
	// =========================================================================

	/**
	 * Сохраняем текущее значение выхода.
	 * v1.3: Merges with super result to preserve base class fields (isLogic).
	 */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();

		var outContact = getOutput("out");
		var currentValue:Dynamic = (outContact != null) ? outContact.value : null;

		var result:Dynamic = { value: currentValue };

		if (base != null)
		{
			if (Reflect.hasField(base, "isLogic"))
			{
				Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
			}
		}

		return result;
	}

	/**
	 * При загрузке восстанавливаем значение.
	 * v1.3: Calls super.restoreState() first so base class fields
	 * are restored before subclass-specific logic runs.
	 */
	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;

		super.restoreState(state);

		if (state.value != null)
		{
			var outContact = getOutput("out");
			if (outContact != null)
			{
				outContact.value = state.value;
			}
		}
	}
}