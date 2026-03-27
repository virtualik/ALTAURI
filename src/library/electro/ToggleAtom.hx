package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * TOGGLE ATOM v1.6 (TickGenerator Migration + Robustness Pass)
 * Переключатель с защитой от мгновенного сброса (Race Condition Protection).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   onContactChanged("rst") -> reset to false                             │
 * │   toggle() -> flip state                                                │
 * │   setState(v) -> set state directly                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   Contact "out" stores current state (true/false)                       │
 * │   getPersistentState() → { state: bool }                                │
 * │   restoreState() → restores contact value                               │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   ToggleWidget shows:                                                   │
 * │   - ON/OFF state                                                        │
 * │   - Click to toggle                                                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.6 Changes:
 * - FIXED: Migrated from SignalQueue to TickGenerator — removes the last
 *   reference to legacy SignalQueue in the electro library.
 * - FIXED: onContactChanged now uses getInput() by name instead of direct
 *   index access (_inputs[0], _inputs[1]) — safer when subclasses or
 *   future versions change the input order or add new contacts.
 * - FIXED: getPersistentState() merges with super result to preserve
 *   base class fields (isLogic) alongside toggle state.
 * - FIXED: restoreState() calls super.restoreState() first so base class
 *   fields are restored before subclass-specific logic runs.
 * - REMOVED: Dead commented-out code left from v1.4 migration.
 *
 * v1.5 Changes:
 * - setState (user interaction) now uses scheduleNextTick() for stability.
 * - Logic inputs (rst/set) remain reactive to work within tick propagation.
 */
class ToggleAtom extends Atom
{

	// =========================================================================
	// CONFIGURATION
	// =========================================================================

	/**
	 * Time in seconds during which Reset/Set is ignored after a manual toggle.
	 * Default: 0.1 seconds.
	 */
	public var resetImmunityTime:Float = 0.1;

	// =========================================================================
	// STATE
	// =========================================================================

	// Инициализируем в прошлом чтобы иммунитет не действовал при старте
	private var _lastToggleTime:Float = -3.0;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================

	public function new(id:String)
	{
		super(
			// Two inputs: rst (Reset) and set (Set)
			[
				new Contact(false, INPUT, "rst"),
				new Contact(false, INPUT, "set")
			],
			// One output: out (current state)
			[
				new Contact(false, OUTPUT, "out")
			],
			null,  // No process function - manual toggle
			id,
			"Toggle"
		);
	}

	// =========================================================================
	// COMPUTE MODULE
	// =========================================================================

	/**
	 * Called when any contact value changes.
	 * Handles reset and set signals with immunity check.
	 *
	 * v1.6: Uses getInput() by name instead of direct index access for safety.
	 */
	override public function onContactChanged(c:Contact):Void
	{
		if (_isScheduled || _isDisposed) return;

		var rstContact = getInput("rst");
		var setContact = getInput("set");

		if (rstContact == null && setContact == null)
		{
			super.onContactChanged(c);
			return;
		}

		var rstValue = (rstContact != null) ? rstContact.value : null;
		var setValue = (setContact != null) ? setContact.value : null;

		// === RESET IMMUNITY LOGIC ===
		// Игнорируем входящие сигналы rst/set в течение resetImmunityTime
		// после последнего ручного переключения. Это предотвращает
		// мгновенный сброс состояния в тот же тик когда пользователь нажал.
		var now = haxe.Timer.stamp();
		var elapsed = now - _lastToggleTime;

		if (elapsed < resetImmunityTime)
		{
			return;
		}
		// ============================

		// Priority: Reset > Set
		if (rstValue == true)
		{
			if (_outputs != null && _outputs.length > 0)
			{
				_outputs[0].value = false;
			}
			return;
		}

		if (setValue == true)
		{
			if (_outputs != null && _outputs.length > 0)
			{
				_outputs[0].value = true;
			}
			return;
		}

		super.onContactChanged(c);
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================

	/**
	 * Toggle the state.
	 */
	public function toggle():Void
	{
		if (_outputs != null && _outputs.length > 0)
		{
			setState(!(_outputs[0].value == true));
		}
	}

	/**
	 * Set state directly (User Interaction).
	 * Updates the immunity timestamp.
	 * v1.6: Uses TickGenerator.scheduleNextTick() instead of legacy SignalQueue.
	 */
	public function setState(value:Bool):Void
	{
		if (_outputs == null || _outputs.length == 0) return;

		// Фиксируем время ручного взаимодействия для механизма иммунитета
		_lastToggleTime = haxe.Timer.stamp();

		// Планируем на следующий такт для синхронизации с логическими часами.
		// Это гарантирует что rst/set сигналы из текущего такта не перезапишут
		// только что установленное состояние.
		TickGenerator.getInstance().scheduleNextTick(function()
		{
			if (_outputs != null && _outputs.length > 0)
			{
				_outputs[0].value = value;
			}
		});
	}

	/**
	 * Get current state.
	 */
	public function getState():Bool
	{
		if (_outputs != null && _outputs.length > 0)
		{
			return _outputs[0].value == true;
		}
		return false;
	}

	// =========================================================================
	// STATE SERIALIZATION v1.6
	// =========================================================================

	/**
	 * Save toggle state for persistence.
	 * v1.6: Merges with super result to preserve base class fields (isLogic).
	 */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();

		var currentState = false;
		if (_outputs != null && _outputs.length > 0)
		{
			currentState = _outputs[0].value == true;
		}

		// Строим результат из состояния тоггла и добавляем поля базового класса
		var result:Dynamic = { state: currentState };

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
	 * Restore toggle state from saved data.
	 * v1.6: Calls super.restoreState() first so base class fields
	 * are restored before subclass-specific logic runs.
	 * Restores contact value directly (no scheduler) to avoid
	 * triggering the immunity timer during loading.
	 */
	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;

		// Сначала восстанавливаем поля базового класса (isLogic и др.)
		super.restoreState(state);

		if (state.state != null)
		{
			if (_outputs != null && _outputs.length > 0)
			{
				// Восстанавливаем напрямую без планировщика и без обновления
				// _lastToggleTime — чтобы иммунитет не блокировал входящие
				// сигналы сразу после загрузки проекта.
				_outputs[0].value = state.state;
			}
		}
	}
}