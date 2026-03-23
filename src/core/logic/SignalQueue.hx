package core.logic;

import core.types.Priority;

/**
 * SIGNAL QUEUE v3.6 (Hybrid: Tick + Reactive)
 * Гибридная архитектура: Синхронная логика + Асинхронные драйверы.
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
 * 
 * SIGNAL QUEUE v3.6 (Hybrid: Tick + Reactive)
 * Гибридная архитектура: Синхронная логика + Асинхронные драйверы.
 *
 * v3.6 Changes:
 * - ADDED: _time (Global discrete time counter).
 * - ADDED: _pendingInputs (Buffer for next tick events).
 * - ADDED: scheduleNextTick(task). Used by Buttons/Inputs to sync with logic.
 * - ADDED: tick(). The main simulation step processor.
 *
 * ARCHITECTURE:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                         ГИБРИДНАЯ МОДЕЛЬ                               │
 * │                                                                         │
 * │   1. DIGITAL (Logic):                                                   │
 * │      Buttons/Inputs -> scheduleNextTick() -> _pendingInputs            │
 * │      tick() starts -> Move _pendingInputs to Queue -> process()        │
 * │      Result: All logic updates synchronized to discrete time steps.    │
 * │                                                                         │
 * │   2. ANALOG (Drivers/Audio):                                            │
 * │      Audio/Oscillators -> schedule() -> Immediate Queue                │
 * │      process() -> Immediate propagation (Speed of Light)               │
 * │      Result: Smooth audio and real-time visualization.                 │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v3.5 Changes:
 * - added `ticksProcessed`: сколько тактов симуляции выполнено за последний кадр.
 * - added `maxTicksPerFrame`: лимит тиков (0 = без лимита, только по времени).
 * - added `throttleSpeed()`: метод для замедления симуляции (слоу-мо).
 */
class SignalQueue {

    private static var _instance:SignalQueue;

    private var _queuesWrite:Map<Priority, Array<Void -> Void>>;
    private var _queuesRead:Map<Priority, Array<Void -> Void>>;

    private var _isProcessing:Bool = false;
    private var _suspended:Bool = false;

    // =========================================================================
    // METRICS & CONTROL
    // =========================================================================

    /** Бюджет времени на кадр (10 мс). Если 0 - работает только по счетчику тиков. */
    public var maxProcessTime:Float = 0.010;

    /** Лимит тиков за кадр. 0 = без лимита (пока есть время). */
    public var maxTicksPerFrame:Int = 0;

    /** Сколько тиков (проходов логики) было выполнено в прошлом кадре. */
    public var ticksProcessed(default, null):Int = 0;

    /** Включить замедление (1 тик за кадр - для отладки). */
    public var slowMotion:Bool = false;

    public var maxIterationsPerFrame:Int = 50000; // Общий лимит задач (защита от зависания)

    // =========================================================================
    // HYBRID CORE v3.6
    // =========================================================================

    /** Глобальное дискретное время (такты симуляции). */
    public var time(default, null):Int = 0;

    /** Буфер задач, запланированных на НАЧАЛО следующего такта. */
    private var _pendingInputs:Array<Void -> Void>;

    public static function getInstance():SignalQueue {
        if (_instance == null) _instance = new SignalQueue();
        return _instance;
    }

    private function new() {
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
     * Стандартное планирование (Асинхронное/Аналоговое).
     * Используется драйверами (Audio), визуализацией и для распространения сигналов.
     * Задача выполняется при ближайшем вызове process().
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        var queue = _queuesWrite.get(priority);
        if (queue != null) {
            queue.push(task);
        }

        if (!_isProcessing && !_suspended) {
            process();
        }
    }

    /**
     * Планирование на СЛЕДУЮЩИЙ ТАКТ (Синхронное/Цифровое).
     * Используется кнопками, входами и генераторами импульсов.
     * Задача будет выполнена в начале следующего вызова tick().
     */
    public function scheduleNextTick(task:Void -> Void):Void {
        if (task != null) {
            _pendingInputs.push(task);
        }
    }

