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

class DeleteAtomCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String; // Это Runtime ID

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
        saveSnapshot();

        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.remove(conn);
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.unlink(cIn);
            }
        }

        if (_atomDef != null) {
            _blueprint.internalAtoms.remove(_atomDef);
        }

        var atomInstance = _assembly.internalAtoms.get(_atomId);

        if (atomInstance != null) {
            if (Std.isOfType(atomInstance, IDisposable)) {
                try { cast(atomInstance, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing: $e'); }
            }
            _assembly.internalAtoms.remove(_atomId);
        }

        Impulsys.quickEmit("ATOM_DELETED", {assemblyId: _assembly.id, id: _atomId});
        complete();
    }

    override public function undo():Void {
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        var bp = AtomRegistry.get(_atomType);
        if (bp == null) {
            if (_atomDef != null && _atomDef.typeId != null) {
                bp = new Blueprint(_atomDef.typeId, _assembly.blueprint.name, [], null, [], []);
                AtomRegistry.registerBlueprint(bp.id, bp);
            }
        }
        
        var atom = AssemblyFactory.createAtom(_atomType, _atomId);
        if (atom == null) { trace('DeleteAtomCommand.undo: Failed to create $_atomType'); return; }

        _assembly.internalAtoms.set(_atomId, atom);

        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);
            }
        }

        Impulsys.quickEmit("ATOM_RESTORED", {
            assemblyId: _assembly.id,
            id: _atomId,
            x: _posX,
            y: _posY,
            atom: atom
        });

        haxe.Timer.delay(restorePhysicalConnections, 10);
    }

    private function restorePhysicalConnections():Void {
        if (_connections == null) return;
        for (conn in _connections) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) cOut.link(cIn);
        }
        Impulsys.quickEmit("REDRAW_WIRES");
    }

    private function saveSnapshot():Void {
        if (_atomDef != null) return;

        // ИСПРАВЛЕНИЕ: Находим Template ID через Assembly
        var templateId = _assembly.getTemplateId(_atomId);

        // 1. Ищем определение в Blueprint по TEMPLATE ID
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == templateId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);
        if (atomInst != null) {
            // Берем тип из определения, если есть, иначе из экземпляра
            if (_atomDef != null) _atomType = _atomDef.typeId;
            else _atomType = atomInst.type;

            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        _connections = [];
        
        // 2. При сохранении связей используем TEMPLATE ID
        for (conn in _blueprint.internalConnections) {
            // Проверяем связи, где участвует наш атом
            // Надо сравнить conn.atomId с templateId (для загруженных) и с _atomId (для созданных)
            var fromMatch = (conn.from.atomId == templateId || conn.from.atomId == _atomId);
            var toMatch = (conn.to.atomId == templateId || conn.to.atomId == _atomId);

            if (fromMatch || toMatch) {
                _connections.push(conn);
            }
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        // Если atomId указывает на SELF
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            // ИСПРАВЛЕНИЕ: Преобразуем ID если это Template ID
            var realAtomId = _assembly.idMap.get(atomId);
            if (realAtomId == null) realAtomId = atomId; // Если нет в карте, значит это уже Runtime ID

            var atom = _assembly.internalAtoms.get(realAtomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}