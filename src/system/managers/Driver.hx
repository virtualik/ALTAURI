package system.managers;

/**
 * Driver Interface v1.0
 * Base interface for all hardware/protocol drivers.
 * 
 * A Driver is an active component that needs regular updates
 * (e.g., signal generators, input devices, monitors).
 */
interface Driver {

    /**
     * Unique ID of the driver instance.
     */
    public var id(default, null):String;

    /**
     * Called once when the driver is registered.
     * Override to perform initialization.
     */
    public function init():Void;

    /**
     * Called periodically (every frame) to poll data or maintain connection.
     * @param dt Delta time in seconds.
     */
    public function update(dt:Float):Void;

    /**
     * Cleanup resources.
     * Called when driver is unregistered or on shutdown.
     */
    public function dispose():Void;
}
