package Src.Atom.Core {
    import flash.geom.Point;
    import Src.Contact.Core.Contact;
    import Src.Impulsys.Impulsys;
    import Src.Impulsys.Impulse;
    import Src.Atom.Data.AtomDefinitions;
    import Src.Managers.AtomManager;

    public class Atom {
        public var id:String;
        public var position:Point;
        public var name:String;
        public var type:String;
        public var data:Object;
        public var contactInputs:Array;
        public var contactOutputs:Array;

        public function Atom(id:String, type:String, position:Point, name:String = null) {
            this.id = id;
            this.type = type;
            this.position = position.clone();
            this.name = name || type;
            this.data = new Object();
            this.contactInputs = new Array();
            this.contactOutputs = new Array();
        }

        public function setPosition(newPosition:Point):Atom {
            var newAtom:Atom = new Atom(id, type, newPosition, name);
            newAtom.data = cloneData(this.data);
            newAtom.contactInputs = this.contactInputs.slice();
            newAtom.contactOutputs = this.contactOutputs.slice();
            setOwnerForAllContacts(newAtom);
            return newAtom;
        }

        private function setOwnerForAllContacts(atom:Atom):void {
            for each (var inputContact:Contact in atom.contactInputs) {
                inputContact.setOwnerAtom(atom);
            }
            for each (var outputContact:Contact in atom.contactOutputs) {
                outputContact.setOwnerAtom(atom);
            }
        }

        public function setContactValue(contactName:String, value:*, isInput:Boolean = true):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            newAtom.data = cloneData(this.data);
            var contactUpdated:Boolean = false;
            var contacts:Array = isInput ? newAtom.contactInputs : newAtom.contactOutputs;

            for each (var contact:Contact in contacts) {
                if (contact.name == contactName) {
                    contact.value = value;
                    contactUpdated = true;
                    break;
                }
            }

            return newAtom;
        }

        public function setData(key:String, value:*):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            newAtom.data = cloneData(this.data);
            newAtom.data[key] = value;
            return newAtom;
        }

        public function hasValue(key:String):Boolean {
            return this.data.hasOwnProperty(key);
        }

        public function getContactByName(name:String, isInput:Boolean = true):Contact {
            var contacts:Array = isInput ? this.contactInputs : this.contactOutputs;
            for each (var contact:Contact in contacts) {
                if (contact.name == name) {
                    return contact;
                }
            }
            return null;
        }

        public function addContact(contact:Contact):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            contact.setOwnerAtom(newAtom);

            if (contact.type === Contact.TYPE_INPUT) {
                newAtom.contactInputs.push(contact);
            } else {
                newAtom.contactOutputs.push(contact);
            }

            return newAtom;
        }

        public function removeContact(contactName:String, isInput:Boolean = true):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            var contacts:Array = isInput ? newAtom.contactInputs : newAtom.contactOutputs;

            for (var i:int = contacts.length - 1; i >= 0; i--) {
                if (Contact(contacts[i]).name == contactName) {
                    Contact(contacts[i]).dispose();
                    contacts.splice(i, 1);
                }
            }

            return newAtom;
        }

        public function connectTo(targetAtom:Atom, sourceContactName:String, targetContactName:String):Boolean {
            var sourceContact:Contact = this.getContactByName(sourceContactName, false);
            var targetContact:Contact = targetAtom.getContactByName(targetContactName, true);

            if (!sourceContact || !targetContact) {
                return false;
            }

            return targetContact.subscribeTo(sourceContact);
        }

        public function disposeContacts():void {
            for each (var inputContact:Contact in this.contactInputs) {
                inputContact.unsubscribe();
                inputContact.dispose();
            }

            for each (var outputContact:Contact in this.contactOutputs) {
                outputContact.unsubscribe();
                outputContact.dispose();
            }

            this.contactInputs = new Array();
            this.contactOutputs = new Array();
        }

        public function getContactsStats():Object {
            var connectedInputs:int = 0;
            var connectedOutputs:int = 0;
            var totalConnections:int = 0;

            for each (var input:Contact in contactInputs) {
                if (input.isConnected) connectedInputs++;
            }

            for each (var output:Contact in contactOutputs) {
                if (output.isConnected) {
                    connectedOutputs++;
                    totalConnections += output.subscribers.length;
                }
            }

            return {
                totalContacts: contactInputs.length + contactOutputs.length,
                inputContacts: contactInputs.length,
                outputContacts: contactOutputs.length,
                connectedInputs: connectedInputs,
                connectedOutputs: connectedOutputs,
                totalConnections: totalConnections,
                connectionRatio: contactOutputs.length > 0 ? (totalConnections / contactOutputs.length).toFixed(2) : "0.00"
            };
        }

        private function cloneData(original:Object):Object {
            var cloned:Object = {};
            for (var key:String in original) {
                cloned[key] = original[key];
            }
            return cloned;
        }

        public function toString():String {
            return "Atom{id:" + this.id + ", name:" + this.name + ", type:" + this.type + ", contacts:" + (this.contactInputs.length + this.contactOutputs.length) + "}";
        }

        public function getDebugInfo():Object {
            return {
                id: this.id,
                name: this.name,
                type: this.type,
                position: {x: this.position.x, y: this.position.y},
                contacts: {
                    inputs: getContactInfo(this.contactInputs),
                    outputs: getContactInfo(this.contactOutputs)
                },
                data: cloneData(this.data)
            };

            function getContactInfo(contacts:Array):Array {
                var info:Array = [];
                for each (var contact:Contact in contacts) {
                    info.push({
                        name: contact.name,
                        id: contact.id,
                        value: contact.value,
                        isConnected: contact.isConnected,
                        subscribers: contact.subscribers.length
                    });
                }
                return info;
            }
        }

        public function triggerUpdate():void {
            Impulsys.emit(new Impulse("ATOM_UPDATED", {
                atom: this,
                timestamp: new Date().getTime()
            }));
        }

        public function getContactValue(contactName:String, isInput:Boolean = true):* {
            var contact:Contact = getContactByName(contactName, isInput);
            return contact ? contact.value : undefined;
        }

        public function hasContact(contactName:String, isInput:Boolean = true):Boolean {
            return getContactByName(contactName, isInput) !== null;
        }

        public function getAllContacts():Array {
            var allContacts:Array = new Array();
            allContacts = allContacts.concat(this.contactInputs);
            allContacts = allContacts.concat(this.contactOutputs);
            return allContacts;
        }

        public function resetAllValues():Atom {
            var newAtom:Atom = this.setPosition(this.position);

            for each (var inputContact:Contact in newAtom.contactInputs) {
                inputContact.value = getDefaultValue(inputContact.data.dataType);
            }
            for each (var outputContact:Contact in newAtom.contactOutputs) {
                outputContact.value = getDefaultValue(outputContact.data.dataType);
            }

            return newAtom;
        }

        private function getDefaultValue(dataType:String):* {
            switch(dataType) {
                case "boolean": return false;
                case "number": return 0;
                case "string": return "";
                case "impulse": return null;
                default: return null;
            }
        }
    }
}
