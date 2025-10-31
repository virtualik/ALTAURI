package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Number Display atom.
     * The display atom does not change its internal state or generate outputs;
     * it simply reflects the input value visually. This behavior implementation
     * does nothing and returns the atom unchanged.
     */
    public class NumberDisplayAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the number display atom. The display does not require specific initialization,
         * so it returns the atom as-is.
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            // Display doesn't need initialization - just return atom
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. The display atom does not generate outputs,
         * so it returns the atom unchanged.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Display doesn't generate outputs - just return atom
            return atom;
        }
    }
}
