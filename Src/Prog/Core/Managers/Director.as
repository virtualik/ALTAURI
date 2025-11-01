package Src.Prog.Core.Managers {
    import flash.events.Event;
    
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Com.Atoms.Core.TrackManager;

    /**
     * Director - main initialization pipeline manager for data-driven architecture
     * Coordinates application startup sequence using command pattern
     * 
     * @class Director
     * @public
     */
    public class Director {
        private static var _initSequence:SerialCommand;

        /**
         * Starts the main initialization pipeline.
         */
        public static function Start():void {
            trace("Director: Starting initialization pipeline for data-driven architecture");

            _initSequence = new SerialCommand(0,
                new InvokeFunction(initializeCoreSystems),
                new InvokeFunction(initializeMultiPulsator),
                new InvokeFunction(WindowsManager.createWindows),
                new InvokeFunction(initializeAtomSystem),
                new InvokeFunction(initializeTrackSystem),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        /**
         * Initializes core systems.
         * 
         * @private
         */
        private static function initializeCoreSystems():void {
            trace("Director: Initializing core systems");
            
            // Initialize DataManager if needed
            // DataManager is static and doesn't require explicit initialization
            
            MultiPulsator.emit(new Impulse("CORE_SYSTEMS_INITIALIZED"));
        }

        /**
         * Initializes MultiPulsator communication system.
         * 
         * @private
         */
        private static function initializeMultiPulsator():void {
            trace("Director: Initializing MultiPulsator");
            
            // MultiPulsator is static and self-initializing
            // Just verify it's working by emitting a test impulse
            MultiPulsator.emit(new Impulse("SYSTEM_READY", {
                message: "MultiPulsator initialized successfully"
            }));
        }

        /**
         * Initializes the atom system with data-driven architecture.
         * 
         * @private
         */
        private static function initializeAtomSystem():void {
            trace("Director: Initializing data-driven atom system");

            try {
                // Initialize AtomManager (creates singleton instance)
                var atomManager:AtomManager = AtomManager.getInstance();
                trace("AtomManager initialized with supported types: " + atomManager.getSupportedAtomTypes().join(", "));
                
                // AtomFactory is static and doesn't require explicit initialization
                // AtomDefinitions are loaded statically
                
                MultiPulsator.emit(new Impulse("ATOM_SYSTEM_INITIALIZED", {
                    supportedTypes: atomManager.getSupportedAtomTypes()
                }));
                
            } catch (error:Error) {
                trace("Error initializing atom system: " + error.message);
                MultiPulsator.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Atom system initialization failed: " + error.message
                }));
            }
        }

        /**
         * Initializes the track management system.
         * 
         * @private
         */
        private static function initializeTrackSystem():void {
            trace("Director: Initializing track system");
            
            try {
                // Initialize TrackManager
                TrackManager.initialize();
                trace("TrackManager initialized");
                
                MultiPulsator.emit(new Impulse("TRACK_SYSTEM_INITIALIZED"));
                
            } catch (error:Error) {
                trace("Error initializing track system: " + error.message);
                MultiPulsator.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Track system initialization failed: " + error.message
                }));
            }
        }

        /**
         * Final initialization procedure.
         * 
         * @private
         */
        private static function finalizeInitialization():void {
            trace("Director: Finalizing initialization");
            
            MultiPulsator.emit(new Impulse("APP_READY", {
                architecture: "data-driven",
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Pipeline completion handler.
         * 
         * @private
         * @param {Event} event - Completion event
         */
        private static function onInitSequenceComplete(event:Event):void {
            trace("Director: Data-driven initialization complete");
            
            MultiPulsator.emit(new Impulse("APP_STARTUP_COMPLETE", {
                message: "Data-driven architecture ready",
                atomTypes: AtomManager.getInstance().getSupportedAtomTypes()
            }));

            // Clean up
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Pipeline error handler.
         * 
         * @private
         * @param {CommandErrorEvent} event - Error event
         */
        private static function onInitSequenceError(event:CommandErrorEvent):void {
            trace("Director: Initialization error: " + event.errorMessage);
            
            MultiPulsator.emit(new Impulse("APP_STARTUP_FAILED", {
                error: event.errorMessage
            }));

            // Clean up
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Force initialization abort.
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
