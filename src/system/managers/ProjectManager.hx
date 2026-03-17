package system.managers;

import haxe.Json;
import core.base.Assembly;
import core.base.Atom;
import core.data.Blueprint;
import core.types.ContactType;
import library.AtomRegistry;
import utils.UID;

// !!! ВАЖНО: using вместо import для методов .replace и .endsWith !!!
using StringTools;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * PROJECT MANAGER v2.2 (Window Position Persistence)
 * Отвечает за файловую систему, пути и сохранение/загрузку проектов.
 * Выносит всю IO логику из Main.
 *
 * v2.2 Changes:
 * - Added windowX/windowY to saved data and return types
 */
class ProjectManager {

    private static var _instance:ProjectManager;

    public var documentsPath:String;
    public var libraryPath:String;
    public var selfrunPath:String;

    public static function getInstance():ProjectManager {
        if (_instance == null) _instance = new ProjectManager();
        return _instance;
    }

    private function new() {}

    /**
     * Инициализация путей и проверка папок.
     */
    public function init():Void {
        #if sys
        var home = Sys.getEnv("HOME");
        if (home == null) home = Sys.getEnv("USERPROFILE");

        if (home != null) {
            home = home.replace("\\", "/");
            if (!home.endsWith("/")) home += "/";
            documentsPath = home + "Documents";
        } else {
            documentsPath = Sys.getCwd();
        }

        var altauriRoot = documentsPath + "/ALTAURI";
        libraryPath = altauriRoot + "/Library";
        selfrunPath = altauriRoot + "/Selfrun.atom";

        if (!FileSystem.exists(altauriRoot)) FileSystem.createDirectory(altauriRoot);
        if (!FileSystem.exists(libraryPath)) FileSystem.createDirectory(libraryPath);

        AtomRegistry.customLibraryPath = libraryPath;

        // Сканируем библиотеку
        AtomRegistry.scanFolder(libraryPath);
        #else
        selfrunPath = "Selfrun.atom";
        libraryPath = "library";
        #end
    }

