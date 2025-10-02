package Application.Managers {
    import flash.utils.Dictionary;
    import Application.Managers.DataManager;
    import Application.AtomLinker.Core.BaseAtom;
    import Application.Commands.ICommand;
    import Application.Commands.AtomLinker.InitAtomManager;
    import Application.AtomLinker.View.IAtomView;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Atom Manager - centralized atom management for application
     * Handles atom storage, retrieval, and updates
     */
    public class AtomManager {
        public static const DATA_MANAGER_KEY:String = "AtomManager";
        private var _atoms:Dictionary;

        /**
         * Constructor - initializes atom storage
         */
        public function AtomManager() {
            _atoms = new Dictionary();

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomManager",
                message: "Atom manager initialized"
            }));
        }

        /**
         * Add atom to manager
         */
        public function addAtom(atom:BaseAtom):void {
            _atoms[atom.id] = atom;

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomManager",
                message: "Atom added: " + atom.name + " (" + atom.id + ")"
            }));
        }

        /**
         * Update atom in manager
         */
        public function updateAtom(atom:BaseAtom):void {
            if (_atoms[atom.id]) {
                var oldAtom:BaseAtom = _atoms[atom.id];

                // Preserve displayObject from old atom if new one doesn't have it
                if (oldAtom.displayObject && !atom.displayObject) {
                    atom.displayObject = oldAtom.displayObject;
                }

                // Update visual component
                if (atom.displayObject && atom.displayObject is IAtomView) {
                    var atomView:IAtomView = atom.displayObject as IAtomView;
                    atomView.initWithAtom(atom);
                    atomView.updateVisuals();
                }

                _atoms[atom.id] = atom;

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "INFO",
                    source: "AtomManager",
                    message: "Atom updated: " + atom.id
                }));
            } else {
                // If atom with this ID didn't exist, add it as new
                addAtom(atom);
            }
        }

        /**
         * Get atom by identifier
         */
        public function getAtom(id:String):BaseAtom {
            return _atoms[id];
        }

        /**
         * Get all atoms
         */
        public function getAllAtoms():Dictionary {
            return _atoms;
        }

        /**
         * Static method for convenient manager access
         */
        public static function getInstance():AtomManager {
            return DataManager.getData(DATA_MANAGER_KEY) as AtomManager;
        }

        /**
         * Factory method for creating initialization command
         */
        public static function Run():ICommand {
            return new InitAtomManager();
        }
    }
}
