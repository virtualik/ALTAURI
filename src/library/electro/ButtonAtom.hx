package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * BUTTON ATOM v1.3 (TickGenerator Migration)
 *
 * Push button with two states (pressed/released).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ButtonAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "out" ──► setState() ──► TickGenerator.scheduleNextTick()     │
 * │                                                                         │
 * │   Widget (ButtonWidget) writes to atom's state via setState().          │
 * │   State is scheduled for next tick to prevent race conditions.          │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.3 Changes:
 * - Migrated from SignalQueue to TickGenerator
 * - Fixed getPersistentState() to merge with super result
 * - Fixed restoreState() to call super.restoreState() first
 */
class ButtonAtom extends Atom
{
    // =========================================================================
    // STATE
    // =========================================================================
    private var _state:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [],
            [new Contact(false, OUTPUT, "out")],
            null,
            id,
            "Button"
        );
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Toggle button state (for external control).
     */
    public function toggle():Void
    {
        setState(!_state);
    }

    /**
     * Set button state directly.
     *
     * Uses TickGenerator.scheduleNextTick() to schedule the output update
     * for the next tick. This keeps user input stable for all logic
     * within the current frame and prevents race conditions.
     *
     * @param value New state (true = pressed, false = released)
     */
    public function setState(value:Bool):Void
    {
        _state = value;
        TickGenerator.getInstance().scheduleNextTick(function()
        {
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = _state;
            }
        });
    }

    /**
     * Get current button state.
     */
    public function getState():Bool
    {
        return _state;
    }

    // =========================================================================
    // STATE SERIALIZATION v1.3
    // =========================================================================
    /**
     * Save button state for persistence.
     *
     * Merges with super result to preserve base class fields (isLogic).
     */
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result:Dynamic = { state: _state };
        
        if (base != null)
        {
            if (Reflect.hasField(base, "isLogic"))
            {
                Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
            }
        }
        return result;
    }

    /**
     * Restore button state from saved data.
     *
     * Calls super.restoreState() first so base class fields are restored
     * before subclass-specific logic runs. Restores contact value directly
     * (without scheduler) so initial state is available immediately on load.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        // First restore base class fields (isLogic, etc.)
        super.restoreState(state);
        
        if (state.state != null)
        {
            _state = state.state;
            // Restore contact value directly — no scheduler needed for load
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = _state;
            }
        }
    }
}