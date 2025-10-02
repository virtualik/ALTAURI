package Application.Managers {
    import flash.utils.Dictionary;

    /**
     * Data Manager - centralized key-value storage for application
     * Provides static interface for global data management
     * 
     * Key features:
     * - Global data storage with unique string keys
     * - Thread-safe access through static methods
     * - Support for any data type
     * - Integration with RegisterData and UnregisterData commands
     */
    public class DataManager {
        // Private static dictionary for data storage
        private static var _data:Dictionary = new Dictionary();

        /**
         * Get data by key
         * @param key - string data identifier
         * @return * - data associated with key or undefined if not found
         */
        public static function getData(key:String):* {
            return _data[key];
        }

        /**
         * Register data in storage
         * @param key - unique string data identifier
         * @param data - data to save (any type)
         */
        public static function registerData(key:String, data:*):void {
            _data[key] = data;
        }

        /**
         * Remove data from storage
         * @param key - string data identifier to remove
         */
        public static function unregisterData(key:String):void {
            delete _data[key];
        }

        /**
         * Complete storage cleanup
         * Removes all data from global storage
         */
        public static function clearData():void {
            for (var key:String in _data) {
                delete _data[key];
            }
        }

        /**
         * Check data existence
         * @param key - string data identifier
         * @return Boolean - true if data exists
         */
        public static function hasData(key:String):Boolean {
            return _data[key] !== undefined;
        }

        /**
         * Get all keys
         * @return Array - array of all registered keys
         */
        public static function getAllKeys():Array {
            var keys:Array = [];
            for (var key:String in _data) {
                keys.push(key);
            }
            return keys;
        }
    }
}
