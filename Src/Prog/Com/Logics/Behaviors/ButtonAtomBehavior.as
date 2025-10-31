package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Button atom.
     * A button typically has no input pins, so `onInputPinChanged` is not used.
     * The primary behavior is triggered directly by the view on click/release,
     * handled by the `setPressed` method.
     */
    public class ButtonAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the button atom by setting its output pin value to false (released state).
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, false);
            }
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. This method is not used for a button atom,
         * as buttons typically do not have input pins.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Button has no inputs - method not used
            return atom;
        }

        /**
         * Sets the pressed state of the button atom.
         * Updates the output pin value based on the pressed state.
         * @param atom The current atom instance.
         * @param isPressed True if the button is pressed, false if released.
         * @return A new BaseAtom instance with the updated output value.
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
