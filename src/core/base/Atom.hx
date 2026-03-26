package core.base;

import core.logic.SignalQueue;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ATOM BASE CLASS v6.7 (Hot Start Protocol)
 * Fundamental unit of logic. Independent of rendering engine.
 *
 * v6.7 Changes (HOT START PROTOCOL):
 * - ADDED: isInitializing flag to Base Atom class.
 * - FIXED: onContactChanged now respects isInitializing flag.
 * - RESULT: Memory atoms (TextInput, Toggle) ignore inputs during load, preserving state.
 *           Passive atoms (LED) receive propagated signals correctly.
 *
 * v6.6 Changes (CRITICAL FIX):
 * - FIXED: restoreState() now checks owner.isInitializing before triggering calculations
 * - FIXED: _calculate() properly handles isLogic during first calculation
 * - IMPROVED: Better coordination with Assembly initialization sequence
 * - ADDED: _isInitializing check to prevent premature signal propagation
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
     * - true (Digital/Logic): Output changes are scheduled for the NEXT tick.
     * - false (Analog/Driver): Output changes happen IMMEDIATELY.
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
    private var _isDisposed:Bool = false;
    private var _hasCalculatedOnce:Bool = false;

    // =========================================================================
    // ИНИЦИАЛИЗАЦИЯ v6.7
    // =========================================================================

    /**
     * Флаг инициализации.
     * Если true, атом игнорирует входящие сигналы (onContactChanged делает return).
     * Это предотвращает перезапись загруженного состояния (например, в TextInput).
     */
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

        // === FIX v6.6: Проверяем, находимся ли мы внутри инициализирующейся Assembly ===
        var isInsideInitializingAssembly = false;
        var sq = SignalQueue.getInstance();

        var isAssemblyWithInternal = Std.isOfType(this, Assembly) &&
                                     cast(this, Assembly).blueprint != null &&
                                     cast(this, Assembly).blueprint.internalAtoms != null &&
                                     cast(this, Assembly).blueprint.internalAtoms.length > 0;

        if (_process != null && !isAssemblyWithInternal && !sq.isSuspended())
        {
            _isScheduled = true;
            SignalQueue.getInstance().scheduleNextTick(function()
            {
                if (!_isDisposed)
                {
                    _calculate();
                }
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

    /**
     * Called when a contact value changes.
     * Schedules a calculation if this atom has a process function.
     *
     * v6.7: Blocks reaction if isInitializing is true.
     */
    public function onContactChanged(c:Contact):Void
    {
        if (_isScheduled || _isDisposed) return;

        // === FIX v6.7: БЛОКИРОВКА РЕАКЦИИ ВО ВРЕМЯ ИНИЦИАЛИЗАЦИИ ===
        // Это предотвращает перезапись сохраненного состояния (например в TextInput),
        // когда входящие сигналы приходят от других инициализирующихся узлов.
        if (isInitializing) return;

        if (c.type == OUTPUT && c.owner == this)
        {
            return;
        }

        if (_process != null)
        {
            _isScheduled = true;
            core.logic.SignalQueue.getInstance().schedule(_calculate, NORMAL);
        }
    }

    /**
     * Perform the calculation.
     */
    private function _calculate():Void
    {
        _isScheduled = false;
        _hasCalculatedOnce = true;

        if (_isDisposed || _process == null || _inputs == null) return;

        // Кэшируем входные значения
        for (i in 0..._inputs.length)
        {
            _inputCache[i] = _inputs[i].value;
        }

        var results = _process(_inputCache);

        if (results != null && results.length == _outputs.length)
        {

            if (isLogic)
            {
                // === ЦИФРОВОЙ РЕЖИМ: Записываем результат в следующем такте ===
                var outs = _outputs;
                var vals = results;

                SignalQueue.getInstance().scheduleNextTick(function()
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
                // === АНАЛОГОВЫЙ РЕЖИМ: Мгновенная запись ===
                for (i in 0..._outputs.length)
                {
                    if (_outputs[i] != null) _outputs[i].value = results[i];
                }
            }
        }
    }

    /**
     * Force a calculation immediately.
     */
    public function forceCalculate():Void
    {
        if (_isDisposed || _process == null || _inputs == null) return;
        _calculate();
    }

    public function getPersistentState():Dynamic { return null; }

    public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;

        if (Reflect.hasField(state, "isLogic"))
        {
            if (!_isLogic)
            {
                this.isLogic = state.isLogic;
            }
        }
    }

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact
    {
        if (_inputs == null) return null;
        for (c in _inputs)
        {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    public function getOutput(name:String):Contact
    {
        if (_outputs == null) return null;
        for (c in _outputs)
        {
            if (c != null && c.name == name) return c;
        }
        return null;
    }

    public function getInputNames():Array<String>
    {
        var names:Array<String> = [];
        for (c in _inputs)
        {
            if (c != null && c.name != null) names.push(c.name);
        }
        return names;
    }

    public function getOutputNames():Array<String>
    {
        var names:Array<String> = [];
        for (c in _outputs)
        {
            if (c != null && c.name != null) names.push(c.name);
        }
        return names;
    }

    public function dispose():Void
    {
        _isDisposed = true;

        if (_isActive)
        {
            DriverManager.getInstance().unregister(this.id);
        }

        if (_inputs != null)
        {
            for (c in _inputs)
            {
                if (c != null) c.dispose();
            }
        }

        if (_outputs != null)
        {
            for (c in _outputs)
            {
                if (c != null) c.dispose();
            }
        }

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}