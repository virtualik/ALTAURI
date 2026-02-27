package core.base;

import core.logic.SignalQueue;
import core.types.Priority;
import core.types.ContactType;

/**
 * CONTACT v4.0 (Optimized + Queue Based)
 * Eliminates recursive data transfer.
 * Uses SignalQueue to schedule updates.
 */
class Contact {

    public var id(default, null):Dynamic;
    public var type(default, null):ContactType;
    public var name(default, null):String;

    // Reference to owner (for fast Atom notification without closures)
    public var owner:Atom;

    public var value(get, set):Dynamic;
    private var _value:Dynamic;

    private var linkedTargets:Array<Contact>;
    private var callbackTargets:Array<Dynamic -> Void>;

    // Flag to protect against re-scheduling the same task
    private var _isScheduled:Bool = false;

    public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed") {
        this.id = "c_" + Std.random(100000);
        this.type = (type == null) ? ContactType.UNDEFINED : type;
        this.name = name;
        this._value = initialValue;

        this.linkedTargets = [];
        this.callbackTargets = [];
    }

    public function link(target:Contact):Void {
        if (target == null) return;
        if (hasLink(target)) return;
        linkedTargets.push(target);

        // Initialization of value
        if (_value != null) {
            target.value = _value;
        }
    }

    public function unlink(target:Contact):Void {
        linkedTargets.remove(target);
    }

    public function hasLink(target:Contact):Bool {
        return linkedTargets.indexOf(target) != -1;
    }

    public function subscribe(callback:Dynamic -> Void):Void {
        if (callback == null) return;
        if (hasCallback(callback)) return;
        callbackTargets.push(callback);
    }

    public function unsubscribe(callback:Dynamic -> Void):Void {
        callbackTargets.remove(callback);
    }

    private function hasCallback(callback:Dynamic -> Void):Bool {
        return callbackTargets.indexOf(callback) != -1;
    }

    private function set_value(newValue:Dynamic):Dynamic {
        // Optimization: If value hasn't changed, exit
        if (_value == newValue) return newValue;

        _value = newValue;

        if (!_isScheduled) {
            _isScheduled = true;
            // Use normal priority
            SignalQueue.getInstance().schedule(_propagate, NORMAL);
        }

        return newValue;
    }

    private function get_value():Dynamic {
        return _value;
    }

    /**
     * Scheduled signal propagation.
     * Called iteratively from SignalQueue.
     */
    private function _propagate():Void {
        _isScheduled = false;

        // 1. Pass values to linked contacts
        // This triggers set_value -> scheduling a new task -> stack doesn't grow.
        for (target in linkedTargets) {
            target.value = this._value;
        }

        // 2. Notify owner (Atom) directly if it exists
        if (owner != null) {
            owner.onContactChanged(this);
        }

        // 3. Notify external subscribers (e.g., UI, View)
        for (callback in callbackTargets) {
            callback(this._value);
        }
    }

    public function dispose():Void {
        linkedTargets = [];
        callbackTargets = [];
        _value = null;
        owner = null;
    }
}