package src.prog.com.Элемент {
    import flash.geom.Point;
    import flash.utils.Dictionary;

    /**
     * Universal immutable atom class representing any computational component.
     * Serves as the core data container for all Element types - no subclassing needed.
     * Follows immutable patterns for state management.
     *
     * @class Элемент
     * @public
     */
    public class Элемент {
        
        /** Unique identifier for the atom */
        public var id:String;
        
        /** Position on the canvas in world coordinates */
        public var position:Point;
        
        /** Display name shown in the UI */
        public var name:String;
        
        /** Atom type identifier (e.g., "Button", "LED") */
        public var type:String;
        
        /** Dynamic data storage for atom-specific properties and state */
        public var data:Object;
        
        /** Collection of input pins */
        public var inputs:Vector.<Pin>;
        
        /** Collection of output pins */
        public var outputs:Vector.<Pin>;

        /**
         * Creates a new Element instance.
         *
         * @constructor
         * @param {String} id - Unique identifier
         * @param {String} type - Element type identifier (e.g., "Button", "LED")
         * @param {Point} position - Element position on canvas (X/Y)
         * @param {String} name - Display name (optional, defaults to type)
         */
        public function Элемент(id:String, type:String, position:Point, name:String = null) {
            this.id = id;
            this.type = type;
            //this.position = position.clone();
            this.name = name || type;
            this.data = new Object();
            this.inputs = new Vector.<Pin>();
            this.outputs = new Vector.<Pin>();
        }
}