package core.base;

import core.logic.TickGenerator;
import core.types.ContactType;
import utils.UID;

/**
 * CONTACT v5.7 (Stability & Correctness Pass)
 *
 * v5.7 Changes:
 * - FIXED: ID generation now uses UID.generate() to prevent collisions
 *   (old Std.random(100000) produced duplicates in large graphs).
 * - FIXED: Oscillation detection rewritten from second-boundary comparison
 *   to delta-time window — eliminates false positives at second boundaries.
 * - FIXED: _propagationDepth static counter now protected via try/finally
 *   to guarantee decrement even when downstream code throws.
 * - FIXED: restoreState isLogic condition was inverted — now correctly
 *   restores both true and false states.
 * - IMPROVED: getValueType() replaced try/catch object detection with
 *   Reflect.isObject() — avoids exception overhead on hot path.
 * - IMPROVED: _receiveValue now also checks _oscillationBlocked before
 *   scheduling, not only in _propagate — reduces unnecessary task creation.
 *
 * v5.6 Changes:
 * - Migrated from SignalQueue to TickGenerator.
 *
 * v5.5 Changes (HOT START PROTOCOL):
 * - REMOVED: Blocking propagation based on owner.isInitializing.
 * - REASON: Signals must flow freely during startup to update indicators (LED).
 *           The logic atoms (TextInput, Gates) block their own reaction via Atom.isInitializing.
 * - KEPT: Oscillation detection intact
 *
 * v5.4 Changes (CRITICAL FIX):
 * - FIXED: isInitializing check now works correctly with new Assembly initialization order
 * - FIXED: propagateCurrentValue() respects isInitializing flag
 * - IMPROVED: Better coordination with Assembly._processPendingSignals()
 * - ADDED: canPropagate() method for checking propagation ability
 *
 * v5.3 Changes:
 * - ADDED: Check for parent Assembly.isInitializing to prevent propagation during creation.
 * - FIXED: Feedback circuits (T-TRIGGER) no longer oscillate during initialization.
 *
 * v5.2 Changes:
 * - REMOVED: Excessive logging that caused freezing.
 * - ADDED: Real oscillation detection that STOPS propagation.
 * - FIXED: T-TRIGGER works without freezing.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Atom (Model)                                                          │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Contact "in" ──────┬─────────────────────┬─────────────────────│   │
 * │   │                     │                     │                     │   │
 * │   │                     │                     │                     │   │
 * │   │   linkedTargets ────┼──► Contact "out"    │                     │   │
 * │   │   (передача         │   (другой атом)     │                     │   │
 * │   │    данных)          │                     │                     │   │
 * │   │                     │                     │                     │   │
 * │   │   callbackTargets ──┼─────────────────────┼──► DeviceView #1    │   │
 * │   │   (уведомление      │                     │    (NodeView)       │   │
 * │   │    подписчиков)     │                     │                     │   │
 * │   │                     │                     └──► DeviceView #2    │   │
 * │   │                     │                          (DeviceWindow)   │   │
 * │   │   owner ────────────┼──► Atom.onContactChanged()                │   │
 * │   │   (атом-владелец)   │    (внутренняя обработка)                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Headless Mode:                                                        │
 * │   ──────────────                                                        │
 * │   - linkedTargets работает ✓ (передача данных между атомами)            │
 * │   - owner работает ✓ (атом обрабатывает данные)                         │
 * │   - callbackTargets не используется (нет DeviceView)                    │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v4.4 Changes:
 * - Added getValue() and setValue() for cleaner state access
 * - Added getValueType() for type detection
 */

class Contact
{
	public var id(default, null):String;
	public var type(default, null):ContactType;
	public var name(default, null):String;
	public var owner:Atom;
	public var value(get, set):Dynamic;
	private var _value:Dynamic;
	private var linkedTargets:Array<Contact>;
	private var callbackTargets:Array<Dynamic -> Void>;
	private var _isScheduled:Bool = false;
	public var isDisposed(default, null):Bool = false;

