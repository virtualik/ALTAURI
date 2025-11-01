package Src.Prog.Com.Atoms.Core {
    /**
     * Represents a connection point (input or output) for data flow between atoms.
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
        
        /** Pin name */
        public var name:String;
        
        /** Pin type (input or output) */
        public var type:String;
        
        /** Current value of the pin */
        public var value:*;
        
        /** Additional pin properties (color, data type, etc.) */
        public var data:Object;

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
            this.id = generateId(); // Генерируем уникальный ID
            this.name = name;
            this.type = type;
            this.value = value;
            this.data = data || {};
        }

        /**
         * Generates a unique identifier for the pin.
         * 
         * @private
         * @return {String} Unique ID
         */
        private function generateId():String {
            return "pin_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        /**
         * Creates a clone of this pin.
         * 
         * @return {Pin} New Pin instance with same properties
         */
        public function clone():Pin {
            var newPin:Pin = new Pin(name, type, value, cloneObject(data));
            newPin.id = this.id; // Сохраняем тот же ID
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
            newPin.id = this.id; // Сохраняем тот же ID
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
    }
}
