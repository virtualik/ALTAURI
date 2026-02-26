package core;

// --- Выносим Enum на уровень пакета (стандарт Haxe) ---
enum Priority {
    CRITICAL;   // Ввод пользователя, драйверы
    NORMAL;     // Логика по умолчанию
    BACKGROUND; // Визуализация, логи
}

/**
 * SIGNAL QUEUE v2.0
 * Priority-based Task Scheduler.
 */
class SignalQueue {

    private static var _instance:SignalQueue;
    
    // Хранилище очередей
    private var _queues:Map<Priority, Array<Void -> Void>>;
    
    private var _isProcessing:Bool = false;
    
    // Защита от "Zombie Loops"
    private var _currentIteration:Int = 0;
    public var maxIterationsPerFrame:Int = 10000; 

    public static function getInstance():SignalQueue {
        if (_instance == null) _instance = new SignalQueue();
        return _instance;
    }

    private function new() {
        _queues = new Map();
        // Инициализация очередей
        _queues.set(CRITICAL, []);
        _queues.set(NORMAL, []);
        _queues.set(BACKGROUND, []);
    }

    /**
     * Добавляет задачу в очередь.
     */
    public function schedule(task:Void -> Void, priority:Priority = NORMAL):Void {
        _queues.get(priority).push(task);
        
        if (!_isProcessing) {
            process();
        }
    }

    /**
     * Итеративная обработка.
     */
    private function process():Void {
        _isProcessing = true;
        _currentIteration = 0;

        // Порядок обработки: Critical -> Normal -> Background
        var order:Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];

        for (p in order) {
            var queue = _queues.get(p);
            
            while (queue.length > 0) {
                // Защита от переполнения
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

    // Метод проверки загрузки ---
    
    /**
     * Возвращает true, если очередь перегружена (прошли >80% лимита).
     * Используйте это в "тяжелых" атомах для отложенного выполнения.
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