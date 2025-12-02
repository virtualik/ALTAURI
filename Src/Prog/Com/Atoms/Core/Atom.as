package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Core.Managers.AtomManager;

    /**
     * Universal immutable atom class - расширен для параллельной работы Pin и Contact систем.
     * Теперь атомы имеют ДВА НЕЗАВИСИМЫХ набора контактов:
     * 1. Старая система: inputs и outputs (Pin)
     * 2. Новая система: contactInputs и contactOutputs (Contact)
     */
    public class Atom {
        /** Unique identifier for the atom */
        public var id:String;
        /** Position on the canvas in world coordinates */
        public var position:Point;
        /** Display name shown in the UI */
        public var name:String;
        /** Atom type identifier (e.g., "Button", "Counter") */
        public var type:String;
        /** Dynamic data storage for atom-specific properties and state */
        public var data:Object;

        /** Collection of input pins (СТАРАЯ СИСТЕМА) */
        public var inputs:Vector.<Pin>;
        /** Collection of output pins (СТАРАЯ СИСТЕМА) */
        public var outputs:Vector.<Pin>;

        /** Collection of input contacts (НОВАЯ СИСТЕМА) */
        public var contactInputs:Vector.<Contact>;
        /** Collection of output contacts (НОВАЯ СИСТЕМА) */
        public var contactOutputs:Vector.<Contact>;

        /**
         * Creates a new Atom instance.
         */
        public function Atom(id:String, type:String, position:Point, name:String = null) {
            this.id = id;
            this.type = type;
            this.position = position.clone();
            this.name = name || type;
            this.data = new Object();

            // Инициализируем обе системы параллельно
            this.inputs = new Vector.<Pin>();
            this.outputs = new Vector.<Pin>();
            this.contactInputs = new Vector.<Contact>();
            this.contactOutputs = new Vector.<Contact>();
            
            trace("🔧 Atom created: " + this.name + " (" + this.id + ") with dual contact systems");
        }

        /**
         * Создает копию Atom с сохранением обеих систем контактов.
         */
        public function setPosition(newPosition:Point):Atom {
            var newAtom:Atom = new Atom(id, type, newPosition, name);
            newAtom.data = cloneData(this.data);

            // Копируем старые Pin'ы
            newAtom.inputs = this.inputs.slice();
            newAtom.outputs = this.outputs.slice();

            // Копируем новые Contact'ы
            newAtom.contactInputs = this.contactInputs.slice();
            newAtom.contactOutputs = this.contactOutputs.slice();

            // Восстанавливаем связи владельца для всех пинов и контактов
            setOwnerForAllPins(newAtom);
            setOwnerForAllContacts(newAtom);

            trace("📍 Atom position updated: " + this.name + " → " + newPosition);
            return newAtom;
        }

        /**
         * Устанавливает владельца для всех пинов (для копий атомов).
         */
        private function setOwnerForAllPins(atom:Atom):void {
            for each (var inputPin:Pin in atom.inputs) {
                inputPin.setOwnerAtom(atom);
            }
            for each (var outputPin:Pin in atom.outputs) {
                outputPin.setOwnerAtom(atom);
            }
        }

        /**
         * Устанавливает владельца для всех контактов (для копий атомов).
         */
        private function setOwnerForAllContacts(atom:Atom):void {
            for each (var inputContact:Contact in atom.contactInputs) {
                inputContact.setOwnerAtom(atom);
            }
            for each (var outputContact:Contact in atom.contactOutputs) {
                outputContact.setOwnerAtom(atom);
            }
        }

        /**
         * Обновляет значение Pin (СТАРАЯ СИСТЕМА).
         * Автоматически синхронизирует значение с Contact системой.
         * 🔥 ДОБАВЛЕНО: Уведомление поведения атома!
         */
        public function setPinValue(pinName:String, value:*, isInput:Boolean = true):Atom {
            trace("=== ATOM SET PIN VALUE (LEGACY) ===");
            trace("Atom: " + this.id + ", Pin: " + pinName + ", Value: " + value + ", IsInput: " + isInput);

            var newAtom:Atom = this.setPosition(this.position); // Создаем копию атома
            newAtom.data = cloneData(this.data);

            var pinUpdated:Boolean = false;

            // Обновляем значение Pin в старой системе
            var pins:Vector.<Pin> = isInput ? newAtom.inputs : newAtom.outputs;
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    trace("Updating legacy pin: " + pin.name + " to value: " + value);
                    
                    // 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Уведомляем поведение для ВХОДНЫХ пинов
                    if (isInput) {
                        trace("🔄 Notifying atom behavior for INPUT pin");
                        notifyPinBehaviorChange(pinName, value, newAtom);
                    }
                    
                    var oldValue:* = pin.value;
                    pin.value = value; // Это вызовет PinEvent и уведомит подписчиков (Track)
                    pinUpdated = true;
                    
                    trace("📊 Pin value changed: " + oldValue + " → " + value);
                    
                    // Синхронизируем с Contact системой
                    syncPinToContact(newAtom, pinName, value, isInput);
                    break;
                }
            }

            if (!pinUpdated) {
                trace("⚠ Pin not found: " + pinName);
            }

            trace("=== END SET PIN VALUE ===");
            return newAtom;
        }

        /**
         * 🔥 НОВЫЙ МЕТОД: Уведомляет поведение атома об изменении Pin.
         * Аналогично Contact.notifyAtomBehavior().
         */
        private function notifyPinBehaviorChange(pinName:String, value:*, atom:Atom):void {
            trace("🔥🔥🔥 PIN → ATOM BEHAVIOR NOTIFICATION 🔥🔥🔥");
            trace("Pin: " + pinName + " = " + value);
            trace("Atom: " + atom.name + " (" + atom.type + ") id: " + atom.id);
            
            // Получаем определение атома
            var definition:Object = AtomDefinitions.getAtomDefinition(atom.type);
            if (!definition) {
                trace("⚠ No definition found for atom type: " + atom.type);
                return;
            }
            
            if (!definition.behavior) {
                trace("⚠ No behavior defined for atom: " + atom.type);
                return;
            }
            
            if (!definition.behavior.onInputChange || !(definition.behavior.onInputChange is Function)) {
                trace("⚠ onInputChange not a function for atom: " + atom.type);
                return;
            }
            
            // Вызываем поведение
            trace("📢 Calling behavior.onInputChange for pin: " + pinName);
            try {
                var newAtom:Atom = definition.behavior.onInputChange(atom, pinName, value);
                
                // Обновляем атом через менеджер
                if (newAtom !== atom) {
                    // Копируем обновленные данные обратно
                    atom.data = cloneData(newAtom.data);
                    trace("✅ Atom data updated via pin behavior");
                    
                    // Триггерим обновление через менеджер
                    if (AtomManager.getInstance().getAtomById(atom.id)) {
						AtomManager.getInstance().updateAtom(atom);
					} else {
						trace("⚠ Atom not registered in AtomManager yet (initialization phase)");
					}
                    trace("✅ AtomManager.updateAtom called");
                } else {
                    trace("⚠ Atom not changed by behavior");
                }
            } catch (error:Error) {
                trace("❌ ERROR in behavior.onInputChange: " + error.message);
                trace(error.getStackTrace());
            }
            
            trace("🔥🔥🔥 PIN BEHAVIOR NOTIFICATION COMPLETE 🔥🔥🔥");
        }

        /**
         * Обновляет значение Contact (НОВАЯ СИСТЕМА).
         * Автоматически синхронизирует значение с Pin системой.
         */
        public function setContactValue(contactName:String, value:*, isInput:Boolean = true):Atom {
            trace("=== ATOM SET CONTACT VALUE (NEW) ===");
            trace("Atom: " + this.id + ", Contact: " + contactName + ", Value: " + value + ", IsInput: " + isInput);

            var newAtom:Atom = this.setPosition(this.position); // Создаем копию атома
            newAtom.data = cloneData(this.data);

            var contactUpdated:Boolean = false;

            // Обновляем значение Contact в новой системе
            var contacts:Vector.<Contact> = isInput ? newAtom.contactInputs : newAtom.contactOutputs;
            for each (var contact:Contact in contacts) {
                if (contact.name == contactName) {
                    trace("Updating new contact: " + contact.name + " to value: " + value);
                    
                    var oldValue:* = contact.value;
                    contact.value = value; // Это вызовет ContactEvent и уведомит подписчиков (Link)
                    contactUpdated = true;
                    
                    trace("📊 Contact value changed: " + oldValue + " → " + value);
                    
                    // Синхронизируем с Pin системой
                    syncContactToPin(newAtom, contactName, value, isInput);
                    break;
                }
            }

            if (!contactUpdated) {
                trace("⚠ Contact not found: " + contactName);
            }

            trace("=== END SET CONTACT VALUE ===");
            return newAtom;
        }

        /**
         * Синхронизирует значение из Pin системы в Contact систему.
         */
        private function syncPinToContact(atom:Atom, pinName:String, value:*, isInput:Boolean):void {
            var contacts:Vector.<Contact> = isInput ? atom.contactInputs : atom.contactOutputs;
            for each (var contact:Contact in contacts) {
                if (contact.name == pinName) {
                    trace("🔄 Syncing pin → contact: " + pinName + " = " + value);
                    contact.value = value;
                    break;
                }
            }
        }

        /**
         * Синхронизирует значение из Contact системы в Pin систему.
         */
        private function syncContactToPin(atom:Atom, contactName:String, value:*, isInput:Boolean):void {
            var pins:Vector.<Pin> = isInput ? atom.inputs : atom.outputs;
            for each (var pin:Pin in pins) {
                if (pin.name == contactName) {
                    trace("🔄 Syncing contact → pin: " + contactName + " = " + value);
                    
                    // 🔥 ВАЖНО: Для входных пинов НЕ вызываем notifyPinBehaviorChange
                    // чтобы избежать двойного вызова поведения
                    if (isInput) {
                        trace("⚠ Skipping pin behavior notification (already handled by contact)");
                    }
                    
                    pin.value = value;
                    break;
                }
            }
        }

        /**
         * Устанавливает данные атома (общий метод для обеих систем).
         */
        public function setData(key:String, value:*):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            newAtom.data = cloneData(this.data);
            newAtom.data[key] = value;
            
            trace("📝 Atom data set: " + key + " = " + value);
            return newAtom;
        }

        /**
         * Проверяет наличие значения в данных атома.
         */
        public function hasValue(key:String):Boolean {
            return this.data.hasOwnProperty(key);
        }

        /**
         * Получает Contact по имени и типу.
         */
        public function getContactByName(name:String, isInput:Boolean = true):Contact {
            var contacts:Vector.<Contact> = isInput ? this.contactInputs : this.contactOutputs;
            for each (var contact:Contact in contacts) {
                if (contact.name == name) {
                    return contact;
                }
            }
            return null;
        }

        /**
         * Получает Pin по имени и типу.
         */
        public function getPinByName(name:String, isInput:Boolean = true):Pin {
            var pins:Vector.<Pin> = isInput ? this.inputs : this.outputs;
            for each (var pin:Pin in pins) {
                if (pin.name == name) {
                    return pin;
                }
            }
            return null;
        }

        /**
         * Добавляет Pin в атом (для динамического создания пинов).
         */
        public function addPin(pin:Pin, isInput:Boolean = true):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            pin.setOwnerAtom(newAtom);
            
            if (isInput) {
                newAtom.inputs.push(pin);
                // Создаем соответствующий Contact
                var contact:Contact = new Contact(pin.name, Contact.TYPE_INPUT, pin.value, pin.data);
                contact.setOwnerAtom(newAtom);
                newAtom.contactInputs.push(contact);
            } else {
                newAtom.outputs.push(pin);
                // Создаем соответствующий Contact
                contact = new Contact(pin.name, Contact.TYPE_OUTPUT, pin.value, pin.data);
                contact.setOwnerAtom(newAtom);
                newAtom.contactOutputs.push(contact);
            }
            
            trace("➕ Added pin: " + pin.name + " (created parallel contact)");
            return newAtom;
        }

        /**
         * Добавляет Contact в атом (для динамического создания контактов).
         */
        public function addContact(contact:Contact):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            contact.setOwnerAtom(newAtom);
            
            if (contact.type === Contact.TYPE_INPUT) {
                newAtom.contactInputs.push(contact);
                // Создаем соответствующий Pin
                var pin:Pin = new Pin(contact.name, "input", contact.value, contact.data);
                pin.setOwnerAtom(newAtom);
                newAtom.inputs.push(pin);
            } else {
                newAtom.contactOutputs.push(contact);
                // Создаем соответствующий Pin
                pin = new Pin(contact.name, "output", contact.value, contact.data);
                pin.setOwnerAtom(newAtom);
                newAtom.outputs.push(pin);
            }
            
            trace("➕ Added contact: " + contact.name + " (created parallel pin)");
            return newAtom;
        }

        /**
         * Удаляет Pin и соответствующий Contact.
         */
        public function removePin(pinName:String, isInput:Boolean = true):Atom {
            var newAtom:Atom = this.setPosition(this.position);
            
            // Удаляем Pin
            var pins:Vector.<Pin> = isInput ? newAtom.inputs : newAtom.outputs;
            for (var i:int = pins.length - 1; i >= 0; i--) {
                if (pins[i].name == pinName) {
                    pins[i].dispose();
                    pins.splice(i, 1);
                    trace("🗑️ Removed pin: " + pinName);
                }
            }
            
            // Удаляем соответствующий Contact
            var contacts:Vector.<Contact> = isInput ? newAtom.contactInputs : newAtom.contactOutputs;
            for (i = contacts.length - 1; i >= 0; i--) {
                if (contacts[i].name == pinName) {
                    contacts[i].dispose();
                    contacts.splice(i, 1);
                    trace("🗑️ Removed parallel contact: " + pinName);
                }
            }
            
            return newAtom;
        }

        /**
         * Создает соединение между двумя атомами через Contact систему.
         */
        public function connectTo(targetAtom:Atom, sourceContactName:String, targetContactName:String):Boolean {
            var sourceContact:Contact = this.getContactByName(sourceContactName, false);
            var targetContact:Contact = targetAtom.getContactByName(targetContactName, true);
            
            if (!sourceContact || !targetContact) {
                trace("❌ Connection failed: contacts not found");
                return false;
            }
            
            return targetContact.subscribeTo(sourceContact);
        }

        /**
         * Освобождает ресурсы обеих систем при удалении атома.
         */
        public function disposeContacts():void {
            trace("🧹 Disposing contacts for atom: " + this.name);

            // Освобождаем все Contact соединения
            for each (var inputContact:Contact in this.contactInputs) {
                inputContact.unsubscribe();
                inputContact.dispose();
            }
            
            for each (var outputContact:Contact in this.contactOutputs) {
                outputContact.unsubscribe();
                outputContact.dispose();
            }

            // Освобождаем все Pin соединения
            for each (var inputPin:Pin in this.inputs) {
                inputPin.dispose();
            }
            
            for each (var outputPin:Pin in this.outputs) {
                outputPin.dispose();
            }

            // Очищаем коллекции
            this.contactInputs = new Vector.<Contact>();
            this.contactOutputs = new Vector.<Contact>();
            this.inputs = new Vector.<Pin>();
            this.outputs = new Vector.<Pin>();
            
            trace("✅ Atom contacts disposed: " + this.name);
        }

        /**
         * Получает статистику по обеим системам контактов.
         */
        public function getContactsStats():Object {
            return {
                totalPins: this.inputs.length + this.outputs.length,
                inputPins: this.inputs.length,
                outputPins: this.outputs.length,
                totalContacts: this.contactInputs.length + this.contactOutputs.length,
                inputContacts: this.contactInputs.length,
                outputContacts: this.contactOutputs.length,
                pinConnections: countPinConnections(),
                contactConnections: countContactConnections()
            };
            
            function countPinConnections():int {
                var count:int = 0;
                for each (var output:Pin in outputs) {
                    // Проверяем, подключен ли пин
                    if (output["_targetedSubscriptions"]) {
                        count += output["_targetedSubscriptions"].length;
                    }
                }
                return count;
            }
            
            function countContactConnections():int {
                var count:int = 0;
                for each (var output:Contact in contactOutputs) {
                    if (output.isConnected) {
                        count += output.subscribers.length;
                    }
                }
                return count;
            }
        }

        /**
         * Клонирует данные объекта.
         */
        private function cloneData(original:Object):Object {
            var cloned:Object = {};
            for (var key:String in original) {
                cloned[key] = original[key];
            }
            return cloned;
        }

        /**
         * Получает строковое представление атома.
         */
        public function toString():String {
            return "Atom{id:" + this.id + 
                   ", name:" + this.name + 
                   ", type:" + this.type + 
                   ", pins:" + (this.inputs.length + this.outputs.length) + 
                   ", contacts:" + (this.contactInputs.length + this.contactOutputs.length) + 
                   "}";
        }

        /**
         * Получает информацию об атоме для отладки.
         */
        public function getDebugInfo():Object {
            return {
                id: this.id,
                name: this.name,
                type: this.type,
                position: {x: this.position.x, y: this.position.y},
                pins: {
                    inputs: getPinInfo(this.inputs),
                    outputs: getPinInfo(this.outputs)
                },
                contacts: {
                    inputs: getContactInfo(this.contactInputs),
                    outputs: getContactInfo(this.contactOutputs)
                },
                data: cloneData(this.data)
            };
            
            function getPinInfo(pins:Vector.<Pin>):Array {
                var info:Array = [];
                for each (var pin:Pin in pins) {
                    info.push({
                        name: pin.name,
                        id: pin.id,
                        value: pin.value,
                        isConnected: pin.hasOwnProperty("_targetedSubscriptions") && pin["_targetedSubscriptions"].length > 0
                    });
                }
                return info;
            }
            
            function getContactInfo(contacts:Vector.<Contact>):Array {
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

        /**
         * Триггерит событие обновления атома.
         */
        public function triggerUpdate():void {
            Impulsys.emit(new Impulse("ATOM_UPDATED", {
                atom: this,
                timestamp: new Date().getTime()
            }));
            
            trace("🔄 Atom update triggered: " + this.name);
        }

        /**
         * Получает значение Pin по имени.
         */
        public function getPinValue(pinName:String, isInput:Boolean = true):* {
            var pin:Pin = getPinByName(pinName, isInput);
            return pin ? pin.value : undefined;
        }

        /**
         * Получает значение Contact по имени.
         */
        public function getContactValue(contactName:String, isInput:Boolean = true):* {
            var contact:Contact = getContactByName(contactName, isInput);
            return contact ? contact.value : undefined;
        }

        /**
         * Проверяет, есть ли у атома указанный Pin.
         */
        public function hasPin(pinName:String, isInput:Boolean = true):Boolean {
            return getPinByName(pinName, isInput) !== null;
        }

        /**
         * Проверяет, есть ли у атома указанный Contact.
         */
        public function hasContact(contactName:String, isInput:Boolean = true):Boolean {
            return getContactByName(contactName, isInput) !== null;
        }

        /**
         * Получает все пины атома (входы и выходы вместе).
         */
        public function getAllPins():Vector.<Pin> {
            var allPins:Vector.<Pin> = new Vector.<Pin>();
            allPins = allPins.concat(this.inputs);
            allPins = allPins.concat(this.outputs);
            return allPins;
        }

        /**
         * Получает все контакты атома (входы и выходы вместе).
         */
        public function getAllContacts():Vector.<Contact> {
            var allContacts:Vector.<Contact> = new Vector.<Contact>();
            allContacts = allContacts.concat(this.contactInputs);
            allContacts = allContacts.concat(this.contactOutputs);
            return allContacts;
        }

        /**
         * Сбрасывает все значения пинов и контактов к значениям по умолчанию.
         */
        public function resetAllValues():Atom {
            var newAtom:Atom = this.setPosition(this.position);
            
            // Сбрасываем пины
            for each (var inputPin:Pin in newAtom.inputs) {
                inputPin.value = getDefaultValue(inputPin.data.dataType);
            }
            for each (var outputPin:Pin in newAtom.outputs) {
                outputPin.value = getDefaultValue(outputPin.data.dataType);
            }
            
            // Сбрасываем контакты
            for each (var inputContact:Contact in newAtom.contactInputs) {
                inputContact.value = getDefaultValue(inputContact.data.dataType);
            }
            for each (var outputContact:Contact in newAtom.contactOutputs) {
                outputContact.value = getDefaultValue(outputContact.data.dataType);
            }
            
            trace("🔄 All pin/contact values reset for atom: " + this.name);
            return newAtom;
        }

        /**
         * Получает значение по умолчанию для типа данных.
         */
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