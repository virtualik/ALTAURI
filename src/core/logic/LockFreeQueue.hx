package core.logic;

/**
 * LOCK-FREE SPSC QUEUE v2.0 (Pure Header-Only C++ Injection)
 *
 * Architecture (Correct Injection):
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  Haxe generates LockFreeQueue.h:                                        │
 * │                                                                         │
 * │  #include <atomic>             // @:headerCode (GLOBAL TOP)             │
 * │  struct AtomicQueueState { ... }                                        │
 * │  static inline lock_free_queue_create() { ... }                         │
 * │  ...                                                                    │
 * │                                                                         │
 * │  class LockFreeQueue_obj { ... }  // Haxe Class                         │
 * │                                                                         │
 * │  Why static inline:                                                     │
 * │  Header is included in many .cpp files (__boot__, TickGenerator).       │
 * │  static inline guarantees linker won't see "duplicate" functions        │
 * │  and won't throw LNK2005 errors.                                        │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Thread Safety:
 * - Single Producer, Single Consumer (SPSC)
 * - Producer: External threads (Audio, etc.)
 * - Consumer: Main thread (TickGenerator)
 * - No locks needed - uses atomic operations
 */
#if cpp
import cpp.RawPointer;
#end

#if hl
import std.atomic.AtomicInt;
#end

// =========================================================================
// C++ PROXY TYPE
// =========================================================================
#if cpp
@:native("AtomicQueueState")
@:structAccess
private extern class QState {}
#end

// =========================================================================
// GLOBAL HEADER INJECTION (Top of .h file)
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
    // C++ SPECIFIC
    // =========================================================================
    #if cpp
    private var _state: RawPointer<QState>;

    @:native("lock_free_queue_create") private static extern function _create(): RawPointer<QState>;
    @:native("lock_free_queue_destroy") private static extern function _destroy(s: RawPointer<QState>): Void;
    @:native("lock_free_queue_load_head_relaxed") private static extern function _loadHeadR(s: RawPointer<QState>): Int;
    @:native("lock_free_queue_load_head_acquire") private static extern function _loadHeadA(s: RawPointer<QState>): Int;
    @:native("lock_free_queue_store_head_release") private static extern function _storeHead(s: RawPointer<QState>, v: Int): Void;
    @:native("lock_free_queue_load_tail_relaxed") private static extern function _loadTailR(s: RawPointer<QState>): Int;
    @:native("lock_free_queue_store_tail_release") private static extern function _storeTail(s: RawPointer<QState>, v: Int): Void;
    #end

    // =========================================================================
    // HASHLINK SPECIFIC
    // =========================================================================
    #if hl
    private var _head: AtomicInt;
    private var _tail: AtomicInt;
    #end

    // =========================================================================
    // COMMON STATE
    // =========================================================================
    private var _buffer: Array<T>;
    private var _capacity: Int;

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    public function new(capacity: Int)
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
     * Add an element (Producer Thread).
     *
     * @param item Item to add
     * @return true if successful, false if queue is full
     */
    public function push(item: T): Bool
    {
        #if cpp
        var currentHead: Int = _loadHeadR(_state);
        var currentTail: Int = _loadTailR(_state);
        var nextHead: Int = (currentHead + 1) % _capacity;

        if (nextHead == currentTail) return false; // Queue full

        _buffer[currentHead] = item;
        _storeHead(_state, nextHead);
        return true;

        #elseif hl
        var currentHead: Int = _head.get();
        var currentTail: Int = _tail.get();
        var nextHead: Int = (currentHead + 1) % _capacity;

        if (nextHead == currentTail) return false; // Queue full

        _buffer[currentHead] = item;
        _head.set(nextHead);
        return true;

        #else
        // Fallback for other targets (JS/Neko)
        _buffer.push(item);
        return true;
        #end
    }

    /**
     * Extract an element (Consumer Thread).
     *
     * @return Item or null if queue is empty
     */
    public function pop(): Null<T>
    {
        #if cpp
        var currentTail: Int = _loadTailR(_state);
        var currentHead: Int = _loadHeadA(_state);

        if (currentHead == currentTail) return null; // Queue empty

        var item = _buffer[currentTail];
        _buffer[currentTail] = null;
        _storeTail(_state, (currentTail + 1) % _capacity);
        return item;

        #elseif hl
        var currentTail: Int = _tail.get();
        var currentHead: Int = _head.get();

        if (currentHead == currentTail) return null; // Queue empty

        var item = _buffer[currentTail];
        _buffer[currentTail] = null;
        _tail.set((currentTail + 1) % _capacity);
        return item;

        #else
        // Fallback for other targets
        if (_buffer.length == 0) return null;
        return _buffer.shift();
        #end
    }

    /**
     * Dispose queue and free resources.
     */
    public function dispose(): Void
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