    public function suspend():Void _suspended = true;

    public function resume():Void {
        if (!_suspended) return;
        _suspended = false;
        if (!_isProcessing && hasPendingTasks()) process();
    }

    public function isSuspended():Bool return _suspended;

    public function hasPendingTasks():Bool {
        for (q in _queuesWrite) if (q != null && q.length > 0) return true;
        for (q in _queuesRead) if (q != null && q.length > 0) return true;
        return false;
    }

    // =========================================================================
    // CORE EXECUTION
    // =========================================================================

    /**
     * Гибридный процессор.
     * Выполняет такты пока есть время ИЛИ пока не достигнут лимит тиков.
     */
    public function process():Void {
        if (_suspended) return;
        if (_isProcessing) return;

        _isProcessing = true;
        ticksProcessed = 0; // Сброс счетчика

        var startTime = haxe.Timer.stamp();
        var iterationGuard = 0; // Защита от бесконечного цикла внутри задач

        // === MULTI-PULSE LOOP ===
        do {
            // 1. Свап буферов
            var temp = _queuesRead;
            _queuesRead = _queuesWrite;
            _queuesWrite = temp;

            // 2. Очистка Write
            var clearQ = _queuesWrite.get(CRITICAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(NORMAL); if (clearQ != null) clearQ.resize(0);
            clearQ = _queuesWrite.get(BACKGROUND); if (clearQ != null) clearQ.resize(0);

            // 3. Выполнение задач (один такт)
            var order:Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];

            for (p in order) {
                var queue = _queuesRead.get(p);

                if (queue != null && queue.length > 0) {
                    for (i in 0...queue.length) {
                        iterationGuard++;
                        if (iterationGuard > maxIterationsPerFrame) {
                            trace('WARN: Iteration overflow!');
                            clear();
                            _isProcessing = false;
                            return;
                        }

                        var task = queue[i];
                        if (task != null) {
                            try { task(); }
                            catch (e:Dynamic) { trace('ERROR: $e'); }
                        }
                    }
                    queue.resize(0);
                }
            }

            ticksProcessed++; // Увеличиваем счетчик только что выполненного такта

            // === УСЛОВИЯ ВЫХОДА ===

            // 1. Если включен Slow Motion - выходим после 1 тика
            if (slowMotion) break;

            // 2. Если задан жесткий лимит тиков - выходим по нему
            if (maxTicksPerFrame > 0 && ticksProcessed >= maxTicksPerFrame) break;

            // 3. Выходим, если кончился бюджет времени (10 мс)
            if (maxProcessTime > 0 && (haxe.Timer.stamp() - startTime) > maxProcessTime) break;

        } while (hasPendingTasks());
        // =======================

        _isProcessing = false;
    }

    /**
     * ТАКТ СИМУЛЯЦИИ (v3.6).
     * 1. Внедряет отложенные входные сигналы (_pendingInputs).
     * 2. Запускает process() для распространения изменений по схеме.
     * 3. Увеличивает глобальное время.
     */
    public function tick():Void {
        // 1. Внедряем запланированные входы (Кнопки, Генераторы)
        if (_pendingInputs.length > 0) {
            for (task in _pendingInputs) {
                schedule(task, NORMAL);
            }
            _pendingInputs = [];
        }

        // 2. Запускаем распространение сигналов (Logic Flow)
        process();

        // 3. Увеличиваем глобальное время
        time++;
    }

    public function clear():Void {
        for (q in _queuesWrite) if(q != null) q.resize(0);
        for (q in _queuesRead) if(q != null) q.resize(0);
        _pendingInputs = [];
        _isProcessing = false;
        _suspended = false;
        ticksProcessed = 0;
    }

    public static function reset():Void {
        if (_instance != null) {
            _instance.clear();
            _instance = null;
        }
    }
}