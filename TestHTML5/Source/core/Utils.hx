package core;

class Utils {
    // WARNING: Setting this to 2 million allows testing huge chains 
    // but risks Stack Overflow crashes.
    public static var MAX_SIGNAL_DEPTH:Int = 2000000; 
    
    private static var _currentDepth:Int = 0;

    public static function enterDepth():Bool {
        _currentDepth++;
        if (_currentDepth > MAX_SIGNAL_DEPTH) {
            trace('ERROR: Signal Depth Overflow!');
            return false; 
        }
        return true; 
    }

    public static function exitDepth():Void {
        _currentDepth--;
    }
    
    public static function resetDepth():Void {
        _currentDepth = 0;
    }
}