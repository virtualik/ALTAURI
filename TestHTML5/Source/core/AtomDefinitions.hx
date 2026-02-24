package core;

class AtomDefinitions {
    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();

    private static function reg(id:String, name:String, pins:Array<Blueprint.PinDef>, ?logic) {
        _blueprints.set(id, new Blueprint(id, name, pins, logic));
    }

    public static function initialize():Void {
        if (_initialized) return;

        // --- INPUTS (Sources) ---
        
        reg("SensorMock", "Random Sensor", 
            [{name: "value", type: OUTPUT, dataType: "number", defaultValue: 0}],
            null 
        );
		
		reg("FPSMonitor", "FPS Monitor", 
            [{name: "fps", type: OUTPUT, dataType: "number", defaultValue: 0}],
            null 
        );
        // --- OUTPUTS (Displays) ---
        
        reg("AlphaNumericLine", "Display", 
            [{name: "in", type: INPUT, dataType: "any"}],
            null // Logic is handled by View, usually
        );
        
        // --- LOGIC (Basics) ---
        
        reg("Pass", "Pass Through", 
            [{name: "in", type: INPUT}, {name: "out", type: OUTPUT}],
            function(v) return v
        );

        _initialized = true;
    }

    public static function get(id:String):Blueprint {
        return _blueprints.get(id);
    }
}