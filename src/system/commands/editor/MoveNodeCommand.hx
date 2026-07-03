package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.logic.Impulsys;

/**
 * MOVE NODE COMMAND v1.0
 * Moves a node to a new position.
 * Supports Undo/Redo.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   MoveNodeCommand                                                       │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Apply new position (_newX, _newY)                            │   │
 * │   │  - Update atom.x and atom.y in blueprint                        │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  - Apply old position (_oldX, _oldY)                            │   │
 * │   │  - Update atom.x and atom.y in blueprint                        │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Note:                                                                 │
 * │   - Visual update happens immediately in NodeEditor (not via impulse)   │
 * │   - This command only updates the Blueprint model                       │
 * │   - nodeId is expected to be Template ID (from NodeEditor)              │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class MoveNodeCommand extends Command {
    private var _blueprint:Blueprint;
    private var _nodeId:String; // Template ID (passed from NodeEditor)
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

    /**
     * Apply new position (used for execute/redo).
     */
    override private function executeInternal():Void {
        apply(_newX, _newY);
        complete();
    }

    /**
     * Restore old position (used for undo).
     */
    override public function undo():Void {
        apply(_oldX, _oldY);
    }

    /**
     * Update atom position in Blueprint.
     * Searches for atom by instanceId (Template ID).
     */
    private function apply(x:Float, y:Float):Void {
        var found = false;

        for (atom in _blueprint.internalAtoms) {
            if (atom.instanceId == _nodeId) {
                atom.x = x;
                atom.y = y;
                found = true;
                break;
            }
        }

        // Note: Visual update happens immediately in NodeEditor,
        // so no impulse is needed here — we only update the model.
        if (!found) {
            trace('MoveNodeCommand: Atom $_nodeId not found in blueprint');
        }
    }

    override public function getDescription():String return 'Move Node $_nodeId';
}