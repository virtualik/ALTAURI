package core.base;

import core.logic.SignalQueue;
import core.types.Priority;
import core.types.ContactType;

/**
 * CONTACT v4.4 (State Serialization)
 * Eliminates recursive data transfer.
 * Uses SignalQueue to schedule updates.
 *
 * v4.4 Changes:
 * - Added getValue() and setValue() for cleaner state access
 * - Added getValueType() for type detection
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

    // Flag to track if disposed
    public var isDisposed(default, null):Bool = false;

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
        if (linkedTargets != null) {
            linkedTargets.remove(target);
        }
    }

    public function hasLink(target:Contact):Bool {
        if (linkedTargets == null) return false;
        return linkedTargets.indexOf(target) != -1;
    }

    /**
     * Subscribe to value changes.
     * Public method for DeviceView and other external subscribers.
     */
    public function subscribe(callback:Dynamic -> Void):Void {
        if (callback == null) return;
        if (hasCallback(callback)) return;
        callbackTargets.push(callback);
    }

    /**
     * Unsubscribe from value changes.
     */
    public function unsubscribe(callback:Dynamic -> Void):Void {
        if (callbackTargets != null) {
            callbackTargets.remove(callback);
        }
    }

    private function hasCallback(callback:Dynamic -> Void):Bool {
        if (callbackTargets == null) return false;
        return callbackTargets.indexOf(callback) != -1;
    }

    private function set_value(newValue:Dynamic):Dynamic {
        // Guard against disposed contact
        if (isDisposed) return newValue;

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
     * Get value as specific type.
     * Useful for state serialization.
     */
    public function getValue():Dynamic {
        return _value;
    }

    /**
     * Set value without triggering propagation.
     * Used during state restoration.
     */
    public function setValueSilent(newValue:Dynamic):Void {
        _value = newValue;
    }

    /**
     * Determine the type of the current value.
     * Returns: "null", "bool", "float", "int", "string", "array", "object"
     */
    public function getValueType():String {
        if (_value == null) return "null";
        if (Std.isOfType(_value, Bool)) return "bool";
        if (Std.isOfType(_value, Int)) return "int";
        if (Std.isOfType(_value, Float)) return "float";
        if (Std.isOfType(_value, String)) return "string";
        if (Std.isOfType(_value, Array)) return "array";
        return "object";
    }

    /**
     * Scheduled signal propagation.
     * Called iteratively from SignalQueue.
     */
    private function _propagate():Void {
        // Guard against disposed contact
        if (isDisposed) {
            _isScheduled = false;
            return;
        }

        _isScheduled = false;

        // 1. Pass values to linked contacts
        if (linkedTargets != null) {
            for (target in linkedTargets) {
                if (target != null && !target.isDisposed) {
                    target.value = this._value;
                }
            }
        }

        // 2. Notify owner (Atom) directly if it exists
        if (owner != null) {
            owner.onContactChanged(this);
        }

        // 3. Notify external subscribers (e.g., UI, View, DeviceView)
        if (callbackTargets != null) {
            for (callback in callbackTargets) {
                if (callback != null) {
                    callback(this._value);
                }
            }
        }
    }

    /**
     * Properly dispose the contact.
     */
    public function dispose():Void {
        // Guard against double-dispose
        if (isDisposed) return;

        isDisposed = true;
        _isScheduled = false;

        // Unlink from all targets (bidirectional cleanup)
        if (linkedTargets != null) {
            for (target in linkedTargets) {
                if (target != null && !target.isDisposed) {
                    target.unlink(this);
                }
            }
            linkedTargets.resize(0);
            linkedTargets = null;
        }

        // Clear all callbacks
        if (callbackTargets != null) {
            callbackTargets.resize(0);
            callbackTargets = null;
        }

        _value = null;
        owner = null;
    }
}
