package Src.Commands {
    import Src.Commands.Command;
    import Src.Managers.DataManager;

    public class RegisterData extends Command {
        public var key:String;
        public var data:*;

        public function RegisterData(key:String, data:*) {
            this.key = key;
            this.data = data;
        }

        override protected function executeInternal():void {
            DataManager.registerData(key, data);
            complete();
        }
    }
}
