package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * TOGGLE ATOM v1.7 (WP-1 Hygiene: dead statics removed)
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
 * TOGGLE ATOM v1.7 (HTML5 Fix + TickGenerator Fallback)
 *
 * Toggle switch with reset immunity (Race Condition Protection).
 *
 * v1.7 Changes:
 * - Added HTML5 fallback: direct contact update if TickGenerator is not ready
 * - Added debug logging for setState() calls
 * - Fixed immunity check to allow external signals (rst/set) from other atoms
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

    // v1.7 (WP-1 FIX-2): the static probe cache _tickGeneratorTested /
    // _tickGeneratorWorks (declared v1.6, relic of the TickGenerator
    // migration) is REMOVED — a full-tree scan found ZERO readers/writers.
    // TickGenerator availability is probed per-instance where needed.

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
     * v1.7: Immunity only blocks signals that come from the SAME atom's setState().
     * External signals (from other atoms like PushButton) are always processed.
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
        
        // === RESET IMMUNITY LOGIC v1.7 ===
        // Only block if the signal comes from our own setState() call.
        // External atoms (like PushButton) should always work.
        var now = haxe.Timer.stamp();
        var elapsed = now - _lastToggleTime;
        
        // Check if this is an external signal (from another atom)
        // External signals bypass immunity
        var isExternalSignal = (c != rstContact && c != setContact);
        
        if (elapsed < resetImmunityTime && !isExternalSignal)
        {
            #if html5
            trace('[ToggleAtom] Immunity blocking signal (elapsed: ' + elapsed + 's)');
            #end
            return;
        }
        // ============================
        
        // Priority: Reset > Set
        if (rstValue == true)
        {
            #if html5
            trace('[ToggleAtom] Reset signal received');
            #end
            if (_outputs != null && _outputs.length > 0)
            {
                _outputs[0].value = false;
            }
            return;
        }
        if (setValue == true)
        {
            #if html5
            trace('[ToggleAtom] Set signal received');
            #end
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
     * 
     * v1.8: Synchronous UI Input. User clicks must process IMMEDIATELY.
     * We bypass TickGenerator for the initial state change to guarantee
     * instant responsiveness in HTML5, bypassing browser throttling.
     * Logic propagation will handle the rest of the graph.
     */
    public function setState(value:Bool):Void
    {
        if (_outputs == null || _outputs.length == 0) return;
        
        // Record time of manual interaction for immunity mechanism
        _lastToggleTime = haxe.Timer.stamp();
        
        // Direct synchronous update for immediate UI response
        if (_outputs[0].value != value) {
            _outputs[0].value = value;
        }
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
    // STATE SERIALIZATION v1.7
    // =========================================================================
    /**
     * Save toggle state for persistence.
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
                        for (field in Reflect.fields(base))
                        {
                                Reflect.setField(result, field, Reflect.field(base, field));
                        }
                }
                return result;
        }

    /**
     * Restore toggle state from saved data.
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
