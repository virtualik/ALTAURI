package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TOGGLE ATOM v1.2 (Reset Input)
 * Переключатель с сохранением состояния и входом сброса.
 *
 * v1.2 Changes:
 * - Added "rst" input (Reset)
 * - When rst = true, toggle resets to OFF state
 * - State persists across saves
 */
class ToggleAtom extends Atom {

    public function new(id:String) {
        super(
            // One input: rst (Reset)
            [
                new Contact(false, INPUT, "rst")
            ],
            // One output: out (current state)
            [
                new Contact(false, OUTPUT, "out")
            ],
            null,  // No process function - manual toggle
            id,
            "Toggle"
        );
    }

    /**
     * Called when any contact value changes.
     * Handles reset signal.
     */
    override public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;

        // Check reset input
        if (_inputs != null && _inputs.length > 0) {
            var rstValue = _inputs[0].value;
            if (rstValue == true) {
                // Reset to OFF - directly set output
                if (_outputs != null && _outputs.length > 0) {
                    _outputs[0].value = false;
                }
                return;  // Don't schedule calculation
            }
        }

        super.onContactChanged(c);
    }

    /**
     * Toggle the state (called by ToggleWidget on click).
     */
    public function toggle():Void {
        if (_outputs != null && _outputs.length > 0) {
            var currentState = _outputs[0].value;
            _outputs[0].value = (currentState != true);
        }
    }

    /**
     * Set state directly.
     */
    public function setState(value:Bool):Void {
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = value;
        }
    }

    /**
     * Get current state.
     */
    public function getState():Bool {
        if (_outputs != null && _outputs.length > 0) {
            return _outputs[0].value == true;
        }
        return false;
    }

    // Save state for persistence
    override public function getPersistentState():Dynamic {
        var state = false;
        if (_outputs != null && _outputs.length > 0) {
            state = _outputs[0].value == true;
        }
        return { state: state };
    }

    // Restore state on load
    override public function restoreState(state:Dynamic):Void {
        if (state != null && state.state != null) {
            if (_outputs != null && _outputs.length > 0) {
                _outputs[0].value = state.state;
            }
        }
    }
}