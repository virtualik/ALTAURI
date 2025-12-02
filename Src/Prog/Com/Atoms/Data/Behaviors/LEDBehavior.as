package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Com.Atoms.Core.Pin;
	import Src.Prog.Com.Atoms.Contact.Core.Contact;
	
    public class LEDBehavior extends BaseBehavior {
        
        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            trace("🔥🔥🔥 === LED INPUT DETECTED ===");
            trace("🔥 Source: " + pinName + ", Value: " + value);
            trace("🔥 Atom: " + atom.name + " (" + atom.id + ")");
            
            // 🔥 УПРОЩЕННАЯ ЛОГИКА - не проверяем isConnected
            var signalSource:String = "UNKNOWN";
            
            if (pinName == "input_pin") {
                // Просто определяем по имени пина
                signalSource = "PIN-based connection";
            } 
            else if (pinName == "input_contact") {
                signalSource = "CONTACT-based connection";
            }
            else {
                trace("⚠️ Unknown pin: " + pinName);
                return atom;
            }
            
            trace("📡 Signal from: " + signalSource);
            
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
            trace("Initializing LED with dual inputs");
            
            // Инициализируем оба входа как false
            var newAtom:Atom = atom
                .setPinValue("input_pin", false, true)
                .setContactValue("input_contact", false, true)
                .setData("isOn", false);
                
            trace("✅ LED initialized:");
            trace("   - input_pin = false");
            trace("   - input_contact = false");
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