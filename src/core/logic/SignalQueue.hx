package core.logic;
import core.types.Priority;

/**
* SIGNAL QUEUE v3.8 (Initialization Fix)
* Гибридная архитектура: Синхронная логика + Асинхронные драйверы.
*
* v3.8 Changes (CRITICAL FIX):
* - FIXED: resume() now processes _pendingInputs before calling process()
* - FIXED: hasPendingTasks() now checks _pendingInputs
* - FIXED: tick() properly resets _blockedUntilNextFrame at the START
* - ADDED: flushPendingInputs() method for explicit pending input processing
* - IMPROVED: Better coordination with Assembly.isInitializing flag
*
* v3.7 Changes:
* - ADDED: Oscillation detection per contact.
* - ADDED: Contact-level iteration tracking to detect and stop infinite loops.
* - IMPROVED: Better logging for debugging feedback circuits.
*
* v3.6 Changes:
* - ADDED: _time (Global discrete time counter).
* - ADDED: _pendingInputs (Buffer for next tick events).
* - ADDED: scheduleNextTick(task). Used by Buttons/Inputs to sync with logic.
* - ADDED: tick(). The main simulation step processor.
*
* ARCHITECTURE:
* ┌─────────────────────────────────────────────────────────────────────────┐
* │                         ГИБРИДНАЯ МОДЕЛЬ                                │
* │                                                                         │
* │   1. DIGITAL (Logic):                                                   │
* │      Buttons/Inputs -> scheduleNextTick() -> _pendingInputs             │
* │      tick() starts -> Move _pendingInputs to Queue -> process()         │
* │      Result: All logic updates synchronized to discrete time steps.     │
* │                                                                         │
* │   2. ANALOG (Drivers/Audio):                                            │
* │      Audio/Oscillators -> schedule() -> Immediate Queue                 │
* │      process() -> Immediate propagation (Speed of Light)                │
* │      Result: Smooth audio and real-time visualization.                  │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*
* v3.5 Changes:
* Добавлен счетчик тиков и возможность ограничения скорости.
* - added `ticksProcessed`: сколько тактов симуляции выполнено за последний кадр.
* - added `maxTicksPerFrame`: лимит тиков (0 = без лимита, только по времени).
* - added `throttleSpeed()`: метод для замедления симуляции (слоу-мо).
* Обрабатывает только ОДИН буфер за вызов.
*
* Это создает задержку в 1 кадр между переключениями сигнала,
* что позволяет видеть изменения состояния в быстрых контурах.
*
* v3.0 Changes:
* - Implemented Double Buffering to eliminate Array.shift() (which caused O(N) copies and GC pressure).
* - Zero allocations during steady state operation (reuses arrays).
* - Massive performance boost for signal-heavy graphs.
*
* This is the CORE of the data flow system:
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   Contact.value = newValue                                              │
* │         │                                                               │
* │         ▼                                                               │
* │   SignalQueue.schedule(_propagate, NORMAL)                              │
* │         │                                                               │
* │         ▼                                                               │
* │   process() - executes all scheduled tasks                              │
* │         │                                                               │
* │         ├─► Contact._propagate()                                        │
* │         │      │                                                        │
* │         │      ├─► linkedTargets[i].value = value (chain reaction)      │
* │         │      │                                                        │
* │         │      ├─► owner.onContactChanged(this) (Atom processing)       │
* │         │      │                                                        │
* │         │      └─► callbackTargets[i](value) (DeviceView update)        │
* │         │                                                               │
* │         └─► ... more tasks ...                                          │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class SignalQueue
{
    private static var _instance:SignalQueue;
    private var _queuesWrite:Map<Priority, Array<Void -> Void>>;
    private var _queuesRead:Map<Priority, Array<Void -> Void>>;
    private var _isProcessing:Bool = false;
    private var _suspended:Bool = false;

    // =========================================================================
    // METRICS & CONTROL
    // =========================================================================
    public var maxProcessTime:Float = 0.010;
    public var maxTicksPerFrame:Int = 0;
    public var ticksProcessed(default, null):Int = 0;
    public var slowMotion:Bool = false;
    public var maxIterationsPerFrame:Int = 50000;

    // =========================================================================
    // HYBRID CORE
    // =========================================================================
    public var time(default, null):Int = 0;
    
    /**
     * Buffer for tasks scheduled via scheduleNextTick().
     * These tasks are moved to the main queue at the START of each tick().
     * 
     * IMPORTANT: This is used by Assembly initialization to defer signal
     * propagation until after isInitializing is set to false.
     */
    private var _pendingInputs:Array<Void -> Void>;

    // === FIX v3.8: Блокировка на уровне кадра ===
    private var _blockedUntilNextFrame:Bool = false;
    private var _iterationGuard:Int = 0;
    private var _maxIterationsPerTick:Int = 5000; // Уменьшен для быстрого обнаружения

    public static function getInstance():SignalQueue
    {
        if (_instance == null) _instance = new SignalQueue();
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
        _pendingInputs = [];
    }

    // =========================================================================
    // SCHEDULING API
    // =========================================================================

    /**
     * Schedule a task for immediate execution.
     * If queue is not suspended and not currently processing, executes immediately.
     * 
     * @param task The task to execute
     * @param priority Priority level (CRITICAL, NORMAL, BACKGROUND)
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void
    {
        // === FIX v3.8: Не принимаем задачи если заблокированы ===
        if (_blockedUntilNextFrame) return;

        var queue = _queuesWrite.get(priority);
        if (queue != null)
        {
            queue.push(task);
        }
        if (!_isProcessing && !_suspended)
        {
            process();
        }
    }

    /**
     * Schedule a task for execution at the START of the next tick.
     * 
     * This is used for:
     * - Button presses (user input)
     * - Initial signal propagation after Assembly creation
     * - Any event that should be synchronized with the simulation clock
     * 
     * Tasks scheduled here are NOT affected by suspend()/resume() during
     * the current frame - they will execute when tick() is called.
     * 
     * @param task The task to execute at next tick
     */
    public function scheduleNextTick(task:Void -> Void):Void
    {
        if (task != null)
        {
            _pendingInputs.push(task);
        }
    }

    /**
     * Suspend queue processing.
     * Used during Assembly initialization to prevent premature signal propagation.
     * 
     * NOTE: scheduleNextTick() tasks are NOT affected by suspend - they will
     * be processed when tick() or resume() is called.
     */
    public function suspend():Void 
    { 
        _suspended = true; 
    }

    /**
     * Resume queue processing.
     * 
     * v3.8 FIX: Now properly processes _pendingInputs before calling process().
     * This ensures that signals scheduled during initialization are properly
     * propagated after Assembly.isInitializing is set to false.
     */
    public function resume():Void
    {
        if (!_suspended) return;
        _suspended = false;
        _blockedUntilNextFrame = false; // === FIX: Сброс блокировки ===
        
        // === CRITICAL FIX v3.8: Обрабатываем pendingInputs ПЕРЕД process() ===
        flushPendingInputs();
        
        if (!_isProcessing && hasPendingTasks()) process();
    }

    public function isSuspended():Bool return _suspended;

    /**
     * Check if there are any pending tasks in the queues.
     * 
     * v3.8 FIX: Now also checks _pendingInputs.
     */
    public function hasPendingTasks():Bool
    {
        for (q in _queuesWrite) if (q != null && q.length > 0) return true;
        for (q in _queuesRead) if (q != null && q.length > 0) return true;
        
        // === FIX v3.8: Проверяем pendingInputs ===
        if (_pendingInputs.length > 0) return true;
        
        return false;
    }

    /**
     * Get the count of pending inputs.
     * Useful for debugging initialization issues.
     */
    public function getPendingInputCount():Int
    {
        return _pendingInputs.length;
    }

    /**
     * Move all pending inputs to the NORMAL priority queue.
     * Called automatically by resume() and tick().
     * 
     * v3.8: New method for explicit pending input processing.
     */
    public function flushPendingInputs():Void
    {
        if (_pendingInputs.length == 0) return;
        
        var queue = _queuesWrite.get(NORMAL);
        if (queue != null)
        {
            for (task in _pendingInputs)
            {
                queue.push(task);
            }
        }
        _pendingInputs = [];
    }

    // =========================================================================
    // CORE EXECUTION
    // =========================================================================

    /**
     * Process all pending tasks in priority order.
     * 
     * Uses double-buffering to avoid O(N) array operations.
     * Tasks are read from _queuesRead and new tasks are written to _queuesWrite.
     */
    public function process():Void
    {
        if (_suspended || _blockedUntilNextFrame) return;
        if (_isProcessing) return;

        _isProcessing = true;
        ticksProcessed = 0;
        var startTime = haxe.Timer.stamp();
        _iterationGuard = 0;

        do {
            // Свап буферов
            var temp = _queuesRead;
            _queuesRead = _queuesWrite;
            _queuesWrite = temp;

            // Очистка Write
            var clearQ = _queuesWrite.get(CRITICAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(NORMAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(BACKGROUND); if (clearQ != null) clearQ.resize(0);

            // Выполнение задач
            var order:Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];
            for (p in order)
            {
                var queue = _queuesRead.get(p);
                if (queue != null && queue.length > 0)
                {
                    for (i in 0...queue.length)
                    {
                        _iterationGuard++;

                        // === FIX v3.8: Блокировка при превышении лимита ===
                        if (_iterationGuard > _maxIterationsPerTick)
                        {
                            // Тихо блокируем до следующего тика
                            _blockedUntilNextFrame = true;
                            clearQueues();
                            _isProcessing = false;
                            return;
                        }

                        var task = queue[i];
                        if (task != null)
                        {
                            try
                            {
                                task();
                            }
                            catch (e:Dynamic) 
                            { 
                                // Silent fail for now - could add error callback
                            }
                        }
                    }
                    queue.resize(0);
                }
            }
            ticksProcessed++;

            if (slowMotion) break;
            if (maxTicksPerFrame > 0 && ticksProcessed >= maxTicksPerFrame) break;
            if (maxProcessTime > 0 && (haxe.Timer.stamp() - startTime) > maxProcessTime) break;
        }
        while (hasPendingTasks() && !_blockedUntilNextFrame);

        _isProcessing = false;
    }

    /**
     * ТАКТ СИМУЛЯЦИИ
     * 
     * This is the main entry point for the simulation clock.
     * Should be called once per frame from Timebase.updateFrame().
     * 
     * Order of operations:
     * 1. Reset _blockedUntilNextFrame (allow new tasks)
     * 2. Move _pendingInputs to NORMAL queue
     * 3. Process all tasks
     * 4. Increment time counter
     */
    public function tick():Void
    {
        // === FIX v3.8: Сброс блокировки в начале нового тика ===
        _blockedUntilNextFrame = false;

        // === FIX v3.8: Внедряем запланированные входы ===
        flushPendingInputs();

        // Запускаем распространение
        process();

        // Увеличиваем время
        time++;
    }

    private function clearQueues():Void
    {
        for (q in _queuesWrite) if (q != null) q.resize(0);
        for (q in _queuesRead) if (q != null) q.resize(0);
    }

    public function clear():Void
    {
        clearQueues();
        _pendingInputs = [];
        _isProcessing = false;
        _suspended = false;
        _blockedUntilNextFrame = false;
        ticksProcessed = 0;
    }

    public static function reset():Void
    {
        if (_instance != null)
        {
            _instance.clear();
            _instance = null;
        }
    }
}
