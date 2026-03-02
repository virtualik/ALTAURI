package system.io;

import haxe.Json;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.events.SecurityErrorEvent;
import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.types.ContactType;
import Lambda;

/**
 * PROJECT I/O v2.0 (Fixed)
 * Safe file operations with proper listener cleanup.
 */
class ProjectIO {

    private static var _currentFileRef:FileReference;
    private static var _onLoadComplete:{blueprint:Blueprint, viewState:{x:Float, y:Float, zoom:Float}} -> Void;
    public static var logger:String -> Void;

    // ========== ИСПРАВЛЕНИЕ: Флаг для защиты от race condition ==========
    private static var _isLoading:Bool = false;
    // ====================================================================

    public static function save(blueprint:Blueprint, nodes:Array<{id:String, x:Float, y:Float}>, viewState:{x:Float, y:Float, zoom:Float}):Void {
        // 1. Update coordinates
        for (atomDef in blueprint.internalAtoms) {
            var nodeData = Lambda.find(nodes, function(n) return n.id == atomDef.instanceId);
            if (nodeData != null) {
                atomDef.x = nodeData.x;
                atomDef.y = nodeData.y;
            }
        }

        // 2. Serialize pins
        var pinsToSave = [];
        for (p in blueprint.pins) {
            pinsToSave.push({
                name: p.name,
                type: Std.string(p.type),
                defaultValue: p.defaultValue,
                dataType: p.dataType
            });
        }

        var dataToSave:Dynamic = {
            version: "1.1",
            blueprint: {
                id: blueprint.id,
                name: blueprint.name,
                category: blueprint.category,
                pins: pinsToSave,
                internalAtoms: blueprint.internalAtoms,
                internalConnections: blueprint.internalConnections
            },
            editor: {
                x: viewState.x,
                y: viewState.y,
                zoom: viewState.zoom
            }
        };

        var json:String = Json.stringify(dataToSave, null, "  ");
        var fileRef = new FileReference();
        fileRef.save(json, blueprint.name + ".atom");
    }

    public static function load(onComplete:{blueprint:Blueprint, viewState:{x:Float, y:Float, zoom:Float}} -> Void):Void {
        if (logger == null) logger = function(s) trace(s);

        // ========== ИСПРАВЛЕНИЕ: Проверка на повторный вызов ==========
        if (_isLoading) {
            logger("IO: WARNING - Load already in progress, ignoring duplicate call");
            return;
        }
        _isLoading = true;
        // ==============================================================

        // ========== ИСПРАВЛЕНИЕ: Очистка предыдущего FileReference ==========
        cleanupFileRef();
        // ===================================================================

        logger("IO: Creating FileRef...");
        _onLoadComplete = onComplete;
        _currentFileRef = new FileReference();

        // ========== ИСПРАВЛЕНИЕ: Именованные обработчики для возможности удаления ==========
        _currentFileRef.addEventListener(Event.SELECT, onSelect);
        _currentFileRef.addEventListener(Event.COMPLETE, onCompleteLoad);
        _currentFileRef.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
        _currentFileRef.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
        _currentFileRef.addEventListener(Event.CANCEL, onCancel);
        // ===================================================================================

        logger("IO: Opening browse()...");
        try {
            _currentFileRef.browse();
            logger("IO: browse() called successfully");
        } catch (e:Dynamic) {
            logger("IO: CRASH in browse() - " + Std.string(e));
            _isLoading = false;
            cleanupFileRef();
        }
    }

    // ========== ИСПРАВЛЕНИЕ: Именованные обработчики ==========

    private static function onSelect(e:Event):Void {
        if (logger != null) logger("IO: File SELECTED - " + _currentFileRef.name);
        _currentFileRef.load();
    }

