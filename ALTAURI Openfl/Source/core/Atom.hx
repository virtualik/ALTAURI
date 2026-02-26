package core;

import core.Utils;
import drivers.Driver;
import drivers.DriverManager;
import core.SignalQueue.Priority;

class Atom implements IDisposable implements Driver {

    public var id(default, null):String;
    public var type(default, null):String;
    public var name(default, null):String;

    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;
    private var _process:Array<Dynamic> -> Array<Dynamic>;

    private var _inputCache:Array<Dynamic>;
    private var _isScheduled:Bool = false;
    private var _isActive:Bool = false;
    private var _isDisposed:Bool = false;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic",
        ?isActive:Bool = false
    ) {
        this.id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;
        this._isActive = isActive;

        this._inputs = inputs;
        this._outputs = outputs;
        this._process = processFunc;

        _inputCache = [];
        if (_inputs != null) {
            for(i in 0..._inputs.length) _inputCache.push(null);
        }

        _bind();

        if (_isActive) {
            DriverManager.getInstance().register(this);
        }
    }

    private function _bind():Void {
        if (_inputs == null) return;
        for (input in _inputs) {
            input.owner = this;
        }
    }

    public function init():Void { }

    public function update(dt:Float):Void {
        _onUpdate(dt);
    }

    private function _onUpdate(dt:Float):Void { }

    public function onContactChanged(c:Contact):Void {
        if (_isScheduled || _isDisposed) return;
        _isScheduled = true;
        SignalQueue.getInstance().schedule(_calculate, NORMAL);
    }

    private function _calculate():Void {
        _isScheduled = false;

        // --- ЗАЩИТА: Если атом уничтожен или нет логики ---
        if (_isDisposed || _process == null || _inputs == null) return;

        for (i in 0..._inputs.length) _inputCache[i] = _inputs[i].value;
        
        var results = _process(_inputCache);

        if (results != null && results.length == _outputs.length) {
            for (i in 0..._outputs.length) {
                if (_outputs[i] != null) _outputs[i].value = results[i];
            }
        }
    }

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact {
        if (_inputs == null) return null;
        for (c in _inputs) if (c.name == name) return c;
        return null;
    }

    public function getOutput(name:String):Contact {
        if (_outputs == null) return null;
        for (c in _outputs) if (c.name == name) return c;
        return null;
    }

    public function dispose():Void {
        _isDisposed = true;

        if (_isActive) {
            DriverManager.getInstance().unregister(this.id);
        }

        if (_inputs != null) for (c in _inputs) c.dispose();
        if (_outputs != null) for (c in _outputs) c.dispose();

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}