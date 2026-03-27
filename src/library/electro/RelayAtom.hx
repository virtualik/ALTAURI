package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * RELAY ATOM v1.4 (Correctness Pass)
 * Реле — пропускает сигнал только когда управление активно.
 *
 * v1.4 Changes:
 * - FIXED: onContactChanged() and _calculate() now use getInput() by name
 *   instead of direct index access (_inputs[0], _inputs[1]) — eliminates
 *   fragility when contact order changes or subclasses add inputs.
 * - FIXED: getPersistentState() merges with super result to preserve base
 *   class fields (isLogic) alongside relay state.
 * - FIXED: restoreState() calls super.restoreState() first so base class
 *   fields are restored before subclass-specific logic runs.
 * - IMPROVED: _calculate() reads from contacts directly rather than from
 *   stale cache — cache is now used only as a convenience for isOpen()
 *   and getLastSignal() API, not as the source of truth for computation.
 *
 * v1.3 Changes:
 * - Fix: Reset Schedule Flag inside _calculate.
 * - Added State Serialization (getPersistentState, restoreState).
 */
class RelayAtom extends Atom
{

	// =========================================================================
	// DATABANK - Кэш последних значений для публичного API
	// =========================================================================

	/**
	 * Последнее значение сигнала. Используется в getLastSignal().
	 * Не является источником истины для вычислений — только для внешнего API.
	 */
	private var _signalValue:Dynamic = null;

	/**
	 * Последнее состояние управления. Используется в isOpen().
	 * Не является источником истины для вычислений — только для внешнего API.
	 */
	private var _controlValue:Bool = false;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================

	public function new(id:String)
	{
		super(
			[
				new Contact(null, INPUT, "signal"),   // Что передаём
				new Contact(false, INPUT, "control")  // Открываем (true) или закрываем (false)
			],
			[
				new Contact(null, OUTPUT, "out")
			],
			null,
			id,
			"Relay"
		);
	}

	// =========================================================================
	// COMPUTE MODULE
	// =========================================================================

	/**
	 * Обновляем кэш и передаём управление базовому классу для планирования
	 * вызова _calculate().
	 *
	 * v1.4: Использует getInput() по имени вместо прямого доступа по индексу.
	 */
	override public function onContactChanged(c:Contact):Void
	{
		// Обновляем кэш для публичного API (isOpen, getLastSignal)
		var signalContact = getInput("signal");
		var controlContact = getInput("control");

		if (signalContact != null) _signalValue = signalContact.value;
		if (controlContact != null) _controlValue = (controlContact.value == true);

		// Передаём управление базовому классу — он запланирует _calculate()
		super.onContactChanged(c);
	}

	/**
	 * Логика реле: пропускает сигнал если управление активно.
	 *
	 * v1.4: Читает значения напрямую из контактов — не из кэша.
	 * Кэш (_signalValue, _controlValue) предназначен только для внешнего API.
	 */
	override private function _calculate():Void
	{
		// Сбрасываем флаг явно — страховка при прямом вызове
		_isScheduled = false;

		var signalContact = getInput("signal");
		var controlContact = getInput("control");
		var outContact = getOutput("out");

		if (signalContact == null || controlContact == null || outContact == null) return;

		if (controlContact.value == true)
		{
			// Управление активно — пропускаем сигнал
			outContact.value = signalContact.value;
		}
		else
		{
			// Управление неактивно — закрываем выход
			outContact.value = null;
		}
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================

	/**
	 * Проверить открыто ли реле (пропускает ли сигнал).
	 */
	public function isOpen():Bool
	{
		return _controlValue;
	}

	/**
	 * Получить последнее значение сигнала прошедшего через реле.
	 */
	public function getLastSignal():Dynamic
	{
		return _signalValue;
	}

	// =========================================================================
	// STATE SERIALIZATION v1.4
	// =========================================================================

	/**
	 * Сохраняем состояние реле для персистентности.
	 * v1.4: Merges with super result to preserve base class fields (isLogic).
	 */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();

		var outContact = getOutput("out");
		var outputValue:Dynamic = (outContact != null) ? outContact.value : null;

		var result:Dynamic = {
			lastOutput: outputValue,
			controlState: _controlValue
		};

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
	 * Восстанавливаем состояние реле из сохранённых данных.
	 * v1.4: Calls super.restoreState() first so base class fields
	 * are restored before subclass-specific logic runs.
	 */
	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;

		super.restoreState(state);

		var outContact = getOutput("out");

		if (state.lastOutput != null && outContact != null)
		{
			outContact.value = state.lastOutput;
		}

		if (state.controlState != null)
		{
			_controlValue = state.controlState;
		}
	}
}