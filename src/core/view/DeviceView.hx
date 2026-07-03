package core.view;
import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.view.DeviceViewRegistry;
import core.view.DeviceWidgetFactory;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import ecs.ECS;
import core.view.InlineParameterEditor;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ParameterPriority;

/**
* DEVICE VIEW BASE v2.1 (Databank Architecture)
* Base class for all device widgets.
*
* Architecture: "Atom is Databank & Compute Core"
* ┌─────────────────────────────────────────────────────────────────────────┐
* │                         ATOM (Entity)                                   │
* │                              │                                          │
* │        ┌─────────────────────┼─────────────────────┐                    │
* │        │                     │                     │                    │
* │        ▼                     ▼                     ▼                    │
* │   A) COMPUTE            B) DATABANK           C) FACE                   │
* │   (processing)          (data)                (DeviceView)              │
* │                                                  │                      │
* │                   DeviceView reads from Atom     │                      │
* │                   DeviceView writes to Atom      │                      │
* │                   DeviceView DOES NOT store state│                      │
* └─────────────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════════
* ARCHITECTURE: "ATOM IS DATABANK & COMPUTE CORE"
* ═══════════════════════════════════════════════════════════════════════════
*
* DeviceView is the FACE of the Atom (Component C).
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   DeviceView DOES NOT STORE business data!                              │
* │                                                                         │
* │   DeviceView:                                                           │
* │   ┌─────────────────────────────────────────────────────────────────┐   │
* │   │   ATTRIBUTES:                                                   │   │
* │   │   - atom:Atom          // Reference to atom (Databank)          │   │
* │   │   - assembly:Assembly  // If atom is an assembly                │   │
* │   │   - isActive:Bool      // Activation flag                       │   │
* │   │                                                                 │   │
* │   │   LIFECYCLE METHODS:                                            │   │
* │   │   - activate()    → subscribe to Contact                        │   │
* │   │   - deactivate()  → unsubscribe from Contact                    │   │
* │   │   - dispose()     → full cleanup                                │   │
* │   │                                                                 │   │
* │   │   SYNCHRONIZATION METHODS:                                      │   │
* │   │   - onContactChanged(contact, newValue) → redraw                │   │
* │   │   - syncFromAtom() → initial sync with Databank                 │   │
* │   │                                                                 │   │
* │   │   WHERE TO STORE DATA:                                          │   │
* │   │   ✗ _buffer:Array<Float>      → In ATOM!                        │   │
* │   │   ✗ _state:Dynamic            → In ATOM!                        │   │
* │   │   ✓ _lastDrawTime:Float       → OK, this is UI state            │   │
* │   │   ✓ _isUpdating:Bool          → OK, this is UI state            │   │
* │   └─────────────────────────────────────────────────────────────────┘   │
* │                                                                         │
* │   Singleton Pattern:                                                    │
* │   DeviceViewRegistry guarantees ONE widget per atom.                    │
* │   Widget moves between NodeView and DeviceWindow.                       │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class DeviceView extends Sprite
{
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
	private var _contactCallbacks:Array< {contact:Contact, callback:Dynamic -> Void}>;
	/**
	* Flag to prevent recursive activation.
	*/
	private var _isActivating:Bool = false;
