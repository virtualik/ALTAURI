package system.commands.base;

import openfl.events.EventDispatcher;
import openfl.events.Event;
import system.commands.base.ICommand;

/**
 * Base abstract command class.
 * Implements infrastructure: completion events, error handling.
 */
class Command extends EventDispatcher implements ICommand {

    public function new() {
        super();
    }

    /**
     * Entry point. Called by UndoManager or manually.
     * Wraps execution in try-catch for safety.
     */
    public function execute():Void {
        try {
            executeInternal();
        } catch (e:Dynamic) {
            trace('[Command Error] ${getDescription()}: $e');
        }
    }

    /**
     * Internal logic. Must be overridden in subclasses.
     */
    private function executeInternal():Void {
        // Override me
    }

    /**
     * Undo logic. Must be overridden.
     */
    public function undo():Void {
        // Override me
    }

    /**
     * Description of command (for logs and UI).
     */
    public function getDescription():String {
        return "Abstract Command";
    }

    /**
     * Completion method. Called inside executeInternal.
     */
    private function complete():Void {
        dispatchEvent(new Event(Event.COMPLETE));
    }
}