package core;

import openfl.events.EventDispatcher;
import openfl.events.Event;

/**
 * МЕНЕДЖЕР ОТМЕНЫ/ПОВТОРА (Haxe Port)
 */
class UndoManager extends EventDispatcher {

    private static var _instance:UndoManager;
    
    // Используем Array вместо Vector
    private var _undoStack:Array<IUndoableAction>;
    private var _redoStack:Array<IUndoableAction>;
    
    private var _maxHistorySize:Int = 50;
    private var _isEnabled:Bool = true;

    // Константы событий
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

    public function registerAction(action:IUndoableAction):Void {
        if (!_isEnabled || action == null) return;

        _undoStack.push(action);
        enforceHistoryLimit(_undoStack);

        // Очистка Redo стека при новом действии
        if (_redoStack.length > 0) {
            _redoStack = []; // Проще создать новый массив
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        }

        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        trace('UndoManager: Registered. Undo: ${_undoStack.length}, Redo: ${_redoStack.length}');
    }

    public function undo():Void {
        if (!_isEnabled || _undoStack.length == 0) return;

        var action = _undoStack.pop();
        
        try {
            action.undo();
            _redoStack.push(action);
            
            dispatchEvent(new Event(UNDO_STACK_CHANGED));
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        } catch (e:Dynamic) {
            trace('UndoManager: ERROR during undo - $e');
            _undoStack.push(action); // Возврат обратно в стек
        }
    }

    public function redo():Void {
        if (!_isEnabled || _redoStack.length == 0) return;

        var action = _redoStack.pop();

        try {
            action.redo();
            _undoStack.push(action);
            
            dispatchEvent(new Event(UNDO_STACK_CHANGED));
            dispatchEvent(new Event(REDO_STACK_CHANGED));
        } catch (e:Dynamic) {
            trace('UndoManager: ERROR during redo - $e');
            _redoStack.push(action);
        }
    }

    private function enforceHistoryLimit(stack:Array<IUndoableAction>):Void {
        if (_maxHistorySize > 0 && stack.length > _maxHistorySize) {
            // Удаляем элементы с начала (самые старые)
            stack.splice(0, stack.length - _maxHistorySize);
        }
    }

    public function clear():Void {
        _undoStack = [];
        _redoStack = [];
        dispatchEvent(new Event(UNDO_STACK_CHANGED));
        dispatchEvent(new Event(REDO_STACK_CHANGED));
    }

    // Свойства (Properties в Haxe)
    public var canUndo(get, never):Bool;
    private function get_canUndo():Bool return _isEnabled && _undoStack.length > 0;

    public var canRedo(get, never):Bool;
    private function get_canRedo():Bool return _isEnabled && _redoStack.length > 0;
    
    public var isEnabled(get, set):Bool;
    private function get_isEnabled():Bool return _isEnabled;
    private function set_isEnabled(value:Bool):Bool {
        _isEnabled = value;
        return _isEnabled;
    }
}