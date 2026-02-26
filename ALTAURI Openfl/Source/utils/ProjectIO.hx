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

        // 2. ВАЖНО: Создаем "Чистый" объект для сериализации.
        // Не сериализуем сам класс blueprint, иначе захватим функцию 'logic' -> Stack Overflow!
        var dataToSave:Dynamic = {
            version: "1.0",
            blueprint: {
                id: blueprint.id,
                name: blueprint.name,
                category: blueprint.category,
                pins: blueprint.pins, // Массив простых структур
                internalAtoms: blueprint.internalAtoms, // Массив простых структур
                internalConnections: blueprint.internalConnections // Массив простых структур
                // logic НЕ сохраняем! При загрузке она подтянется из AtomDefinitions.
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
                
                // --- Ручное конструирование Blueprint (безопасное) ---
                
                // 1. Pins
                var pins:Array<core.PinDef> = [];
                if (rawBp.pins != null) {
                    for (p in cast(rawBp.pins, Array<Dynamic>)) {
                        pins.push({
                            name: p.name,
                            type: _parseContactType(p.type),
                            defaultValue: p.defaultValue,
                            dataType: p.dataType
                        });
                    }
                }

                // 2. Atoms
                var atoms:Array<core.AtomDef> = [];
                if (rawBp.internalAtoms != null) {
                    for (a in cast(rawBp.internalAtoms, Array<Dynamic>)) {
                        atoms.push({
                            instanceId: a.instanceId,
                            typeId: a.typeId,
                            x: a.x,
                            y: a.y
                        });
                    }
                }

                // 3. Connections
                var conns:Array<core.ConnectionDef> = [];
                if (rawBp.internalConnections != null) {
                    for (c in cast(rawBp.internalConnections, Array<Dynamic>)) {
                        conns.push({
                            from: { atomId: c.from.atomId, contactName: c.from.contactName },
                            to: { atomId: c.to.atomId, contactName: c.to.contactName }
                        });
                    }
                }

                // 4. Создаем экземпляр класса
                var bp = new Blueprint(
                    rawBp.id,
                    rawBp.name,
                    pins,
                    null, // logic всегда null при загрузке
                    atoms,
                    conns,
                    rawBp.category
                );
                
                logger("IO: Blueprint built OK: " + bp.name);
                onComplete(bp);

            } catch (err:Dynamic) {
                logger("IO: PARSE ERROR! " + err);
                // Убираем опасный вывод стека, чтобы не спровоцировать краш
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

    private static function _parseContactType(val:Dynamic):ContactType {
        if (Std.isOfType(val, ContactType)) return val;
        if (Std.isOfType(val, String)) {
            switch(val) {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        return UNDEFINED;
    }
}