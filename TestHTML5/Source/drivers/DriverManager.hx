package drivers;

import haxe.ds.StringMap;
import openfl.events.Event;

/**
 * DRIVER MANAGER v1.0
 * Singleton that manages all active drivers.
 * Ticks them every frame.
 */
class DriverManager {
    
    private static var _instance:DriverManager;
    
    private var _drivers:Map<String, Driver>;
    private var _isRunning:Bool = false;
    private var _lastTime:Float = 0;
	
    public static function getInstance():DriverManager {
        if (_instance == null) _instance = new DriverManager();
        return _instance;
    }

    private function new() {
        _drivers = new Map();
    }
    
    /**
     * Register a driver instance.
     */
    public function register(driver:Driver):Void {
        if (_drivers.exists(driver.id)) return;
        
        _drivers.set(driver.id, driver);
        driver.init();
        
		_lastTime = haxe.Timer.stamp();
		
        // Start ticking if not already
        if (!_isRunning) {
            openfl.Lib.current.stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
            _isRunning = true;
        }
    }
    
    /**
     * Unregister and dispose a driver.
     */
    public function unregister(id:String):Void {
        var driver = _drivers.get(id);
        if (driver != null) {
            driver.dispose();
            _drivers.remove(id);
        }
    }
    
    /**
     * Main Loop.
     */
	private function onEnterFrame(e:Event):Void {
        // Calculate real dt
        var now = haxe.Timer.stamp();
        var dt = now - _lastTime;
        _lastTime = now;
        
        // Limit dt to avoid spikes when tab was inactive
        if (dt > 0.1) dt = 0.1; 

        for (driver in _drivers) {
            driver.update(dt);
        }
    }

    public function dispose():Void {
        if (_isRunning) {
            openfl.Lib.current.stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
            _isRunning = false;
        }
        
        for (driver in _drivers) {
            driver.dispose();
        }
        _drivers = new Map();
    }
}