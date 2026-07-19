package core.logic;

import library.AtomRegistry;
import core.data.Blueprint;

/**
* ═══════════════════════════════════════════════════════════════════════════╗
* ║                     NAMING SERVICE v1.0                                  ║
* ║          Global Unique Name Resolution for Atoms & Assemblies            ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                                                                          ║
* ║  Central service for ensuring global name uniqueness across the entire   ║
* ║  application — every Atom instance and every Blueprint has a name that   ║
* ║  is unique across all open editor contexts, all loaded assemblies, and   ║
* ║  all blueprints registered in AtomRegistry.                              ║
* ║                                                                          ║
* ║  Two independent namespaces:                                             ║
* ║  ─────────────────────────────                                           ║
* ║   1. INSTANCE NAMES (Atom.displayName)                                   ║
* ║      ─ One global registry, NOT scoped to parent Assembly                ║
* ║      ─ Two atoms in different Assemblies CANNOT share displayName        ║
* ║      ─ Auto-suffix "_N" appended on conflict                             ║
* ║                                                                          ║
* ║   2. BLUEPRINT NAMES (Blueprint.name)                                    ║
* ║      ─ Backed by AtomRegistry directly                                   ║
* ║      ─ Used to prevent two custom assemblies being saved with same name  ║
* ║                                                                          ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                     ARCHITECTURE                                         ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                                                                          ║
* ║   ┌─────────────────────────────────────────────────────────────────┐    ║
* ║   │   NamingService (Static)                                        │    ║
* ║   │                                                                 │    ║
* ║   │   ┌──────────────────────────────────────────────────────────┐  │    ║
* ║   │   │  _instanceNames : Map<String, String>                    │  │    ║
* ║   │   │    key   = Atom.displayName                              │  │    ║
* ║   │   │    value = Atom.id (runtime instance ID)                 │  │    ║
* ║   │   │                                                          │  │    ║
* ║   │   │  Methods:                                                │  │    ║
* ║   │   │   - isInstanceNameTaken(name, ?excludeInstanceId)        │  │    ║
* ║   │   │   - registerInstanceName(name, instanceId)               │  │    ║
* ║   │   │   - unregisterInstanceName(name)                         │  │    ║
* ║   │   │   - resolveUniqueInstanceName(candidate, ?exclude)       │  │    ║
* ║   │   │   - renameInstance(oldName, newName, instanceId)         │  │    ║
* ║   │   │   - clearInstanceNames()                                 │  │    ║
* ║   │   └──────────────────────────────────────────────────────────┘  │    ║
* ║   │                                                                 │    ║
* ║   │   ┌──────────────────────────────────────────────────────────┐  │    ║
* ║   │   │  Blueprint Names (delegated to AtomRegistry):            │  │    ║
* ║   │   │   - isBlueprintNameTaken(name, ?excludeBpId)             │  │    ║
* ║   │   │   - resolveUniqueBlueprintName(candidate, ?exclude)      │  │    ║
* ║   │   └──────────────────────────────────────────────────────────┘  │    ║
* ║   └─────────────────────────────────────────────────────────────────┘    ║
* ║                                                                          ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                     USAGE FLOW                                           ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                                                                          ║
* ║   ┌──────────────────────────────────────────────────────────────────┐   ║
* ║   │  CREATE ATOM                                                     │   ║
* ║   │   ──────────                                                     │   ║
* ║   │   candidate = "Button"                                           │   ║
* ║   │   unique   = NamingService.resolveUniqueInstanceName(candidate)  │   ║
* ║   │   atom.displayName = unique                                      │   ║
* ║   │   NamingService.registerInstanceName(unique, atom.id)            │   ║
* ║   └──────────────────────────────────────────────────────────────────┘   ║
* ║                                                                          ║
* ║   ┌──────────────────────────────────────────────────────────────────┐   ║
* ║   │  RENAME ATOM                                                     │   ║
* ║   │   ───────────                                                    │   ║
* ║   │   oldName = atom.displayName                                     │   ║
* ║   │   newName = NamingService.resolveUniqueInstanceName(typed,       │   ║
* ║   │                                        atom.id)                  │   ║
* ║   │   NamingService.unregisterInstanceName(oldName)                  │   ║
* ║   │   atom.displayName = newName                                     │   ║
* ║   │   NamingService.registerInstanceName(newName, atom.id)           │   ║
* ║   └──────────────────────────────────────────────────────────────────┘   ║
* ║                                                                          ║
* ║   ┌──────────────────────────────────────────────────────────────────┐   ║
* ║   │  DELETE ATOM                                                     │   ║
* ║   │   ───────────                                                    │   ║
* ║   │   NamingService.unregisterInstanceName(atom.displayName)         │   ║
* ║   │   atom.dispose()    (also unregisters defensively)               │   ║
* ║   └──────────────────────────────────────────────────────────────────┘   ║
* ║                                                                          ║
* ║   ┌──────────────────────────────────────────────────────────────────┐   ║
* ║   │  SAVE NEW ASSEMBLY TO LIBRARY                                    │   ║
* ║   │   ──────────────────────────────                                 │   ║
* ║   │   unique = NamingService.resolveUniqueBlueprintName(typedName)   │   ║
* ║   │   blueprint.name = unique                                        │   ║
* ║   │   AtomRegistry.registerBlueprint(blueprint.id, blueprint)        │   ║
* ║   └──────────────────────────────────────────────────────────────────┘   ║
* ║                                                                          ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                     SUFFIX ALGORITHM                                     ║
* ╠══════════════════════════════════════════════════════════════════════════╣
* ║                                                                          ║
* ║   Input: "Button" (taken)                                                ║
* ║   Try:  "Button_1"  → taken? try next                                    ║
* ║   Try:  "Button_2"  → free → return                                      ║
* ║                                                                          ║
* ║   Input: "My Button" (taken)                                             ║
* ║   Try:  "My Button_1" → free → return                                    ║
* ║                                                                          ║
* ║   Note: If candidate already ends with "_N" and that slot is free,       ║
* ║   the candidate is used as-is. The suffix is only appended on conflict.  ║
* ║                                                                          ║
* ╚══════════════════════════════════════════════════════════════════════════╝
*/
class NamingService
{
// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE STATE
// ═══════════════════════════════════════════════════════════════════════════
        /**
        * Global registry of instance displayNames.
        *
        * Key:   atom.displayName (String)
        * Value: atom.id          (String, runtime instance ID)
        *
        * Invariant: at any moment, the set of keys == the set of displayNames
        * of all live Atom instances across all open editor contexts and all
        * loaded Assemblies in the application.
        */
        private static var _instanceNames:Map<String, String> = new Map();

// ═══════════════════════════════════════════════════════════════════════════
// INSTANCE NAME API
// ═══════════════════════════════════════════════════════════════════════════
        /**
        * Check if an instance name is already taken by some live Atom.
        *
        * @param name              The displayName to check
        * @param excludeInstanceId Optional atom ID to exclude (used when
        *                          renaming — atom shouldn't conflict with itself)
        * @return true if the name is taken by another atom, false if available
        */
        public static function isInstanceNameTaken(name:String, ?excludeInstanceId:String):Bool
        {
                if (name == null || name.length == 0) return true;
                var existingId = _instanceNames.get(name);
                if (existingId == null) return false;
                if (excludeInstanceId != null && existingId == excludeInstanceId) return false;
                return true;
        }

