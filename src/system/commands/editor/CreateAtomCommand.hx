package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.IDisposable;
import core.base.AssemblyFactory;
import core.logic.Impulsys;

/**
 * Command to create a new atom instance.
 * v2.1: CRITICAL FIX for Redo crash. 
 * Nullifies instance reference on Undo to force re-creation on Redo.
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
        // Генерируем ID только если это первый запуск (создание)
        if (_instanceId == null) {
            _instanceId = utils.UID.generate();
        }

        // Создаем определение
        if (_atomDef == null) {
            _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
        }

        if (!_blueprint.internalAtoms.contains(_atomDef)) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // СОЗДАЕМ ЭКЗЕМПЛЯР
        // Если _atomInstance null (первый раз или после Undo), создаем заново.
        if (_atomInstance == null) {
            _atomInstance = AssemblyFactory.createAtom(_typeId, _instanceId);
            if (_atomInstance == null) {
                trace('CreateAtomCommand ERROR: Factory failed to create $_typeId');
                return;
            }
        }

        _assembly.internalAtoms.set(_instanceId, _atomInstance);

        Impulsys.quickEmit("ATOM_RESTORED", {id: _instanceId, x: _posX, y: _posY, atom: _atomInstance});
        complete();
    }

    override public function undo():Void {
        // 1. Удаляем определение
        _blueprint.internalAtoms.remove(_atomDef);

        // 2. Удаляем из сборки и убиваем объект
        var inst = _assembly.internalAtoms.get(_instanceId);
        if (inst != null) {
            if (Std.isOfType(inst, IDisposable)) {
                try { 
                    cast(inst, IDisposable).dispose(); 
                } catch (e:Dynamic) { 
                    trace('Error disposing atom: $e'); 
                }
            }
            _assembly.internalAtoms.remove(_instanceId);
        }

        // 3. ИСПРАВЛЕНИЕ КРАША:
        // Зануляем ссылку, чтобы при Redo (вызов execute) создался НОВЫЙ объект.
        // Иначе мы попытаемся использовать старый, у которого inputs/outputs == null.
        _atomInstance = null;

        Impulsys.quickEmit("ATOM_DELETED", {id: _instanceId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}