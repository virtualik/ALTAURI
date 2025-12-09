package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.utils.getTimer;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;

    /**
     * Validating atom factory - создает атомы ТОЛЬКО с Contact системой.
     */
    public class AtomFactory {

        private static var _initialized:Boolean = false;
        private static var _atomCounter:int = 0;
        private static var _debugMode:Boolean = true;

        public static function initialize():void {
            if (_initialized) return;

            if (!AtomDefinitions.getSupportedTypes()) {
                trace("AtomFactory: WARNING - AtomDefinitions not initialized properly");
                AtomDefinitions.initialize();
            }

            _initialized = true;
            trace("✅ AtomFactory: Initialized - creating atoms with SINGLE contact system");
        }

        /**
         * Creates a complete atom instance with Contact system only.
         */
        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            if (!_initialized) {
                trace("AtomFactory: ERROR - Factory not initialized");
                initialize();
            }

            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) {
                trace("AtomFactory: ERROR - Atom type not registered: " + type);
                return null;
            }

            // Create atom instance
            var atom:Atom = new Atom(generateId(), type, position, name || type);

            // Create contacts from definition (ТОЛЬКО Contact система)
            createContactsFromDefinition(atom, definition.pins);

            // Initialize behavior if defined
            if (definition.behavior && definition.behavior.initialize is Function) {
                atom = definition.behavior.initialize(atom);
            }

            // Create view
            var view:AtomView = new AtomView(atom, windowType);

            if (_debugMode) {
                trace("🎯 AtomFactory: Created atom - " + type + " (" + atom.id + ")");
                trace("   🔗 Contacts: " + atom.contactInputs.length + " inputs, " + atom.contactOutputs.length + " outputs");
                trace("   📍 Position: " + position);
            }

            return { atom: atom, view: view };
        }

        /**
         * Creates Contact system from definition.
         */
        private static function createContactsFromDefinition(atom:Atom, pinsDefinition:Array):void {
            if (!pinsDefinition || pinsDefinition.length === 0) {
                trace("⚠ AtomFactory: No pins definition for atom type: " + atom.type);
                return;
            }

            for each (var pinDef:Object in pinsDefinition) {
                // Создаем контакт
                var contact:Contact = createContactFromDefinition(pinDef);
                
                // Устанавливаем атом-владельца
                contact.setOwnerAtom(atom);

                // Добавляем в соответствующие коллекции
                if (pinDef.type == "input") {
                    atom.contactInputs.push(contact);
                } else {
                    atom.contactOutputs.push(contact);
                }

                if (_debugMode) {
                    trace("   ➕ Created contact: " + pinDef.type + " '" + pinDef.name + "'");
                    trace("     🔗 Contact: " + contact.id);
                }
            }
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
                    originalPinDef: pinDef
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
         * Creates a simple test atom for debugging.
         */
        public static function createTestAtom(type:String = "Button", name:String = null):Atom {
            var result:Object = createAtom(type, new Point(100, 100), "Editor", name || "Test" + type);
            return result ? result.atom : null;
        }
    }
}