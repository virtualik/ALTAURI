package core.base;

import core.logic.SignalQueue;
import core.types.Priority;
import core.types.ContactType;

/**
 * CONTACT v4.1 (Memory Leak Fixed)
 * Eliminates recursive data transfer.
 * Uses SignalQueue to schedule updates.
 *
 * FIX v4.1:
 * - dispose() now clears owner reference
 * - dispose() cancels scheduled propagation
 * - Added defensive null checks
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
    private var _isDisposed:Bool = false;

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

    public function subscribe(callback:Dynamic -> Void):Void {
        if (callback == null) return;
        if (hasCallback(callback)) return;
        callbackTargets.push(callback);
    }

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
        if (_isDisposed) return newValue;
        
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
        // Guard against disposed contact
        if (_isDisposed) {
            _isScheduled = false;
            return;
        }
        
        _isScheduled = false;

        // 1. Pass values to linked contacts
        // This triggers set_value -> scheduling a new task -> stack doesn't grow.
        if (linkedTargets != null) {
            for (target in linkedTargets) {
                if (target != null && !target._isDisposed) {
                    target.value = this._value;
                }
            }
        }

        // 2. Notify owner (Atom) directly if it exists
        if (owner != null) {
            owner.onContactChanged(this);
        }

        // 3. Notify external subscribers (e.g., UI, View)
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
     * FIX v4.1: Complete cleanup to allow garbage collection.
     */
    public function dispose():Void {
        // 1. Mark as disposed first to prevent any further operations
        _isDisposed = true;
        _isScheduled = false;
        
        // 2. Clear linked targets (break references)
        if (linkedTargets != null) {
            // Unlink from all targets to break bidirectional references
            for (target in linkedTargets) {
                if (target != null) {
                    target.unlink(this);
                }
            }
            linkedTargets.resize(0);
            linkedTargets = null;
        }
        
        // 3. Clear callback targets
        if (callbackTargets != null) {
            callbackTargets.resize(0);
            callbackTargets = null;
        }
        
        // 4. Clear value
        _value = null;
        
        // 5. Clear owner reference (CRITICAL!)
        owner = null;
    }
    
    /**
     * Check if this contact is disposed.
     */
    public var isDisposed(get, never):Bool;
    private function get_isDisposed():Bool {
        return _isDisposed;
    }
}
