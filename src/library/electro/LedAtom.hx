package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * LED ATOM v1.1 (Passive Display)
 *
 * Passive indicator atom. No processing logic.
 * View subscribes to input contact and displays state.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   LedAtom (Databank)                                                    │
 * │                                                                         │
 * │   Contact "in" ◄─── External Signal                                     │
 * │                                                                         │
 * │   Widget (LEDWidget) reads from atom's input contact.                   │
 * │   Atom is passive — no computation, just data storage.                  │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class LedAtom extends Atom 
{
    public function new(id:String) 
    {
        super(
            [new Contact(false, INPUT, "in")],
            [],   // No outputs
            null, // No process function
            id,
            "LED",
            false // Not an active driver
        );
    }
}