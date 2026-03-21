package core.view;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;

/**
 * DEVICE VIEW BASE v2.0 (Databank Architecture)
 * Base class for all device widgets.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * DeviceView - это ЛИЦО Атома (Component В).
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeviceView НЕ ХРАНИТ бизнес-данные!                                   │
 * │                                                                         │
 * │   DeviceView:                                                           │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │   АТРИБУТЫ:                                                     │   │
 * │   │   - atom:Atom          // Ссылка на атом (Databank)             │   │
 * │   │   - assembly:Assembly  // Если атом - сборка                    │   │
 * │   │   - isActive:Bool      // Флаг активации                        │   │
 * │   │                                                                 │   │
 * │   │   МЕТОДЫ ЖИЗНЕННОГО ЦИКЛА:                                      │   │
 * │   │   - activate()    → подписка на Contact                         │   │
 * │   │   - deactivate()  → отписка от Contact                          │   │
 * │   │   - dispose()     → полная очистка                              │   │
 * │   │                                                                 │   │
 * │   │   МЕТОДЫ СИНХРОНИЗАЦИИ:                                         │   │
 * │   │   - onContactChanged(contact, newValue) → перерисовка           │   │
 * │   │   - syncFromAtom() → начальная синхронизация с Databank         │   │
 * │   │                                                                 │   │
 * │   │   ГДЕ ХРАНИТЬ ДАННЫЕ:                                           │   │
 * │   │   ✗ _buffer:Array<Float>      → В АТОМЕ!                        │   │
 * │   │   ✗ _state:Dynamic            → В АТОМЕ!                        │   │
 * │   │   ✓ _lastDrawTime:Float       → ОК, это UI-состояние            │   │
 * │   │   ✓ _isUpdating:Bool          → ОК, это UI-состояние            │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Singleton Pattern:                                                    │
 * │   DeviceViewRegistry гарантирует ОДИН виджет на атом.                   │
 * │   Виджет перемещается между NodeView и DeviceWindow.                    │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.0 Changes:
 * - Added syncFromAtom() for initial data synchronization
 * - Added documentation for Databank architecture
 * - Improved activate/deactivate lifecycle
 * - Full compatibility with DeviceViewRegistry
 *
 * v1.4 Changes:
 * - Added contact subscription and lifecycle management
 */
class DeviceView extends Sprite {

    // =========================================================================
    // REFERENCES
    // =========================================================================

    /**
     * Atom (Model) - the Databank and Compute Core.
     * DeviceView reads data from atom and displays it.
     */
    public var atom(default, null):Atom;

    /**
     * Assembly reference if atom is an Assembly.
     * Useful for accessing internal atoms.
     */
    public var assembly(default, null):Assembly;

    // =========================================================================
    // STATE
    // =========================================================================

    /**
     * Is this view currently active (subscribed to updates)?
     */
    public var isActive(default, null):Bool = false;

    /**
     * Has this view been disposed?
     */
    public var isDisposed(default, null):Bool = false;

    // =========================================================================
    // SUBSCRIPTION TRACKING
    // =========================================================================

    /**
     * Tracked contact subscriptions for proper cleanup.
     * Format: [{contact: Contact, callback: Dynamic -> Void}]
     */
    private var _contactCallbacks:Array<{contact:Contact, callback:Dynamic -> Void}>;

