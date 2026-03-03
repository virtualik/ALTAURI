package core.logic;

import core.types.Priority;

/**
 * SIGNAL QUEUE v2.0
 * Priority-based Task Scheduler.
 */
class SignalQueue {

    private static var _instance:SignalQueue;

    // Storage for queues
    private var _queues:Map<Priority, Array<Void -> Void>>;

    private var _isProcessing:Bool = false;

    // Protection against "Zombie Loops"
    private var _currentIteration:Int = 0;
    public var maxIterationsPerFrame:Int = 10000;

    public static function getInstance():SignalQueue {
        if (_instance == null) _instance = new SignalQueue();
        return _instance;
    }

    private function new() {
        _queues = new Map();
        // Initialize queues
        _queues.set(CRITICAL, []);
        _queues.set(NORMAL, []);
        _queues.set(BACKGROUND, []);
    }

    /**
     * Adds a task to the queue.
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        _queues.get(priority).push(task);

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

            while (queue.length > 0) {
                // Overflow protection
                _currentIteration++;
                if (_currentIteration > maxIterationsPerFrame) {
                    trace('WARN: SignalQueue overflow at priority $p. Pausing.');
                    _isProcessing = false;
                    return;
                }

                var task = queue.shift();
                task();
            }
        }

        _isProcessing = false;
    }

    /**
     * Returns true if the queue is overloaded (>80% of limit used).
     * Use this in "heavy" atoms for deferred execution.
     */
    public function isOverloaded():Bool {
        return _currentIteration > Std.int(maxIterationsPerFrame * 0.8);
    }

    public function clear():Void {
        _queues = new Map();
        _queues.set(CRITICAL, []);
        _queues.set(NORMAL, []);
        _queues.set(BACKGROUND, []);
        _isProcessing = false;
    }
}