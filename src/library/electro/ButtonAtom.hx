package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.SignalQueue;

/**
 * BUTTON ATOM v1.2 (Tick Synchronized)
 * Кнопка с двумя состояниями (нажата/отпущена).
 * 
 * * v1.2 Changes:
 * - Uses scheduleNextTick() to sync output changes with the simulation tick.
 * - Prevents race conditions within the same frame.
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
        setState(!_state);
    }

    /**
     * Set button state directly.
     * v1.2: Schedules the output update for the next tick.
     */
    public function setState(value:Bool):Void {
        _state = value;
        
        // ИСПРАВЛЕНИЕ: Планируем изменение на следующий такт.
        // Это делает входной сигнал стабильным для логики внутри текущего кадра.
        SignalQueue.getInstance().scheduleNextTick(function() {
            if (_outputs != null && _outputs.length > 0) {
                _outputs[0].value = _state;
            }
        });
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
            // Restore the output contact value immediately on load
            if (_outputs != null && _outputs.length > 0) {
                _outputs[0].value = _state;
            }
        }
    }
}