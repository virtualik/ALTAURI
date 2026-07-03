package core.logic;

import core.types.Priority;
import haxe.Timer;
import system.managers.DriverManager;

/**
 * TICK GENERATOR v1.1 (Unified Clock & Queue + Thread Safety)
 *
 * The central hub for simulation control.
 *
 * Responsibilities:
 * - Manages the fixed time-step simulation loop
 * - Schedules and executes logic tasks (CRITICAL, NORMAL, BACKGROUND)
 * - Provides thread-safe task queue for external threads (e.g., Audio)
 *
 * Architecture:
 * ┌───────────────────────────────────────────────────────┐
 * │ External Threads        Main Loop (Game Loop)         │
 * │                                                       │
 * │ ┌────────────────┐      ┌──────────────────────────┐  │
 * │ │Audio Callback  │      │ onEnterFrame() {         │  │
 * │ │scheduleNextTick│─SPSC─▶ TickGenerator.update(dt);│  │
 * │ └────────────────Queue  │ }                        │  │
 * │                         │                          │  │
 * │ ┌────────────────       │ flushPendingInputs()     │  │
 * │ │UI Input (Main) │─────▶│   ↓                      │  │
 * │ │scheduleNextTick│(safe)│ performStep()            │  │
 * │ └────────────────┘thread│ ├─►DriverManager.update()│  │
 * │                         │ ├─►flushPendingInputs()  │  │
 * │                         │ ├─►process()             │  │
 * │                         │ └─►emitTick()            │  │
 * └───────────────────────────────────────────────────────┘
 *
 * v1.1 Changes:
 * - Replaced _pendingInputs array with LockFreeQueue<Void->Void>.
 *   This eliminates Data Race when calling scheduleNextTick() from
 *   external threads (e.g., Audio Thread in MiniAudioAtom).
 */
class TickGenerator
{
    private static var _instance: TickGenerator;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    /** Simulation frequency in Hertz. */
    public var targetHz(default, set): Int = 60;

    private function set_targetHz(value: Int): Int
    {
        targetHz = Std.int(Math.max(1, value));
        fixedDeltaTime = 1.0 / targetHz;
        return targetHz;
    }

    /** Fixed time step in seconds. */
    public var fixedDeltaTime(default, null): Float = 1.0 / 60.0;

    /** Maximum steps per frame (protection against "death spiral"). */
    public var maxStepsPerFrame: Int = 5;

    // =========================================================================
    // STATE
    // =========================================================================
    /** Global tick counter (impulse count). */
    public var currentTick(default, null): Int = 0;

    /** Start time of current frame (for profiling). */
    public var frameStartTime(default, null): Float = 0.0;

    private var _accumulator: Float = 0.0;
    private var _isPaused: Bool = false;

    // =========================================================================
    // QUEUE SYSTEM
    // =========================================================================
    private var _queuesWrite: Map<Priority, Array<Void -> Void>>;
    private var _queuesRead: Map<Priority, Array<Void -> Void>>;
    private var _isProcessing: Bool = false;
    private var _suspended: Bool = false;

    /** v1.1: Lock-free queue for cross-thread communication. */
    private var _pendingQueue: LockFreeQueue<Void -> Void>;

    private var _blockedUntilNextFrame: Bool = false;
    private var _iterationGuard: Int = 0;
    private var _maxIterationsPerTick: Int = 5000;

    // =========================================================================
    // LISTENERS (Tick Event)
    // =========================================================================
    private var _tickListeners: Array<Void -> Void> = [];

    public static function getInstance(): TickGenerator
    {
        if (_instance == null) _instance = new TickGenerator();
        return _instance;
    }

    private function new()
    {
        _queuesWrite = new Map();
        _queuesRead = new Map();
        _queuesWrite.set(CRITICAL, []);
        _queuesWrite.set(NORMAL, []);
        _queuesWrite.set(BACKGROUND, []);
        _queuesRead.set(CRITICAL, []);
        _queuesRead.set(NORMAL, []);
        _queuesRead.set(BACKGROUND, []);

        // 4096 tasks capacity - enough for aggressive audio streams
        _pendingQueue = new LockFreeQueue<Void -> Void>(4096);
    }

    // =========================================================================
    // MAIN LOOP
    // =========================================================================
    /**
     * Main update method. Called from Main.onMainLoop.
     *
     * @param realDt Real delta time in seconds
     */
    public function update(realDt: Float): Void
    {
        if (_isPaused) return;

        frameStartTime = Timer.stamp();

        // 1. Accumulate time
        _accumulator += realDt;

        // 2. Protection against "Death Spiral"
        // If accumulator grows too large (lag), clamp it to prevent freezing
        var maxAccum: Float = fixedDeltaTime * maxStepsPerFrame;
        if (_accumulator > maxAccum)
        {
            _accumulator = maxAccum;
        }

        // 3. Perform simulation steps
        var stepsPerformed: Int = 0;
        while (_accumulator >= fixedDeltaTime)
        {
            performStep(fixedDeltaTime);
            _accumulator -= fixedDeltaTime;
            stepsPerformed++;
            if (stepsPerformed >= maxStepsPerFrame) break;
        }
    }

    /**
     * One discrete simulation step.
     *
     * Order of execution is critical:
     * 1. Drivers (Analog/Generators) produce data FIRST
     * 2. Logic (Digital) propagates data SECOND
     */
    private function performStep(dt: Float): Void
    {
        // 1. Advance global tick counter (Timebase)
        currentTick++;

        // 2. Update DRIVERS (Analog/Generators) - FIRST!
        // Generators create data in their output contacts
        DriverManager.getInstance().update(dt);

        // 3. Run LOGIC TICK (Digital) - SECOND!
        // SignalQueue propagates data from generators to oscilloscopes
        tick();
    }

