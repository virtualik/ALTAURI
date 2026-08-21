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
	import lime.system.System;
	import sys.FileSystem;
	import sys.io.File;
#end
/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     PROJECT MANAGER v2.5                                  ║
* ║       (Blueprint Sanitization + Dual Naming + Platform Filtering)         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Manages file system, paths, and project save/load operations.            ║
* ║  Extracts all IO logic from Main.                                         ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │   ProjectManager (Singleton)                                        │  ║
* ║  │                                                                     │  ║
* ║  │   ┌─────────────────────────────────────────────────────────────┐   │  ║
* ║  │   │  File Paths:                                                │   │  ║
* ║  │   │  - documentsPath: String  → User documents folder           │   │  ║
* ║  │   │  - libraryPath: String    → Custom atoms library            │   │  ║
* ║  │   │  - selfrunPath: String    → Main project file               │   │  ║
* ║  │   │                                                             │   │  ║
* ║  │   │  Save Operations:                                           │   │  ║
* ║  │   │  - saveSelfrun()          → Save root project               │   │  ║
* ║  │   │  - saveAssemblyToLibrary()→ Save assembly to library folder │   │  ║
* ║  │   │  - deleteAssemblyFile()   → Delete assembly file            │   │  ║
* ║  │   │                                                             │   │  ║
* ║  │   │  Load Operations:                                           │   │  ║
* ║  │   │  - loadSelfrun()          → Load root project               │   │  ║
* ║  │   │  - parseBlueprintFromJson()→ Parse JSON to Blueprint        │   │  ║
* ║  │   │  - _sanitizeBlueprint()  → Remove ghost connections (v2.4)  │   │  ║
* ║  │   │                                                             │   │  ║
* ║  │   │  Initialization:                                            │   │  ║
* ║  │   │  - init()                 → Create directories, scan library│   │  ║
* ║  │   └─────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │   v2.5 Changes:                                                     │  ║
* ║  │   - ADDED: Platform filtering support (platforms field)             │  ║
* ║  │   - Platforms serialized in .atom files for target-aware loading    │  ║
* ║  │   - ADDED _sanitizeBlueprint(): removes ghost connections at load   │  ║
* ║  │   - Ghost = connection referencing non-existent atom or SELF port   │  ║
* ║  │   - Prevents WireRenderer from drawing wires to null endpoints      │  ║
* ║  │   - Prevents Assembly._createInternalConnections() from crashing    │  ║
* ║  │   - FIXED: Replaced Reflect.field with direct property access for   │  ║
* ║  │     externalName to guarantee reliable serialization in Haxe.       │  ║
* ║  │                                                                     │  ║
* ║  │   v2.3 Changes:                                                     │  ║
* ║  │   - FIXED: saveSelfrun() now serializes pins with externalName      │  ║
* ║  │   - FIXED: dataType null handling (no more "null" string)           │  ║
* ║  │   - Preserves ConductorPort dual naming (externalName+internalName) │  ║
* ║  │                                                                     │  ║
* ║  │   v2.2 Changes:                                                     │  ║
* ║  │   - Added windowX/windowY to saved data and return types            │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
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
			#if android
			// On Android, use secure, isolated app storage.
			var altauriRoot = lime.system.System.applicationStorageDirectory;
			// Make sure the path ends with a slash so the names don't stick together.
			if (!altauriRoot.endsWith("/")) altauriRoot += "/";
			
			documentsPath = altauriRoot; 
			libraryPath = altauriRoot + "Library";
			selfrunPath = altauriRoot + "Selfrun.atom";
			#else
			// Old, proven code for Windows, Mac, and Linux
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
			#end

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
	* v2.3: Pins serialized with externalName support.
	* v2.2: Added windowX, windowY parameters.
	* v2.5: Added platforms field for platform filtering.
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
			var atomData:Dynamic =
			{
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y,
				values: values
			};
			// v3.9 FIX: Always write visualMode (default to "LIGHT" if not set)
			atomData.visualMode = atomDef.visualMode != null ? atomDef.visualMode : "LIGHT";
			atomsToSave.push(atomData);
		}
// Serialize connections with template IDs
		var connsToSave:Array<Dynamic> = [];
		for (conn in rootAssembly.blueprint.internalConnections)
		{
			var fromId = conn.from.atomId;
			var toId = conn.to.atomId;
			if (fromId != "SELF") fromId = rootAssembly.getTemplateId(fromId);
			if (toId != "SELF") toId = rootAssembly.getTemplateId(toId);
			connsToSave.push(
			{
				from: { atomId: fromId, contactName: conn.from.contactName },
				to: { atomId: toId, contactName: conn.to.contactName }
			});
		}
		var bp = rootAssembly.blueprint;
