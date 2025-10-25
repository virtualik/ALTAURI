package Src.Prog.Core.MultiPulsator {
    /**
     * Impulse implementation - concrete message container for MultiPulsator system
     * Universal data container providing standardized message format and type safety
     *
     * Primary message vehicle for inter-module communication
     * Implements IImpulse interface for consistent message handling
     */
    public class Impulse implements IImpulse {
        private var _type:String;
        private var _data:Object;

        /**
         * Constructor - creates new impulse with specified type and data
         * @param type - impulse type identifier
         * @param data - optional data payload (default null)
         */
        public function Impulse(type:String, data:Object = null) {
            _type = type;
            _data = data;
        }

        /**
         * Get impulse type - string identifier
         * @return String - impulse type
         */
        public function get type():String {
            return _type;
        }

        /**
         * Get impulse data - payload object
         * @return Object - impulse data
         */
        public function get data():Object {
            return _data;
        }
    }
}
