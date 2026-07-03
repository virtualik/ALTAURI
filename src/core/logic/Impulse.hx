package core.logic;

import core.logic.EventType;

/**
 * IMPULSE v1.1
 *
 * Data container for events.
 * Carries event type and optional payload through Impulsys bus.
 */
class Impulse {
    public var type(default, null): EventType;
    public var data(default, null): Dynamic;

    public function new(type: EventType, data: Dynamic = null) {
        this.type = type;
        this.data = data;
    }
}