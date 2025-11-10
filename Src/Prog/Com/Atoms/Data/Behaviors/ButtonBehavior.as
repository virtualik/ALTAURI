package Src.Prog.Com.Atoms.Data.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;

    public class ButtonBehavior extends BaseBehavior {
        override public function onInteraction(atom:Atom, interactionType:String):Atom {
            if (interactionType == "press") {
                trace("Button pressed - sending TRUE signal");
                return atom.setPinValue("output", true, false);
            }
            return atom;
        }
        
        override public function onRelease(atom:Atom):Atom {
            trace("Button released - sending FALSE signal");
            return atom.setPinValue("output", false, false);
        }
    }
}