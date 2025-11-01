package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import flash.utils.Dictionary;

    /**
     * Universal immutable atom class that represents any computational component in the system.
     * This is the core data container for all atom types - no subclassing needed.
     * 
     * @class Atom
     * @public
     */
    public class Atom {
        /** Unique identifier for the atom */
        public var id:String;
        
        /** Position on the canvas */
        public var position:Point;
        
        /** Display name */
        public var name:String;
        
        /** Atom type (e.g., "Button", "Counter") */
        public var type:String;
        
        /** Dynamic data storage for atom-specific properties */
        public var data:Dictionary;
        
        /** Input pins */
        public var inputs:Vector.<Pin>;
        
        /** Output pins */
        public var outputs:Vector.<Pin>;

        /**
         * Creates a new Atom instance.
         * 
         * @constructor
         * @param {String} id - Unique identifier
         * @param {String} type - Atom type
         * @param {Point} position - Initial position
         * @param {String} name - Display name (optional, defaults to type)
         */
        public function Atom(id:String, type:String, position:Point, name:String = null) {
            this.id = id;
            this.type = type;
            this.position = position.clone();
            this.name = name || type;
            this.data = new Dictionary();
            this.inputs = new Vector.<Pin>();
            this.outputs = new Vector.<Pin>();
        }

        /**
         * Creates a new Atom with updated position (immutable pattern).
         * 
         * @param {Point} newPosition - New position
         * @return {Atom} New Atom instance with updated position
         */
        public function setPosition(newPosition:Point):Atom {
            var newAtom:Atom = new Atom(id, type, newPosition, name);
            newAtom.data = cloneData(this.data);
            newAtom.inputs = clonePins(this.inputs);
            newAtom.outputs = clonePins(this.outputs);
            return newAtom;
        }

        /**
         * Creates a new Atom with updated data property (immutable pattern).
         * 
         * @param {String} key - Data key to update
         * @param {*} value - New value
         * @return {Atom} New Atom instance with updated data
         */
        public function setData(key:String, value:*):Atom {
            var newAtom:Atom = new Atom(id, type, position, name);
            newAtom.data = cloneData(this.data);
            newAtom.data[key] = value;
            newAtom.inputs = clonePins(this.inputs);
            newAtom.outputs = clonePins(this.outputs);
            return newAtom;
        }

        /**
         * Creates a new Atom with updated pin value (immutable pattern).
         * 
         * @param {String} pinName - Name of the pin to update
         * @param {*} value - New value for the pin
         * @param {Boolean} isInput - Whether the pin is input (true) or output (false)
         * @return {Atom} New Atom instance with updated pin value
         */
        public function setPinValue(pinName:String, value:*, isInput:Boolean = true):Atom {
            var newAtom:Atom = new Atom(id, type, position, name);
            newAtom.data = cloneData(this.data);
            newAtom.inputs = updatePinValue(inputs, pinName, value, isInput);
            newAtom.outputs = updatePinValue(outputs, pinName, value, !isInput);
            return newAtom;
        }

        /**
         * Retrieves a value from the data dictionary.
         * 
         * @param {String} key - Data key
         * @return {*} Value associated with the key, or undefined if not found
         */
        public function getValue(key:String):* {
            return data[key];
        }

        /**
         * Checks if a data key exists.
         * 
         * @param {String} key - Data key to check
         * @return {Boolean} True if key exists, false otherwise
         */
        public function hasValue(key:String):Boolean {
            return data[key] !== undefined;
        }

        /**
         * Creates a deep clone of the data dictionary.
         * 
         * @private
         * @param {Dictionary} original - Original dictionary to clone
         * @return {Dictionary} Cloned dictionary
         */
        private function cloneData(original:Dictionary):Dictionary {
            var cloned:Dictionary = new Dictionary();
            for (var key:String in original) {
                cloned[key] = original[key];
            }
            return cloned;
        }

        /**
         * Creates a deep clone of a pin vector.
         * 
         * @private
         * @param {Vector.<Pin>} original - Original pin vector to clone
         * @return {Vector.<Pin>} Cloned pin vector
         */
        private function clonePins(original:Vector.<Pin>):Vector.<Pin> {
            var cloned:Vector.<Pin> = new Vector.<Pin>();
            for each (var pin:Pin in original) {
                cloned.push(pin.clone());
            }
            return cloned;
        }

        /**
         * Updates pin value in a pin vector.
         * 
         * @private
         * @param {Vector.<Pin>} pins - Original pin vector
         * @param {String} pinName - Name of pin to update
         * @param {*} value - New value
         * @param {Boolean} shouldUpdate - Whether to perform the update
         * @return {Vector.<Pin>} New pin vector with updated pin
         */
        private function updatePinValue(pins:Vector.<Pin>, pinName:String, value:*, shouldUpdate:Boolean):Vector.<Pin> {
            if (!shouldUpdate) return clonePins(pins);
            
            var newPins:Vector.<Pin> = new Vector.<Pin>();
            for each (var pin:Pin in pins) {
                if (pin.name == pinName) {
                    newPins.push(pin.cloneWithValue(value));
                } else {
                    newPins.push(pin.clone());
                }
            }
            return newPins;
        }
    }
}
