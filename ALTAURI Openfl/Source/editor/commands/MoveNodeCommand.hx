package editor.commands;

import core.IUndoableAction;
import core.Blueprint;
import core.Impulsys;

class MoveNodeCommand implements IUndoableAction {
    
    private var _blueprint:Blueprint;
    private var _nodeId:String;
    
    // Мы храним координаты как простые числа, это дешево для памяти
    private var _oldX:Float;
    private var _oldY:Float;
    private var _newX:Float;
    private var _newY:Float;

    public function new(blueprint:Blueprint, nodeId:String, oldX:Float, oldY:Float, newX:Float, newY:Float) {
        _blueprint = blueprint;
        _nodeId = nodeId;
        _oldX = oldX;
        _oldY = oldY;
        _newX = newX;
        _newY = newY;
    }

    public function undo():Void {
        apply(_oldX, _oldY);
    }

    public function redo():Void {
        apply(_newX, _newY);
    }

    private function apply(x:Float, y:Float):Void {
        // 1. Обновляем модель данных
        for (atom in _blueprint.internalAtoms) {
            if (atom.instanceId == _nodeId) {
                atom.x = x;
                atom.y = y;
                break;
            }
        }
        // Особый случай: если двигали "SELF" (корневой узел Assembly)
        // В текущей реализации он не сохраняется в internalAtoms, но мы можем обработать это отдельно, если нужно.
        // Пока предполагаем, что двигаем только внутренние атомы.

        // 2. Синхронизируем Вид
        // Посылаем импульс, чтобы NodeView обновил свои спрайты, если действие пришло из Undo/Redo
        Impulsys.quickEmit("FORCE_UPDATE_NODE_POSITION", {id: _nodeId, x: x, y: y});
    }

    public function getDescription():String {
        return 'Move Node $_nodeId';
    }
}