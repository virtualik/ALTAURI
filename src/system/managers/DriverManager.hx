package system.managers;

import system.managers.Driver;

/**
 * DRIVER MANAGER v2.0
 * Manages active drivers (update loops).
 */
class DriverManager {

    private static var _instance:DriverManager;

    private var _drivers:Map<String, Driver>;

    public static function getInstance():DriverManager {
        if (_instance == null) _instance = new DriverManager();
        return _instance;
    }

    private function new() {
        _drivers = new Map();
    }

    public function register(driver:Driver):Void {
        if (_drivers.exists(driver.id)) return;

        _drivers.set(driver.id, driver);
        driver.init();
    }

    public function unregister(id:String):Void {
        var driver = _drivers.get(id);
        if (driver != null) {
            _drivers.remove(id);
        }
    }

    /**
     * Main update loop. Called from Main.onMainLoop.
     * @param dt Delta time in seconds.
     */
    public function update(dt:Float):Void {
        for (driver in _drivers) {
            if (driver != null) {
                driver.update(dt);
            }
        }
    }

    public function dispose():Void {
        _drivers = new Map();
    }
}
