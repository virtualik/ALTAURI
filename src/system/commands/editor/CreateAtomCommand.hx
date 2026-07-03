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
 * CREATE ATOM COMMAND v1.0
 * Creates a new atom instance in the assembly.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   CreateAtomCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Generate instanceId if not provided (UID.generate())         │   │
 * │   │  - Create AtomDef with position                                 │   │
 * │   │  - Add AtomDef to blueprint.internalAtoms                       │   │
 * │   │  - Create atom instance via AssemblyFactory                     │   │
 * │   │  - Add instance to assembly.internalAtoms                       │   │
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
 * │   1. Generate ID (if needed)                                            │
 * │   2. Create AtomDef (data model)                                        │
 * │   3. Add to blueprint (persistence)                                     │
 * │   4. Create instance via Factory (runtime)                              │
 * │   5. Add to assembly (execution)                                        │
 * │   6. Emit event (UI update)                                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class CreateAtomCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _typeId:String;
    private var _instanceId:String;
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

    override private function executeInternal():Void {
        if (_instanceId == null) {
            _instanceId = utils.UID.generate();
        }

        if (_atomDef == null) {
            _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
        }

        if (!_blueprint.internalAtoms.contains(_atomDef)) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        if (_atomInstance == null) {
            _atomInstance = AssemblyFactory.createAtom(_typeId, _instanceId);
            if (_atomInstance == null) {
                trace('CreateAtomCommand ERROR: Factory failed to create $_typeId');
                return;
            }
        }

        _assembly.internalAtoms.set(_instanceId, _atomInstance);

        Impulsys.quickEmit(EventType.ATOM_RESTORED, {
            assemblyId: _assembly.id,
            id: _instanceId,
            x: _posX,
            y: _posY,
            atom: _atomInstance
        });

        complete();
    }

    override public function undo():Void {
        _blueprint.internalAtoms.remove(_atomDef);

        var inst = _assembly.internalAtoms.get(_instanceId);
        if (inst != null) {
            if (Std.isOfType(inst, IDisposable)) {
                try { cast(inst, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing atom: $e'); }
            }
            _assembly.internalAtoms.remove(_instanceId);
        }

        _atomInstance = null;

        Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: _instanceId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}