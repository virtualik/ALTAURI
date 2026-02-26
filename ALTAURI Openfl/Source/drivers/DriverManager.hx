package drivers;

import haxe.ds.StringMap;
import openfl.events.Event;

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

    public function register(driver:Driver):Void {
        if (_drivers.exists(driver.id)) return;

        _drivers.set(driver.id, driver);
        driver.init();

        _lastTime = haxe.Timer.stamp();

        if (!_isRunning) {
            openfl.Lib.current.stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
            _isRunning = true;
        }
    }

    public function unregister(id:String):Void {
        var driver = _drivers.get(id);
        if (driver != null) {
            // Не вызываем dispose драйвера здесь, это делает Main.hardReset
            _drivers.remove(id);
        }
    }

    private function onEnterFrame(e:Event):Void {
        // Защита от выполнения, если менеджер уже остановлен
        if (!_isRunning) return;

        var now = haxe.Timer.stamp();
        var dt = now - _lastTime;
        _lastTime = now;

        if (dt > 0.1) dt = 0.1;

        for (driver in _drivers) {
            // Проверка на null на случай удаления во время итерации
            if (driver != null) {
                driver.update(dt);
            }
        }
    }

    // --- НОВЫЙ МЕТОД: Полная остановка ---
    public function dispose():Void {
        if (_isRunning) {
            openfl.Lib.current.stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
            _isRunning = false;
        }

        // Явно уничтожаем все драйверы
        for (driver in _drivers) {
            if (driver != null) driver.dispose();
        }
        
        _drivers = new Map(); // Очищаем список
    }
}