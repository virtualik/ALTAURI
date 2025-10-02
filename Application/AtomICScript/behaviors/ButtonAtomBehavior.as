package Application.AtomICScript.behaviors {
    import Application.AtomICScript.IAtomBehavior;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;

    /**
     * Button Atom Behavior
     * Button has no inputs, so onInputPinChanged is not used
     * Behavior is called directly from View on click
     */
    public class ButtonAtomBehavior implements IAtomBehavior {
        /**
         * Handle input pin change (not used for button)
         * @param atom - current atom
         * @param changedPin - changed pin
         * @return BaseAtom - same atom
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Button has no inputs - method not used
            return atom;
        }

        /**
         * Specific method: set button pressed state
         * @param atom - current atom
         * @param isPressed - true for pressed, false for released
         * @return BaseAtom - new atom with updated output
         */
        public function setPressed(atom:BaseAtom, isPressed:Boolean):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, isPressed);
            }
            return atom;
        }
    }
}
