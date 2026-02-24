package core;

/**
 * CONTACT v3.5 (Stable + Loop Protection)
 */
class Contact {
    
    public var id(default, null):Dynamic;
    public var type(default, null):ContactType;
    public var name(default, null):String;
    
    public var value(get, set):Dynamic;
    private var _value:Dynamic;
    
    private var linkedTargets:Array<Contact>;
    private var callbackTargets:Array<Dynamic -> Void>;

    // Removed local isProcessing, using global Utils depth counter

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
        // Optimisation: Stop if value didn't change (reduces noise)
        if (_value == newValue) return newValue;
        
        _value = newValue;
        dispatch();
        return newValue;
    }

    private function get_value():Dynamic {
        return _value;
    }

    /**
     * Propagates signal.
     * Uses global Loop Protection.
     */
    private function dispatch():Void {
        // 1. Check Global Depth
        if (!Utils.enterDepth()) return;

        // 2. Propagate to Linked Contacts
        for (target in linkedTargets) {
            target.value = this._value; // Recursive set_value calls will increase depth
        }

        // 3. Notify Callbacks
        for (callback in callbackTargets) {
            callback(this._value);
        }

        // 4. Exit Depth
        Utils.exitDepth();
    }

    public function dispose():Void {
        linkedTargets = [];
        callbackTargets = [];
        _value = null;
    }
}