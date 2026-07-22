package ui.contextmenu;

import openfl.display.Sprite;
import ui.contextmenu.data.MenuCategory;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     CATEGORY SIDEBAR                                      ║
 * ║          (Left panel with category buttons)                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Left panel of the context menu containing category buttons.              ║
 *  Categories are displayed vertically in order.                              ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  CategorySidebar (Sprite)                                           │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Visual:                                                      │  │  ║
 * ║  │  │  ┌─────────────────────────────────────────────────────────┐  │  │  ║
 * ║  │  │  │  [Recent]                                               │  │  │  ║
 *   │  │  │  [Editor]  ← Selected (blue bg + green accent)          │  │  │  ║
 * ║  │  │  │  [Atoms]                                                │  │  │  
 * ║  │  │  │  [Assemblies]                                           │  │  │  ║
 * ║  │  │  └─────────────────────────────────────────────────────────┘  │  │  ║
 * ║  │  │                                                             │  │  ║
 * ║  │  │  Width: 150px (fixed)                                       │  │  ║
 * ║  │  │  Height: Auto (based on category count × 40px)              │  │  
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  ─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class CategorySidebar extends Sprite
{
    /** Callback when a category is selected. */
    public var onCategorySelected:MenuCategory -> Void;
    
    /** Array of category items. */
    private var _items:Array<CategoryItem>;
    
    /** Currently selected category. */
    private var _selectedCategory:MenuCategory;
    
    /** Fixed width. */
    private static inline var SIDEBAR_WIDTH:Float = 150.0;
    
    /**
     * Create a new category sidebar.
     * 
     * @param categories Array of categories to display
     */
    public function new(categories:Array<MenuCategory>)
    {
        super();
        _items = [];
        buildUI(categories);
    }
    
    /**
     * Build the sidebar UI with category buttons.
     * 
     * @param categories Array of categories to display
     */
    private function buildUI(categories:Array<MenuCategory>):Void
    {
        // Sort categories by order field
        categories.sort(function(a, b) return a.order - b.order);
        
        var yPos:Float = 0;
        for (category in categories)
        {
            var item = new CategoryItem(category);
            item.y = yPos;
            item.onClick = onCategoryClick;
            addChild(item);
            _items.push(item);
            yPos += item.getItemHeight();
        }
        
        // Draw background
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, SIDEBAR_WIDTH, yPos);
        graphics.endFill();
        
        // Right border line
        graphics.lineStyle(1, 0x333344);
        graphics.moveTo(SIDEBAR_WIDTH, 0);
        graphics.lineTo(SIDEBAR_WIDTH, yPos);
    }
    
    /**
     * Handle category click.
     * 
     * @param category Clicked category
     */
    private function onCategoryClick(category:MenuCategory):Void
    {
        // Deselect previous
        if (_selectedCategory != null)
        {
            for (item in _items)
            {
                if (item.category.id == _selectedCategory.id)
                {
                    item.setSelected(false);
                    break;
                }
            }
        }
        
        // Select new
        _selectedCategory = category;
        for (item in _items)
        {
            if (item.category.id == category.id)
            {
                item.setSelected(true);
                break;
            }
        }
        
        // Notify
        if (onCategorySelected != null)
        {
            onCategorySelected(category);
        }
    }
    
    /**
     * Get sidebar width.
     */
    public function getSidebarWidth():Float { return SIDEBAR_WIDTH; }
    
    /**
     * Get sidebar height.
     */
    public function getSidebarHeight():Float { return height; }
    
    /**
     * Cleanup.
     */
    public function dispose():Void
    {
        _items = [];
        _selectedCategory = null;
        onCategorySelected = null;
    }
}