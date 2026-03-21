package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TOGGLE ATOM v1.3 (Reset Immunity)
 * Переключатель с защитой от мгновенного сброса (Race Condition Protection).
 *
 * v1.3 Changes:
 * - Added "Reset Immunity" period (default 2 seconds).
 * - Prevents Reset signal from affecting the toggle immediately after user interaction.
 * - Allows user to see the state change before feedback logic kicks in.
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ToggleAtom (Databank)                                                 │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   onContactChanged("rst") → reset to false                              │
 * │   toggle() → flip state                                                 │
 * │   setState(v) → set state directly                                      │
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
 * v1.2 Changes:
 * - Added "rst" input (Reset)
 * - When rst = true, toggle resets to OFF state
 * - State persists across saves
 */
class ToggleAtom extends Atom {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    /**
     * Time in seconds during which Reset is ignored after a manual toggle.
     * Default: 0.01 seconds (as requested).
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

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================

    /**
     * Called when any contact value changes.
     * Handles reset signal with Immunity check.
     */
    override public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;

        // Check reset input
        if (_inputs != null && _inputs.length > 0) {
            var rstValue = _inputs[0].value;
            
            if (rstValue == true) {
                // === RESET IMMUNITY LOGIC ===
                var now = haxe.Timer.stamp();
                var elapsed = now - _lastToggleTime;

                if (elapsed < resetImmunityTime) {
                    // Immunity active: Ignore the reset signal
                    // trace('ToggleAtom: Reset ignored (Immunity ${Std.int(elapsed*1000)}ms < ${Std.int(resetImmunityTime*1000)}ms)');
                    return;
                }
                // =============================

                // Reset to OFF
                if (_outputs != null && _outputs.length > 0) {
                    _outputs[0].value = false;
                }
                return;  // Don't schedule calculation
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
     * Set state directly.
     * Updates the immunity timestamp.
     */
    public function setState(value:Bool):Void {
        if (_outputs != null && _outputs.length > 0) {
            // Record the time of manual interaction
            _lastToggleTime = haxe.Timer.stamp();
            
            // Set value
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