package ui.contextmenu.data;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU ENTRY PROVIDER                                   ║
 * ║          (Interface for menu content providers)                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 *   Interface for classes that supply menu entries to the context menu.      ║
 *  Different providers handle different content sources:                      ║
 *    - EditorCommandsProvider: Cut/Copy/Paste/Undo/Redo commands              ║
 *    - AtomLibraryProvider: Built-in atoms from AtomRegistry                  ║
 *    - AssemblyLibraryProvider: User-created assemblies                       ║
 * ║                                                                           
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuEntryProvider (Interface)                                      │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Methods:                                                     │  │  ║
 * ║  │  │  - getEntries() → Array<MenuEntry>                            │  │  ║
 * ║  │  │  - getCategoryId() → String                                   │  │  ║
 * ║  │  │  - supportsSearch() → Bool                                    │  │  ║
 * ║  │  │  - filter(query: String) → Array<MenuEntry>                   │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  ─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
interface MenuEntryProvider
{
    /**
     * Get all menu entries from this provider.
     * 
     * @return Array of MenuEntry instances
     */
    function getEntries():Array<MenuEntry>;
    
    /**
     * Get the category ID this provider belongs to.
     * 
     * @return Category ID (e.g., "editor", "atoms", "assemblies")
     */
    function getCategoryId():String;
    
    /**
     * Check if this provider supports text search filtering.
     * 
     * @return true if filter() should be called, false to skip
     */
    function supportsSearch():Bool;
    
    /**
     * Filter entries by search query.
     * 
     * @param query Search text (case-insensitive)
     * @return Filtered array of matching entries
     */
    function filter(query:String):Array<MenuEntry>;
}