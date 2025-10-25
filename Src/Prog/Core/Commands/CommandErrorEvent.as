package Src.Prog.Core.Commands {
    import flash.events.Event;

    /**
     * Command Error Event - specialized event for command system
     * Packages and transmits error information from command execution
     *
     * Used throughout command system to standardize error reporting
     * and enable error handling in composite command structures
     */
    public class CommandErrorEvent extends Event {
        public static const ERROR:String = "commandError";
        public var errorMessage:String;

        /**
         * Command Error Event constructor
         * @param type - event type (use CommandErrorEvent.ERROR)
         * @param message - error description text
         * @param bubbles - event bubbling (default false)
         * @param cancelable - event cancelable (default false)
         */
        public function CommandErrorEvent(type:String, message:String = "", bubbles:Boolean = false, cancelable:Boolean = false) {
            super(type, bubbles, cancelable);
            this.errorMessage = message;
        }

        /**
         * Override clone method
         * @return Event - new event instance with same parameters
         */
        override public function clone():Event {
            return new CommandErrorEvent(type, errorMessage, bubbles, cancelable);
        }

        /**
         * Override toString method
         * @return String - string event description
         */
        override public function toString():String {
            return formatToString("CommandErrorEvent", "type", "errorMessage", "bubbles", "cancelable", "eventPhase");
        }
    }
}
