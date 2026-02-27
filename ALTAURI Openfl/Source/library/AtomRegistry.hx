package library;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.types.ContactType;

/**
 * ATOM REGISTRY v1.0
 * Centralized registry for Atom Blueprints.
 */
class AtomRegistry {
    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();

    private static function reg(id:String, name:String, pins:Array<PinDef>, ?logic) {
        _blueprints.set(id, new Blueprint(id, name, pins, logic));
    }

    public static function getAllIds():Array<String> {
        return [for (key in _blueprints.keys()) key];
    }

    public static function initialize():Void {
        if (_initialized) return;

        // --- INPUTS (Sources) ---

        reg("SensorMock", "Random Sensor",
            [{name: "value", type: OUTPUT, dataType: "number", defaultValue: 0}],
            null
        );

        reg("FPSMonitorAtom", "FPS Monitor Atom",
            [{name: "fps", type: OUTPUT, dataType: "number", defaultValue: 0}],
            null
        );

        reg("FrameTimeAtom", "Frame Time (ms)",
            [{name: "ms", type: OUTPUT, dataType: "number", defaultValue: 0.0}],
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