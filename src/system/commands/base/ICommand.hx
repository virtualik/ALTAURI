package system.commands.base;

/**
 * ICommand INTERFACE v1.0
 * 
 * Base interface for all commands in the system.
 * Defines the contract for the Command Pattern implementation.
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ICommand (Interface)                                                  │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Required Methods:                                              │   │
 * │   │  - execute()           → Perform the action                     │   │
 * │   │  - undo()              → Reverse the action                     │   │
 * │   │  - getDescription()    → Human-readable description             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Purpose:                                                              │
 * │   - Enables Undo/Redo functionality in the editor                       │
 * │   - Provides consistent API for all commands                            │
 * │   - Allows commands to be stored in history stacks                      │
 * │                                                                         │
 * │   Implementation:                                                       │
 * │   - All concrete commands must implement this interface                 │
 * │   - Typically extends Command base class                                │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
interface ICommand {
    
    /**
     * Execute the command action.
     * Should be idempotent when possible.
     */
    function execute():Void;
    
    /**
     * Undo the command action.
     * Should reverse the effects of execute().
     */
    function undo():Void;
    
    /**
     * Get human-readable description.
     * Used for logging and UI display.
     */
    function getDescription():String;
}