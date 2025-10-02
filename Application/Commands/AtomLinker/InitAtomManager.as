package Application.Commands.AtomLinker {
    import Application.Commands.Command;
    import Application.Managers.DataManager;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.AtomManager;
    import Application.AtomLinker.Services.AtomFactory;

    /**
     * Init Atom Manager Command - initializes atom management system
     * Creates AtomManager instance and initializes AtomFactory
     */
    public class InitAtomManager extends Command {
        private var _atomManager:AtomManager;

        /**
         * Init Atom Manager constructor
         */
        public function InitAtomManager() {
            super();
        }

        /**
         * Execute command internal logic
         */
        override protected function executeInternal():void {
            try {
                _atomManager = new AtomManager();
                DataManager.registerData(AtomManager.DATA_MANAGER_KEY, _atomManager);
                AtomFactory.initialize();

                var checkManager:AtomManager = AtomManager.getInstance();
                if (checkManager) {
                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        message: "InitAtomManager: [INFO] Atom manager successfully created and registered."
                    }));
                }

                complete();

            } catch (error:Error) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "InitAtomManager: [ERROR] Critical error: " + error.message
                }));
                throw error;
            }
        }

        /**
         * Get atom manager instance
         * @return AtomManager - atom manager
         */
        public function get atomManager():AtomManager {
            return _atomManager;
        }
    }
}
