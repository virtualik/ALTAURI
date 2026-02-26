package editor.commands;

import core.Command;
import core.Blueprint;
import core.Impulsys;

class MoveNodeCommand extends Command {
    
    private var _blueprint:Blueprint;
    private var _nodeId:String;
    
    private var _oldX:Float;
    private var _oldY:Float;
    private var _newX:Float;
    private var _newY:Float;

    public function new(blueprint:Blueprint, nodeId:String, oldX:Float, oldY:Float, newX:Float, newY:Float) {
        super();
        _blueprint = blueprint;
        _nodeId = nodeId;
        _oldX = oldX;
        _oldY = oldY;
        _newX = newX;
        _newY = newY;
    }

    // Execute обновляет модель до НОВОЙ позиции.
    // Используется при Redo.
    override private function executeInternal():Void {
        apply(_newX, _newY);
        complete();
    }

    override public function undo():Void {
        apply(_oldX, _oldY);
    }

    private function apply(x:Float, y:Float):Void {
        // 1. Обновляем модель
        for (atom in _blueprint.internalAtoms) {
            if (atom.instanceId == _nodeId) {
                atom.x = x;
                atom.y = y;
                break;
            }
        }
        // 2. Обновляем Вид
        Impulsys.quickEmit("FORCE_UPDATE_NODE_POSITION", {id: _nodeId, x: x, y: y});
    }

    override public function getDescription():String return 'Move Node $_nodeId';
}