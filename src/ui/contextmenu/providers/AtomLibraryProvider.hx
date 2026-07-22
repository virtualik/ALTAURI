package ui.contextmenu.providers;

import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.MenuEntryProvider;
import ui.contextmenu.data.MenuCategory;
import library.AtomRegistry;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     ATOM LIBRARY PROVIDER                                 ║
 * ║          (Provides built-in atoms for context menu)                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Provides all registered atoms from AtomRegistry:                         ║
 *    - Native atoms (Button, LED, Toggle, etc.)                               ║
 *    - Active drivers (SignalGenerator, MiniAudioAtom, etc.)                  ║
 *    - Custom assemblies (user-created)                                       ║
 * ║                                                                           ║
 * ║  Architecture:                                                            
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  AtomLibraryProvider (implements MenuEntryProvider)                 │  ║
 *   │                                                                     │  ║
 *   │  Methods:                                                           │  
 * ║  │  - getEntries() → Array<MenuEntry>                                  │  ║
 * ║  │  - getCategoryId() → String ("atoms")                               │  ║
 * ║  │  - supportsSearch() → Bool (true)                                   │  ║
 * ║  │  - filter(query) → Array<MenuEntry>                                 │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 *   Usage:                                                                   ║
 * ║  ───────                                                                  ║
 * ║  var provider = new AtomLibraryProvider(currentBpId);                     ║
 *   var entries = provider.getEntries();                                     ║
 * ║                                                                           ║
 * ═══════════════════════════════════════════════════════════════════════════╝
 */
class AtomLibraryProvider implements MenuEntryProvider
{
    /** Current blueprint ID to exclude from list. */
    private var _currentBpId:String;
    
    /**
     * Create a new atom library provider.
     * 
     * @param currentBpId Current blueprint ID to exclude (prevents self-reference)
     */
    public function new(?currentBpId:String = null)
    {
        _currentBpId = currentBpId;
    }
    
    /**
     * Get all atom library entries.
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
            if (bp != null)
            {
                entries.push(MenuEntry.createAtom(id, bp.name));
            }
        }
        
        return entries;
    }
    
    /**
     * Get the category ID this provider belongs to.
     * 
     * @return Category ID ("atoms")
     */
    public function getCategoryId():String
    {
        return MenuCategory.ATOMS;
    }
    
    /**
     * Check if this provider supports text search filtering.
     * 
     * @return true (atom library supports search)
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