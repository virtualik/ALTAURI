package Application.AtomICScript.behaviors {
    import Application.AtomICScript.IAtomBehavior;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;

    /**
     * Counter Atom Behavior
     * Responds to true on input, increments counter and updates output
     */
    public class CounterAtomBehavior implements IAtomBehavior {
        /**
         * Handle input pin change
         * @param atom - current atom
         * @param changedPin - changed pin
         * @return BaseAtom - new atom with updated counter
         */
        public function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom {
            // Counter triggers only on true
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
