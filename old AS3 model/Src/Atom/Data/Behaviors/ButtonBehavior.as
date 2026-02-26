package Src.Atom.Data.Behaviors {
    import Src.Atom.Core.Atom;

    public class ButtonBehavior extends BaseBehavior {
        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            if (interactionType == "press") {
                var newAtom:Atom = atom;
                newAtom = newAtom.setContactValue("output", true, false);
                return newAtom;
            }
            return atom;
        }

        override public function onRelease(atom:Atom):Atom {
            var newAtom:Atom = atom;
            newAtom = newAtom.setContactValue("output", false, false);
            return newAtom;
        }

        override public function initialize(atom:Atom):Atom {
            var newAtom:Atom = atom
                .setContactValue("output", false, false);
            return newAtom;
        }

        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            return atom;
        }
    }
}
