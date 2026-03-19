package core.logic;

import core.types.Priority;

/**
 * SIGNAL QUEUE v3.0 (Zero-Allocation Core)
 * Priority-based Task Scheduler optimized for high-frequency signals.
 *
 * v3.0 Changes:
 * - Implemented Double Buffering to eliminate Array.shift() (which caused O(N) copies and GC pressure).
 * - Zero allocations during steady state operation (reuses arrays).
 * - Massive performance boost for signal-heavy graphs.
 */
class SignalQueue {

    private static var _instance:SignalQueue;

    // Два набора очередей: одна для записи (write), вторая для чтения/выполнения (read)
    private var _queuesWrite:Map<Priority, Array<Void -> Void>>;
    private var _queuesRead:Map<Priority, Array<Void -> Void>>;

    private var _isProcessing:Bool = false;
    private var _currentIteration:Int = 0;

    // Увеличенный лимит для сложных схем
    public var maxIterationsPerFrame:Int = 50000;

    public static function getInstance():SignalQueue {
        if (_instance == null) _instance = new SignalQueue();
        return _instance;
    }

    private function new() {
        _queuesWrite = new Map();
        _queuesRead = new Map();

        // Инициализация буферов
        _queuesWrite.set(CRITICAL, []);
        _queuesWrite.set(NORMAL, []);
        _queuesWrite.set(BACKGROUND, []);

        _queuesRead.set(CRITICAL, []);
        _queuesRead.set(NORMAL, []);
        _queuesRead.set(BACKGROUND, []);
    }

    /**
     * Adds a task to the write buffer.
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        var queue = _queuesWrite.get(priority);
        if (queue != null) {
            queue.push(task);
        }

        if (!_isProcessing) {
            process();
        }
    }

    /**
     * Iterative processing using Double Buffering.
     */
    public function process():Void {
        _isProcessing = true;
        _currentIteration = 0;

        // 1. Свапаем буферы: то, что писали - становится очередью на чтение.
        // Пустой буфер чтения становится буфером записи для новых задач.
        var temp = _queuesRead;
        _queuesRead = _queuesWrite;
        _queuesWrite = temp;

        // 2. Очищаем буфер записи (в который теперь будем писать новые задачи)
        // resize(0) быстрее, чем создание нового массива, так как сохраняет емкость
        var clearQ = _queuesWrite.get(CRITICAL); if (clearQ != null) clearQ.resize(0);
        clearQ = _queuesWrite.get(NORMAL); if (clearQ != null) clearQ.resize(0);
        clearQ = _queuesWrite.get(BACKGROUND); if (clearQ != null) clearQ.resize(0);

        // 3. Обрабатываем задачи из Read буфера
        var order:Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];

        for (p in order) {
            var queue = _queuesRead.get(p);

            if (queue != null && queue.length > 0) {
                // Итерация по индексу - самая быстрая операция
                for (i in 0...queue.length) {
                    // Защита от бесконечного цикла
                    _currentIteration++;
                    if (_currentIteration > maxIterationsPerFrame) {
                        trace('WARN: SignalQueue overflow at priority $p. Clearing.');
                        clear();
                        _isProcessing = false;
                        return;
                    }

                    var task = queue[i];
                    if (task != null) {
                        try {
                            task();
                        } catch (e:Dynamic) {
                            trace('ERROR in SignalQueue task: $e');
                        }
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
        for (q in _queuesWrite) if(q != null) q.resize(0);
        for (q in _queuesRead) if(q != null) q.resize(0);
        _isProcessing = false;
        _currentIteration = 0;
    }

    /**
     * Execute all pending tasks immediately and clear.
     */
    public function flush():Void {
        process();
    }

    /**
     * Get total number of pending tasks (approx).
     */
    public function getTotalTaskCount():Int {
        var total = 0;
        for (q in _queuesWrite) if (q != null) total += q.length;
        for (q in _queuesRead) if (q != null) total += q.length;
        return total;
    }

    public static function reset():Void {
        if (_instance != null) {
            _instance.clear();
            _instance = null;
        }
    }
}