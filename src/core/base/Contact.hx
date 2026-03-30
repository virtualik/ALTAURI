package core.base;

import core.logic.TickGenerator;
import core.types.ContactType;
import utils.UID;

/**
 * CONTACT v5.8 (Batched Driver Update & Stability Pass)
 *
 * v5.8 Changes:
 * - ADDED: setValueSilent() метод.
 *   Позволяет драйверам (Atom с isLogic=false) обновлять множество выходов
 *   без создания промежуточных задач в TickGenerator на каждый выход.
 *   Устраняет проблему "N лишних итераций process()" при пакетном обновлении.
 *
 * Сравнение методов записи:
 * ┌────────────────────┬───────────────────────────────────────────────────────┐
 * │ Метод              │ Поведение                                             │
 * ├────────────────────┼───────────────────────────────────────────────────────┤
 * │ contact.value = x  │ Запись + schedule(_propagate) в TickGenerator         │
 * │                    │ (Триггерит пересчет downstream атомов)                │
 * ├────────────────────┼───────────────────────────────────────────────────────┤
 * │ setValueSilent(x)  │ ТОЛЬКО запись в _value. Ничего не триггерит.          │
 * │                    │ Используется драйверами для "тихой" подготовки данных │
 * ├────────────────────┼───────────────────────────────────────────────────────┤
 * │ propagateCurrent.. │ Вызывает _propagate() для текущего значения.          │
 * │ Value()            │ Вызывается драйверами ОДИН раз после Silent-записи    │
 * └────────────────────┴───────────────────────────────────────────────────────┘
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
	private static var _propagationDepth:Int = 0;
	private static inline var MAX_PROPAGATION_DEPTH:Int = 100;

	// === ОБНАРУЖЕНИЕ ОСЦИЛЛЯЦИИ v5.7 ===
	private var _lastChangeTime:Float = 0;
	private var _changeCount:Int = 0;
	private var _oscillationBlocked:Bool = false;
	public var ignoreOscillation:Bool = false;
	private static inline var CHANGES_PER_SECOND_LIMIT:Int = 600;
	private static inline var OSCILLATION_WINDOW:Float = 1.0;

	public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed")
	{
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
		if (_value != null && !suppressPropagation) target.value = _value;
	}

	public function propagateCurrentValue():Void
	{
		if (_value == null || isDisposed) return;
		if (!canPropagate()) return;

		if (linkedTargets != null)
		{
			for (target in linkedTargets)
			{
				if (target != null && !target.isDisposed) target._receiveValue(_value);
			}
		}
	}

	private function _receiveValue(newValue:Dynamic):Void
	{
		if (isDisposed) return;
		if (_value == newValue) return;

		if (_oscillationBlocked) return;

		_value = newValue;

		if (!_isScheduled)
		{
			_isScheduled = true;
			TickGenerator.getInstance().schedule(_propagate, NORMAL);
		}
	}

	public function canPropagate():Bool
	{
		if (isDisposed) return false;
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

		if (_value == newValue && !Std.isOfType(newValue, Array)) return newValue;

		var currentTime = haxe.Timer.stamp();
		var elapsed = currentTime - _lastChangeTime;

		if (elapsed >= OSCILLATION_WINDOW)
		{
			_changeCount = 0;
			_oscillationBlocked = false;
		}

		_lastChangeTime = currentTime;
		_changeCount++;

		if (!ignoreOscillation && _changeCount > CHANGES_PER_SECOND_LIMIT)
		{
			_oscillationBlocked = true;
			//   trace('Contact ${name} blocked due to oscillation, changes=$_changeCount, elapsed=$elapsed');
			return newValue;
		}

		if (_propagationDepth >= MAX_PROPAGATION_DEPTH) return newValue;

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
		catch (e:Dynamic) { }
		_propagationDepth--;

		return newValue;
	}

	/**
	 * v5.8: Тихая запись значения без создания задач в TickGenerator.
	 * Существенно снижает нагрузку на планировщик при пакетных обновлениях.
	 */
	public function setValueSilent(newValue:Dynamic):Void
	{
		if (isDisposed) return;
		_value = newValue;
	}

	public function resetOscillation():Void
	{
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

		if (owner != null) owner.onContactChanged(this);

		if (linkedTargets != null)
		{
			for (target in linkedTargets)
			{
				if (target != null && !target.isDisposed) target.value = this._value;
			}
		}

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