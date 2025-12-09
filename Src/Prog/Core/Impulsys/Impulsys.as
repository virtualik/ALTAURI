package Src.Prog.Core.Impulsys {
    import flash.utils.Dictionary;

    public class Impulsys {
        private static var instance:Impulsys;
        private var impulseListeners:Dictionary;

        public function Impulsys() {
            impulseListeners = new Dictionary();
        }

        public static function getInstance():Impulsys {
            if (!instance) {
                instance = new Impulsys();
            }
            return instance;
        }

        public static function subscribeToImpulse(type:String, listener:Function):void {
            getInstance().addImpulseListener(type, listener);
        }

        public function addImpulseListener(type:String, listener:Function):void {
            if (!impulseListeners[type]) {
                impulseListeners[type] = [];
            }
            impulseListeners[type].push(listener);
        }

        public static function emit(impulse:Impulse):void {
            getInstance().fireImpulse(impulse);
        }

        public function fireImpulse(impulse:Impulse):void {
            if (impulseListeners[impulse.type]) {
                for each (var listener:Function in impulseListeners[impulse.type]) {
                    listener(impulse);
                }
            }
        }

        public static function removeImpulse(type:String, listener:Function):void {
            getInstance().removeImpulseListener(type, listener);
        }

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

        public static function getImpulseListeners():void {
            var dict:Dictionary = getInstance().impulseListeners;
            var count:int = 0;

            for (var key:* in dict) {
                count++;
            }
        }
    }
}
