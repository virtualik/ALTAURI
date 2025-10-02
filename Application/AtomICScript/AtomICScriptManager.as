package Application.AtomICScript {
    import Application.AtomLinker.Core.BaseAtom;
    import Application.AtomLinker.Core.Pin;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import flash.utils.Dictionary;

    /**
     * AtomICScript Manager - behavior management for atoms
     * Stores and provides IAtomBehavior by atom type
     * Integrates with AtomFactory and ConnectionManager
     */
    public class AtomICScriptManager {
        private static var _instance:AtomICScriptManager;
        private var _behaviors:Dictionary;

        /**
         * AtomICScript Manager constructor
         */
        public function AtomICScriptManager() {
            _behaviors = new Dictionary();
        }

        /**
         * Get singleton instance
         * @return AtomICScriptManager - singleton instance
         */
        public static function getInstance():AtomICScriptManager {
            if (!_instance) {
                _instance = new AtomICScriptManager();
            }
            return _instance;
        }

        /**
         * Register behavior for atom type
         * @param atomType - atom type (e.g., "Counter")
         * @param behavior - behavior instance
         */
        public function registerBehavior(atomType:String, behavior:IAtomBehavior):void {
            _behaviors[atomType] = behavior;
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "AtomICScriptManager: [INFO] Registered behavior for: " + atomType
            }));
        }

        /**
         * Get behavior by atom type
         * @param atomType - atom type
         * @return IAtomBehavior - behavior or null if not found
         */
        public function getBehavior(atomType:String):IAtomBehavior {
            return _behaviors[atomType];
        }

        /**
         * Invoke behavior for atom on pin change
         * @param atom - atom whose pin changed
         * @param changedPin - changed pin
         * @return BaseAtom - new atom version or original if behavior not applicable
         */
        public function handlePinChange(atom:BaseAtom, changedPin:Pin):BaseAtom {
            if (changedPin.type != Pin.TYPE_INPUT) {
                return atom; // Only inputs trigger behavior
            }
            var behavior:IAtomBehavior = getBehavior(atom.type);
            if (behavior) {
                return behavior.onInputPinChanged(atom, changedPin);
            }
            return atom;
        }
    }
}
