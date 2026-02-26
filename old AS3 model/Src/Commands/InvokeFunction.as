package Src.Commands {
    import Src.Commands.Command;
    import Src.Commands.CommandErrorEvent;

    public class InvokeFunction extends Command {
        public var func:Function;
        public var args:Array;

        public function InvokeFunction(func:Function, args:Array = null) {
            super(0, null);
            this.func = func;
            this.args = args;
        }

        override protected function executeInternal():void {
            try {
                if (args != null && args.length > 0) {
                    func.apply(null, args);
                } else {
                    func();
                }
                complete();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "InvokeFunction: Function execution failed - " + error.message));
            }
        }
    }
}
