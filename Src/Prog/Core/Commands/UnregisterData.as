package Src.Prog.Core.Commands {
    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Managers.DataManager;

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
