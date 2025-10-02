package Application.Commands.Utils {
    import Application.Commands.Command;
    import flash.utils.setTimeout;
    import Application.Commands.Events.CommandErrorEvent;

    /**
     * Waits for condition fulfillment
     * Periodically checks until condition is met or timeout
     */
    public class WaitForCondition extends Command {
        private var _conditionCheck:Function;
        private var _timeoutMs:int;
        private var _checkInterval:int;
        private var _startTime:Number;

        public function WaitForCondition(conditionCheck:Function,
                                       timeoutMs:int = 5000,
                                       checkInterval:int = 100) {
            this._conditionCheck = conditionCheck;
            this._timeoutMs = timeoutMs;
            this._checkInterval = checkInterval;
        }

        override protected function executeInternal():void {
            _startTime = new Date().getTime();
            checkCondition();
        }

        private function checkCondition():void {
            try {
                if (_conditionCheck()) {
                    complete();
                } else if (new Date().getTime() - _startTime > _timeoutMs) {
                    dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                        "Condition not met after " + _timeoutMs + "ms"));
                    complete();
                } else {
                    setTimeout(checkCondition, _checkInterval);
                }
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "Condition check failed: " + error.message));
                complete();
            }
        }
    }
}
