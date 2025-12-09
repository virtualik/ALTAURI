package Src.Prog.Core.Impulsys {
    import flash.utils.Dictionary;

    /**
     * Centralized impulse management system implementing Publisher-Subscriber pattern.
     * Provides asynchronous communication between components via impulses.
     *
     * @class Impulsys
     * @public
     */
    public class Impulsys {
        
        /** Singleton instance */
        private static var instance:Impulsys;
        
        /** Dictionary storing impulse type to listener arrays mapping */
        private var impulseListeners:Dictionary;

        /**
         * Private constructor for singleton pattern.
         */
        public function Impulsys() {
            impulseListeners = new Dictionary();
        }

        /**
         * Gets the singleton instance (lazy initialization).
         *
         * @static
         * @return {Impulsys} Singleton instance
         */
        public static function getInstance():Impulsys {
            if (!instance) {
                instance = new Impulsys();
            }
            return instance;
        }

        /**
         * Subscribes to impulses of specified type (static interface).
         *
         * @static
         * @param {String} type - Impulse type to subscribe to
         * @param {Function} listener - Handler function to call when impulse is received
         */
        public static function subscribeToImpulse(type:String, listener:Function):void {
            getInstance().addImpulseListener(type, listener);
        }

        /**
         * Adds an impulse listener for specified type.
         *
         * @param {String} type - Impulse type to listen for
         * @param {Function} listener - Handler function
         */
        public function addImpulseListener(type:String, listener:Function):void {
            if (!impulseListeners[type]) {
                impulseListeners[type] = [];
            }
            impulseListeners[type].push(listener);
        }

        /**
         * Emits an impulse to all subscribers (static interface).
         *
         * @static
         * @param {Impulse} impulse - Impulse object to send
         */
        public static function emit(impulse:Impulse):void {
            getInstance().fireImpulse(impulse);
        }

        /**
         * Sends impulse to all registered listeners.
         *
         * @param {Impulse} impulse - Impulse to distribute
         */
        public function fireImpulse(impulse:Impulse):void {
            if (impulseListeners[impulse.type]) {
                for each (var listener:Function in impulseListeners[impulse.type]) {
                    listener(impulse);
                }
            }
        }

        /**
         * Unsubscribes from impulses (static interface).
         *
         * @static
         * @param {String} type - Impulse type to unsubscribe from
         * @param {Function} listener - Handler function to remove
         */
        public static function removeImpulse(type:String, listener:Function):void {
            getInstance().removeImpulseListener(type, listener);
        }

        /**
         * Removes impulse listener from system.
         *
         * @param {String} type - Impulse type
         * @param {Function} listener - Handler function to remove
         */
        public function removeImpulseListener(type:String, listener:Function):void {
            if (impulseListeners[type]) {
                var index:int = impulseListeners[type].indexOf(listener);
                if (index != -1) {
                    impulseListeners[type].splice(index, 1);
                    
                    if (impulseListeners[type].length == 0) {
                        delete impulseListeners[type];
                    }
                }
            }
        }

        /**
         * Debug method to get current subscription counts.
         *
         * @static
         */
        public static function getImpulseListeners():void {
            var dict:Dictionary = getInstance().impulseListeners;
            var count:int = 0;

            for (var key:* in dict) {
                count++;
            }
            trace("Impulsys: " + count + " impulse types with active listeners");
        }
    }
}
