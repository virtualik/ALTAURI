package Src.Prog.Core.Managers {
    import flash.events.Event;
    
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Com.Atoms.Core.TrackManager;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;

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
        public static function Run():void {
            trace("Director: Starting initialization pipeline for data-driven architecture");

            _initSequence = new SerialCommand(0,
				new InvokeFunction(initializeCoreSystems),
				new InvokeFunction(initializeImpulsys),
				new InvokeFunction(WindowsManager.createWindows),
				new InvokeFunction(initializeAtomSystem),  // AtomDefinitions должны быть здесь
				new InvokeFunction(initializeMenuSystem),  // MenuManager зависит от атомов
				new InvokeFunction(initializeTrackSystem), // TrackManager зависит от атомов
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
            
            Impulsys.emit(new Impulse("CORE_SYSTEMS_INITIALIZED"));
        }

        /**
         * Initializes Impulsys communication system.
         * 
         * @private
         */
        private static function initializeImpulsys():void {
            trace("Director: Initializing Impulsys");
            
            // Impulsys is static and self-initializing
            // Just verify it's working by emitting a test impulse
            Impulsys.emit(new Impulse("SYSTEM_READY", {
                message: "Impulsys initialized successfully"
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
				// ИНИЦИАЛИЗИРУЕМ AtomDefinitions ПЕРЕД ИХ ИСПОЛЬЗОВАНИЕМ
				AtomDefinitions.initialize();
				AtomDefinitions.validateDefinitions(); // Опционально: для проверки определений

				// Initialize AtomManager (creates singleton instance)
				var atomManager:AtomManager = AtomManager.getInstance();
				trace("AtomManager initialized with supported types: " + atomManager.getSupportedAtomTypes().join(", "));

				// Инициализируем AtomFactory
				AtomFactory.initialize();

				Impulsys.emit(new Impulse("ATOM_SYSTEM_INITIALIZED", {
					supportedTypes: atomManager.getSupportedAtomTypes()
				}));

			} catch (error:Error) {
				trace("Error initializing atom system: " + error.message);
				Impulsys.emit(new Impulse("ERROR", {
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
                
                Impulsys.emit(new Impulse("TRACK_SYSTEM_INITIALIZED"));
                
            } catch (error:Error) {
                trace("Error initializing track system: " + error.message);
                Impulsys.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Track system initialization failed: " + error.message
                }));
            }
        }

        /**
         * Initializes the menu management system.
         *
         * @private
         */
        private static function initializeMenuSystem():void {
            trace("Director: Initializing menu system");

            try {
                // Initialize MenuManager
                MenuManager.initialize();
                trace("MenuManager initialized");

                Impulsys.emit(new Impulse("MENU_SYSTEM_INITIALIZED"));

            } catch (error:Error) {
                trace("Error initializing menu system: " + error.message);
                Impulsys.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Menu system initialization failed: " + error.message
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
            
            Impulsys.emit(new Impulse("APP_READY", {
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
            
            Impulsys.emit(new Impulse("APP_STARTUP_COMPLETE", {
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
            
            Impulsys.emit(new Impulse("APP_STARTUP_FAILED", {
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
