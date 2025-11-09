package Src.Prog.Com.Atoms.Core {
    import flash.events.Event;

    /**
     * Custom event for pin system
     * FIXED: Proper Event inheritance for Flash event system
     */
    public class PinEvent extends Event {
        public var sourcePin:Pin;
        public var newValue:*;
        public var oldValue:*;

        public function PinEvent(type:String, sourcePin:Pin, newValue:* = null, oldValue:* = null, 
                               bubbles:Boolean = false, cancelable:Boolean = false) {
            super(type, bubbles, cancelable);
            this.sourcePin = sourcePin;
            this.newValue = newValue;
            this.oldValue = oldValue;
        }

        override public function clone():Event {
            return new PinEvent(type, sourcePin, newValue, oldValue, bubbles, cancelable);
        }

        override public function toString():String {
            return formatToString("PinEvent", "type", "sourcePin", "newValue", "oldValue", 
                                "bubbles", "cancelable", "eventPhase");
        }
    }
}