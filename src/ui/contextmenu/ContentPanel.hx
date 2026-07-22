package ui.contextmenu;

import openfl.display.Sprite;
import ui.contextmenu.data.MenuCategory;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.RecentMenuTracker;
import ui.contextmenu.DisplayMode;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     CONTENT PANEL                                         ║
 * ║          (Right panel with entries based on selected category)            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Right panel of the context menu. Displays entries based on the           ║
 *  currently selected category:                                               ║
 *    - Recent: RecentSection with last 5 actions                              ║
 *    - Editor: List of editor commands (Cut/Copy/Paste/Undo/Redo/etc.)        
 *    - Atoms: Grid of atom types from AtomRegistry                            ║
 *    - Assemblies: Grid of user-created assemblies                            ║
 * ║                                                                           ║
 *   Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  ContentPanel (Sprite)                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  
 * ║  │  │  [SearchBar]                                                  │  │  ║
 * ║  │  ├───────────────────────────────────────────────────────────────┤  │  
 * ║  │  │  [RecentSection] (if Recent category)                         │  │  ║
 * ║  │  ├───────────────────────────────────────────────────────────────┤  │  ║
 * ║  │  │  [MenuItemGrid or List]                                       │  │  ║
 * ║  │  │  ┌────┐ ┌────┐ ┌────┐                                        │  │  ║
 * ║  │  │  │Btn │ │LED │ │Tog │  3 columns                             │  │  ║
 * ║  │  │  └────┘ └──── └────┘                                        │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  Width: 450px (fixed)                                               │  ║
 * ║  │  Height: Auto (based on content)                                    │  ║
 * ║  ─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class ContentPanel extends Sprite
{
    /** Callback when an entry is clicked. */
    public var onEntryClick:MenuEntry -> Void;
    
    /** Search bar. */
    private var _searchBar:SearchBar;
    
    /** Recent section (shown only for Recent category). */
    private var _recentSection:RecentSection;
    
    /** Grid for atoms/assemblies. */
    private var _grid:MenuItemGrid;
    
    /** List container for editor commands. */
    private var _listContainer:Sprite;
    
    /** Current category. */
    private var _currentCategory:MenuCategory;
    
    /** Current entries. */
    private var _currentEntries:Array<MenuEntry>;
    
    /** Dimensions. */
    private static inline var PANEL_WIDTH:Float = 450.0;
    private static inline var SEARCH_HEIGHT:Float = 35.0;
    private static inline var RECENT_HEIGHT:Float = 60.0;
    private static inline var PADDING:Float = 10.0;
    
    /**
     * Create a new content panel.
     */
    public function new()
    {
        super();
        _currentEntries = [];
        buildUI();
    }
    
    /**
     * Build the panel UI.
     */
    private function buildUI():Void
    {
        // Background
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, PANEL_WIDTH, 400);
        graphics.endFill();
        
        // Search bar
        _searchBar = new SearchBar(PANEL_WIDTH - PADDING * 2);
        _searchBar.x = PADDING;
        _searchBar.y = PADDING;
        _searchBar.onSearch = onSearch;
        addChild(_searchBar);
        
        // Recent section (hidden by default)
        _recentSection = new RecentSection(PANEL_WIDTH - PADDING * 2);
        _recentSection.x = PADDING;
        _recentSection.y = PADDING + SEARCH_HEIGHT + PADDING;
        _recentSection.onEntryClick = onEntryClicked;
        _recentSection.visible = false;
        addChild(_recentSection);
        
        // Grid
        _grid = new MenuItemGrid(3);
        _grid.x = PADDING;
        _grid.onItemClick = onEntryClicked;
        addChild(_grid);
        
        // List container
        _listContainer = new Sprite();
        _listContainer.x = PADDING;
        addChild(_listContainer);
    }
    
    /**
     * Update panel content based on category and entries.
     * 
     * @param category Selected category
     * @param entries Entries to display
     */
    public function updateContent(category:MenuCategory, entries:Array<MenuEntry>):Void
    {
        _currentCategory = category;
        _currentEntries = entries;
        
        // Clear existing content
        _grid.clear();
        while (_listContainer.numChildren > 0)
        {
            _listContainer.removeChildAt(0);
        }
        
        // Show/hide recent section
        if (category.id == MenuCategory.RECENT)
        {
            _recentSection.visible = true;
            _recentSection.refresh();
            _grid.y = PADDING + SEARCH_HEIGHT + PADDING + RECENT_HEIGHT + PADDING;
            _listContainer.y = _grid.y;
        }
        else
        {
            _recentSection.visible = false;
            _grid.y = PADDING + SEARCH_HEIGHT + PADDING;
            _listContainer.y = _grid.y;
        }
        
        // Display entries based on category
        if (category.id == MenuCategory.EDITOR)
        {
            displayAsList(entries);
        }
        else
        {
            displayAsGrid(entries);
        }
    }
    
    /**
     * Display entries as a list (for Editor commands).
     */
    private function displayAsList(entries:Array<MenuEntry>):Void
    {
        _grid.visible = false;
        _listContainer.visible = true;
        
        var yPos:Float = 0;
        for (entry in entries)
        {
            var item = new MenuItem(entry, DisplayMode.LIST);
            item.y = yPos;
            item.onClick = onEntryClicked;
            _listContainer.addChild(item);
            yPos += item.getItemHeight();
        }
    }
    
    /**
     * Display entries as a grid (for Atoms/Assemblies).
     */
    private function displayAsGrid(entries:Array<MenuEntry>):Void
    {
        _grid.visible = true;
        _listContainer.visible = false;
        _grid.setEntries(entries);
    }
    
    /**
     * Handle search text change.
     */
    private function onSearch(query:String):Void
    {
        if (query == null || query.length == 0)
        {
            updateContent(_currentCategory, _currentEntries);
            return;
        }
        
        var filtered:Array<MenuEntry> = [];
        var lowerQuery = query.toLowerCase();
        for (entry in _currentEntries)
        {
            if (entry.displayName.toLowerCase().indexOf(lowerQuery) != -1)
            {
                filtered.push(entry);
            }
        }
        
        if (_currentCategory.id == MenuCategory.EDITOR)
        {
            displayAsList(filtered);
        }
        else
        {
            displayAsGrid(filtered);
        }
    }
    
    /**
     * Handle entry click.
     */
    private function onEntryClicked(entry:MenuEntry):Void
    {
        if (onEntryClick != null)
        {
            onEntryClick(entry);
        }
    }
    
    /**
     * Get panel width.
     */
    public function getPanelWidth():Float { return PANEL_WIDTH; }
    
    /**
     * Get panel height (approximate).
     */
    public function getPanelHeight():Float
    {
        var height = PADDING + SEARCH_HEIGHT + PADDING;
        if (_currentCategory != null && _currentCategory.id == MenuCategory.RECENT)
        {
            height += RECENT_HEIGHT + PADDING;
        }
        if (_grid.visible)
        {
            height += _grid.getGridHeight();
        }
        else if (_listContainer.visible)
        {
            height += _listContainer.height;
        }
        return height;
    }
    
    /**
     * Dispose panel.
     */
    public function dispose():Void
    {
        _searchBar.dispose();
        _recentSection.dispose();
        _grid.dispose();
        onEntryClick = null;
    }
}