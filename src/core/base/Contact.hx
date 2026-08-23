package core.base;
import core.logic.TickGenerator;
import core.types.ContactType;
import core.types.ContactType.*;
import utils.UID;

/**
* CONTACT v5.12 (Gateway Repeat Forwarding + Link Lifecycle Traps)
*
* A connection point that can be linked to other contacts.
* When value changes, it propagates to linked targets.
*
* Key Features:
* - Oscillation protection (prevents infinite loops)
* - Silent value setting (for batched driver updates)
* - Callback subscription (for widgets and DeviceViews)
* - v5.9: TOPOLOGY GUARD (Defers propagation during graph mutation)
* - v5.10: TRAP PROBE (filtered set_value logging for conduction
* - v5.11: LINK/UNLINK lifecycle traps + _receiveValue probe
*   (gateway-link death forensics)
*   forensics — see utils.Trap.NAMES)
*
* Comparison of Write Methods:
* ┌────────────────────┬───────────────────────────────────────────────────────┐
* │ Method             │ Behavior                                              │
* ├────────────────────┼───────────────────────────────────────────────────────┤
* │ contact.value = x  │ Write + schedule(_propagate) in TickGenerator         │
* │                    │ (Triggers downstream atom recalculation)              │
* ├────────────────────┼───────────────────────────────────────────────────────┤
* │ setValueSilent(x)  │ ONLY writes to _value. Does not trigger anything.     │
* │                    │ Used by drivers for "silent" data preparation         │
* ├────────────────────┼───────────────────────────────────────────────────────┤
* │ propagateCurrent.. │ Calls _propagate() for current value.                 │
* │ Value()            │ Called by drivers ONCE after Silent write             │
* └────────────────────┴───────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════
* v5.9 TOPOLOGY GUARD INTEGRATION
* ═══════════════════════════════════════════════════════════════════════
*
* When TickGenerator.isTopologyLocked() is true (e.g., during GroupAtoms,
* Undo/Redo, or Port Deletion), signal propagation is deferred.
* This prevents Use-After-Free crashes when atoms/ports are disposed
* while the reactive graph is mid-calculation.
*/
class Contact
{
// ========================================================================
// PROPERTIES
// ========================================================================
/** Unique identifier for this contact. */
public var id(default, null):String;
/** Contact type (INPUT, OUTPUT, BIDIRECTIONAL, UNDEFINED). */
public var type(default, null):ContactType;
/** Contact name (e.g., "in", "out", "freq"). */
public var name(default, null):String;
/** Owner atom (who this contact belongs to). */
public var owner:Atom;
/** Current value (getter/setter with propagation logic). */
public var value(get, set):Dynamic;
private var _value:Dynamic;
/** Linked target contacts (for signal propagation). */
private var linkedTargets:Array<Contact>;
/** Callback subscribers (widgets, DeviceViews). */
private var callbackTargets:Array<Dynamic -> Void>;
/** Is propagation currently scheduled? */
private var _isScheduled:Bool = false;
/** Is this contact disposed? */
public var isDisposed(default, null):Bool = false;
/** windows for frame */
private var _windowStart:Float = 0.0;  // новое поле
// ========================================================================
// OSCILLATION PROTECTION
// ========================================================================
/** Current propagation depth (prevents infinite recursion). */
private static var _propagationDepth:Int = 0;
/** Maximum allowed propagation depth. */
private static inline var MAX_PROPAGATION_DEPTH:Int = 100;
/** Time of last value change (for oscillation detection). */
private var _lastChangeTime:Float = 0;
/** Number of changes in current window. */
private var _changeCount:Int = 0;
/** Is oscillation currently blocked? */
private var _oscillationBlocked:Bool = false;
/** Should this contact ignore oscillation detection? */
public var ignoreOscillation:Bool = false;
/** v5.12: GATEWAY MODE — forward repeated identical values.
 * Conduit contacts (ConductorPort internal/external) MUST
 * deliver every write: consumers behind them may use the
 * consume-and-reset pattern (e.g. TextArea.append), so a
 * repeat IS a meaningful event. Leaf atoms keep the dedup. */
public var forwardRepeats:Bool = false;
/** Maximum changes per second before blocking. */
private static inline var CHANGES_PER_SECOND_LIMIT:Int = 600;
/** Time window for oscillation detection (seconds). */
private static inline var OSCILLATION_WINDOW:Float = 1.0;

// ========================================================================
// CONSTRUCTOR
// ========================================================================
/**
* Create a new Contact.
*
* @param initialValue Initial value
* @param type         Contact type
* @param name         Contact name
*/
public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed")
{
this.id = UID.generate();
this.type = (type == null) ? ContactType.UNDEFINED : type;
this.name = name;
this._value = initialValue;
this.linkedTargets = [];
this.callbackTargets = [];
}

// ========================================================================
// LINKING
// ========================================================================
/**
* Link this contact to a target.
*
* If this contact has a value, it propagates to the target immediately
* (unless suppressPropagation is true).
*
* @param target              Target contact to link to
* @param suppressPropagation If true, do not propagate current value
*/
public function link(target:Contact, ?suppressPropagation:Bool = false):Void
{
if (target == null) return;
if (hasLink(target)) return;
// v5.11: link lifecycle trap
if (utils.Trap.nameMatches(this.name) || utils.Trap.nameMatches(target.name))
utils.Trap.log("LINK", (owner != null ? owner.id : "?") + "." + this.name + " -> " + (target.owner != null ? target.owner.id : "?") + "." + target.name + (suppressPropagation ? " [silent]" : ""));
linkedTargets.push(target);
if (_value != null && !suppressPropagation)
{
target.value = _value;
}
}

/**
* Propagate current value to all linked targets.
*
* This method:
* 1. Notifies owner atom (onContactChanged)
* 2. Propagates to linked contacts
* 3. Notifies callback subscribers (widgets)
*
* Used by drivers after setValueSilent() to trigger a single propagation.
* 
* v5.9: Defers execution if Topology Guard is active.
*/
public function propagateCurrentValue():Void
{
if (_value == null || isDisposed) return;
if (!canPropagate()) return;

// v5.9: TOPOLOGY GUARD - Defer if graph is mutating
var tg = TickGenerator.getInstance();
if (tg.isTopologyLocked())
{
tg.deferTopologyTask(function() {
if (!isDisposed) _propagate();
});
return;
}

// 1. Notify owner atom (like in _propagate)
if (owner != null) owner.onContactChanged(this);

// 2. Propagate to linked targets (wires)
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

// 3. Notify callback subscribers (widgets, DeviceViews)
// FIX: This block was previously missing, causing widgets to not
// receive updates from drivers using setValueSilent.
if (callbackTargets != null)
{
for (callback in callbackTargets)
{
if (callback != null) callback(this._value);
}
}
}

/**
* Receive a value from a linked contact.
*
* Schedules propagation if not already scheduled.
*
* @param newValue New value to receive
*/
private function _receiveValue(newValue:Dynamic):Void
{
if (isDisposed) return;
if (!forwardRepeats && _value == newValue) return;
if (_oscillationBlocked) return;

// v5.11: probe the propagateCurrentValue delivery path
if (utils.Trap.nameMatches(this.name)) utils.Trap.log("CONTACT", (owner != null ? owner.id : "?") + "." + this.name + " <= " + Std.string(newValue) + " [recv]");
_value = newValue;

// v5.9: TOPOLOGY GUARD - Defer if graph is mutating
var tg = TickGenerator.getInstance();
if (tg.isTopologyLocked())
{
tg.deferTopologyTask(function() {
if (!isDisposed) _propagate();
});
return;
}

if (!_isScheduled)
{
_isScheduled = true;
tg.schedule(_propagate, NORMAL);
}
}

/**
* Check if this contact can propagate.
*
* @return true if not disposed
*/
public function canPropagate():Bool
{
if (isDisposed) return false;
return true;
}

/**
* Unlink a target contact.
*
* @param target Target to unlink
*/
public function unlink(target:Contact):Void
{
if (linkedTargets != null)
{
var removed = linkedTargets.remove(target);
// v5.11: unlink lifecycle trap
if (removed && (utils.Trap.nameMatches(this.name) || utils.Trap.nameMatches(target.name)))
utils.Trap.log("UNLINK", (owner != null ? owner.id : "?") + "." + this.name + " -x- " + (target.owner != null ? target.owner.id : "?") + "." + target.name);
}
}

/**
* Check if this contact is linked to a target.
*
* @param target Target to check
* @return true if linked
*/
public function hasLink(target:Contact):Bool
{
if (linkedTargets == null) return false;
return linkedTargets.indexOf(target) != -1;
}

// ========================================================================
// SUBSCRIPTION (for widgets)
// ========================================================================
/**
* Subscribe a callback to value changes.
*
* Used by DeviceViews to receive updates when contact value changes.
*
* @param callback Function to call on value change (receives new value)
*/
public function subscribe(callback:Dynamic -> Void):Void
{
if (callback == null) return;
if (hasCallback(callback)) return;
callbackTargets.push(callback);
}

/**
* Unsubscribe a callback.
*
* @param callback Function to remove
*/
public function unsubscribe(callback:Dynamic -> Void):Void
{
if (callbackTargets != null) callbackTargets.remove(callback);
}

/**
* Check if a callback is already subscribed.
*
* @param callback Function to check
* @return true if subscribed
*/
private function hasCallback(callback:Dynamic -> Void):Bool
{
return callbackTargets != null && callbackTargets.indexOf(callback) != -1;
}

// ========================================================================
// VALUE GETTER/SETTER
// ========================================================================
/**
* Set value with propagation logic.
*
* This setter:
* 1. Checks for oscillation
* 2. Checks propagation depth
* 3. Schedules propagation via TickGenerator
* 
* v5.9: Defers propagation if Topology Guard is active.
*
* @param newValue New value to set
* @return The value that was set
*/
private function set_value(newValue:Dynamic):Dynamic
{
if (isDisposed) return newValue;
// v5.10: TRAP PROBE — filtered, crash-proof conduction trace.
if (utils.Trap.nameMatches(this.name)) utils.Trap.log("CONTACT", (owner != null ? owner.id : "?") + "." + this.name + " <= " + Std.string(newValue));
if (!forwardRepeats && _value == newValue && !Std.isOfType(newValue, Array)) return newValue;

// Oscillation detection
var currentTime = haxe.Timer.stamp();

// Заблокированы? Ждём полной секунды тишины
if (_oscillationBlocked) {
    if (currentTime - _lastChangeTime >= OSCILLATION_WINDOW) {
        _oscillationBlocked = false;
        _changeCount = 0;
        _windowStart = currentTime;
    } else {
        return newValue;
    }
}

// Катим фиксированное окно
if (currentTime - _windowStart >= OSCILLATION_WINDOW) {
    _windowStart = currentTime;
    _changeCount = 0;
}
_lastChangeTime = currentTime;
_changeCount++;

if (!ignoreOscillation && _changeCount > CHANGES_PER_SECOND_LIMIT) {
    _oscillationBlocked = true;
    return newValue;
}

// Recursion protection
if (_propagationDepth >= MAX_PROPAGATION_DEPTH) return newValue;

_propagationDepth++;
try
{
_value = newValue;

// v5.9: TOPOLOGY GUARD - Defer if graph is mutating
var tg = TickGenerator.getInstance();
if (tg.isTopologyLocked())
{
tg.deferTopologyTask(function() {
if (!isDisposed) _propagate();
});
return newValue;
}

if (!_isScheduled)
{
_isScheduled = true;
tg.schedule(_propagate, NORMAL);
}
}
catch (e:Dynamic) { }
_propagationDepth--;

return newValue;
}

/**
* v5.8: Silent value write without scheduling propagation.
*
* Significantly reduces TickGenerator load during batched updates.
* Used by drivers (e.g., MiniAudioAtom, SignalGenerator) to prepare
* multiple output values before triggering a single propagation.
*
* @param newValue New value to set (no propagation triggered)
*/
public function setValueSilent(newValue:Dynamic):Void
{
if (isDisposed) return;
_value = newValue;
}

/**
* Reset oscillation detection state.
*
* Call this when you want to clear the change counter.
*/
public function resetOscillation():Void
{
_oscillationBlocked = false;
_changeCount = 0;
_lastChangeTime = 0.0;
}

/**
* Get current value.
*
* @return Current value
*/
private function get_value():Dynamic return _value;

/**
* Internal propagation method.
*
* Called by TickGenerator when scheduled.
* Propagates value to all linked targets and callbacks.
*/
private function _propagate():Void
{
if (isDisposed)
{
_isScheduled = false;
return;
}
_isScheduled = false;
if (!canPropagate()) return;
if (_oscillationBlocked) return;

// Notify owner atom
if (owner != null) owner.onContactChanged(this);

// Propagate to linked contacts
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

// Notify callbacks
if (callbackTargets != null)
{
for (callback in callbackTargets)
{
if (callback != null) callback(this._value);
}
}
}

// ========================================================================
// UTILITY
// ========================================================================
/**
* Get current value (alternative to .value getter).
*
* @return Current value
*/
public function getValue():Dynamic { return _value; }

/**
* Set value directly without any propagation logic.
*
* USE WITH CAUTION - bypasses all safety checks.
*
* @param value Value to set
*/
public function setValueDirect(value:Dynamic):Void { _value = value; }

/**
* Get type name of current value.
*
* @return Type name ("bool", "int", "float", "string", "array", "object", "unknown")
*/
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

// ========================================================================
// LINK QUERY HELPERS (v3.2)
// ========================================================================
/**
* Check if this contact has any incoming or outgoing links.
*
* Used by NodeView to determine if inline editor should be shown.
*
* @return true if has links
*/
public function hasLinks():Bool {
return linkedTargets != null && linkedTargets.length > 0;
}

/**
* Get the number of linked targets.
*
* @return Number of links
*/
public function getLinkCount():Int {
return linkedTargets != null ? linkedTargets.length : 0;
}

/**
* Get all linked target contacts.
* Used by Assembly to safely clean up topology before rebuilding.
*/
public function getLinkedTargets():Array<Contact> {
return (linkedTargets != null) ? linkedTargets.copy() : [];
}

// ========================================================================
// DISPOSE
// ========================================================================
/**
* Dispose contact and clean up all references.
*
* Called when owner atom is destroyed.
*/
public function dispose():Void
{
if (isDisposed) return;
// v5.11: contact death trap
if (utils.Trap.nameMatches(this.name)) utils.Trap.log("CONTACT-DISPOSE", (owner != null ? owner.id : "?") + "." + this.name + " (links=" + (linkedTargets != null ? linkedTargets.length : 0) + ")");
isDisposed = true;

// Unlink all targets
if (linkedTargets != null)
{
for (target in linkedTargets)
{
if (target != null && !target.isDisposed)
{
target.unlink(this);
}
}
linkedTargets.resize(0);
linkedTargets = null;
}

// Clear callbacks
if (callbackTargets != null)
{
callbackTargets.resize(0);
callbackTargets = null;
}
owner = null;
}
}