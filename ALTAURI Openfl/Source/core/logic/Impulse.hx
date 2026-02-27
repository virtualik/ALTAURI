package core.logic;

/**
 * IMPULSE v1.0
 * A data container for events traveling through the Impulsys bus.
 */
class Impulse {
    public var type(default, null):String;
    public var data(default, null):Dynamic;

    public function new(type:String, data:Dynamic = null) {
        this.type = type;
        this.data = data;
    }
}