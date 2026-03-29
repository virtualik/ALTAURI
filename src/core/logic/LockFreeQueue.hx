package core.logic;

/**
 * LOCK-FREE SPSC QUEUE v2.0 (Pure Header-Only C++ Injection)
 * 
 * Архитектура (Правильная инъекция):
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  Haxe генерирует LockFreeQueue.h:                                    │
 * │                                                                         │
 * │  #include <atomic>             // @:headerCode (ГЛОБАЛЬНЫЙ ВЕРХ)     │
 * │  struct AtomicQueueState { ... }                                      │
 * │  static inline lock_free_queue_create() { ... }                      │
 * │  ...                                                                   │
 * │                                                                         │
 * │  class LockFreeQueue_obj { ... }  // Класс Haxe                      │
 * │                                                                         │
 * │  Почему static inline:                                                 │
 * │  Заголовок включается во многие .cpp файлы (__boot__, TickGenerator). │
 * │  static inline гарантирует, что линковщик не увидит "дубликаты"       │
 * │  функций и не выдаст LNK2005.                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */

#if cpp
import cpp.RawPointer;
#end
#if hl
import std.atomic.AtomicInt;
#end

// =========================================================================
// C++ ПРОКСИ ТИП
// =========================================================================
#if cpp
@:native("AtomicQueueState")
@:structAccess
private extern class QState {}
#end

// =========================================================================
// ГЛОБАЛЬНАЯ ВСТАВКА В ЗАГОЛОВОК (В самый верх .h файла)
// =========================================================================
@:headerCode('
#include <atomic>

struct alignas(64) AtomicQueueState {
    std::atomic<int> head;
    std::atomic<int> tail;
};

static inline AtomicQueueState* lock_free_queue_create() {
    AtomicQueueState* s = new AtomicQueueState();
    s->head.store(0, std::memory_order_relaxed);
    s->tail.store(0, std::memory_order_relaxed);
    return s;
}

static inline void lock_free_queue_destroy(AtomicQueueState* s) {
    delete s;
}

static inline int lock_free_queue_load_head_relaxed(AtomicQueueState* s) {
    return s->head.load(std::memory_order_relaxed);
}

static inline int lock_free_queue_load_head_acquire(AtomicQueueState* s) {
    return s->head.load(std::memory_order_acquire);
}

static inline void lock_free_queue_store_head_release(AtomicQueueState* s, int val) {
    s->head.store(val, std::memory_order_release);
}

static inline int lock_free_queue_load_tail_relaxed(AtomicQueueState* s) {
    return s->tail.load(std::memory_order_relaxed);
}

static inline void lock_free_queue_store_tail_release(AtomicQueueState* s, int val) {
    s->tail.store(val, std::memory_order_release);
}
')
class LockFreeQueue<T>
{
    // =========================================================================
    // C++ СПЕЦИФИКА
    // =========================================================================
    #if cpp
    private var _state:RawPointer<QState>;

    @:native("lock_free_queue_create") private static extern function _create():RawPointer<QState>;
    @:native("lock_free_queue_destroy") private static extern function _destroy(s:RawPointer<QState>):Void;
    @:native("lock_free_queue_load_head_relaxed") private static extern function _loadHeadR(s:RawPointer<QState>):Int;
    @:native("lock_free_queue_load_head_acquire") private static extern function _loadHeadA(s:RawPointer<QState>):Int;
    @:native("lock_free_queue_store_head_release") private static extern function _storeHead(s:RawPointer<QState>, v:Int):Void;
    @:native("lock_free_queue_load_tail_relaxed") private static extern function _loadTailR(s:RawPointer<QState>):Int;
    @:native("lock_free_queue_store_tail_release") private static extern function _storeTail(s:RawPointer<QState>, v:Int):Void;
    #end

    // =========================================================================
    // HASHLINK СПЕЦИФИКА
    // =========================================================================
    #if hl
    private var _head:AtomicInt;
    private var _tail:AtomicInt;
    #end

    // =========================================================================
    // ОБЩЕЕ СОСТОЯНИЕ
    // =========================================================================
    private var _buffer:Array<T>;
    private var _capacity:Int;

    // =========================================================================
    // ИНИЦИАЛИЗАЦИЯ
    // =========================================================================
    public function new(capacity:Int)
    {
        _capacity = capacity;
        _buffer = new Array<T>();
        for (i in 0...capacity) _buffer.push(null);
        
        #if cpp
        _state = _create();
        #end
        #if hl
        _head = new AtomicInt(0);
        _tail = new AtomicInt(0);
        #end
    }

    // =========================================================================
    // API
    // =========================================================================

    /**
     * Добавить элемент (Producer Thread).
     */
    public function push(item:T):Bool
    {
        #if cpp
        var currentHead:Int = _loadHeadR(_state);
        var currentTail:Int = _loadTailR(_state);
        #end
        #if hl
        var currentHead:Int = _head.get();
        var currentTail:Int = _tail.get();
        #end

        var nextHead:Int = (currentHead + 1) % _capacity;
        if (nextHead == currentTail) return false;

        _buffer[currentHead] = item;

        #if cpp
        _storeHead(_state, nextHead);
        #end
        #if hl
        _head.set(nextHead);
        #end

        return true;
    }

    /**
     * Извлечь элемент (Consumer Thread).
     */
    public function pop():Null<T>
    {
        #if cpp
        var currentTail:Int = _loadTailR(_state);
        var currentHead:Int = _loadHeadA(_state);
        #end
        #if hl
        var currentTail:Int = _tail.get();
        var currentHead:Int = _head.get();
        #end

        if (currentHead == currentTail) return null;

        var item = _buffer[currentTail];
        _buffer[currentTail] = null;

        #if cpp
        _storeTail(_state, (currentTail + 1) % _capacity);
        #end
        #if hl
        _tail.set((currentTail + 1) % _capacity);
        #end

        return item;
    }

    public function dispose():Void
    {
        #if cpp
        if (_state != null)
        {
            _destroy(_state);
            untyped _state = null;
        }
        #end
        _buffer = null;
    }
}