package core.logic;

import openfl.events.Event;
import openfl.Lib;

/**
 * TIMEBASE v1.0 (Heartbeat System)
 * Сердце симуляции. Управляет глобальным временем и тактами (MultiPulse).
 * 
 * Работает в двух режимах:
 * 1. Realtime (VSync) - Стандартный. Стремится удержать FPS.
 * 2. Turbo - Максимальная скорость (дляaudio буферов и быстрых расчетов).
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
        
        // 1. Обновляем системный такт
        currentTick++;

        // 2. Запускаем очередь сигналов
        // SignalQueue.process() теперь сам решает, 
        // сколько "тиков" он успеет сделать за frameBudget.
        SignalQueue.getInstance().process();
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