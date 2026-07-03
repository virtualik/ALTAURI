package core.view;
import core.base.Atom;
import openfl.display.Sprite;

/**
* DEVICE VIEW REGISTRY v1.0
* Singleton widget registry - ensures "One Atom = One Face" principle.
*
* Architecture "Atom is Databank & Compute Core":
* ┌─────────────────────────────────────────────────────────────────────────┐
* │                         ATOM (Entity)                                   │
* │                              │                                          │
* │        ┌─────────────────────┼─────────────────────┐                    │
* │        │                     │                     │                    │
* │        ▼                     ▼                     ▼                    │
* │   A) COMPUTE            B) DATABANK           C) FACE                   │
* │   (processing)          (data)                (DeviceView)              │
* │                                                 │                       │
* │                                                 │                       │
* │                      ┌──────────────────────────┘                       │
* │                      │                                                  │
* │                      ▼                                                  │
* │              DeviceViewRegistry                                         │
* │              (guarantees uniqueness)                                    │
* │                      │                                                  │
* │         ┌────────────┴────────────┐                                     │
* │         │                         │                                     │
* │         ▼                         ▼                                     │
* │    NodeView (preview)      DeviceWindow (full)                          │
* │    scaled=0.6              scaled=1.0                                   │
* │                                                                         │
* │    Widget MOVES between containers,                                     │
* │    but ALWAYS one instance per atom.                                    │
* └─────────────────────────────────────────────────────────────────────────┘
*
* Principles:
* 1. One atom = one DeviceView (Face)
* 2. DeviceView can live in NodeView OR in DeviceWindow
* 3. On move - same object, only parent and scale change
* 4. On atom delete - widget removed from registry
*
* Headless Mode:
* - Registry does not create widgets automatically
* - Widgets created only on UI request
* - Atoms work independently of widget presence
*/
class DeviceViewRegistry
{
	private static var _instance:DeviceViewRegistry;
	/**
	* Map: atom.id -> DeviceView
	* Guarantees widget uniqueness for each atom.
	*/
	private var _widgets:Map<String, DeviceView>;
	/**
	* Map: atom.id -> current widget container
	* For tracking widget location (NodeView or DeviceWindow)
	*/
	private var _containers:Map<String, String>;
// Constants for container identification
	public static inline var CONTAINER_NODE_VIEW:String = "NodeView";
	public static inline var CONTAINER_DEVICE_WINDOW:String = "DeviceWindow";
	/**
	* Get singleton instance.
	*/
	public static function getInstance():DeviceViewRegistry
	{
		if (_instance == null)
		{
			_instance = new DeviceViewRegistry();
		}
		return _instance;
	}
	private function new()
	{
		_widgets = new Map<String, DeviceView>();
		_containers = new Map<String, String>();
	}
// =========================================================================
// MAIN API
// =========================================================================
	/**
	* Get or create widget for atom.
	*
	* This is the MAIN method for obtaining Atom's Face.
	*
	* @param atom Atom for which widget is needed
	* @param createIfNotExists If true - creates new widget if missing
	* @return DeviceView or null if atom null or widget cannot be created
	*/
	public function getOrCreate(atom:Atom, createIfNotExists:Bool = true):DeviceView
	{
		if (atom == null) return null;
// Already exists?
		if (_widgets.exists(atom.id))
		{
			return _widgets.get(atom.id);
		}
		if (!createIfNotExists) return null;
// Create new via Factory
		var widget = DeviceWidgetFactory.create(atom);
		if (widget != null)
		{
			_widgets.set(atom.id, widget);
// Container not assigned yet
			_containers.remove(atom.id);
		}
		return widget;
	}
	/**
	* Check if widget exists for atom.
	*/
	public function exists(atomId:String):Bool
	{
		return _widgets.exists(atomId);
	}
	/**
	* Get existing widget (without creation).
	*/
	public function get(atomId:String):DeviceView
	{
		return _widgets.get(atomId);
	}
	/**
	* Register already created widget.
	* Used when widget created manually but needs registration.
	*/
	public function register(atomId:String, widget:DeviceView):Void
	{
		if (atomId == null || widget == null) return;
// If widget already exists for this atom - remove old one first
		if (_widgets.exists(atomId))
		{
			var old = _widgets.get(atomId);
			if (old != null && old != widget)
			{
				old.dispose();
			}
		}
		_widgets.set(atomId, widget);
	}
	/**
	* Remove widget from registry.
	* Called when atom deleted from project.
	*
	* @param atomId Atom ID
	* @param disposeWidget If true - calls dispose() on widget
	*/
	public function remove(atomId:String, disposeWidget:Bool = true):Void
	{
		var widget = _widgets.get(atomId);
		if (widget != null)
		{
			if (disposeWidget)
			{
				widget.dispose();
			}
			_widgets.remove(atomId);
			_containers.remove(atomId);
		}
	}
// =========================================================================
// CONTAINER MANAGEMENT
// =========================================================================
	/**
	* Set current widget container.
	*
	* @param atomId Atom ID
	* @param containerType "NodeView" or "DeviceWindow"
	*/
	public function setContainer(atomId:String, containerType:String):Void
	{
		if (atomId == null) return;
		_containers.set(atomId, containerType);
	}
	/**
	* Get current widget container.
	*
	* @return "NodeView", "DeviceWindow" or null if widget doesn't exist
	*/
	public function getContainer(atomId:String):String
	{
		return _containers.get(atomId);
	}
	/**
	* Clear container registration for an atom.
	* Call when widget is removed from any container without moving to another.
	*/
	public function clearContainer(atomId:String):Void
	{
		_containers.remove(atomId);
	}
	/**
	* Check if widget is in NodeView.
	*/
	public function isInNodeView(atomId:String):Bool
	{
		return _containers.get(atomId) == CONTAINER_NODE_VIEW;
	}
	/**
	* Check if widget is in DeviceWindow.
	*/
	public function isInDeviceWindow(atomId:String):Bool
	{
		return _containers.get(atomId) == CONTAINER_DEVICE_WINDOW;
	}
// =========================================================================
// WIDGET MOVEMENT
// =========================================================================
	/**
	* Move widget to DeviceWindow.
	*
	* If widget currently in NodeView - it will be extracted
	* and moved to DeviceWindow with full scale.
	*
	* @param atomId Atom ID
	* @param targetContainer Sprite for adding widget
	* @param posX Position X in new container
	* @param posY Position Y in new container
	* @return DeviceView or null
	*/
	public function moveToDeviceWindow(atomId:String, targetContainer:Sprite,
									   ?posX:Float = 0, ?posY:Float = 0):DeviceView
	{
		var widget = _widgets.get(atomId);
		if (widget == null) return null;
// If already in DeviceWindow - just update position
		if (isInDeviceWindow(atomId))
		{
			widget.x = posX;
			widget.y = posY;
			return widget;
		}
// Extract from current parent (NodeView)
		if (widget.parent != null)
		{
			widget.parent.removeChild(widget);
		}
// Set full scale
		widget.scaleX = 1.0;
		widget.scaleY = 1.0;
// Add to new container
		widget.x = posX;
		widget.y = posY;
		targetContainer.addChild(widget);
// Update container
		setContainer(atomId, CONTAINER_DEVICE_WINDOW);
// Activate if not active
		if (!widget.isActive)
		{
			widget.activate();
		}
		return widget;
	}
	/**
	* Move widget back to NodeView.
	*
	* Used when DeviceWindow closes.
	*
	* @param atomId Atom ID
	* @param targetContainer Sprite (NodeView) for adding widget
	* @param scaleFactor Scale for preview (usually 0.6)
	* @param posX Position X
	* @param posY Position Y
	* @return DeviceView or null
	*/
	public function moveToNodeView(atomId:String, targetContainer:Sprite,
								   scaleFactor:Float = 0.6, ?posX:Float = 0, ?posY:Float = 0):DeviceView
	{
		var widget = _widgets.get(atomId);
		if (widget == null) return null;
// If already in NodeView - just update
		if (isInNodeView(atomId))
		{
			widget.x = posX;
			widget.y = posY;
			widget.scaleX = scaleFactor;
			widget.scaleY = scaleFactor;
			return widget;
		}
// Extract from current parent (DeviceWindow/DeviceCard)
		if (widget.parent != null)
		{
			widget.parent.removeChild(widget);
		}
// Set preview scale
		widget.scaleX = scaleFactor;
		widget.scaleY = scaleFactor;
// Add to NodeView
		widget.x = posX;
		widget.y = posY;
		targetContainer.addChild(widget);
// Update container
		setContainer(atomId, CONTAINER_NODE_VIEW);
		return widget;
	}
// =========================================================================
// INFO & DIAGNOSTICS
// =========================================================================
	/**
	* Get count of registered widgets.
	*/
	public function getCount():Int
	{
		var count = 0;
		for (key in _widgets.keys()) count++;
		return count;
	}
	/**
	* Get all atom IDs with widgets.
	*/
	public function getAtomIds():Array<String>
	{
		var ids:Array<String> = [];
		for (id in _widgets.keys())
		{
			ids.push(id);
		}
		return ids;
	}
	/**
	* Get all widgets in specified container.
	*/
	public function getWidgetsInContainer(containerType:String):Array<DeviceView>
	{
		var result:Array<DeviceView> = [];
		for (atomId in _containers.keys())
		{
			if (_containers.get(atomId) == containerType)
			{
				var widget = _widgets.get(atomId);
				if (widget != null)
				{
					result.push(widget);
				}
			}
		}
		return result;
	}
	/**
	* Diagnostic output of registry state.
	*/
	public function debugPrint():Void
	{
		var nodeViewCount = 0;
		var deviceWindowCount = 0;
		var noContainerCount = 0;
		for (atomId in _widgets.keys())
		{
			var container = _containers.get(atomId);
			if (container == CONTAINER_NODE_VIEW) nodeViewCount++;
			else if (container == CONTAINER_DEVICE_WINDOW) deviceWindowCount++;
			else noContainerCount++;
		}
	}
// =========================================================================
// CLEANUP
// =========================================================================
	/**
	* Remove all widgets from registry.
	* Used on full project reload.
	*
	* @param disposeWidgets If true - calls dispose() on all widgets
	*/
	public function clear(disposeWidgets:Bool = true):Void
	{
		if (disposeWidgets)
		{
			for (widget in _widgets)
			{
				if (widget != null)
				{
					try
					{
						widget.dispose();
					}
					catch (e:Dynamic)
					{
						trace('DeviceViewRegistry: Error disposing widget: $e');
					}
				}
			}
		}
		_widgets.clear();
		_containers.clear();
		trace('DeviceViewRegistry: Cleared all widgets');
	}
	/**
	* Full singleton reset.
	* Used on application exit or full reset.
	*/
	public static function reset():Void
	{
		if (_instance != null)
		{
			_instance.clear(true);
			_instance = null;
		}
	}
}