        /**
        * Register an instance name in the global registry.
        *
        * Should be called immediately after setting atom.displayName.
        * If the name is already taken (and not by the same instance), registration
        * fails and the caller MUST call resolveUniqueInstanceName() first.
        *
        * @param name       displayName to register
        * @param instanceId atom.id of the owning atom
        * @return true if registered, false if name was already taken by another atom
        */
        public static function registerInstanceName(name:String, instanceId:String):Bool
        {
                if (name == null || name.length == 0) return false;
                if (instanceId == null || instanceId.length == 0) return false;
                if (isInstanceNameTaken(name, instanceId)) return false;
                _instanceNames.set(name, instanceId);
                return true;
        }

        /**
        * Unregister an instance name (e.g. when atom is disposed).
        *
        * Safe to call multiple times — silently no-ops if name wasn't registered.
        *
        * @param name displayName to remove from registry
        */
        public static function unregisterInstanceName(name:String):Void
        {
                if (name == null) return;
                _instanceNames.remove(name);
        }

        /**
        * Atomically rename: unregister old, register new.
        *
        * Use this for rename operations to avoid transient conflicts when
        * the new name happens to be the old name of another atom mid-rename.
        *
        * @param oldName       Current displayName
        * @param newName       Desired displayName (must already be resolved unique!)
        * @param instanceId    atom.id of the renaming atom
        * @return true if rename succeeded, false otherwise
        */
        public static function renameInstance(oldName:String, newName:String, instanceId:String):Bool
        {
                if (newName == null || newName.length == 0) return false;
                if (isInstanceNameTaken(newName, instanceId)) return false;
                if (oldName != null) _instanceNames.remove(oldName);
                _instanceNames.set(newName, instanceId);
                return true;
        }

