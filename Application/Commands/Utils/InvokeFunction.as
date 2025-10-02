package Application.Commands.Utils {
    import Application.Commands.Command;

    /**
     * Encapsulates function call as command
     * For integrating existing code with command system
     */
    public class InvokeFunction extends Command {
        public var func:Function;
        public var args:Array;

        public function InvokeFunction(func:Function, args:Array = null) {
            super(0, null);
            this.func = func;
            this.args = args;
        }

        override protected function executeInternal():void {
            if (args != null && args.length > 0) {
                func.apply(null, args);
            } else {
                func();
            }
            complete();
        }
    }
}
