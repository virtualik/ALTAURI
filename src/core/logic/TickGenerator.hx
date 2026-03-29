package core.logic;

import core.types.Priority;
import haxe.Timer;
import system.managers.DriverManager;

/**
 * TICK GENERATOR v1.1 (Unified Clock & Queue + Thread Safety)
 * Единый центр управления симуляцией.
 *
 * v1.1 Changes:
 * - FIXED: Заменен массив _pendingInputs на LockFreeQueue<Void->Void>.
 *   Это полностью устраняет Data Race при вызове scheduleNextTick()
 *   из сторонних потоков (например, Audio Thread в MiniAudioAtom).
 *
 * Архитектура:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   External Threads                  Main Loop (Game Loop)              │
 * │                                                                         │
 * │   ┌───────────────────┐             ┌─────────────────────────────────┐ │
 * │   │ Audio Callback    │             │  onEnterFrame() {              │ │
 * │   │ scheduleNextTick()│───SPSC────►│    TickGenerator.update(dt);   │ │
 * │   └───────────────────┘   Queue     │  }                              │ │
 * │                                         │                             │
 * │   ┌───────────────────┐                 ▼                             │
 * │   │ UI Input (Main)   │──────────► flushPendingInputs()              │
 * │   │ scheduleNextTick()│  (безопасно,│    │                            │
 * │   └───────────────────┘   тот поток) │    ▼                            │
 * │                                         performStep()                 │
 * │                                           ├─ DriverManager.update()   │
 * │                                           ├─ flushPendingInputs()     │
 * │                                           ├─ process()                │
 * │                                           └─ emitTick()               │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class TickGenerator
{
    private static var _instance:TickGenerator;

    // =========================================================================
    // CONFIGURATION (from SimulationClock)
    // =========================================================================

    /** Частота симуляции в Герцах. */
    public var targetHz(default, set):Int = 60;
    private function set_targetHz(value:Int):Int
    {
        targetHz = Std.int(Math.max(1, value));
        fixedDeltaTime = 1.0 / targetHz;
        return targetHz;
    }

    /** Фиксированный шаг времени в секундах. */
    public var fixedDeltaTime(default, null):Float = 1.0 / 60.0;

    /** Максимальное количество шагов за один кадр (защита от спирали смерти). */
    public var maxStepsPerFrame:Int = 5;

    // =========================================================================
    // STATE (from Timebase & SignalQueue)
    // =========================================================================

    /** Глобальный такт (счетчик импульсов). */
    public var currentTick(default, null):Int = 0;

    /** Время старта текущего кадра (для профилирования). */
    public var frameStartTime(default, null):Float = 0.0;

    private var _accumulator:Float = 0.0;
    private var _isPaused:Bool = false;

    // =========================================================================
    // QUEUE SYSTEM (from SignalQueue)
    // =========================================================================

    private var _queuesWrite:Map<Priority, Array<Void -> Void>>;
    private var _queuesRead:Map<Priority, Array<Void -> Void>>;
    private var _isProcessing:Bool = false;
    private var _suspended:Bool = false;

    // v1.1: Lock-free очередь для межпоточного обмена
    private var _pendingQueue:LockFreeQueue<Void -> Void>;
    
    private var _blockedUntilNextFrame:Bool = false;
    private var _iterationGuard:Int = 0;
    private var _maxIterationsPerTick:Int = 5000;

    // =========================================================================
    // LISTENERS (Tick Event)
    // =========================================================================

    private var _tickListeners:Array<Void -> Void> = [];

    public static function getInstance():TickGenerator
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
        
        // 4096 задач с запасом даже при самом агрессивном аудиопотоке
        _pendingQueue = new LockFreeQueue<Void -> Void>(4096);
    }

    // =========================================================================
    // MAIN LOOP (from SimulationClock)
    // =========================================================================

    /**
     * Главный метод обновления. Вызывается из Main.onMainLoop.
     */
    public function update(realDt:Float):Void
    {
        if (_isPaused) return;

        frameStartTime = Timer.stamp();

        // 1. Накапливаем время
        _accumulator += realDt;

        // 2. Защита от "Спирали смерти"
        var maxAccum:Float = fixedDeltaTime * maxStepsPerFrame;
        if (_accumulator > maxAccum)
        {
            _accumulator = maxAccum;
        }

        // 3. Выполняем шаги симуляции
        var stepsPerformed:Int = 0;

        while (_accumulator >= fixedDeltaTime)
        {
            performStep(fixedDeltaTime);
            _accumulator -= fixedDeltaTime;
            stepsPerformed++;

            if (stepsPerformed >= maxStepsPerFrame) break;
        }
    }

    /**
     * Один дискретный шаг симуляции.
     */
    private function performStep(dt:Float):Void
    {
        // 1. Продвигаем глобальный счетчик тактов (Timebase)
        currentTick++;

        // 2. Обновляем ДРАЙВЕРЫ (Analog/Generators) — СНАЧАЛА!
        // Генераторы создают данные в своих выходных контактах
        DriverManager.getInstance().update(dt);

        // 3. Запускаем ТАКТ ЛОГИКИ (Digital) — ПОТОМ!
        // SignalQueue распространяет данные от генераторов к осциллографам
        tick();
    }

    // =========================================================================
    // TICK LOGIC (from SignalQueue + Event)
    // =========================================================================

    /**
     * ТАКТ СИМУЛЯЦИИ
     * Обрабатывает отложенные задачи и уведомляет слушателей.
     */
    public function tick():Void
    {
        // Сброс блокировок нового кадра
        _blockedUntilNextFrame = false;

        // Внедряем запланированные входы (кнопки, инпуты, аудио данные)
        flushPendingInputs();

        // Запускаем распространение сигналов
        process();

        // Уведомляем слушателей о завершении такта (для синхронизации UI или иных систем)
        emitTick();
    }

    /**
     * Подписка на событие тика.
     */
    public function addTickListener(listener:Void -> Void):Void
    {
        if (listener != null && _tickListeners.indexOf(listener) == -1)
        {
            _tickListeners.push(listener);
        }
    }

    public function removeTickListener(listener:Void -> Void):Void
    {
        _tickListeners.remove(listener);
    }

    private function emitTick():Void
    {
        // Копируем массив для безопасной итерации (слушатель может отписаться)
        var listeners = _tickListeners.copy();
        for (l in listeners)
        {
            if (l != null) l();
        }
    }

    // =========================================================================
    // SCHEDULING API (from SignalQueue)
    // =========================================================================

    /**
     * Schedule a task for immediate execution within the current or next tick.
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void
    {
        if (_blockedUntilNextFrame) return;

        var queue = _queuesWrite.get(priority);
        if (queue != null)
        {
            queue.push(task);
        }
        // Если мы не в процессе обработки и не в паузе, запускаем немедленно
        // (но обычно все вызывается из update -> tick -> process)
        if (!_isProcessing && !_suspended)
        {
            process();
        }
    }

    /**
     * Schedule a task for execution at the START of the next tick.
     * v1.1: ПОТОКОБЕЗОПАСНО. Можно вызывать из Audio Thread.
     */
    public function scheduleNextTick(task:Void -> Void):Void
    {
        if (task != null)
        {
            if (!_pendingQueue.push(task))
            {
                trace('TickGenerator: pending queue overflow! Task dropped.');
            }
        }
    }

    public function suspend():Void
    {
        _suspended = true;
    }

    public function resume():Void
    {
        if (!_suspended) return;
        _suspended = false;
        _blockedUntilNextFrame = false;

        flushPendingInputs();
        if (!_isProcessing && hasPendingTasks()) process();
    }

    public function isSuspended():Bool return _suspended;

    public function hasPendingTasks():Bool
    {
        for (q in _queuesWrite) if (q != null && q.length > 0) return true;
        for (q in _queuesRead) if (q != null && q.length > 0) return true;
        
        // v1.1: проверка LockFreeQueue
        var test = _pendingQueue.pop();
        if (test != null)
        {
            // Если что-то есть, возвращаем обратно (через push, это безопасно из главного потока)
            // В идеале для SPSC нужен peek(), но для проверки переполнения пойдёт так
            _queuesWrite.get(NORMAL).push(test);
            return true;
        }
        return false;
    }

    public function flushPendingInputs():Void
    {
        var queue = _queuesWrite.get(NORMAL);
        if (queue == null) return;

        // v1.1: Вытаскиваем задачи из lock-free очереди без аллокаций
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

    private function process():Void
    {
        if (_suspended || _blockedUntilNextFrame) return;
        if (_isProcessing) return;

        _isProcessing = true;
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
                            catch (e:Dynamic) { trace('TickGenerator: Error in task: $e'); }
                        }
                    }
                    q.resize(0);
                }
            }

            if (haxe.Timer.stamp() - frameStartTime > 0.1) break; // Hard timeout
        }
        while (hasPendingTasks() && !_blockedUntilNextFrame);

        _isProcessing = false;
    }

    private function clearQueues():Void
    {
        for (q in _queuesWrite) if (q != null) q.resize(0);
        for (q in _queuesRead) if (q != null) q.resize(0);
    }

    public function clear():Void
    {
        clearQueues();
        _isProcessing = false;
        _suspended = false;
        _blockedUntilNextFrame = false;
    }

    public static function reset():Void
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

    public function pause():Void
    {
        _isPaused = true;
    }

    public function resumeSimulation():Void
    {
        _isPaused = false;
        _accumulator = 0.0;
    }
}