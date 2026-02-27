package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.Impulsys;
import library.AtomRegistry;

/**
 * Command to create a new atom instance.
 */
class CreateAtomCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;

    private var _typeId:String;
    private var _instanceId:String;
    private var _posX:Float;
    private var _posY:Float;

    // Snapshot data for undo
    private var _atomDef:core.data.Blueprint.AtomDef;
    private var _atomInstance:Atom;

    public function new(blueprint:Blueprint, assembly:Assembly, typeId:String, instanceId:String, x:Float, y:Float) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _typeId = typeId;
        _instanceId = instanceId;
        _posX = x;
        _posY = y;
    }

    override private function executeInternal():Void {
        // 1. Create definition for Blueprint (if first run)
        if (_atomDef == null) {
            _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
        }

        // Add to model
        if (!_blueprint.internalAtoms.contains(_atomDef)) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // 2. Create Atom instance (logic, contacts)
        if (_atomInstance == null) {
            var bp = AtomRegistry.get(_typeId);
            if (bp == null) return; 

            var inputs = [];
            var outputs = [];
            for (pin in bp.pins) {
                var c = new Contact(pin.defaultValue, pin.type, pin.name);
                if (pin.type == ContactType.INPUT) inputs.push(c);
                else outputs.push(c);
            }
            _atomInstance = new Atom(inputs, outputs, bp.logic, _instanceId, _typeId);
        }

        // Register in Assembly
        _assembly.internalAtoms.set(_instanceId, _atomInstance);

        // 3. Send impulse for NodeEditor to create View
        Impulsys.quickEmit("ATOM_RESTORED", {id: _instanceId, x: _posX, y: _posY, atom: _atomInstance});

        complete();
    }

    override public function undo():Void {
        // 1. Remove definition from Blueprint
        _blueprint.internalAtoms.remove(_atomDef);

        // 2. Remove from Assembly
        _assembly.internalAtoms.remove(_instanceId);

        // 3. Send impulse to delete View
        Impulsys.quickEmit("ATOM_DELETED", {id: _instanceId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}