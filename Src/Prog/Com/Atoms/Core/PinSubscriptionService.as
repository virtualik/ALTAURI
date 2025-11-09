package Src.Prog.Com.Atoms.Core {
    /**
     * Сервис для управления подписками между пинами
     */
    public class PinSubscriptionService {
        private static var _instance:PinSubscriptionService;
        
        public static function getInstance():PinSubscriptionService {
            if (!_instance) _instance = new PinSubscriptionService();
            return _instance;
        }
        
        /**
         * Создание подписки между пинами атомов
         */
        public function createAtomPinSubscription(sourceAtom:Atom, targetAtom:Atom, 
                                                sourcePinName:String, targetPinName:String):Boolean {
            var sourcePin:Pin = findPinByName(sourceAtom.outputs, sourcePinName);
            var targetPin:Pin = findPinByName(targetAtom.inputs, targetPinName);
            
            if (sourcePin && targetPin) {
                return targetPin.subscribeToPin(sourcePin, Pin.PIN_VALUE_CHANGED, 
                    function(event:PinEvent):void {
                        // Автоматическая синхронизация
                        targetPin.value = event.newValue;
                    });
            }
            return false;
        }
        
        /**
         * Получение статистики системы подписок
         */
        public function getSubscriptionStats():Object {
            return Pin.getSystemStats();
        }
    }
}
