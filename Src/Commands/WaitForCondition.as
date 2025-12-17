package Src.Commands {
    import flash.utils.Timer;
    import flash.events.TimerEvent;
    import Src.Commands.Command;
    import Src.Commands.CommandErrorEvent;

    public class WaitForCondition extends Command {
        private var _conditionCheck:Function;
        private var _timeoutMs:int;
        private var _checkInterval:int;
        private var _checkTimer:Timer;
        private var _timeoutTimer:Timer;
        private var _isComplete:Boolean;

        public function WaitForCondition(conditionCheck:Function,
                                       timeoutMs:int = 5000,
                                       checkInterval:int = 100) {
            super();
            this._conditionCheck = conditionCheck;
            this._timeoutMs = timeoutMs;
            this._checkInterval = checkInterval;
            this._isComplete = false;
        }

        override protected function executeInternal():void {
            _isComplete = false;
            _checkTimer = new Timer(_checkInterval);
            _checkTimer.addEventListener(TimerEvent.TIMER, onCheckTimer);
            _checkTimer.start();

            _timeoutTimer = new Timer(_timeoutMs, 1);
            _timeoutTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimeout);
            _timeoutTimer.start();
            checkCondition();
        }

        private function onCheckTimer(event:TimerEvent):void {
            if (!_isComplete) {
                checkCondition();
            }
        }

        private function onTimeout(event:TimerEvent):void {
            if (!_isComplete) {
                cleanupTimers();
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "WaitForCondition: Timeout reached after " + _timeoutMs + "ms"));
                complete();
            }
        }

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

        override protected function complete(e:Event = null):void {
            cleanupTimers();
            super.complete(e);
        }
    }
}
