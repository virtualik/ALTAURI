package Src.Prog.Core.Commands {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.Commands.CommandErrorEvent;
    import Src.Prog.Core.Commands.ICommand;

    /**
     * Parallel Command - composite command for parallel execution
     * Executes all subcommands simultaneously and completes when all finish
     *
     * Key features:
     * - Concurrent execution of multiple commands
     * - Configurable initial delay
     * - Error handling with proper cleanup
     * - Completion when all subcommands finish
     */
    public class ParallelCommand extends EventDispatcher implements ICommand {
        private var _commands:Array;
        private var _completeCommandCount:int;
        private var _delay:Number;

        /**
         * Parallel Command constructor
         * @param delay - delay in seconds before execution start
         * @param commands - variable number of subcommands for parallel execution
         */
        public function ParallelCommand(delay:Number, ...commands) {
            _delay = delay;

            if (commands.length == 1 && commands[0] is Array) {
                _commands = commands[0];
            } else {
                _commands = commands;
            }

            _completeCommandCount = 0;
        }

        /**
         * Execute parallel command
         * Starts parallel execution process of subcommands
         */
        public function execute():void {
            _completeCommandCount = 0;

            if (_commands.length == 0) {
                dispatchEvent(new Event(Event.COMPLETE));
                return;
            }

            if (_delay > 0) {
                var timer:Timer = new Timer(int(1000 * _delay), 1);
                timer.addEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
                timer.start();
            } else {
                startAllCommands();
            }
        }

        /**
         * Delay completion handler
         * @param e - timer completion event
         */
        private function onDelayComplete(e:TimerEvent):void {
            var timer:Timer = e.target as Timer;
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, onDelayComplete);
            startAllCommands();
        }

        /**
         * Start all subcommands
         * Starts all subcommands simultaneously and subscribes to their events
         */
        private function startAllCommands():void {
            for each (var command:ICommand in _commands) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).addEventListener(Event.COMPLETE, onSubcommandComplete);
                    (command as EventDispatcher).addEventListener(CommandErrorEvent.ERROR, onSubcommandError);
                }
                command.execute();
            }
        }

        /**
         * Subcommand completion handler
         * @param e - subcommand completion event
         */
        private function onSubcommandComplete(e:Event):void {
            var command:ICommand = e.target as ICommand;

            if (command is EventDispatcher) {
                (command as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
            }

            _completeCommandCount++;

            if (_completeCommandCount == _commands.length) {
                dispatchEvent(new Event(Event.COMPLETE));
            }
        }

        /**
         * Subcommand error handler
         * @param event - subcommand error event
         */
        private function onSubcommandError(event:CommandErrorEvent):void {
            var failedCommand:ICommand = event.target as ICommand;

            if (failedCommand is EventDispatcher) {
                (failedCommand as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                (failedCommand as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
            }

            cleanupAllListeners();

            dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                "Error in parallel command: " + event.errorMessage));
        }

        /**
         * Clean up all listeners
         * Unsubscribes from all subcommands to prevent memory leaks
         */
        private function cleanupAllListeners():void {
            for each (var command:ICommand in _commands) {
                if (command is EventDispatcher) {
                    (command as EventDispatcher).removeEventListener(Event.COMPLETE, onSubcommandComplete);
                    (command as EventDispatcher).removeEventListener(CommandErrorEvent.ERROR, onSubcommandError);
                }
            }
        }
    }
}
