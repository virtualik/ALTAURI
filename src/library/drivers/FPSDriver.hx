package library.drivers;

import system.managers.Driver;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * FPS DRIVER v1.0
 * Calculates Frames Per Second based on Delta Time.
 */
class FPSDriver implements Driver {

    public var id(default, null):String;

    private var _targetContact:Contact;
    private var _frames:Int = 0;
    private var _elapsed:Float = 0;
    private var _currentFPS:Float = 0;

    public function new(id:String, targetContact:Contact) {
        this.id = id;
        this._targetContact = targetContact;
    }

    public function init():Void {
        trace('FPS Driver [$id] started.');
    }

    public function update(dt:Float):Void {
        _frames++;
        _elapsed += dt;

        if (_elapsed >= 0.5) {
            _currentFPS = _frames / _elapsed;

            if (_targetContact != null) {
                _targetContact.value = Math.round(_currentFPS);
            }

            _frames = 0;
            _elapsed = 0;
        }
    }

    public function dispose():Void {
        _targetContact = null;
    }
}