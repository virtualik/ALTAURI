package library;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.types.ContactType;
// Импорты для классов, если используются в логике по умолчанию
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
                {name: "signal", type: INPUT, dataType: "any"},
                {name: "control", type: INPUT, dataType: "bool"},
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

    // --- НОВОЕ: Регистрация сборок ---

    public static function registerBlueprint(id:String, bp:Blueprint):Void {
        _blueprints.set(id, bp);
    }

    // --- НОВОЕ: Сканирование папки ---
    #if sys
    public static function scanFolder(path:String):Void {
        if (!sys.FileSystem.exists(path)) {
            sys.FileSystem.createDirectory(path);
            return;
        }
        
        trace("Scanning library folder: " + path);
        
        for (file in sys.FileSystem.readDirectory(path)) {
            if (StringTools.endsWith(file, ".atom")) {
                var fullPath = path + "/" + file;
                try {
                    var content = sys.io.File.getContent(fullPath);
                    var json = haxe.Json.parse(content);
                    var rawBp:Dynamic = json.blueprint;

                    // Восстанавливаем типы
                    var pins:Array<PinDef> = [];
                    if (rawBp.pins != null) {
                        for (p in (cast(rawBp.pins, Array<Dynamic>))) {
                            pins.push({
                                name: Std.string(p.name),
                                type: _parseContactType(p.type),
                                defaultValue: p.defaultValue,
                                dataType: Std.string(p.dataType)
                            });
                        }
                    }
                    
                    // Восстанавливаем связи (нужно привести типы)
                    var conns = [];
                    if (rawBp.internalConnections != null) {
                        for(c in (cast(rawBp.internalConnections, Array<Dynamic>))) {
                            conns.push({
                                from: { atomId: Std.string(c.from.atomId), contactName: Std.string(c.from.contactName) },
                                to: { atomId: Std.string(c.to.atomId), contactName: Std.string(c.to.contactName) }
                            });
                        }
                    }
                    
                    var atoms = [];
                     if (rawBp.internalAtoms != null) {
                        for(a in (cast(rawBp.internalAtoms, Array<Dynamic>))) {
                            atoms.push({
                                instanceId: Std.string(a.instanceId),
                                typeId: Std.string(a.typeId),
                                x: a.x,
                                y: a.y
                            });
                        }
                    }

                    var bp = new Blueprint(
                        Std.string(rawBp.id),
                        Std.string(rawBp.name),
                        pins,
                        null,
                        atoms,
                        conns,
                        Std.string(rawBp.category)
                    );

                    registerBlueprint(bp.id, bp);
                    trace("Library loaded: " + bp.id);
                } catch(e:Dynamic) {
                    trace("Failed to load atom: " + file + " | Error: " + e);
                }
            }
        }
    }

    private static function _parseContactType(val:Dynamic):ContactType {
        if (Std.isOfType(val, ContactType)) return val;
        if (Std.isOfType(val, String)) {
            switch(Std.string(val)) {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        if (Std.isOfType(val, Int) || Std.isOfType(val, Float)) {
            var index = Std.int(val);
            switch(index) {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        return UNDEFINED;
    }
    #end
}