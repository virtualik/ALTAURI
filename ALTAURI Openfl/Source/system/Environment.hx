package system;

/**
 * ENVIRONMENT v1.0
 * Defines the execution context (Editor vs Device vs Server).
 * This is where hardware abstraction or system calls live.
 */
class Environment {

    private static var _instance:Environment;

    public static function getInstance():Environment {
        if (_instance == null) _instance = new Environment();
        return _instance;
    }

    private function new() {}

    // Future: GPIO, Network, File system wrappers
    public function getSystemTime():Float {
        return Sys.time(); // Or Date.now().getTime() depending on target
    }

    public function log(msg:String):Void {
        trace("[ENV] " + msg);
    }
}