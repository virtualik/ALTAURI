package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Represents the base immutable class for computational components (atoms).
     * Contains core properties like ID, position, name, type, and input/output pins.
     * Implements immutable behavior: methods that change state return a *new* BaseAtom instance.
     * Integrates with MultiPulsator for system communication.
     */
    public class BaseAtom {
        public var id:String;
        public var position:Point;
        // Убран displayObject - визуализацией управляет BaseAtomView
        public var name:String;
        public var type:String;
        private var _inputContacts:Vector.<Pin>;
        private var _outputContacts:Vector.<Pin>;

        /**
         * Constructs a BaseAtom instance.
         * @param id The unique identifier for the atom.
         * @param pos The initial position of the atom.
         * @param name The name of the atom.
         * @param type The type of the atom (e.g., "Button", "Counter").
         * @param inputContacts An optional vector of input pins.
         * @param outputContacts An optional vector of output pins.
         */
        public function BaseAtom(id:String, pos:Point, name:String, type:String, inputContacts:Vector.<Pin> = null, outputContacts:Vector.<Pin> = null) {
            this.id = id;
            this.position = pos ? pos.clone() : new Point(); // Клонируем Point для безопасности
            this.name = name;
            this.type = type;
            // Клонируем векторы и пины для иммутабельности
            this._inputContacts = inputContacts ? clonePins(inputContacts) : new Vector.<Pin>();
            this._outputContacts = outputContacts ? clonePins(outputContacts) : new Vector.<Pin>();
            
            // Устанавливаем ссылки на родительский атом для всех пинов
            updatePinsParentAtom();
        }

        /**
         * Creates a new atom instance with an updated position.
         * This method implements the immutable pattern.
         * @param newPosition The new position for the atom.
         * @return A new BaseAtom instance with the updated position.
         */
        public function setPosition(newPosition:Point):BaseAtom {
            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                newPosition ? newPosition.clone() : new Point(), // Клонируем новую позицию
                this.name,
                this.type,
                this._inputContacts, // Используем клоны, созданные в конструкторе
                this._outputContacts
            );
            return newAtom;
        }

        /**
         * Creates a new atom instance with an updated value for a specific input pin.
         * This method implements the immutable pattern.
         * @param pinName The name of the input pin to update.
         * @param newValue The new value for the pin.
         * @return A new BaseAtom instance with the updated input pin, or the same instance if the pin was not found.
         */
        public function setInputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _inputContacts.length; i++) {
                if (_inputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "WARN",
                    source: "BaseAtom",
                    message: "Input pin '" + pinName + "' not found for atom '" + this.name + "' (" + this.id + "). Returning same instance."
                }));
                return this; // Pin not found, return the same instance
            }

            // Создаём копию вектора и обновлённый пин
            var newInputContacts:Vector.<Pin> = this._inputContacts.concat(); // Копируем вектор
            var updatedPin:Pin = _inputContacts[pinIndex].setValue(newValue); // Создаём новый пин
            newInputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position, // Клонируется в конструкторе
                this.name,
                this.type,
                newInputContacts, // Передаём новый вектор с обновлённым пином
                this._outputContacts // Клонируется в конструкторе
            );
            return newAtom;
        }

        /**
         * Creates a new atom instance with an updated value for a specific output pin.
         * This method implements the immutable pattern.
         * @param pinName The name of the output pin to update.
         * @param newValue The new value for the pin.
         * @return A new BaseAtom instance with the updated output pin, or the same instance if the pin was not found.
         */
        public function setOutputPinValue(pinName:String, newValue:*):BaseAtom {
            var pinIndex:int = -1;
            for (var i:int = 0; i < _outputContacts.length; i++) {
                if (_outputContacts[i].name == pinName) {
                    pinIndex = i;
                    break;
                }
            }
            if (pinIndex == -1) {
                 MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    level: "WARN",
                    source: "BaseAtom",
                    message: "Output pin '" + pinName + "' not found for atom '" + this.name + "' (" + this.id + "). Returning same instance."
                }));
                return this; // Pin not found, return the same instance
            }

            // Создаём копию вектора и обновлённый пин
            var newOutputContacts:Vector.<Pin> = this._outputContacts.concat(); // Копируем вектор
            var updatedPin:Pin = _outputContacts[pinIndex].setValue(newValue); // Создаём новый пин
            newOutputContacts[pinIndex] = updatedPin;

            var newAtom:BaseAtom = new BaseAtom(
                this.id,
                this.position, // Клонируется в конструкторе
                this.name,
                this.type,
                this._inputContacts, // Клонируется в конструкторе
                newOutputContacts // Передаём новый вектор с обновлённым пином
            );
            return newAtom;
        }

        /**
         * Updates the `_parentAtom` reference on all input and output pins of *this* atom instance.
         * This is necessary to maintain the link between pins and their parent atom after creating a new atom instance.
         */
        private function updatePinsParentAtom():void {
            for each (var inputPin:Pin in this._inputContacts) {
                 inputPin.setParentAtom(this); // Используем setter вместо прямого доступа
            }
            for each (var outputPin:Pin in this._outputContacts) {
                 outputPin.setParentAtom(this); // Используем setter вместо прямого доступа
            }
        }

        /**
         * Gets a copy of the vector containing all input pins.
         * @return A copy of the input pins vector.
         */
        public function get inputContacts():Vector.<Pin> {
            return this._inputContacts.concat(); // Return a copy to prevent external modification
        }

        /**
         * Gets a copy of the vector containing all output pins.
         * @return A copy of the output pins vector.
         */
        public function get outputContacts():Vector.<Pin> {
            return this._outputContacts.concat(); // Return a copy to prevent external modification
        }

        /**
         * Gets a combined vector containing all input and output pins.
         * @return A new vector containing all pins.
         */
        public function getAllContacts():Vector.<Pin> {
            var all:Vector.<Pin> = new Vector.<Pin>();
            all = all.concat(this._inputContacts); // Add input pins
            all = all.concat(this._outputContacts); // Add output pins
            return all; // Return the combined vector
        }

        // --- Утилиты ---

        /**
         * Helper function to deeply clone a vector of Pin objects.
         * This ensures immutability of the pins themselves when creating new BaseAtom instances.
         * @param originalPins The original vector of pins.
         * @return A new vector containing cloned pin instances.
         */
        private function clonePins(originalPins:Vector.<Pin>):Vector.<Pin> {
            var clonedPins:Vector.<Pin> = new Vector.<Pin>();
            for each (var originalPin:Pin in originalPins) {
                // Используем setValue(null) как способ клонирования пина с сохранением его состояния
                var clonedPin:Pin = originalPin.setValue(originalPin.value);
                clonedPins.push(clonedPin);
            }
            return clonedPins;
        }
    }
}
