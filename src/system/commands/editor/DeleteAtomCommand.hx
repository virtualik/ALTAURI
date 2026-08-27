package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.base.IDisposable;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;
import core.base.AssemblyFactory;
import library.AtomRegistry;

/**
 * DELETE ATOM COMMAND v1.1
 * Deletes an atom and its connections from the assembly.
 * Supports Undo/Redo with full snapshot restoration.
 *
 * v1.1 CHANGES (NamingService integration):
 *  - Saves displayName in snapshot before dispose
 *  - On undo(): restores the saved displayName (or resolves a unique
 *    variant if the original slot has since been taken)
 *  - Registers the restored name in NamingService
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeleteAtomCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  1. saveSnapshot() — capture atom definition and connections    │   │
 * │   │  2. Capture displayName BEFORE dispose (v1.1)                   │   │
 * │   │  3. Remove connections from blueprint                           │   │
 * │   │  4. Unlink physical connections between contacts                │   │
 * │   │  5. Remove atom definition from blueprint                       │   │
 * │   │  6. Dispose atom instance (also releases name slot)             │   │
 * │   │  7. Remove instance from assembly                               │   │
 * │   │  8. Emit ATOM_DELETED event                                     │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  1. Restore atom definition to blueprint                        │   │
 * │   │  2. Recreate atom instance via AssemblyFactory                  │   │
 * │   │  3. Restore saved displayName (or unique variant) (v1.1)        │   │
 * │   │  4. Register name in NamingService (v1.1)                       │   │
 * │   │  5. Add instance to assembly                                    │   │
 * │   │  6. Restore connections to blueprint                            │   │
 * │   │  7. Emit ATOM_RESTORED event                                    │   │
 * │   │  8. Delayed: restorePhysicalConnections()                       │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DeleteAtomCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String; // Runtime ID
    private var _atomDef:AtomDef;
    private var _atomType:String;
    private var _connections:Array<ConnectionDef>;
    private var _posX:Float;
    private var _posY:Float;
    // v1.1: Saved displayName so undo() can restore it EXACTLY (including
    // any custom name the user chose). Without this, undo() would create
    // a fresh atom with displayName = type, breaking global uniqueness
    // and losing user intent.
    private var _savedDisplayName:String = null;

    public function new(blueprint:Blueprint, assembly:Assembly, atomId:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _atomId = atomId;
    }

        override private function executeInternal():Void {
                saveSnapshot();
                
                var involvesSelf = false;
                
                // Remove connections
                if (_connections != null) {
                        for (conn in _connections) {
                                if (conn.from.atomId == "SELF" || conn.to.atomId == "SELF") {
                                        involvesSelf = true;
                                }
                                _blueprint.internalConnections.remove(conn);
                                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                                if (cOut != null && cIn != null) cOut.unlink(cIn);
                        }
                }
                
                // Remove atom definition
                if (_atomDef != null) {
                        _blueprint.internalAtoms.remove(_atomDef);
                }
                
                // Remove atom instance
                // v1.1: Capture displayName BEFORE dispose — dispose() releases the
                // name slot in NamingService, but we need it for undo().
                var atomInstance = _assembly.internalAtoms.get(_atomId);
                if (atomInstance != null) {
                        var atom:Atom = cast atomInstance;
                        if (atom != null && atom.displayName != null) {
                                _savedDisplayName = atom.displayName;
                        }
                        // dispose() will also call NamingService.unregisterInstanceName()
                        // via Atom.dispose() — that's the canonical place to release the slot.
                        if (Std.isOfType(atomInstance, IDisposable)) {
                                try { cast(atomInstance, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing: $e'); }
                        }
                        _assembly.internalAtoms.remove(_atomId);
                }
                
                // === FIX: Синхронизация рантайма, если удаляемый атом был связан с портами сборки ===
                if (involvesSelf) {
                        _assembly.rebuildInternalConnections();
                }
                
                Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, atomId: _atomId});
                complete();
        }

    override public function undo():Void {
        // Restore atom definition
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // Ensure blueprint exists in registry
        var bp = AtomRegistry.get(_atomType);
        if (bp == null) {
            if (_atomDef != null && _atomDef.typeId != null) {
                bp = new Blueprint(_atomDef.typeId, _assembly.blueprint.name, [], null, [], []);
                AtomRegistry.registerBlueprint(bp.id, bp);
            }
        }

        // Recreate atom instance
        var atom = AssemblyFactory.createAtom(_atomType, _atomId);
        if (atom == null) { trace('DeleteAtomCommand.undo: Failed to create $_atomType'); return; }
        _assembly.internalAtoms.set(_atomId, atom);

        // ═══════════════════════════════════════════════════════════════════
        // v1.1: Restore saved displayName (or resolve a unique variant if the
        // original slot has since been taken by another atom).
        // ═══════════════════════════════════════════════════════════════════
        // The atom we just created has displayName = type (default). We need
        // to restore _savedDisplayName, BUT during the time the atom was
        // disposed, another atom may have taken the same name. So we ask
        // NamingService to resolve a unique variant — which is the saved name
        // itself if still free, or "SavedName_N" if not.
        // ═══════════════════════════════════════════════════════════════════
        var finalName:String;
        if (_savedDisplayName != null) {
                finalName = core.logic.NamingService.resolveUniqueInstanceName(
                                                        _savedDisplayName, _atomId);
        } else {
                // No saved name — generate a fresh one via factory
                finalName = AssemblyFactory.generateUniqueDisplayName(
                        _atomType,
                        core.logic.NamingService.isInstanceNameTaken,
                        null,
                        false
                );
        }
        atom.displayName = finalName;
        core.logic.NamingService.registerInstanceName(finalName, _atomId);

        // Restore connections to blueprint
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);
            }
        }

        Impulsys.quickEmit(EventType.ATOM_RESTORED, {
            assemblyId: _assembly.id,
            atomId: _atomId,
            x: _posX,
            y: _posY,
            atom: atom
        });

        // Delayed physical connection restore
        haxe.Timer.delay(restorePhysicalConnections, 10);
    }

    private function restorePhysicalConnections():Void {
        if (_connections == null) return;
        for (conn in _connections) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) cOut.link(cIn);
        }
        Impulsys.quickEmit(EventType.REDRAW_WIRES);
    }

    /**
     * Capture complete atom state for undo restoration.
     */
    private function saveSnapshot():Void {
        if (_atomDef != null) return;

        // Find Template ID via Assembly
        var templateId = _assembly.getTemplateId(_atomId);

        // Find atom definition in Blueprint by TEMPLATE ID
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == templateId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);
        if (atomInst != null) {
            // Take type from definition if available, otherwise from instance
            if (_atomDef != null) _atomType = _atomDef.typeId;
            else _atomType = atomInst.type;
            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        _connections = [];

        // Collect connections using TEMPLATE ID
        for (conn in _blueprint.internalConnections) {
            // Check connections where our atom participates
            // Compare conn.atomId with templateId (for loaded) and with _atomId (for created)
            var fromMatch = (conn.from.atomId == templateId || conn.from.atomId == _atomId);
            var toMatch = (conn.to.atomId == templateId || conn.to.atomId == _atomId);
            if (fromMatch || toMatch) {
                _connections.push(conn);
            }
        }
    }

    /**
     * Resolve a contact by atom ID and contact name.
     * Handles SELF (assembly ports) and regular atoms.
     */
    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            // Convert Template ID to Runtime ID if needed
            var realAtomId = _assembly.idMap.get(atomId);
            if (realAtomId == null) realAtomId = atomId; // Already Runtime ID

            var atom = _assembly.internalAtoms.get(realAtomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}
