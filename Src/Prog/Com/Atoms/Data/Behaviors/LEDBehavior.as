package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.Managers.AtomManager;

    public class LEDBehavior extends BaseBehavior {
        override public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            trace("=== LED INPUT CHANGE ===");
            trace("LED " + atom.id + " received value: " + value + " from pin: " + pinName);

            var isOn:Boolean = (value === true);
            var newAtom:Atom = atom.setData("isOn", isOn);

            trace("LED data updated - isOn: " + newAtom.data.isOn);
            AtomManager.getInstance().updateAtom(newAtom);
            return newAtom;
        }
    }
}