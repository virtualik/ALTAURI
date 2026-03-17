package core.base;

import core.types.ContactType;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ATOM BASE CLASS v5.3 (State Serialization)
 * Fundamental unit of logic. Independent of rendering engine.
 *
 * v5.3 Changes:
 * - Added getPersistentState() for saving atom state
 * - Added restoreState() for restoring atom state on load
 * - Default implementations return null (no state to save)
 */
class Atom implements IDisposable implements Driver {

    public var id(default, null):String;
    public var type(default, null):String;
    public var name(default, null):String;

    // В Haxe private = protected (доступен в подклассах)
    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;
    private var _process:Array<Dynamic> -> Array<Dynamic>;

    private var _inputCache:Array<Dynamic>;
    private var _isScheduled:Bool = false;
    private var _isActive:Bool = false;
    private var _isDisposed:Bool = false;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic",
        ?isActive:Bool = false
    ) {
        this.id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;

        this._isActive = isActive;

        this._inputs = (inputs != null) ? inputs : [];
        this._outputs = (outputs != null) ? outputs : [];
        this._process = processFunc;

        _inputCache = [];
        for (i in 0..._inputs.length) _inputCache.push(null);

        _bind();

        if (_isActive) {
            DriverManager.getInstance().register(this);
        }
    }

    private function _bind():Void {
        for (input in _inputs) {
            if (input != null) input.owner = this;
        }
    }

    public function init():Void { }

    public function update(dt:Float):Void {
        _onUpdate(dt);
    }

    private function _onUpdate(dt:Float):Void { }

    /**
     * Called by Contact when its value changes.
     */
    public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;
        _isScheduled = true;
        core.logic.SignalQueue.getInstance().schedule(_calculate, NORMAL);
    }

    private function _calculate():Void {
        _isScheduled = false;

        if (_isDisposed || _process == null || _inputs == null) return;

        for (i in 0..._inputs.length) {
            _inputCache[i] = _inputs[i].value;
        }

        var results = _process(_inputCache);

        if (results != null && results.length == _outputs.length) {
            for (i in 0..._outputs.length) {
                if (_outputs[i] != null) _outputs[i].value = results[i];
            }
        }
    }

    // =========================================================================
    // STATE SERIALIZATION v5.3
    // =========================================================================

    /**
     * Get persistent state for saving.
     * Override in subclasses to save atom-specific data.
     * 
     * Default implementation returns null (no state to save).
     * 
     * Example implementations:
     * - ButtonAtom: { state: _state }
     * - SignalGeneratorAtom: { frequency: _frequency, phase: _phase }
     * - TextInputAtom: { value: _outputs[0].value }
     * 
     * @return Dynamic object containing state data, or null if no state
     */
    public function getPersistentState():Dynamic { 
        return null; 
    }

    /**
     * Restore state from saved data.
     * Override in subclasses to restore atom-specific data.
     * 
     * Called when loading a project to restore the atom's state.
     * The state parameter contains the data returned by getPersistentState().
     * 
     * @param state The saved state data
     */
    public function restoreState(state:Dynamic):Void { 
        // Default: do nothing
    }

    // =========================================================================
    // GETTERS
    // =========================================================================

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact {
        if (_inputs == null) return null;
        for (c in _inputs) {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    public function getOutput(name:String):Contact {
        if (_outputs == null) return null;
        for (c in _outputs) {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    public function dispose():Void {
        _isDisposed = true;

        if (_isActive) {
            DriverManager.getInstance().unregister(this.id);
        }

        if (_inputs != null) {
            for (c in _inputs) {
                if (c != null) c.dispose();
            }
        }

        if (_outputs != null) {
            for (c in _outputs) {
                if (c != null) c.dispose();
            }
        }

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}
