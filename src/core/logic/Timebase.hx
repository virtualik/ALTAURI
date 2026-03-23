package core.logic;

/**
 * TIMEBASE v1.1 (Heartbeat System)
 * Сердце симуляции. Управляет глобальным временем и тактами (MultiPulse).
 * 
 * Работает в двух режимах:
 * 1. Realtime (VSync) - Стандартный. Стремится удержать FPS.
 * 2. Turbo - Максимальная скорость (дляaudio буферов и быстрых расчетов).
 * 
 * Гибридный подход: 
 * Система уникальна тем, что совмещает в себе оба мира.
 * 
 * Как это работает:
 * Внешний мир (Кнопки, Генераторы, UI): Работают по "Тактовой" модели.
 * Они планируют изменение, но оно вступает в силу только в начале следующего такта. Это дисциплинирует входные данные. 
 * Внутренняя логика (Провода, NAND): Работает по модели "Dataflow" (мгновенно внутри такта).
 * Почему так? Потому что за один такт сигнал должен успеть пройти через все вентили от входа к выходу.
 * Это моделирует Propagation Delay (задержку распространения) реальной электроники.
 * Итог:
 * Текущая система Dataflow лучше подходит для "Живых" приборов (Осциллограф, Аудио, UI анимации).
 * Digital Simulator лучше для Вычислительных устройств (Процессоры, Автоматы, Память).
 * 
 * Стабильность цифровой логики (такты) и скорость отклика интерфейса (мгновенный propagation внутри такта).
 * Это "золотая середина".
 * 
 * * v1.1 Changes:
 * - Calls SignalQueue.tick() instead of process() to drive the simulation clock.
 */
class Timebase {

    private static var _instance:Timebase;

    public static function getInstance():Timebase {
        if (_instance == null) _instance = new Timebase();
        return _instance;
    }

    // =====================================================================
    // CONFIGURATION
    // =====================================================================

    /** Бюджет времени на 1 кадр (10ms). Если обработка займет больше - фриз. */
    public var frameBudget:Float = 0.010;

    /** Целевая частота тиков в секунду (для аудио/логики). */
    public var targetTickRate:Int = 44100;

    /** Текущий глобальный такт (счетчик импульсов). */
    public var currentTick(default, null):Int = 0;

    /** Время старта текущего кадра (для профилирования). */
    public var frameStartTime(default, null):Float = 0.0;

    private function new() { }

    // =====================================================================
    // PULSE DRIVER
    // =====================================================================

    /**
     * Запускает обработку тиков на один кадр.
     * Вызывается из Main.onMainLoop.
     */
    public function updateFrame():Void {
        frameStartTime = haxe.Timer.stamp();

        // 1. Обновляем системный такт (визуальный счетчик)
        currentTick++;

        // 2. Запускаем ТАКТ СИМУЛЯЦИИ (Logic Clock)
        // tick() внутри сам вызовет process() и продвинет время в SignalQueue.
        SignalQueue.getInstance().tick();
    }

    /**
     * Получить прошедшее время с начала кадра (в секундах).
     */
    public function getElapsed():Float {
        return haxe.Timer.stamp() - frameStartTime;
    }

    /**
     * Проверка на перегрузку (если кадр занял больше budget).
     */
    public function isOverBudget():Bool {
        return getElapsed() > frameBudget;
    }
}