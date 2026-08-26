package system.managers;
import openfl.events.EventDispatcher;
import openfl.events.Event;
import system.commands.base.ICommand;
import core.logic.TickGenerator;

/**
* UNDO MANAGER v1.1 (Reentrancy-safe Topology Transaction Guard Integration)
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
* │   ═══════════════════════════════════════════════════════════════════   │
* │   v1.1  REENTRANCY-SAFE TOPOLOGY TRANSACTION GUARD                      │
* │   ═══════════════════════════════════════════════════════════════════   │
* │                                                                         │
* │   All command executions (execute, undo, redo) are now wrapped in a     │
* │   Topology Transaction via TickGenerator.lockTopology().                │
* │                                                                         │
* │   This guarantees that structural mutations (GroupAtoms, DeletePort,    │
* │   CreateAtom) happen in an atomic zone where the reactive graph is      │
* │   frozen. Signal propagation is deferred until the transaction ends.    │
* │                                                                         │
* │   NOTE: Haxe does not have a `finally` keyword in try-catch blocks.     │
* │   Therefore, unlockTopology() is called explicitly at the end of both   │
* │   the `try` block and the `catch` block to guarantee cleanup.           │
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

/**
* v1.2 (Episod G-3): the command currently executing (execute/undo/redo).
*
* Commands are synchronous, so at most one is in flight at any moment.
* Lets event handlers that fire DURING a command (e.g. Main.onPortRemoved
* inside Assembly.removePort inside RemovePortCommand.execute) hand their
* side-effect snapshots back to that command for undo symmetry.
*/
private var _executing:ICommand = null;

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
* v1.1: Wraps execution in Topology Transaction Guard.
* NOTE: Haxe has no `finally` keyword, so unlockTopology() is called
*       explicitly at the end of both `try` and `catch` blocks.
*
* @param cmd Command to execute and store
*/
public function executeAndStore(cmd:ICommand):Void {
    var tg = TickGenerator.getInstance();
    tg.lockTopology();
    _executing = cmd; // v1.2 (Episod G-3)
    try {
        cmd.execute(); // Execute
        _undoStack.push(cmd);
        enforceHistoryLimit(_undoStack);

        // Clear redo stack on new action
        if (_redoStack.length > 0) {
            _redoStack = [];
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        
        // Unlock on success (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    } catch (e:Dynamic) {
        trace('[UndoManager] Error executing command: $e');
        
        // Unlock on error (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    }
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
* 
* v1.1: Wraps undo in Topology Transaction Guard.
* NOTE: Haxe has no `finally` keyword, so unlockTopology() is called
*       explicitly at the end of both `try` and `catch` blocks.
*/
public function undo():Void {
    if (_undoStack.length == 0) return;
    var action = _undoStack.pop();

    var tg = TickGenerator.getInstance();
    tg.lockTopology();
    _executing = action; // v1.2 (Episod G-3)
    try {
        action.undo();
        _redoStack.push(action);
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
        
        // Unlock on success (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    } catch (e:Dynamic) {
        trace('[UndoManager] Error in Undo: $e');
        
        // Unlock on error (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    }
}

/**
* Redo the last undone command.
* Moves command from redo stack to undo stack.
* 
* v1.1: Wraps redo in Topology Transaction Guard.
* NOTE: Haxe has no `finally` keyword, so unlockTopology() is called
*       explicitly at the end of both `try` and `catch` blocks.
*/
public function redo():Void {
    if (_redoStack.length == 0) return;
    var action = _redoStack.pop();

    var tg = TickGenerator.getInstance();
    tg.lockTopology();
    _executing = action; // v1.2 (Episod G-3)
    try {
        action.execute();
        _undoStack.push(action);
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
        
        // Unlock on success (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    } catch (e:Dynamic) {
        trace('[UndoManager] Error in Redo: $e');
        
        // Unlock on error (Haxe has no `finally`)
        _executing = null; // v1.2 (Episod G-3)
        tg.unlockTopology();
    }
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
* v1.2 (Episod G-3): the command currently executing, or null when none is.
*/
public function getExecutingCommand():ICommand return _executing;

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
