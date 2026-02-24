package core;

// Updated to ensure all necessary types are registered for Serialization lookup

class AtomDefinitions {
    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();

    public static function initialize():Void {
        if (_initialized) return;

        // --- Primitives ---
        
        register(new Blueprint("NumberSource", "Number Source",
            [{name: "out", type: ContactType.OUTPUT, dataType: "number", defaultValue: 0}],
            null
        ));

        register(new Blueprint("PassThrough", "Pass Through",
            [
                {name: "in", type: ContactType.INPUT, dataType: "number"},
                {name: "out", type: ContactType.OUTPUT, dataType: "number"}
            ],
            function(vals) return [vals[0]]
        ));

        register(new Blueprint("Adder", "Adder", 
            [
                {name: "a", type: ContactType.INPUT, dataType: "number"},
                {name: "b", type: ContactType.INPUT, dataType: "number"},
                {name: "sum", type: ContactType.OUTPUT, dataType: "number"}
            ],
            function(vals) {
                var a = (vals[0] != null) ? vals[0] : 0;
                var b = (vals[1] != null) ? vals[1] : 0;
                return [a + b]; 
            }
        ));

        // --- Composite Example ---

        register(new Blueprint(
            "Doubler", "Doubler (x2)",
            [
                {name: "input", type: ContactType.INPUT, dataType: "number"},
                {name: "output", type: ContactType.OUTPUT, dataType: "number"}
            ],
            null, 
            [ { instanceId: "adder1", typeId: "Adder" } ],
            [
                { from: {atomId: "SELF", contactName: "input"}, to: {atomId: "adder1", contactName: "a"} },
                { from: {atomId: "SELF", contactName: "input"}, to: {atomId: "adder1", contactName: "b"} },
                { from: {atomId: "adder1", contactName: "sum"}, to: {atomId: "SELF", contactName: "output"} }
            ]
        ));

        _initialized = true;
    }

    public static function register(bp:Blueprint):Void {
        _blueprints.set(bp.id, bp);
    }

    public static function get(id:String):Blueprint {
        return _blueprints.get(id);
    }
}