package core.base;

import haxe.Timer;
import core.base.Atom;
import core.base.Contact;
import core.logic.SignalQueue;

/**
 * HEAVY ATOM v1.1
 * Atom with Load Shedding support.
 * FIXED: Timer cancellation on dispose.
 */
class HeavyAtom extends Atom {

    private var _delayedTimer:Timer;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Heavy"
    ) {
        super(inputs, outputs, processFunc, id, type);
    }

    override function onContactChanged(c:Contact):Void {
        if (SignalQueue.getInstance().isOverloaded()) {
            if (_isScheduled) return;
            _isScheduled = true;

            // FIX: Save timer to variable
            _delayedTimer = Timer.delay(() -> {
                _isScheduled = false;
                _delayedTimer = null;
                if (!_isDisposed) _calculate(); // Check before execution
            }, 1);

            return;
        }

        super.onContactChanged(c);
    }

    // FIX: Override dispose
    override public function dispose():Void {
        if (_delayedTimer != null) {
            _delayedTimer.stop();
            _delayedTimer = null;
        }
        super.dispose();
    }
}