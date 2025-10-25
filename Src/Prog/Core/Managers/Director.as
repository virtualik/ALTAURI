package Src.Prog.Core.Managers {
    import flash.events.Event;

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.CommandErrorEvent;

    /**
     * Director - main initialization pipeline manager
     * Coordinates application startup sequence using command pattern
     *
     * Orchestrates the complete application bootstrap process
     * Manages sequential execution of system initialization commands
     */
    public class Director {
        private static var _initSequence:SerialCommand;

        /**
         * Start main initialization pipeline
         * Begins the sequential execution of system initialization commands
         */
        public static function Start():void {
            // MANAGERS INITIALIZATION
            _initSequence = new SerialCommand(0,
                new InvokeFunction(WindowsManager.createWindows),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        /**
         * Final initialization procedure
         * Signals that application is ready for operation
         */
        private static function finalizeInitialization():void {
            MultiPulsator.emit(new Impulse("APP_READY"));
        }

        /**
         * Pipeline completion handler
         * Cleans up resources and signals successful startup completion
         */
        private static function onInitSequenceComplete(event:Event):void {
            MultiPulsator.emit(new Impulse("APP_STARTUP_COMPLETE"));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Pipeline error handler
         * Cleans up resources on initialization failure
         */
        private static function onInitSequenceError(event:CommandErrorEvent):void {
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Force initialization abort
         * Emergency stop for initialization process
         */
        public static function abortInitialization():void {
            if (_initSequence) {
                _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
                _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
                _initSequence = null;
            }
        }
    }
}
