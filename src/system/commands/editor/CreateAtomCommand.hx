package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.IDisposable;
import core.base.AssemblyFactory;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * CREATE ATOM COMMAND v1.1 (Template ID as instanceId + idMap Registration)
 * Creates a new atom instance in the assembly.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v1.1 CHANGES (Blueprint as Single Source of Truth)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  PROBLEM:
 *  The old code wrote `instanceId = UID.generate()` (RUNTIME ID) into
 *  AtomDef and stored the atom under that runtime ID in
 *  _assembly.internalAtoms. It did NOT register the mapping in _idMap.
 *
 *  This caused two symptoms:
 *    1. After save + restart, the atom's wires were lost. The disk-stored
 *       bp.internalAtoms[i].instanceId was a runtime ID that no longer
 *       existed in the new session. resolveContact failed, and the
 *       SAFETY NET in _createInternalConnections removed every wire as a
 *       ghost.
 *    2. resolveContact couldn't find the atom by template ID when looking
 *       up wires in bp.internalConnections, because _idMap didn't have
 *       the entry.
 *
 *  SOLUTION (Load-Symmetric Reconstruction principle):
 *  - Use the typeId (Template ID) as the instanceId in AtomDef. This is
 *    the same stable identifier that would be used if the assembly had
 *    been loaded from disk.
 *  - Register the template→runtime mapping via _assembly.registerAtomMapping()
 *    so that resolveContact can find the live instance by its template ID.
 *
 *  This makes CreateAtomCommand symmetric with the project-load path:
 *  when a project is loaded, _createInternalInstances generates a fresh
 *  runtime ID via UID.generate(), records template→runtime in _idMap,
 *  and stores the atom under the runtime ID. CreateAtomCommand now does
 *  exactly the same thing at runtime.
 *
 *  displayName generation is preserved — restored atoms get their name
 *  from initialState via restoreState(); newly created atoms get a
 *  unique displayName via AssemblyFactory.generateUniqueDisplayName.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   CreateAtomCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Generate runtimeId if not provided (UID.generate())          │   │
 * │   │  - v1.1: Use typeId as instanceId in AtomDef (Template ID)      │   │
 * │   │  - Create AtomDef with position                                 │   │
 * │   │  - Add AtomDef to blueprint.internalAtoms                       │   │
 * │   │  - Create atom instance via AssemblyFactory                     │   │
 * │   │  - Add instance to assembly.internalAtoms (keyed by runtimeId)  │   │
 * │   │  - v1.1: Register template→runtime mapping in assembly.idMap    │   │
 * │   │  - Emit ATOM_RESTORED event                                     │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  - Remove AtomDef from blueprint                                │   │
 * │   │  - Dispose atom instance                                        │   │
 * │   │  - Remove instance from assembly                                │   │
 * │   │  - Emit ATOM_DELETED event                                      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Atom Creation Flow:                                                   │
 * │   ─────────────────────                                                 │
 * │   1. Generate runtime ID (UID.generate)                                 │
 * │   2. Create AtomDef with instanceId = typeId (Template ID, v1.1)        │
 * │   3. Add to blueprint (persistence)                                     │
 * │   4. Create instance via Factory (runtime)                              │
 * │   5. Add to assembly.internalAtoms keyed by runtimeId                   │
 * │   6. Register template→runtime in _idMap (v1.1)                         │
 * │   7. Emit event (UI update)                                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class CreateAtomCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _typeId:String;
    private var _instanceId:String;  // runtime ID passed in (for undo/redo)
    private var _runtimeId:String;   // v1.1: actual runtime ID used
    private var _posX:Float;
    private var _posY:Float;
    private var _atomDef:core.data.Blueprint.AtomDef;
    private var _atomInstance:Atom;

    public function new(blueprint:Blueprint, assembly:Assembly, typeId:String, ?instanceId:String, x:Float, y:Float) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _typeId = typeId;
        _instanceId = instanceId;
        _posX = x;
        _posY = y;
    }

        override private function executeInternal():Void
        {
                // v1.1: Generate a fresh runtime ID for this instance.
                // This is what _createInternalInstances does at load time.
                if (_runtimeId == null) {
                        _runtimeId = (_instanceId != null) ? _instanceId : utils.UID.generate();
                }

                // v1.1: AtomDef.instanceId is the Template ID (typeId), NOT the
                // runtime ID. This matches the on-disk format and the
                // Load-Symmetric Reconstruction principle.
                if (_atomDef == null) {
                        _atomDef = { instanceId: _typeId, typeId: _typeId, x: _posX, y: _posY };
                }
                if (!_blueprint.internalAtoms.contains(_atomDef)) {
                        _blueprint.internalAtoms.push(_atomDef);
                }
                if (_atomInstance == null) {
                        _atomInstance = AssemblyFactory.createAtom(_typeId, _runtimeId);
                        if (_atomInstance == null) {
                                trace('CreateAtomCommand ERROR: Factory failed to create $_typeId');
                                return;
                        }
                }

                // === v1.1: Generate unique display name for NEW atoms ===
                // Only for newly created atoms (not restored from save).
                // Restored atoms get their displayName from initialState via restoreState().
                if (_atomInstance.displayName == null || _atomInstance.displayName == _atomInstance.type) {
                        _atomInstance.displayName = AssemblyFactory.generateUniqueDisplayName(_typeId, _assembly);
                }

                // Store the atom under its RUNTIME ID (matches _createInternalInstances).
                _assembly.internalAtoms.set(_runtimeId, _atomInstance);

                // v1.1: Register template→runtime mapping so that resolveContact
                // can find this atom by its template ID in bp.internalConnections.
                // Without this, wires referencing this atom would fail to resolve
                // after save/load or after EditorContext.updateInstancesOf.
                _assembly.registerAtomMapping(_typeId, _runtimeId);

                Impulsys.quickEmit(EventType.ATOM_RESTORED, {
                        assemblyId: _assembly.id,
                        id: _runtimeId,
                        x: _posX,
                        y: _posY,
                        atom: _atomInstance
                });
                complete();
        }

    override public function undo():Void {
        _blueprint.internalAtoms.remove(_atomDef);

        var inst = _assembly.internalAtoms.get(_runtimeId);
        if (inst != null) {
            if (Std.isOfType(inst, IDisposable)) {
                try { cast(inst, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing atom: $e'); }
            }
            _assembly.internalAtoms.remove(_runtimeId);
        }

        // v1.1: Remove the template→runtime mapping we added in execute().
        _assembly.unregisterAtomMapping(_typeId);

        _atomInstance = null;

        Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: _runtimeId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}