package drivers;

import core.Contact;
import core.Impulsys;
import core.Impulse;

/**
 * MOCK SENSOR DRIVER v1.0
 * Simulates a hardware sensor generating data over time.
 * Demonstrates how to push data into the ALTAURI Core.
 */
class MockSensorDriver implements Driver {
    
    public var id(default, null):String;
    
    private var _targetContact:Contact;
    private var _frequency:Float; // How often to update (seconds)
    private var _timer:Float = 0;
    
    public function new(id:String, targetContact:Contact, frequency:Float = 1.0) {
        this.id = id;
        this._targetContact = targetContact;
        this._frequency = frequency;
    }
    
    public function init():Void {
        trace('Driver [$id] initialized. Sending data to Contact: ${_targetContact.name}');
    }
    
    public function update(dt:Float):Void {
        _timer += dt;
        
        if (_timer >= _frequency) {
            _timer = 0;
            
            // --- SIMULATION LOGIC ---
            // In a real driver (e.g., MQTT), we would check for new messages here.
            // For Mock, we generate a random number.
            
            var value = Math.random() * 100; // 0..100 range
            
            // PUSH DATA INTO CORE
            // This triggers the Cascade Mutation!
            if (_targetContact != null) {
                _targetContact.value = value;
            }
        }
    }
    
    public function dispose():Void {
        _targetContact = null;
    }
}