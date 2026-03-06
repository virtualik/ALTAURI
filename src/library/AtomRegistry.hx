package library;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.types.ContactType;
import library.logic.NandAtom;
import library.electro.ButtonAtom;
import library.electro.LedAtom;
import library.electro.RelayAtom;
import sys.FileSystem;
import sys.io.File;

class AtomRegistry {
    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();

    // Путь к библиотеке будет установлен извне
    public static var customLibraryPath:String = "";

    private static function reg(id:String, name:String, pins:Array<PinDef>, ?logic) {
        _blueprints.set(id, new Blueprint(id, name, pins, logic));
    }

    public static function getAllIds():Array<String> {
        return [for (key in _blueprints.keys()) key];
    }

    public static function initialize():Void {
        if (_initialized) return;

        // --- 1. NATIVE ATOMS (Logic defined in code) ---
        
        reg("NAND", "NAND Gate",
            [{name: "A", type: INPUT}, {name: "B", type: INPUT}, {name: "Q", type: OUTPUT}],
            function(v) return [!(v[0] && v[1])]
        );

        reg("Button", "Push Button",
            [{name: "out", type: OUTPUT, dataType: "bool"}],
            null // Logic handled by View/Driver interaction usually, or just toggle
        );

        reg("LED", "LED Indicator",
            [{name: "in", type: INPUT, dataType: "bool"}],
            null
        );

        reg("Relay", "Relay Switch",
            [
                {name: "signal", type: INPUT, dataType: "any"},
                {name: "control", type: INPUT, dataType: "bool"},
                {name: "out", type: OUTPUT, dataType: "any"}
            ],
            null // Logic handled in RelayAtom class (if it exists) or logic func
            // Note: If RelayAtom is a class extending Atom, Factory handles it.
            // If we want it to be generic Assembly, we add logic here.
        );
        
        reg("Pass", "Pass Through",
            [{name: "in", type: INPUT}, {name: "out", type: OUTPUT}],
            function(v) return v
        );

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

        reg("AlphaNumericLine", "Display",
            [{name: "in", type: INPUT, dataType: "any"}],
            null
        );

        _initialized = true;
    }

    public static function get(id:String):Blueprint {
        return _blueprints.get(id);
    }

    public static function registerBlueprint(id:String, bp:Blueprint):Void {
        _blueprints.set(id, bp);
    }

    // --- SCAN FOLDER ---
    public static function scanFolder(path:String):Void {
        if (!FileSystem.exists(path)) {
            try {
                FileSystem.createDirectory(path);
            } catch(e:Dynamic) {
                trace("Error creating library dir: " + e);
            }
            return;
        }

        trace("Scanning library folder: " + path);

        for (file in FileSystem.readDirectory(path)) {
            if (StringTools.endsWith(file, ".atom")) {
                var fullPath = path + "/" + file;
                loadAtomFile(fullPath);
            }
        }
    }

    public static function loadAtomFile(fullPath:String):Bool {
        try {
            var content = File.getContent(fullPath);
            var json = haxe.Json.parse(content);
            var rawBp:Dynamic = json.blueprint;

			var pins:Array<PinDef> = [];
			if (rawBp.pins != null) {
				var seenNames = new Map<String, Bool>();  // ИСПРАВЛЕНИЕ: Отслеживание дубликатов
				for (p in (cast(rawBp.pins, Array<Dynamic>))) {
					var pinName = Std.string(p.name);
					if (!seenNames.exists(pinName)) {  // Пропустить дубликаты
						pins.push({
							name: pinName,
							type: _parseContactType(p.type),
							defaultValue: p.defaultValue,
							dataType: Std.string(p.dataType)
						});
						seenNames.set(pinName, true);
					} else {
						trace('WARN: Duplicate pin "$pinName" skipped in ${Std.string(rawBp.id)}');
					}
				}
			}

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
                null, // Logic is always null for loaded files (Custom Assemblies)
                atoms,
                conns,
                Std.string(rawBp.category)
            );

            registerBlueprint(bp.id, bp);
            trace("Library loaded: " + bp.id);
            return true;
        } catch(e:Dynamic) {
            trace("Failed to load atom: " + fullPath + " | Error: " + e);
            return false;
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
}