    /**
     * Flag to prevent recursive activation.
     */
    private var _isActivating:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom) {
        super();
        this.atom = atom;

        if (Std.isOfType(atom, Assembly)) {
            this.assembly = cast(atom, Assembly);
        }

        _contactCallbacks = [];
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================

    /**
     * Activate the view.
     *
     * Called when:
     * - NodeView becomes visible
     * - DeviceWindow opens and adds this widget
     * - User focuses on this device
     *
     * Subclasses should override onActivate() instead of this method.
     */
    public function activate():Void {
        if (isActive || _isActivating || isDisposed) return;
        _isActivating = true;

        isActive = true;

        // Subscribe to all contacts
        subscribeToContacts();

        // Sync current state from atom's Databank
        syncFromAtom();

        // Subclass hook
        onActivate();

        _isActivating = false;
    }

    /**
     * Deactivate the view.
     *
     * Called when:
     * - NodeView becomes invisible
     * - DeviceWindow closes
     * - User navigates away
     *
     * Subclasses should override onDeactivate() instead of this method.
     */
    public function deactivate():Void {
        if (!isActive || isDisposed) return;

        isActive = false;

        // Unsubscribe from all contacts
        unsubscribeFromContacts();

        // Subclass hook
        onDeactivate();
    }

    /**
     * Called after activation.
     * Override in subclasses to perform initialization.
     */
    private function onActivate():Void {
        // Override me
    }

    /**
     * Called after deactivation.
     * Override in subclasses to perform cleanup.
     */
    private function onDeactivate():Void {
        // Override me
    }

    // =========================================================================
    // CONTACT SUBSCRIPTION
    // =========================================================================

    /**
     * Subscribe to all atom contacts.
     *
     * This is how DeviceView (View) connects to Atom (Model).
     * When a Contact value changes, onContactChanged() is called.
     */
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

    /**
     * Unsubscribe from all contacts.
     */
    private function unsubscribeFromContacts():Void {
        for (item in _contactCallbacks) {
            if (item.contact != null && !item.contact.isDisposed) {
                item.contact.unsubscribe(item.callback);
            }
        }
        _contactCallbacks.resize(0);
    }

    // =========================================================================
    // DATA SYNCHRONIZATION
    // =========================================================================

    /**
     * Synchronize view state from atom's Databank.
     *
     * Called automatically on activate().
     * Override in subclasses to read atom's buffer/state.
     *
     * Example for OscilloscopeWidget:
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ override private function syncFromAtom():Void {                         │
     * │     if (Std.isOfType(atom, OscilloscopeAtom)) {                         │
     * │         var oscAtom = cast(atom, OscilloscopeAtom);                     │
     * │         // Read buffer from atom's Databank                             │
     * │         drawWave(                                                       │
     * │             oscAtom.getBuffer(),                                        │
     * │             oscAtom.getWriteIndex(),                                    │
     * │             oscAtom.getSamplesCollected()                               │
     * │         );                                                              │
     * │     }                                                                   │
     * │ }                                                                       │
     * └─────────────────────────────────────────────────────────────────────────┘
     */
    private function syncFromAtom():Void {
        // Override in subclasses to sync from Databank
    }

    /**
     * Handle contact value change.
     *
     * This is the MAIN method for responding to data changes.
     * Override in subclasses to update the visual representation.
     *
     * @param contact The contact that changed
     * @param newValue The new value
     *
     * Example for LEDWidget:
     * ┌─────────────────────────────────────────────────────────────────────────┐
     * │ override private function onContactChanged(c:Contact, v:Dynamic):Void { │
     * │     if (isDisposed) return;                                             │
     * │     // Check which contact changed                                      │
     * │     if (c.name == "in") {                                               │
     * │         // Update visual based on value                                 │
     * │         _isOn = (v == true);                                            │
     * │         redraw();                                                       │
     * │     }                                                                   │
     * │ }                                                                       │
     * └─────────────────────────────────────────────────────────────────────────┘
     */
    private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // Override me
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    /**
     * Clean up all resources.
     *
     * Called when:
     * - Atom is deleted from project
     * - DeviceViewRegistry clears all widgets
     * - Application shuts down
     */
    public function dispose():Void {
        if (isDisposed) return;
        isDisposed = true;

        // Deactivate if active
        deactivate();

        // Clear references
        atom = null;
        assembly = null;

        // Remove all children
        while (numChildren > 0) {
            var child = removeChildAt(0);
            if (Std.isOfType(child, DeviceView)) {
                cast(child, DeviceView).dispose();
            }
        }

        // Clear graphics
        graphics.clear();
    }

    // =========================================================================
    // UTILITY
    // =========================================================================

    /**
     * Get current container type.
     * Uses DeviceViewRegistry to determine location.
     */
    public function getContainerType():String {
        if (atom == null) return null;
        return DeviceViewRegistry.getInstance().getContainer(atom.id);
    }

    /**
     * Check if this view is in DeviceWindow.
     */
    public function isInDeviceWindow():Bool {
        return getContainerType() == DeviceViewRegistry.CONTAINER_DEVICE_WINDOW;
    }

    /**
     * Check if this view is in NodeView.
     */
    public function isInNodeView():Bool {
        return getContainerType() == DeviceViewRegistry.CONTAINER_NODE_VIEW;
    }
}
