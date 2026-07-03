package system.managers;

import system.managers.Driver;

/**
 * DRIVER MANAGER v2.1 (Performance)
 * Manages active drivers (update loops).
 * Part of the COMPUTE LAYER in "Atom is Databank & Compute Core" architecture.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DriverManager (Compute Layer)                                         │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Main Loop:                                                     │   │
 * │   │  ┌───────────────────────────────────────────────────────────┐  │   │
 * │   │  │  onEnterFrame() {                                         │  │   │
 * │   │  │      var dt = calculateDelta();                           │  │   │
 * │   │  │      DriverManager.update(dt);  // Update active atoms    │  │   │
 * │   │  │      SignalQueue.process();     // Propagate signals      │  │   │
 * │   │  │  }                                                        │  │   │
 * │   │  └───────────────────────────────────────────────────────────┘  │   │
 * │   │                                                                 │   │
 * │   │  Active Atoms (Drivers):                                        │   │
 * │   │  - SignalGenerator:      multi-mode signal generator            │   │
 * │   │  - MiniAudioAtom:        captures microphone/loopback data      │   │
 * │   │  - ComPortAtom:          serial port communication              │   │
 * │   │  - ComEnumeratorAtom:    scans registry for COM ports           │   │
 * │   │  - SystemVUMeterAtom:    WASAPI audio level monitoring          │   │
 * │   │  - OscilloscopeAtom:     time-based signal sampling             │   │
 * │   │                                                                 │   │
 * │   │  Passive Atoms (NOT Drivers):                                   │   │
 * │   │  - LedAtom:       displays input signal                         │   │
 * │   │  - ButtonAtom:    provides output on interaction                │   │
 * │   │  - ToggleAtom:    maintains state between interactions          │   │
 * │   │  - RelayAtom:     passes signal when control is active          │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   v2.1 Changes:                                                         │
 * │   - Added getDriverCount() for debugging                                │
 * │   - Safe iteration with copy on update                                  │
 * │   - Cached _driverList for fast iteration                               │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DriverManager
{
    // =========================================================================
    // SINGLETON
    // =========================================================================
    private static var _instance:DriverManager;
    
    // =========================================================================
    // STATE
    // =========================================================================
    private var _drivers:Map<String, Driver>;
    private var _driverList:Array<Driver>;  // Cached for fast iteration
    private var _needsRebuild:Bool = false;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public static function getInstance():DriverManager
    {
        if (_instance == null) _instance = new DriverManager();
        return _instance;
    }
    
    private function new()
    {
        _drivers = new Map();
        _driverList = [];
    }
    
    // =========================================================================
    // REGISTRATION
    // =========================================================================
    /**
     * Register a driver for periodic updates.
     * Calls driver.init() immediately.
     * 
     * @param driver Driver instance to register
     */
    public function register(driver:Driver):Void
    {
        if (_drivers.exists(driver.id))
        {
            trace('DriverManager: Driver ${driver.id} already registered');
            return;
        }
        
        _drivers.set(driver.id, driver);
        _needsRebuild = true;
        driver.init();
        
        trace('DriverManager: Registered ${driver.id}');
    }
    
    /**
     * Unregister a driver.
     * Does NOT call dispose() - caller is responsible for cleanup.
     * 
     * @param id Driver ID to unregister
     */
    public function unregister(id:String):Void
    {
        var driver = _drivers.get(id);
        if (driver != null)
        {
            _drivers.remove(id);
            _needsRebuild = true;
            trace('DriverManager: Unregistered $id');
        }
    }
    
    // =========================================================================
    // UPDATE LOOP
    // =========================================================================
    /**
     * Main update loop. Called from Main.onMainLoop.
     * Updates all registered drivers with delta time.
     * 
     * @param dt Delta time in seconds.
     */
    public function update(dt:Float):Void
    {
        // Rebuild cached list if drivers were added/removed
        if (_needsRebuild)
        {
            _driverList = [for (d in _drivers) d];
            _needsRebuild = false;
        }
        
        // Update all drivers
        for (driver in _driverList)
        {
            if (driver != null)
            {
                try
                {
                    driver.update(dt);
                }
                catch (e:Dynamic)
                {
                    trace('DriverManager: Error in ${driver.id}: $e');
                }
            }
        }
    }
    
    // =========================================================================
    // QUERY API
    // =========================================================================
    /**
     * Get number of registered drivers.
     */
    public function getDriverCount():Int
    {
        var count = 0;
        for (key in _drivers.keys()) count++;
        return count;
    }
    
    /**
     * Check if a driver is registered.
     */
    public function hasDriver(id:String):Bool
    {
        return _drivers.exists(id);
    }
    
    /**
     * Get driver by ID.
     */
    public function getDriver(id:String):Driver
    {
        return _drivers.get(id);
    }
    
    // =========================================================================
    // CLEANUP
    // =========================================================================
    /**
     * Dispose all drivers and clear registry.
     * Called on application shutdown or hard reset.
     */
    public function dispose():Void
    {
        for (id in _drivers.keys())
        {
            var driver = _drivers.get(id);
            if (driver != null)
            {
                try
                {
                    driver.dispose();
                }
                catch (e:Dynamic)
                {
                    trace('DriverManager: Error disposing $id: $e');
                }
            }
        }
        
        _drivers.clear();
        _driverList = [];
        _needsRebuild = false;
    }
    
    /**
     * Reset singleton instance.
     * Used for testing or hard reset.
     */
    public static function reset():Void
    {
        if (_instance != null)
        {
            _instance.dispose();
            _instance = null;
        }
    }
}