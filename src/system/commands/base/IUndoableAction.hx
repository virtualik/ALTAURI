package system.commands.base;

/**
 * Interface specifically for undoable actions history.
 */
interface IUndoableAction {
    /**
     * Undo the action.
     */
    function undo():Void;

    /**
     * Redo the action.
     */
    function redo():Void;

    /**
     * Description of the action (for UI or logs).
     */
    function getDescription():String;
}