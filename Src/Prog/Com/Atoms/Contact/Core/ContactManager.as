package Src.Prog.Com.Atoms.Contact.Core {
    import flash.utils.Dictionary;

    /**
     * Менеджер для глобального управления контактами.
     * Отвечает за регистрацию, предотвращение циклов и статистику.
     * Упрощенный аналог PinEventManager.
     * 
     * @class ContactManager
     */
    public class ContactManager {
        
        // Singleton instance
        private static var _instance:ContactManager;
        
        // Хранилище всех зарегистрированных контактов
        private var _allContacts:Vector.<Contact>;
        private var _contactsById:Dictionary;

        /**
         * Приватный конструктор для singleton.
         */
        public function ContactManager() {
            if (_instance) {
                throw new Error("ContactManager is singleton. Use getInstance() instead.");
            }
            
            _allContacts = new Vector.<Contact>();
            _contactsById = new Dictionary();
            
            trace("ContactManager: Initialized");
        }

        /**
         * Получает singleton instance менеджера.
         * 
         * @return ContactManager - Единственный экземпляр менеджера
         */
        public static function getInstance():ContactManager {
            if (!_instance) {
                _instance = new ContactManager();
            }
            return _instance;
        }

        /**
         * Регистрирует контакт в системе.
         * 
         * @param contact - Контакт для регистрации
         */
        public function registerContact(contact:Contact):void {
            if (!_contactsById[contact.id]) {
                _allContacts.push(contact);
                _contactsById[contact.id] = contact;
                trace("ContactManager: Registered contact - " + contact.name + " (" + contact.type + ")");
            }
        }

        /**
         * Удаляет контакт из системы.
         * 
         * @param contact - Контакт для удаления
         */
        public function unregisterContact(contact:Contact):void {
            var index:int = _allContacts.indexOf(contact);
            if (index !== -1) {
                _allContacts.splice(index, 1);
            }
            
            if (_contactsById[contact.id]) {
                delete _contactsById[contact.id];
            }
            
            trace("ContactManager: Unregistered contact - " + contact.name);
        }

        /**
         * Находит контакт по ID.
         * 
         * @param contactId - ID контакта
         * @return Contact - Найденный контакт или null
         */
        public function findContactById(contactId:String):Contact {
            return _contactsById[contactId] as Contact;
        }

        /**
         * Проверяет, создаст ли соединение циклическую зависимость.
         * 
         * @param fromContact - Исходный контакт
         * @param toContact - Целевой контакт
         * @return Boolean - True если создаст цикл
         */
        public function wouldCreateCycle(fromContact:Contact, toContact:Contact):Boolean {
            // Базовые проверки
            if (!fromContact || !toContact) return true;
            if (fromContact === toContact) return true;
            
            // Нельзя соединять контакты одного атома
            if (fromContact.atom && toContact.atom && fromContact.atom.id === toContact.atom.id) {
                return true;
            }
            
            // Проверяем рекурсивно все подключения
            return checkForCycle(toContact, fromContact);
        }

        /**
         * Рекурсивно проверяет наличие циклов в графе подключений.
         * 
         * @param current - Текущий контакт для проверки
         * @param target - Целевой контакт, который пытаемся подключить
         * @param visited - Посещенные контакты (для рекурсии)
         * @return Boolean - True если найден цикл
         */
        private function checkForCycle(current:Contact, target:Contact, visited:Dictionary = null):Boolean {
            if (!visited) visited = new Dictionary();
            
            // Если уже посещали этот контакт - цикл найден
            if (visited[current]) return false;
            visited[current] = true;
            
            // Если нашли целевой контакт - цикл
            if (current === target) return true;
            
            // Рекурсивно проверяем все подключения текущего контакта
            if (current.type === Contact.TYPE_OUTPUT) {
                for each (var subscriber:Contact in current.subscribers) {
                    if (checkForCycle(subscriber, target, visited)) {
                        return true;
                    }
                }
            } else if (current.source) {
                if (checkForCycle(current.source, target, visited)) {
                    return true;
                }
            }
            
            return false;
        }

        /**
         * Получает статистику по системе контактов.
         * 
         * @return Object - Объект со статистикой
         */
        public function getStats():Object {
            var inputCount:int = 0;
            var outputCount:int = 0;
            var connectedInputs:int = 0;
            var connectedOutputs:int = 0;
            var totalConnections:int = 0;

            for each (var contact:Contact in _allContacts) {
                if (contact.type === Contact.TYPE_INPUT) {
                    inputCount++;
                    if (contact.isConnected) connectedInputs++;
                } else if (contact.type === Contact.TYPE_OUTPUT) {
                    outputCount++;
                    if (contact.isConnected) connectedOutputs++;
                    totalConnections += contact.subscribers.length;
                }
            }

            return {
                totalContacts: _allContacts.length,
                inputContacts: inputCount,
                outputContacts: outputCount,
                connectedInputs: connectedInputs,
                connectedOutputs: connectedOutputs,
                totalConnections: totalConnections,
                connectionRatio: outputCount > 0 ? (totalConnections / outputCount).toFixed(2) : "0.00"
            };
        }

        /**
         * Очищает все зарегистрированные контакты (для тестирования).
         */
        public function clearAll():void {
            _allContacts = new Vector.<Contact>();
            _contactsById = new Dictionary();
            trace("ContactManager: Cleared all contacts");
        }

        /**
         * Получает все зарегистрированные контакты.
         * 
         * @return Vector.<Contact> - Все контакты
         */
        public function getAllContacts():Vector.<Contact> {
            return _allContacts.slice();
        }
    }
}