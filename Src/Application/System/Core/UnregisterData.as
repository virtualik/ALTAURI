package Src.Application.System.Core {
    import Src.Application.System.Core.Command;
    import Src.Application.System.Managers.DataManager;

    /**
     * Unregister Data Command - encapsulates data removal from DataManager
     * Encapsulates data clearing operation into command object
     * 
     * Provides command pattern interface for data removal operations
     * Enables clean data management within command sequences
     */
    public class UnregisterData extends Command {
        public var key:String;

        /**
         * Unregister Data Command constructor
         * @param key - string data identifier to remove
         */
        public function UnregisterData(key:String) {
            this.key = key;
        }

        /**
         * Execute command - unregister data
         */
        override protected function executeInternal():void {
            DataManager.unregisterData(key);
            complete();
        }
    }
}
