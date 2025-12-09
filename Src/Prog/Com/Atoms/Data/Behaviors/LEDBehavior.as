package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.Managers.AtomManager;

    public class LEDBehavior extends BaseBehavior {
        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            var isOn:Boolean = (value === true);
            var newAtom:Atom = atom.setData("isOn", isOn);
            AtomManager.getInstance().updateAtom(newAtom);
            return newAtom;
        }

        override public function initialize(atom:Atom):Atom {
            var newAtom:Atom = atom
                .setContactValue("input", false, true)
                .setData("isOn", false);
            return newAtom;
        }

        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            return atom;
        }
    }
}
