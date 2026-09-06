package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;
import core.types.ContactType.*;

/**
 * PASS-THROUGH ATOM v1.4 (Link-Based + Active Timer)
 * 
 * Instantly translates a value from the input to the output via link().
 * Generates a changed impulse (50 ms) via subscribe + an update timer.
 * 
 * ──────────────────────────────────────────────────────┐
 * │  in ──[LINK]──► out                                  │
 * │   │                                                  │
 * │   └──► changed (bool pulse, 50ms via update timer)   │
 * └──────────────────────────────────────────────────────┘
 */
class PassThroughAtom extends Atom
{
    /** The duration of the changed impulse in seconds */
    private static inline var PULSE_DURATION:Float = 0.05;
    
    /** A countdown timer for resetting changed */
    private var _changedTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [new Contact(null, INPUT, "in")],
            [
                new Contact(null, OUTPUT, "out"),
                new Contact(false, OUTPUT, "changed")
            ],
            null,
            id,
            "PassThrough",
            false
        );
        
        var input = getInput("in");
        var output = getOutput("out");
        var changed = getOutput("changed");
        
        if (input != null && output != null)
        {
            // A direct value broadcast (no _calculate, no recursion)
            input.link(output);
            
            // Subscribing to changes to generate the changed impulse
			input.subscribe(function(v:Dynamic) {
				if (changed != null && changed.value == false)
				{
					changed.value = true;
					// A reset after 3 frames (~50 ms at 60 FPS)
					TickGenerator.getInstance().scheduleNextTick(function() {
						TickGenerator.getInstance().scheduleNextTick(function() {
							TickGenerator.getInstance().scheduleNextTick(function() {
								if (changed != null) changed.value = false;
							});
						});
					});
				}
			});
            
            input.ignoreOscillation = true;
        }
    }
    
    /**
     * Called by DriverManager every frame (isActive = true).
     * The only task is to reset changed when the timer expires.
     */
    override public function update(dt:Float):Void
    {
        super.update(dt);
        
        if (_changedTimer > 0)
        {
            _changedTimer -= dt;
            if (_changedTimer <= 0)
            {
                var changed = getOutput("changed");
                if (changed != null) changed.value = false;
            }
        }
    }
}