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
import core.base.AssemblyFactory;
import library.AtomRegistry;

/**
 * Command to delete an atom and its connections.
 * Supports Undo/Redo with proper visual restoration.
 */
class DeleteAtomCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String;

    // Snapshot for restoration
    private var _atomDef:AtomDef;
    private var _atomType:String;
    private var _connections:Array<ConnectionDef>;
    private var _posX:Float;
    private var _posY:Float;

    public function new(blueprint:Blueprint, assembly:Assembly, atomId:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _atomId = atomId;
    }

    override private function executeInternal():Void {
        // 1. Save data BEFORE deletion
        saveSnapshot();

        // 2. Remove connections from model and physically
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.remove(conn);

                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.unlink(cIn);
            }
        }

        // 3. Remove Atom from model
        if (_atomDef != null) {
            _blueprint.internalAtoms.remove(_atomDef);
        }

        var atomInstance = _assembly.internalAtoms.get(_atomId);

        // 4. Properly dispose atom instance
        if (atomInstance != null) {
            if (Std.isOfType(atomInstance, IDisposable)) {
                try {
                    cast(atomInstance, IDisposable).dispose();
                } catch (e:Dynamic) {
                    trace('DeleteAtomCommand: Error disposing atom $_atomId: $e');
                }
            }
            _assembly.internalAtoms.remove(_atomId);
        }

        Impulsys.quickEmit("ATOM_DELETED", {id: _atomId});
        complete();
    }

    override public function undo():Void {
        // 1. Restore Atom in Blueprint
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // 2. Recreate Atom instance using Factory
		// ИСПРАВЛЕНИЕ: Убедиться, что Blueprint зарегистрирован в Registry
		var bp = AtomRegistry.get(_atomType);
		if (bp == null) {
			// Если Blueprint не найден, попроб восстановить из сохранённых данных
			if (_atomDef != null && _atomDef.typeId != null) {
				bp = new Blueprint(
					_atomDef.typeId,
					_assembly.blueprint.name, // Use the stored name
					[], // Will be populated from snapshot
					null,
					[],
					[]
				);
				AtomRegistry.registerBlueprint(bp.id, bp);
			}
		}
        var atom = AssemblyFactory.createAtom(_atomType, _atomId);
        if (atom == null) {
            trace('DeleteAtomCommand.undo: Failed to create atom $_atomType');
            return;
        }
        
        _assembly.internalAtoms.set(_atomId, atom);

        // 3. Restore connections in Blueprint
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);
            }
        }

        // 4. ИСПРАВЛЕНИЕ: Отправить событие для визуального восстановления
        Impulsys.quickEmit("ATOM_RESTORED", {
            id: _atomId, 
            x: _posX, 
            y: _posY, 
            atom: atom
        });
        
        // 5. Восстановить физические связи после небольшого delay
        // (чтобы NodeEditor успел создать визуал)
        haxe.Timer.delay(restorePhysicalConnections, 10);
    }
    
    private function restorePhysicalConnections():Void {
        if (_connections == null) return;
        
        for (conn in _connections) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) {
                cOut.link(cIn);
            }
        }
        
        Impulsys.quickEmit("REDRAW_WIRES");
    }

    private function saveSnapshot():Void {
        if (_atomDef != null) return;

        // 1. Сначала находим определение в Blueprint (оно содержит правильный typeId)
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == _atomId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);

        if (atomInst != null) {
            // ИСПРАВЛЕНИЕ: Берем typeId из определения (_atomDef), а не из atomInst.type.
            // atomInst.type может быть просто именем ("Frame Time"), а нужен ID ("FrameTimeAtom").
            if (_atomDef != null) {
                _atomType = _atomDef.typeId;
            } else {
                // Fallback на случай странностей
                _atomType = atomInst.type; 
            }
            
            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        // Сохраняем связи
        _connections = [];
        for (conn in _blueprint.internalConnections) {
            if (conn.from.atomId == _atomId || conn.to.atomId == _atomId) {
                _connections.push(conn);
            }
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            var atom = _assembly.internalAtoms.get(atomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}