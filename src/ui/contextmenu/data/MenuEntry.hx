package ui.contextmenu.data;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU ENTRY                                            ║
 * ║          (Data model for a single menu item)                              ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 *   Represents a single actionable item in the context menu content panel.   ║
 *  Entries can be:                                                            ║
 *    - Commands (Cut, Copy, Paste, Undo, Redo)                                ║
 *    - Atom types (Button, LED, Toggle, SignalGenerator)                      ║
 *    - Assembly types (user-created custom assemblies)                        ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuEntry                                                          │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 *   │  │  Fields:                                                      │  │  ║
 * ║  │  │  - id: String        → Unique identifier                      │  │  ║
 * ║  │  │  - displayName: String → Human-readable label                 │  │  ║
 * ║  │  │  - icon: String      → Icon identifier (maps to assets)       │  │  ║
 * ║  │  │  - categoryId: String  → Parent category ID                   │  │  ║
 * ║  │  │  - actionId: String    → Action identifier for Impulsys       │  │  ║
 * ║  │  │  - data: Dynamic     → Optional payload for action            │  │  ║
 * ║  │  │  - shortcut: String  → Keyboard shortcut hint (future)        │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ═══════════════════════════════════════════════════════════════════════════╝
 */
class MenuEntry
{
    /** Unique entry identifier. */
    public var id:String;
    
    /** Human-readable display name. */
    public var displayName:String;
    
    /** Icon identifier (maps to assets/icons/). */
    public var icon:String;
    
    /** Parent category ID (links to MenuCategory.id). */
    public var categoryId:String;
    
    /** Action identifier for Impulsys event payload. */
    public var actionId:String;
    
    /** Optional data payload passed with action. */
    public var data:Dynamic;
    
    /** Keyboard shortcut hint (reserved for future hotkey service). */
    public var shortcut:String;
    
    /**
     * Create a new menu entry.
     * 
     * @param id          Unique identifier
     * @param displayName Human-readable label
     * @param icon        Icon identifier
     * @param categoryId  Parent category ID
     * @param actionId    Action identifier for Impulsys
     * @param data        Optional payload
     * @param shortcut    Keyboard shortcut hint (optional)
     */
    public function new(
        id:String,
        displayName:String,
        ?icon:String = null,
        ?categoryId:String = null,
        ?actionId:String = null,
        ?data:Dynamic = null,
        ?shortcut:String = null
    )
    {
        this.id = id;
        this.displayName = displayName;
        this.icon = (icon != null) ? icon : id;
        this.categoryId = categoryId;
        this.actionId = (actionId != null) ? actionId : id;
        this.data = data;
        this.shortcut = shortcut;
    }
    
    /**
     * Factory: Create an editor command entry.
     * 
     * @param actionId Command action ID (e.g., "DELETE_ALL_SELECTED")
     * @param displayName Human-readable label
     * @param data Optional command payload
     * @return MenuEntry configured for editor command
     */
    public static function createCommand(actionId:String, displayName:String, ?data:Dynamic):MenuEntry
    {
        return new MenuEntry(
            "cmd_" + actionId,
            displayName,
            "command",
            MenuCategory.EDITOR,
            actionId,
            data
        );
    }
    
    /**
     * Factory: Create an atom library entry.
     * 
     * @param typeId Atom type ID from AtomRegistry
     * @param displayName Human-readable atom name
     * @return MenuEntry configured for atom creation
     */
    public static function createAtom(typeId:String, displayName:String):MenuEntry
    {
        return new MenuEntry(
            "atom_" + typeId,
            displayName,
            typeId,
            MenuCategory.ATOMS,
            "ADD_ATOM",
            { typeId: typeId }
        );
    }
    
    /**
     * Factory: Create an assembly library entry.
     * 
     * @param typeId Assembly type ID from AtomRegistry
     * @param displayName Human-readable assembly name
     * @return MenuEntry configured for assembly creation
     */
    public static function createAssembly(typeId:String, displayName:String):MenuEntry
    {
        return new MenuEntry(
            "asm_" + typeId,
            displayName,
            "assembly",
            MenuCategory.ASSEMBLIES,
            "ADD_ATOM",
            { typeId: typeId }
        );
    }
}