package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.utils.getTimer;

    /**
     * Validating atom factory - only creates atoms that are properly registered
     */
    public class AtomFactory {
        private static var _initialized:Boolean = false;
        private static var _atomCounter:int = 0;

        /**
         * Initialize the factory
         */
		public static function initialize():void {
			if (_initialized) return;

			// Убедимся, что AtomDefinitions инициализированы
			if (!AtomDefinitions.getSupportedTypes()) {
				trace("AtomFactory: WARNING - AtomDefinitions not initialized properly");
				// Автоматически инициализируем если не сделано
				AtomDefinitions.initialize();
			}

			_initialized = true;
			trace("AtomFactory: Initialized - ready to create validated atoms");
		}

        /**
         * Creates a complete atom instance with view based on type definition.
         * 
         * @param {String} type - Atom type to create
         * @param {Point} position - Initial position
         * @param {String} windowType - Window context for view rendering
         * @return {Object} Object containing {atom: Atom, view: AtomView} or null if type not found
         */
		public static function createAtom(type:String, position:Point, windowType:String):Object {
			if (!_initialized) {
				initialize();
			}

			trace("AtomFactory: Creating atom of type: " + type);

			// VALIDATION: Check if atom type is registered
			if (!AtomDefinitions.isAtomTypeRegistered(type)) {
				trace("ERROR: Cannot create unregistered atom type: " + type);
				MultiPulsator.emit(new Impulse("ERROR", {
					source: "AtomFactory",
					message: "Attempted to create unregistered atom type: " + type,
					atomType: type,
					severity: "high"
				}));
				return null;
			}

			// Get definition
			var definition:Object = AtomDefinitions.getAtomDefinition(type);
			if (!definition) {
				trace("ERROR: Definition not found for registered type: " + type);
				return null;
			}

			trace("AtomFactory: Definition found - displayName: " + definition.displayName + ", pins: " + (definition.pins ? definition.pins.length : 0));

			try {
				// Generate unique ID for the atom
				var atomId:String = generateAtomId(type);
				var displayName:String = definition.displayName || type;
				var category:String = definition.category || "General";

				trace("AtomFactory: Creating base atom with ID: " + atomId);

				// Create base atom with ALL required parameters
				var atom:Atom = new Atom(atomId, type, position, displayName);

				trace("AtomFactory: Base atom created successfully");

				// Store category in atom data instead of direct property
				atom.data["category"] = category;

				trace("AtomFactory: Creating pins from definition");

				// Create pins from definition
				createPinsFromDefinition(atom, definition.pins);

				trace("AtomFactory: Creating AtomView");

				// Create view
				var view:AtomView = new AtomView(atom, windowType);

				trace("AtomFactory: AtomView created successfully");

				// Apply view configuration
				if (definition.viewConfig) {
					trace("AtomFactory: Applying view config");
					applyViewConfig(view, definition.viewConfig);
				}

				trace("SUCCESS: Atom created - " + type + " at " + position + " with ID: " + atomId);


			} catch (error:Error) {
				trace("ERROR: Failed to create atom " + type + ": " + error.message);
				trace("ERROR: Error details - name: " + error.name + ", ID: " + error.errorID);
				trace("ERROR: Stack trace: " + error.getStackTrace());

				MultiPulsator.emit(new Impulse("ERROR", {
					source: "AtomFactory",
					message: "Failed to create atom: " + error.message,
					atomType: type,
					error: error
				}));

				return null;
			}
			return {
				atom: atom,
				view: view,
				definition: definition
			};
		}

        /**
         * Generate a unique ID for an atom
         */
        private static function generateAtomId(type:String):String {
            _atomCounter++;
            return type + "_" + getTimer() + "_" + _atomCounter;
        }

		/**
		 * Create pins from definition
		 */
		private static function createPinsFromDefinition(atom:Atom, pinsDefinition:Array):void {
			if (!pinsDefinition) {
				trace("WARNING: No pins defined for atom: " + atom.type);
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

					// Создаем объект data для пина, если указан dataType или description
					var pinData:Object = {};
					if (pinDef.dataType) {
						pinData.dataType = pinDef.dataType;
					}
					if (pinDef.description) {
						pinData.description = pinDef.description;
					}

					// Создаем пин с правильными аргументами: name, type, value=null, data=pinData
					var pin:Pin = new Pin(pinDef.name, pinDef.type, null, pinData);

					// Добавляем пин к атому - ИСПРАВЛЕНИЕ ЗДЕСЬ
					if (pinDef.type == "input") {
						atom.inputs.push(pin);  // ЗАМЕНИТЬ addInputPin(pin) на inputs.push(pin)
						trace("  Added input pin: " + pinDef.name + " (" + pinDef.dataType + ")");
					} else {
						atom.outputs.push(pin); // ЗАМЕНИТЬ addOutputPin(pin) на outputs.push(pin)
						trace("  Added output pin: " + pinDef.name + " (" + pinDef.dataType + ")");
					}
				} catch (error:Error) {
					trace("ERROR: Failed to create pin '" + pinDef.name + "' for atom " + atom.type + ": " + error.message);
				}
			}

			trace("Created " + pinsDefinition.length + " pins for atom: " + atom.type);
		}

        /**
         * Apply view configuration
         */
        private static function applyViewConfig(view:AtomView, config:Object):void {
            try {
                if (config.width) view.width = config.width;
                if (config.height) view.height = config.height;
                if (config.backgroundColor) view.setBackgroundColor(config.backgroundColor);
                
                trace("Applied view config for: " + view.atom.type);
            } catch (error:Error) {
                trace("ERROR: Failed to apply view config: " + error.message);
            }
        }

        /**
         * Validate if atom type can be created
         */
        public static function canCreateAtom(type:String):Boolean {
            return AtomDefinitions.isAtomTypeRegistered(type);
        }

        /**
         * Get all creatable atom types
         */
        public static function getCreatableAtomTypes():Array {
            return AtomDefinitions.getSupportedTypes();
        }

        /**
         * Get creatable atom types by category
         */
        public static function getCreatableAtomTypesByCategory(category:String):Array {
            return AtomDefinitions.getTypesByCategory(category);
        }

        /**
         * Validate factory state
         */
        public static function validate():void {
            trace("=== ATOM FACTORY VALIDATION ===");
            trace("Initialized: " + _initialized);
            
            var creatableTypes:Array = getCreatableAtomTypes();
            trace("Creatable atom types: " + creatableTypes.length);
            
            for each (var type:String in creatableTypes) {
                trace(" - " + type + ": " + (canCreateAtom(type) ? "OK" : "INVALID"));
            }
            
            trace("=== END FACTORY VALIDATION ===");
        }
    }
}
