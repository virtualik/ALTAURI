package src.prog.com.Элемент {
    import flash.geom.Point;
    import flash.utils.Dictionary;

    /**
     * Represents a connection point (input or output) for data flow between atoms.
     * Manages data listeners for direct peer-to-peer communication.
     * Follows immutable patterns for state management.
     *
     * @class Контакт
     * @public
     */
    public class Контакт {
        /** Input pin type constant */
        public static const TYPE_INPUT:String = "input";
        
        /** Output pin type constant */
        public static const TYPE_OUTPUT:String = "output";

        /** Unique identifier for the pin */
        public var id:String;
        
        /** Pin name for identification */
        public var name:String;
        
        /** Pin type (input or output) */
        public var type:String;
        
        /** Additional pin properties (data type, description, etc.) */
        public var data:Object;
        
        /** Collection of listener functions for data changes */
        private var _listeners:Vector.<Function>;
        
        /** Backing field for pin value */
        private var _value:*;
        
        public function Контакт() {}
}