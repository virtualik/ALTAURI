package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.SignalQueue;

/**
* TOGGLE ATOM v1.5 (Hybrid Sync)
 * Переключатель с защитой от мгновенного сброса (Race Condition Protection).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   onContactChanged("rst") -> reset to false                             │
 * │   toggle() -> flip state                                                │
 * │   setState(v) -> set state directly                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   Contact "out" stores current state (true/false)                       │
 * │   getPersistentState() → { state: bool }                                │
 * │   restoreState() → restores contact value                               │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   ToggleWidget shows:                                                   │
 * │   - ON/OFF state                                                        │
 * │   - Click to toggle                                                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.5 Changes:
 * - setState (user interaction) now uses scheduleNextTick() for stability.
 * - Logic inputs (rst/set) remain reactive to work within tick propagation.
 */
class ToggleAtom extends Atom {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    /**
     * Time in seconds during which Reset/Set is ignored after a manual toggle.
     * Default: 0.01 seconds.
     */
    public var resetImmunityTime:Float = 0.01;

    // =========================================================================
    // STATE
    // =========================================================================

    private var _lastToggleTime:Float = -3.0; // Initialize in the past

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(id:String) {
        super(
            // Two inputs: rst (Reset) and set (Set)
            [
                new Contact(false, INPUT, "rst"), // Index 0
                new Contact(false, INPUT, "set")  // Index 1
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
     * Handles reset and set signals with Immunity check.
     */
    override public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;

        // Check inputs
        if (_inputs != null && _inputs.length > 1) {
            var rstValue = _inputs[0].value;
            var setValue = _inputs[1].value;

            // === RESET IMMUNITY LOGIC ===
            var now = haxe.Timer.stamp();
            var elapsed = now - _lastToggleTime;

            if (elapsed < resetImmunityTime) {
                // Immunity active: Ignore the reset/set signals
                return;
            }
            // =============================

            // Priority: Reset > Set
            if (rstValue == true) {
                // Reset to OFF
                if (_outputs != null && _outputs.length > 0) {
                    _outputs[0].value = false;
                }
                return;
            }

            if (setValue == true) {
                // Set to ON
                if (_outputs != null && _outputs.length > 0) {
                    _outputs[0].value = true;
                }
                return;
            }
        }

        super.onContactChanged(c);
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================

    /**
     * Toggle the state.
     */
    public function toggle():Void {
        if (_outputs != null && _outputs.length > 0) {
            var currentState = _outputs[0].value;
            setState(!(currentState == true));
        }
    }

    /**
     * Set state directly (User Interaction).
     * Updates the immunity timestamp.
     * v1.5: Uses scheduleNextTick for stability.
     */
    public function setState(value:Bool):Void {
        if (_outputs != null && _outputs.length > 0) {
            // Record the time of manual interaction
            _lastToggleTime = haxe.Timer.stamp();

            // Set value
            // _outputs[0].value = value; // Old way (immediate)
            
            // v1.5 HYBRID: Schedule for next tick to sync with logic clock
            SignalQueue.getInstance().scheduleNextTick(function() {
                if (_outputs != null && _outputs.length > 0) {
                    _outputs[0].value = value;
                }
            });
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

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================

    override public function getPersistentState():Dynamic {
        var state = false;
        if (_outputs != null && _outputs.length > 0) {
            state = _outputs[0].value == true;
        }
        return { state: state };
    }

    override public function restoreState(state:Dynamic):Void {
        if (state != null && state.state != null) {
            if (_outputs != null && _outputs.length > 0) {
                // Restore state silently to avoid triggering immunity timer
                _outputs[0].value = state.state;
            }
        }
    }
}