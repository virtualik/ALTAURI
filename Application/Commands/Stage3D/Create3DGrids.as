package Application.Commands.Stage3D {
    import Application.Commands.Command;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.Stage3DManager;
    import Application.Commands.Events.CommandErrorEvent;

    /**
     * Command for creating 3D grids
     *
     * Create3DGrids creates coordinate grids in 3D scene for visual
     * spatial orientation. Creates three perpendicular planes.
     */
    public class Create3DGrids extends Command {
        private var _gridClass:Class;

        /**
         * Constructor for grid creation command
         *
         * @param gridClass - BitmapData class for grid texture
         */
        public function Create3DGrids(gridClass:Class) {
            super();
            this._gridClass = gridClass;
        }

        /**
         * Command execution - grid creation
         */
        override protected function executeInternal():void {
            var manager:Stage3DManager = Stage3DManager.getInstance();

            if (!manager.sceneManager) {
                dispatchError("Scene manager not available for grid creation");
                return;
            }

            manager.createGrids(_gridClass);
            complete();
        }

        private function dispatchError(message:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Create3DGrids: [ERROR] " + message
            }));
            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, message));
        }
    }
}
