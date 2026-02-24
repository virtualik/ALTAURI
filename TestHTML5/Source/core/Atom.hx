package core;

import core.Utils;

/**
 * ATOM v3.5
 * Functional node implementing IDisposable.
 */
class Atom implements IDisposable {
    public var id(default, null):String;
    public var type(default, null):String;
    public var name(default, null):String;

    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;
    private var _process:Array<Dynamic> -> Array<Dynamic>;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic"
    ) {
        this.id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;

        this._inputs = inputs;
        this._outputs = outputs;
        this._process = processFunc;

        _bind();
    }

    private function _bind():Void {
        for (input in _inputs) {
            input.subscribe(_onInputChange);
        }
    }

    private function _onInputChange(_:Dynamic):Void {
        if (_process == null) return;

        var values = [for (i in _inputs) i.value];
        var results = _process(values);

        if (results != null && results.length == _outputs.length) {
            for (i in 0..._outputs.length) {
                _outputs[i].value = results[i];
            }
        }
    }

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    // --- NEW: Helper methods to fix the crash ---
    
    public function getInput(name:String):Contact {
        for (c in _inputs) {
            if (c.name == name) return c;
        }
        return null;
    }

    public function getOutput(name:String):Contact {
        for (c in _outputs) {
            if (c.name == name) return c;
        }
        return null;
    }

    // -------------------------------------------

    public function dispose():Void {
        for (c in _inputs) c.dispose();
        for (c in _outputs) c.dispose();

        _inputs = null;
        _outputs = null;
        _process = null;
    }
}