package core.logic;

import core.logic.EventType;

/**
 * IMPULSYS v1.3 (Memory Optimization)
 * Статическая шина событий (Event Bus).
 *
 * v1.3 Changes:
 * - removeImpulse now removes empty arrays from the bus
 * - Added getListenerCount() for debugging
 * - Proper cleanup on clear()
 */
class Impulsys {

    private static var _bus:Map<EventType, Array<Impulse -> Void>> = new Map();

    // Счётчик для отладки
    private static var _totalListeners:Int = 0;

    public static function subscribeToImpulse(type:EventType, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) {
            _bus.set(type, []);
        }
        var list = _bus.get(type);

        // Защита от дублирования
        if (list.indexOf(callback) == -1) {
            list.push(callback);
            _totalListeners++;
        }
    }

    /**
     * v1.3: Удаляет callback и очищает пустые массивы.
     */
    public static function removeImpulse(type:EventType, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) return;

        var list = _bus.get(type);
        var removed = list.remove(callback);

        if (removed) {
            _totalListeners--;
        }

        // FIX: Удалять пустые массивы из Map
        if (list.length == 0) {
            _bus.remove(type);
        }
    }

    public static function emit(impulse:Impulse):Void {
        if (!_bus.exists(impulse.type)) return;

        // Копируем список для защиты от модификации во время итерации
        var list = _bus.get(impulse.type);
        var callbacks = list.copy();

        for (cb in callbacks) {
            if (cb != null) {
                try {
                    cb(impulse);
                } catch (e:Dynamic) {
                    trace('Impulsys: Error in callback for ${impulse.type}: $e');
                }
            }
        }
    }

    public static function quickEmit(type:EventType, data:Dynamic = null):Void {
        emit(new Impulse(type, data));
    }

    /**
     * Полная очистка шины.
     * Использовать только при полной перезагрузке системы.
     */
    public static function clear():Void {
        for (type in _bus.keys()) {
            var list = _bus.get(type);
            if (list != null) {
                list.resize(0);
            }
        }
        _bus.clear();
        _bus = new Map();
        _totalListeners = 0;
    }

    /**
     * Получить количество слушателей для типа события.
     */
    public static function getListenerCount(?type:EventType):Int {
        if (type != null) {
            if (!_bus.exists(type)) return 0;
            return _bus.get(type).length;
        }
        return _totalListeners;
    }

    /**
     * Получить все типы событий, имеющие слушателей.
     */
    public static function getActiveEventTypes():Array<EventType> {
        return [for (type in _bus.keys()) type];
    }

    /**
     * Отладочный вывод состояния шины.
     */
    public static function debugPrint():Void {
        trace('=== Impulsys Debug ===');
        trace('Total listeners: $_totalListeners');
        trace('Active event types: ${Lambda.count(_bus)}');
        for (type in _bus.keys()) {
            var count = _bus.get(type).length;
            trace('  $type: $count listeners');
        }
        trace('======================');
    }
}
