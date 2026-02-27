package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * FPS MONITOR ATOM
 * Active atom measuring Frames Per Second.
 */
class FPSMonitorAtom extends Atom {

    private var _frames:Int = 0;
    private var _elapsed:Float = 0;

    public function new(id:String) {
        // Call parent constructor with isActive = true
        super(
            [],
            [new Contact(0, OUTPUT, "fps")],
            null,
            id,
            "FPSMonitor",
            true // ACTIVE!
        );
    }

    // Override Driver update method
    override private function _onUpdate(dt:Float):Void {
        _frames++;
        _elapsed += dt;

        if (_elapsed >= 0.5) {
            var fps = Math.round(_frames / _elapsed);

            // Write result to output contact
            _outputs[0].value = fps;

            _frames = 0;
            _elapsed = 0;
        }
    }
}