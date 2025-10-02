package Application.MultiPulsator {
    /**
     * Impulse implementation - concrete message container for MultiPulsator system
     * Universal data container providing standardized message format and type safety
     */
    public class Impulse implements IImpulse {
        private var _type:String;
        private var _data:Object;

        /**
         * Constructor - creates new impulse with specified type and data
         */
        public function Impulse(type:String, data:Object = null) {
            _type = type;
            _data = data;
        }

        /**
         * Get impulse type - string identifier
         */
        public function get type():String {
            return _type;
        }

        /**
         * Get impulse data - payload object
         */
        public function get data():Object {
            return _data;
        }
    }
}
