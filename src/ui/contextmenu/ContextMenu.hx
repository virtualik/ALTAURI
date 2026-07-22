package ui.contextmenu;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import ui.contextmenu.data.MenuCategory;
import ui.contextmenu.data.MenuEntry;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     CONTEXT MENU v2.0                                     ║
 * ║          (Two-panel context menu with categories and content)             ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Main context menu container. Combines CategorySidebar (left) and         ║
 *  ContentPanel (right) into a unified two-panel menu.                        ║
 * ║                                                                           ║
 *   Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  ContextMenu (Sprite)                                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌────────────┬──────────────────────────────────────────────────┐  │  ║
 * ║  │  │ Category   │  [SearchBar]                                     │  │  ║
 *   │  │ Sidebar    ├──────────────────────────────────────────────────┤  │  ║
 * ║  │  │            │  [RecentSection] (if Recent)                     │  │  ║
 * ║  │  │ ► Editor   ├──────────────────────────────────────────────────  │  ║
 * ║  │  │   Atoms    │  [ContentPanel]                                  │  │  
 * ║  │  │   Assembl. │    ┌────┐ ┌────┐ ┌────┐                         │  │  ║
 * ║  │  │            │    │Btn │ │LED │ │Tog │  3 columns              │  │  ║
 * ║  │  │            │    └────┘ ────┘ └────┘                         │  │  ║
 * ║  │  └────────────┴──────────────────────────────────────────────────┘  │  ║
 *   │                                                                     │  ║
 * ║  │  Sidebar width: 150px                                               │  ║
 *   │  Content width: 450px                                               │  ║
 * ║  │  Total width: 600px                                                 │  ║
 *   │  Height: Auto (based on content)                                    │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Behavior:                                                                ║
 *     - show(x, y): Position menu with smart bounds checking                 ║
 *     - hide(): Hide menu and remove stage listener                          ║
 * ║    - Click outside: Auto-hide                                             ║
 * ║    - Category selection: Updates content panel                            ║
 * ║    - Entry click: Emits CONTEXT_MENU_ACTION via Impulsys                  ║
 * ║                                                                           ║
 * ═══════════════════════════════════════════════════════════════════════════╝
 */
class ContextMenu extends Sprite
{
    /** Sidebar with categories. */
    private var _sidebar:CategorySidebar;
    
    /** Content panel with entries. */
    private var _contentPanel:ContentPanel;
    
    /** Current categories. */
    private var _categories:Array<MenuCategory>;
    
    /** Current entries per category. */
    private var _entriesByCategory:Map<String, Array<MenuEntry>>;
    
    /** Currently selected category. */
    private var _selectedCategory:MenuCategory;
    
    /** Spawn position. */
    private var _spawnX:Float = 0;
    private var _spawnY:Float = 0;
    
    /** Dimensions. */
    private static inline var SIDEBAR_WIDTH:Float = 150.0;
    private static inline var CONTENT_WIDTH:Float = 450.0;
    private static inline var TOTAL_WIDTH:Float = SIDEBAR_WIDTH + CONTENT_WIDTH;
    private static inline var MIN_HEIGHT:Float = 200.0;
    private static inline var MAX_HEIGHT:Float = 500.0;
    
    /**
     * Create a new context menu.
     */
    public function new()
    {
        super();
        _entriesByCategory = new Map();
        buildUI();
    }
    
    /**
     * Build the menu UI.
     */
    private function buildUI():Void
    {
        // Background
        graphics.lineStyle(1, 0x444455);
        graphics.beginFill(0x1a1a24);
        graphics.drawRoundRect(0, 0, TOTAL_WIDTH, MIN_HEIGHT, 8, 8);
        graphics.endFill();
        
        // Sidebar
        _sidebar = new CategorySidebar([]);
        _sidebar.x = 0;
        _sidebar.y = 0;
        _sidebar.onCategorySelected = onCategorySelected;
        addChild(_sidebar);
        
        // Content panel
        _contentPanel = new ContentPanel();
        _contentPanel.x = SIDEBAR_WIDTH;
        _contentPanel.y = 0;
        _contentPanel.onEntryClick = onEntryClicked;
        addChild(_contentPanel);
    }
    
