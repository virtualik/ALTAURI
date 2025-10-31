package Src.Prog.Core.Managers {
    import flash.events.Event;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Com.Atoms.Core.AtomFactory;

    /**
     * Director - main initialization pipeline manager
     * Coordinates application startup sequence using command pattern
     */
    public class Director {
        private static var _initSequence:SerialCommand;

        /**
         * Start main initialization pipeline
         */
        public static function Start():void {
            trace("Director: Starting initialization pipeline");
            
            _initSequence = new SerialCommand(0,
                new InvokeFunction(initializeCoreSystems),
                new InvokeFunction(WindowsManager.createWindows),
                new InvokeFunction(initializeAtomSystem),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        /**
         * Initialize core systems
         */
        private static function initializeCoreSystems():void {
            trace("Director: Initializing core systems");
            MultiPulsator.emit(new Impulse("CORE_SYSTEMS_INITIALIZED"));
        }

        /**
         * Initialize atom system
         */
        private static function initializeAtomSystem():void {
            trace("Director: Initializing atom system");
            
            // Initialize AtomFactory
            try {
                AtomFactory.initialize();
                trace("AtomFactory initialized");
            } catch (error:Error) {
                trace("Error initializing AtomFactory: " + error.message);
            }
            
            // Initialize AtomManager
            try {
                AtomManager.getInstance();
                trace("AtomManager initialized");
            } catch (error:Error) {
                trace("Error initializing AtomManager: " + error.message);
            }

            MultiPulsator.emit(new Impulse("ATOM_SYSTEM_INITIALIZED"));
        }

        /**
         * Final initialization procedure
         */
        private static function finalizeInitialization():void {
            trace("Director: Finalizing initialization");
            MultiPulsator.emit(new Impulse("APP_READY"));
        }

        /**
         * Pipeline completion handler
         */
        private static function onInitSequenceComplete(event:Event):void {
            trace("Director: Initialization complete");
            MultiPulsator.emit(new Impulse("APP_STARTUP_COMPLETE"));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Pipeline error handler
         */
        private static function onInitSequenceError(event:CommandErrorEvent):void {
            trace("Director: Initialization error: " + event.errorMessage);
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Force initialization abort
         */
        public static function abortInitialization():void {
            trace("Director: Aborting initialization");
            if (_initSequence) {
                _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
                _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
                _initSequence = null;
            }
        }
    }
}
