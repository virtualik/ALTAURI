package Src.Atom.Data.Behaviors {
    import Src.Atom.Core.Atom;

    public class BaseBehavior {
        public function onInteraction(atom:Atom, interactionType:String):Atom {
            return atom;
        }

        public function onRelease(atom:Atom):Atom {
            return atom;
        }

        public function onInputChange(atom:Atom, pinName:String, value:*):Atom {
            return atom;
        }

        public function initialize(atom:Atom):Atom {
            return atom;
        }
    }
}
