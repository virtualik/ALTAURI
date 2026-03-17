package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * BUTTON ATOM v1.1 (State Serialization)
 * Кнопка с двумя состояниями (нажата/отпущена).
 * 
 * v1.1 Changes:
 * - Added getPersistentState() for saving button state
 * - Added restoreState() for restoring button state on load
 */
class ButtonAtom extends Atom {

    private var _state:Bool = false;

    public function new(id:String) {
        super(
            [],
            [new Contact(false, OUTPUT, "out")],
            null,
            id,
            "Button"
        );
    }

    /**
     * Toggle button state (for external control).
     */
    public function toggle():Void {
        _state = !_state;
        _outputs[0].value = _state;
    }

    /**
     * Set button state directly.
     */
    public function setState(value:Bool):Void {
        _state = value;
        _outputs[0].value = _state;
    }

    /**
     * Get current button state.
     */
    public function getState():Bool {
        return _state;
    }

    // =========================================================================
    // STATE SERIALIZATION v1.1
    // =========================================================================

    /**
     * Save button state for persistence.
     * Returns the current toggle state so it can be restored on load.
     */
    override public function getPersistentState():Dynamic {
        return { 
            state: _state 
        };
    }

    /**
     * Restore button state from saved data.
     * Called when loading a project to restore the button's toggle state.
     */
    override public function restoreState(state:Dynamic):Void {
        if (state != null && state.state != null) {
            _state = state.state;
            // Restore the output contact value
            if (_outputs != null && _outputs.length > 0) {
                _outputs[0].value = _state;
            }
        }
    }
}
