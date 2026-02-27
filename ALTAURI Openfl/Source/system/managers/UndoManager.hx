package system.managers;

import openfl.events.EventDispatcher;
import openfl.events.Event;
import system.commands.base.ICommand;

/**
 * UNDO MANAGER
 * Manages history of commands for undo/redo functionality.
 */
class UndoManager extends EventDispatcher {

    private static var _instance:UndoManager;

    private var _undoStack:Array<ICommand>;
    private var _redoStack:Array<ICommand>;

    private var _maxHistorySize:Int = 50;

    public static inline var UNDO_STACK_CHANGED:String = "undoStackChanged";
    public static inline var REDO_STACK_CHANGED:String = "redoStackChanged";

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

    public function executeAndStore(cmd:ICommand):Void {
        cmd.execute(); // Execute

        _undoStack.push(cmd);
        enforceHistoryLimit(_undoStack);

        if (_redoStack.length > 0) {
            _redoStack = [];
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }

        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        trace('UndoManager: Executed and stored "${cmd.getDescription()}"');
    }

    public function storeExecuted(cmd:ICommand):Void {
        _undoStack.push(cmd);
        enforceHistoryLimit(_undoStack);

        if (_redoStack.length > 0) {
            _redoStack = [];
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
    }

    public function undo():Void {
        if (_undoStack.length == 0) return;

        var action = _undoStack.pop();

        // --- Error protection ---
        try {
            action.undo();
        } catch (e:Dynamic) {
            trace('CRITICAL ERROR in Undo: ${action.getDescription()} -> $e');
        }

        _redoStack.push(action);

        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }

    public function redo():Void {
        if (_redoStack.length == 0) return;

        var action = _redoStack.pop();

        // --- Error protection ---
        try {
            action.execute();
        } catch (e:Dynamic) {
            trace('CRITICAL ERROR in Redo: ${action.getDescription()} -> $e');
        }

        _undoStack.push(action);

        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }

    public function clear():Void {
        _undoStack = [];
        _redoStack = [];
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }

    private function enforceHistoryLimit(stack:Array<ICommand>):Void {
        if (_maxHistorySize > 0 && stack.length > _maxHistorySize) {
            stack.shift();
        }
    }

    public var canUndo(get, never):Bool;
    private function get_canUndo():Bool return _undoStack.length > 0;

    public var canRedo(get, never):Bool;
    private function get_canRedo():Bool return _redoStack.length > 0;
}