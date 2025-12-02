package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;

    public class ButtonBehavior extends BaseBehavior {
        
        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            if (interactionType == "press") {
                trace("🚀🚀🚀 === BUTTON PRESSED === 🚀🚀🚀");
                trace("Sending TRUE to both output systems");
                
                var newAtom:Atom = atom;
                
                // 1. Отправляем в Pin-систему (старая) - создаст Track
                trace("📤 Sending to Pin system: output_pin = true");
                newAtom = newAtom.setPinValue("output_pin", true, false);
                
                // 2. Отправляем в Contact-систему (новая) - создаст Link
                trace("📤 Sending to Contact system: output_contact = true");
                newAtom = newAtom.setContactValue("output_contact", true, false);
                
                trace("✅ Both systems notified");
                trace("🚀🚀🚀 === BUTTON PRESS COMPLETE === 🚀🚀🚀");
                return newAtom;
            }
            return atom;
        }
        
        override public function onRelease(atom:Atom):Atom {
            trace("🔽🔽🔽 === BUTTON RELEASED === 🔽🔽🔽");
            trace("Sending FALSE to both output systems");
            
            var newAtom:Atom = atom;
            
            // 1. Отправляем в Pin-систему
            trace("📤 Sending to Pin system: output_pin = false");
            newAtom = newAtom.setPinValue("output_pin", false, false);
            
            // 2. Отправляем в Contact-систему
            trace("📤 Sending to Contact system: output_contact = false");
            newAtom = newAtom.setContactValue("output_contact", false, false);
            
            trace("✅ Both systems notified");
            trace("🔽🔽🔽 === BUTTON RELEASE COMPLETE === 🔽🔽🔽");
            return newAtom;
        }
        
        override public function initialize(atom:Atom):Atom {
            trace("=== BUTTON INITIALIZING ===");
            trace("Initializing Button with dual outputs");
            
            var newAtom:Atom = atom
                .setPinValue("output_pin", false, false)
                .setContactValue("output_contact", false, false);
                
            trace("✅ Button initialized:");
            trace("   - output_pin = false");
            trace("   - output_contact = false");
            
            trace("=== BUTTON INITIALIZATION COMPLETE ===");
            return newAtom;
        }
        
        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            trace("⚠️ Button received input change (should not happen): " + pinName + " = " + value);
            return atom;
        }
    }
}