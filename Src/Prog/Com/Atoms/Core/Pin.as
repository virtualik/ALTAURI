package Src.Prog.Com.Atoms.Core {
    import flash.events.EventDispatcher;
    import flash.events.Event;

    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     * Implements targeted subscriptions to isolate data propagation without global events.
     *
     * Key changes:
     * - Removed _eventManager.dispatchToAll() from set value
     * - Only direct subscriptions are used
     *
     * @class Pin
     * @extends EventDispatcher
     * @public
     */
    public class Pin extends EventDispatcher {
        public static const VERSION:String = "PIN_CLASS_V2_WITH_EVENTS";
        public static const PIN_VALUE_CHANGED:String = "pinValueChanged";
        public static const PIN_CONNECTED:String = "pinConnected";
        public static const PIN_DISCONNECTED:String = "pinDisconnected";
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        public var id:String;
        public var name:String;
        public var type:String;
        public var data:Object;

        private var _listeners:Vector.<Function>;
        private var _value:*;
        private var _targetedSubscriptions:Vector.<PinSubscription>;
        private static var _eventManager:PinEventManager;

        private static function initializeEventManager():void {
            if (!_eventManager) {
                _eventManager = new PinEventManager();
            }
        }

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
            _eventManager.registerPin(this);
        }

        public function get value():* {
            return _value;
        }

        public function set value(newValue:*):void {
            if (_value === newValue) return;
            var oldValue:* = _value;
            _value = newValue;
            trace("=== PIN VALUE CHANGE (V2) ===");
            trace("Pin " + this.name + " (" + this.type + ")");
            trace("Old value: " + oldValue);
            trace("New value: " + newValue);
            notifyListeners(newValue, oldValue);
            var pinEvent:PinEvent = new PinEvent(PIN_VALUE_CHANGED, this, newValue, oldValue);
            trace("🚀 DISPATCHING PIN_VALUE_CHANGED EVENT FOR PIN: " + this.name);
            trace("Event details: " + pinEvent.type + ", value: " + pinEvent.newValue);
            this.dispatchEvent(pinEvent);
            trace("✅ Event dispatched successfully");
            // ← УДАЛЕНО: _eventManager.dispatchToAll(this, pinEvent);
            trace("=== END PIN VALUE CHANGE ===");
        }

        // =============================================================================
        // LISTENER METHODS
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

        public function notifyConnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_CONNECTED, this, this.value);
                // dispatchToAll intentionally removed — not needed with direct subscriptions
            }
        }

        public function notifyDisconnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_DISCONNECTED, this, this.value);
                // dispatchToAll intentionally removed
            }
        }

        // =============================================================================
        // TARGETED SUBSCRIPTION METHODS
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
            for each (var eventType:String in events) {
                targetPin.addEventListener(eventType, callback);
            }
            _targetedSubscriptions.push(subscription);
            return true;
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
            return removed;
        }

        public function unsubscribeFromAllPins():void {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                removeAllEvents(subscription);
            }
            _targetedSubscriptions = new Vector.<PinSubscription>();
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
        // UTILS
        // =============================================================================

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
