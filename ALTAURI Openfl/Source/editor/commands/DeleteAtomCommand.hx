package editor.commands;

import core.Command;
import core.Blueprint;
import core.Assembly;
import core.Atom;
import core.Contact;
import core.ContactType;
import core.Impulsys;

class DeleteAtomCommand extends Command {
    
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String;
    
    // Снепшот данных для восстановления
    private var _atomDef:core.Blueprint.AtomDef;
    private var _atomType:String;
    private var _connections:Array<core.Blueprint.ConnectionDef>; // Храним ссылки
    private var _posX:Float;
    private var _posY:Float;

    public function new(blueprint:Blueprint, assembly:Assembly, atomId:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _atomId = atomId;
    }

    override private function executeInternal():Void {
        // 1. Сохраняем данные ПЕРЕД удалением
        saveSnapshot();

        // 2. Удаляем связи из модели и физически
        if (_connections != null) {
            for (conn in _connections) {
                // Удаляем из Blueprint (метод remove ищет объект по ссылке)
                _blueprint.internalConnections.remove(conn);
                
                // Разрываем физически
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.unlink(cIn);
            }
        }

        // 3. Удаляем Атом из модели
        if (_atomDef != null) {
            _blueprint.internalAtoms.remove(_atomDef);
        }
        _assembly.internalAtoms.remove(_atomId);

        Impulsys.quickEmit("ATOM_DELETED", {id: _atomId});
        complete();
    }

    override public function undo():Void {
        // 1. Восстанавливаем Атом в Blueprint
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // 2. Воссоздаем экземпляр Атома
        var bp = core.AtomDefinitions.get(_atomType);
        if (bp == null) return;

        var inputs = [];
        var outputs = [];
        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }
        var atom = new Atom(inputs, outputs, bp.logic, _atomId, _atomType);
        _assembly.internalAtoms.set(_atomId, atom);

        // 3. Восстанавливаем связи
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);
                
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.link(cIn);
            }
        }

        Impulsys.quickEmit("ATOM_RESTORED", {id: _atomId, x: _posX, y: _posY, atom: atom});
    }

    private function saveSnapshot():Void {
        if (_atomDef != null) return; // Уже сохранено

        // Ищем определение атома
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == _atomId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);
        
        if (atomInst != null) {
            _atomType = atomInst.type;
            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        // Собираем все связи, связанные с этим атомом
        _connections = [];
        for (conn in _blueprint.internalConnections) {
            if (conn.from.atomId == _atomId || conn.to.atomId == _atomId) {
                _connections.push(conn);
            }
        }
    }

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            return (type == INPUT) ? _assembly.inputs.get(contactName) : _assembly.outputs.get(contactName);
        } else {
            var atom = _assembly.internalAtoms.get(atomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}