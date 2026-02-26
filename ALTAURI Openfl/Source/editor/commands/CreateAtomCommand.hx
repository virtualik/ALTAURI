package editor.commands;

import core.Command;
import core.Blueprint;
import core.Assembly;
import core.Atom;
import core.Contact;
import core.ContactType;
import core.Impulsys;
import core.AtomDefinitions;

class CreateAtomCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    
    private var _typeId:String;
    private var _instanceId:String;
    private var _posX:Float;
    private var _posY:Float;
    
    // Сохраняем данные для отката
    private var _atomDef:core.Blueprint.AtomDef;
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
        // 1. Создаем определение для Blueprint (если это первый запуск)
        if (_atomDef == null) {
            _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
        }
        
        // Добавляем в модель
        // Проверка на contains не обязательна, но полезна для Redo
        if (!_blueprint.internalAtoms.contains(_atomDef)) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // 2. Создаем экземпляр Атома (логика, контакты)
        if (_atomInstance == null) {
            var bp = AtomDefinitions.get(_typeId);
            if (bp == null) return; // Защита

            var inputs = [];
            var outputs = [];
            for (pin in bp.pins) {
                var c = new Contact(pin.defaultValue, pin.type, pin.name);
                if (pin.type == ContactType.INPUT) inputs.push(c);
                else outputs.push(c);
            }
            _atomInstance = new Atom(inputs, outputs, bp.logic, _instanceId, _typeId);
        }
        
        // Регистрируем в Assembly
        _assembly.internalAtoms.set(_instanceId, _atomInstance);

        // 3. Шлем импульс, чтобы NodeEditor создал Вид (NodeView)
        Impulsys.quickEmit("ATOM_RESTORED", {id: _instanceId, x: _posX, y: _posY, atom: _atomInstance});
        
        complete();
    }

    override public function undo():Void {
        // 1. Удаляем определение из Blueprint
        _blueprint.internalAtoms.remove(_atomDef);
        
        // 2. Удаляем из Assembly (сам объект атома оставляем в памяти для Redo, но убираем из активной карты)
        _assembly.internalAtoms.remove(_instanceId);
        
        // 3. Шлем импульс, чтобы NodeEditor удалил Вид
        Impulsys.quickEmit("ATOM_DELETED", {id: _instanceId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}