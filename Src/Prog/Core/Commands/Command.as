package Src.Prog.Core.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.TimerEvent;
    import flash.utils.Timer;
    import Src.Prog.Core.Commands.CommandErrorEvent;

    public class Command extends EventDispatcher implements ICommand {
        private var _timer:Timer;
        public var title:String;

        public function Command(delay:Number = 0, title:String = null) {
            this.title = title;
            _timer = new Timer(int(1000 * delay), 1);
            _timer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimerComplete);
        }

        private function onTimerComplete(e:TimerEvent):void {
            execute();
        }

        public final function start(e:Event = null):void {
            _timer.start();
        }

        public function execute():void {
            try {
                executeInternal();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR, error.message));
            }
        }

        protected function executeInternal():void {
            complete();
        }

        protected final function complete(e:Event = null):void {
            dispatchEvent(new Event(Event.COMPLETE));
        }
    }
}
