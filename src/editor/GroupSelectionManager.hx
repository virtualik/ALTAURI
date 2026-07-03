package editor;

/**
 * GROUP SELECTION MANAGER v1.0
 * Pure data class for managing lists of selected IDs.
 * 
 * Does NOT depend on graphics (OpenFL) — works only with data.
 * Used by SelectionManager for node/wire selection tracking.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   GroupSelectionManager                                                 │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Data Storage:                                                  │   │
 * │   │  - _selectedNodes:Map<String, Bool>  → Node IDs                 │   │
 * │   │  - _selectedWires:Array<String>      → Wire IDs                 │   │
 * │   │                                                                 │   │
 * │   │  Node Operations:                                               │   │
 * │   │  - addNode(id)                                                  │   │
 * │   │  - removeNode(id)                                               │   │
 * │   │  - hasNode(id) → Bool                                           │   │
 * │   │  - toggleNode(id) → Bool                                        │   │
 * │   │  - clearNodes()                                                 │   │
 * │   │  - getNodeIds() → Array<String>                                 │   │
 * │   │                                                                 │   │
 * │   │  Wire Operations:                                               │   │
 * │   │  - addWire(id)                                                  │   │
 * │   │  - removeWire(id)                                               │   │
 * │   │  - hasWire(id) → Bool                                           │   │
 * │   │  - clearWires()                                                 │   │
 * │   │  - getWireIds() → Array<String>                                 │   │
 * │   │                                                                 │   │
 * │   │  Global Operations:                                             │   │
 * │   │  - clear()           → Clear all selection                      │   │
 * │   │  - setNodes(ids)     → Set node selection                       │   │
 * │   │  - setWires(ids)     → Set wire selection                       │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var selection = new GroupSelectionManager();                          │
 * │   selection.addNode("id_abc123");                                       │
 * │   selection.toggleNode("id_def456");                                    │
 * │   var selectedIds = selection.getNodeIds();                             │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class GroupSelectionManager
{
    // =========================================================================
    // DATA STORAGE
    // =========================================================================
    private var _selectedNodes:Map<String, Bool>;
    private var _selectedWires:Array<String>;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new()
    {
        _selectedNodes = new Map();
        _selectedWires = [];
    }
    
    // =========================================================================
    // NODE OPERATIONS
    // =========================================================================
    /**
     * Add a node to selection.
     * @param id Node ID to select
     */
    public function addNode(id:String):Void
    {
        if (!_selectedNodes.exists(id))
        {
            _selectedNodes.set(id, true);
        }
    }
    
    /**
     * Remove a node from selection.
     * @param id Node ID to deselect
     */
    public function removeNode(id:String):Void
    {
        _selectedNodes.remove(id);
    }
    
    /**
     * Check if a node is selected.
     * @param id Node ID to check
     * @return true if selected
     */
    public function hasNode(id:String):Bool
    {
        return _selectedNodes.exists(id);
    }
    
    /**
     * Toggle node selection state.
     * @param id Node ID to toggle
     * @return new selection state (true = selected, false = deselected)
     */
    public function toggleNode(id:String):Bool
    {
        if (hasNode(id))
        {
            removeNode(id);
            return false;
        }
        else
        {
            addNode(id);
            return true;
        }
    }
    
    /**
     * Clear all node selections.
     */
    public function clearNodes():Void
    {
        _selectedNodes = new Map();
    }
    
    /**
     * Get all selected node IDs.
     * @return Array of selected node IDs
     */
    public function getNodeIds():Array<String>
    {
        return [for (id in _selectedNodes.keys()) id];
    }
    
    /**
     * Get count of selected nodes.
     * @return Number of selected nodes
     */
    public function getNodeCount():Int
    {
        var count = 0;
        for (key in _selectedNodes.keys()) count++;
        return count;
    }
    
    // =========================================================================
    // WIRE OPERATIONS
    // =========================================================================
    /**
     * Add a wire to selection.
     * @param id Wire ID to select
     */
    public function addWire(id:String):Void
    {
        if (_selectedWires.indexOf(id) == -1)
        {
            _selectedWires.push(id);
        }
    }
    
    /**
     * Remove a wire from selection.
     * @param id Wire ID to deselect
     */
    public function removeWire(id:String):Void
    {
        _selectedWires.remove(id);
    }
    
    /**
     * Check if a wire is selected.
     * @param id Wire ID to check
     * @return true if selected
     */
    public function hasWire(id:String):Bool
    {
        return _selectedWires.indexOf(id) != -1;
    }
    
    /**
     * Clear all wire selections.
     */
    public function clearWires():Void
    {
        _selectedWires = [];
    }
    
    /**
     * Get all selected wire IDs.
     * @return Array of selected wire IDs (copy)
     */
    public function getWireIds():Array<String>
    {
        return _selectedWires.copy();
    }
    
    /**
     * Get count of selected wires.
     * @return Number of selected wires
     */
    public function getWireCount():Int
    {
        return _selectedWires.length;
    }
    
    // =========================================================================
    // GLOBAL OPERATIONS
    // =========================================================================
    /**
     * Clear all selection (nodes + wires).
     */
    public function clear():Void
    {
        clearNodes();
        clearWires();
    }
    
    /**
     * Select all specified node IDs.
     * @param ids Array of node IDs to select
     */
    public function setNodes(ids:Array<String>):Void
    {
        clearNodes();
        for (id in ids) addNode(id);
    }
    
    /**
     * Select all specified wire IDs.
     * @param ids Array of wire IDs to select
     */
    public function setWires(ids:Array<String>):Void
    {
        clearWires();
        for (id in ids) addWire(id);
    }
}