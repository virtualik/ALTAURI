package core;

import core.Utils;
import drivers.Driver;
import drivers.DriverManager;

// Теперь Atom может быть Драйвером
class Atom implements IDisposable implements Driver {
    
    public var id(default, null):String;
    public var type(default, null):String;
    public var name(default, null):String;

    private var _inputs:Array<Contact>;
    private var _outputs:Array<Contact>;
    private var _process:Array<Dynamic> -> Array<Dynamic>;
    
    private var _inputCache:Array<Dynamic>;
    private var _isScheduled:Bool = false;
    
    // Флаг, является ли атом "активным" (источником)
    private var _isActive:Bool = false;

    public function new(
        inputs:Array<Contact>,
        outputs:Array<Contact>,
        processFunc:Array<Dynamic> -> Array<Dynamic>,
        ?id:String,
        ?type:String = "Generic",
        ?isActive:Bool = false // Новый флаг
    ) {
        this.id = (id != null) ? id : "atom_" + Std.random(100000);
        this.type = type;
        this.name = type;
        this._isActive = isActive;

        this._inputs = inputs;
        this._outputs = outputs;
        this._process = processFunc;

        _inputCache = [];
        for(i in 0...inputs.length) _inputCache.push(null);

        _bind();
        
        // Если Атом активный, он сам регистрирует себя в системе!
        if (_isActive) {
            DriverManager.getInstance().register(this);
        }
    }

    private function _bind():Void {
        for (input in _inputs) {
            input.owner = this;
        }
    }
    
    // --- Реализация интерфейса Driver ---
    
    public function init():Void {
        // Метод инициализации драйвера (вызывается один раз при регистрации)
        // Например, стартовые настройки
    }

    public function update(dt:Float):Void {
        // Этот метод вызывается каждый кадр, только если _isActive == true
        // Здесь мы можем обновлять внутренние данные или генерировать сигналы
        _onUpdate(dt);
    }
    
    // Метод для переопределения в наследниках (Active Atoms)
    private function _onUpdate(dt:Float):Void {
        // По умолчанию ничего не делает
    }

    // --- Логика вычислений (без изменений) ---

    public function onContactChanged(c:Contact):Void {
        if (_isScheduled) return;
        _isScheduled = true;
        SignalQueue.getInstance().schedule(_calculate, NORMAL);
    }

    private function _calculate():Void {
        _isScheduled = false;
        if (_process == null) return;

        for (i in 0..._inputs.length) _inputCache[i] = _inputs[i].value;
        var results = _process(_inputCache);

        if (results != null && results.length == _outputs.length) {
            for (i in 0..._outputs.length) {
                _outputs[i].value = results[i];
            }
        }
    }

    public function getInputs():Array<Contact> return _inputs;
    public function getOutputs():Array<Contact> return _outputs;

    public function getInput(name:String):Contact {
        for (c in _inputs) if (c.name == name) return c;
        return null;
    }

    public function getOutput(name:String):Contact {
        for (c in _outputs) if (c.name == name) return c;
        return null;
    }

    public function dispose():Void {
        // Если мы были активным, удаляем себя из менеджера
        if (_isActive) {
            DriverManager.getInstance().unregister(this.id);
        }
        
        for (c in _inputs) c.dispose();
        for (c in _outputs) c.dispose();

        _inputs = null;
        _outputs = null;
        _process = null;
        _inputCache = null;
    }
}