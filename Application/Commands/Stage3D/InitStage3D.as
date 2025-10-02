package Application.Commands.Stage3D {
    import Application.Commands.Command;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.Context3DRenderMode;
    import flash.display3D.Context3DProfile;
    import flash.events.Event;
    import Application.Managers.DataManager;
    import Application.Commands.Events.CommandErrorEvent;
    import flash.events.ErrorEvent;

    /**
     * Command for initializing Stage3D context
     *
     * InitStage3D is responsible for creating and configuring Stage3D rendering context.
     * Encapsulates the process of context request, creation event handling
     * and context storage in global DataManager.
     *
     * Main functions:
     * - Request Stage3D context with specified parameters
     * - Handle successful context creation
     * - Handle initialization errors
     * - Store context for subsequent use
     */
    public class InitStage3D extends Command {
        private var _stage3D:Stage3D;
        private var _renderMode:String;
        private var _profile:String;
        public static const CONTEXT_READY:String = "contextReady";
        
        /**
         * Constructor for Stage3D initialization command
         *
         * @param stage3D - Stage3D instance to initialize
         * @param renderMode - rendering mode (auto/software)
         * @param profile - context profile (baseline/baselineExtended/etc)
         */
        public function InitStage3D(stage3D:Stage3D, renderMode:String = "auto", profile:String = "baselineExtended") {
            super();
            this._stage3D = stage3D;
            this._renderMode = renderMode;
            this._profile = profile;
        }

        /**
         * Command execution - Stage3D context request
         */
        override protected function executeInternal():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3D: [INFO] Requesting rendering context"
            }));

            _stage3D.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
            _stage3D.addEventListener(ErrorEvent.ERROR, onContextError);
            
            _stage3D.requestContext3D(
                _renderMode == "software" ? Context3DRenderMode.SOFTWARE : Context3DRenderMode.AUTO,
                _profile
            );
        }

        /**
         * Context creation handler
         */
        private function onContextCreated(e:Event):void {
            _stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
            _stage3D.removeEventListener(ErrorEvent.ERROR, onContextError);

            var context3D:Context3D = _stage3D.context3D;

            if (context3D) {
                DataManager.registerData("CONTEXT3D", context3D);
                DataManager.registerData("STAGE3D", _stage3D);

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "Stage3D: [INFO] Context successfully created: " + context3D.driverInfo
                }));

                dispatchEvent(new Event(CONTEXT_READY));
                complete();
            } else {
                dispatchError("Failed to create Stage3D context");
            }
        }

        /**
         * Error handling
         */
        private function dispatchError(message:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3D: [ERROR] " + message
            }));

            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, message));
        }

        private function onContextError(e:ErrorEvent):void {
            _stage3D.removeEventListener(ErrorEvent.ERROR, onContextError);
            _stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
            dispatchError("Context creation error: " + e.text);
        }
    }
}