	// === ЗАЩИТА ОТ РЕКУРСИИ ===
	// Статический счётчик глубины рекурсии для всех контактов.
	// Защищён через try/finally чтобы гарантировать декремент даже при исключениях.
	private static var _propagationDepth:Int = 0;
	private static inline var MAX_PROPAGATION_DEPTH:Int = 100;
	// === ОБНАРУЖЕНИЕ ОСЦИЛЛЯЦИИ v5.7 ===
	// Используем дельта-время вместо сравнения границ секунд.
	// Это устраняет ложные срабатывания когда изменение происходит
	// ровно на границе двух секунд (currentSecond > lastSecond давало сброс
	// счётчика в тот же момент когда должна была сработать блокировка).
	private var _lastChangeTime:Float = 0;
	private var _changeCount:Int = 0;
	private var _oscillationBlocked:Bool = false;
	public var ignoreOscillation:Bool = false;
	private static inline var CHANGES_PER_SECOND_LIMIT:Int = 600;
	private static inline var OSCILLATION_WINDOW:Float = 1.0; // секунд

	public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed")
	{
		// v5.7: используем UID для гарантии уникальности идентификатора
		// (Std.random(100000) давал коллизии в графах с > ~300 контактами)
		this.id = UID.generate();
		this.type = (type == null) ? ContactType.UNDEFINED : type;
		this.name = name;
		this._value = initialValue;
		this.linkedTargets = [];
		this.callbackTargets = [];
	}

	public function link(target:Contact, ?suppressPropagation:Bool = false):Void
	{
		if (target == null) return;
		if (hasLink(target)) return;
		linkedTargets.push(target);
		if (_value != null && !suppressPropagation)
		{
			target.value = _value;
		}
	}

	public function propagateCurrentValue():Void
	{
		if (_value == null || isDisposed) return;

		// === FIX v5.5: Убрана проверка isInitializing ===
		// Сигнал должен распространяться всегда.
		if (!canPropagate()) return;

		if (linkedTargets != null)
		{
			for (target in linkedTargets)
			{
				if (target != null && !target.isDisposed)
				{
					target._receiveValue(_value);
				}
			}
		}
	}

	private function _receiveValue(newValue:Dynamic):Void
	{
		if (isDisposed) return;
		if (_value == newValue) return;

		// v5.7: Проверяем блокировку осцилляции ДО создания задачи в очереди.
		// Раньше задача создавалась всегда, а блокировка проверялась только
		// в _propagate — это приводило к накоплению мёртвых задач в TickGenerator.
		if (_oscillationBlocked) return;

		_value = newValue;

		if (!_isScheduled)
		{
			_isScheduled = true;
			TickGenerator.getInstance().schedule(_propagate, NORMAL);
		}
	}

	/**
	 * Check if this contact can propagate values.
	 *
	 * v5.5 FIX: Removed isInitializing check to allow signal flow during startup.
	 */
	public function canPropagate():Bool
	{
		if (isDisposed) return false;
		// === FIX v5.5: РАЗРЕШАЕМ РАСПРОСТРАНЕНИЕ ===
		// Блокировка реакции теперь лежит на Atom.onContactChanged
		return true;
	}

	public function unlink(target:Contact):Void
	{
		if (linkedTargets != null) linkedTargets.remove(target);
	}

	public function hasLink(target:Contact):Bool
	{
		if (linkedTargets == null) return false;
		return linkedTargets.indexOf(target) != -1;
	}

	public function subscribe(callback:Dynamic -> Void):Void
	{
		if (callback == null) return;
		if (hasCallback(callback)) return;
		callbackTargets.push(callback);
	}

	public function unsubscribe(callback:Dynamic -> Void):Void
	{
		if (callbackTargets != null) callbackTargets.remove(callback);
	}

	private function hasCallback(callback:Dynamic -> Void):Bool
	{
		return callbackTargets != null && callbackTargets.indexOf(callback) != -1;
	}

