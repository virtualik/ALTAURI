package Application.AtomLinker.Core {
    import flash.display.DisplayObject;
    import flash.geom.Point;
    import flash.utils.Dictionary;

    /**
     * Base Atom - immutable atom class for circuit components
     * Represents basic circuit component with input/output pins
     */
    public class BaseAtom {
        public var id:String;
        public var position:Point;
        public var displayObject:DisplayObject;
        public var name:String;
        public var type:String;
        private var _inputContacts:Vector.<Pin>;
        private var _outputContacts:Vector.<Pin>;

        /**
         * Base Atom constructor
         * @param id - unique atom identifier
         * @param pos - atom position
         * @param name - atom name
         * @param type - atom type
         * @param inputContacts - input pins vector
         * @param outputContacts - output pins vector
         */
        public function BaseAtom(id:String, pos:Point, name:String, type:String, inputContacts:Vector.<Pin> = null, outputContacts:Vector.<Pin> = null) {
            this.id = id;
            this.position = pos;
            this.name = name;
            this.type = type;
            this._inputContacts = inputContacts ? inputContacts.concat() : new Vector.<Pin>();
            this._outputContacts = outputContacts ? outputContacts.concat() : new Vector.<Pin>();
        }

        /**
         * Create new atom with updated position
         * @param newPosition - new position for atom
         * @return BaseAtom - new atom instance with updated position
         */
        public function setPosition(newPosition:Point):BaseAtom {
            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                newPosition,
                this.name,
                this.type,
                this._inputContacts.concat(),
                this._outputContacts.concat()
            );

            newAtom.displayObject = this.displayObject;
            updatePinsParentAtom(newAtom);
            return newAtom;
        }

        /**
         * Set input pin value (immutable)
         * @param pinName - pin name to update
         * @param newValue - new value for pin
         * @return BaseAtom - new atom instance with updated pin
         */
        public function setInputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _inputContacts.length; i++) {
                if (_inputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) return this;

            var newInputContacts:Vector.<Pin> = _inputContacts.concat();
            var updatedPin:Pin = _inputContacts[pinIndex].setValue(newValue);
            newInputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position,
                this.name,
                this.type,
                newInputContacts,
                this._outputContacts.concat()
            );
            newAtom.displayObject = this.displayObject;
            updatePinsParentAtom(newAtom);
            return newAtom;
        }

        /**
         * Set output pin value (immutable)
         * @param pinName - pin name to update
         * @param newValue - new value for pin
         * @return BaseAtom - new atom instance with updated pin
         */
        public function setOutputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _outputContacts.length; i++) {
                if (_outputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) return this;

            var newOutputContacts:Vector.<Pin> = _outputContacts.concat();
            var updatedPin:Pin = _outputContacts[pinIndex].setValue(newValue);
            newOutputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position,
                this.name,
                this.type,
                this._inputContacts.concat(),
                newOutputContacts
            );
            newAtom.displayObject = this.displayObject;
            updatePinsParentAtom(newAtom);
            return newAtom;
        }

        /**
         * Update pins parent atom reference
         * @param atom - atom to set as parent for pins
         */
        private function updatePinsParentAtom(atom:BaseAtom):void {
            for each (var inputPin:Pin in atom.inputContacts) {
                if (inputPin.hasOwnProperty("_parentAtom")) {
                    inputPin["_parentAtom"] = atom;
                }
            }
            for each (var outputPin:Pin in atom.outputContacts) {
                if (outputPin.hasOwnProperty("_parentAtom")) {
                    outputPin["_parentAtom"] = atom;
                }
            }
        }

        /**
         * Get input contacts
         * @return Vector.<Pin> - copy of input pins vector
         */
        public function get inputContacts():Vector.<Pin> {
            return this._inputContacts.concat();
        }

        /**
         * Get output contacts
         * @return Vector.<Pin> - copy of output pins vector
         */
        public function get outputContacts():Vector.<Pin> {
            return this._outputContacts.concat();
        }

        /**
         * Get all contacts (input + output)
         * @return Vector.<Pin> - combined vector of all pins
         */
        public function getAllContacts():Vector.<Pin> {
            var all:Vector.<Pin> = new Vector.<Pin>();
            all = all.concat(this._inputContacts);
            all = all.concat(this._outputContacts);
            return all;
        }
    }
}
