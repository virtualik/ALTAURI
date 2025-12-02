package Src.Prog.Com.Atoms.Contact.Core {
    import flash.events.EventDispatcher;
    import Src.Prog.Com.Atoms.Contact.Core.ContactEvent;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Core.Managers.AtomManager;

    /**
     * Упрощенный аналог Pin - представляет точку подключения для передачи данных между атомами.
     * Основное правило: Один выход → Много входов. Один вход → Один выход.
     * 
     * @class Contact
     * @extends EventDispatcher
     */
    public class Contact extends EventDispatcher {
        
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";
        public static const VALUE_CHANGED:String = "contactValueChanged";
        public static const CONNECTED:String = "contactConnected";
        public static const DISCONNECTED:String = "contactDisconnected";

        // =============================================================================
        // PROPERTIES
        // =============================================================================
        public var id:String;
        public var name:String;
        public var type:String; // "input" или "output"
        public var data:Object; // Дополнительные метаданные

        private var _value:*;
        private var _atom:Atom; // Родительский атом
        private var _subscribers:Vector.<Contact>; // Для ВЫХОДА: кто на меня подписан
        private var _source:Contact;               // Для ВХОДА: на кого я подписан

        // =============================================================================
        // CONSTRUCTOR
        // =============================================================================
        public function Contact(name:String, type:String, value:* = null, data:Object = null) {
            super();
            
            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value;
            this.data = data || {};
            
            _subscribers = new Vector.<Contact>();
            
            // Регистрируем в менеджере
            ContactManager.getInstance().registerContact(this);
            
            trace("🔗 Contact created: " + this.name + " (" + this.type + ") id: " + this.id);
        }

        // =============================================================================
        // VALUE MANAGEMENT
        // =============================================================================
        public function get value():* { 
            return _value; 
        }
        
        public function set value(newValue:*):void {
            if (_value === newValue) return;
            
            trace("🔔 Contact.value SETTER: " + this.name + " = " + newValue + " (old: " + _value + ")");
            var oldValue:* = _value;
            _value = newValue;
            
            // Уведомляем подписчиков (для выходов)
            if (type === TYPE_OUTPUT) {
                notifySubscribers(newValue, oldValue);
            }
            
            // 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Если это ВХОД, уведомляем поведение атома!
            if (type === TYPE_INPUT && _atom) {
                notifyAtomBehavior(newValue, oldValue);
            }
            
            // Отправляем событие
            dispatchEvent(new ContactEvent(VALUE_CHANGED, this, newValue, oldValue));
        }

        // =============================================================================
        // ATOM BEHAVIOR NOTIFICATION
        // =============================================================================
        /**
         * Уведомляет родительский атом об изменении значения контакта.
         * Аналогично тому, как Pin система вызывает onInputChange в поведении.
         */
        private function notifyAtomBehavior(newValue:*, oldValue:*):void {
            trace("🔥 CONTACT → ATOM BEHAVIOR NOTIFICATION 🔥");
            trace("Contact: " + this.name + " = " + newValue);
            trace("Atom: " + (_atom ? _atom.name + " (" + _atom.type + ")" : "null"));
            
            if (!_atom) {
                trace("⚠ No atom associated with contact");
                return;
            }
            
            // Получаем определение атома
            var definition:Object = AtomDefinitions.getAtomDefinition(_atom.type);
            if (!definition) {
                trace("⚠ No definition found for atom type: " + _atom.type);
                return;
            }
            
            if (!definition.behavior) {
                trace("⚠ No behavior defined for atom: " + _atom.type);
                return;
            }
            
            if (!definition.behavior.onInputChange || !(definition.behavior.onInputChange is Function)) {
                trace("⚠ onInputChange not a function for atom: " + _atom.type);
                return;
            }
            
            // Вызываем поведение
            trace("📢 Calling behavior.onInputChange for contact: " + this.name);
            try {
                var newAtom:Atom = definition.behavior.onInputChange(_atom, this.name, newValue);
                
                // Обновляем атом через менеджер
                if (newAtom !== _atom) {
                    AtomManager.getInstance().updateAtom(newAtom);
                    trace("✅ Atom updated via contact behavior");
                } else {
                    trace("⚠ Atom not changed by behavior");
                }
            } catch (error:Error) {
                trace("❌ ERROR in behavior.onInputChange: " + error.message);
                trace(error.getStackTrace());
            }
            
            trace("🔥 CONTACT BEHAVIOR NOTIFICATION COMPLETE 🔥");
        }

        // =============================================================================
        // SUBSCRIPTION MANAGEMENT
        // =============================================================================
        /**
         * Подписывает этот контакт на целевой контакт.
         * Только ВХОД может подписаться на ВЫХОД.
         * 
         * @param targetContact - Контакт, на который подписываемся
         * @return Boolean - Успешно ли выполнена подписка
         */
        public function subscribeTo(targetContact:Contact):Boolean {
            trace("=== CONTACT SUBSCRIBE TO ===");
            trace("Subscriber: " + this.name + " (" + this.type + ")");
            trace("Target: " + targetContact.name + " (" + targetContact.type + ")");
            
            // Проверяем базовые условия
            if (!targetContact || targetContact === this) {
                trace("❌ Invalid target or self-subscription");
                return false;
            }
            
            // Только input → output разрешено
            if (this.type !== TYPE_INPUT || targetContact.type !== TYPE_OUTPUT) {
                trace("❌ Invalid subscription type (only input → output allowed)");
                return false;
            }
            
            // Вход уже имеет источник - отписываемся сначала
            if (this._source) {
                trace("⚠ Already has source, unsubscribing first");
                this.unsubscribe();
            }
            
            // Проверяем, что не создаем циклических связей
            if (wouldCreateCycle(this, targetContact)) {
                trace("❌ Would create cycle");
                return false;
            }
            
            // Добавляем в подписчики выхода
            if (targetContact._subscribers.indexOf(this) === -1) {
                targetContact._subscribers.push(this);
                trace("✓ Added to target subscribers");
            }
            
            // Устанавливаем источник для входа
            this._source = targetContact;
            trace("✓ Source set for input contact");
            
            // Уведомляем о подключении
            this.notifyConnected();
            targetContact.notifyConnected();
            
            // 🔥 НЕМЕДЛЕННАЯ ПЕРЕДАЧА ТЕКУЩЕГО ЗНАЧЕНИЯ
            if (targetContact.value !== undefined && targetContact.value !== null) {
                trace("➡️ Propagating initial value: " + targetContact.value);
                this.value = targetContact.value;
            }
            
            trace("=== SUBSCRIPTION SUCCESSFUL ===");
            return true;
        }
        
        /**
         * Отписывает этот контакт от текущего источника (для входов)
         * или удаляет всех подписчиков (для выходов).
         */
        public function unsubscribe():void {
            trace("=== CONTACT UNSUBSCRIBE ===");
            trace("Contact: " + this.name + " (" + this.type + ")");
            
            if (type === TYPE_INPUT) {
                // Для входа: отписываемся от источника
                if (this._source) {
                    var index:int = this._source._subscribers.indexOf(this);
                    if (index !== -1) {
                        this._source._subscribers.splice(index, 1);
                        trace("✓ Removed from source subscribers");
                    }
                    
                    var oldSource:Contact = this._source;
                    this._source = null;
                    
                    // Уведомляем об отключении
                    this.notifyDisconnected();
                    oldSource.notifyDisconnected();
                    
                    // Сбрасываем значение при отключении
                    this.value = undefined;
                    trace("✓ Value reset to undefined");
                } else {
                    trace("⚠ No source to unsubscribe from");
                }
            } else {
                // Для выхода: отписываем всех подписчиков
                trace("Output has " + _subscribers.length + " subscribers");
                for each (var subscriber:Contact in _subscribers) {
                    subscriber.unsubscribe();
                }
                _subscribers = new Vector.<Contact>();
                trace("✓ All subscribers removed");
            }
            
            trace("=== UNSUBSCRIBE COMPLETE ===");
        }
        
        /**
         * Добавляет подписчика к этому контакту (только для выходов).
         * Внутренний метод, используется subscribeTo.
         */
        internal function addSubscriber(subscriber:Contact):void {
            if (this.type === TYPE_OUTPUT && _subscribers.indexOf(subscriber) === -1) {
                _subscribers.push(subscriber);
            }
        }
        
        /**
         * Удаляет подписчика из этого контакта (только для выходов).
         */
        internal function removeSubscriber(subscriber:Contact):void {
            var index:int = _subscribers.indexOf(subscriber);
            if (index !== -1) {
                _subscribers.splice(index, 1);
            }
        }

        // =============================================================================
        // NOTIFICATION METHODS
        // =============================================================================
        private function notifySubscribers(newValue:*, oldValue:*):void {
            trace("📤 Contact.notifySubscribers: " + this.name + " → " + _subscribers.length + " subscribers");
            
            for each (var subscriber:Contact in _subscribers) {
                trace("  → Subscriber: " + subscriber.name);
                subscriber.value = newValue; // Прямая передача данных (вызовет notifyAtomBehavior)
            }
        }
        
        private function notifyConnected():void {
            trace("🔗 Contact connected: " + this.name);
            dispatchEvent(new ContactEvent(CONNECTED, this, _value));
        }
        
        private function notifyDisconnected():void {
            trace("🔌 Contact disconnected: " + this.name);
            dispatchEvent(new ContactEvent(DISCONNECTED, this, _value));
        }

        // =============================================================================
        // LIFECYCLE MANAGEMENT
        // =============================================================================
        public function setOwnerAtom(atom:Atom):void {
            _atom = atom;
            trace("👤 Contact " + this.name + " owner set: " + (atom ? atom.name : "null"));
        }
        
        public function get atom():Atom { 
            return _atom; 
        }
        
        public function dispose():void {
            trace("🧹 Disposing contact: " + this.name);
            
            // Отписываем все соединения
            this.unsubscribe();
            
            // Удаляем из менеджера
            ContactManager.getInstance().unregisterContact(this);
            
            // Очищаем ссылки
            _subscribers = null;
            _source = null;
            _atom = null;
            
            trace("✅ Contact disposed: " + this.name);
        }

        // =============================================================================
        // UTILITY METHODS
        // =============================================================================
        private function generateId():String {
            return "contact_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }
        
        private static function wouldCreateCycle(contact:Contact, target:Contact):Boolean {
            // Базовая проверка на циклы: нельзя соединять контакты одного атома
            if (contact.atom && target.atom && contact.atom.id === target.atom.id) {
                trace("❌ Would create cycle: same atom");
                return true;
            }
            
            // TODO: В будущем добавить более сложную проверку на циклические связи
            return false;
        }

        // =============================================================================
        // PUBLIC ACCESSORS
        // =============================================================================
        public function get subscribers():Vector.<Contact> { 
            return _subscribers.slice(); 
        }
        
        public function get source():Contact { 
            return _source; 
        }
        
        public function get isConnected():Boolean {
            if (type === TYPE_INPUT) {
                return _source !== null;
            } else {
                return _subscribers.length > 0;
            }
        }
        
        /**
         * Получает отладочную информацию о контакте.
         */
        public function getDebugInfo():Object {
            return {
                id: this.id,
                name: this.name,
                type: this.type,
                value: this.value,
                atom: this._atom ? this._atom.name + " (" + this._atom.id + ")" : "none",
                subscribers: this._subscribers ? this._subscribers.length : 0,
                source: this._source ? this._source.name : "none",
                isConnected: this.isConnected
            };
        }
    }
}