package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import flash.utils.getTimer;

    /**
     * Validating atom factory - only creates atoms that are properly registered
     * Centralized creation point for all atom instances with validation
     * 
     * @class AtomFactory
     * @public
     */
    public class AtomFactory {
        private static var _initialized:Boolean = false;
        private static var _atomCounter:int = 0;

        /**
         * Initialize the factory system
         * Must be called before creating any atoms
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
         * Creates a complete atom instance with view based on type definition
         * 
         * @static
         * @public
         * @param {String} type - Atom type identifier (e.g., "Button", "Counter")
         * @param {Point} position - Initial position on canvas
         * @param {String} windowType - Target window type ("Editor", "Device")
         * @param {String} name - Optional display name (defaults to type)
         * @return {Object} Object containing {atom: Atom, view: AtomView} or null if creation failed
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
         * Create pins for atom based on definition
         * 
         * @static
         * @private
         * @param {Atom} atom - Target atom instance
         * @param {Array} pinsDefinition - Array of pin definitions
         */
        private static function createPinsFromDefinition(atom:Atom, pinsDefinition:Array):void {
            if (!pinsDefinition || pinsDefinition.length === 0) {
                trace("AtomFactory: WARNING - No pins defined for atom: " + atom.type);
                return;
            }

            for each (var pinDef:Object in pinsDefinition) {
                try {
                    // Validate pin definition
                    if (!pinDef.name) {
                        trace("ERROR: Pin definition missing name for atom: " + atom.type);
                        continue;
                    }
                    if (!pinDef.type || (pinDef.type != "input" && pinDef.type != "output")) {
                        trace("ERROR: Invalid pin type '" + pinDef.type + "' for pin '" + pinDef.name + "' in atom: " + atom.type);
                        continue;
                    }

                    // Create pin data object
                    var pinData:Object = {};
                    if (pinDef.dataType) pinData.dataType = pinDef.dataType;
                    if (pinDef.description) pinData.description = pinDef.description;

                    // Create pin instance
                    var pin:Pin = new Pin(pinDef.name, pinDef.type, null, pinData);

                    // Add to appropriate pin collection
                    if (pinDef.type == "input") {
                        atom.inputs.push(pin);
                    } else {
                        atom.outputs.push(pin);
                    }
                    
                } catch (error:Error) {
                    trace("ERROR: Failed to create pin '" + pinDef.name + "' for atom " + atom.type + ": " + error.message);
                }
            }

            trace("AtomFactory: Created " + pinsDefinition.length + " pins for atom: " + atom.type);
        }

        /**
         * Generate a unique ID for an atom
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
         * Validate if atom type can be created
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
         * Get all creatable atom types
         * 
         * @static
         * @public
         * @return {Array} Array of registered atom type strings
         */
        public static function getCreatableAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Get creatable atom types by category
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
         * Check if factory is properly initialized
         * 
         * @static
         * @public
         * @return {Boolean} True if factory is ready to create atoms
         */
        public static function get isInitialized():Boolean {
            return _initialized;
        }

        /**
         * Get total count of atoms created by this factory
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
