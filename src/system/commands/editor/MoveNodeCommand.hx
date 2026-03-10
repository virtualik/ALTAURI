package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.logic.Impulsys;

/**
 * Command to move a node position.
 */
class MoveNodeCommand extends Command {

    private var _blueprint:Blueprint;
    private var _nodeId:String; // Теперь ожидает Template ID (так как мы его так передаем)

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

    // Execute updates model to NEW position.
    // Used for Redo.
    override private function executeInternal():Void {
        apply(_newX, _newY);
        complete();
    }

    override public function undo():Void {
        apply(_oldX, _oldY);
    }

    private function apply(x:Float, y:Float):Void {
        // 1. Update Model
        // Ищем по ID, который пришел (это Template ID из NodeEditor)
        var found = false;
        for (atom in _blueprint.internalAtoms) {
            if (atom.instanceId == _nodeId) {
                atom.x = x;
                atom.y = y;
                found = true;
                break;
            }
        }
        
        // Примечание: Так как мы обновляем вид немедленно в NodeEditor,
        // здесь нам нужно только обновить данные модели.
        // Импульс на обновление вида можно не слать, чтобы не дергать лишний раз.
        
        if (!found) {
            trace('MoveNodeCommand: Atom $_nodeId not found in blueprint');
        }
    }

    override public function getDescription():String return 'Move Node $_nodeId';
}