package core.logic;

import core.types.Priority;

/**
 * SIGNAL QUEUE v3.5 (Metrics & Speed Control)
 * Добавлен счетчик тиков и возможность ограничения скорости.
 *
 * v3.5 Changes:
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
 * Как управлять скоростью
 * 1. Нормальная скорость:
 * SignalQueue.getInstance().slowMotion = false;
 * SignalQueue.getInstance().maxTicksPerFrame = 0; // Без лимита
 *  ->Будет крутить столько тактов, сколько успеет за 10 мс.
 * 
 * 2. Slow Motion (Отладка):
 * SignalQueue.getInstance().slowMotion = true;
 *  ->Будет делать ровно 1 тик за кадр. Вы увидите, как сигнал бежит по проводам.
 * 
 * 3. Фиксированная скорость:
 * SignalQueue.getInstance().maxTicksPerFrame = 100; //Ограничить 100 тактами логики за кадр.
 * 
 * Теперь я точно знаю производительность моей системы. 
 * Если ticksProcessed показывает 5000 — значит логика "улетела" далеко вперёд реального времени.
 * Если 1 — значит система тяжелая или включен слоу-мо.
 * 
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
    }

    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        var queue = _queuesWrite.get(priority);
        if (queue != null) {
            queue.push(task);
        }

        if (!_isProcessing && !_suspended) {
            process();
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

    public function clear():Void {
        for (q in _queuesWrite) if(q != null) q.resize(0);
        for (q in _queuesRead) if(q != null) q.resize(0);
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