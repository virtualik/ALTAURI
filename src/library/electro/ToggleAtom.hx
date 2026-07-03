package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * TOGGLE ATOM v1.6 (TickGenerator Migration + Robustness Pass)
 *
 * Toggle switch with reset immunity (Race Condition Protection).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   Contact "rst" ──► onContactChanged() ──► reset to false               │
 * │   Contact "set" ──► onContactChanged() ──► set to true                  │
 * │   toggle()      ──► setState() ──► scheduleNextTick()                   │
 * │                                                                         │
 * │   Reset immunity prevents instant reset after manual toggle.            │
 * │   User interaction is scheduled for next tick for stability.            │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.6 Changes:
 * - Migrated from SignalQueue to TickGenerator
 * - onContactChanged uses getInput() by name (safer)
 * - Fixed getPersistentState() to merge with super result
 * - Fixed restoreState() to call super.restoreState() first
 * - Removed dead commented-out code
 */
class ToggleAtom extends Atom
{
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    /**
     * Time in seconds during which Reset/Set is ignored after manual toggle.
     * Default: 0.1 seconds.
     */
    public var resetImmunityTime:Float = 0.1;

    // =========================================================================
    // STATE
    // =========================================================================
    // Initialized in the past so immunity doesn't affect startup
    private var _lastToggleTime:Float = -3.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            // Two inputs: rst (Reset) and set (Set)
            [
                new Contact(false, INPUT, "rst"),
                new Contact(false, INPUT, "set")
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

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================
    /**
     * Called when any contact value changes.
     * Handles reset and set signals with immunity check.
     *
     * Uses getInput() by name instead of direct index access for safety.
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isScheduled || _isDisposed) return;
        
        var rstContact = getInput("rst");
        var setContact = getInput("set");
        
        if (rstContact == null && setContact == null)
        {
            super.onContactChanged(c);
            return;
        }
        
        var rstValue = (rstContact != null) ? rstContact.value : null;
        var setValue = (setContact != null) ? setContact.value : null;
        
        // === RESET IMMUNITY LOGIC ===
        // Ignore incoming rst/set signals within resetImmunityTime
        // after last manual toggle. Prevents instant reset in same tick
        // when user just toggled.
        var now = haxe.Timer.stamp();
        var elapsed = now - _lastToggleTime;
        if (elapsed < resetImmunityTime)
        {
            return;
        }
        // ============================
        
        // Priority: Reset > Set
        if (rstValue == true)
        {
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = false;
            }
            return;
        }
        if (setValue == true)
        {
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = true;
            }
            return;
        }
        
        super.onContactChanged(c);
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Toggle the state.
     */
    public function toggle():Void
    {
        if (_outputs != null && _outputs.length > 0)
        {
            setState(!(_outputs[0].value == true));
        }
    }

    /**
     * Set state directly (User Interaction).
     * Updates the immunity timestamp.
     *
     * Uses TickGenerator.scheduleNextTick() for stability.
     * Guarantees that rst/set signals from current tick won't overwrite
     * the state just set by user.
     */
    public function setState(value:Bool):Void
    {
        if (_outputs == null || _outputs.length == 0) return;
        
        // Record time of manual interaction for immunity mechanism
        _lastToggleTime = haxe.Timer.stamp();
        
        // Schedule for next tick to sync with logic clock
        TickGenerator.getInstance().scheduleNextTick(function()
        {
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = value;
            }
        });
    }

    /**
     * Get current state.
     */
    public function getState():Bool
    {
        if (_outputs != null && _outputs.length > 0)
        {
            return _outputs[0].value == true;
        }
        return false;
    }

    // =========================================================================
    // STATE SERIALIZATION v1.6
    // =========================================================================
    /**
     * Save toggle state for persistence.
     *
     * Merges with super result to preserve base class fields (isLogic).
     */
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var currentState = false;
        
        if (_outputs != null && _outputs.length > 0)
        {
            currentState = _outputs[0].value == true;
        }
        
        var result:Dynamic = { state: currentState };
        
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
     * Restore toggle state from saved data.
     *
     * Calls super.restoreState() first so base class fields are restored
     * before subclass-specific logic runs. Restores contact value directly
     * (no scheduler) to avoid triggering immunity timer during loading.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        // First restore base class fields (isLogic, etc.)
        super.restoreState(state);
        
        if (state.state != null)
        {
            if (_outputs != null && _outputs.length > 0)
            {
                // Restore directly without scheduler and without updating
                // _lastToggleTime — so immunity doesn't block incoming
                // signals immediately after project load.
                _outputs[0].value = state.state;
            }
        }
    }
}