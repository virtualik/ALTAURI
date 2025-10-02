package Application.Commands.Data {
    import Application.Commands.Command;
    import Application.Managers.DataManager;

    /**
     * Register Data Command - encapsulates data registration in DataManager
     * Encapsulates data saving operation into command object
     */
    public class RegisterData extends Command {
        public var key:String;
        public var data:*;

        /**
         * Register Data Command constructor
         * @param key - string data identifier
         * @param data - data to save in storage
         */
        public function RegisterData(key:String, data:*) {
            this.key = key;
            this.data = data;
        }

        /**
         * Execute command - register data
         */
        override protected function executeInternal():void {
            DataManager.registerData(key, data);
            complete();
        }
    }
}
