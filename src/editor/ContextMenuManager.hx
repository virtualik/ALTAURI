package editor;

import core.base.Assembly;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import core.types.ContactType;
import library.AtomRegistry;
import system.commands.base.MacroCommand;
import system.commands.editor.AddPortCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.GroupAtomsCommand;
import system.commands.editor.RemovePortCommand;
import system.managers.UndoManager;
import ui.ContextMenu;
import ui.SettingsPanel;

/**
* CONTEXT MENU MANAGER v1.3 (Global Name Uniqueness + Topology Guard Integration)
* Responsible for creating and handling editor context menus.
* Listens to impulses from NodeEditor and manages the menu UI.
*
* Architecture:
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   ContextMenuManager                                                    │
* │                                                                         │
* │   ┌─────────────────────────────────────────────────────────────────┐   │
* │   │  Event Subscriptions:                                           │   │
* │   │  - CONTEXT_MENU_ACTION   → onMenuAction() (execute commands)    │   │
* │   │  - CLOSE_CONTEXT_MENU    → onCloseContextMenu() (hide menu)     │   │
* │   │  - NODE_RIGHT_CLICKED    → onNodeRightClick() (node menu)       │   │
* │   │  - WIRE_RIGHT_CLICKED    → onWireRightClick() (wire menu)       │   │
* │   │  - PORT_RIGHT_CLICKED    → onPortRightClick() (port menu)       │   │
* │   │  - CANVAS_RIGHT_CLICKED  → onCanvasRightClick() (atom menu)     │   │
* │   │                                                                 │   │
* │   │  Menu Actions:                                                  │   │
* │   │  - ADD_ATOM             → NodeEditor.createAtom()               │   │
* │   │  - DELETE_ALL_SELECTED  → MacroCommand[DeleteAtom+DeleteWires]  │   │
* │   │  - DELETE_SELECTED_ATOMS→ NodeEditor.deleteSelectedNodes()      │   │
* │   │  - DELETE_WIRES         → DeleteWiresCommand                    │   │
* │   │  - GROUP_ATOMS          → GroupAtomsCommand (via UndoManager)   │   │
* │   │  - ADD_PORT             → AddPortCommand                        │   │
* │   │  - REMOVE_PORT          → RemovePortCommand                     │   │
* │   └─────────────────────────────────────────────────────────────────┘   │
* │                                                                         │
* │   v1.3 Changes:                                                         │
* │   - ADDED: _isNameTakenGlobally callback to ensure newly grouped        │
* │     assemblies receive globally unique names (e.g., "CustomAssembly_1").│
* │                                                                         │
* │   v1.2 Changes:                                                         │
* │   - FIXED: groupSelectedToAssembly() now uses UndoManager.executeAndStore() │
* │     instead of direct cmd.execute(). This ensures Topology Guard is     │
* │     activated, preventing race conditions with audio drivers.           │
* │                                                                         │
* │   v1.1 Changes:                                                         │
* │   - Added dispose() method for proper cleanup                           │
* │   - Unsubscribes from all Impulsys events                               │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class ContextMenuManager
{
	private var _menu:ContextMenu;
	private var _editor:NodeEditor;
	private var _assembly:Assembly;
	
	// Reference to settings (needed for allowAssembly check)
	private var _settingsPanel:SettingsPanel;
	
	// Temporary state for passing data to action
	private var _contextTargetId:String = null;
	
	// Flag to protect against repeated dispose
	private var _isDisposed:Bool = false;
	
	// v1.3: Global name uniqueness checker for grouping operations
	private var _isNameTakenGlobally:(String, ?String) -> Bool;

	public function new(settingsPanel:SettingsPanel)
	{
		_settingsPanel = settingsPanel;
		_menu = new ContextMenu();
		
		// Subscribe to all required impulses
		Impulsys.subscribeToImpulse(EventType.CONTEXT_MENU_ACTION, onMenuAction);
		Impulsys.subscribeToImpulse(EventType.CLOSE_CONTEXT_MENU, onCloseContextMenu);
		Impulsys.subscribeToImpulse(EventType.NODE_RIGHT_CLICKED, onNodeRightClick);
		Impulsys.subscribeToImpulse(EventType.WIRE_RIGHT_CLICKED, onWireRightClick);
		Impulsys.subscribeToImpulse(EventType.PORT_RIGHT_CLICKED, onPortRightClick);
		Impulsys.subscribeToImpulse(EventType.CANVAS_RIGHT_CLICKED, onCanvasRightClick);
	}

	/**
	* Update context when switching editor/assembly.
	* 
	* @param editor Current NodeEditor instance
	* @param assembly Current Assembly instance
	* @param isNameTakenGlobally Callback to check name uniqueness globally (v1.3)
	*/

	public function setContext(editor:NodeEditor, assembly:Assembly, ?isNameTakenGlobally:(String, ?String) -> Bool):Void
	{
		_editor = editor;
		_assembly = assembly;
		_isNameTakenGlobally = isNameTakenGlobally;
	}

	/**
	* Returns the visual menu component for adding to the scene.
	*/
	public function getView():ContextMenu
	{
		return _menu;
	}

	// ========================================================================
	// DISPOSE - v1.1
	// ========================================================================
	/**
	* Properly dispose the manager.
	* Unsubscribes from all Impulsys events to prevent memory leaks.
	*/
	public function dispose():Void
	{
		if (_isDisposed) return;
		_isDisposed = true;
		
		// Unsubscribe from all impulses
		Impulsys.removeImpulse(EventType.CONTEXT_MENU_ACTION, onMenuAction);
		Impulsys.removeImpulse(EventType.CLOSE_CONTEXT_MENU, onCloseContextMenu);
		Impulsys.removeImpulse(EventType.NODE_RIGHT_CLICKED, onNodeRightClick);
		Impulsys.removeImpulse(EventType.WIRE_RIGHT_CLICKED, onWireRightClick);
		Impulsys.removeImpulse(EventType.PORT_RIGHT_CLICKED, onPortRightClick);
		Impulsys.removeImpulse(EventType.CANVAS_RIGHT_CLICKED, onCanvasRightClick);
		
		// Clear references
		if (_menu != null)
		{
			_menu.hide();
			_menu = null;
		}
		_editor = null;
		_assembly = null;
		_settingsPanel = null;
		_contextTargetId = null;
		_isNameTakenGlobally = null;
	}

	// ========================================================================
	// HANDLERS: Triggered by Impulsys
	// ========================================================================
	private function onCanvasRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		resetMenu();
		buildAtomMenu(impulse.data.x, impulse.data.y);
		_menu.show(impulse.data.x, impulse.data.y);
	}

	private function onNodeRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;
		
		var view:NodeView = impulse.data.view;
		_contextTargetId = impulse.data.id;
		
		// Selection logic on right-click
		// If clicked on unselected node - reset selection and select only this one
		if (!_editor.isSelected(_contextTargetId))
		{
			// Node not selected: reset all (nodes + wires) and select this node
			_editor.deselectAll();
			_editor.selectNode(_contextTargetId, view);
		}
		else 
		{
			// FIX: Node is ALREADY selected.
			// We keep node selection (for group delete to work),
			// but clear wire selection to avoid confusion.
			_editor.clearWireSelection();
		}
		
		resetMenu();
		var nodeCount = _editor.getSelectedNodeCount();
		var wireCount = _editor.getSelectedWireIds().length;
		
		// --- DELETE OPTIONS ---
		if (wireCount > 0)
		{
			_menu.addItem("Delete Selected (" + nodeCount + " nodes, " + wireCount + " wires)", "DELETE_ALL_SELECTED", {});
			_menu.addItem("——————", "SEP");
		}
		
		// Determine type of selected objects
		var typeName = "Nodes";
		var allAssemblies = true;
		var allAtoms = true;
		for (id in _editor.getSelectedNodeIds())
		{
			var atom = _assembly.internalAtoms.get(id);
			if (atom != null)
			{
				if (Std.isOfType(atom, Assembly)) allAtoms = false;
				else allAssemblies = false;
			}
		}
		if (allAssemblies) typeName = "Assemblies";
		else if (allAtoms) typeName = "Atoms";
		else typeName = "Nodes";
		
		if (nodeCount == 1) typeName = typeName.substr(0, typeName.length - 1);
		_menu.addItem("Delete Selected " + typeName + " (" + nodeCount + ")", "DELETE_SELECTED_ATOMS", {});
		
		// --- GROUP OPTION ---
		if (nodeCount >= 2 && _settingsPanel.allowAssembly)
		{
			_menu.addItem("——————", "SEP");
			_menu.addItem("Group Selected Atoms (" + nodeCount + ")", "GROUP_ATOMS", {});
		}
		_menu.show(impulse.data.x, impulse.data.y);
	}

	private function onWireRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;
		
		resetMenu();
		var wireCount:Int = Std.int(impulse.data.ids.length);
		var nodeCount = _editor.getSelectedNodeCount();
		
		if (nodeCount > 0)
		{
			_menu.addItem("Delete Selected (" + nodeCount + " nodes, " + wireCount + " wires)", "DELETE_ALL_SELECTED", {});
			_menu.addItem("——————", "SEP");
		}
		
		var label = (wireCount > 1) ? "Delete Selected Wires (" + wireCount + ")" : "Delete Wire";
		_menu.addItem(label, "DELETE_WIRES", {ids: impulse.data.ids});
		_menu.show(impulse.data.x, impulse.data.y);
	}

	private function onPortRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;
		
		resetMenu();
		_menu.addItem('Delete Port "${impulse.data.portName}"', "REMOVE_PORT", {name: impulse.data.portName});
		_menu.show(impulse.data.x, impulse.data.y);
	}

	// ========================================================================
	// ACTIONS: Menu Item Clicked
	// ========================================================================
	private function onMenuAction(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		_menu.hide();
		
		if (impulse == null || impulse.data == null || impulse.data.action == null) return;
		
		var action:String = Std.string(impulse.data.action);
		var data = impulse.data.data;
		var x = impulse.data.x;
		var y = impulse.data.y;
		
		switch (action)
		{
			case "DELETE_ALL_SELECTED":
				var macrocom = new MacroCommand();
				var nodeIds = _editor.getSelectedNodeIds();
				for (id in nodeIds) macrocom.addCommand(new DeleteAtomCommand(_assembly.blueprint, _assembly, id));
				var wireIds = _editor.getSelectedWireIds();
				if (wireIds.length > 0) macrocom.addCommand(new DeleteWiresCommand(_assembly.blueprint, _assembly, wireIds));
				UndoManager.getInstance().executeAndStore(macrocom);
				_editor.deselectAll();
				return;
				
			case "DELETE_SELECTED_ATOMS":
				_editor.deleteSelectedNodes();
				_contextTargetId = null;
				return;
				
			case "DELETE_ATOM":
				// This case remains for compatibility or single deletion
				if (_editor.getSelectedNodeCount() > 0)
				{
					_editor.deleteSelectedNodes();
				}
				_contextTargetId = null;
				return;
				
			case "DELETE_WIRES":
				var cmd = new DeleteWiresCommand(_assembly.blueprint, _assembly, data.ids);
				UndoManager.getInstance().executeAndStore(cmd);
				return;
				
			case "GROUP_ATOMS":
				if (_settingsPanel.allowAssembly) groupSelectedToAssembly();
				return;
				
			case "ADD_PORT":
				if (data != null && data.type != null)
				{
					var cmd = new AddPortCommand(_assembly, data.type);
					UndoManager.getInstance().executeAndStore(cmd);
				}
				return;
				
			case "REMOVE_PORT":
				if (data != null && data.name != null)
				{
					var cmd = new RemovePortCommand(_assembly, data.name);
					UndoManager.getInstance().executeAndStore(cmd);
				}
				return;
		}
		
		// Adding an atom (Action: "ADD_ATOM")
		if (action == "ADD_ATOM")
		{
			if (data != null && data.typeId != null)
			{
				_editor.createAtom(data.typeId, x, y);
			}
		}
	}

	private function onCloseContextMenu(i:Impulse):Void
	{
		if (_isDisposed) return;
		_menu.hide();
	}

	// ========================================================================
	// BUILDERS
	// ========================================================================
	private function resetMenu():Void
	{
		_menu.hide();
		// Clear menu
		_menu.clear();
	}

	private function buildAtomMenu(x:Float, y:Float):Void
	{
		var ids = AtomRegistry.getAllIds();
		ids.sort(function(a, b) return Reflect.compare(a, b));
		var currentBpId:String = (_assembly != null && _assembly.blueprint != null) ? _assembly.blueprint.id : null;
		
		for (id in ids)
		{
			if (id == currentBpId) continue;
			var bp = AtomRegistry.get(id);
			if (bp != null) _menu.addItem("Add " + bp.name, "ADD_ATOM", {typeId: id});
		}
		
		_menu.addItem("——————", "SEP");
		// Используем полный путь core.types.ContactType на всякий случай, хотя импорт уже добавлен
		_menu.addItem("Add Input Port", "ADD_PORT", {type: core.types.ContactType.INPUT});
		_menu.addItem("Add Output Port", "ADD_PORT", {type: core.types.ContactType.OUTPUT});
	}

	/**
	* Group selected atoms into a new Assembly.
	*
	* v1.3 FIX: Passes _isNameTakenGlobally to GroupAtomsCommand to ensure
	* the newly created assembly receives a globally unique display name.
	*
	* v1.2 FIX: Now uses UndoManager.executeAndStore() instead of direct cmd.execute().
	* This ensures Topology Guard is activated via lockTopology(), preventing
	* race conditions with audio drivers during grouping operations.
	*/
	private function groupSelectedToAssembly():Void
	{
		var selectedIds = _editor.getSelectedNodeIds();
		if (selectedIds.length < 1) return;
		
		var cmd = new GroupAtomsCommand(_assembly.blueprint, _assembly, selectedIds, _isNameTakenGlobally);
		
		// v1.2 FIX: Use UndoManager to activate Topology Guard
		UndoManager.getInstance().executeAndStore(cmd);
		_editor.deselectAll();
	}
}