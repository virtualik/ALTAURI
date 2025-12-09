package Src.Prog.Com.Atoms.Contact.Core {
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Core.Managers.AtomManager;

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
            trace("🔗 Contact created: " + this.name + " (" + this.type + ")");
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

            trace("🔔 Contact.value SETTER: " + this.name + " = " + newValue + " (old: " + _value + ")");
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
            trace("🔥 CONTACT → ATOM BEHAVIOR NOTIFICATION 🔥");
            trace("Contact: " + this.name + " = " + newValue);
            trace("Atom: " + (_atom ? _atom.name + " (" + _atom.type + ")" : "null"));

            if (!_atom) {
                trace("⚠ No atom associated with contact");
                return;
            }

            var definition:Object = AtomDefinitions.getAtomDefinition(_atom.type);
            if (!definition) {
                trace("⚠ No definition found for atom type: " + _atom.type);
                return;
            }

            if (!definition.behavior || !definition.behavior.onInputChange || !(definition.behavior.onInputChange is Function)) {
                trace("⚠ No valid behavior for atom: " + _atom.type);
                return;
            }

            trace("📢 Calling behavior.onInputChange for contact: " + this.name);
            try {
                var newAtom:Atom = definition.behavior.onInputChange(_atom, this.name, newValue);

                if (newAtom !== _atom) {
                    AtomManager.getInstance().updateAtom(newAtom);
                    trace("✅ Atom updated via contact behavior");
                } else {
                    trace("⚠ Atom not changed by behavior");
                }
            } catch (error:Error) {
                trace("❌ ERROR in behavior.onInputChange: " + error.message);
            }

            trace("🔥 CONTACT BEHAVIOR NOTIFICATION COMPLETE 🔥");
        }

        public function subscribeTo(targetContact:Contact):Boolean {
            trace("=== CONTACT SUBSCRIBE TO ===");
            trace("Subscriber: " + this.name + " (" + this.type + ")");
            trace("Target: " + targetContact.name + " (" + targetContact.type + ")");

            if (!targetContact || targetContact === this) {
                trace("❌ Invalid target or self-subscription");
                return false;
            }

            if (this.type !== TYPE_INPUT || targetContact.type !== TYPE_OUTPUT) {
                trace("❌ Invalid subscription type (only input → output allowed)");
                return false;
            }

            if (this._source) {
                trace("⚠ Already has source, unsubscribing first");
                this.unsubscribe();
            }

            if (wouldCreateCycle(this, targetContact)) {
                trace("❌ Would create cycle");
                return false;
            }

            if (targetContact._subscribers.indexOf(this) === -1) {
                targetContact._subscribers.push(this);
                trace("✓ Added to target subscribers");
            }

            this._source = targetContact;
            trace("✓ Source set for input contact");

            this.notifyConnected();
            targetContact.notifyConnected();

            if (targetContact.value !== undefined && targetContact.value !== null) {
                trace("➡️ Propagating initial value: " + targetContact.value);
                this.value = targetContact.value;
            }

            trace("=== SUBSCRIPTION SUCCESSFUL ===");
            return true;
        }

        public function unsubscribe():void {
            trace("=== CONTACT UNSUBSCRIBE ===");
            trace("Contact: " + this.name + " (" + this.type + ")");

            if (type === TYPE_INPUT) {
                if (this._source) {
                    var index:int = this._source._subscribers.indexOf(this);
                    if (index !== -1) {
                        this._source._subscribers.splice(index, 1);
                        trace("✓ Removed from source subscribers");
                    }

                    var oldSource:Contact = this._source;
                    this._source = null;

                    this.notifyDisconnected();
                    oldSource.notifyDisconnected();

                    this.value = undefined;
                    trace("✓ Value reset to undefined");
                } else {
                    trace("⚠ No source to unsubscribe from");
                }
            } else {
                trace("Output has " + _subscribers.length + " subscribers");
                for each (var subscriber:Contact in _subscribers) {
                    subscriber.unsubscribe();
                }
                _subscribers = new Array();
                trace("✓ All subscribers removed");
            }

            trace("=== UNSUBSCRIBE COMPLETE ===");
        }

        private function notifySubscribers(newValue:*, oldValue:*):void {
            trace("📤 Contact.notifySubscribers: " + this.name + " → " + _subscribers.length + " subscribers");

            for each (var subscriber:Contact in _subscribers) {
                trace("  → Subscriber: " + subscriber.name);
                subscriber.value = newValue;
            }
        }

        public function setOwnerAtom(atom:Atom):void {
            _atom = atom;
            trace("👤 Contact " + this.name + " owner set: " + (atom ? atom.name : "null"));
        }

        public function get atom():Atom {
            return _atom;
        }

        public function dispose():void {
            trace("🧹 Disposing contact: " + this.name);
            this.unsubscribe();
            _valueChangedCallbacks.length = 0;
            _connectedCallbacks.length = 0;
            _disconnectedCallbacks.length = 0;
            ContactManager.getInstance().unregisterContact(this);
            _subscribers = null;
            _source = null;
            _atom = null;
            trace("✅ Contact disposed: " + this.name);
        }

        private function generateId():String {
            return "contact_" + new Date().getTime() + "_" + Math.floor(Math.random() * 1000000);
        }

        private static function wouldCreateCycle(contact:Contact, target:Contact):Boolean {
            if (contact.atom && target.atom && contact.atom.id === target.atom.id) {
                trace("❌ Would create cycle: same atom");
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