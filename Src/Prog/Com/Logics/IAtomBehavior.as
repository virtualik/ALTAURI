package Src.Prog.Com.Logics {
	import Src.Prog.Com.Atoms.Core.BaseAtom;
	import Src.Prog.Com.Atoms.Core.Pin;


    /**
     * Interface defining the contract for an atom's behavior.
     * Specifies the lifecycle methods for atom initialization and
     * reaction to input pin changes. Used in an immutable architecture,
     * meaning implementations must return a *new* BaseAtom instance.
     */
    public interface IAtomBehavior {
        /**
         * Initializes the atom after its creation.
         * @param atom The newly created atom instance.
         * @return A new BaseAtom instance representing the initialized state.
         */
        function initializeAtom(atom:BaseAtom):BaseAtom;

        /**
         * Called when an input pin's value changes.
         * @param atom The current (new) atom instance.
         * @param changedPin The input pin that changed.
         * @return A new BaseAtom instance with updated outputs, or the same atom if no changes are needed.
         */
        function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom;
    }
}
