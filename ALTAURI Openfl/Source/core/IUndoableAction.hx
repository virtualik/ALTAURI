package core;

interface IUndoableAction {
    /**
     * Отменить действие
     */
    function undo():Void;

    /**
     * Повторить действие
     */
    function redo():Void;

    /**
     * Описание действия (для UI или логов)
     */
    function getDescription():String;
}