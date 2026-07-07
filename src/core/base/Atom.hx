package core.base;
import core.logic.TickGenerator;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
* ATOM BASE CLASS v7.1 (DisplayName Support)
* Fundamental unit of logic. Independent of rendering engine.
*
* An Atom is the smallest executable unit in the system.
* It holds inputs, outputs, and a processing function.
*
* Key Responsibilities:
* - Manages contact connections (inputs/outputs)
* - Schedules calculations via TickGenerator
* - Supports Logic Mode (digital) and Analog Mode (immediate)
* - Implements Driver interface for active components
* - v7.1: Supports user-friendly displayName with uniqueness
*/
class Atom implements IDisposable implements Driver
{
// ========================================================================
// PROPERTIES
// ========================================================================
public var id(get, never):String;
private function get_id():String return _id;
private var _id:String;

public var type(default, null):String;

public var name(default, null):String;

/**
* v7.1: User-friendly display name (editable, unique within Assembly).
* Used in UI for node identification.
* Default value: type (e.g., "Button", "NETRadioPlayer")
*/
public var displayName(get, set):String;
private var _displayName:String;

private function get_displayName():String {
    return _displayName != null ? _displayName : type;
}

private function set_displayName(value:String):String {
    _displayName = value;
    return value;
}

/**
* Determines the timing model for this atom.
* ┌────────────────┬────────────────────────────────────────────────┐
* │ Value          │ Behavior                                       │
* ├────────────────┼────────────────────────────────────────────────┤
* │ true (Digital) │ Output changes are scheduled for the NEXT tick │
* │ false (Analog) │ Output changes happen IMMEDIATELY              │
* └────────────────┴────────────────────────────────────────────────┘
*/
public var isLogic(get, set):Bool;
private var _isLogic:Bool = false;
private function get_isLogic():Bool return _isLogic;
private function set_isLogic(value:Bool):Bool
{
    _isLogic = value;
    return _isLogic;
}

private var _inputs:Array<Contact>;
private var _outputs:Array<Contact>;
private var _process:Array<Dynamic> -> Array<Dynamic>;
private var _inputCache:Array<Dynamic>;
private var _isScheduled:Bool = false;
private var _isActive:Bool = false;

/**
* v7.0: @:volatile forces the processor to always read from RAM,
* not from the thread register cache.
*
* This is critical for drivers (e.g., MiniAudioAtom).
* The OS audio thread checks _isDisposed in callback. Without @:volatile,
* the C++ compiler might cache the value in the audio thread's register,
* and after dispose() is called in the main thread, the audio thread
* will continue execution with a "stale" (false) flag value.
*/
@:volatile private var _isDisposed:Bool = false;
private var _hasCalculatedOnce:Bool = false;

// ========================================================================
// INITIALIZATION v7.0
// ========================================================================
public var isInitializing(get, set):Bool;
private var _isInitializing:Bool = false;
private function get_isInitializing():Bool return _isInitializing;
private function set_isInitializing(value:Bool):Bool
{
    _isInitializing = value;
    return _isInitializing;
}

/**
* Create a new Atom instance.
*
* @param inputs      Array of input contacts
* @param outputs     Array of output contacts
* @param processFunc Processing function (inputs -> outputs)
* @param id          Unique instance ID
* @param type        Atom type name
* @param isActive    If true, registers with DriverManager for updates
* @param displayName Optional user-friendly name (default: type)
*/
public function new(
    inputs:Array<Contact>,
    outputs:Array<Contact>,
    processFunc:Array<Dynamic> -> Array<Dynamic>,
    ?id:String,
    ?type:String = "Generic",
    ?isActive:Bool = false,
    ?displayName:String = null
)
{
    this._id = (id != null) ? id : "atom_" + Std.random(100000);
    this.type = type;
    this.name = type;
    this._displayName = (displayName != null) ? displayName : type;
    this._isActive = isActive;
    this._inputs = (inputs != null) ? inputs : [];
    this._outputs = (outputs != null) ? outputs : [];
    this._process = processFunc;
    _inputCache = [];
    for (i in 0..._inputs.length) _inputCache.push(null);
    _bind();
    var tg = TickGenerator.getInstance();
    var isAssemblyWithInternal = Std.isOfType(this, Assembly) &&
        cast(this, Assembly).blueprint != null &&
        cast(this, Assembly).blueprint.internalAtoms != null &&
        cast(this, Assembly).blueprint.internalAtoms.length > 0;
    // Schedule initial calculation if not an assembly with internal atoms
    // and TickGenerator is not suspended.
    if (_process != null && !isAssemblyWithInternal && !tg.isSuspended())
    {
        _isScheduled = true;
        TickGenerator.getInstance().scheduleNextTick(function()
        {
            if (!_isDisposed) _calculate();
        });
    }
    // Register as active driver if flag is set
    if (_isActive)
    {
        DriverManager.getInstance().register(this);
    }
}

/**
* Bind contacts to this atom as owner.
*/
private function _bind():Void
{
    for (input in _inputs)
    {
        if (input != null) input.owner = this;
    }
    for (output in _outputs)
    {
        if (output != null) output.owner = this;
    }
}

// ========================================================================
// LIFECYCLE
// ========================================================================
public function init():Void { }

/**
* Update loop for active drivers.
* Called by DriverManager every frame.
*/
public function update(dt:Float):Void
{
    _onUpdate(dt);
}

private function _onUpdate(dt:Float):Void { }

/**
* Called when a contact value changes.
* Schedules calculation if not already scheduled.
*/
public function onContactChanged(c:Contact):Void
{
    if (_isScheduled || _isDisposed) return;
    if (isInitializing) return;
    // Ignore changes from our own outputs (prevents feedback loops)
    if (c.type == OUTPUT && c.owner == this) return;
    if (_process != null)
    {
        _isScheduled = true;
        TickGenerator.getInstance().schedule(_calculate, NORMAL);
    }
}

/**
* Main calculation step.
* Reads inputs, runs process function, writes outputs.
*/
private function _calculate():Void
{
    _isScheduled = false;
    _hasCalculatedOnce = true;
    if (_isDisposed || _process == null || _inputs == null) return;
    // Cache input values
    for (i in 0..._inputs.length) _inputCache[i] = _inputs[i].value;
    // Process
    var results = _process(_inputCache);
    // Write outputs
    if (results != null && results.length == _outputs.length)
    {
        if (isLogic)
        {
            // Logic Mode: Schedule output update for next tick (unit delay)
            var outs = _outputs;
            var vals = results;
            TickGenerator.getInstance().scheduleNextTick(function()
            {
                if (_isDisposed) return;
                for (i in 0...outs.length)
                {
                    if (outs[i] != null) outs[i].value = vals[i];
                }
            });
        }
        else
        {
            // Analog Mode: Immediate update
            for (i in 0..._outputs.length)
            {
                if (_outputs[i] != null) _outputs[i].value = results[i];
            }
        }
    }
}

/**
* Force calculation immediately (bypass scheduler).
* Use with caution.
*/
public function forceCalculate():Void
{
    if (_isDisposed || _process == null || _inputs == null) return;
    _calculate();
}

// ========================================================================
// STATE SERIALIZATION v7.1
// ========================================================================
/**
* Save state for persistence.
* v7.1: Includes displayName
*/
public function getPersistentState():Dynamic
{
    if (_isLogic || _displayName != type) {
        return {
            isLogic: _isLogic,
            displayName: _displayName
        };
    }
    return null;
}

/**
* Restore state from saved data.
* v7.1: Restores displayName
*/
public function restoreState(state:Dynamic):Void
{
    if (state == null) return;
    // Firstly restore base feilds
    if (Reflect.hasField(state, "isLogic")) {
        this.isLogic = state.isLogic;
    }
    
    // === RESTORE displayName ===
    if (Reflect.hasField(state, "displayName")) 
    {
        _displayName = state.displayName;
        trace('Atom ${id}: Restored displayName = "${_displayName}"');
    }
}



// ========================================================================
// CONTACT ACCESS
// ========================================================================
public function getInputs():Array<Contact> return _inputs;
public function getOutputs():Array<Contact> return _outputs;

public function getInput(name:String):Contact
{
    if (_inputs == null) return null;
    for (c in _inputs) if (c != null && c.name == name) return c;
    return null;
}

public function getOutput(name:String):Contact
{
    if (_outputs == null) return null;
    for (c in _outputs) if (c != null && c.name == name) return c;
    return null;
}

public function getInputNames():Array<String>
{
    var names:Array<String> = [];
    for (c in _inputs) if (c != null && c.name != null) names.push(c.name);
    return names;
}

public function getOutputNames():Array<String>
{
    var names:Array<String> = [];
    for (c in _outputs) if (c != null && c.name != null) names.push(c.name);
    return names;
}

// ========================================================================
// DISPOSE
// ========================================================================
public function dispose():Void
{
    // v7.0: @:volatile guarantees visibility in Audio Thread
    _isDisposed = true;
    if (_isActive) DriverManager.getInstance().unregister(this.id);
    if (_inputs != null) { for (c in _inputs) { if (c != null) c.dispose(); } }
    if (_outputs != null) { for (c in _outputs) { if (c != null) c.dispose(); } }
    _inputs = null;
    _outputs = null;
    _process = null;
    _inputCache = null;
}
}