package Src.Prog.Core.Commands {
    public class CreatePinSubscription extends Command {
        private var _sourcePin:Pin;
        private var _targetPin:Pin;
        private var _eventTypes:Array;

        public function CreatePinSubscription(sourcePin:Pin, targetPin:Pin, eventTypes:Array = null) {
            super(0, "CreatePinSubscription");
            _sourcePin = sourcePin;
            _targetPin = targetPin;
            _eventTypes = eventTypes || [Pin.PIN_VALUE_CHANGED];
        }

        override protected function executeInternal():void {
            if (_targetPin.subscribeToPin(_sourcePin, _eventTypes, onPinValueChanged)) {
                complete();
            } else {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "Failed to create pin subscription"));
            }
        }

        private function onPinValueChanged(event:PinEvent):void {
        }
    }
}
