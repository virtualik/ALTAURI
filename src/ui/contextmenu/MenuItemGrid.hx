package ui.contextmenu;

import openfl.display.Sprite;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.DisplayMode;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU ITEM GRID                                        ║
 * ║          (Grid layout for atom/assembly entries)                          ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 *                                                                            ║
 * ║  Grid layout container for MenuItem instances in GRID mode.               ║
 *  Arranges items in N columns with automatic row wrapping.                   ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuItemGrid (Sprite)                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌────────┐ ┌────────┐ ┌────────┐                                  │  ║
 * ║  │  │ [Icon] │ │ [Icon] │ │ [Icon] │  ← 3 columns                      │  
 * ║  │  │ Label  │ │ Label  │ │ Label  │                                  │  ║
 * ║  │  ────────┘ └────────┘ └────────┘                                  │  ║
 * ║  │  ┌────────┐ ┌──────── ┌────────┐                                  │  ║
 * ║  │  │ [Icon] │ │ [Icon] │ │ [Icon] │                                  │  ║
 * ║  │  │ Label  │ │ Label  │ │ Label  │                                  │  ║
 * ║  │  ────────┘ └────────┘ └────────┘                                  │  ║
 * ║  │                                                                     │  ║
 *   │  Columns: 3 (configurable)                                          │  ║
 *   │  Item size: 100×80px                                                │  
 * ║  │  Spacing: 5px                                                       │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class MenuItemGrid extends Sprite
{
    /** Callback when an item is clicked. */
    public var onItemClick:MenuEntry -> Void;
    
    /** Array of menu items. */
    private var _items:Array<MenuItem>;
    
    /** Number of columns. */
    private var _columns:Int;
    
    /** Item spacing. */
    private static inline var SPACING:Float = 5.0;
    
    /** Item dimensions (must match MenuItem GRID mode). */
    private static inline var ITEM_WIDTH:Float = 100.0;
    private static inline var ITEM_HEIGHT:Float = 80.0;
    
    /**
     * Create a new menu item grid.
     * 
     * @param columns Number of columns (default: 3)
     */
    public function new(?columns:Int = 3)
    {
        super();
        _items = [];
        _columns = columns != null ? columns : 3;
    }
    
    /**
     * Set entries and rebuild the grid.
     * 
     * @param entries Array of menu entries to display
     */
    public function setEntries(entries:Array<MenuEntry>):Void
    {
        clear();
        
        var xPos:Float = 0;
        var yPos:Float = 0;
        var colIndex:Int = 0;
        
        for (entry in entries)
        {
            var item = new MenuItem(entry, DisplayMode.GRID);
            item.x = xPos;
            item.y = yPos;
            item.onClick = onItemClicked;
            addChild(item);
            _items.push(item);
            
            colIndex++;
            if (colIndex >= _columns)
            {
                colIndex = 0;
                xPos = 0;
                yPos += ITEM_HEIGHT + SPACING;
            }
            else
            {
                xPos += ITEM_WIDTH + SPACING;
            }
        }
    }
    
    /**
     * Handle item click.
     */
    private function onItemClicked(entry:MenuEntry):Void
    {
        if (onItemClick != null)
        {
            onItemClick(entry);
        }
    }
    
    /**
     * Clear all items.
     */
    public function clear():Void
    {
        for (item in _items)
        {
            if (item.parent != null) item.parent.removeChild(item);
        }
        _items = [];
    }
    
    /**
     * Get total grid height.
     */
    public function getGridHeight():Float
    {
        if (_items.length == 0) return 0;
        var rows = Math.ceil(_items.length / _columns);
        return rows * ITEM_HEIGHT + (rows - 1) * SPACING;
    }
    
    /**
     * Get total grid width.
     */
    public function getGridWidth():Float
    {
        var cols = Math.min(_items.length, _columns);
        return cols * ITEM_WIDTH + (cols - 1) * SPACING;
    }
    
    /**
     * Dispose grid.
     */
    public function dispose():Void
    {
        clear();
        onItemClick = null;
    }
}