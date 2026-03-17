package core.logic;

/**
 * IMPULSYS v1.1
 * Статическая шина событий (Event Bus).
 */
class Impulsys {

    private static var _bus:Map<EventType, Array<Impulse -> Void>> = new Map();

    public static function subscribeToImpulse(type:EventType, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) {
            _bus.set(type, []);
        }
        _bus.get(type).push(callback);
    }

    public static function removeImpulse(type:EventType, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) return;
        var list = _bus.get(type);
        list.remove(callback);
    }

    public static function emit(impulse:Impulse):Void {
        if (!_bus.exists(impulse.type)) return;
        var list = _bus.get(impulse.type);
        for (cb in list) {
            cb(impulse);
        }
    }

    public static function quickEmit(type:EventType, data:Dynamic = null):Void {
        emit(new Impulse(type, data));
    }

    public static function clear():Void {
        for (type in _bus.keys()) {
            var list = _bus.get(type);
            if (list != null) list.resize(0);
        }
        _bus.clear();
        _bus = new Map();
    }
}