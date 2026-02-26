package Src.Commands {
    import Src.Commands.Command;
    import Src.Managers.DataManager;

    public class UnregisterData extends Command {
        public var key:String;

        public function UnregisterData(key:String) {
            this.key = key;
        }

        override protected function executeInternal():void {
            DataManager.unregisterData(key);
            complete();
        }
    }
}
