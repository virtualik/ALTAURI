package core.view;

import openfl.display.Sprite;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;

/**
 * DEVICE VIEW BASE v1.0
 * Базовый класс для всех представлений устройств.
 * 
 * Каждый Atom может создать своё представление для DeviceWindow
 * путём переопределения метода createDeviceView().
 */
class DeviceView extends Sprite {
    
    /**
     * Ссылка на Atom, который это представление отображает.
     */
    public var atom(default, null):Atom;
    
    /**
     * Ссылка на Assembly, если atom является сборкой.
     */
    public var assembly(default, null):Assembly;
    
    /**
     * Флаг, что представление активно и обновляется.
     */
    public var isActive(default, null):Bool = false;
    
    /**
     * Подписки на контакты для автоотписки при dispose.
     */
    private var _contactCallbacks:Array<{contact:Contact, callback:Dynamic -> Void}>;
    
    public function new(atom:Atom) {
        super();
        this.atom = atom;
        
        if (Std.isOfType(atom, Assembly)) {
            this.assembly = cast(atom, Assembly);
        }
        
        _contactCallbacks = [];
    }
    
    /**
     * Активировать представление.
     * Вызывается когда представление добавлено на сцену DeviceWindow.
     */
    public function activate():Void {
        isActive = true;
        subscribeToContacts();
        onActivate();
    }
    
    /**
     * Деактивировать представление.
     * Вызывается когда представление убрано со сцены.
     */
    public function deactivate():Void {
        isActive = false;
        unsubscribeFromContacts();
        onDeactivate();
    }
    
    /**
     * Переопределяемый метод для активации.
     */
    private function onActivate():Void { }
    
    /**
     * Переопределяемый метод для деактивации.
     */
    private function onDeactivate():Void { }
    
    /**
     * Подписаться на все входы и выходы.
     */
    private function subscribeToContacts():Void {
        if (atom == null) return;
        
        var inputs = atom.getInputs();
        if (inputs != null) {
            for (c in inputs) {
                if (c != null) {
                    var cb = function(v:Dynamic) { onContactChanged(c, v); };
                    c.subscribe(cb);
                    _contactCallbacks.push({contact: c, callback: cb});
                }
            }
        }
        
        var outputs = atom.getOutputs();
        if (outputs != null) {
            for (c in outputs) {
                if (c != null) {
                    var cb = function(v:Dynamic) { onContactChanged(c, v); };
                    c.subscribe(cb);
                    _contactCallbacks.push({contact: c, callback: cb});
                }
            }
        }
    }
    
    /**
     * Отписаться от всех контактов.
     */
    private function unsubscribeFromContacts():Void {
        for (item in _contactCallbacks) {
            if (item.contact != null && !item.contact.isDisposed) {
                item.contact.unsubscribe(item.callback);
            }
        }
        _contactCallbacks = [];
    }
    
    /**
     * Вызывается при изменении значения контакта.
     * Переопределите для реакции на изменения.
     */
    private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // Override me
    }
    
    /**
     * Получить значение контакта по имени.
     */
    private function getInputValue(name:String):Dynamic {
        if (atom == null) return null;
        var c = atom.getInput(name);
        return c != null ? c.value : null;
    }
    
    private function getOutputValue(name:String):Dynamic {
        if (atom == null) return null;
        var c = atom.getOutput(name);
        return c != null ? c.value : null;
    }
    
    /**
     * Установить значение контакта (для интерактивных элементов).
     */
    private function setInputValue(name:String, value:Dynamic):Void {
        if (atom == null) return;
        var c = atom.getInput(name);
        if (c != null) c.value = value;
    }
    
    /**
     * Полная очистка.
     */
    public function dispose():Void {
        deactivate();
        atom = null;
        assembly = null;
        
        while (numChildren > 0) {
            removeChildAt(0);
        }
        
        graphics.clear();
    }
}
