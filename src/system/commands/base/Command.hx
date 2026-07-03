package system.commands.base;

import openfl.events.EventDispatcher;
import openfl.events.Event;
import system.commands.base.ICommand;

/**
 * BASE COMMAND v1.0
 * 
 * Abstract base class for all commands in the system.
 * Implements the Command Pattern with Undo/Redo support.
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Command (Abstract Base)                                               │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Lifecycle:                                                     │   │
 * │   │  - execute()        → Entry point, wraps executeInternal()      │   │
 * │   │  - executeInternal()→ Override in subclasses for actual logic   │   │
 * │   │  - undo()           → Override to reverse the action            │   │
 * │   │  - getDescription() → Human-readable description for logs/UI    │   │
 * │   │  - complete()       → Dispatches Event.COMPLETE                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Error Handling:                                                       │
 * │   - execute() wraps logic in try-catch for safety                       │
 * │   - Errors are logged but don't crash the application                   │
 * │                                                                         │
 * │   Event System:                                                         │
 * │   - Extends EventDispatcher                                             │
 * │   - Dispatches Event.COMPLETE when action finishes                      │
 * │   - Listeners can react to command completion                           │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class Command extends EventDispatcher implements ICommand {
    
    public function new() {
        super();
    }
    
    /**
     * Entry point for command execution.
     * Called by UndoManager or manually.
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
     * Internal logic implementation.
     * Must be overridden in subclasses.
     */
    private function executeInternal():Void {
        // Override me
    }
    
    /**
     * Undo logic implementation.
     * Must be overridden in subclasses.
     */
    public function undo():Void {
        // Override me
    }
    
    /**
     * Human-readable description of the command.
     * Used for logs and UI display.
     */
    public function getDescription():String {
        return "Abstract Command";
    }
    
    /**
     * Completion method.
     * Called inside executeInternal() when action finishes.
     * Dispatches Event.COMPLETE to notify listeners.
     */
    private function complete():Void {
        dispatchEvent(new Event(Event.COMPLETE));
    }
}