package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.Managers.AtomManager;

    public class LEDBehavior extends BaseBehavior {

        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            trace("🔥🔥🔥 === LED INPUT DETECTED ===");
            trace("🔥 Source: " + pinName + ", Value: " + value);
            trace("🔥 Atom: " + atom.name + " (" + atom.id + ")");

            // 🔥 ИСПРАВЛЕНО: Используем "input" вместо "input_pin"/"input_contact"
            var signalSource:String = "Contact system";
            
            var isOn:Boolean = (value === true);
            trace("💡 LED should be: " + (isOn ? "ON 💚" : "OFF 🖤"));

            var newAtom:Atom = atom.setData("isOn", isOn);
            trace("📊 Data updated: isOn = " + newAtom.data.isOn);

            // Обновляем атом через менеджер
            AtomManager.getInstance().updateAtom(newAtom);
            trace("✅ AtomManager.updateAtom called");

            trace("🔥🔥🔥 === LED UPDATE COMPLETE ===");
            return newAtom;
        }

        override public function initialize(atom:Atom):Atom {
            trace("=== LED INITIALIZING ===");
            trace("Initializing LED with single contact system");

            // 🔥 ИСПРАВЛЕНО: Используем "input" вместо "input_pin"/"input_contact"
            var newAtom:Atom = atom
                .setContactValue("input", false, true)
                .setData("isOn", false);

            trace("✅ LED initialized:");
            trace("   - input = false");
            trace("   - isOn = false");

            trace("=== LED INITIALIZATION COMPLETE ===");
            return newAtom;
        }

        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            trace("🔄 LED interaction: " + interactionType);
            return atom;
        }
    }
}