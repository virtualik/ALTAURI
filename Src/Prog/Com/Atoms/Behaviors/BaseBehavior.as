// Src/Prog/Com/Atoms/Behaviors/BaseBehavior.as
package Src.Prog.Com.Atoms.Behaviors {
    import Src.Prog.Com.Atoms.Core.Atom;

    public class BaseBehavior {
        public function onInteraction(atom:Atom, interactionType:String):Atom {
            return atom; // Базовая реализация - без изменений
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
