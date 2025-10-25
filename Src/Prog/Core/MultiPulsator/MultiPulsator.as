package Src.Prog.Core.MultiPulsator {
    import flash.utils.Dictionary;

    /**
     * Impulse management system - application communication core
     * Implements Publisher-Subscriber pattern for asynchronous communication between components via impulses
     *
     * Key features:
     * - Centralized messaging between modules
     * - Multiple subscribers per impulse type support
     * - Thread-safe Singleton pattern
     * - Impulse validation and error handling
     */
    public class MultiPulsator {
        // Singleton pattern static variable
        private static var instance:MultiPulsator;

        // Dictionary for subscribers: key - impulse type, value - array of handler functions
        private var impulseListeners:Dictionary;

        /**
         * Constructor - initializes subscriber storage system
         * Private constructor as part of Singleton pattern implementation
         */
        public function MultiPulsator() {
            impulseListeners = new Dictionary();
        }

        /**
         * Debug method - outputs information about subscribers
         * Provides insight into current subscription state for debugging
         */
        public static function getImpulseListeners():void {
            var dict:Dictionary = getInstance().impulseListeners;
            var count:int = 0;

            // Count unique impulse types
            for (var key:* in dict) {
                count++;
            }
        }

        /**
         * Get Singleton instance - main access point to impulse system
         * Creates instance on first access (lazy initialization)
         * @return MultiPulsator - single system instance
         */
        public static function getInstance():MultiPulsator {
            if (!instance) {
                instance = new MultiPulsator();
            }
            return instance;
        }

        /**
         * Subscribe to impulse (static interface)
         * Convenient static wrapper for impulse subscription
         * @param type - impulse type to subscribe to
         * @param listener - impulse handler function
         */
        public static function subscribeToImpulse(type:String, listener:Function):void {
            getInstance().addImpulseListener(type, listener);
        }

        /**
         * Add impulse subscriber
         * Registers handler function for specified impulse type
         * @param type - impulse type to subscribe to
         * @param listener - function to be called when impulse is received
         */
        public function addImpulseListener(type:String, listener:Function):void {
            // Create array for impulse type if it doesn't exist
            if (!impulseListeners[type]) {
                impulseListeners[type] = [];
            }
            // Add listener to array
            impulseListeners[type].push(listener);
        }

        /**
         * Send impulse (static interface)
         * Convenient static wrapper for impulse sending
         * @param impulse - impulse object to send
         */
        public static function emit(impulse:Impulse):void {
            getInstance().fireImpulse(impulse);
        }

        /**
         * Main impulse sending method
         * Validates impulse and distributes to all subscribed listeners
         * @param impulse - impulse object to process
         */
        public function fireImpulse(impulse:Impulse):void {
            // Check for subscribers for this impulse type
            if (impulseListeners[impulse.type]) {
                // Call all registered listeners
                for each(var listener:Function in impulseListeners[impulse.type]) {
                    listener(impulse);
                }
            }
        }

        /**
         * Unsubscribe from impulse (static interface)
         * Convenient static wrapper for subscription removal
         * @param type - impulse type to unsubscribe from
         * @param listener - function to remove from subscribers
         */
        public static function removeImpulse(type:String, listener:Function):void {
            getInstance().removeImpulseListener(type, listener);
        }

        /**
         * Remove subscriber from system
         * Removes function from handlers for specified impulse type
         * @param type - impulse type
         * @param listener - function to remove
         */
        public function removeImpulseListener(type:String, listener:Function):void {
            if (impulseListeners[type]) {
                var index:int = impulseListeners[type].indexOf(listener);
                if (index != -1) {
                    // Remove listener from array
                    impulseListeners[type].splice(index, 1);

                    // Clear entry if no listeners remain
                    if (impulseListeners[type].length == 0) {
                        delete impulseListeners[type];
                    }
                }
            }
        }
    }
}
