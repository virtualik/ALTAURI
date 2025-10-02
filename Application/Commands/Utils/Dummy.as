package Application.Commands.Utils {
    import Application.Commands.Command;

    /**
     * Empty command for sequence filling
     * Immediately completes without any actions
     */
    public class Dummy extends Command {
        public function Dummy() {
            super();
        }

        override protected function executeInternal():void {
            complete();
        }
    }
}