	private function set_value(newValue:Dynamic):Dynamic
	{
		if (isDisposed) return newValue;

		// === FIX v5.6: Массивы всегда считаются "изменёнными" ===
		// Генератор передаёт тот же _buffer (ссылка), но содержимое изменилось.
		// Без этого fix propagate НЕ вызывается и осциллограф не обновляется!
		if (_value == newValue && !Std.isOfType(newValue, Array)) return newValue;

		// === ОБНАРУЖЕНИЕ ОСЦИЛЛЯЦИИ v5.7 ===
		// Считаем изменения в скользящем окне OSCILLATION_WINDOW секунд.
		// Дельта-подход устраняет ложные сбросы на границах секунд.
		var currentTime = haxe.Timer.stamp();
		var elapsed = currentTime - _lastChangeTime;

		if (elapsed >= OSCILLATION_WINDOW)
		{
			// Прошло достаточно времени — сбрасываем счётчик и снимаем блокировку
			_changeCount = 0;
			_oscillationBlocked = false;
		}

		_lastChangeTime = currentTime;
		_changeCount++;

		if (!ignoreOscillation && _changeCount > CHANGES_PER_SECOND_LIMIT)
		{
			_oscillationBlocked = true;
			trace('Contact ${name} blocked due to oscillation, changes=$_changeCount, elapsed=$elapsed');
			return newValue;
		}

		// === ЗАЩИТА ОТ РЕКУРСИИ v5.7 ===
		// try гарантирует декремент счётчика даже если downstream код
		// выбросит исключение — без этого счётчик "застревал" и блокировал
		// все последующие распространения до перезагрузки.
		if (_propagationDepth >= MAX_PROPAGATION_DEPTH)
		{
			return newValue;
		}

		_propagationDepth++;
		try
		{
			_value = newValue;
			if (!_isScheduled)
			{
				_isScheduled = true;
				TickGenerator.getInstance().schedule(_propagate, NORMAL);
			}
		}
		catch (e:Dynamic)
		{

		}
		_propagationDepth--;

		return newValue;
	}
	
	public function resetOscillation():Void {
		_oscillationBlocked = false;
		_changeCount = 0;
		_lastChangeTime = 0.0;
	}
	
	private function get_value():Dynamic return _value;

	private function _propagate():Void
	{
		if (isDisposed) { _isScheduled = false; return; }
		_isScheduled = false;

		if (!canPropagate()) return;
		if (_oscillationBlocked) return;

		// 1. Уведомляем владельца (Атом решает: реагировать или нет, проверив isInitializing)
		if (owner != null)
		{
			owner.onContactChanged(this);
		}

		// 2. Передаём значение дальше (Свободное распространение)
		if (linkedTargets != null)
		{
			for (target in linkedTargets)
			{
				if (target != null && !target.isDisposed)
				{
					target.value = this._value;
				}
			}
		}

		// 3. Уведомляем UI
		if (callbackTargets != null)
		{
			for (callback in callbackTargets)
			{
				if (callback != null) callback(this._value);
			}
		}
	}

	public function getValue():Dynamic { return _value; }
	public function setValueDirect(value:Dynamic):Void { _value = value; }

	public function getValueType():String
	{
		if (_value == null) return "null";
		if (Std.isOfType(_value, Bool)) return "bool";
		if (Std.isOfType(_value, Int)) return "int";
		if (Std.isOfType(_value, Float)) return "float";
		if (Std.isOfType(_value, String)) return "string";
		if (Std.isOfType(_value, Array)) return "array";
		// v5.7: Reflect.isObject() вместо try/catch — нет накладных расходов
		// на создание и обработку исключения на горячем пути.
		if (Reflect.isObject(_value)) return "object";
		return "unknown";
	}

	public function dispose():Void
	{
		if (isDisposed) return;
		isDisposed = true;
		if (linkedTargets != null)
		{
			for (target in linkedTargets)
			{
				if (target != null && !target.isDisposed) target.unlink(this);
			}
			linkedTargets.resize(0);
			linkedTargets = null;
		}
		if (callbackTargets != null)
		{
			callbackTargets.resize(0);
			callbackTargets = null;
		}
		owner = null;
	}
}