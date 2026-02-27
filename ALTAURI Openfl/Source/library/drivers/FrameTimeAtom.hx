package library.drivers;

import core.base.Atom;
import core.base.Contact;

/**
 * FRAME TIME ATOM
 * Active atom measuring frame duration (Delta Time) in milliseconds.
 * Works via DriverManager.
 */
class FrameTimeAtom extends Atom {

    public function new(id:String) {
        // Call parent constructor:
        // 1. No inputs.
        // 2. One output "ms" (Float).
        // 3. No processing logic (_process = null).
        // 4. isActive = true (IMPORTANT! Registers in DriverManager).
        super(
            [],
            [new Contact(0.0, OUTPUT, "ms")],
            null,
            id,
            "FrameTime",
            true
        );
    }

    // Override update method called every frame
    override private function _onUpdate(dt:Float):Void {
        // dt comes in seconds (e.g., 0.016). We need milliseconds.
        var ms = dt * 1000;

        // Write result to output contact.
        // This triggers the signal, connected atoms receive data.
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = ms;
        }
    }
}