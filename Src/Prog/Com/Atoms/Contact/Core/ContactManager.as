package Src.Prog.Com.Atoms.Contact.Core {
    import flash.utils.Dictionary;

    public class ContactManager {
        private static var _instance:ContactManager;
        private var _allContacts:Vector.<Contact>;
        private var _contactsById:Dictionary;

        public function ContactManager() {
            if (_instance) {
                throw new Error("ContactManager is singleton. Use getInstance() instead.");
            }

            _allContacts = new Vector.<Contact>();
            _contactsById = new Dictionary();
        }

        public static function getInstance():ContactManager {
            if (!_instance) {
                _instance = new ContactManager();
            }
            return _instance;
        }

        public function registerContact(contact:Contact):void {
            if (!_contactsById[contact.id]) {
                _allContacts.push(contact);
                _contactsById[contact.id] = contact;
            }
        }

        public function unregisterContact(contact:Contact):void {
            var index:int = _allContacts.indexOf(contact);
            if (index !== -1) {
                _allContacts.splice(index, 1);
            }

            if (_contactsById[contact.id]) {
                delete _contactsById[contact.id];
            }
        }

        public function findContactById(contactId:String):Contact {
            return _contactsById[contactId] as Contact;
        }

        public function wouldCreateCycle(fromContact:Contact, toContact:Contact):Boolean {
            if (!fromContact || !toContact) return true;
            if (fromContact === toContact) return true;

            if (fromContact.atom && toContact.atom && fromContact.atom.id === toContact.atom.id) {
                return true;
            }

            return checkForCycle(toContact, fromContact);
        }

        private function checkForCycle(current:Contact, target:Contact, visited:Dictionary = null):Boolean {
            if (!visited) visited = new Dictionary();

            if (visited[current]) return false;
            visited[current] = true;

            if (current === target) return true;

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

        public function clearAll():void {
            _allContacts = new Vector.<Contact>();
            _contactsById = new Dictionary();
        }

        public function getAllContacts():Vector.<Contact> {
            return _allContacts.slice();
        }
    }
}
