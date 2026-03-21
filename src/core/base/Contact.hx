package core.base;

import core.logic.SignalQueue;
import core.types.Priority;
import core.types.ContactType;

/**
* CONTACT v5.1
 * v5.1 Changes:
 * - Order change in _propagate:
 *   1. Notify OWNER first (allows logic to clamp/cancel signal)
 *   2. Propagate to LINKED TARGETS second
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
class Contact {

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

    public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed") {
        this.id = "c_" + Std.random(100000);
        this.type = (type == null) ? ContactType.UNDEFINED : type;
        this.name = name;
        this._value = initialValue;
        this.linkedTargets = [];
        this.callbackTargets = [];
    }

    // ... (link, unlink, subscribe, unsubscribe - без изменений) ...
    
    public function link(target:Contact):Void {
        if (target == null) return;
        if (hasLink(target)) return;
        linkedTargets.push(target);
        if (_value != null) target.value = _value;
    }

    public function unlink(target:Contact):Void {
        if (linkedTargets != null) linkedTargets.remove(target);
    }
    
    public function hasLink(target:Contact):Bool {
        if (linkedTargets == null) return false;
        return linkedTargets.indexOf(target) != -1;
    }

    public function subscribe(callback:Dynamic -> Void):Void {
        if (callback == null) return;
        if (hasCallback(callback)) return;
        callbackTargets.push(callback);
    }

    public function unsubscribe(callback:Dynamic -> Void):Void {
        if (callbackTargets != null) callbackTargets.remove(callback);
    }

    private function hasCallback(callback:Dynamic -> Void):Bool {
        return callbackTargets != null && callbackTargets.indexOf(callback) != -1;
    }

    private function set_value(newValue:Dynamic):Dynamic {
        if (isDisposed) return newValue;
        if (_value == newValue) return newValue;

        _value = newValue;

        if (!_isScheduled) {
            _isScheduled = true;
            SignalQueue.getInstance().schedule(_propagate, NORMAL);
        }
        return newValue;
    }

    private function get_value():Dynamic return _value;

    /**
     * v5.1: Исправленный порядок распространения.
     */
    private function _propagate():Void {
        if (isDisposed) { _isScheduled = false; return; }
        _isScheduled = false;

        // 1. СНАЧАЛА уведомляем владельца (Atom).
        // Если это Reset вход, владелец (Toggle) может изменить ВЫХОД.
        if (owner != null) {
            owner.onContactChanged(this);
        }

        // 2. ПОТОМ передаем значение дальше.
        // Если владелец изменил выход, это изменение попадет в очередь.
        if (linkedTargets != null) {
            for (target in linkedTargets) {
                if (target != null && !target.isDisposed) {
                    target.value = this._value;
                }
            }
        }

        // 3. Уведомляем UI
        if (callbackTargets != null) {
            for (callback in callbackTargets) {
                if (callback != null) callback(this._value);
            }
        }
    }

    public function dispose():Void {
        if (isDisposed) return;
        isDisposed = true;
        
        if (linkedTargets != null) {
            for (target in linkedTargets) {
                if (target != null && !target.isDisposed) target.unlink(this);
            }
            linkedTargets.resize(0);
            linkedTargets = null;
        }
        
        if (callbackTargets != null) {
            callbackTargets.resize(0);
            callbackTargets = null;
        }
        owner = null;
    }
}