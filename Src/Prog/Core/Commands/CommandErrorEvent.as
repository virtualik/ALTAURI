package Src.Prog.Core.Commands {
    import flash.events.Event;

    public class CommandErrorEvent extends Event {
        public static const ERROR:String = "commandError";
        public var errorMessage:String;

        public function CommandErrorEvent(type:String, message:String = "", bubbles:Boolean = false, cancelable:Boolean = false) {
            super(type, bubbles, cancelable);
            this.errorMessage = message;
        }

        override public function clone():Event {
            return new CommandErrorEvent(type, errorMessage, bubbles, cancelable);
        }

        override public function toString():String {
            return formatToString("CommandErrorEvent", "type", "errorMessage", "bubbles", "cancelable", "eventPhase");
        }
    }
}
