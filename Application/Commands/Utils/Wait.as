package Application.Commands.Utils {
    import Application.Commands.Command;

    /**
     * Pause command for sequence delays
     * Uses built-in Command delay mechanism
     */
    public class Wait extends Command {
        public function Wait(delay:Number = 0) {
            super(delay);
        }

        override protected function executeInternal():void {
            complete();
        }
    }
}
