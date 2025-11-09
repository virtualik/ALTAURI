package Src.Prog.Com.Atoms.Core {
    import flash.events.EventDispatcher;
    import flash.events.Event;

    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     * Implements targeted subscriptions to isolate data propagation without global events.
     *
     * @class Pin
     * @extends EventDispatcher
     * @public
     */
    public class Pin extends EventDispatcher {

        // Version marker for debugging
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
         * Initialize static event manager.
         *
         * @private
         * @static
         */
        private static function initializeEventManager():void {
            if (!_eventManager) {
                _eventManager = new PinEventManager();
            }
        }

        /**
         * Creates a new Pin instance.
         *
         * @constructor
         * @param {String} name - Pin name
         * @param {String} type - Pin type (TYPE_INPUT or TYPE_OUTPUT)
         * @param {*} value - Initial value (optional)
         * @param {Object} data - Additional pin data (optional)
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

            _eventManager.registerPin(this);
        }

        // =============================================================================
        // VALUE MANAGEMENT WITH EVENT DISPATCHING
        // =============================================================================

        /**
         * Gets the current pin value.
         *
         * @public
         * @return {*} Current value
         */
        public function get value():* {
            return _value;
        }

        /**
         * Sets the pin value and notifies listeners/subscriptions.
         * Dispatches PIN_VALUE_CHANGED event for direct subscribers only.
         *
         * @public
         * @param {*} newValue - New value to set
         */
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

            if (this.type === TYPE_OUTPUT) {
                _eventManager.dispatchToAll(this, pinEvent);
            }

            trace("=== END PIN VALUE CHANGE ===");
        }

        // =============================================================================
        // TARGETED SUBSCRIPTION METHODS (PRIMARY DATA FLOW MECHANISM)
        // =============================================================================

        /**
         * Subscribes to events from another pin.
         * Allows direct peer-to-peer subscriptions for isolated data flow.
         *
         * @public
         * @param {Pin} targetPin - Pin to subscribe to
         * @param {*} eventTypes - Event type(s) to subscribe to (string or array)
         * @param {Function} callback - Callback function for events
         * @return {Boolean} True if subscription was created
         */
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

        /**
         * Subscribes to multiple pins.
         *
         * @public
         * @param {Array} targetPins - Array of pins to subscribe to
         * @param {*} eventTypes - Event type(s)
         * @param {Function} callback - Callback function
         */
        public function subscribeToPins(targetPins:Array, eventTypes:*, callback:Function):void {
            for each (var targetPin:Pin in targetPins) {
                subscribeToPin(targetPin, eventTypes, callback);
            }
        }

        /**
         * Subscribes to pin by ID.
         *
         * @public
         * @param {String} pinId - Pin ID to subscribe to
         * @param {*} eventTypes - Event type(s)
         * @param {Function} callback - Callback function
         * @return {Boolean} True if subscription was created
         */
        public function subscribeToPinById(pinId:String, eventTypes:*, callback:Function):Boolean {
            var targetPin:Pin = _eventManager.findPinById(pinId);
            if (targetPin) {
                return subscribeToPin(targetPin, eventTypes, callback);
            }
            trace("Pin not found with ID: " + pinId);
            return false;
        }

        /**
         * Subscribes to pin by name.
         *
         * @public
         * @param {String} pinName - Pin name to subscribe to
         * @param {*} eventTypes - Event type(s)
         * @param {Function} callback - Callback function
         * @return {Boolean} True if subscription was created
         */
        public function subscribeToPinByName(pinName:String, eventTypes:*, callback:Function):Boolean {
            var targetPin:Pin = _eventManager.findPinByName(pinName);
            if (targetPin) {
                return subscribeToPin(targetPin, eventTypes, callback);
            }
            trace("Pin not found with name: " + pinName);
            return false;
        }

        /**
         * Unsubscribes from a specific pin.
         *
         * @public
         * @param {Pin} targetPin - Pin to unsubscribe from
         * @param {*} eventTypes - Event type(s) to unsubscribe (optional)
         * @return {Boolean} True if unsubscribed
         */
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

        /**
         * Unsubscribes from all pins.
         *
         * @public
         */
        public function unsubscribeFromAllPins():void {
            for each (var subscription:PinSubscription in _targetedSubscriptions) {
                removeAllEvents(subscription);
            }
            _targetedSubscriptions = new Vector.<PinSubscription>();
            trace("✓ Unsubscribed from all pins");
        }

        /**
         * Gets current subscriptions.
         *
         * @public
         * @return {Array} Array of subscription objects
         */
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

        /**
         * Checks if subscribed to specific pin and event.
         *
         * @public
         * @param {Pin} targetPin - Pin to check
         * @param {String} eventType - Event type (optional)
         * @return {Boolean} True if subscribed
         */
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

        /**
         * Adds a local listener for pin events.
         *
         * @public
         * @param {Function} listener - Listener function
         */
        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) {
                _listeners.push(listener);
            }
        }

        /**
         * Removes a local listener.
         *
         * @public
         * @param {Function} listener - Listener to remove
         */
        public function removeListener(listener:Function):void {
            var index:int = _listeners.indexOf(listener);
            if (index !== -1) {
                _listeners.splice(index, 1);
            }
        }

        /**
         * Notifies local listeners of value change.
         *
         * @private
         * @param {*} newValue - New value
         * @param {*} oldValue - Old value
         */
        private function notifyListeners(newValue:*, oldValue:*):void {
            for (var i:int = 0; i < _listeners.length; i++) {
                _listeners[i](newValue, oldValue, this);
            }
        }

        /**
         * Notifies connected status change.
         *
         * @public
         */
        public function notifyConnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_CONNECTED, this, this.value);
                _eventManager.dispatchToAll(this, event);
            }
        }

        /**
         * Notifies disconnected status change.
         *
         * @public
         */
        public function notifyDisconnected():void {
            if (this.type === TYPE_OUTPUT) {
                var event:PinEvent = new PinEvent(PIN_DISCONNECTED, this, this.value);
                _eventManager.dispatchToAll(this, event);
            }
        }

        /**
         * Generates unique ID.
         *
         * @private
         * @return {String} Unique ID
         */
        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        /**
         * Clones the pin.
         *
         * @public
         * @return {Pin} Cloned pin
         */
        public function clone():Pin {
            var newPin:Pin = new Pin(name, type, _value, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        /**
         * Clones pin with new value.
         *
         * @public
         * @param {*} newValue - New value
         * @return {Pin} Cloned pin with value
         */
        public function cloneWithValue(newValue:*):Pin {
            var newPin:Pin = new Pin(name, type, newValue, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        /**
         * Clones object.
         *
         * @private
         * @param {Object} obj - Object to clone
         * @return {Object} Cloned object
         */
        private function cloneObject(obj:Object):Object {
            var cloned:Object = {};
            for (var key:String in obj) {
                cloned[key] = obj[key];
            }
            return cloned;
        }

        /**
         * Disposes the pin.
         *
         * @public
         */
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

        /**
         * Normalizes event types to array.
         *
         * @private
         * @param {*} eventTypes - Event types
         * @return {Array} Normalized array
         */
        private function normalizeEventTypes(eventTypes:*):Array {
            if (eventTypes is String) return [eventTypes];
            if (eventTypes is Array) return eventTypes;
            return [PIN_VALUE_CHANGED];
        }

        /**
         * Checks for existing subscription.
         *
         * @private
         * @param {PinSubscription} newSubscription - Subscription to check
         * @return {Boolean} True if exists
         */
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

        /**
         * Removes specific events from subscription.
         *
         * @private
         * @param {PinSubscription} subscription - Subscription
         * @param {Array} eventsToRemove - Events to remove
         * @return {Boolean} True if removed
         */
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

        /**
         * Removes all events from subscription.
         *
         * @private
         * @param {PinSubscription} subscription - Subscription
         */
        private function removeAllEvents(subscription:PinSubscription):void {
            for each (var eventType:String in subscription.eventTypes) {
                subscription.targetPin.removeEventListener(eventType, subscription.callback);
            }
        }

        // =============================================================================
        // STATIC METHODS
        // =============================================================================

        /**
         * Gets system statistics.
         *
         * @public
         * @static
         * @return {Object} System stats
         */
        public static function getSystemStats():Object {
            return _eventManager ? _eventManager.getStats() : { totalPins: 0 };
        }
    }
}
