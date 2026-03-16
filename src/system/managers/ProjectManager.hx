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
 * PROJECT MANAGER v1.0
 * Отвечает за файловую систему, пути и сохранение/загрузку проектов.
 * Выносит всю IO логику из Main.
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
            home = home.replace("\\", "/"); // Теперь это сработает
            if (!home.endsWith("/")) home += "/"; // И это тоже
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
     */
    public function saveSelfrun(
        rootAssembly:Assembly, 
        viewState:{x:Float, y:Float, zoom:Float}, 
        deviceWindowData:Array<{path:Array<String>, x:Float, y:Float}>,
        isDeviceWindowOpen:Bool
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
        
        var data:Dynamic = {
            version: "1.3",
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
                devices: deviceWindowData
            }
        };

        try {
            File.saveContent(selfrunPath, haxe.Json.stringify(data, null, "  "));
            trace("ProjectManager: Selfrun saved.");
        } catch(e:Dynamic) {
            trace("Error saving Selfrun: " + e);
        }

        saveInternalAssemblies(rootAssembly);
        #end
    }

    /**
     * Загрузить данные Selfrun.
     */
    public function loadSelfrun():{blueprint:Blueprint, view:{x:Float, y:Float, zoom:Float}, devices:Array<Dynamic>, isOpen:Bool} {
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
            
            var devices:Array<Dynamic> = [];
            var isOpen = false;
            if (json.deviceWindow != null) {
                isOpen = json.deviceWindow.isOpen;
                if (json.deviceWindow.devices != null) {
                    devices = json.deviceWindow.devices;
                }
            }

            return {blueprint: bp, view: viewState, devices: devices, isOpen: isOpen};
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