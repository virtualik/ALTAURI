package library.drivers;

import system.managers.Driver;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * MOCK SENSOR DRIVER v1.0
 * Simulates a hardware sensor generating data over time.
 * Demonstrates how to push data into the Core.
 */
class MockSensorDriver implements Driver {

    public var id(default, null):String;

    private var _targetContact:Contact;
    private var _frequency:Float; 
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

            // Simulation Logic
            var value = Math.random() * 100; 

            // PUSH DATA INTO CORE
            if (_targetContact != null) {
                _targetContact.value = value;
            }
        }
    }

    public function dispose():Void {
        _targetContact = null;
    }
}