    private static function onCompleteLoad(e:Event):Void {
        if (logger != null) logger("IO: File COMPLETE! Parsing...");

        try {
            var data:String = _currentFileRef.data.toString();
            var json:Dynamic = Json.parse(data);
            var rawBp:Dynamic = json.blueprint;

            // --- 1. PINS ---
            var pins:Array<PinDef> = [];
            if (rawBp.pins != null) {
                for (p in cast(rawBp.pins, Array<Dynamic>)) {
                    pins.push({
                        name: Std.string(p.name),
                        type: _parseContactType(p.type),
                        defaultValue: p.defaultValue,
                        dataType: Std.string(p.dataType)
                    });
                }
            }

            // --- 2. ATOMS ---
            var atoms:Array<AtomDef> = [];
            if (rawBp.internalAtoms != null) {
                for (a in cast(rawBp.internalAtoms, Array<Dynamic>)) {
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
                        instanceId: Std.string(a.instanceId),
                        typeId: Std.string(a.typeId),
                        x: posX,
                        y: posY
                    });
                }
            }

            // --- 3. CONNECTIONS ---
            var conns:Array<ConnectionDef> = [];
            if (rawBp.internalConnections != null) {
                for (c in cast(rawBp.internalConnections, Array<Dynamic>)) {
                    conns.push({
                        from: {
                            atomId: Std.string(c.from.atomId),
                            contactName: Std.string(c.from.contactName)
                        },
                        to: {
                            atomId: Std.string(c.to.atomId),
                            contactName: Std.string(c.to.contactName)
                        }
                    });
                }
            }

            // 4. Create Blueprint
            var bp = new Blueprint(
                Std.string(rawBp.id),
                Std.string(rawBp.name),
                pins,
                null,
                atoms,
                conns,
                Std.string(rawBp.category)
            );

            // ========== ИСПРАВЛЕНИЕ: Безопасный парсинг editor state ==========
            var viewState:{x:Float, y:Float, zoom:Float} = {x: 0.0, y: 0.0, zoom: 1.0};
            if (json.editor != null) {
                viewState.x = _safeParseFloat(json.editor.x, 0.0);
                viewState.y = _safeParseFloat(json.editor.y, 0.0);
                viewState.zoom = _safeParseFloat(json.editor.zoom, 1.0);
            }
            // ===================================================================

            if (logger != null) logger("IO: Blueprint built OK: " + bp.name);

            // Cleanup before callback
            _isLoading = false;
            cleanupFileRef();

            // Call callback
            if (_onLoadComplete != null) {
                _onLoadComplete({blueprint: bp, viewState: viewState});
            }
            _onLoadComplete = null;

        } catch (err:Dynamic) {
            if (logger != null) logger("IO: PARSE ERROR! " + Std.string(err));
            _isLoading = false;
            cleanupFileRef();
            _onLoadComplete = null;
        }
    }

    private static function onIOError(e:IOErrorEvent):Void {
        if (logger != null) logger("IO: IO_ERROR! " + e.text);
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }

    private static function onSecurityError(e:SecurityErrorEvent):Void {
        if (logger != null) logger("IO: SECURITY_ERROR! " + e.text);
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }

    private static function onCancel(e:Event):Void {
        if (logger != null) logger("IO: Dialog CANCELLED");
        _isLoading = false;
        cleanupFileRef();
        _onLoadComplete = null;
    }

    // ========== ИСПРАВЛЕНИЕ: Метод очистки FileReference ==========
    private static function cleanupFileRef():Void {
        if (_currentFileRef != null) {
            _currentFileRef.removeEventListener(Event.SELECT, onSelect);
            _currentFileRef.removeEventListener(Event.COMPLETE, onCompleteLoad);
            _currentFileRef.removeEventListener(IOErrorEvent.IO_ERROR, onIOError);
            _currentFileRef.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
            _currentFileRef.removeEventListener(Event.CANCEL, onCancel);
            _currentFileRef = null;
        }
    }
    // ==============================================================

    // ========== ИСПРАВЛЕНИЕ: Безопасный парсинг Float ==========
    private static function _safeParseFloat(value:Dynamic, defaultValue:Float):Float {
        if (value == null) return defaultValue;
        var result = Std.parseFloat(Std.string(value));
        if (Math.isNaN(result)) return defaultValue;
        return result;
    }
    // ===========================================================

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