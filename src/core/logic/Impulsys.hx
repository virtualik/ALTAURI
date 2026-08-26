package core.logic;

/**
 * IMPULSYS v1.4 (Memory Optimization + Reliability Layer)
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
 * DISPOSE CONTRACT (implicit since v3.0):
 *   Every component that calls subscribeToImpulse() in its constructor MUST
 *   call removeImpulse() with the SAME function reference in its dispose().
 *   Clients should keep the exact closure references they subscribed with
 *   (see NodeEditor.hx:289-290 for the canonical pattern) so removeImpulse()
 *   can unsubscribe the identical function pointer.
 *
 * POST-CLEAR CONTRACT:
 *   clear() is a blunt instrument — it wipes ALL subscriptions system-wide
 *   and is invoked only from Main.hx during "soft restart". After clear(),
 *   every subscriber that should remain live MUST be re-subscribed explicitly
 *   (see Main.hx:2430-2446). Components whose owners are NOT recreated after
 *   clear() will silently lose reactivity.
 *
 * v1.4 Changes (Episod F-lite):
 * - Added null guards to subscribeToImpulse() and emit() (rejected silently,
 *   traced under -debug)
 * - Added public static onError hook: when set, emit() routes callback
 *   exceptions to onError(e, impulse) instead of bare trace. Defaults to null
 *   (legacy trace behavior preserved).
 * - Simplified clear(): removed redundant list.resize(0) loop and redundant
 *   _bus = new Map() reassignment. Map.clear() is sufficient.
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
     * v1.4: External error hook for emit() try/catch.
     * Set in Main once during initialization; emit() calls it on callback
     * exception instead of bare trace(). null -> legacy trace behavior.
     * Signature: (error: Dynamic, impulse: Impulse) -> Void
     */
    public static var onError: Dynamic -> Impulse -> Void = null;

    /**
     * Subscribe to an event type.
     *
     * @param type     Event type to listen for
     * @param callback Function to call when event is emitted
     */
    public static function subscribeToImpulse(type: EventType, callback: Impulse -> Void): Void {
        // v1.4: Null guard — reject silently to keep null keys out of the Map.
        if (type == null || callback == null) {
            #if debug
            trace('Impulsys.subscribeToImpulse: rejected null argument (type=$type, callback=$callback)');
            #end
            return;
        }
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
        // v1.4: Null guard — reject null impulse / null type early.
        if (impulse == null || impulse.type == null) {
            #if debug
            trace('Impulsys.emit: rejected null impulse or impulse.type');
            #end
            return;
        }
        if (!_bus.exists(impulse.type)) return;

        // Copy list to protect against modification during iteration
        var list = _bus.get(impulse.type);
        var callbacks = list.copy();

        for (cb in callbacks) {
            if (cb != null) {
                try {
                    cb(impulse);
                } catch (e: Dynamic) {
                    // v1.4: route to onError hook if set, else legacy trace.
                    if (onError != null) {
                        onError(e, impulse);
                    } else {
                        trace('Impulsys: Error in callback for ${impulse.type}: $e');
                    }
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
     *
     * v1.4: Simplified — Map.clear() is sufficient; no need to resize each
     * array first (they will be GC'd with the Map), and no need to reassign
     * _bus to a new Map() (clear() already empties the existing Map).
     */
    public static function clear(): Void {
        _bus.clear();
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
