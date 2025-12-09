package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;

    public class ButtonBehavior extends BaseBehavior {

        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            if (interactionType == "press") {
                trace("🚀🚀🚀 === BUTTON PRESSED === 🚀🚀🚀");
                trace("Sending TRUE to contact system");

                var newAtom:Atom = atom;

                // 🔥 ИСПРАВЛЕНО: Используем "output" вместо "output_pin"/"output_contact"
                trace("📤 Sending to Contact system: output = true");
                newAtom = newAtom.setContactValue("output", true, false);

                trace("✅ Contact system notified");
                trace("🚀🚀🚀 === BUTTON PRESS COMPLETE === 🚀🚀🚀");
                return newAtom;
            }
            return atom;
        }

        override public function onRelease(atom:Atom):Atom {
            trace("🔽🔽🔽 === BUTTON RELEASED === 🔽🔽🔽");
            trace("Sending FALSE to contact system");

            var newAtom:Atom = atom;

            // 🔥 ИСПРАВЛЕНО: Используем "output" вместо "output_pin"/"output_contact"
            trace("📤 Sending to Contact system: output = false");
            newAtom = newAtom.setContactValue("output", false, false);

            trace("✅ Contact system notified");
            trace("🔽🔽🔽 === BUTTON RELEASE COMPLETE === 🔽🔽🔽");
            return newAtom;
        }

        override public function initialize(atom:Atom):Atom {
            trace("=== BUTTON INITIALIZING ===");
            trace("Initializing Button with single contact system");

            var newAtom:Atom = atom
                .setContactValue("output", false, false);

            trace("✅ Button initialized:");
            trace("   - output = false");

            trace("=== BUTTON INITIALIZATION COMPLETE ===");
            return newAtom;
        }

        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            trace("⚠️ Button received input change (should not happen): " + pinName + " = " + value);
            return atom;
        }
    }
}