        /**
        * Resolve a candidate name to a globally unique variant.
        *
        * If candidate is free → returned as-is.
        * If candidate is taken → append "_N" where N is the smallest positive
        * integer making the name free.
        *
        * Examples:
        *   resolveUniqueInstanceName("Button")         → "Button"     (first one)
        *   resolveUniqueInstanceName("Button")         → "Button_1"   (second)
        *   resolveUniqueInstanceName("Button")         → "Button_2"   (third)
        *   resolveUniqueInstanceName("Button_5")       → "Button_5"   (if free)
        *   resolveUniqueInstanceName("MyBtn", "atom_1")→ "MyBtn"      (excludes self)
        *
        * @param candidate         Desired name
        * @param excludeInstanceId Optional atom ID to exclude (for rename)
        * @return Globally unique name (never null, never empty)
        */
        public static function resolveUniqueInstanceName(candidate:String, ?excludeInstanceId:String):String
        {
                if (candidate == null || candidate.length == 0) candidate = "Atom";
                if (!isInstanceNameTaken(candidate, excludeInstanceId))
                {
                        return candidate;
                }
                var counter:Int = 1;
                var c:String = candidate + "_" + counter;
                while (isInstanceNameTaken(c, excludeInstanceId))
                {
                        counter++;
                        c = candidate + "_" + counter;
                }
                return c;
        }

        /**
        * Wipe the entire instance-name registry.
        *
        * Use ONLY at project load / unload boundaries, before atoms are
        * re-instantiated from disk. After clearInstanceNames(), every live
        * Atom must be re-registered via registerInstanceName() or via
        * Assembly._createInternalInstances().
        */
        public static function clearInstanceNames():Void
        {
                _instanceNames = new Map();
        }

        /**
        * Debug helper: dump all registered instance names to trace.
        */
        public static function dumpInstanceNames():Void
        {
                trace('═══ NamingService: ${Lambda.count(_instanceNames)} registered instance names ═══');
                for (name in _instanceNames.keys())
                {
                        trace('  "$name" → ${_instanceNames.get(name)}');
                }
        }

// ═══════════════════════════════════════════════════════════════════════════
// BLUEPRINT NAME API
// ═══════════════════════════════════════════════════════════════════════════
        /**
        * Check if a blueprint name is already registered in AtomRegistry.
        *
        * Blueprint names are checked against AtomRegistry._blueprints directly
        * (no separate map needed — AtomRegistry is the source of truth).
        *
        * @param name        Blueprint.name to check
        * @param excludeBpId Optional blueprint.id to exclude (for rename)
        * @return true if another blueprint has this name
        */
        public static function isBlueprintNameTaken(name:String, ?excludeBpId:String):Bool
        {
                if (name == null || name.length == 0) return true;
                for (id in AtomRegistry.getAllIds())
                {
                        if (excludeBpId != null && id == excludeBpId) continue;
                        var bp:Blueprint = AtomRegistry.get(id);
                        if (bp != null && bp.name == name) return true;
                }
                return false;
        }

        /**
        * Resolve a candidate blueprint name to a unique variant.
        *
        * Same algorithm as resolveUniqueInstanceName but for blueprint.name.
        *
        * @param candidate   Desired blueprint name
        * @param excludeBpId Optional blueprint.id to exclude (for rename)
        * @return Globally unique blueprint name
        */
        public static function resolveUniqueBlueprintName(candidate:String, ?excludeBpId:String):String
        {
                if (candidate == null || candidate.length == 0) candidate = "Assembly";
                if (!isBlueprintNameTaken(candidate, excludeBpId))
                {
                        return candidate;
                }
                var counter:Int = 1;
                var c:String = candidate + "_" + counter;
                while (isBlueprintNameTaken(c, excludeBpId))
                {
                        counter++;
                        c = candidate + "_" + counter;
                }
                return c;
        }
}