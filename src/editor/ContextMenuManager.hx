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
import ui.contextmenu.ContextMenu;
import ui.contextmenu.data.MenuCategory;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.RecentMenuTracker;
import ui.contextmenu.providers.EditorCommandsProvider;
import ui.contextmenu.providers.AtomLibraryProvider;
import ui.contextmenu.providers.AssemblyLibraryProvider;
import ui.SettingsPanel;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     CONTEXT MENU MANAGER v2.0                             ║
 * ║          (New generation context menu with categories)                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Responsible for creating and handling editor context menus.              ║
 * ║Listens to impulses from NodeEditor and manages the menu UI.               ║
 * ║                                                                           ║
 * ║ Architecture:                                                             ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  ContextMenuManager                                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  Event Subscriptions:                                               │  ║
 * ║  │  - CONTEXT_MENU_ACTION   → onMenuAction() (execute commands)        │  ║
 * ║  │  - CLOSE_CONTEXT_MENU    → onCloseContextMenu() (hide menu)         │  ║
 * ║  │  - NODE_RIGHT_CLICKED    → onNodeRightClick() (node menu)           │  ║
 * ║  │  - WIRE_RIGHT_CLICKED    → onWireRightClick() (wire menu)           │  ║
 * ║  │  - PORT_RIGHT_CLICKED    → onPortRightClick() (port menu)           │  ║
 * ║  │  - CANVAS_RIGHT_CLICKED  → onCanvasRightClick() (atom menu)         │  ║
 * ║  │                                                                     │  ║
 * ║  │  Menu Actions:                                                      │  ║
 * ║  │  - ADD_ATOM             → NodeEditor.createAtom()                   │  ║
 * ║  │  - DELETE_ALL_SELECTED  → MacroCommand[DeleteAtom+DeleteWires]      │  ║
 * ║  │  - DELETE_SELECTED_ATOMS→ NodeEditor.deleteSelectedNodes()          │  ║
 * ║  │  - DELETE_WIRES         → DeleteWiresCommand                        │  ║
 * ║  │  - GROUP_ATOMS          → GroupAtomsCommand (via UndoManager)       │  ║
 * ║  │  - ADD_PORT             → AddPortCommand                            │  ║
 * ║  │  - REMOVE_PORT          → RemovePortCommand                         │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║ v2.0 Changes:                                                             ║
 * ║  - Uses new ContextMenu v2.0 with category sidebar + content panel        ║
 * ║ - Providers: EditorCommandsProvider, AtomLibraryProvider,                 ║
 * ║    AssemblyLibraryProvider                                                ║
 * ║  - Recent section via RecentMenuTracker                                   ║
 * ║  - Smart positioning via MenuBoundsCalculator                             ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class ContextMenuManager
{
	/** The new context menu instance. */
	private var _menu:ContextMenu;

	/** Current editor reference. */
	private var _editor:NodeEditor;

	/** Current assembly reference. */
	private var _assembly:Assembly;

	/** Reference to settings (needed for allowAssembly check). */
	private var _settingsPanel:SettingsPanel;

	/** Temporary state for passing data to action. */
	private var _contextTargetId:String = null;

	/** Flag to protect against repeated dispose. */
	private var _isDisposed:Bool = false;

	/** Global name uniqueness checker for grouping operations. */
	private var _isNameTakenGlobally:(String, ?String) -> Bool;

	/**
	 * Create a new context menu manager.
	 *
	 * @param settingsPanel Settings panel reference
	 */
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
	 * @param isNameTakenGlobally Callback to check name uniqueness globally
	 */
	public function setContext(
		editor:NodeEditor,
		assembly:Assembly,
		?isNameTakenGlobally:(String, ?String) -> Bool
	):Void
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
	// DISPOSE
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

	/**
	 * Handle canvas right-click (add atom menu).
	 * Opens menu with ATOMS category selected by default.
	 */
	private function onCanvasRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		resetMenu();
		// Set preferred category BEFORE setData so it's applied during menu build
		_menu.setPreferredCategory(MenuCategory.ATOMS);
		buildAtomMenu(impulse.data.x, impulse.data.y);
		applySidebarPosition();
		_menu.show(impulse.data.x, impulse.data.y);
	}

	/**
	 * Handle node right-click (node context menu).
	 */
	private function onNodeRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;

		var view:NodeView = impulse.data.view;
		_contextTargetId = impulse.data.id;

		// Selection logic on right-click
		if (!_editor.isSelected(_contextTargetId))
		{
			// Node not selected: reset all and select only this one
			_editor.deselectAll();
			_editor.selectNode(_contextTargetId, view);
		}
		else
		{
			// Node already selected: keep node selection, clear wires
			_editor.clearWireSelection();
		}

		resetMenu();

		var nodeCount = _editor.getSelectedNodeCount();
		var wireCount = _editor.getSelectedWireIds().length;

		// Build menu data
		var categories = MenuCategory.getBuiltinCategories();
		var entriesByCategory = new Map<String, Array<MenuEntry>>();

		// Editor commands
		var editorProvider = new EditorCommandsProvider(
			nodeCount,
			wireCount,
			_settingsPanel.allowAssembly
		);
		entriesByCategory.set(MenuCategory.EDITOR, editorProvider.getEntries());

		// Atom library
		var currentBpId = (_assembly != null && _assembly.blueprint != null)
		? _assembly.blueprint.id
		: null;
		var atomProvider = new AtomLibraryProvider(currentBpId);
		entriesByCategory.set(MenuCategory.ATOMS, atomProvider.getEntries());

		// Assembly library
		var assemblyProvider = new AssemblyLibraryProvider(currentBpId);
		entriesByCategory.set(MenuCategory.ASSEMBLIES, assemblyProvider.getEntries());

		// Set preferred category BEFORE setData so it's applied during menu build
		_menu.setPreferredCategory(MenuCategory.EDITOR);
		// Set menu data
		_menu.setData(categories, entriesByCategory);
		applySidebarPosition();
		_menu.show(impulse.data.x, impulse.data.y);
	}

	/**
	 * Handle wire right-click (wire context menu).
	 */
	private function onWireRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;

		resetMenu();

		var wireCount:Int = Std.int(impulse.data.ids.length);
		var nodeCount = _editor.getSelectedNodeCount();

		var categories = MenuCategory.getBuiltinCategories();
		var entriesByCategory = new Map<String, Array<MenuEntry>>();

		// Editor commands
		var editorProvider = new EditorCommandsProvider(
			nodeCount,
			wireCount,
			_settingsPanel.allowAssembly
		);
		entriesByCategory.set(MenuCategory.EDITOR, editorProvider.getEntries());

		// Set preferred category BEFORE setData so it's applied during menu build
		_menu.setPreferredCategory(MenuCategory.EDITOR);
		_menu.setData(categories, entriesByCategory);
		applySidebarPosition();
		_menu.show(impulse.data.x, impulse.data.y);
	}

	/**
	 * Handle port right-click (port context menu).
	 */
	private function onPortRightClick(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		if (impulse == null || impulse.data == null) return;

		resetMenu();

		var categories = MenuCategory.getBuiltinCategories();
		var entriesByCategory = new Map<String, Array<MenuEntry>>();

		// Remove port command
		var removeEntry = MenuEntry.createCommand(
			"REMOVE_PORT",
			'Delete Port "${impulse.data.portName}"',
		{ name: impulse.data.portName }
		);
		entriesByCategory.set(MenuCategory.EDITOR, [removeEntry]);

		// Set preferred category BEFORE setData so it's applied during menu build
		_menu.setPreferredCategory(MenuCategory.EDITOR);
		_menu.setData(categories, entriesByCategory);
		applySidebarPosition();
		_menu.show(impulse.data.x, impulse.data.y);
	}

	// ========================================================================
	// ACTIONS: Menu Item Clicked
	// ========================================================================

	/**
	 * Handle menu action (item clicked).
	 */
	private function onMenuAction(impulse:Impulse):Void
	{
		if (_isDisposed) return;
		_menu.hide();

		if (impulse == null || impulse.data == null || impulse.data.action == null) return;

		var action:String = Std.string(impulse.data.action);
		var data = impulse.data.data;
		var x = impulse.data.x;
		var y = impulse.data.y;

		// Track recent action
		var recentEntry = new MenuEntry(
			"recent_" + action,
			action,
			"recent",
			MenuCategory.RECENT,
			action,
			data
		);
		RecentMenuTracker.getInstance().record(recentEntry);

		switch (action)
		{
			case "DELETE_ALL_SELECTED":
				var macrocom = new MacroCommand();
				var nodeIds = _editor.getSelectedNodeIds();
				for (id in nodeIds)
				{
					macrocom.addCommand(new DeleteAtomCommand(
						_assembly.blueprint, _assembly, id
					));
				}
				var wireIds = _editor.getSelectedWireIds();
				if (wireIds.length > 0)
				{
					macrocom.addCommand(new DeleteWiresCommand(
											_assembly.blueprint, _assembly, wireIds
										));
				}
				UndoManager.getInstance().executeAndStore(macrocom);
				_editor.deselectAll();
				return;

			case "DELETE_SELECTED_ATOMS":
				_editor.deleteSelectedNodes();
				_contextTargetId = null;
				return;

			case "DELETE_ATOM":
				if (_editor.getSelectedNodeCount() > 0)
				{
					_editor.deleteSelectedNodes();
				}
				_contextTargetId = null;
				return;

			case "DELETE_WIRES":
				var cmd = new DeleteWiresCommand(
					_assembly.blueprint, _assembly, data.ids
				);
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

	/**
	 * Handle close context menu request.
	 */
	private function onCloseContextMenu(i:Impulse):Void
	{
		if (_isDisposed) return;
		_menu.hide();
	}

	// ========================================================================
	// BUILDERS
	// ========================================================================

	/**
	 * Reset menu state.
	 */
	private function resetMenu():Void
	{
		_menu.hide();
		_menu.clear();
	}

	/**
	 * Build atom menu (canvas right-click).
	 *
	 * @param x Mouse X position
	 * @param y Mouse Y position
	 */
	private function buildAtomMenu(x:Float, y:Float):Void
	{
		var categories = MenuCategory.getBuiltinCategories();
		var entriesByCategory = new Map<String, Array<MenuEntry>>();

		// Atom library
		var currentBpId = (_assembly != null && _assembly.blueprint != null)
		? _assembly.blueprint.id
		: null;
		var atomProvider = new AtomLibraryProvider(currentBpId);
		entriesByCategory.set(MenuCategory.ATOMS, atomProvider.getEntries());

		// Assembly library
		var assemblyProvider = new AssemblyLibraryProvider(currentBpId);
		entriesByCategory.set(MenuCategory.ASSEMBLIES, assemblyProvider.getEntries());

		// Editor commands (port options)
		var editorEntries = [
			MenuEntry.createCommand(
				"ADD_PORT",
				"Add Input Port",
		{ type: core.types.ContactType.INPUT }
			),
		MenuEntry.createCommand(
			"ADD_PORT",
			"Add Output Port",
		{ type: core.types.ContactType.OUTPUT }
		)
		];
		entriesByCategory.set(MenuCategory.EDITOR, editorEntries);

		_menu.setData(categories, entriesByCategory);
	}

	/**
	 * Group selected atoms into a new Assembly.
	 *
	 * Uses UndoManager.executeAndStore() to activate Topology Guard.
	 */
	private function groupSelectedToAssembly():Void
	{
		var selectedIds = _editor.getSelectedNodeIds();
		if (selectedIds.length < 1) return;

		var cmd = new GroupAtomsCommand(
			_assembly.blueprint,
			_assembly,
			selectedIds,
			_isNameTakenGlobally
		);
		UndoManager.getInstance().executeAndStore(cmd);
		_editor.deselectAll();
	}

	/**
	* Apply sidebar position from settings to menu.
	* Called before showing menu.
	*/
	private function applySidebarPosition():Void
	{
		if (_menu != null && _settingsPanel != null)
		{
			_menu.setSidebarPosition(_settingsPanel.contextMenuSidebarPosition);
		}
	}
}