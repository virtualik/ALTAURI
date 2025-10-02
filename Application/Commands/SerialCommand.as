package Application.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Application.Commands.Events.CommandErrorEvent;

    /**
     * Serial Command - composite command for sequential execution
     * Executes subcommands one after another in strict order
     */
    public class SerialCommand extends EventDispatcher implements ICommand {
        private var _commands:Array;
        private var _currentIndex:int;
        private var _delay:Number;
        private var _commandId:String;

        /**
         * Serial Command constructor
         * @param delay - delay in seconds before execution start
         * @param commands - variable number of subcommands or command array
         */
        public function SerialCommand(delay:Number, ...commands) {
            _delay = delay;
            _commandId = "SC_" + new Date().getTime() + "_" + Math.random().toString().substr(2, 5);

            if (commands.length == 1 && commands[0] is Array) {
                _commands = commands[0];
            } else {
                _commands = commands;
            }

            _currentIndex = 0;
        }

        /**
         * Execute serial command
         * Starts sequential execution process of subcommands
         */
        public function execute():void {
            if (_commands.length == 0) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            if (_delay > 0) {
                var timer:Timer = new Timer(int(1000 * _delay), 1);
                timer.addEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
                timer.start();
            } else {
                executeNextCommand();
            }
        }

        /**
         * Delay completion handler
         * @param e - timer completion event
         */
        private function onDelayComplete(e:TimerEvent):void {
            var timer:Timer = e.target as Timer;
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
            executeNextCommand();
        }

        /**
         * Execute next subcommand
         * Recursive method for sequential command execution
         */
        private function executeNextCommand():void {
            if (_currentIndex >= _commands.length) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            var command:ICommand = _commands[_currentIndex] as ICommand;

            if (command) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).addEventListener(Event.COMPLETE, onCommandComplete);
                    (command as EventDispatcher).addEventListener(CommandErrorEvent.ERROR, onCommandError);
                    command.execute();
                } else {
                    _currentIndex++;
                    executeNextCommand();
                }
            } else {
                _currentIndex++;
                executeNextCommand();
            }
        }

        /**
         * Subcommand completion handler
         * @param event - subcommand completion event
         */
        private function onCommandComplete(event:Event):void {
            var command:ICommand = event.target as ICommand;

            if (command is EventDispatcher) {
                (command as EventDispatcher).removeEventListener(Event.COMPLETE, onCommandComplete);
                (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onCommandError);
            }

            _currentIndex++;
            executeNextCommand();
        }

        /**
         * Subcommand error handler
         * @param event - subcommand error event
         */
        private function onCommandError(event:CommandErrorEvent):void {
            var failedCommand:ICommand = event.target as ICommand;

            if (failedCommand is EventDispatcher) {
                (failedCommand as EventDispatcher).removeEventListener(Event.COMPLETE, onCommandComplete);
                (failedCommand as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onCommandError);
            }

            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                "Error in command sequence: " + event.errorMessage));
        }
    }
}
