package core.view;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;

/**
 * DEVICE VIEW BASE v1.4
 * Base class for all device widgets.
 * Provides contact subscription and lifecycle management.
 */
class DeviceView extends Sprite {
    
    public var atom(default, null):Atom;
    public var assembly(default, null):Assembly;
    public var isActive(default, null):Bool = false;
    
    private var _contactCallbacks:Array<{contact:Contact, callback:Dynamic -> Void}>;
    private var _isActivating:Bool = false;
    public var isDisposed(default, null):Bool = false;

    public function new(atom:Atom) {
        super();
        this.atom = atom;
        if (Std.isOfType(atom, Assembly)) {
            this.assembly = cast(atom, Assembly);
        }
        _contactCallbacks = [];
    }

    public function activate():Void {
        if (isActive || _isActivating || isDisposed) return;
        _isActivating = true;

        isActive = true;
        subscribeToContacts();
        onActivate();

        _isActivating = false;
    }

    public function deactivate():Void {
        if (!isActive || isDisposed) return;
        isActive = false;
        unsubscribeFromContacts();
        onDeactivate();
    }

    private function onActivate():Void {}
    private function onDeactivate():Void {}

    private function subscribeToContacts():Void {
        if (isDisposed || atom == null) return;

        // Clean existing subscriptions first
        if (_contactCallbacks.length > 0) {
            unsubscribeFromContacts();
        }

        // Subscribe to inputs
        var inputs = atom.getInputs();
        if (inputs != null) {
            for (c in inputs) {
                if (c != null && !c.isDisposed) {
                    var cb = function(v:Dynamic) {
                        if (!isDisposed) onContactChanged(c, v);
                    };
                    c.subscribe(cb);
                    _contactCallbacks.push({contact: c, callback: cb});
                    
                    // Process initial value
                    if (c.value != null && !isDisposed) {
                        onContactChanged(c, c.value);
                    }
                }
            }
        }

        // Subscribe to outputs
        var outputs = atom.getOutputs();
        if (outputs != null) {
            for (c in outputs) {
                if (c != null && !c.isDisposed) {
                    var cb = function(v:Dynamic) {
                        if (!isDisposed) onContactChanged(c, v);
                    };
                    c.subscribe(cb);
                    _contactCallbacks.push({contact: c, callback: cb});
                    
                    if (c.value != null && !isDisposed) {
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
        _contactCallbacks.resize(0);
    }

    /**
     * Override this method to handle contact value changes.
     */
    private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // Override me
    }

    public function dispose():Void {
        if (isDisposed) return;
        isDisposed = true;

        deactivate();
        atom = null;
        assembly = null;

        while (numChildren > 0) {
            removeChildAt(0);
        }
        graphics.clear();
    }
}
