package library;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.types.ContactType;
import library.logic.NandAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;

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

        // --- 1. LOGIC PRIMITIVES (Foundation) ---
        // NAND - Универсальный базовый элемент
        reg("NAND", "NAND Gate",
            [{name: "A", type: INPUT}, {name: "B", type: INPUT}, {name: "Q", type: OUTPUT}],
            null // Logic is inside NandAtom class
        );

        // --- 2. ELECTRO COMPONENTS (I/O) ---
        
        // Button (Source)
        reg("Button", "Push Button",
            [{name: "out", type: OUTPUT, dataType: "bool"}],
            null
        );

        // LED (Display)
        reg("LED", "LED Indicator",
            [{name: "in", type: INPUT, dataType: "bool"}],
            null
        );

        // Relay (Commutator)
        reg("Relay", "Relay Switch",
            [
                {name: "signal", type: INPUT, dataType: "any"}, // Данные
                {name: "control", type: INPUT, dataType: "bool"}, // Управление
                {name: "out", type: OUTPUT, dataType: "any"}
            ],
            null
        );

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
            null
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