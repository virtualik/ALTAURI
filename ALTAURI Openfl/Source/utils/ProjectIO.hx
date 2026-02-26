package utils;

import haxe.Json;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.utils.ByteArray;
import core.Blueprint;
import core.ContactType;
import Lambda;

class ProjectIO {

    private static var _currentFileRef:FileReference;
    public static var logger:String -> Void;

    public static function save(blueprint:Blueprint, nodes:Array<{id:String, x:Float, y:Float}>):Void {
        // 1. Обновляем координаты
        for (atomDef in blueprint.internalAtoms) {
            var nodeData = Lambda.find(nodes, function(n) return n.id == atomDef.instanceId);
            if (nodeData != null) {
                atomDef.x = nodeData.x;
                atomDef.y = nodeData.y;
            }
        }

        // 2. Сериализуем пины: тип принудительно в строку
        var pinsToSave = [];
        for (p in blueprint.pins) {
            pinsToSave.push({
                name: p.name,
                type: Std.string(p.type), // "INPUT", "OUTPUT"
                defaultValue: p.defaultValue,
                dataType: p.dataType
            });
        }

        var dataToSave:Dynamic = {
            version: "1.0",
            blueprint: {
                id: blueprint.id,
                name: blueprint.name,
                category: blueprint.category,
                pins: pinsToSave,
                internalAtoms: blueprint.internalAtoms,
                internalConnections: blueprint.internalConnections
            }
        };

        var json:String = Json.stringify(dataToSave, null, "  ");
        var fileRef = new FileReference();
        fileRef.save(json, blueprint.name + ".altauri");
    }

    public static function load(onComplete:Blueprint -> Void):Void {
        if (logger == null) logger = function(s) trace(s);
        logger("IO: Creating FileRef...");
        _currentFileRef = new FileReference();

        _currentFileRef.addEventListener(Event.SELECT, function(e) {
            logger("IO: File SELECTED!");
            _currentFileRef.load();
        });

        _currentFileRef.addEventListener(Event.COMPLETE, function(e) {
            logger("IO: File COMPLETE! Parsing...");
            try {
                var data:String = _currentFileRef.data.toString();
                var json:Dynamic = Json.parse(data);
                var rawBp:Dynamic = json.blueprint;

                // --- 1. PINS ---
                var pins:Array<core.PinDef> = [];
                if (rawBp.pins != null) {
                    for (p in cast(rawBp.pins, Array<Dynamic>)) {
                        pins.push({
                            name: Std.string(p.name), // Защита от i32
                            type: _parseContactType(p.type),
                            defaultValue: p.defaultValue,
                            dataType: Std.string(p.dataType)
                        });
                    }
                }

                // --- 2. ATOMS ---
                var atoms:Array<core.AtomDef> = [];
                if (rawBp.internalAtoms != null) {
                    for (a in cast(rawBp.internalAtoms, Array<Dynamic>)) {
                        // Безопасное чтение координат
                        var posX:Float = 0.0;
                        var posY:Float = 0.0;
                        
                        if (a.x != null) {
                            var vx = Std.parseFloat(Std.string(a.x));
                            if (!Math.isNaN(vx)) posX = vx;
                        }
                        if (a.y != null) {
                            var vy = Std.parseFloat(Std.string(a.y));
                            if (!Math.isNaN(vy)) posY = vy;
                        }

                        atoms.push({
                            instanceId: Std.string(a.instanceId), // Защита от i32
                            typeId: Std.string(a.typeId),         // Защита от i32
                            x: posX,
                            y: posY
                        });
                    }
                }

                // --- 3. CONNECTIONS ---
                var conns:Array<core.ConnectionDef> = [];
                if (rawBp.internalConnections != null) {
                    for (c in cast(rawBp.internalConnections, Array<Dynamic>)) {
                        conns.push({
                            from: { 
                                atomId: Std.string(c.from.atomId),     // Защита от i32
                                contactName: Std.string(c.from.contactName) 
                            },
                            to: { 
                                atomId: Std.string(c.to.atomId),       // Защита от i32
                                contactName: Std.string(c.to.contactName) 
                            }
                        });
                    }
                }

                // 4. Создаем Blueprint
                var bp = new Blueprint(
                    Std.string(rawBp.id),
                    Std.string(rawBp.name),
                    pins,
                    null, // logic
                    atoms,
                    conns,
                    Std.string(rawBp.category)
                );

                logger("IO: Blueprint built OK: " + bp.name);
                onComplete(bp);

            } catch (err:Dynamic) {
                logger("IO: PARSE ERROR! " + err);
                // Вывод стека может помочь, но иногда крашит, оставим так
            }
            _currentFileRef = null;
        });

        _currentFileRef.addEventListener(IOErrorEvent.IO_ERROR, function(e) {
            logger("IO: IO_ERROR! " + e.text);
            _currentFileRef = null;
        });

        _currentFileRef.addEventListener(Event.CANCEL, function(e) {
            logger("IO: Dialog CANCELLED");
            _currentFileRef = null;
        });

        logger("IO: Opening browse()...");
        _currentFileRef.browse();
    }

    // --- Улучшенный парсер типов ---
    private static function _parseContactType(val:Dynamic):ContactType {
        // Если это уже Enum (маловероятно при загрузке из JSON, но возможно)
        if (Std.isOfType(val, ContactType)) return val;

        // Если это строка
        if (Std.isOfType(val, String)) {
            switch(Std.string(val)) {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        // Если это число (Int или Float)
        // JSON парсеры могут выдавать Int
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