package Application.Commands.Utils {
    import Application.Commands.Command;

    /**
     * Bulk object property assignment command
     * Sets multiple properties at once
     */
    public class SetProperties extends Command {
        public var target:Object;
        public var properties:Object;

        public function SetProperties(target:Object, properties:Object) {
            this.target = target;
            this.properties = properties;
        }

        override protected function executeInternal():void {
            for (var key:String in properties) {
                target[key] = properties[key];
            }
            complete();
        }
    }
}
