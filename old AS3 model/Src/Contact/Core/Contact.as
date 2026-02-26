package Src.Contact.Core {
    import Src.Atom.Core.Atom;
    import Src.Atom.Data.AtomDefinitions;
    import Src.Managers.AtomManager;

    public class Contact {
        public static const TYPE_INPUT:String = "input";
        public static const TYPE_OUTPUT:String = "output";

        public var id:String;
        public var name:String;
        public var type:String;
        public var data:Object;
        private var _value:*;
        private var _atom:Atom;
        private var _subscribers:Array;
        private var _source:Contact;
        private var _valueChangedCallbacks:Array;
        private var _connectedCallbacks:Array;
        private var _disconnectedCallbacks:Array;

        public function Contact(name:String, type:String, value:* = null, data:Object = null) {
            this.id = generateId();
            this.name = name;
            this.type = type;
            this._value = value;
            this.data = data || {};
            _subscribers = new Array();
            _valueChangedCallbacks = new Array();
            _connectedCallbacks = new Array();
            _disconnectedCallbacks = new Array();
            ContactManager.getInstance().registerContact(this);
        }

        public function addValueChangedCallback(callback:Function):void {
            if (_valueChangedCallbacks.indexOf(callback) === -1) {
                _valueChangedCallbacks.push(callback);
            }
        }

        public function removeValueChangedCallback(callback:Function):void {
            var index:int = _valueChangedCallbacks.indexOf(callback);
            if (index !== -1) _valueChangedCallbacks.splice(index, 1);
        }

        public function addConnectedCallback(callback:Function):void {
            if (_connectedCallbacks.indexOf(callback) === -1) {
                _connectedCallbacks.push(callback);
            }
        }

        public function removeConnectedCallback(callback:Function):void {
            var index:int = _connectedCallbacks.indexOf(callback);
            if (index !== -1) _connectedCallbacks.splice(index, 1);
        }

        public function addDisconnectedCallback(callback:Function):void {
            if (_disconnectedCallbacks.indexOf(callback) === -1) {
                _disconnectedCallbacks.push(callback);
            }
        }

        public function removeDisconnectedCallback(callback:Function):void {
            var index:int = _disconnectedCallbacks.indexOf(callback);
            if (index !== -1) _disconnectedCallbacks.splice(index, 1);
        }

        private function notifyValueChanged(newValue:*, oldValue:*):void {
            for each (var callback:Function in _valueChangedCallbacks) {
                callback(this, newValue, oldValue);
            }
        }

        private function notifyConnected():void {
            for each (var callback:Function in _connectedCallbacks) {
                callback(this);
            }
        }

        private function notifyDisconnected():void {
            for each (var callback:Function in _disconnectedCallbacks) {
                callback(this);
            }
        }

        public function get value():* {
            return _value;
        }

        public function set value(newValue:*):void {
            if (_value === newValue) return;

            var oldValue:* = _value;
            _value = newValue;

            if (type === TYPE_OUTPUT) {
                notifySubscribers(newValue, oldValue);
            }

            if (type === TYPE_INPUT && _atom) {
                notifyAtomBehavior(newValue, oldValue);
            }

            notifyValueChanged(newValue, oldValue);
        }

        private function notifyAtomBehavior(newValue:*, oldValue:*):void {
            if (!_atom) {
                return;
            }

            var definition:Object = AtomDefinitions.getAtomDefinition(_atom.type);
            if (!definition) {
                return;
            }

            if (!definition.behavior || !definition.behavior.onInputChange || !(definition.behavior.onInputChange is Function)) {
                return;
            }

            try {
                var newAtom:Atom = definition.behavior.onInputChange(_atom, this.name, newValue);

                if (newAtom !== _atom) {
                    AtomManager.getInstance().updateAtom(newAtom);
                }
            } catch (error:Error) {
            }
        }

        public function subscribeTo(targetContact:Contact):Boolean {
            if (!targetContact || targetContact === this) {
                return false;
            }

            if (this.type !== TYPE_INPUT || targetContact.type !== TYPE_OUTPUT) {
                return false;
            }

            if (this._source) {
                this.unsubscribe();
            }

            if (wouldCreateCycle(this, targetContact)) {
                return false;
            }

            if (targetContact._subscribers.indexOf(this) === -1) {
                targetContact._subscribers.push(this);
            }

            this._source = targetContact;

            this.notifyConnected();
            targetContact.notifyConnected();

            if (targetContact.value !== undefined && targetContact.value !== null) {
                this.value = targetContact.value;
            }

            return true;
        }

        public function unsubscribe():void {
            if (type === TYPE_INPUT) {
                if (this._source) {
                    var index:int = this._source._subscribers.indexOf(this);
                    if (index !== -1) {
                        this._source._subscribers.splice(index, 1);
                    }

                    var oldSource:Contact = this._source;
                    this._source = null;

                    this.notifyDisconnected();
                    oldSource.notifyDisconnected();

                    this.value = undefined;
                }
            } else {
                for each (var subscriber:Contact in _subscribers) {
                    subscriber.unsubscribe();
                }
                _subscribers = new Array();
            }
        }

        private function notifySubscribers(newValue:*, oldValue:*):void {
            for each (var subscriber:Contact in _subscribers) {
                subscriber.value = newValue;
            }
        }

        public function setOwnerAtom(atom:Atom):void {
            _atom = atom;
        }

        public function get atom():Atom {
            return _atom;
        }

        public function dispose():void {
            this.unsubscribe();
            _valueChangedCallbacks.length = 0;
            _connectedCallbacks.length = 0;
            _disconnectedCallbacks.length = 0;
            ContactManager.getInstance().unregisterContact(this);
            _subscribers = null;
            _source = null;
            _atom = null;
        }

        private function generateId():String {
            return "contact_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        private static function wouldCreateCycle(contact:Contact, target:Contact):Boolean {
            if (contact.atom && target.atom && contact.atom.id === target.atom.id) {
                return true;
            }
            return false;
        }

        public function get subscribers():Array {
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

        public function getDebugInfo():Object {
            return {
                id: this.id,
                name: this.name,
                type: this.type,
                value: this.value,
                atom: this._atom ? this._atom.name + " (" + this._atom.id + ")" : "none",
                subscribers: this._subscribers ? this._subscribers.length : 0,
                source: this._source ? this._source.name : "none",
                isConnected: this.isConnected,
                callbacks: _valueChangedCallbacks.length + _connectedCallbacks.length + _disconnectedCallbacks.length
            };
        }
    }
}
