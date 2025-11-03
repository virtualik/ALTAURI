package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
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
            if (!AtomDefinitions.getSupportedTypes()) {
                trace("AtomFactory: WARNING - AtomDefinitions not initialized properly");
                AtomDefinitions.initialize();
            }
            _initialized = true;
            trace("AtomFactory: Initialized - ready to create validated atoms");
        }

        /**
         * Creates a complete atom instance with view based on type definition.
         */
        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) return null;

            // ✅ Используем статический generateId()
            var atom:Atom = new Atom(generateId(), type, position, name || type);

            // Создаём пины из определения
            for each (var pinDef:Object in definition.pins) {
                var pin:Pin = new Pin(pinDef.name, pinDef.type, null, pinDef.data || {});
                if (pinDef.type == Pin.TYPE_INPUT) {
                    atom.inputs.push(pin);
                } else if (pinDef.type == Pin.TYPE_OUTPUT) {
                    atom.outputs.push(pin);
                }
            }

            // Инициализируем поведение
            if (definition.behavior && definition.behavior.initialize is Function) {
                atom = definition.behavior.initialize(atom);
            }

            var view:AtomView = new AtomView(atom, windowType);
            return { atom: atom, view: view };
        }

        /**
         * Generate a unique ID for an atom
         * @private
         * @return {String} Unique atom ID
         */
        private static function generateId():String {
            _atomCounter++;
            return "atom_" + getTimer() + "_" + _atomCounter;
        }

        // Остальные методы (createPinsFromDefinition и т.д.) — оставь как есть,
        // но учти: они НЕ статические, а вызываются из статического контекста → это ошибка!

        // ❗ ВАЖНО: все вспомогательные методы должны быть СТАТИЧЕСКИМИ,
        // потому что AtomFactory используется только через статические вызовы.

        /**
         * Create pins from definition
         */
        public static function createPinsFromDefinition(atom:Atom, pinsDefinition:Array):void {
            if (!pinsDefinition) {
                trace("WARNING: No pins defined for atom: " + atom.type);
                return;
            }

            for each (var pinDef:Object in pinsDefinition) {
                try {
                    if (!pinDef.name) {
                        trace("ERROR: Pin definition missing name for atom: " + atom.type);
                        continue;
                    }
                    if (!pinDef.type || (pinDef.type != "input" && pinDef.type != "output")) {
                        trace("ERROR: Invalid pin type '" + pinDef.type + "' for pin '" + pinDef.name + "' in atom: " + atom.type);
                        continue;
                    }

                    var pinData:Object = {};
                    if (pinDef.dataType) pinData.dataType = pinDef.dataType;
                    if (pinDef.description) pinData.description = pinDef.description;

                    var pin:Pin = new Pin(pinDef.name, pinDef.type, null, pinData);

                    if (pinDef.type == "input") {
                        atom.inputs.push(pin);
                        trace("  Added input pin: " + pinDef.name + " (" + pinDef.dataType + ")");
                    } else {
                        atom.outputs.push(pin);
                        trace("  Added output pin: " + pinDef.name + " (" + pinDef.dataType + ")");
                    }
                } catch (error:Error) {
                    trace("ERROR: Failed to create pin '" + pinDef.name + "' for atom " + atom.type + ": " + error.message);
                }
            }

            trace("Created " + pinsDefinition.length + " pins for atom: " + atom.type);
        }

        /**
         * Apply view configuration (если AtomView поддерживает setBackgroundColor)
         * Но в твоём AtomView такого метода нет → лучше удалить или оставить заглушку
         */
        public static function applyViewConfig(view:AtomView, config:Object):void {
            // В текущей версии AtomView нет setBackgroundColor → пропускаем
            trace("View config application not implemented (AtomView has no setBackgroundColor)");
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
