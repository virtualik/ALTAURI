package system.managers;

import system.managers.Driver;

/**
 * DRIVER MANAGER v2.1 (Performance)
 * Manages active drivers (update loops).
 *
 * v2.1 Changes:
 * - Added getDriverCount() for debugging
 * - Safe iteration with copy on update
 */
class DriverManager {

    private static var _instance:DriverManager;

    private var _drivers:Map<String, Driver>;
    private var _driverList:Array<Driver>;  // Cached for fast iteration
    private var _needsRebuild:Bool = false;

    public static function getInstance():DriverManager {
        if (_instance == null) _instance = new DriverManager();
        return _instance;
    }

    private function new() {
        _drivers = new Map();
        _driverList = [];
    }

    public function register(driver:Driver):Void {
        if (_drivers.exists(driver.id)) {
            trace('DriverManager: Driver ${driver.id} already registered');
            return;
        }

        _drivers.set(driver.id, driver);
        _needsRebuild = true;
        
        driver.init();
        trace('DriverManager: Registered ${driver.id}');
    }

    public function unregister(id:String):Void {
        var driver = _drivers.get(id);
        if (driver != null) {
            _drivers.remove(id);
            _needsRebuild = true;
            trace('DriverManager: Unregistered $id');
        }
    }

    /**
     * Main update loop. Called from Main.onMainLoop.
     * @param dt Delta time in seconds.
     */
    public function update(dt:Float):Void {
        // Rebuild list if needed
        if (_needsRebuild) {
            _driverList = [for (d in _drivers) d];
            _needsRebuild = false;
        }

        // Update all drivers
        for (driver in _driverList) {
            if (driver != null) {
                try {
                    driver.update(dt);
                } catch (e:Dynamic) {
                    trace('DriverManager: Error in ${driver.id}: $e');
                }
            }
        }
    }

    /**
     * Get number of registered drivers.
     */
    public function getDriverCount():Int {
        return Lambda.count(_drivers);
    }

    /**
     * Check if a driver is registered.
     */
    public function hasDriver(id:String):Bool {
        return _drivers.exists(id);
    }

    /**
     * Get driver by ID.
     */
    public function getDriver(id:String):Driver {
        return _drivers.get(id);
    }

    /**
     * Clear all drivers.
     */
    public function dispose():Void {
        for (id in _drivers.keys()) {
            var driver = _drivers.get(id);
            if (driver != null) {
                try {
                    driver.dispose();
                } catch (e:Dynamic) {
                    trace('DriverManager: Error disposing $id: $e');
                }
            }
        }
        _drivers.clear();
        _driverList = [];
        _needsRebuild = false;
    }
}
