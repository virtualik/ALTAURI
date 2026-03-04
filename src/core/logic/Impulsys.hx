package core.logic;

import core.logic.Impulse;

/**
 * IMPULSYS v1.0
 * Static Event Bus for system-wide communication.
 * Decouples UI from Logic.
 */
class Impulsys {

    // Map: Event Type -> Array of Callbacks
    private static var _bus:Map<String, Array<Impulse -> Void>> = new Map();

    /**
     * Subscribe to an event.
     */
    public static function subscribeToImpulse(type:String, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) {
            _bus.set(type, []);
        }
        _bus.get(type).push(callback);
    }

    /**
     * Unsubscribe from an event.
     */
    public static function removeImpulse(type:String, callback:Impulse -> Void):Void {
        if (!_bus.exists(type)) return;

        var list = _bus.get(type);
        list.remove(callback);
    }

    /**
     * Emit an event.
     */
    public static function emit(impulse:Impulse):Void {
        if (!_bus.exists(impulse.type)) return;

        var list = _bus.get(impulse.type);
        for (cb in list) {
            cb(impulse);
        }
    }

    /**
     * Helper to emit quickly without creating Impulse object manually.
     */
    public static function quickEmit(type:String, data:Dynamic = null):Void {
        emit(new Impulse(type, data));
    }

    /**
     * Clear ALL subscriptions.
     */
    public static function clear():Void {
        for (type in _bus.keys()) {
            var list = _bus.get(type);
            if (list != null) list.resize(0);
        }
        _bus.clear();
        _bus = new Map();
    }
}