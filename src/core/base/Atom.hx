package core.base;

import core.logic.TickGenerator;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ATOM BASE CLASS v7.0 (Correctness & Thread Safety Pass)
 * Fundamental unit of logic. Independent of rendering engine.
 *
 * v7.0 Changes:
 * - FIXED: _isDisposed помечен как @:volatile.
 *   Это критически важно для драйверов (например MiniAudioAtom).
 *   Аудио-поток ОС проверяет _isDisposed в callback. Без @:volatile
 *   компилятор C++ может закэшировать значение в регистре аудио-потока,
 *   и после вызова dispose() в главном потоке, аудио-поток продолжит
 *   выполнение с "устаревшим" (false) значением флага.
 *
 * v6.9 Changes:
 * - FIXED: restoreState() isLogic condition was inverted.
 * - IMPROVED: _bind() guard clauses made consistent.
 */
class Atom implements IDisposable implements Driver
{

    public var id(get, never):String;
    private function get_id():String return _id;
    private var _id:String;

    public var type(default, null):String;
    public var name(default, null):String;

    /**
     * Determines the timing model for this atom.
     * ┌────────────────┬────────────────────────────────────────────────┐
     * │ Value          │ Behavior                                       │
     * ├────────────────┼────────────────────────────────────────────────┤
     * │ true (Digital) │ Output changes are scheduled for the NEXT tick │
     * │ false (Analog) │ Output changes happen IMMEDIATELY              │
     * └────────────────┴────────────────────────────────────────────────┘
     */
    public var isLogic(get, set):Bool;
    private var _isLogic:Bool = false;

    private function get_isLogic():Bool return _isLogic;

    private function set_isLogic(value:Bool):Bool
    {
        _isLogic = value;
        return _isLogic;
    }

    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;

    private var _process:Array<Dynamic> -> Array<Dynamic>;
    private var _inputCache:Array<Dynamic>;

    private var _isScheduled:Bool = false;
    private var _isActive:Bool = false;
    
    // v7.0: @:volatile заставляет процессор всегда читать из RAM,
    // а не из кэша регистра потока.
    @:volatile private var _isDisposed:Bool = false;
    
    private var _hasCalculatedOnce:Bool = false;

    // =========================================================================
    // ИНИЦИАЛИЗАЦИЯ v7.0
    // =========================================================================

    public var isInitializing(get, set):Bool;
    private var _isInitializing:Bool = false;

    private function get_isInitializing():Bool return _isInitializing;
    private function set_isInitializing(value:Bool):Bool
    {
        _isInitializing = value;
        return _isInitializing;
    }

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic",
        ?isActive:Bool = false
    )
    {
        this._id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;
        this._isActive = isActive;
        this._inputs = (inputs != null) ? inputs : [];
        this._outputs = (outputs != null) ? outputs : [];
        this._process = processFunc;
        _inputCache = [];
        for (i in 0..._inputs.length) _inputCache.push(null);
        _bind();

        var tg = TickGenerator.getInstance();

        var isAssemblyWithInternal = Std.isOfType(this, Assembly) &&
                                     cast(this, Assembly).blueprint != null &&
                                     cast(this, Assembly).blueprint.internalAtoms != null &&
                                     cast(this, Assembly).blueprint.internalAtoms.length > 0;

        if (_process != null && !isAssemblyWithInternal && !tg.isSuspended())
        {
            _isScheduled = true;
            TickGenerator.getInstance().scheduleNextTick(function()
            {
                if (!_isDisposed) _calculate();
            });
        }

        if (_isActive)
        {
            DriverManager.getInstance().register(this);
        }
    }

    private function _bind():Void
    {
        for (input in _inputs)
        {
            if (input != null) input.owner = this;
        }
        for (output in _outputs)
        {
            if (output != null) output.owner = this;
        }
    }

    public function init():Void { }

    public function update(dt:Float):Void
    {
        _onUpdate(dt);
    }

    private function _onUpdate(dt:Float):Void { }

    public function onContactChanged(c:Contact):Void
    {
        if (_isScheduled || _isDisposed) return;
        if (isInitializing) return;

        if (c.type == OUTPUT && c.owner == this) return;

        if (_process != null)
        {
            _isScheduled = true;
            TickGenerator.getInstance().schedule(_calculate, NORMAL);
        }
    }

    private function _calculate():Void
    {
        _isScheduled = false;
        _hasCalculatedOnce = true;

        if (_isDisposed || _process == null || _inputs == null) return;

        for (i in 0..._inputs.length) _inputCache[i] = _inputs[i].value;

        var results = _process(_inputCache);

        if (results != null && results.length == _outputs.length)
        {
            if (isLogic)
            {
                var outs = _outputs;
                var vals = results;
                TickGenerator.getInstance().scheduleNextTick(function()
                {
                    if (_isDisposed) return;
                    for (i in 0...outs.length)
                    {
                        if (outs[i] != null) outs[i].value = vals[i];
                    }
                });
            }
            else
            {
                for (i in 0..._outputs.length)
                {
                    if (_outputs[i] != null) _outputs[i].value = results[i];
                }
            }
        }
    }

    public function forceCalculate():Void
    {
        if (_isDisposed || _process == null || _inputs == null) return;
        _calculate();
    }

    public function getPersistentState():Dynamic
    {
        if (_isLogic) return { isLogic: true };
        return null;
    }

    public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        if (Reflect.hasField(state, "isLogic")) this.isLogic = state.isLogic;
    }

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact
    {
        if (_inputs == null) return null;
        for (c in _inputs) if (c != null && c.name == name) return c;
        return null;
    }

    public function getOutput(name:String):Contact
    {
        if (_outputs == null) return null;
        for (c in _outputs) if (c != null && c.name == name) return c;
        return null;
    }

    public function getInputNames():Array<String>
    {
        var names:Array<String> = [];
        for (c in _inputs) if (c != null && c.name != null) names.push(c.name);
        return names;
    }

    public function getOutputNames():Array<String>
    {
        var names:Array<String> = [];
        for (c in _outputs) if (c != null && c.name != null) names.push(c.name);
        return names;
    }

    public function dispose():Void
    {
        _isDisposed = true; // v7.0: @:volatile гарантирует видимость в Audio Thread

        if (_isActive) DriverManager.getInstance().unregister(this.id);

        if (_inputs != null) { for (c in _inputs) { if (c != null) c.dispose(); } }
        if (_outputs != null) { for (c in _outputs) { if (c != null) c.dispose(); } }

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}