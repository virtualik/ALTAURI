package ui.contextmenu.providers;

import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.MenuEntryProvider;
import ui.contextmenu.data.MenuCategory;
import library.AtomRegistry;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     ASSEMBLY LIBRARY PROVIDER                             ║
 * ║          (Provides user-created assemblies for context menu)              ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Provides user-created assemblies (non-native blueprints):                ║
 *    - Custom assemblies saved to library                                     ║
 *    - Excludes native atoms                                                  ║
 *    - Excludes current blueprint (prevent self-reference)                    ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 *   ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  AssemblyLibraryProvider (implements MenuEntryProvider)             │  ║
 * ║  │                                                                     │  ║
 * ║  │  Methods:                                                           │  ║
 * ║  │  - getEntries() → Array<MenuEntry>                                  │  ║
 * ║  │  - getCategoryId() → String ("assemblies")                          │  ║
 * ║  │  - supportsSearch() → Bool (true)                                   │  
 * ║  │  - filter(query) → Array<MenuEntry>                                 │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Usage:                                                                   ║
 * ║  ───────                                                                  ║
 * ║  var provider = new AssemblyLibraryProvider(currentBpId);                 ║
 * ║  var entries = provider.getEntries();                                     ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class AssemblyLibraryProvider implements MenuEntryProvider
{
    /** Current blueprint ID to exclude from list. */
    private var _currentBpId:String;
    
    /**
     * Create a new assembly library provider.
     * 
     * @param currentBpId Current blueprint ID to exclude (prevent self-reference)
     */
    public function new(?currentBpId:String = null)
    {
        _currentBpId = currentBpId;
    }
    
    /**
     * Get all assembly library entries.
     * 
     * @return Array of MenuEntry instances
     */
    public function getEntries():Array<MenuEntry>
    {
        var entries:Array<MenuEntry> = [];
        var ids = AtomRegistry.getAllIds();
        ids.sort(function(a, b) return Reflect.compare(a, b));
        
        for (id in ids)
        {
            // Skip current blueprint (prevent self-reference)
            if (id == _currentBpId) continue;
            
            var bp = AtomRegistry.get(id);
            if (bp != null && !bp.isNative)
            {
                entries.push(MenuEntry.createAssembly(id, bp.name));
            }
        }
        
        return entries;
    }
    
    /**
     * Get the category ID this provider belongs to.
     * 
     * @return Category ID ("assemblies")
     */
    public function getCategoryId():String
    {
        return MenuCategory.ASSEMBLIES;
    }
    
    /**
     * Check if this provider supports text search filtering.
     * 
     * @return true (assembly library supports search)
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