    /**
     * Set categories and entries for the menu.
     * 
     * @param categories Array of categories to display in sidebar
     * @param entriesByCategory Map of category ID to entries
     */
    public function setData(categories:Array<MenuCategory>, entriesByCategory:Map<String, Array<MenuEntry>>):Void
    {
        _categories = categories;
        _entriesByCategory = entriesByCategory;
        
        // Rebuild sidebar
        while (_sidebar.numChildren > 0)
        {
            _sidebar.removeChildAt(0);
        }
        _sidebar = new CategorySidebar(categories);
        _sidebar.x = 0;
        _sidebar.y = 0;
        _sidebar.onCategorySelected = onCategorySelected;
        addChild(_sidebar);
        
        // Select first category by default
        if (categories.length > 0)
        {
            selectCategory(categories[0]);
        }
    }
    
    /**
     * Select a category and update content panel.
     */
    private function selectCategory(category:MenuCategory):Void
    {
        _selectedCategory = category;
        var entries = _entriesByCategory.get(category.id);
        if (entries == null) entries = [];
        _contentPanel.updateContent(category, entries);
        
        // Resize menu to fit content
        resizeToFitContent();
    }
    
    /**
     * Handle category selection from sidebar.
     */
    private function onCategorySelected(category:MenuCategory):Void
    {
        selectCategory(category);
    }
    
    /**
     * Handle entry click from content panel.
     */
    private function onEntryClicked(entry:MenuEntry):Void
    {
        // Emit action via Impulsys
        core.logic.Impulsys.quickEmit(core.logic.EventType.CONTEXT_MENU_ACTION, {
            action: entry.actionId,
            data: entry.data,
            x: _spawnX,
            y: _spawnY
        });
        
        hide();
    }
    
    /**
     * Resize menu to fit content.
     */
    private function resizeToFitContent():Void
    {
        var contentHeight = _contentPanel.getPanelHeight();
        var totalHeight = Math.max(MIN_HEIGHT, Math.min(MAX_HEIGHT, contentHeight));
        
        graphics.clear();
        graphics.lineStyle(1, 0x444455);
        graphics.beginFill(0x1a1a24);
        graphics.drawRoundRect(0, 0, TOTAL_WIDTH, totalHeight, 8, 8);
        graphics.endFill();
    }
    
    /**
     * Show menu at specified position with smart bounds checking.
     * 
     * @param x Requested X position
     * @param y Requested Y position
     */
    public function show(x:Float, y:Float):Void
    {
        _spawnX = x;
        _spawnY = y;
        
        // Smart positioning
        var stageW = stage != null ? stage.stageWidth : 1920;
        var stageH = stage != null ? stage.stageHeight : 1080;
        var bounds = MenuBoundsCalculator.clamp(x, y, TOTAL_WIDTH, height, stageW, stageH);
        
        this.x = bounds.x;
        this.y = bounds.y;
        visible = true;
        
        if (stage != null)
        {
            stage.addEventListener(MouseEvent.MOUSE_DOWN, onStageClick);
        }
    }
    
    /**
     * Hide menu.
     */
    public function hide():Void
    {
        visible = false;
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onStageClick);
        }
    }
    
    /**
     * Handle stage click (close menu if clicked outside).
     */
    private function onStageClick(e:MouseEvent):Void
    {
        if (!this.hitTestPoint(e.stageX, e.stageY))
        {
            hide();
        }
    }
    
    /**
     * Get spawn position.
     */
    public function getSpawnPosition():{x:Float, y:Float}
    {
        return { x: _spawnX, y: _spawnY };
    }
    
    /**
     * Clear all data.
     */
    public function clear():Void
    {
        _categories = [];
        _entriesByCategory = new Map();
        _selectedCategory = null;
    }
    
    /**
     * Dispose menu.
     */
    public function dispose():Void
    {
        hide();
        _sidebar.dispose();
        _contentPanel.dispose();
        _categories = null;
        _entriesByCategory = null;
    }
}