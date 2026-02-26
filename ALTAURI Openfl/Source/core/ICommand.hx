package core;

/**
 * Базовый интерфейс для всех команд.
 * Добавляет контракт для отмены действий, критичный для редактора.
 */
interface ICommand {
    function execute():Void;
    function undo():Void;
    function getDescription():String;
}