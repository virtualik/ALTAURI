package core.logic;

/**
 * IMPULSYS v1.3 (Memory Optimization)
 *
 * Static event bus for system-wide communication.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Component A                       Impulsys (Bus)                      │
 * │   ┌─────────────┐                   ┌───────────────┐                   │
 * │   │ quickEmit() │──────────────────►│  _bus:Map     │                   │
 * │   └─────────────┘                   │  (EventType)  │                   │
 * │                                     └───────┬───────┘                   │
 * │                                             │                           │
 * │                                     ┌───────▼───────┐                   │
 * │                                     │  Callbacks[]  │                   │
 * │                                     └───────┬───────┘                   │
 * │                                             │                           │
 * │   Component B                               ▼                           │
 * │   ┌─────────────┐                   ┌───────────────┐                   │
 * │   │ subscribe() │◄──────────────────│  onImpulse()  │                   │
 * │   └─────────────┘                   └───────────────┘                   │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.3 Changes:
 * - removeImpulse now removes empty arrays from the bus
 * - Added getListenerCount() for debugging
 * - Proper cleanup on clear()
 */
class Impulsys {
    private static var _bus: Map<EventType, Array<Impulse -> Void>> = new Map();

    // Counter for debugging
    private static var _totalListeners: Int = 0;

    /**
     * Subscribe to an event type.
     *
     * @param type     Event type to listen for
     * @param callback Function to call when event is emitted
     */
    public static function subscribeToImpulse(type: EventType, callback: Impulse -> Void): Void {
        if (!_bus.exists(type)) {
            _bus.set(type, []);
        }
        var list = _bus.get(type);

        // Protection against duplicates
        if (list.indexOf(callback) == -1) {
            list.push(callback);
            _totalListeners++;
        }
    }

    /**
     * Unsubscribe from an event type.
     *
     * v1.3: Removes callback and clears empty arrays.
     *
     * @param type     Event type
     * @param callback Function to remove
     */
    public static function removeImpulse(type: EventType, callback: Impulse -> Void): Void {
        if (!_bus.exists(type)) return;

        var list = _bus.get(type);
        var removed = list.remove(callback);

        if (removed) {
            _totalListeners--;
        }

        // Remove empty arrays from Map to prevent memory leaks
        if (list.length == 0) {
            _bus.remove(type);
        }
    }

    /**
     * Emit an impulse to all subscribers.
     *
     * @param impulse Impulse containing type and data
     */
    public static function emit(impulse: Impulse): Void {
        if (!_bus.exists(impulse.type)) return;

        // Copy list to protect against modification during iteration
        var list = _bus.get(impulse.type);
        var callbacks = list.copy();

        for (cb in callbacks) {
            if (cb != null) {
                try {
                    cb(impulse);
                } catch (e: Dynamic) {
                    trace('Impulsys: Error in callback for ${impulse.type}: $e');
                }
            }
        }
    }

    /**
     * Quick emit - creates Impulse internally.
     *
     * @param type Event type
     * @param data Optional data payload
     */
    public static function quickEmit(type: EventType, data: Dynamic = null): Void {
        emit(new Impulse(type, data));
    }

    /**
     * Full clear of the bus.
     * Use only during full system reload.
     */
    public static function clear(): Void {
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
     * Get listener count for a specific event type.
     *
     * @param type Event type (null for total count)
     * @return Number of listeners
     */
    public static function getListenerCount(?type: EventType): Int {
        if (type != null) {
            if (!_bus.exists(type)) return 0;
            return _bus.get(type).length;
        }
        return _totalListeners;
    }

    /**
     * Get all event types that have listeners.
     *
     * @return Array of active event types
     */
    public static function getActiveEventTypes(): Array<EventType> {
        return [for (type in _bus.keys()) type];
    }

    /**
     * Debug output of bus state.
     */
    public static function debugPrint(): Void {
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