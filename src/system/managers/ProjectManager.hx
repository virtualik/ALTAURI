package system.managers;

import haxe.Json;
import core.base.Assembly;
import core.base.Atom;
import core.data.Blueprint;
import core.types.ContactType;
import library.AtomRegistry;
import utils.UID;
using StringTools;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * PROJECT MANAGER v2.2 (Window Position Persistence)
 * Manages file system, paths, and project save/load operations.
 * Extracts all IO logic from Main.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ProjectManager (Singleton)                                            │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  File Paths:                                                    │   │
 * │   │  - documentsPath: String  → User documents folder               │   │
 * │   │  - libraryPath: String    → Custom atoms library                │   │
 * │   │  - selfrunPath: String    → Main project file                   │   │
 * │   │                                                                 │   │
 * │   │  Save Operations:                                               │   │
 * │   │  - saveSelfrun()          → Save root project                   │   │
 * │   │  - saveAssemblyToLibrary()→ Save assembly to library folder     │   │
 * │   │  - deleteAssemblyFile()   → Delete assembly file                │   │
 * │   │                                                                 │   │
 * │   │  Load Operations:                                               │   │
 * │   │  - loadSelfrun()          → Load root project                   │   │
 * │   │  - parseBlueprintFromJson()→ Parse JSON to Blueprint            │   │
 * │   │                                                                 │   │
 * │   │  Initialization:                                                │   │
 * │   │  - init()                 → Create directories, scan library    │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   v2.2 Changes:                                                         │
 * │   - Added windowX/windowY to saved data and return types                │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ProjectManager
{
    private static var _instance:ProjectManager;
    
    /** User documents folder path */
    public var documentsPath:String;
    
    /** Custom atoms library folder path */
    public var libraryPath:String;
    
    /** Main project file path (Selfrun.atom) */
    public var selfrunPath:String;
    
    /**
     * Get singleton instance.
     */
    public static function getInstance():ProjectManager
    {
        if (_instance == null) _instance = new ProjectManager();
        return _instance;
    }
    
    private function new() {}
    
    /**
     * Initialize paths and check folders.
     * Creates ALTAURI directory structure if not exists.
     */
    public function init():Void
    {
        #if sys
        var home = Sys.getEnv("HOME");
        if (home == null) home = Sys.getEnv("USERPROFILE");
        
        if (home != null)
        {
            home = home.replace("\\", "/");
            if (!home.endsWith("/")) home += "/";
            documentsPath = home + "Documents";
        }
        else {
            documentsPath = Sys.getCwd();
        }
        
        var altauriRoot = documentsPath + "/ALTAURI";
        libraryPath = altauriRoot + "/Library";
        selfrunPath = altauriRoot + "/Selfrun.atom";
        
        // Create directory structure
        if (!FileSystem.exists(altauriRoot)) FileSystem.createDirectory(altauriRoot);
        if (!FileSystem.exists(libraryPath)) FileSystem.createDirectory(libraryPath);
        
        // Set custom library path for AtomRegistry
        AtomRegistry.customLibraryPath = libraryPath;
        
        // Scan library for custom atoms
        AtomRegistry.scanFolder(libraryPath);
        #else
        selfrunPath = "Selfrun.atom";
        libraryPath = "library";
        #end
    }
    
    /**
     * Save root project (Selfrun).
     * v2.2: Added windowX, windowY parameters.
     *
     * @param rootAssembly       Root assembly to save
     * @param viewState          Editor viewport state (x, y, zoom)
     * @param deviceWindowData   Array of device window positions
     * @param isDeviceWindowOpen Whether device window is open
     * @param windowWidth        Device window width
     * @param windowHeight       Device window height
     * @param windowX            Device window X position
     * @param windowY            Device window Y position
     */
    public function saveSelfrun(
        rootAssembly:Assembly,
        viewState: {x:Float, y:Float, zoom:Float},
        deviceWindowData:Array< {path:Array<String>, x:Float, y:Float, ?width:Float, ?height:Float}>,
        isDeviceWindowOpen:Bool,
        ?windowWidth:Float = 420,
        ?windowHeight:Float = 320,
        ?windowX:Float = 100,
        ?windowY:Float = 100
    ):Void
    {
        #if sys
        if (rootAssembly == null) return;
        
        // Serialize atoms with runtime states
        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in rootAssembly.blueprint.internalAtoms)
        {
            var runtimeId = rootAssembly.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;
            
            var atomInstance:Atom = cast rootAssembly.internalAtoms.get(runtimeId);
            var values:Dynamic = null;
            
            if (atomInstance != null)
            {
                values = atomInstance.getPersistentState();
            }
            
            atomsToSave.push(
                {
                    instanceId: atomDef.instanceId,
                    typeId: atomDef.typeId,
                    x: atomDef.x,
                    y: atomDef.y,
                    values: values
                });
        }
        
        // Serialize connections with template IDs
        var connsToSave:Array<Dynamic> = [];
        for (conn in rootAssembly.blueprint.internalConnections)
        {
            var fromId = conn.from.atomId;
            var toId = conn.to.atomId;
            
            // Convert runtime IDs to template IDs for persistence
            if (fromId != "SELF") fromId = rootAssembly.getTemplateId(fromId);
            if (toId != "SELF") toId = rootAssembly.getTemplateId(toId);
            
            connsToSave.push(
                {
                    from: { atomId: fromId, contactName: conn.from.contactName },
                    to: { atomId: toId, contactName: conn.to.contactName }
                });
        }
        
        var bp = rootAssembly.blueprint;
        
        // Serialize device window data
        var devicesToSave:Array<Dynamic> = [];
        if (deviceWindowData != null)
        {
            for (d in deviceWindowData)
            {
                var w:Float = (d.width != null) ? d.width : 100.0;
                var h:Float = (d.height != null) ? d.height : 80.0;
                
                devicesToSave.push(
                    {
                        path: d.path,
                        x: d.x,
                        y: d.y,
                        width: w,
                        height: h
                    });
            }
        }
        
        // Build complete save data
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
        }
        catch (e:Dynamic)
        {
            trace("Error saving Selfrun: " + e);
        }
        
        // Save nested assemblies to library
        saveInternalAssemblies(rootAssembly);
        #end
    }
    
    /**
     * Load Selfrun data.
     * v2.2: Returns window X, Y positions.
     *
     * @return Complete project data or null if file not found
     */
    public function loadSelfrun():
        {
            blueprint:Blueprint,
            view: {x:Float, y:Float, zoom:Float},
            devices:Array<
                {
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
        }
    {
        #if sys
        if (!FileSystem.exists(selfrunPath)) return null;
        
        try
        {
            var content = File.getContent(selfrunPath);
            var json = haxe.Json.parse(content);
            var rawBp:Dynamic = json.blueprint;
            
            // Parse blueprint
            var bp = parseBlueprintFromJson(rawBp);
            
            // Parse editor viewport state
            var viewState = {x: 0.0, y: 0.0, zoom: 1.0};
            if (json.editor != null)
            {
                viewState.x = _safeFloat(json.editor.x);
                viewState.y = _safeFloat(json.editor.y);
                viewState.zoom = _safeFloat(json.editor.zoom);
            }
            
            // Parse device window data
            var devices:Array<
                {
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
            
            if (json.deviceWindow != null)
            {
                isOpen = json.deviceWindow.isOpen;
                windowX = _safeFloat(json.deviceWindow.x, 100);
                windowY = _safeFloat(json.deviceWindow.y, 100);
                windowWidth = _safeFloat(json.deviceWindow.width, 420);
                windowHeight = _safeFloat(json.deviceWindow.height, 320);
                
                if (json.deviceWindow.devices != null)
                {
                    for (d in cast(json.deviceWindow.devices, Array<Dynamic>))
                    {
                        var path:Array<String> = [];
                        if (d.path != null)
                        {
                            for (s in cast(d.path, Array<Dynamic>))
                            {
                                path.push(Std.string(s));
                            }
                        }
                        
                        devices.push(
                            {
                                path: path,
                                x: _safeFloat(d.x, 0),
                                y: _safeFloat(d.y, 0),
                                width: _safeFloat(d.width, 100),
                                height: _safeFloat(d.height, 80)
                            });
                    }
                }
            }
            
            return
                {
                    blueprint: bp,
                    view: viewState,
                    devices: devices,
                    isOpen: isOpen,
                    windowX: windowX,
                    windowY: windowY,
                    windowWidth: windowWidth,
                    windowHeight: windowHeight
                };
        }
        catch (err:Dynamic)
        {
            trace('Error parsing Selfrun: $err');
            return null;
        }
        #else
        return null;
        #end
    }
    
    /**
     * Save assembly to library folder.
     * Used for nested assemblies and custom atoms.
     *
     * @param asm Assembly to save
     */
    public function saveAssemblyToLibrary(asm:Assembly):Void
    {
        #if sys
        var bp = asm.blueprint;
        
        // Skip root assembly and loaded assemblies
        if (bp.id == "selfrun" || bp.id == "loaded_asm") return;
        
        // Serialize atoms
        var atomsToSave:Array<Dynamic> = [];
        for (atomDef in bp.internalAtoms)
        {
            var runtimeId = asm.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;
            
            var atomInstance:Atom = cast asm.internalAtoms.get(runtimeId);
            var values:Dynamic = null;
            
            if (atomInstance != null) values = atomInstance.getPersistentState();
            
            atomsToSave.push({ 
                instanceId: atomDef.instanceId, 
                typeId: atomDef.typeId, 
                x: atomDef.x, 
                y: atomDef.y, 
                values: values 
            });
        }
        
        // Serialize connections
        var connsToSave:Array<Dynamic> = [];
        for (conn in bp.internalConnections)
        {
            var fromId = conn.from.atomId; 
            var toId = conn.to.atomId;
            
            if (fromId != "SELF") fromId = asm.getTemplateId(fromId);
            if (toId != "SELF") toId = asm.getTemplateId(toId);
            
            connsToSave.push({ 
                from: { atomId: fromId, contactName: conn.from.contactName }, 
                to: { atomId: toId, contactName: conn.to.contactName } 
            });
        }
        
        // Serialize pins
        var pinsData:Array<Dynamic> = [];
        for (pin in bp.pins) 
            pinsData.push({ 
                name: pin.name, 
                type: Std.string(pin.type), 
                defaultValue: pin.defaultValue, 
                dataType: pin.dataType 
            });
        
        // Build save data
        var data:Dynamic = { 
            version: "1.1", 
            blueprint: { 
                id: bp.id, 
                name: bp.name, 
                category: bp.category, 
                pins: pinsData, 
                internalAtoms: atomsToSave, 
                internalConnections: connsToSave 
            } 
        };
        
        var path = libraryPath + "/" + bp.id + ".atom";
        
        try {
            File.saveContent(path, haxe.Json.stringify(data, null, "  "));
            trace("ProjectManager: Saved: " + bp.id);
            AtomRegistry.registerBlueprint(bp.id, bp);
        }
        catch (e:Dynamic) { 
            trace("Error saving assembly: " + e); 
        }
        #end
    }
    
    /**
     * Delete assembly file from library.
     *
     * @param typeId Assembly type ID (filename without extension)
     */
    public function deleteAssemblyFile(typeId:String):Void
    {
        #if sys
        var path = libraryPath + "/" + typeId + ".atom";
        
        if (FileSystem.exists(path))
        {
            try { 
                FileSystem.deleteFile(path); 
            }
            catch (e:Dynamic) { 
                trace('Error deleting $path'); 
            }
        }
        #end
    }
    
    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================
    
    /**
     * Recursively save nested assemblies to library.
     * Called automatically when saving root project.
     */
    private function saveInternalAssemblies(asm:Assembly)
    {
        #if sys
        if (asm.internalAtoms == null) return;
        
        for (key in asm.internalAtoms.keys())
        {
            var sub = asm.internalAtoms.get(key);
            
            if (Std.isOfType(sub, Assembly))
            {
                var subAsm = cast(sub, Assembly);
                
                // Save only assemblies with internal atoms
                if (subAsm.blueprint.internalAtoms != null && subAsm.blueprint.internalAtoms.length > 0)
                {
                    saveAssemblyToLibrary(subAsm);
                    saveInternalAssemblies(subAsm);
                }
            }
        }
        #end
    }
    
    /**
     * Parse blueprint from JSON data.
     * Handles String → ContactType conversion for pins.
     *
     * @param rawBp Raw blueprint data from JSON
     * @return Parsed Blueprint instance
     */
    private function parseBlueprintFromJson(rawBp:Dynamic):Blueprint
    {
        // Parse pins with type conversion
        var pins:Array<core.data.Blueprint.PinDef> = [];
        
        if (rawBp.pins != null)
        {
            for (p in (cast(rawBp.pins, Array<Dynamic>)))
            {
                pins.push(
                    {
                        name: Std.string(p.name),
                        // FIX: Use _parseContactType for String → ContactType conversion
                        type: _parseContactType(p.type),
                        defaultValue: p.defaultValue,
                        dataType: Std.string(p.dataType)
                    });
            }
        }
        
        // Parse connections
        var conns = [];
        if (rawBp.internalConnections != null)
        {
            for (c in (cast(rawBp.internalConnections, Array<Dynamic>)))
            {
                conns.push(
                    {
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
        
        // Parse atom definitions
        var atoms = [];
        if (rawBp.internalAtoms != null)
        {
            for (a in (cast(rawBp.internalAtoms, Array<Dynamic>)))
            {
                atoms.push(
                    {
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
    
    /**
     * Parse ContactType from dynamic value (String or Int).
     * Handles both JSON string format ("INPUT") and numeric format (0).
     *
     * @param val Dynamic value from JSON
     * @return Parsed ContactType
     */
    private function _parseContactType(val:Dynamic):ContactType
    {
        if (Std.isOfType(val, ContactType)) return val;
        
        if (Std.isOfType(val, String))
        {
            switch (Std.string(val))
            {
                case "INPUT": return INPUT;
                case "OUTPUT": return OUTPUT;
                case "BIDIRECTIONAL": return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        // Handle numeric indices
        if (Std.isOfType(val, Int) || Std.isOfType(val, Float))
        {
            switch (Std.int(val))
            {
                case 0: return INPUT;
                case 1: return OUTPUT;
                case 2: return BIDIRECTIONAL;
                default: return UNDEFINED;
            }
        }
        
        return UNDEFINED;
    }
    
    /**
     * Safe float parsing with default value.
     *
     * @param v Dynamic value to parse
     * @param def Default value if parsing fails
     * @return Parsed float or default
     */
    private function _safeFloat(v:Dynamic, def:Float=0.0):Float
    {
        if (v == null) return def;
        var f = Std.parseFloat(Std.string(v));
        return Math.isNaN(f) ? def : f;
    }
}