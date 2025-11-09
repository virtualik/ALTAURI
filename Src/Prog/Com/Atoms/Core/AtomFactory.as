package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.utils.getTimer;

    /**
     * Validating atom factory - creates atoms that are properly registered.
     * Centralized creation point for all atom instances with validation.
     *
     * @class AtomFactory
     * @public
     */
    public class AtomFactory {
        
        /** Factory initialization flag */
        private static var _initialized:Boolean = false;
        
        /** Counter for generating unique atom IDs */
        private static var _atomCounter:int = 0;

        /**
         * Initializes the factory system.
         * Must be called before creating any atoms.
         *
         * @static
         * @public
         */
        public static function initialize():void {
            if (_initialized) return;

            if (!AtomDefinitions.getSupportedTypes()) {
                trace("AtomFactory: WARNING - AtomDefinitions not initialized properly");
                AtomDefinitions.initialize();
            }

            _initialized = true;
            trace("AtomFactory: Initialized - ready to create validated atoms");
        }

        /**
         * Creates a complete atom instance with view based on type definition.
         *
         * @static
         * @public
         * @param {String} type - Atom type identifier (e.g., "Button", "Counter")
         * @param {Point} position - Initial position on canvas
         * @param {String} windowType - Target window type ("Editor", "Device")
         * @param {String} name - Optional display name (defaults to type)
         * @return {Object} Object containing {atom: Atom, view: AtomView} or null if failed
         */
        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            // Validate factory state
            if (!_initialized) {
                trace("AtomFactory: ERROR - Factory not initialized");
                return null;
            }

            // Validate atom type
            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) {
                trace("AtomFactory: ERROR - Atom type not registered: " + type);
                return null;
            }

            // Create atom instance
            var atom:Atom = new Atom(generateId(), type, position, name || type);

            // Create pins from definition
            createPinsFromDefinition(atom, definition.pins);

            // Initialize behavior if defined
            if (definition.behavior && definition.behavior.initialize is Function) {
                atom = definition.behavior.initialize(atom);
            }

            // Create view
            var view:AtomView = new AtomView(atom, windowType);

            trace("AtomFactory: Created atom - " + type + " (" + atom.id + ")");

            return { atom: atom, view: view };
        }

        /**
         * Creates pins for atom based on definition.
         *
         * @static
         * @private
         * @param {Atom} atom - Target atom instance
         * @param {Array} pinsDefinition - Array of pin definitions
         */
		private static function createPinsFromDefinition(atom:Atom, pinsDefinition:Array):void {
			for each (var pinDef:Object in pinsDefinition) {
				// Создаем пин с расширенными возможностями
				var pin:Pin = new Pin(pinDef.name, pinDef.type, null, pinDef);
				

				
				// Добавляем в соответствующие коллекции
				if (pinDef.type == "input") {
					atom.inputs.push(pin);
				} else {
					atom.outputs.push(pin);
				}
			}
		}

        /**
         * Generates a unique ID for an atom.
         *
         * @static
         * @private
         * @return {String} Unique atom identifier
         */
        private static function generateId():String {
            _atomCounter++;
            return "atom_" + getTimer() + "_" + _atomCounter;
        }

        /**
         * Validates if atom type can be created.
         *
         * @static
         * @public
         * @param {String} type - Atom type to validate
         * @return {Boolean} True if atom type is registered and creatable
         */
        public static function canCreateAtom(type:String):Boolean {
            return AtomDefinitions.isAtomTypeRegistered(type);
        }

        /**
         * Gets all creatable atom types.
         *
         * @static
         * @public
         * @return {Array} Array of registered atom type strings
         */
        public static function getCreatableAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Gets creatable atom types by category.
         *
         * @static
         * @public
         * @param {String} category - Category to filter by
         * @return {Array} Array of atom types in specified category
         */
        public static function getCreatableAtomTypesByCategory(category:String):Array {
            return AtomDefinitions.getTypesByCategory(category);
        }

        /**
         * Checks if factory is properly initialized.
         *
         * @static
         * @public
         * @return {Boolean} True if factory is ready to create atoms
         */
        public static function get isInitialized():Boolean {
            return _initialized;
        }

        /**
         * Gets total count of atoms created by this factory.
         *
         * @static
         * @public
         * @return {int} Number of atoms created
         */
        public static function get atomsCreated():int {
            return _atomCounter;
        }
    }
}
