package Src.Managers {
    import flash.events.Event;
    import Src.Impulsator.Impulsys;
    import Src.Impulsator.Impulse;
    import Src.Commands.SerialCommand;
    import Src.Commands.InvokeFunction;
    import Src.Commands.CommandErrorEvent;
    import Src.Atom.Core.AtomFactory;
    import Src.Atom.Data.AtomDefinitions;

    public class Director {
        private static var _initSequence:SerialCommand;

        public static function Run():void {
            _initSequence = new SerialCommand(0,
                new InvokeFunction(initializeCoreSystems),
                new InvokeFunction(initializeImpulsys),
                new InvokeFunction(WindowsManager.createWindows),
                new InvokeFunction(initializeAtomSystem),
                new InvokeFunction(initializeContextMenuystem),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        private static function initializeCoreSystems():void {
            Impulsys.emit(new Impulse("CORE_SYSTEMS_INITIALIZED"));
        }

        private static function initializeImpulsys():void {
            Impulsys.emit(new Impulse("SYSTEM_READY", {
                message: "Impulsys initialized successfully"
            }));
        }

        private static function initializeAtomSystem():void {
            try {
                AtomDefinitions.initialize();
                AtomDefinitions.validateDefinitions();

                var atomManager:AtomManager = AtomManager.getInstance();
                AtomFactory.initialize();

                Impulsys.emit(new Impulse("ATOM_SYSTEM_INITIALIZED", {
                    supportedTypes: AtomFactory.getCreatableAtomTypes()
                }));

            } catch (error:Error) {
                Impulsys.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Atom system initialization failed: " + error.message
                }));
            }
        }

        private static function initializeContextMenuystem():void {
            try {
                MenuManager.initialize();
                Impulsys.emit(new Impulse("MENU_SYSTEM_INITIALIZED"));

            } catch (error:Error) {
                Impulsys.emit(new Impulse("ERROR", {
                    source: "Director",
                    message: "Menu system initialization failed: " + error.message
                }));
            }
        }

        private static function finalizeInitialization():void {
            Impulsys.emit(new Impulse("APP_READY", {
                architecture: "decentralized",
                trackSystem: "autonomous",
                timestamp: new Date().getTime()
            }));
        }

        private static function onInitSequenceComplete(event:Event):void {
            Impulsys.emit(new Impulse("APP_STARTUP_COMPLETE", {
                message: "Decentralized architecture ready",
                atomTypes: AtomFactory.getCreatableAtomTypes(),
                trackArchitecture: "autonomous"
            }));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        private static function onInitSequenceError(event:CommandErrorEvent):void {
            Impulsys.emit(new Impulse("APP_STARTUP_FAILED", {
                error: event.errorMessage
            }));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        public static function abortInitialization():void {
            if (_initSequence) {
                _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
                _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
                _initSequence = null;
            }
        }
    }
}
