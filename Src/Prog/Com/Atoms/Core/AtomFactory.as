package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;

    /**
     * Factory class for creating atoms and their views based on data definitions.
     * 
     * @class AtomFactory
     * @public
     */
    public class AtomFactory {
        
        /**
         * Creates a complete atom instance with view based on type definition.
         * 
         * @param {String} type - Atom type to create
         * @param {Point} position - Initial position
         * @param {String} windowType - Window context for view rendering
         * @param {String} name - Display name (optional)
         * @return {Object} Object containing {atom: Atom, view: AtomView} or null if type not found
         */
        public static function createAtom(type:String, position:Point, windowType:String = "Editor", name:String = null):Object {
            var definition:Object = AtomDefinitions.getAtomDefinition(type);
            if (!definition) return null;

            // Create atom instance
            var atom:Atom = new Atom(generateId(), type, position, name);
            
            // Create pins from definition
for each (var pinDef1:Object in definition.pins.inputs) {
    var inputPin:Pin = new Pin(pinDef1.name, Pin.TYPE_INPUT);
    // Копируем дополнительные данные из определения
    if (pinDef1.data) {
        for (var key1:String in pinDef1.data) {
            inputPin.data[key1] = pinDef1.data[key1];
        }
    }
    atom.inputs.push(inputPin);
}

for each (var pinDef2:Object in definition.pins.outputs) {
    var outputPin:Pin = new Pin(pinDef2.name, Pin.TYPE_OUTPUT);
    // Копируем дополнительные данные из определения
    if (pinDef2.data) {
        for (var key2:String in pinDef2.data) {
            outputPin.data[key2] = pinDef2.data[key2];
        }
    }
    atom.outputs.push(outputPin);
}            
            // Initialize atom using behavior function
            atom = definition.behavior.initialize(atom);
            
            // Create view with appropriate window context
            var view:AtomView = new AtomView(atom, windowType);
            
            return { atom: atom, view: view };
        }

        /**
         * Generates a unique identifier for atoms.
         * 
         * @private
         * @return {String} Unique ID string
         */
        private static function generateId():String {
            return "atom_" + new Date().getTime() + "_" + Math.round(Math.random() * 1000000);
        }
    }
}
