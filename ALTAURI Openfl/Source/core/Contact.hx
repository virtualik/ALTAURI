package core;

/**
 * CONTACT v4.0 (Optimized + Queue Based)
 * Устранена рекурсивная передача данных.
 * Использует SignalQueue для планирования обновлений.
 */
class Contact {
    
    public var id(default, null):Dynamic;
    public var type(default, null):ContactType;
    public var name(default, null):String;
    
    // Ссылка на владельца (для быстрого уведомления Атома без замыканий)
    public var owner:Atom; 
    
    public var value(get, set):Dynamic;
    private var _value:Dynamic;
    
    private var linkedTargets:Array<Contact>;
    private var callbackTargets:Array<Dynamic -> Void>;
    
    // Флаг для защиты от повторного планирования одной и той же задачи
    private var _isScheduled:Bool = false;

    public function new(initialValue:Dynamic = null, ?type:ContactType, ?name:String = "unnamed") {
        this.id = "c_" + Std.random(100000);
        this.type = (type == null) ? ContactType.UNDEFINED : type;
        this.name = name;
        this._value = initialValue;
        
        this.linkedTargets = [];
        this.callbackTargets = [];
    }

    public function link(target:Contact):Void {
        if (target == null) return;
        if (hasLink(target)) return;
        linkedTargets.push(target);
        
        // Инициализация значения
        if (_value != null) {
            target.value = _value;
        }
    }

    public function unlink(target:Contact):Void {
        linkedTargets.remove(target);
    }
    
    public function hasLink(target:Contact):Bool {
        return linkedTargets.indexOf(target) != -1;
    }

    public function subscribe(callback:Dynamic -> Void):Void {
        if (callback == null) return;
        if (hasCallback(callback)) return;
        callbackTargets.push(callback);
    }

    public function unsubscribe(callback:Dynamic -> Void):Void {
        callbackTargets.remove(callback);
    }
    
    private function hasCallback(callback:Dynamic -> Void):Bool {
        return callbackTargets.indexOf(callback) != -1;
    }

    private function set_value(newValue:Dynamic):Dynamic {
        // Оптимизация: Если значение не изменилось, выходим
        if (_value == newValue) return newValue;
        
        _value = newValue;

		if (!_isScheduled) {
			_isScheduled = true;
			// Используем нормальный приоритет (можно не указывать второй аргумент)
			SignalQueue.getInstance().schedule(_propagate, NORMAL); 
		}
        
        return newValue;
    }

    private function get_value():Dynamic {
        return _value;
    }

    /**
     * Планируемое распространение сигнала.
     * Вызывается итеративно из SignalQueue.
     */
    private function _propagate():Void {
        _isScheduled = false;

        // 1. Передаем значения связанным контактам
        // Это вызовет set_value у них -> планирование новой задачи -> стек не растет.
        for (target in linkedTargets) {
            target.value = this._value;
        }

        // 2. Уведомляем владельца (Атом) напрямую, если он есть
        // Это быстрее, чем через subscribe, и не создает замыканий
        if (owner != null) {
            owner.onContactChanged(this);
        }

        // 3. Уведомляем внешних подписчиков (например, UI, View)
        // Внимание: callback может быть медленным. 
        // В идеале UI тоже должен подписываться на очередь, но пока оставим так.
        for (callback in callbackTargets) {
            callback(this._value);
        }
    }

    public function dispose():Void {
        linkedTargets = [];
        callbackTargets = [];
        _value = null;
        owner = null;
    }
}