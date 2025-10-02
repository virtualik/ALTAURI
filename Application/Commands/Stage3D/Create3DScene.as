package Application.Commands.Stage3D {
    import Application.Commands.Command;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.Stage3DManager;
    import Application.Commands.Events.CommandErrorEvent;
    import flash.display3D.Context3D;
    import Application.Managers.DataManager;

    /**
     * Command for creating 3D scene
     *
     * Create3DScene initializes main 3D scene with basic components
     * and settings. Serves as entry point for 3D environment creation.
     */
    public class Create3DScene extends Command {

        /**
         * Command execution - scene creation
         */
        override protected function executeInternal():void {
            var context3D:Context3D = DataManager.getData("CONTEXT3D") as Context3D;

            if (!context3D) {
                dispatchError("Stage3D context not available for scene creation");
                return;
            }

            var manager:Stage3DManager = Stage3DManager.getInstance();
            manager.createScene();
            complete();
        }

        private function dispatchError(message:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Create3DScene: [ERROR] " + message
            }));
            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, message));
        }
    }
}
