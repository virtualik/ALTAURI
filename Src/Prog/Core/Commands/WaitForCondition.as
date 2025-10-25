package Src.Prog.Core.Commands {
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.Commands.Command;
    import Src.Prog.Core.Commands.CommandErrorEvent;

    /**
     * Wait for condition fulfillment command
     * Periodically checks condition until it's met or timeout occurs
     * Uses Timer-based implementation for consistency with command system
     *
     * Typical use cases:
     * - Waiting for resource loading completion
     * - Waiting for system readiness
     * - Waiting for user input confirmation
     */
    public class WaitForCondition extends Command {
        private var _conditionCheck:Function;
        private var _timeoutMs:int;
        private var _checkInterval:int;
        private var _checkTimer:Timer;
        private var _timeoutTimer:Timer;
        private var _isComplete:Boolean;

        /**
         * Wait for condition command constructor
         * @param conditionCheck - function that returns Boolean when condition is met
         * @param timeoutMs - maximum waiting time in milliseconds (default 5000)
         * @param checkInterval - condition check interval in milliseconds (default 100)
         */
        public function WaitForCondition(conditionCheck:Function,
                                       timeoutMs:int = 5000,
                                       checkInterval:int = 100) {
            super();
            this._conditionCheck = conditionCheck;
            this._timeoutMs = timeoutMs;
            this._checkInterval = checkInterval;
            this._isComplete = false;
        }

        /**
         * Execute command - start condition checking process
         * Sets up periodic checking and timeout monitoring
         */
        override protected function executeInternal():void {
            _isComplete = false;

            // Start periodic condition checking
            _checkTimer = new Timer(_checkInterval);
            _checkTimer.addEventListener(TimerEvent.TIMER, onCheckTimer);
            _checkTimer.start();

            // Setup timeout monitoring
            _timeoutTimer = new Timer(_timeoutMs, 1);
            _timeoutTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimeout);
            _timeoutTimer.start();

            // Perform immediate first check
            checkCondition();
        }

        /**
         * Check timer handler - periodic condition verification
         * @param event - timer event
         */
        private function onCheckTimer(event:TimerEvent):void {
            if (!_isComplete) {
                checkCondition();
            }
        }

        /**
         * Timeout handler - condition not met within specified time
         * @param event - timeout timer completion event
         */
        private function onTimeout(event:TimerEvent):void {
            if (!_isComplete) {
                cleanupTimers();
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "WaitForCondition: Timeout reached after " + _timeoutMs + "ms"));
                complete();
            }
        }

        /**
         * Condition checking logic
         * Evaluates condition function and completes if condition is met
         */
        private function checkCondition():void {
            try {
                if (_conditionCheck()) {
                    _isComplete = true;
                    cleanupTimers();
                    complete();
                }
            } catch (error:Error) {
                _isComplete = true;
                cleanupTimers();
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "WaitForCondition: Condition check failed - " + error.message));
                complete();
            }
        }

        /**
         * Clean up timer resources
         * Stops and removes event listeners from both timers
         */
        private function cleanupTimers():void {
            if (_checkTimer) {
                _checkTimer.stop();
                _checkTimer.removeEventListener(TimerEvent.TIMER, onCheckTimer);
                _checkTimer = null;
            }

            if (_timeoutTimer) {
                _timeoutTimer.stop();
                _timeoutTimer.removeEventListener(TimerEvent.TIMER_COMPLETE, onTimeout);
                _timeoutTimer = null;
            }
        }

        /**
         * Command completion override
         * Ensures proper resource cleanup on completion
         */
        override protected function complete(e:Event = null):void {
            cleanupTimers();
            super.complete(e);
        }
    }
}
