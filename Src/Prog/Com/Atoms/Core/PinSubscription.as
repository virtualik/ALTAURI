package Src.Prog.Com.Atoms.Core {
/**
 * Subscription information for targeted pin subscriptions
 */	public class PinSubscription {
        public var targetPin:Pin;
        public var eventTypes:Array;
        public var callback:Function;
        
        public function PinSubscription(targetPin:Pin, eventTypes:Array, callback:Function) {
            this.targetPin = targetPin;
            this.eventTypes = eventTypes;
            this.callback = callback;
        }
    }
}