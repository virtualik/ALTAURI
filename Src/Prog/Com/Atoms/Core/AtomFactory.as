package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.utils.getTimer;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;

    /**
     * Validating atom factory - создает атомы с параллельными Pin и Contact системами.
     */
    public class AtomFactory {

        /** Factory initialization flag */
        private static var _initialized:Boolean = false;
        /** Counter for generating unique atom IDs */
        private static var _atomCounter:int = 0;
        /** Флаг для отладки */
        private static var _debugMode:Boolean = true;

        /**
         * Initializes the factory system.
         */
        public static function initialize():void {
            if (_initialized) return;

            if (!AtomDefinitions.getSupportedTypes()) {
                trace("AtomFactory: WARNING - AtomDefinitions not initialized properly");
                AtomDefinitions.initialize();
            }

            _initialized = true;
            trace("✅ AtomFactory: Initialized - ready to create atoms with DUAL contact systems");
        }

        /**
         * Creates a complete atom instance with both Pin and Contact systems.
         */
        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            // Validate factory state
            if (!_initialized) {
                trace("AtomFactory: ERROR - Factory not initialized");
                initialize(); // Auto-initialize
            }

            // Validate atom type
            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) {
                trace("AtomFactory: ERROR - Atom type not registered: " + type);
                return null;
            }

            // Create atom instance
            var atom:Atom = new Atom(generateId(), type, position, name || type);

            // Create pins AND contacts from definition (ПАРАЛЛЕЛЬНЫЕ СИСТЕМЫ)
            createDualSystemsFromDefinition(atom, definition.pins);

            // Initialize behavior if defined
            if (definition.behavior && definition.behavior.initialize is Function) {
                atom = definition.behavior.initialize(atom);
            }

            // Create view
            var view:AtomView = new AtomView(atom, windowType);

            if (_debugMode) {
                trace("🎯 AtomFactory: Created atom - " + type + " (" + atom.id + ")");
                trace("   📌 Pins: " + atom.inputs.length + " inputs, " + atom.outputs.length + " outputs");
                trace("   🔗 Contacts: " + atom.contactInputs.length + " inputs, " + atom.contactOutputs.length + " outputs");
                trace("   📍 Position: " + position);
            }

            return { atom: atom, view: view };
        }

        /**
         * Creates both Pin and Contact systems from definition.
         * Каждый пин создает соответствующий контакт с теми же параметрами.
         */
        private static function createDualSystemsFromDefinition(atom:Atom, pinsDefinition:Array):void {
            if (!pinsDefinition || pinsDefinition.length === 0) {
                trace("⚠ AtomFactory: No pins definition for atom type: " + atom.type);
                return;
            }

            for each (var pinDef:Object in pinsDefinition) {
                // 1. Создаем пин (СТАРАЯ СИСТЕМА)
                var pin:Pin = createPinFromDefinition(pinDef);
                
                // 2. Создаем контакт (НОВАЯ СИСТЕМА)
                var contact:Contact = createContactFromDefinition(pinDef);
                
                // 3. Устанавливаем атом-владельца
                pin.setOwnerAtom(atom);
                contact.setOwnerAtom(atom);
                
                // 4. Добавляем в соответствующие коллекции
                if (pinDef.type == "input") {
                    atom.inputs.push(pin);
                    atom.contactInputs.push(contact);
                } else {
                    atom.outputs.push(pin);
                    atom.contactOutputs.push(contact);
                }
                
                if (_debugMode) {
                    trace("   ➕ Created: " + pinDef.type + " '" + pinDef.name + "'");
                    trace("     📌 Pin: " + pin.id);
                    trace("     🔗 Contact: " + contact.id);
                }
            }
        }

        /**
         * Creates a Pin from definition.
         */
        private static function createPinFromDefinition(pinDef:Object):Pin {
            return new Pin(
                pinDef.name,
                pinDef.type,
                getDefaultValue(pinDef.dataType),
                {
                    dataType: pinDef.dataType || "any",
                    description: pinDef.description || "",
                    defaultValue: getDefaultValue(pinDef.dataType)
                }
            );
        }

        /**
         * Creates a Contact from definition.
         */
        private static function createContactFromDefinition(pinDef:Object):Contact {
            var contactType:String = pinDef.type == "input" ? Contact.TYPE_INPUT : Contact.TYPE_OUTPUT;
            
            return new Contact(
                pinDef.name,
                contactType,
                getDefaultValue(pinDef.dataType),
                {
                    dataType: pinDef.dataType || "any",
                    description: pinDef.description || "",
                    defaultValue: getDefaultValue(pinDef.dataType),
                    originalPinDef: pinDef // Сохраняем ссылку на оригинальное определение
                }
            );
        }

        /**
         * Gets default value based on data type.
         */
        private static function getDefaultValue(dataType:String):* {
            switch(dataType) {
                case "boolean": return false;
                case "number": return 0;
                case "string": return "";
                case "impulse": return null;
                default: return null;
            }
        }

        /**
         * Generates a unique ID for an atom.
         */
        private static function generateId():String {
            _atomCounter++;
            return "atom_" + getTimer() + "_" + _atomCounter;
        }

        /**
         * Validates if atom type can be created.
         */
        public static function canCreateAtom(type:String):Boolean {
            return AtomDefinitions.isAtomTypeRegistered(type);
        }

        /**
         * Gets all creatable atom types.
         */
        public static function getCreatableAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Gets creatable atom types by category.
         */
        public static function getCreatableAtomTypesByCategory(category:String):Array {
            return AtomDefinitions.getTypesByCategory(category);
        }

        /**
         * Checks if factory is properly initialized.
         */
        public static function get isInitialized():Boolean {
            return _initialized;
        }

        /**
         * Gets total count of atoms created by this factory.
         */
        public static function get atomsCreated():int {
            return _atomCounter;
        }

        /**
         * Enables debug mode for detailed logging.
         */
        public static function enableDebugMode():void {
            _debugMode = true;
            trace("🔍 AtomFactory debug mode ENABLED");
        }

        /**
         * Disables debug mode.
         */
        public static function disableDebugMode():void {
            _debugMode = false;
            trace("🔍 AtomFactory debug mode DISABLED");
        }

        /**
         * Creates a simple test atom for debugging.
         */
        public static function createTestAtom(type:String = "Button", name:String = null):Atom {
            var result:Object = createAtom(type, new Point(100, 100), "Editor", name || "Test" + type);
            return result ? result.atom : null;
        }
    }
}