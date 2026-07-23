package ui.contextmenu.providers;

import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.MenuEntryProvider;
import ui.contextmenu.data.MenuCategory;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     EDITOR COMMANDS PROVIDER                              ║
 * ║          (Provides editor commands for context menu)                      ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Provides standard editor commands:                                       ║
 * ║  - Delete Selected (nodes + wires)                                        ║
 * ║  - Delete Selected Atoms                                                  ║
 * ║  - Delete Selected Wires                                                  ║
 * ║  - Group Selected Atoms                                                   ║
 * ║  - Add Input Port                                                         ║
 * ║  - Add Output Port                                                        ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  EditorCommandsProvider (implements MenuEntryProvider)              │  ║
 * ║  │                                                                     │  ║
 * ║  │  Methods:                                                           │  ║
 * ║  │  - getEntries() → Array<MenuEntry>                                  │  ║
 * ║  │  - getCategoryId() → String ("editor")                              │  ║
 * ║  │  - supportsSearch() → Bool (true)                                   │  ║
 * ║  │  - filter(query) → Array<MenuEntry>                                 │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Usage:                                                                   ║
 * ║  ───────                                                                  ║
 * ║  var provider = new EditorCommandsProvider(nodeCount, wireCount,          ║
 * ║                                         allowAssembly);                   ║
 * ║ var entries = provider.getEntries();                                      ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class EditorCommandsProvider implements MenuEntryProvider
{
	/** Number of selected nodes. */
	private var _nodeCount:Int;
	/** Number of selected wires. */
	private var _wireCount:Int;
	/** Whether assembly creation is allowed. */
	private var _allowAssembly:Bool;
	/** Whether to include Add Port commands. */
	private var _includeAddPort:Bool;
	/**
	* Create a new editor commands provider.
	*
	* @param nodeCount       Number of selected nodes
	* @param wireCount       Number of selected wires
	* @param allowAssembly   Whether assembly creation is allowed
	* @param includeAddPort  Whether to include Add Input/Output Port commands
	*/
	public function new(nodeCount:Int, wireCount:Int, allowAssembly:Bool, ?includeAddPort:Bool = true)
	{
		_nodeCount = nodeCount;
		_wireCount = wireCount;
		_allowAssembly = allowAssembly;
		_includeAddPort = includeAddPort;
	}
	/**
	* Get all editor command entries.
	*
	* Entries are filtered based on current selection state:
	* - Delete commands appear only when there is something to delete
	* - Group command appears only when 2+ nodes are selected and assembly is allowed
	* - Port commands are included only if _includeAddPort is true
	*
	* @return Array of MenuEntry instances
	*/
	public function getEntries():Array<MenuEntry>
	{
		var entries:Array<MenuEntry> = [];
// ── Delete options (only if there is something to delete) ──
		if (_nodeCount > 0 || _wireCount > 0)
		{
			if (_nodeCount > 0 && _wireCount > 0)
			{
// Both nodes and wires selected — combined delete
				entries.push(MenuEntry.createCommand(
					"DELETE_ALL_SELECTED",
					"Delete Selected (" + _nodeCount + " nodes, " + _wireCount + " wires)"
				));
			}
			else if (_nodeCount > 0)
			{
// Only nodes selected
				var typeName = (_nodeCount == 1) ? "Node" : "Nodes";
				entries.push(MenuEntry.createCommand(
								 "DELETE_SELECTED_ATOMS",
								 "Delete " + typeName + " (" + _nodeCount + ")"
							 ));
			}
// Wires-only delete (always shown when wires exist, even alongside nodes)
			if (_wireCount > 0)
			{
				var label = (_wireCount > 1)
							? "Delete Wires (" + _wireCount + ")"
							: "Delete Wire";
				entries.push(MenuEntry.createCommand("DELETE_WIRES", label));
			}
		}
// ── Group option (only when 2+ nodes selected and assembly allowed) ──
		if (_nodeCount >= 2 && _allowAssembly)
		{
			entries.push(MenuEntry.createCommand(
							 "GROUP_ATOMS",
							 "Group Selected Atoms (" + _nodeCount + ")"
						 ));
		}
// ── Port options (only if includeAddPort is true) ──
		if (_includeAddPort)
		{
			entries.push(MenuEntry.createCommand(
							 "ADD_PORT",
							 "Add Input Port",
			{ type: core.types.ContactType.INPUT }
						 ));
			entries.push(MenuEntry.createCommand(
							 "ADD_PORT",
							 "Add Output Port",
			{ type: core.types.ContactType.OUTPUT }
						 ));
		}
		return entries;
	}
	/**
	* Get the category ID this provider belongs to.
	*
	* @return Category ID ("editor")
	*/
	public function getCategoryId():String
	{
		return MenuCategory.EDITOR;
	}
	/**
	* Check if this provider supports text search filtering.
	*
	* @return true (editor commands support search)
	*/
	public function supportsSearch():Bool
	{
		return true;
	}
	/**
	* Filter entries by search query.
	*
	* @param query Search text (case-insensitive)
	* @return Filtered array of matching entries
	*/
	public function filter(query:String):Array<MenuEntry>
	{
		var filtered:Array<MenuEntry> = [];
		var lowerQuery = query.toLowerCase();
		for (entry in getEntries())
		{
			if (entry.displayName.toLowerCase().indexOf(lowerQuery) != -1)
			{
				filtered.push(entry);
			}
		}
		return filtered;
	}
}