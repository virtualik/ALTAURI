package system.managers;

import openfl.events.EventDispatcher;
import openfl.events.Event;
import system.commands.base.ICommand;

/**
 * UNDO MANAGER v1.0
 * Manages history of commands for undo/redo functionality.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   UndoManager (Singleton)                                               │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Stacks:                                                        │   │
 * │   │  - _undoStack:Array<ICommand>  → Executed commands              │   │
 * │   │  - _redoStack:Array<ICommand>  → Undone commands                │   │
 * │   │  - _maxHistorySize:Int = 50    → Memory limit                   │   │
 * │   │                                                                 │   │
 * │   │  Operations:                                                    │   │
 * │   │  - executeAndStore(cmd)  → Execute + push to undo stack         │   │
 * │   │  - storeExecuted(cmd)    → Push already-executed command        │   │
 * │   │  - undo()                → Pop from undo, push to redo          │   │
 * │   │  - redo()                → Pop from redo, push to undo          │   │
 * │   │  - clear()               → Clear both stacks                    │   │
 * │   │                                                                 │   │
 * │   │  Events:                                                        │   │
 * │   │  - UNDO_STACK_CHANGED    → Dispatched when undo stack changes   │   │
 * │   │  - REDO_STACK_CHANGED    → Dispatched when redo stack changes   │   │
 * │   │                                                                 │   │
 * │   │  Properties:                                                    │   │
 * │   │  - canUndo:Bool          → True if undo stack is not empty      │   │
 * │   │  - canRedo:Bool          → True if redo stack is not empty      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var cmd = new CreateAtomCommand(...);                                 │
 * │   UndoManager.getInstance().executeAndStore(cmd);                       │
 * │                                                                         │
 * │   // Later...                                                           │
 * │   UndoManager.getInstance().undo();  // Reverses the command            │
 * │   UndoManager.getInstance().redo();  // Re-executes the command         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class UndoManager extends EventDispatcher {
    // =========================================================================
    // SINGLETON
    // =========================================================================
    private static var _instance:UndoManager;
    
    // =========================================================================
    // STATE
    // =========================================================================
    private var _undoStack:Array<ICommand>;
    private var _redoStack:Array<ICommand>;
    private var _maxHistorySize:Int = 50;
    
    // =========================================================================
    // EVENTS
    // =========================================================================
    public static inline var UNDO_STACK_CHANGED:String = "undoStackChanged";
    public static inline var REDO_STACK_CHANGED:String = "redoStackChanged";
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    private function new() {
        super();
        _undoStack = [];
        _redoStack = [];
    }
    
    public static function getInstance():UndoManager {
        if (_instance == null) {
            _instance = new UndoManager();
        }
        return _instance;
    }
    
    // =========================================================================
    // EXECUTION
    // =========================================================================
    /**
     * Execute a command and store it in undo history.
     * Clears redo stack (new action invalidates redo history).
     * 
     * @param cmd Command to execute and store
     */
    public function executeAndStore(cmd:ICommand):Void {
        cmd.execute(); // Execute
        
        _undoStack.push(cmd);
        enforceHistoryLimit(_undoStack);
        
        // Clear redo stack on new action
        if (_redoStack.length > 0) {
            _redoStack = [];
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }
        
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        //trace('UndoManager: Executed and stored "${cmd.getDescription()}"');
    }
    
    /**
     * Store an already-executed command in undo history.
     * Used for batch operations where command was executed separately.
     * 
     * @param cmd Already-executed command to store
     */
    public function storeExecuted(cmd:ICommand):Void {
        _undoStack.push(cmd);
        enforceHistoryLimit(_undoStack);
        
        if (_redoStack.length > 0) {
            _redoStack = [];
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }
        
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
    }
    
    // =========================================================================
    // UNDO/REDO
    // =========================================================================
    /**
     * Undo the last executed command.
     * Moves command from undo stack to redo stack.
     */
    public function undo():Void {
        if (_undoStack.length == 0) return;
        
        var action = _undoStack.pop();
        
        // Error protection
        try {
            action.undo();
        } catch (e:Dynamic) {
            //trace('CRITICAL ERROR in Undo: ${action.getDescription()} -> $e');
        }
        
        _redoStack.push(action);
        
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }
    
    /**
     * Redo the last undone command.
     * Moves command from redo stack to undo stack.
     */
    public function redo():Void {
        if (_redoStack.length == 0) return;
        
        var action = _redoStack.pop();
        
        // Error protection
        try {
            action.execute();
        } catch (e:Dynamic) {
            //trace('CRITICAL ERROR in Redo: ${action.getDescription()} -> $e');
        }
        
        _undoStack.push(action);
        
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }
    
    // =========================================================================
    // CLEANUP
    // =========================================================================
    /**
     * Clear both undo and redo stacks.
     * Called on project reset or hard reload.
     */
    public function clear():Void {
        _undoStack = [];
        _redoStack = [];
        
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }
    
    /**
     * Enforce maximum history size.
     * Removes oldest commands when limit is exceeded.
     */
    private function enforceHistoryLimit(stack:Array<ICommand>):Void {
        if (_maxHistorySize > 0 && stack.length > _maxHistorySize) {
            stack.shift();
        }
    }
    
    // =========================================================================
    // PROPERTIES
    // =========================================================================
    /**
     * Check if undo is available.
     */
    public var canUndo(get, never):Bool;
    private function get_canUndo():Bool return _undoStack.length > 0;
    
    /**
     * Check if redo is available.
     */
    public var canRedo(get, never):Bool;
    private function get_canRedo():Bool return _redoStack.length > 0;
}