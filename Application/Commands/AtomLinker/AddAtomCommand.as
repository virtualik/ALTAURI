package Application.Commands.AtomLinker {
    import Application.Commands.Command;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.Managers.AtomManager;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Add Atom Command - adds atom to AtomManager
     * Accepts pre-created atom and registers it in the system
     */
    public class AddAtomCommand extends Command {
        private var _atomManager:AtomManager;
        private var _atomToAdd:BaseAtom;

        /**
         * Add Atom Command constructor
         * @param atomManager - atom manager instance
         * @param atom - atom to add
         */
        public function AddAtomCommand(atomManager:AtomManager, atom:BaseAtom) {
            _atomManager = atomManager;
            _atomToAdd = atom;

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "AddAtomCommand: [DEBUG] Command created for atom: " + atom.name
            }));
        }

        /**
         * Execute command internal logic
         */
        override protected function executeInternal():void {
            _atomManager.addAtom(_atomToAdd);

            MultiPulsator.emit(new Impulse("ATOM_CREATED", {
                atom: _atomToAdd,
                id: _atomToAdd.id,
                position: _atomToAdd.position
            }));

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "AddAtomCommand: [INFO] Atom added to manager: " + _atomToAdd.name
            }));
        }

        /**
         * Get newly added atom
         * @return BaseAtom - added atom
         */
        public function get newAtom():BaseAtom {
            return _atomToAdd;
        }
    }
}
