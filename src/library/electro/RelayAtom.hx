package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * RELAY ATOM v1.4 (Correctness Pass)
 *
 * Relay — passes signal only when control is active.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   RelayAtom (Databank)                                                  │
 * │                                                                         │
 * │   Contact "signal"   ──► _calculate() ──► Contact "out"                 │
 * │   Contact "control"  ──► (gate)                                         │
 * │                                                                         │
 * │   If control == true:  out = signal                                     │
 * │   If control == false: out = null                                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.4 Changes:
 * - onContactChanged() and _calculate() use getInput() by name
 * - Fixed getPersistentState() to merge with super result
 * - Fixed restoreState() to call super.restoreState() first
 * - _calculate() reads from contacts directly (not from stale cache)
 */
class RelayAtom extends Atom
{
    // =========================================================================
    // DATABANK - Cache for Public API
    // =========================================================================
    /**
     * Last signal value. Used in getLastSignal().
     * Not the source of truth for computation — only for external API.
     */
    private var _signalValue:Dynamic = null;
    
    /**
     * Last control state. Used in isOpen().
     * Not the source of truth for computation — only for external API.
     */
    private var _controlValue:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "signal"),   // What we pass
                new Contact(false, INPUT, "control")  // Open (true) or close (false)
            ],
            [
                new Contact(null, OUTPUT, "out")
            ],
            null,
            id,
            "Relay"
        );
    }

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================
    /**
     * Update cache and pass control to base class for scheduling
     * of _calculate() call.
     *
     * Uses getInput() by name instead of direct index access.
     */
    override public function onContactChanged(c:Contact):Void
    {
        // Update cache for public API (isOpen, getLastSignal)
        var signalContact = getInput("signal");
        var controlContact = getInput("control");
        
        if (signalContact != null) _signalValue = signalContact.value;
        if (controlContact != null) _controlValue = (controlContact.value == true);
        
        // Pass control to base class — it will schedule _calculate()
        super.onContactChanged(c);
    }

    /**
     * Relay logic: pass signal if control is active.
     *
     * Reads values directly from contacts — not from cache.
     * Cache (_signalValue, _controlValue) is for external API only.
     */
    override private function _calculate():Void
    {
        // Explicitly reset flag — safety for direct calls
        _isScheduled = false;
        
        var signalContact = getInput("signal");
        var controlContact = getInput("control");
        var outContact = getOutput("out");
        
        if (signalContact == null || controlContact == null || outContact == null) return;
        
        if (controlContact.value == true)
        {
            // Control active — pass signal
            outContact.value = signalContact.value;
        }
        else
        {
            // Control inactive — close output
            outContact.value = null;
        }
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Check if relay is open (passing signal).
     */
    public function isOpen():Bool
    {
        return _controlValue;
    }

    /**
     * Get last signal value that passed through relay.
     */
    public function getLastSignal():Dynamic
    {
        return _signalValue;
    }

    // =========================================================================
    // STATE SERIALIZATION v1.4
    // =========================================================================
    /**
     * Save relay state for persistence.
     *
     * Merges with super result to preserve base class fields (isLogic).
     */
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var outContact = getOutput("out");
        var outputValue:Dynamic = (outContact != null) ? outContact.value : null;
        
        var result:Dynamic = {
            lastOutput: outputValue,
            controlState: _controlValue
        };
        
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
     * Restore relay state from saved data.
     *
     * Calls super.restoreState() first so base class fields are restored
     * before subclass-specific logic runs.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        super.restoreState(state);
        
        var outContact = getOutput("out");
        if (state.lastOutput != null && outContact != null)
        {
            outContact.value = state.lastOutput;
        }
        if (state.controlState != null)
        {
            _controlValue = state.controlState;
        }
    }
}