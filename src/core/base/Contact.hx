package core.base;

import core.logic.SignalQueue;
import core.types.ContactType;

/**
* * CONTACT v5.5 (Hot Start Protocol Fix)
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
    public var id(default, null):Dynamic;
    public var type(default, null):ContactType;
    public var name(default, null):String;
    public var owner:Atom;
    public var value(get, set):Dynamic;
    private var _value:Dynamic;
    private var linkedTargets:Array<Contact>;
    private var callbackTargets:Array<Dynamic -> Void>;
    private var _isScheduled:Bool = false;
    public var isDisposed(default, null):Bool = false;
    private static var _propagationDepth:Int = 0;
    private static inline var MAX_PROPAGATION_DEPTH:Int = 100;

    // === FIX v5.5: Осцилляция определяется по частоте изменений ===
    private var _lastChangeTime:Float = 0;
    private var _changeCount:Int = 0;
    private var _oscillationBlocked:Bool = false;
    private static inline var CHANGES_PER_SECOND_LIMIT:Int = 600; // Увеличено для 60FPS

    public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed")
    {
        this.id = "c_" + Std.random(100000);
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

        _value = newValue;

        if (!_isScheduled)
        {
            _isScheduled = true;
            SignalQueue.getInstance().schedule(_propagate, NORMAL);
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
        if (_value == newValue) return newValue;

        // === FIX v5.5: Убрана блокировка isInitializing ===
        // Теперь Contact.value просто обновляется и планирует распространение.

        // === FIX v5.5: Обнаружение осцилляции ===
        var currentTime = haxe.Timer.stamp();
        var currentSecond = Std.int(currentTime);

        // Сброс счетчика в новую секунду
        if (currentSecond > Std.int(_lastChangeTime)) {
            _changeCount = 0;
            _oscillationBlocked = false;
        }
        
        _lastChangeTime = currentTime;
        _changeCount++;

        if (_changeCount > CHANGES_PER_SECOND_LIMIT)
        {
            _oscillationBlocked = true;
            return newValue;
        }

        // === ЗАЩИТА ОТ РЕКУРСИИ ===
        if (_propagationDepth >= MAX_PROPAGATION_DEPTH)
        {
            return newValue;
        }
        _propagationDepth++;

        _value = newValue;
        if (!_isScheduled)
        {
            _isScheduled = true;
            SignalQueue.getInstance().schedule(_propagate, NORMAL);
        }

        _propagationDepth--;
        return newValue;
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
        try {
            Reflect.fields(_value);
            return "object";
        } catch (e:Dynamic) {
            return "unknown";
        }
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