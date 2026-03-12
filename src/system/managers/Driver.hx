package system.managers;

/**
 * Driver Interface v1.0
 * Base interface for all hardware/protocol drivers.
 */
interface Driver {

    /**
     * Unique ID of the driver instance.
     */
    public var id(default, null):String;

    /**
     * Called once when the driver is registered.
     */
    public function init():Void;

    /**
     * Called periodically (e.g., every frame or tick) to poll data or maintain connection.
     * @param dt Delta time in seconds.
     */
    public function update(dt:Float):Void;

    /**
     * Cleanup resources.
     */
    public function dispose():Void;
}
