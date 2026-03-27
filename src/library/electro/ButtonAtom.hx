package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * BUTTON ATOM v1.3 (TickGenerator Migration)
 * Кнопка с двумя состояниями (нажата/отпущена).
 *
 * v1.3 Changes:
 * - FIXED: Migrated from SignalQueue to TickGenerator — completes the
 *   migration started in Atom/Contact and removes the last reference
 *   to the legacy SignalQueue in the electro library.
 * - FIXED: getPersistentState() now merges with super result so that
 *   base class fields (isLogic) are preserved alongside button state.
 * - FIXED: restoreState() now calls super.restoreState() first so that
 *   base class fields are restored before subclass-specific logic runs.
 *
 * v1.2 Changes:
 * - Uses scheduleNextTick() to sync output changes with the simulation tick.
 * - Prevents race conditions within the same frame.
 *
 * v1.1 Changes:
 * - Added getPersistentState() for saving button state
 * - Added restoreState() for restoring button state on load
 */
class ButtonAtom extends Atom
{

	private var _state:Bool = false;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================

	public function new(id:String)
	{
		super(
			[],
			[new Contact(false, OUTPUT, "out")],
			null,
			id,
			"Button"
		);
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================

	/**
	 * Toggle button state (for external control).
	 */
	public function toggle():Void
	{
		setState(!_state);
	}

	/**
	 * Set button state directly.
	 * v1.3: Uses TickGenerator.scheduleNextTick() instead of legacy SignalQueue.
	 * Schedules the output update for the next tick to keep user input
	 * stable for all logic within the current frame.
	 */
	public function setState(value:Bool):Void
	{
		_state = value;

		TickGenerator.getInstance().scheduleNextTick(function()
		{
			if (_outputs != null && _outputs.length > 0)
			{
				_outputs[0].value = _state;
			}
		});
	}

	/**
	 * Get current button state.
	 */
	public function getState():Bool
	{
		return _state;
	}

	// =========================================================================
	// STATE SERIALIZATION v1.3
	// =========================================================================

	/**
	 * Save button state for persistence.
	 * v1.3: Merges with super result to preserve base class fields (isLogic).
	 */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();

		// Базовый класс возвращает null когда isLogic == false.
		// Создаём объект состояния и добавляем поля базового класса если они есть.
		var result:Dynamic = { state: _state };

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
	 * Restore button state from saved data.
	 * v1.3: Calls super.restoreState() first so base class fields
	 * are restored before subclass-specific logic runs.
	 */
	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;

		// Сначала восстанавливаем поля базового класса (isLogic и др.)
		super.restoreState(state);

		if (state.state != null)
		{
			_state = state.state;
			// Восстанавливаем значение контакта напрямую — без планировщика,
			// чтобы начальное состояние было доступно сразу при загрузке.
			if (_outputs != null && _outputs.length > 0)
			{
				_outputs[0].value = _state;
			}
		}
	}
}