package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.utils.getTimer;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;

    public class AtomFactory {
        private static var _initialized:Boolean = false;
        private static var _atomCounter:int = 0;
        private static var _debugMode:Boolean = true;

        public static function initialize():void {
            if (_initialized) return;

            if (!AtomDefinitions.getSupportedTypes()) {
                AtomDefinitions.initialize();
            }

            _initialized = true;
        }

        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            if (!_initialized) {
                initialize();
            }

            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) {
                return null;
            }

            var atom:Atom = new Atom(generateId(), type, position, name || type);
            createContactsFromDefinition(atom, definition.pins);

            if (definition.behavior && definition.behavior.initialize is Function) {
                atom = definition.behavior.initialize(atom);
            }

            var view:AtomView = new AtomView(atom, windowType);

            return { atom: atom, view: view };
        }

        private static function createContactsFromDefinition(atom:Atom, pinsDefinition:Array):void {
            if (!pinsDefinition || pinsDefinition.length === 0) {
                return;
            }

            for each (var pinDef:Object in pinsDefinition) {
                var contact:Contact = createContactFromDefinition(pinDef);
                contact.setOwnerAtom(atom);

                if (pinDef.type == "input") {
                    atom.contactInputs.push(contact);
                } else {
                    atom.contactOutputs.push(contact);
                }
            }
        }

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

        private static function getDefaultValue(dataType:String):* {
            switch(dataType) {
                case "boolean": return false;
                case "number": return 0;
                case "string": return "";
                case "impulse": return null;
                default: return null;
            }
        }

        private static function generateId():String {
            _atomCounter++;
            return "atom_" + getTimer() + "_" + _atomCounter;
        }

        public static function canCreateAtom(type:String):Boolean {
            return AtomDefinitions.isAtomTypeRegistered(type);
        }

		public static function getCreatableAtomTypes():Array {
			return AtomDefinitions.getSupportedTypes();
		}

        public static function getCreatableAtomTypesByCategory(category:String):Array {
            return AtomDefinitions.getTypesByCategory(category);
        }

        public static function get isInitialized():Boolean {
            return _initialized;
        }

        public static function get atomsCreated():int {
            return _atomCounter;
        }

        public static function createTestAtom(type:String = "Button", name:String = null):Atom {
            var result:Object = createAtom(type, new Point(100, 100), "Editor", name || "Test" + type);
            return result ? result.atom : null;
        }
    }
}
