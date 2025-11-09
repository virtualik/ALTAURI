package Src.Prog.Com.Atoms.Core {
	import flash.events.EventDispatcher;
    
    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     *
     * @class Pin
     * @public
     */
    public class Pin extends EventDispatcher {

        // Явный маркер версии
        public static const VERSION:String = "PIN_CLASS_V2_WITH_EVENTS";
 
        // Event type constants
        public static const PIN_VALUE_CHANGED:String = "pinValueChanged";
        public static const PIN_CONNECTED:String = "pinConnected";
        public static const PIN_DISCONNECTED:String = "pinDisconnected";

        // Pin type constants
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        /** Unique identifier for the pin */
        public var id:String;

        /** Pin name for identification */
        public var name:String;

        /** Pin type (input or output) */
        public var type:String;

        /** Additional pin properties (data type, description, etc.) */
        public var data:Object;

        /** Collection of listener functions for data changes */
        private var _listeners:Vector.<Function>;

        /** Backing field for pin value */
        private var _value:*;

        /** Collection of specific pin subscriptions */
        private var _targetedSubscriptions:Vector.<PinSubscription>;

        // Static event manager for entire pin system
        private static var _eventManager:PinEventManager;

        /**
         * Initialize static event manager
         */
        private static function initializeEventManager():void {
            if (!_eventManager) {
                _eventManager = new PinEventManager();
            }
        }

        /**
         * Creates a new Pin instance.
         */
        public function Pin(name:String, type:String, value:* = null, data:Object = null) {
            super();

            initializeEventManager();

            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value;
            this.data = data || {};
            this._listeners = new Vector.<Function>();
            this._targetedSubscriptions = new Vector.<PinSubscription>();

            // Register pin in event system
            _eventManager.registerPin(this);

            // FIXED: Remove dangerous automatic subscriptions that cause recursion
            // setupCrossPinSubscriptions(); // COMMENTED OUT - CAUSES INFINITE LOOPS
        }

        // =============================================================================
        // VALUE MANAGEMENT WITH EVENT DISPATCHING
        // =============================================================================

        public function get value():* {
            return _value;
        }

        public function set value(newValue:*):void {
            // FIXED: Add recursion protection - skip if value unchanged
            if (_value === newValue) return;
            
            var oldValue:* = _value;
            _value = newValue;

            trace("=== PIN VALUE CHANGE (V2) ===");
            trace("Pin " + this.name + " (" + this.type + ")");
            trace("Old value: " + oldValue);
            trace("New value: " + newValue);

            // FIXED: Notify local listeners
            notifyListeners(newValue, oldValue);

            // FIXED: Dispatch PIN_VALUE_CHANGED event so subscriptions can catch it
            var pinEvent:PinEvent = new PinEvent(PIN_VALUE_CHANGED, this, newValue, oldValue);
            trace("🚀 DISPATCHING PIN_VALUE_CHANGED EVENT FOR PIN: " + this.name);
            trace("Event details: " + pinEvent.type + ", value: " + pinEvent.newValue);
            
            this.dispatchEvent(pinEvent);
            trace("✅ Event dispatched successfully");

            // FIXED: Global notifications ONLY for output pins to prevent input->input loops
            if (this.type === TYPE_OUTPUT) {
                _eventManager.dispatchToAll(this, pinEvent);
            }
            
            trace("=== END PIN VALUE CHANGE ===");
        }

        // =============================================================================
        // TARGETED SUBSCRIPTION METHODS (PRIMARY DATA FLOW MECHANISM)
        // =============================================================================

        public function subscribeToPin(targetPin:Pin, eventTypes:*, callback:Function):Boolean {
            if (!targetPin || targetPin === this) {
                trace("Pin.subscribeToPin: Invalid target pin");
                return false;
            }

            var events:Array = normalizeEventTypes(eventTypes);
            var subscription:PinSubscription = new PinSubscription(targetPin, events, callback);

            if (hasExistingSubscription(subscription)) {
                trace("Pin.subscribeToPin: Subscription already exists for pin: " + targetPin.name);
                return false;
            }

            trace("Pin.subscribeToPin: Adding " + events.length + " event listeners to pin: " + targetPin.name);
            for each (var eventType:String in events) {
                trace(" - Adding listener for: " + eventType);
                targetPin.addEventListener(eventType, callback);
            }

            _targetedSubscriptions.push(subscription);

            trace("✓ Pin.subscribeToPin: Subscribed to pin: " + targetPin.name + 
                  " for events: " + events.join(", "));
            trace("Current subscriptions count: " + _targetedSubscriptions.length);
            return true;
        }

        public function subscribeToPins(targetPins:Array, eventTypes:*, callback:Function):void {
            for each (var targetPin:Pin in targetPins) {
                subscribeToPin(targetPin, eventTypes, callback);
            }
        }

        public function subscribeToPinById(pinId:String, eventTypes:*, callback:Function):Boolean {
            var targetPin:Pin = _eventManager.findPinById(pinId);
            if (targetPin) {
                return subscribeToPin(targetPin, eventTypes, callback);
            }
            trace("Pin not found with ID: " + pinId);
            return false;
        }

        public function subscribeToPinByName(pinName:String, eventTypes:*, callback:Function):Boolean {
            var targetPin:Pin = _eventManager.findPinByName(pinName);
            if (targetPin) {
                return subscribeToPin(targetPin, eventTypes, callback);
            }
            trace("Pin not found with name: " + pinName);
            return false;
        }

        public function unsubscribeFromPin(targetPin:Pin, eventTypes:* = null):Boolean {
            var events:Array = normalizeEventTypes(eventTypes);
            var removed:Boolean = false;

            for (var i:int = _targetedSubscriptions.length - 1; i >= 0; i--) {
                var subscription:PinSubscription = _targetedSubscriptions[i];

                if (subscription.targetPin === targetPin) {
                    if (events.length > 0) {
                        removed = removeSpecificEvents(subscription, events) || removed;
                        if (subscription.eventTypes.length === 0) {
                            _targetedSubscriptions.splice(i, 1);
                        }
                    } else {
                        removeAllEvents(subscription);
                        _targetedSubscriptions.splice(i, 1);
                        removed = true;
                    }
                }
            }

            if (removed) trace("✓ Unsubscribed from pin: " + targetPin.name);
            return removed;
        }

        public function unsubscribeFromAllPins():void {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                removeAllEvents(subscription);
            }
            _targetedSubscriptions = new Vector.<PinSubscription>();
            trace("✓ Unsubscribed from all pins");
        }

        public function getSubscriptions():Array {
            var result:Array = [];
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                result.push({
                    targetPin: subscription.targetPin.name,
                    targetPinId: subscription.targetPin.id,
                    eventTypes: subscription.eventTypes.slice(),
                    callback: subscription.callback
                });
            }
            return result;
        }

        public function isSubscribedTo(targetPin:Pin, eventType:String = null):Boolean {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                if (subscription.targetPin === targetPin) {
                    if (!eventType) return true;
                    if (subscription.eventTypes.indexOf(eventType) !== -1) return true;
                }
            }
            return false;
        }

        // =============================================================================
        // ORIGINAL CLASS METHODS
        // =============================================================================

        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) {
                _listeners.push(listener);
            }
        }

        public function removeListener(listener:Function):void {
            var index:int = _listeners.indexOf(listener);
            if (index !== -1) {
                _listeners.splice(index, 1);
            }
        }

        private function notifyListeners(newValue:*, oldValue:*):void {
            for (var i:int = 0; i < _listeners.length; i++) {
                _listeners[i](newValue, oldValue, this);
            }
        }

        /**
         *  Limited connection notifications to prevent storms
         */
        public function notifyConnected():void {
            // FIXED: Only notify for output pins to prevent input pin storms
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_CONNECTED, this, this.value);
                _eventManager.dispatchToAll(this, event);
            }
        }

        /**
         *  Limited disconnection notifications to prevent storms
         */
        public function notifyDisconnected():void {
            // FIXED: Only notify for output pins to prevent input pin storms
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_DISCONNECTED, this, this.value);
                _eventManager.dispatchToAll(this, event);
            }
        }

        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        public function clone():Pin {
            var newPin:Pin = new Pin(name, type, _value, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        public function cloneWithValue(newValue:*):Pin {
            var newPin:Pin = new Pin(name, type, newValue, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        private function cloneObject(obj:Object):Object {
            var cloned:Object = {};
            for (var key:String in obj) {
                cloned[key] = obj[key];
            }
            return cloned;
        }

        public function dispose():void {
            notifyDisconnected();
            unsubscribeFromAllPins();
            if (_eventManager) {
                _eventManager.unregisterPin(this);
            }
            _listeners = null;
            _targetedSubscriptions = null;
        }

        // =============================================================================
        // HELPER METHODS
        // =============================================================================

        private function normalizeEventTypes(eventTypes:*):Array {
            if (eventTypes is String) return [eventTypes];
            if (eventTypes is Array) return eventTypes;
            return [PIN_VALUE_CHANGED];
        }

        private function hasExistingSubscription(newSubscription:PinSubscription):Boolean {
            for each (var existing:PinSubscription in _targetedSubscriptions) {
                if (existing.targetPin === newSubscription.targetPin &&
                    existing.callback === newSubscription.callback) {
                    for each (var eventType:String in newSubscription.eventTypes) {
                        if (existing.eventTypes.indexOf(eventType) !== -1) return true;
                    }
                }
            }
            return false;
        }

        private function removeSpecificEvents(subscription:PinSubscription, eventsToRemove:Array):Boolean {
            var removed:Boolean = false;
            for each (var eventType:String in eventsToRemove) {
                var index:int = subscription.eventTypes.indexOf(eventType);
                if (index !== -1) {
                    subscription.eventTypes.splice(index, 1);
                    subscription.targetPin.removeEventListener(eventType, subscription.callback);
                    removed = true;
                }
            }
            return removed;
        }

        private function removeAllEvents(subscription:PinSubscription):void {
            for each (var eventType:String in subscription.eventTypes) {
                subscription.targetPin.removeEventListener(eventType, subscription.callback);
            }
        }

        // =============================================================================
        // STATIC METHODS
        // =============================================================================

        public static function getSystemStats():Object {
            return _eventManager ? _eventManager.getStats() : { totalPins: 0 };
        }
    }
}