    /**
     * Сохранить корневой проект (Selfrun).
     * v2.2: Added windowX, windowY
     */
    public function saveSelfrun(
        rootAssembly:Assembly,
        viewState:{x:Float, y:Float, zoom:Float},
        deviceWindowData:Array<{path:Array<String>, x:Float, y:Float, ?width:Float, ?height:Float}>,
        isDeviceWindowOpen:Bool,
        ?windowWidth:Float = 420,
        ?windowHeight:Float = 320,
        ?windowX:Float = 100,
        ?windowY:Float = 100
    ):Void {
        #if sys
        if (rootAssembly == null) return;

        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in rootAssembly.blueprint.internalAtoms) {
            var runtimeId = rootAssembly.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;

            var atomInstance:Atom = cast rootAssembly.internalAtoms.get(runtimeId);
            var values:Dynamic = null;
            if (atomInstance != null) {
                values = atomInstance.getPersistentState();
            }

            atomsToSave.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y,
                values: values
            });
        }

        var connsToSave:Array<Dynamic> = [];
        for (conn in rootAssembly.blueprint.internalConnections) {
            var fromId = conn.from.atomId;
            var toId = conn.to.atomId;

            if (fromId != "SELF") fromId = rootAssembly.getTemplateId(fromId);
            if (toId != "SELF") toId = rootAssembly.getTemplateId(toId);

            connsToSave.push({
                from: { atomId: fromId, contactName: conn.from.contactName },
                to: { atomId: toId, contactName: conn.to.contactName }
            });
        }

        var bp = rootAssembly.blueprint;

        var devicesToSave:Array<Dynamic> = [];
        if (deviceWindowData != null) {
            for (d in deviceWindowData) {
                var w:Float = (d.width != null) ? d.width : 100.0;
                var h:Float = (d.height != null) ? d.height : 80.0;
                devicesToSave.push({
                    path: d.path,
                    x: d.x,
                    y: d.y,
                    width: w,
                    height: h
                });
            }
        }

        var data:Dynamic = {
            version: "2.2",
            blueprint: {
                id: bp.id,
                name: bp.name,
                category: bp.category,
                pins: bp.pins,
                internalAtoms: atomsToSave,
                internalConnections: connsToSave
            },
            editor: viewState,
            deviceWindow: {
                isOpen: isDeviceWindowOpen,
                x: windowX,
                y: windowY,
                width: windowWidth,
                height: windowHeight,
                devices: devicesToSave
            }
        };

        try {
            File.saveContent(selfrunPath, haxe.Json.stringify(data, null, "  "));
            trace("ProjectManager: Selfrun saved (v2.2 with window pos).");
        } catch(e:Dynamic) {
            trace("Error saving Selfrun: " + e);
        }

        saveInternalAssemblies(rootAssembly);
        #end
    }

    /**
     * Загрузить данные Selfrun.
     * v2.2: Returns window X, Y
     */
    public function loadSelfrun():{
        blueprint:Blueprint,
        view:{x:Float, y:Float, zoom:Float},
        devices:Array<{
            path:Array<String>,
            x:Float,
            y:Float,
            ?width:Float,
            ?height:Float
        }>,
        isOpen:Bool,
        windowX:Float,
        windowY:Float,
        windowWidth:Float,
        windowHeight:Float
    } {
        #if sys
        if (!FileSystem.exists(selfrunPath)) return null;

        try {
            var content = File.getContent(selfrunPath);
            var json = haxe.Json.parse(content);
            var rawBp:Dynamic = json.blueprint;
            var bp = parseBlueprintFromJson(rawBp);

            var viewState = {x: 0.0, y: 0.0, zoom: 1.0};
            if (json.editor != null) {
                viewState.x = _safeFloat(json.editor.x);
                viewState.y = _safeFloat(json.editor.y);
                viewState.zoom = _safeFloat(json.editor.zoom);
            }

            var devices:Array<{
                path:Array<String>,
                x:Float,
                y:Float,
                ?width:Float,
                ?height:Float
            }> = [];
            var isOpen = false;
            var windowX = 100.0;
            var windowY = 100.0;
            var windowWidth = 420.0;
            var windowHeight = 320.0;

            if (json.deviceWindow != null) {
                isOpen = json.deviceWindow.isOpen;

                windowX = _safeFloat(json.deviceWindow.x, 100);
                windowY = _safeFloat(json.deviceWindow.y, 100);
                windowWidth = _safeFloat(json.deviceWindow.width, 420);
                windowHeight = _safeFloat(json.deviceWindow.height, 320);

                if (json.deviceWindow.devices != null) {
                    for (d in cast(json.deviceWindow.devices, Array<Dynamic>)) {
                        var path:Array<String> = [];
                        if (d.path != null) {
                            for (s in cast(d.path, Array<Dynamic>)) {
                                path.push(Std.string(s));
                            }
                        }
                        devices.push({
                            path: path,
                            x: _safeFloat(d.x, 0),
                            y: _safeFloat(d.y, 0),
                            width: _safeFloat(d.width, 100),
                            height: _safeFloat(d.height, 80)
                        });
                    }
                }
            }

            return {
                blueprint: bp,
                view: viewState,
                devices: devices,
                isOpen: isOpen,
                windowX: windowX,
                windowY: windowY,
                windowWidth: windowWidth,
                windowHeight: windowHeight
            };
        } catch(err:Dynamic) {
            trace('Error parsing Selfrun: $err');
            return null;
        }
        #else
        return null;
        #end
    }

    /**
     * Сохранить сборку в библиотеку.
     */
    public function saveAssemblyToLibrary(asm:Assembly):Void {
        #if sys
        var bp = asm.blueprint;
        if (bp.id == "selfrun" || bp.id == "loaded_asm") return;

        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in bp.internalAtoms) {
            var runtimeId = asm.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;
            var atomInstance:Atom = cast asm.internalAtoms.get(runtimeId);
            var values:Dynamic = null;
            if (atomInstance != null) values = atomInstance.getPersistentState();
            atomsToSave.push({ instanceId: atomDef.instanceId, typeId: atomDef.typeId, x: atomDef.x, y: atomDef.y, values: values });
        }

        var connsToSave:Array<Dynamic> = [];
        for (conn in bp.internalConnections) {
            var fromId = conn.from.atomId; var toId = conn.to.atomId;
            if (fromId != "SELF") fromId = asm.getTemplateId(fromId);
            if (toId != "SELF") toId = asm.getTemplateId(toId);
            connsToSave.push({ from: { atomId: fromId, contactName: conn.from.contactName }, to: { atomId: toId, contactName: conn.to.contactName } });
        }

        var pinsData:Array<Dynamic> = [];
        for (pin in bp.pins) pinsData.push({ name: pin.name, type: Std.string(pin.type), defaultValue: pin.defaultValue, dataType: pin.dataType });

        var data:Dynamic = { version: "1.1", blueprint: { id: bp.id, name: bp.name, category: bp.category, pins: pinsData, internalAtoms: atomsToSave, internalConnections: connsToSave } };
        var path = libraryPath + "/" + bp.id + ".atom";
        try {
            File.saveContent(path, haxe.Json.stringify(data, null, "  "));
            trace("ProjectManager: Saved: " + bp.id);
            AtomRegistry.registerBlueprint(bp.id, bp);
        } catch(e:Dynamic) { trace("Error saving assembly: " + e); }
        #end
    }

    /**
     * Удалить файл сборки.
     */
    public function deleteAssemblyFile(typeId:String):Void {
        #if sys
        var path = libraryPath + "/" + typeId + ".atom";
        if (FileSystem.exists(path)) {
            try { FileSystem.deleteFile(path); } catch(e:Dynamic) { trace('Error deleting $path'); }
        }
        #end
    }

    // =============================================================================================
    // PRIVATE HELPERS
    // =============================================================================================

    private function saveInternalAssemblies(asm:Assembly) {
        #if sys
        if (asm.internalAtoms == null) return;
        for (key in asm.internalAtoms.keys()) {
            var sub = asm.internalAtoms.get(key);
            if (Std.isOfType(sub, Assembly)) {
                var subAsm = cast(sub, Assembly);
                if (subAsm.blueprint.internalAtoms != null && subAsm.blueprint.internalAtoms.length > 0) {
                    saveAssemblyToLibrary(subAsm);
                    saveInternalAssemblies(subAsm);
                }
            }
        }
        #end
    }

    private function parseBlueprintFromJson(rawBp:Dynamic):Blueprint {
        var pins:Array<core.data.Blueprint.PinDef> = [];
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
                    y: a.y,
                    values: a.values
                });
            }
        }

        return new Blueprint(
            Std.string(rawBp.id),
            Std.string(rawBp.name),
            pins,
            null,
            atoms,
            conns,
            Std.string(rawBp.category)
        );
    }

    private function _parseContactType(val:Dynamic):ContactType {
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
            switch(Std.int(val)) {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        return UNDEFINED;
    }

    private function _safeFloat(v:Dynamic, def:Float=0.0):Float {
        if (v == null) return def;
        var f = Std.parseFloat(Std.string(v));
        return Math.isNaN(f) ? def : f;
    }
}