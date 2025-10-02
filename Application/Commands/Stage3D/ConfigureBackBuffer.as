package Application.Commands.Stage3D {
    import Application.Commands.Command;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import flash.display3D.Context3D;
    import Application.Managers.DataManager;
    import Application.Commands.Events.CommandErrorEvent;

    /**
     * Command for configuring back buffer for Stage3D
     *
     * ConfigureBackBuffer sets up the rendering buffer for Stage3D context
     * with specified size and quality parameters.
     */
    public class ConfigureBackBuffer extends Command {
        private var _width:int;
        private var _height:int;
        private var _antiAlias:int;
        private var _enableDepthAndStencil:Boolean;

        /**
         * Constructor for buffer configuration command
         */
        public function ConfigureBackBuffer(width:int, height:int, antiAlias:int = 4, enableDepthAndStencil:Boolean = true) {
            super();
            this._width = width;
            this._height = height;
            this._antiAlias = antiAlias;
            this._enableDepthAndStencil = enableDepthAndStencil;
        }

        /**
         * Command execution - buffer configuration
         */
        override protected function executeInternal():void {
            var context3D:Context3D = DataManager.getData("CONTEXT3D") as Context3D;

            if (!context3D) {
                dispatchError("Stage3D context not found");
                return;
            }

            try {
                context3D.configureBackBuffer(_width, _height, _antiAlias, _enableDepthAndStencil);

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "Stage3D: [INFO] Back buffer configured: " + _width + "x" + _height
                }));

                complete();
            } catch (error:Error) {
                dispatchError("Back buffer configuration error: " + error.message);
            }
        }

        private function dispatchError(message:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3D: [ERROR] " + message
            }));
            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, message));
        }
    }
}