// v2.4 FIX: Serialize pins with direct externalName access
		var pinsToSave:Array<Dynamic> = [];
		for (pin in bp.pins)
		{
			var pinData:Dynamic =
			{
				name: pin.name,
				type: Std.string(pin.type),
				defaultValue: pin.defaultValue
			};
			if (pin.dataType != null) pinData.dataType = pin.dataType;
// Direct property access is 100% reliable for @:optional typedef fields in Haxe
			if (pin.externalName != null && pin.externalName != "")
			{
				pinData.externalName = pin.externalName;
			}
			pinsToSave.push(pinData);
		}
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
			version: "2.5",
			blueprint: {
				id: bp.id,
				name: bp.name,
				category: bp.category,
				pins: pinsToSave,
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
// v2.5: Serialize platforms field if present
		if (bp.platforms != null && bp.platforms.length > 0)
		{
			data.blueprint.platforms = bp.platforms;
		}
		try {
			File.saveContent(selfrunPath, haxe.Json.stringify(data, null, "  "));
			trace("ProjectManager: Selfrun saved (v2.5 with platform filtering).");
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
// Parse blueprint (includes v2.4 sanitization + v2.5 platforms)
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
			var atomData:Dynamic =
			{
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y,
				values: values
			};
			// v3.9 FIX: Always write visualMode (default to "LIGHT" if not set)
			atomData.visualMode = atomDef.visualMode != null ? atomDef.visualMode : "LIGHT";
			atomsToSave.push(atomData);
		}
// Serialize connections
		var connsToSave:Array<Dynamic> = [];
		for (conn in bp.internalConnections)
		{
			var fromId = conn.from.atomId;
			var toId = conn.to.atomId;
			if (fromId != "SELF") fromId = asm.getTemplateId(fromId);
			if (toId != "SELF") toId = asm.getTemplateId(toId);
			connsToSave.push(
			{
				from: { atomId: fromId, contactName: conn.from.contactName },
				to: { atomId: toId, contactName: conn.to.contactName }
			});
		}
// v2.4 FIX: Serialize pins with direct externalName access
		var pinsData:Array<Dynamic> = [];
		for (pin in bp.pins)
		{
			var pinData:Dynamic =
			{
				name: pin.name,
				type: Std.string(pin.type),
				defaultValue: pin.defaultValue
			};
			if (pin.dataType != null) pinData.dataType = pin.dataType;
// Direct property access is 100% reliable for @:optional typedef fields in Haxe
			if (pin.externalName != null && pin.externalName != "")
			{
				pinData.externalName = pin.externalName;
			}
			pinsData.push(pinData);
		}
// Build save data
		var data:Dynamic = {
			version: "1.3",
			blueprint: {
				id: bp.id,
				name: bp.name,
				category: bp.category,
				pins: pinsData,
				internalAtoms: atomsToSave,
				internalConnections: connsToSave
			}
		};
// v2.5: Serialize platforms field if present
		if (bp.platforms != null && bp.platforms.length > 0)
		{
			data.blueprint.platforms = bp.platforms;
		}
		var path = libraryPath + "/" + bp.id + ".atom";
		try {
			File.saveContent(path, haxe.Json.stringify(data, null, "  "));
			trace("ProjectManager: Saved: " + bp.id);
			AtomRegistry.registerBlueprint(bp.id, bp);
		}
		catch (e:Dynamic)
		{
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
			try
			{
				FileSystem.deleteFile(path);
			}
			catch (e:Dynamic)
			{
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
	* v2.4: Calls _sanitizeBlueprint() after parsing to remove ghost connections.
	* v2.5: Parses platforms field for platform filtering.
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
// v2.3 FIX: Handle dataType null correctly
				var dt:String = null;
				if (p.dataType != null)
				{
					dt = Std.string(p.dataType);
					if (dt == "null") dt = null;
				}
// v2.4 FIX: Handle externalName null correctly with direct access
				var extName:String = null;
				if (p.externalName != null)
				{
					extName = Std.string(p.externalName);
					if (extName == "null") extName = null;
				}
				pins.push(
				{
					name: Std.string(p.name),
					type: _parseContactType(p.type),
					defaultValue: p.defaultValue,
					dataType: dt,
					externalName: extName
				});
			}
		}
// Parse connections
		var conns:Array<core.data.Blueprint.ConnectionDef> = [];
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
		var atoms:Array<core.data.Blueprint.AtomDef> = [];
		if (rawBp.internalAtoms != null)
		{
			for (a in (cast(rawBp.internalAtoms, Array<Dynamic>)))
			{
				// v3.9: Parse visual mode
				var vm:String = null;
				if (a.visualMode != null) vm = Std.string(a.visualMode);
				
				atoms.push(
				{
					instanceId: Std.string(a.instanceId),
					typeId: Std.string(a.typeId),
					x: a.x,
					y: a.y,
					values: a.values,
					visualMode: vm
				});
			}
		}
// ══════════════════════════════════════════════════════════════════
// v2.5: Parse platforms array for platform filtering
// ═══════════════════════════════════════════════════════════════════
// platforms: ["cpp"] → only for C++ target
// platforms: ["html5"] → only for HTML5 target
// platforms: null or [] → available on all platforms
		var platforms:Array<String> = null;
		if (rawBp.platforms != null)
		{
			platforms = [];
			for (p in cast(rawBp.platforms, Array<Dynamic>))
			{
				platforms.push(Std.string(p));
			}
		}
// ═══════════════════════════════════════════════════════════════════
// v2.4: Sanitize blueprint BEFORE creating Blueprint object
// ═══════════════════════════════════════════════════════════════════
// Remove connections referencing non-existent atoms or SELF ports.
// This prevents ghost wires and null reference crashes at runtime.
		_sanitizeConnections(conns, atoms, pins, Std.string(rawBp.id));
		return new Blueprint(
				   Std.string(rawBp.id),
				   Std.string(rawBp.name),
				   pins,
				   null,
				   atoms,
				   conns,
				   Std.string(rawBp.category),
				   platforms
			   );
	}
	/**
	* v2.4: Remove ghost connections from parsed blueprint data.
	*
	* A connection is "ghost" if:
	*   - It references an atomId that doesn't exist in internalAtoms (and != "SELF")
	*   - It references a SELF port that doesn't exist in pins
	*
	* This is the FIRST LINE OF DEFENSE against corrupted save files.
	* Assembly._createInternalConnections() is the SECOND line (runtime).
	*
	* ┌─────────────────────────────────────────────────────────────────────┐
	* │  SANITIZATION FLOW:                                                 │
	* │                                                                     │
	* │  For each connection:                                               │
	* │    1. Check from.atomId:                                            │
	* │       - If "SELF": verify from.contactName exists in pins           │
	* │       - Else: verify from.atomId exists in internalAtoms            │
	* │    2. Check to.atomId:                                              │
	* │       - If "SELF": verify to.contactName exists in pins             │
	* │       - Else: verify to.atomId exists in internalAtoms              │
	* │    3. If either check fails: REMOVE connection                      │
	* │                                                                     │
	* │  Result: Only valid connections survive into Blueprint              │
	* └─────────────────────────────────────────────────────────────────────┘
	*
	* @param conns  Parsed connections array (modified in-place)
	* @param atoms  Parsed atom definitions
	* @param pins   Parsed pin definitions
	* @param bpId   Blueprint ID (for logging)
	*/
	private function _sanitizeConnections(
		conns:Array<core.data.Blueprint.ConnectionDef>,
		atoms:Array<core.data.Blueprint.AtomDef>,
		pins:Array<core.data.Blueprint.PinDef>,
		bpId:String
	):Void
	{
		if (conns == null || conns.length == 0) return;
// Build lookup sets
		var atomIds = new Map<String, Bool>();
		for (a in atoms) atomIds.set(a.instanceId, true);
		var pinNames = new Map<String, Bool>();
		for (p in pins) pinNames.set(p.name, true);
// Find ghost connections
		var toRemove:Array<core.data.Blueprint.ConnectionDef> = [];
		for (conn in conns)
		{
			var fromValid = _isEndpointValid(conn.from.atomId, conn.from.contactName, atomIds, pinNames);
			var toValid = _isEndpointValid(conn.to.atomId, conn.to.contactName, atomIds, pinNames);
			if (!fromValid || !toValid)
			{
				toRemove.push(conn);
			}
		}
// Remove ghost connections
		for (conn in toRemove)
		{
			conns.remove(conn);
			trace('  🔧 SANITIZE [${bpId}]: Removed ghost connection: ' +
				  '${conn.from.atomId}.${conn.from.contactName} → ' +
				  '${conn.to.atomId}.${conn.to.contactName}');
		}
		#if DEBUG
		if (toRemove.length > 0)
		{
			trace('  📋 SANITIZE [${bpId}]: Removed ${toRemove.length} ghost connections ' +
				  '(${conns.length} valid remaining)');
		}
		#end
	}
	/**
	* v2.4: Check if a connection endpoint is valid.
	*
	* @param atomId      "SELF" or atom instance ID
	* @param contactName Port name (for SELF) or contact name (for atom)
	* @param atomIds     Set of valid atom instance IDs
	* @param pinNames    Set of valid pin names (for SELF ports)
	* @return true if endpoint is valid, false if ghost
	*/
	private function _isEndpointValid(
		atomId:String,
		contactName:String,
		atomIds:Map<String, Bool>,
		pinNames:Map<String, Bool>
	):Bool
	{
		if (atomId == "SELF")
		{
// SELF endpoint: contactName must be a valid pin name
			return pinNames.exists(contactName);
		}
		else
		{
// Atom endpoint: atomId must exist in internalAtoms
			return atomIds.exists(atomId);
		}
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