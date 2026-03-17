package core.logic;

/**
 * IMPULSE v1.1
 * Контейнер данных для событий.
 */
class Impulse {
    public var type(default, null):EventType;
    public var data(default, null):Dynamic;

    public function new(type:EventType, data:Dynamic = null) {
        this.type = type;
        this.data = data;
    }
}