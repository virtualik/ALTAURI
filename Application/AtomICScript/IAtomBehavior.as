package Application.AtomICScript {
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;

    /**
     * IAtomBehavior interface - atom behavior contract
     * Defines atom reaction to input pin changes
     * Used in immutable architecture: returns NEW BaseAtom instance
     */
    public interface IAtomBehavior {
        /**
         * Called when input pin changes
         * @param atom - current (new) atom version
         * @param changedPin - changed input pin
         * @return BaseAtom - new atom version with updated outputs, or same atom if no changes
         */
        function onInputPinChanged(atom:BaseAtom, changedPin:Pin):BaseAtom;
    }
}