    // =========================================================================
    // TICK LOGIC
    // =========================================================================
    /**
     * SIMULATION TICK
     *
     * Processes pending tasks and notifies listeners.
     */
    public function tick(): Void
    {
        // Reset new frame locks
        _blockedUntilNextFrame = false;

        // Inject pending inputs (buttons, inputs, audio data)
        flushPendingInputs();

        // Launch signal propagation
        process();

        // Notify listeners about tick completion (for UI sync, etc.)
        emitTick();
    }

    /**
     * Subscribe to tick event.
     */
    public function addTickListener(listener: Void -> Void): Void
    {
        if (listener != null && _tickListeners.indexOf(listener) == -1)
        {
            _tickListeners.push(listener);
        }
    }

    public function removeTickListener(listener: Void -> Void): Void
    {
        _tickListeners.remove(listener);
    }

    private function emitTick(): Void
    {
        // Copy array for safe iteration (listener may unsubscribe)
        var listeners = _tickListeners.copy();
        for (l in listeners)
        {
            if (l != null) l();
        }
    }

    // =========================================================================
    // SCHEDULING API
    // =========================================================================
    /**
     * Schedule a task for immediate execution within current or next tick.
     *
     * @param task     Task to execute
     * @param priority Task priority (CRITICAL, NORMAL, BACKGROUND)
     */
    public function schedule(task: Void -> Void, priority: Priority = NORMAL): Void
    {
        if (_blockedUntilNextFrame) return;

        var queue = _queuesWrite.get(priority);
        if (queue != null)
        {
            queue.push(task);
        }

        // If not processing and not suspended, run immediately
        // (usually called from update -> tick -> process)
        if (!_isProcessing && !_suspended)
        {
            process();
        }
    }

    /**
     * Schedule a task for execution at the START of the next tick.
     *
     * v1.1: THREAD-SAFE. Can be called from Audio Thread.
     *
     * @param task Task to execute
     */
    public function scheduleNextTick(task: Void -> Void): Void
    {
        if (task != null)
        {
            if (!_pendingQueue.push(task))
            {
                trace('TickGenerator: pending queue overflow! Task dropped.');
            }
        }
    }

    public function suspend(): Void
    {
        _suspended = true;
    }

    public function resume(): Void
    {
        if (!_suspended) return;
        _suspended = false;
        _blockedUntilNextFrame = false;
        flushPendingInputs();
        if (!_isProcessing && hasPendingTasks()) process();
    }

    public function isSuspended(): Bool return _suspended;

    public function hasPendingTasks(): Bool
    {
        for (q in _queuesWrite) if (q != null && q.length > 0) return true;
        for (q in _queuesRead) if (q != null && q.length > 0) return true;

        // v1.1: Check LockFreeQueue
        var test = _pendingQueue.pop();
        if (test != null)
        {
            // If something exists, put it back (via push, safe from main thread)
            // Ideally SPSC needs peek(), but this works for overflow check
            _queuesWrite.get(NORMAL).push(test);
            return true;
        }
        return false;
    }

    /**
     * Flush tasks from lock-free queue to main queue.
     * Called at start of each tick.
     */
    public function flushPendingInputs(): Void
    {
        var queue = _queuesWrite.get(NORMAL);
        if (queue == null) return;

        // v1.1: Extract tasks from lock-free queue without allocations
        var task = _pendingQueue.pop();
        while (task != null)
        {
            queue.push(task);
            task = _pendingQueue.pop();
        }
    }

    // =========================================================================
    // CORE EXECUTION
    // =========================================================================
    private function process(): Void
    {
        if (_suspended || _blockedUntilNextFrame) return;
        if (_isProcessing) return;

        _isProcessing = true;
        _iterationGuard = 0;

        do {
            // Swap buffers
            var temp = _queuesRead;
            _queuesRead = _queuesWrite;
            _queuesWrite = temp;

            // Clear Write buffers
            var clearQ = _queuesWrite.get(CRITICAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(NORMAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(BACKGROUND); if (clearQ != null) clearQ.resize(0);

            // Execute tasks in priority order
            var order: Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];
            for (p in order)
            {
                var q = _queuesRead.get(p);
                if (q != null && q.length > 0)
                {
                    for (i in 0...q.length)
                    {
                        _iterationGuard++;
                        if (_iterationGuard > _maxIterationsPerTick)
                        {
                            _blockedUntilNextFrame = true;
                            clearQueues();
                            _isProcessing = false;
                            return;
                        }

                        var task = q[i];
                        if (task != null)
                        {
                            try { task(); }
                            catch (e: Dynamic) { trace('TickGenerator: Error in task: $e'); }
                        }
                    }
                    q.resize(0);
                }
            }

            // Hard timeout protection
            if (haxe.Timer.stamp() - frameStartTime > 0.1) break;
        }
        while (hasPendingTasks() && !_blockedUntilNextFrame);

        _isProcessing = false;
    }

    private function clearQueues(): Void
    {
        for (q in _queuesWrite) if (q != null) q.resize(0);
        for (q in _queuesRead) if (q != null) q.resize(0);
    }

    public function clear(): Void
    {
        clearQueues();
        _isProcessing = false;
        _suspended = false;
        _blockedUntilNextFrame = false;
    }

    public static function reset(): Void
    {
        if (_instance != null)
        {
            _instance.clear();
            if (_instance._pendingQueue != null) _instance._pendingQueue.dispose();
            _instance = null;
        }
    }

    // =========================================================================
    // PAUSE / CONTROL
    // =========================================================================
    public function pause(): Void
    {
        _isPaused = true;
    }

    public function resumeSimulation(): Void
    {
        _isPaused = false;
        _accumulator = 0.0;
    }
}