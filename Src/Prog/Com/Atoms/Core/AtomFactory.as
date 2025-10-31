package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import flash.utils.Dictionary;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Managers.DataManager;
    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.BaseAtomView;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Atoms.Custom.ButtonAtom;
    import Src.Prog.Com.Atoms.Custom.CounterAtom;
    import Src.Prog.Com.Atoms.Custom.NumberDisplayAtom;
    import Src.Prog.Com.Atoms.Custom.ButtonAtom_EditorView;
    import Src.Prog.Com.Atoms.Custom.CounterAtom_EditorView;
    import Src.Prog.Com.Atoms.Custom.NumberDisplayAtom_EditorView;

    /**
     * Centralized factory for creating atom instances (BaseAtom + BaseAtomView).
     * Uses a registry in DataManager to map atom types to their concrete classes.
     * Integrates with MultiPulsator for system communication.
     */
    public class AtomFactory {
        // Используем DataManager как DataBank для хранения реестра
        public static const REGISTRY_KEY:String = "ATOM_FACTORY_REGISTRY";

        /**
         * Initializes the factory by ensuring the registry exists in DataManager.
         * This should be called during application startup.
         */
        public static function initialize():void {
            if (!DataManager.hasData(REGISTRY_KEY)) {
                DataManager.registerData(REGISTRY_KEY, new Dictionary());
            }
            
            // Register default atom types
            registerDefaultAtomTypes();
            
            MultiPulsator.emit(new Impulse("ATOM_FACTORY_INITIALIZED"));
        }

		/**
		 * Registers default atom types.
		 */
		private static function registerDefaultAtomTypes():void {
			// Register Button atom
			registerAtomType("Button", 
				ButtonAtom,
				ButtonAtom_EditorView,
				"Button", 
				"Input"
			);

			// Register Counter atom  
			registerAtomType("Counter",
				CounterAtom,
				CounterAtom_EditorView, 
				"Counter",
				"Logic"
			);

			// Register NumberDisplay atom
			registerAtomType("NumberDisplay",
				NumberDisplayAtom,
				NumberDisplayAtom_EditorView,
				"Number Display",
				"Output"
			);
		}

        /**
         * Registers a new atom type with its concrete BaseAtom and BaseAtomView classes.
         * @param atomType The unique identifier for the atom type (e.g., "Button").
         * @param atomClass The BaseAtom subclass used for the atom's logic.
         * @param viewClass The BaseAtomView subclass used for the atom's view (e.g., EditorAtomView, DeviceAtomView).
         * @param displayName An optional human-readable name for the atom type.
         * @param category An optional category for grouping the atom type.
         */
        public static function registerAtomType(atomType:String, atomClass:Class, viewClass:Class, displayName:String = null, category:String = "General"):void {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!atomType || !atomClass || !viewClass) {
                MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Cannot register invalid atom type: " + atomType }));
                return;
            }
            registry[atomType] = {
                atomClass: atomClass,
                viewClass: viewClass,
                displayName: displayName || atomType,
                category: category
            };
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", { level: "DEBUG", source: "AtomFactory", message: "Registered atom type: " + atomType }));
        }

        /**
         * Creates a new atom instance (BaseAtom + BaseAtomView) of the specified type.
         * The created atom and view are linked and returned as an object.
         * @param atomType The type of atom to create (e.g., "Button").
         * @param position The initial position for the atom.
         * @param name An optional name for the atom (defaults to the display name of the type).
         * @return An object containing {atom: BaseAtom, view: BaseAtomView}, or null if creation failed.
         */
		public static function createAtom(atomType:String, position:Point, name:String = null):Object {
			trace("AtomFactory.createAtom called: " + atomType + " at " + position);
			
			if (!atomType || !position) {
				trace("ERROR: Invalid parameters");
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Invalid parameters for createAtom: type=" + atomType + ", pos=" + position }));
				return null;
			}

			var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
			var typeInfo:Object = registry[atomType];

			if (!typeInfo) {
				trace("ERROR: Atom type not found in registry: " + atomType);
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Atom type not found in registry: " + atomType }));
				return null;
			}

			trace("Found atom type info: " + typeInfo.displayName);
			
			var atomInfo:Object = typeInfo;
			var atomName:String = name || atomInfo.displayName;
			var atomId:String = generateId();
			
			trace("Creating atom with ID: " + atomId);

			try {
				// 1. Создать визуальное представление
				var ViewClass:Class = atomInfo.viewClass;
				trace("ViewClass: " + ViewClass);
				var view:BaseAtomView = new ViewClass() as BaseAtomView;
				trace("View created: " + view);

				// 2. Создать логическое представление
				var AtomClass:Class = atomInfo.atomClass;
				trace("AtomClass: " + AtomClass);
				var inputPins:Vector.<Pin> = createPinsForType(atomType, Pin.TYPE_INPUT);
				var outputPins:Vector.<Pin> = createPinsForType(atomType, Pin.TYPE_OUTPUT);
				trace("Pins created - inputs: " + inputPins.length + ", outputs: " + outputPins.length);

				var atom:BaseAtom = new AtomClass(atomId, position, atomName, atomType, inputPins, outputPins);
				trace("Atom created: " + atom);

				// 3. Связать атом и вью
				view.initWithAtom(atom);
				trace("View initialized with atom");

				MultiPulsator.emit(new Impulse("LOG_MESSAGE", { level: "INFO", source: "AtomFactory", message: "Atom created: " + atomId + " (" + atomType + ")" }));

				trace("SUCCESS: Atom creation completed");
				return { atom: atom, view: view };

			} catch (e:Error) {
				trace("ERROR in atom creation: " + e.message + "\n" + e.getStackTrace());
				MultiPulsator.emit(new Impulse("ERROR", { source: "AtomFactory", message: "Error creating atom type " + atomType + ": " + e.message }));
				return null;
			}
		return null;
		}

        /**
         * Generates a unique identifier for an atom.
         * @return A unique string ID.
         */
        private static function generateId():String {
            // Простой генератор ID, можно улучшить
            return "atom_" + new Date().getTime() + "_" + Math.round(Math.random() * 1000000);
        }

        /**
         * Creates and configures the pins (input or output) for a specific atom type.
         * This is a simplified version. In practice, pin creation might be part of the ConcreteAtom constructor.
         * @param type The atom type (e.g., "Button").
         * @param pinType The type of pins to create (Pin.TYPE_INPUT or Pin.TYPE_OUTPUT).
         * @return A Vector of Pin instances.
         */
        private static function createPinsForType(type:String, pinType:String):Vector.<Pin> {
            var pins:Vector.<Pin> = new Vector.<Pin>();
            // Пример на основе старого кода
            switch (type) {
                case "Button":
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "Counter":
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
                    break;
                case "NumberDisplay":
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    break;
                default:
                    // Пины по умолчанию, если тип неизвестен
                    if (pinType === Pin.TYPE_INPUT) pins.push(new Pin("in", Pin.TYPE_INPUT, null));
                    if (pinType === Pin.TYPE_OUTPUT) pins.push(new Pin("out", Pin.TYPE_OUTPUT, null));
            }
            return pins;
        }

        // --- Утилиты ---

        /**
         * Gets all registered atom type names.
         * @return Array of registered atom type names.
         */
        public static function getRegisteredTypeNames():Array {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!registry) return [];
            
            var names:Array = [];
            for (var type:String in registry) {
                names.push(type);
            }
            return names;
        }

        /**
         * Gets information about a specific atom type.
         * @param atomType The atom type to get information for.
         * @return Object with atom type information, or null if not found.
         */
        public static function getAtomInfo(atomType:String):Object {
            var registry:Dictionary = DataManager.getData(REGISTRY_KEY) as Dictionary;
            if (!registry) return null;
            
            return registry[atomType];
        }
    }
}
