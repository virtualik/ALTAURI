package ui.contextmenu;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;
import ui.contextmenu.data.MenuCategory;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.RecentMenuTracker;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     CONTENT PANEL                                         ║
 * ║          (Right panel with entries based on selected category)            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Right panel of the context menu. Displays entries based on the           ║
 * ║  currently selected category:                                             ║
 * ║  - Recent: RecentSection with last 5 actions                              ║
 * ║  - Editor: List of editor commands (Cut/Copy/Paste/Undo/Redo/etc.)        ║
 * ║  - Atoms: Grid of atom types from AtomRegistry                            ║
 * ║  - Assemblies: Grid of user-created assemblies                            ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  ContentPanel (Sprite)                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  [SearchBar]                                                  │  │  ║
 * ║  │  ├───────────────────────────────────────────────────────────────┤  │  ║
 * ║  │  │  [RecentSection] (if Recent category)                         │  │  ║
 * ║  │  ├───────────────────────────────────────────────────────────────┤  │  ║
 * ║  │  │  [MenuItemGrid or List]                                       │  │  ║
 * ║  │  │  ┌────┐ ┌────┐ ┌────┐                                         │  │  ║
 * ║  │  │  │Btn │ │LED │ │Tog │  3 columns                              │  │  ║
 * ║  │  │  └────┘ └────┘ └────┘                                         │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  Width: 450px (fixed)                                               │  ║
 * ║  │  Height: Auto (based on content)                                    │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class ContentPanel extends Sprite
{
    public var onEntryClick:MenuEntry -> Void;
    
    private var _searchBar:SearchBar;
    private var _recentSection:RecentSection;
    
    // NEW: Dedicated container for scrollable content
    private var _scrollContainer:Sprite;
    
    private var _grid:MenuItemGrid;
    private var _listContainer:Sprite;
    
    private var _currentCategory:MenuCategory;
    private var _currentEntries:Array<MenuEntry>;
    
    // Scroll state
    private var _scrollY:Float = 0;
    private var _maxScrollY:Float = 0;
    private var _scrollStep:Float = 20.0;
    
    private static inline var PANEL_WIDTH:Float = 450.0;
    private static inline var SEARCH_HEIGHT:Float = 35.0;
    private static inline var RECENT_HEIGHT:Float = 60.0;
    private static inline var PADDING:Float = 10.0;
    private static inline var MAX_CONTENT_HEIGHT:Float = 400.0;
    
    public function new()
    {
        super();
        _currentEntries = [];
        buildUI();
    }
    
    private function buildUI():Void
    {
        // 1. Background (covers entire panel)
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, PANEL_WIDTH, MAX_CONTENT_HEIGHT);
        graphics.endFill();
        
        // Enable mouse interaction to block events from passing through to Editor
        mouseEnabled = true;
        mouseChildren = true;
        addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
        
        // 2. Search bar (Fixed at top, NEVER scrolls)
        _searchBar = new SearchBar(PANEL_WIDTH - PADDING * 2);
        _searchBar.x = PADDING;
        _searchBar.y = PADDING;
        _searchBar.onSearch = onSearch;
        addChild(_searchBar);
        
        // 3. Recent section (Fixed below search, NEVER scrolls)
        _recentSection = new RecentSection(PANEL_WIDTH - PADDING * 2);
        _recentSection.x = PADDING;
        _recentSection.y = PADDING + SEARCH_HEIGHT + PADDING;
        _recentSection.onEntryClick = onEntryClicked;
        _recentSection.visible = false;
        addChild(_recentSection);
        
        // 4. Scroll Container (Holds ONLY the grid/list)
        _scrollContainer = new Sprite();
        _scrollContainer.x = PADDING;
        // Initial Y will be set in updateContent based on Recent visibility
        _scrollContainer.y = PADDING + SEARCH_HEIGHT + PADDING;
        addChild(_scrollContainer);
        
        // 5. Grid (4 columns) and List are children of _scrollContainer
        _grid = new MenuItemGrid(4);
        _grid.x = 0; // Relative to scroll container
        _grid.y = 0;
        _grid.onItemClick = onEntryClicked;
        _scrollContainer.addChild(_grid);
        
        _listContainer = new Sprite();
        _listContainer.x = 0; // Relative to scroll container
        _listContainer.y = 0;
        _scrollContainer.addChild(_listContainer);
    }

    public function updateContent(category:MenuCategory, entries:Array<MenuEntry>):Void
    {
        _currentCategory = category;
        _currentEntries = entries;
        _scrollY = 0; // Reset scroll on category change
        
        _grid.clear();
        while (_listContainer.numChildren > 0)
        {
            _listContainer.removeChildAt(0);
        }
        
        // Adjust scroll container Y based on Recent section visibility
        if (category.id == MenuCategory.RECENT)
        {
            _recentSection.visible = true;
            _recentSection.refresh();
            _scrollContainer.y = PADDING + SEARCH_HEIGHT + PADDING + RECENT_HEIGHT + PADDING;
        }
        else
        {
            _recentSection.visible = false;
            _scrollContainer.y = PADDING + SEARCH_HEIGHT + PADDING;
        }
        
        if (category.id == MenuCategory.EDITOR)
        {
            displayAsList(entries);
        }
        else
        {
            displayAsGrid(entries);
        }
        
        updateScrollBounds();
        applyScroll();
    }
    
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
    
    private function displayAsGrid(entries:Array<MenuEntry>):Void
    {
        _grid.visible = true;
        _listContainer.visible = false;
        _grid.setEntries(entries);
    }
    
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
        
        updateScrollBounds();
        applyScroll();
    }
    
    private function onEntryClicked(entry:MenuEntry):Void
    {
        if (onEntryClick != null)
        {
            onEntryClick(entry);
        }
    }
    
    // ========================================================================
    // SCROLL LOGIC
    // ========================================================================
    
    private function updateScrollBounds():Void
    {
        var contentHeight:Float = 0;
        if (_grid.visible)
        {
            contentHeight = _grid.getGridHeight();
        }
        else if (_listContainer.visible)
        {
            contentHeight = _listContainer.height;
        }
        
        // Visible height is the total panel height minus the Y offset of the scroll container
        var visibleHeight:Float = MAX_CONTENT_HEIGHT - _scrollContainer.y;
        
        _maxScrollY = Math.max(0, contentHeight - visibleHeight);
    }
    
    private function applyScroll():Void
    {
        // Clamp scroll value
        if (_scrollY < 0) _scrollY = 0;
        if (_scrollY > _maxScrollY) _scrollY = _maxScrollY;
        
        // Move content UP by scrollY (negative offset)
        var scrollOffset = -_scrollY;
        _grid.y = scrollOffset;
        _listContainer.y = scrollOffset;
        
        // Apply scrollRect ONLY to the scroll container.
        // This guarantees that content moving up (negative Y) is clipped 
        // exactly at the top edge of the container, which sits right below the Search Bar.
        var visibleHeight:Float = MAX_CONTENT_HEIGHT - _scrollContainer.y;
        _scrollContainer.scrollRect = new Rectangle(
            0, 
            0, 
            PANEL_WIDTH - (PADDING * 2), 
            visibleHeight
        );
    }
    
    private function onMouseWheel(e:MouseEvent):Void
    {
        // Stop propagation to prevent Editor from receiving the event
        e.stopPropagation();
        
        _scrollY -= e.delta * _scrollStep;
        applyScroll();
    }
    
    public function getPanelWidth():Float { return PANEL_WIDTH; }
    
    public function getPanelHeight():Float
    {
        return MAX_CONTENT_HEIGHT;
    }
    
    public function dispose():Void
    {
        removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
        _searchBar.dispose();
        _recentSection.dispose();
        _grid.dispose();
        onEntryClick = null;
    }
}