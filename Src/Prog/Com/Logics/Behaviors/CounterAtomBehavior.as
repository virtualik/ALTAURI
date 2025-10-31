package Src.Prog.Com.Logics.Behaviors {
    import Src.Prog.Com.Logics.IAtomBehavior;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;

    /**
     * Implements the behavior for a Counter atom.
     * Responds to a 'true' value on its input pin by incrementing an internal counter
     * and updating its output pin with the new value.
     */
    public class CounterAtomBehavior implements IAtomBehavior {
        /**
         * @inheritDoc
         * Initializes the counter atom by setting its output pin value to 0.
         */
        public function initializeAtom(atom:BaseAtom):BaseAtom {
            if (atom.outputContacts.length > 0) {
                var outPin:Pin = atom.outputContacts[0];
                return atom.setOutputPinValue(outPin.name, 0);
            }
            return atom;
        }

        /**
         * @inheritDoc
         * Handles changes to an input pin. The counter increments its value
         * only when the input pin receives a 'true' value.
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Counter triggers only on 'true'
            if (changedPin.value === true) {
                var currentValue:int = 0;
                if (atom.outputContacts.length > 0) {
                    var currentOutputPin:Pin = atom.outputContacts[0];
                    if (currentOutputPin.value !== null && currentOutputPin.value !== undefined) {
                        currentValue = int(currentOutputPin.value);
                    }
                }
                var newCounterValue:int = currentValue + 1;
                if (atom.outputContacts.length > 0) {
                    var outPin:Pin = atom.outputContacts[0];
                    return atom.setOutputPinValue(outPin.name, newCounterValue);
                }
            }
            return atom;
        }
    }
}
