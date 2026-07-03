package system.managers;

/**
 * Driver Interface v1.0
 * Base interface for all hardware/protocol drivers.
 *
 * A Driver is an active component that needs regular updates
 * (e.g., signal generators, input devices, monitors).
 *
 * In the "Atom is Databank & Compute Core" architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Driver extends Atom                                                   │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │      - update(dt) is called every frame by DriverManager                │
 * │      - Performs time-based calculations                                 │
 * │      - Example: SignalGenerator calculates next sample                  │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │      - Stores generated data (frequency, phase, buffer)                 │
 * │      - getPersistentState() saves the state                             │
 * │                                                                         │
 * │   В) FACE:                                                              │
 * │      - DeviceView shows the generator's output                          │
 * │      - DeviceViewRegistry manages the single instance                   │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
interface Driver
{
    /**
     * Unique ID of the driver instance.
     */
    public var id(get, never):String;
    
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

/**
 * Planned drivers for future implementation:
 *
 * - TextFeild
 * - TextArea
 * - InputText
 * - PushButton
 * - ToggleButton
 * - RadioButton
 * - CheckBox
 *
 * - Keyboard
 * - Mouse
 * - COMPORT
 * - NetConnect
 */