package core.view;

import openfl.display.Sprite;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;

/**
 * DEVICE VIEW BASE v1.1
 * Базовый класс для всех представлений устройств.
 *
 * v1.1 Fix: Immediately calls onContactChanged with current value upon subscription.
 * This prevents the widget from being blank when recreated (e.g., on node selection).
 */
class DeviceView extends Sprite {

    public var atom(default, null):Atom;
    public var assembly(default, null):Assembly;
    public var isActive(default, null):Bool = false;
    private var _contactCallbacks:Array<{contact:Contact, callback:Dynamic -> Void}>;

    public function new(atom:Atom) {
        super();
        this.atom = atom;

        if (Std.isOfType(atom, Assembly)) {
            this.assembly = cast(atom, Assembly);
        }

        _contactCallbacks = [];
    }

    public function activate():Void {
        isActive = true;
        subscribeToContacts();
        onActivate();
    }

    public function deactivate():Void {
        isActive = false;
        unsubscribeFromContacts();
        onDeactivate();
    }

    private function onActivate():Void { }
    private function onDeactivate():Void { }

    private function subscribeToContacts():Void {
        if (atom == null) return;

        var inputs = atom.getInputs();
        if (inputs != null) {
            for (c in inputs) {
                if (c != null) {
                    var cb = function(v:Dynamic) { onContactChanged(c, v); };
                    c.subscribe(cb);
                    _contactCallbacks.push({contact: c, callback: cb});
                    
                    // ИСПРАВЛЕНИЕ: Мгновенно вызываем обновление с текущим значением
                    // Это нужно, чтобы при пересоздании виджета (redraw) он сразу отобразил данные
                    if (c.value != null) {
                        onContactChanged(c, c.value);
                    }
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
                    
                    // ИСПРАВЛЕНИЕ: То же самое для выходов
                    if (c.value != null) {
                        onContactChanged(c, c.value);
                    }
                }
            }
        }
    }

    private function unsubscribeFromContacts():Void {
        for (item in _contactCallbacks) {
            if (item.contact != null && !item.contact.isDisposed) {
                item.contact.unsubscribe(item.callback);
            }
        }
        _contactCallbacks = [];
    }

    private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // Override me
    }

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

    private function setInputValue(name:String, value:Dynamic):Void {
        if (atom == null) return;
        var c = atom.getInput(name);
        if (c != null) c.value = value;
    }

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