package system.commands.base;

/**
 * Base interface for all commands.
 * Adds a contract for undoing actions, critical for the editor.
 */
interface ICommand {
    function execute():Void;
    function undo():Void;
    function getDescription():String;
}