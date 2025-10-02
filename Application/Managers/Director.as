package Application.Managers {
    import flash.events.Event;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Commands.SerialCommand;
    import Application.Commands.Utils.Wait;
    import Application.Commands.Utils.InvokeFunction;
    import Application.Commands.Events.CommandErrorEvent;

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
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",		// ️INFO ℹ️💡📘🔵 / WARN ⚠️⚡🟡🔔 / ERROR ❌⛔🔴🚨❗ / DEBUG 🐛🔍🛠️🟣🔧 / FATAL/CRITICAL 💀☠️🆘🔥 / SUCCESS ✅✔️🟢🎉 / TRACE 👣📝⚪
                source: "Director",
                message: "ℹ️ Starting main initialization pipeline"
            }));

            // UNIFIED STANDARD FOR ALL COURSES
            _initSequence = new SerialCommand(0,
                AtomManager.Run(),
                AssetDispatcherManager.Run(),
                WindowsManager.Run(),
                new Wait(0.5),
                Stage3DManager.Run(),
                new InvokeFunction(loadSchemaProcedure),
                new InvokeFunction(buildSchemaProcedure),
                new InvokeFunction(finalizeInitialization)
            );

            _initSequence.addEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.addEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence.execute();
        }

        /**
         * Schema loading procedure
         */
        private static function loadSchemaProcedure():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [INFO] [Pipeline] Loading schema..."
            }));
            MultiPulsator.emit(new Impulse("SCHEMA_LOADED"));
        }

        /**
         * Schema building procedure
         */
        private static function buildSchemaProcedure():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [INFO] [Pipeline] Building schema..."
            }));
            MultiPulsator.emit(new Impulse("SCHEMA_BUILT"));
        }

        /**
         * Final initialization procedure
         */
        private static function finalizeInitialization():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [INFO] [Pipeline] Final setup..."
            }));
            MultiPulsator.emit(new Impulse("APP_READY"));
        }

        /**
         * Pipeline completion handler
         */
        private static function onInitSequenceComplete(event:Event):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [INFO] Main initialization pipeline completed SUCCESSFULLY."
            }));

            MultiPulsator.emit(new Impulse("APP_STARTUP_COMPLETE"));

            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Pipeline error handler
         */
        private static function onInitSequenceError(event:CommandErrorEvent):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [ERROR] Main initialization pipeline interrupted: " + event.errorMessage
            }));
            _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
            _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
            _initSequence = null;
        }

        /**
         * Force initialization abort
         */
        public static function abortInitialization():void {
            if (_initSequence) {
                _initSequence.removeEventListener(Event.COMPLETE, onInitSequenceComplete);
                _initSequence.removeEventListener(CommandErrorEvent.ERROR, onInitSequenceError);
                _initSequence = null;
            }
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Director: [WARNING] Initialization forcibly interrupted."
            }));
        }
    }
}
