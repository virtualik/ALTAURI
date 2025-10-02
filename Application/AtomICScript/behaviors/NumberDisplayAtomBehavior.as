package Application.AtomICScript.behaviors {
    import Application.AtomICScript.IAtomBehavior;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;

    /**
     * Number Display Atom Behavior
     * Display doesn't change state - just shows input
     * Behavior does nothing, returns same atom
     */
    public class NumberDisplayAtomBehavior implements IAtomBehavior {
        /**
         * Handle input pin change
         * @param atom - current atom
         * @param changedPin - changed pin
         * @return BaseAtom - same atom (display doesn't generate outputs)
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Display doesn't generate outputs - just return atom
            return atom;
        }
    }
}
