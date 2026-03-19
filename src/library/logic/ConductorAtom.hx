package library.logic;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.SignalQueue;
import core.types.Priority;

using core.types.ContactType;

/**
 * CONDUCTOR ATOM v1.0 (Multi-Input OR Gate)
 * Многовходовый кондуктор с логикой OR.
 *
 * Принцип работы:
 * - 2-20 входов (динамически добавляются)
 * - Выход = true если ХОТЯ БЫ ОДИН вход = true
 * - Выход = false только если ВСЕ входы = false
 */
class ConductorAtom extends Atom {

    public static inline var MIN_INPUTS:Int = 2;
    public static inline var MAX_INPUTS:Int = 20;

    private var _conductorInputCount:Int = 2;

    public function new(id:String, ?initialInputs:Int = 2) {
        _conductorInputCount = Std.int(Math.max(MIN_INPUTS, Math.min(initialInputs, MAX_INPUTS)));

        var inputs:Array<Contact> = [];
        for (i in 0..._conductorInputCount) {
            inputs.push(new Contact(false, INPUT, "in" + i));
        }

        var outputs:Array<Contact> = [
            new Contact(false, OUTPUT, "out")
        ];

        super(inputs, outputs, null, id, "Conductor");
    }

    override public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;
        _isScheduled = true;
        SignalQueue.getInstance().schedule(_calculate, NORMAL);
    }

    override private function _calculate():Void {
        _isScheduled = false;

        if (_isDisposed || _inputs == null || _outputs == null) return;
        if (_outputs.length < 1) return;

        // OR: true if ANY input is true
        var result:Bool = false;

        for (input in _inputs) {
            if (input != null && input.value == true) {
                result = true;
                break;
            }
        }

        _outputs[0].value = result;
    }

    /**
     * Add new input port.
     */
    public function addInput():String {
        if (_inputs.length >= MAX_INPUTS) {
            trace('ConductorAtom: Max inputs ($MAX_INPUTS) reached');
            return null;
        }

        var newName = "in" + _inputs.length;
        var newContact = new Contact(false, INPUT, newName);
        newContact.owner = this;
        _inputs.push(newContact);
        _conductorInputCount = _inputs.length;

        while (_inputCache.length < _inputs.length) {
            _inputCache.push(null);
        }

        _calculate();

        trace('ConductorAtom: Added $newName (total: $_conductorInputCount)');
        return newName;
    }

    /**
     * Remove last input port.
     */
    public function removeLastInput():Bool {
        if (_inputs.length <= MIN_INPUTS) {
            trace('ConductorAtom: Min inputs ($MIN_INPUTS) reached');
            return false;
        }

        var removed = _inputs.pop();
        if (removed != null) {
            removed.dispose();
        }

        _conductorInputCount = _inputs.length;
        _calculate();

        trace('ConductorAtom: Removed input (total: $_conductorInputCount)');
        return true;
    }

    public function getInputCount():Int {
        return _inputs != null ? _inputs.length : 0;
    }

    override public function getPersistentState():Dynamic {
        return { inputCount: _conductorInputCount };
    }

    override public function restoreState(state:Dynamic):Void {
        if (state == null || state.inputCount == null) return;

        var targetCount = Std.int(Math.max(MIN_INPUTS, Math.min(state.inputCount, MAX_INPUTS)));

        while (_inputs.length < targetCount) {
            var newName = "in" + _inputs.length;
            var newContact = new Contact(false, INPUT, newName);
            newContact.owner = this;
            _inputs.push(newContact);
        }
        while (_inputs.length > targetCount) {
            var removed = _inputs.pop();
            if (removed != null) removed.dispose();
        }

        _conductorInputCount = _inputs.length;

        while (_inputCache.length < _inputs.length) {
            _inputCache.push(null);
        }
    }
}