// =========================================================================
// CONSTRUCTOR
// =========================================================================
	public function new(atom:Atom)
	{
		super();
		this.atom = atom;
		if (Std.isOfType(atom, Assembly))
		{
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
	public function activate():Void
	{
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
	public function deactivate():Void
	{
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
	private function onActivate():Void
	{
// Override me
	}
	/**
	* Called after deactivation.
	* Override in subclasses to perform cleanup.
	*/
	private function onDeactivate():Void
	{
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
	private function subscribeToContacts():Void
	{
		if (isDisposed || atom == null) return;
// Clean existing subscriptions first
		if (_contactCallbacks.length > 0)
		{
			unsubscribeFromContacts();
		}
// Subscribe to inputs
		var inputs = atom.getInputs();
		if (inputs != null)
		{
			for (c in inputs)
			{
				if (c != null && !c.isDisposed)
				{
					var cb = function(v:Dynamic)
					{
						if (!isDisposed) onContactChanged(c, v);
					};
					c.subscribe(cb);
					_contactCallbacks.push({contact: c, callback: cb});
// Process initial value
					if (c.value != null && !isDisposed)
					{
						onContactChanged(c, c.value);
					}
				}
			}
		}
// Subscribe to outputs
		var outputs = atom.getOutputs();
		if (outputs != null)
		{
			for (c in outputs)
			{
				if (c != null && !c.isDisposed)
				{
					var cb = function(v:Dynamic)
					{
						if (!isDisposed) onContactChanged(c, v);
					};
					c.subscribe(cb);
					_contactCallbacks.push({contact: c, callback: cb});
					if (c.value != null && !isDisposed)
					{
						onContactChanged(c, c.value);
					}
				}
			}
		}
	}
	/**
	* Unsubscribe from all contacts.
	*/
	private function unsubscribeFromContacts():Void
	{
		for (item in _contactCallbacks)
		{
			if (item.contact != null && !item.contact.isDisposed)
			{
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
	private function syncFromAtom():Void
	{
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
	private function onContactChanged(contact:Contact, newValue:Dynamic):Void
	{
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
	public function dispose():Void
	{
		if (isDisposed) return;
		isDisposed = true;
// Deactivate if active
		deactivate();
// Clear references
		atom = null;
		assembly = null;
// Remove all children
		while (numChildren > 0)
		{
			var child = removeChildAt(0);
			if (Std.isOfType(child, DeviceView))
			{
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
	public function getContainerType():String
	{
		if (atom == null) return null;
		return DeviceViewRegistry.getInstance().getContainer(atom.id);
	}
	/**
	* Check if this view is in DeviceWindow.
	*/
	public function isInDeviceWindow():Bool
	{
		return getContainerType() == DeviceViewRegistry.CONTAINER_DEVICE_WINDOW;
	}
	/**
	* Check if this view is in NodeView.
	*/
	public function isInNodeView():Bool
	{
		return getContainerType() == DeviceViewRegistry.CONTAINER_NODE_VIEW;
	}
// =========================================================================
// WIDGET SIZE QUERY (v1.1)
// =========================================================================
	/**
	* Returns the natural (unscaled) dimensions of this widget.
	*
	* Used by NodeView to calculate the proper node rectangle size,
	* ensuring that the Atom body with contacts is always larger than
	* the Widget card, and the Widget fits comfortably inside the
	* Atom rectangle with padding.
	*
	* Subclasses that define `widgetWidth` and `widgetHeight` fields
	* do NOT need to override this method — it reads them via Reflect.
	* Only subclasses with non-standard sizing need to override.
	*
	* Layout principle:
	* ┌──────────────────────────────────────────────┐
	* │  NodeView rectangle (Atom body + contacts)   │
	* │  ┌────────────────────────────────────────┐  │
	* │  │  Widget (scaled by PREVIEW_SCALE)      │  │
	* │  │  Always smaller than NodeView          │  │
	* │  └────────────────────────────────────────┘  │
	* │  ← padding →                    ← padding →  │
	* └──────────────────────────────────────────────┘
	*
	* @return {width: Float, height: Float} unscaled widget dimensions
	*/
	public function getWidgetSize(): {width:Float, height:Float}
	{
		var w:Float = 80;
		var h:Float = 40;
// Most subclasses declare public var widgetWidth / widgetHeight.
// Read them via Reflect so we don't force every subclass to override.
		if (Reflect.hasField(this, "widgetWidth"))
		{
			var v = Reflect.field(this, "widgetWidth");
			if (v != null) w = cast v;
		}
		if (Reflect.hasField(this, "widgetHeight"))
		{
			var v = Reflect.field(this, "widgetHeight");
			if (v != null) h = cast v;
		}
		return {width: w, height: h};
	}
}