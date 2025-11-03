package Src.Prog.Com.Atoms.Core {
    
    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     *
     * @class Pin
     * @public
     */
    public class Pin {
        
        /** Input pin type constant */
        public static const TYPE_INPUT:String = "input";
        
        /** Output pin type constant */
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
            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value; // Use backing field
            this.data = data || {};
            this._listeners = new Vector.<Function>();
        }

        /**
         * Gets the current value of the pin.
         * 
         * @return {*} Current pin value
         */
        public function get value():* {
            return _value;
        }

        /**
         * Sets the pin value and notifies all listeners of the change.
         *
         * @param {*} newValue - New value for the pin
         */
		public function set value(newValue:*):void {
			if (_value !== newValue) {
				var oldValue:* = _value;
				_value = newValue;
				
				trace("=== PIN VALUE CHANGE ===");
				trace("Pin " + this.name + " (" + this.type + ")");
				trace("Old value: " + oldValue);
				trace("New value: " + newValue);
				trace("=== END PIN VALUE CHANGE ===");
				
				notifyListeners(newValue, oldValue);
			}
		}

        /**
         * Adds a listener function to be called when pin data changes.
         *
         * @param {Function} listener - Function to call on data change
         */
        public function addListener(listener:Function):void {
            if (_listeners.indexOf(listener) === -1) {
                _listeners.push(listener);
            }
        }

        /**
         * Removes a previously added listener function.
         *
         * @param {Function} listener - Function to remove
         */
        public function removeListener(listener:Function):void {
            var index:int = _listeners.indexOf(listener);
            if (index !== -1) {
                _listeners.splice(index, 1);
            }
        }

        /**
         * Notifies all registered listeners of a data change.
         *
         * @private
         * @param {*} newValue - New pin value
         * @param {*} oldValue - Previous pin value
         */
        private function notifyListeners(newValue:*, oldValue:*):void {
            for (var i:int = 0; i < _listeners.length; i++) {
                _listeners[i](newValue, oldValue, this);
            }
        }

        /**
         * Generates a unique identifier for the pin.
         *
         * @private
         * @return {String} Unique pin identifier
         */
        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        /**
         * Creates a clone of this pin instance.
         *
         * @return {Pin} New Pin instance with same properties
         */
        public function clone():Pin {
            var newPin:Pin = new Pin(name, type, _value, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        /**
         * Creates a clone of this pin with a new value.
         *
         * @param {*} newValue - New value for the pin
         * @return {Pin} New Pin instance with updated value
         */
        public function cloneWithValue(newValue:*):Pin {
            var newPin:Pin = new Pin(name, type, newValue, cloneObject(data));
            newPin.id = this.id;
            return newPin;
        }

        /**
         * Creates a deep clone of an object.
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
         * Cleans up resources and removes all listeners.
         */
        public function dispose():void {
            _listeners = null;
        }
    }
}
