package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;

    /**
     * Universal immutable atom class representing any computational component.
     * Serves as the core data container for all atom types - no subclassing needed.
     * Follows immutable patterns for state management.
     *
     * UPDATED: Pin objects are now STABLE (not cloned) — only .value is mutated.
     * This preserves direct subscriptions while maintaining Atom immutability.
     *
     * @class Atom
     * @public
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
        /** Collection of input pins */
        public var inputs:Vector.<Pin>;
        /** Collection of output pins */
        public var outputs:Vector.<Pin>;

        /**
         * Creates a new Atom instance.
         *
         * @constructor
         * @param {String} id - Unique identifier
         * @param {String} type - Atom type identifier
         * @param {Point} position - Initial position on canvas
         * @param {String} name - Display name (optional, defaults to type)
         */
        public function Atom(id:String, type:String, position:Point, name:String = null) {
            this.id = id;
            this.type = type;
            this.position = position.clone();
            this.name = name || type;
            this.data = new Object();
            this.inputs = new Vector.<Pin>();
            this.outputs = new Vector.<Pin>();
        }

        public function setPosition(newPosition:Point):Atom {
            var newAtom:Atom = new Atom(id, type, newPosition, name);
            newAtom.data = cloneData(this.data);
            newAtom.inputs = inputs;    // ← Pin-ы НЕ клонируются!
            newAtom.outputs = outputs;  // ← Это ключ к стабильности подписок
            return newAtom;
        }

        public function setData(key:String, value:*):Atom {
            trace("=== ATOM SETDATA ===");
            trace("Key: " + key + ", Value: " + value);
            trace("Original data: " + JSON.stringify(this.data));
            var newAtom:Atom = new Atom(id, type, position, name);
            newAtom.data = cloneData(this.data);
            newAtom.data[key] = value;
            newAtom.inputs = inputs;
            newAtom.outputs = outputs;
            trace("New atom data: " + JSON.stringify(newAtom.data));
            trace("=== END SETDATA ===");
            return newAtom;
        }

        /**
         * Mutates Pin.value in-place instead of cloning Pin.
         * Returns a new Atom (immutable interface), but Pin objects are reused.
         */
        public function setPinValue(pinName:String, value:*, isInput:Boolean = true):Atom {
            trace("=== ATOM SET PIN VALUE ===");
            trace("Atom: " + this.id + ", Pin: " + pinName + ", Value: " + value + ", IsInput: " + isInput);
            
            var newAtom:Atom = new Atom(id, type, position, name);
            newAtom.data = cloneData(this.data);
            
            // Обновляем значение существующего Pin
            var pins:Vector.<Pin> = isInput ? inputs : outputs;
            var pinUpdated:Boolean = false;
            
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    trace("Updating pin: " + pin.name + " to value: " + value);
                    pin.value = value; // ← Это вызовет PinEvent!
                    pinUpdated = true;
                    break;
                }
            }
            
            if (!pinUpdated) {
                trace("⚠ Pin not found: " + pinName);
            }
            
            newAtom.inputs = inputs;
            newAtom.outputs = outputs;
            
            trace("=== END SET PIN VALUE ===");
            return newAtom;
        }

        public function getValue(key:String):* {
            return data[key];
        }

        public function hasValue(key:String):Boolean {
            return data[key] !== undefined;
        }

        private function cloneData(original:Object):Object {
            var cloned:Object = {};
            for (var key:String in original) {
                cloned[key] = original[key];
            }
            return cloned;
        }

        /**
         * НОВЫЙ МЕТОД: мутирует значение существующего Pin по имени.
         */
        private function updatePinValueInPlace(pins:Vector.<Pin>, pinName:String, value:*):void {
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    pin.value = value; // ← Это вызовет PinEvent!
                    return;
                }
            }
        }
    }
}