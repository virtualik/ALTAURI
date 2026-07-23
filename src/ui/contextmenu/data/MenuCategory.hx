package ui.contextmenu.data;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU CATEGORY                                         ║
 * ║          (Data model for sidebar category item)                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Represents a single category in the context menu sidebar.                ║
 * ║  Categories group menu entries by purpose:                                ║
 * ║  - Editor commands (Cut/Copy/Paste/Undo/Redo)                             ║
 * ║  - Atom library (Button, LED, Toggle, etc.)                               ║
 * ║  - Assembly library (user-created custom assemblies)                      ║
 * ║  - Recent (last 5 used actions)                                           ║
 * ║                                                                           ║
 * ║ Architecture:                                                             ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuCategory                                                       │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Fields:                                                      │  │  ║
 * ║  │  │  - id: String        → Unique identifier (e.g., "editor")     │  │  ║
 * ║  │  │  - displayName: String → Human-readable label                 │  │  ║
 * ║  │  │  - icon: String      → Icon identifier for sidebar            │  │  ║
 * ║  │  │  - order: Int        → Sort order in sidebar (lower = first)  │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class MenuCategory
{
    /** Unique category identifier. */
    public var id:String;
    
    /** Human-readable display name for sidebar. */
    public var displayName:String;
    
    /** Icon identifier (maps to assets/icons/menu/). */
    public var icon:String;
    
    /** Sort order in sidebar (lower values appear first). */
    public var order:Int;
    
    /**
     * Create a new menu category.
     * 
     * @param id          Unique identifier (e.g., "editor", "atoms", "assemblies")
     * @param displayName Human-readable label for sidebar
     * @param icon        Icon identifier for visual representation
     * @param order       Sort order (0 = first, 1 = second, etc.)
     */
    public function new(id:String, displayName:String, ?icon:String = null, ?order:Int = 0)
    {
        this.id = id;
        this.displayName = displayName;
        this.icon = (icon != null) ? icon : id;
        this.order = order;
    }
    
    /**
     * Built-in category constants for standard menu sections.
     * 
     * ─────────────────────────────────────────────────────────────────────
     * │  CATEGORY_ID  │ DISPLAY_NAME      │ ORDER │ PURPOSE                │
     * ├───────────────┼───────────────────┼───────┼────────────────────────┤
     * │  "recent"     │ Recent            │ 0     │ Last 5 actions         │
     * │  "editor"     │ Editor            │ 1     │ Cut/Copy/Paste/Undo    │
     * │  "atoms"      │ Atoms             │ 2     │ Built-in atom library  │
     * │  "assemblies" │ Assemblies        │ 3     │ User-created assemblies│
     * └───────────────┴───────────────────┴───────┴────────────────────────┘
     */
    public static inline var RECENT:String = "recent";
    public static inline var EDITOR:String = "editor";
    public static inline var ATOMS:String = "atoms";
    public static inline var ASSEMBLIES:String = "assemblies";
    
    /**
     * Get all built-in categories in display order.
     * 
     * @return Array of MenuCategory instances sorted by order field
     */
    public static function getBuiltinCategories():Array<MenuCategory>
    {
        return [
            new MenuCategory(RECENT, "Recent", "clock", 0),
            new MenuCategory(EDITOR, "Editor", "edit", 1),
            new MenuCategory(ATOMS, "Atoms", "atom", 2),
            new MenuCategory(ASSEMBLIES, "Assemblies", "assembly", 3)
        ];
    }
}