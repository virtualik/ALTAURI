package Application.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.TimerEvent;
    import flash.utils.Timer;

    import Application.Commands.Events.CommandErrorEvent;

    /**
     * Base Command Class - abstract implementation of Command pattern
     * Provides common infrastructure for all application commands
     */
    public class Command extends EventDispatcher implements ICommand {
        private var _timer:Timer;
        public var title:String;

        /**
         * Base Command constructor
         * @param delay - delay in seconds before command execution (default 0)
         * @param title - optional command title for identification
         */
        public function Command(delay:Number = 0, title:String = null) {
            this.title = title;
            _timer = new Timer(int(1000 * delay), 1);
            _timer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimerComplete);
        }

        /**
         * Timer complete handler
         * @param e - timer completion event
         */
        private function onTimerComplete(e:TimerEvent):void {
            execute();
        }

        /**
         * Start command execution
         * @param e - optional event (not used in base implementation)
         */
        public final function start(e:Event = null):void {
            _timer.start();
        }

        /**
         * Execute command - ICommand interface implementation
         */
        public function execute():void {
            try {
                executeInternal();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, error.message));
            }
        }

        /**
         * Internal command execution - template method
         * Override in child classes with specific logic
         */
        protected function executeInternal():void {
            complete();
        }

        /**
         * Complete command execution
         * @param e - optional event (not used)
         */
        protected final function complete(e:Event = null):void {
            dispatchEvent(new Event(Event.COMPLETE));
        }
    }
}
