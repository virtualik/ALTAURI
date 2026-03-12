package library;

import core.data.Blueprint;
import core.types.ContactType;

/**
 * Atom Registry v2.0
 * Stores and manages blueprints for all atom types.
 */
class AtomRegistry {

    private static var _initialized:Bool = false;
    private static var _blueprints:Map<String, Blueprint> = new Map();

    public static var customLibraryPath:String = "";

    private static function reg(id:String, name:String, pins:Array<core.data.Blueprint.PinDef>, ?logic) {
        _blueprints.set(id, new Blueprint(id, name, pins, logic));
    }

    public static function getAllIds():Array<String> {
        return [for (key in _blueprints.keys()) key];
    }

    public static function initialize():Void {
        if (_initialized) return;

        // Native Atoms Registration
        reg("NAND", "NAND Gate",
            [{name: "A", type: INPUT}, {name: "B", type: INPUT}, {name: "Q", type: OUTPUT}],
            function(v) return [!(v[0] && v[1])]
        );
        reg("Button", "Push Button", [{name: "out", type: OUTPUT, dataType: "bool"}], null);
        reg("LED", "LED Indicator", [{name: "in", type: INPUT, dataType: "bool"}], null);
        reg("Relay", "Relay Switch",
            [
                {name: "signal", type: INPUT, dataType: "any"},
                {name: "control", type: INPUT, dataType: "bool"},
                {name: "out", type: OUTPUT, dataType: "any"}
            ], null
        );
        reg("Pass", "Pass Through", [{name: "in", type: INPUT}, {name: "out", type: OUTPUT}], function(v) return v);
        reg("SensorMock", "Random Sensor", [{name: "value", type: OUTPUT, dataType: "number", defaultValue: 0}], null);
        reg("FPSMonitorAtom", "FPS Monitor Atom", [{name: "fps", type: OUTPUT, dataType: "number", defaultValue: 0}], null);
        reg("FrameTimeAtom", "Frame Time (ms)", [{name: "ms", type: OUTPUT, dataType: "number", defaultValue: 0.0}], null);
        reg("AlphaNumericLine", "Display", [{name: "in", type: INPUT, dataType: "any"}], null);

        _initialized = true;
    }

    public static function get(id:String):Blueprint {
        return _blueprints.get(id);
    }

    public static function registerBlueprint(id:String, bp:Blueprint):Void {
        _blueprints.set(id, bp);
    }

    public static function remove(id:String):Bool {
        if (_blueprints.exists(id)) {
            _blueprints.remove(id);
            trace('AtomRegistry: Removed $id');
            return true;
        }
        return false;
    }

    public static function scanFolder(path:String):Void {
        #if sys
        if (!sys.FileSystem.exists(path)) {
            try { sys.FileSystem.createDirectory(path); } catch(e:Dynamic) { trace("Error creating library dir: " + e); }
            return;
        }
        trace("Scanning library folder: " + path);
        for (file in sys.FileSystem.readDirectory(path)) {
            if (StringTools.endsWith(file, ".atom")) {
                var fullPath = path + "/" + file;
                loadAtomFile(fullPath);
            }
        }
        #end
    }

    public static function loadAtomFile(fullPath:String):Bool {
        #if sys
        try {
            var content = sys.io.File.getContent(fullPath);
            var json = haxe.Json.parse(content);
            var rawBp:Dynamic = json.blueprint;

            var pins:Array<core.data.Blueprint.PinDef> = [];
            if (rawBp.pins != null) {
                var seenNames = new Map<String, Bool>();
                for (p in (cast(rawBp.pins, Array<Dynamic>))) {
                    var pinName = Std.string(p.name);
                    if (!seenNames.exists(pinName)) {
                        pins.push({
                            name: pinName,
                            type: _parseContactType(p.type),
                            defaultValue: p.defaultValue,
                            dataType: Std.string(p.dataType)
                        });
                        seenNames.set(pinName, true);
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
                null,
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
        #else
        return false;
        #end
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
        return UNDEFINED;
    }
}
