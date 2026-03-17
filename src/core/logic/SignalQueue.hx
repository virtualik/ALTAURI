package core.logic;

import core.types.Priority;

/**
 * SIGNAL QUEUE v2.4 (Priority System)
 * Priority-based Task Scheduler.
 *
 * v2.4 Changes:
 * - Increased iteration limit for complex signal chains
 * - Safer queue clearing on overflow
 * - Added executeAndClear for atomic operations
 */
class SignalQueue {

    private static var _instance:SignalQueue;

    // Storage for queues by priority
    private var _queues:Map<Priority, Array<Void -> Void>>;

    private var _isProcessing:Bool = false;

    // Protection against "Zombie Loops"
    private var _currentIteration:Int = 0;

    // УВЕЛИЧЕННЫЙ ЛИМИТ: Позволяет обрабатывать больше сигналов за кадр
    public var maxIterationsPerFrame:Int = 25000;

    public static function getInstance():SignalQueue {
        if (_instance == null) _instance = new SignalQueue();
        return _instance;
    }

    private function new() {
        _queues = new Map();
        _queues.set(CRITICAL, []);
        _queues.set(NORMAL, []);
        _queues.set(BACKGROUND, []);
    }

    /**
     * Adds a task to the queue.
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        var queue = _queues.get(priority);
        if (queue != null) {
            queue.push(task);
        }

        if (!_isProcessing) {
            process();
        }
    }

    /**
     * Iterative processing.
     */
    public function process():Void {
        _isProcessing = true;
        _currentIteration = 0;

        // Processing order: Critical -> Normal -> Background
        var order:Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];

        for (p in order) {
            var queue = _queues.get(p);

            while (queue != null && queue.length > 0) {
                // Overflow protection
                _currentIteration++;
                if (_currentIteration > maxIterationsPerFrame) {
                    trace('WARN: SignalQueue overflow at priority $p. Clearing remaining tasks to prevent freeze.');

                    // Clear queues to prevent persistent lag spikes
                    clear();

                    _isProcessing = false;
                    return;
                }

                var task = queue.shift();
                if (task != null) {
                    try {
                        task();
                    } catch (e:Dynamic) {
                        trace('ERROR in SignalQueue task: $e');
                    }
                }
            }
        }

        _isProcessing = false;
    }

    /**
     * Returns true if the queue is overloaded (>80% of limit used).
     */
    public function isOverloaded():Bool {
        return _currentIteration > Std.int(maxIterationsPerFrame * 0.8);
    }

    /**
     * Clear all queues.
     */
    public function clear():Void {
        for (queue in _queues) {
            if (queue != null) {
                queue.resize(0);
            }
        }
        _isProcessing = false;
        _currentIteration = 0;
    }

    /**
     * Execute all pending tasks immediately and clear.
     * Useful for finalizing before save/exit.
     */
    public function flush():Void {
        var totalTasks = getTotalTaskCount();
        if (totalTasks > 0) {
            trace('SignalQueue: Flushing $totalTasks pending tasks...');
            process();
        }
    }

    /**
     * Get total number of pending tasks.
     */
    public function getTotalTaskCount():Int {
        var total = 0;
        for (queue in _queues) {
            if (queue != null) {
                total += queue.length;
            }
        }
        return total;
    }

    /**
     * Reset singleton instance.
     */
    public static function reset():Void {
        if (_instance != null) {
            _instance.clear();
            _instance = null;
        }
    }
}
