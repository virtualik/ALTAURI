package ui.contextmenu;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import ui.contextmenu.data.MenuCategory;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     CATEGORY ITEM                                         ║
 * ║          (Single category button in sidebar)                              ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 *   Visual representation of a MenuCategory in the sidebar.                  ║
 *  Displays icon + label, highlights when selected.                           ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ─────────────────────────────────────────────────────────────────────┐  ║
 *   │  CategoryItem (Sprite)                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 *   │  │  Visual:                                                      │  │  ║
 *   │  │  ┌─────────────────────────────────────────────────────────┐  │  │  ║
 * ║  │  │  │  [Icon] Category Name                                    │  │  │  ║
 *   │  │  │  ← 150px wide, 40px tall                                │  │  │  ║
 * ║  │  │  └─────────────────────────────────────────────────────────┘  │  │  ║
 * ║  │  │                                                             │  │  ║
 *   │  │  States:                                                      │  │  ║
 * ║  │  │  - Normal: bg=0x2a2a3a, text=0xAAAAAA                        │  │  ║
 * ║  │  │  - Hover: bg=0x3a3a4a, text=0xFFFFFF                         │  │  ║
 * ║  │  │  - Selected: bg=0x00AAFF, text=0xFFFFFF, left border accent  │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  ─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class CategoryItem extends Sprite
{
    /** Category data model. */
    public var category:MenuCategory;
    
    /** Callback when item is clicked. */
    public var onClick:MenuCategory -> Void;
    
    /** Is this category currently selected? */
    public var isSelected:Bool = false;
    
    /** Background sprite. */
    private var _bg:Sprite;
    
    /** Label text field. */
    private var _label:TextField;
    
    /** Fixed dimensions. */
    private static inline var ITEM_WIDTH:Float = 150.0;
    private static inline var ITEM_HEIGHT:Float = 40.0;
    
    /** Colors. */
    private static inline var COLOR_NORMAL_BG:Int = 0x2a2a3a;
    private static inline var COLOR_HOVER_BG:Int = 0x3a3a4a;
    private static inline var COLOR_SELECTED_BG:Int = 0x00AAFF;
    private static inline var COLOR_NORMAL_TEXT:Int = 0xAAAAAA;
    private static inline var COLOR_SELECTED_TEXT:Int = 0xFFFFFF;
    private static inline var COLOR_ACCENT:Int = 0x00FF88;
    
    /**
     * Create a new category item.
     * 
     * @param category Category data model
     */
    public function new(category:MenuCategory)
    {
        super();
        this.category = category;
        buildUI();
    }
    
    /**
     * Build the visual UI elements.
     */
    private function buildUI():Void
    {
        // Background
        _bg = new Sprite();
        addChild(_bg);
        
        // Label
        _label = new TextField();
        _label.defaultTextFormat = new TextFormat("_sans", 13, COLOR_NORMAL_TEXT, true);
        _label.text = category.displayName;
        _label.width = ITEM_WIDTH - 20;
        _label.height = ITEM_HEIGHT;
        _label.x = 10;
        _label.y = 0;
        _label.selectable = false;
        _label.mouseEnabled = false;
        addChild(_label);
        
        // Interaction
        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
        addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        addEventListener(MouseEvent.CLICK, onClickHandler);
        
        drawNormal();
    }
    
    /**
     * Set selection state and update visual.
     * 
     * @param selected true = selected, false = normal
     */
    public function setSelected(selected:Bool):Void
    {
        isSelected = selected;
        if (selected)
        {
            drawSelected();
        }
        else
        {
            drawNormal();
        }
    }
    
    /**
     * Draw normal state background.
     */
    private function drawNormal():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_NORMAL_BG);
        _bg.graphics.drawRect(0, 0, ITEM_WIDTH, ITEM_HEIGHT);
        _bg.graphics.endFill();
        _label.textColor = COLOR_NORMAL_TEXT;
    }
    
    /**
     * Draw hover state background.
     */
    private function drawHover():Void
    {
        if (isSelected) return; // Don't override selected state
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_HOVER_BG);
        _bg.graphics.drawRect(0, 0, ITEM_WIDTH, ITEM_HEIGHT);
        _bg.graphics.endFill();
    }
    
    /**
     * Draw selected state background with accent border.
     */
    private function drawSelected():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_SELECTED_BG);
        _bg.graphics.drawRect(0, 0, ITEM_WIDTH, ITEM_HEIGHT);
        _bg.graphics.endFill();
        
        // Left accent border
        _bg.graphics.beginFill(COLOR_ACCENT);
        _bg.graphics.drawRect(0, 0, 4, ITEM_HEIGHT);
        _bg.graphics.endFill();
        
        _label.textColor = COLOR_SELECTED_TEXT;
    }
    
    /**
     * Mouse over handler.
     */
    private function onMouseOver(e:MouseEvent):Void
    {
        drawHover();
    }
    
    /**
     * Mouse out handler.
     */
    private function onMouseOut(e:MouseEvent):Void
    {
        if (isSelected)
        {
            drawSelected();
        }
        else
        {
            drawNormal();
        }
    }
    
    /**
     * Click handler.
     */
    private function onClickHandler(e:MouseEvent):Void
    {
        if (onClick != null)
        {
            onClick(category);
        }
    }
    
    /**
     * Get item width.
     */
    public function getItemWidth():Float { return ITEM_WIDTH; }
    
    /**
     * Get item height.
     */
    public function getItemHeight():Float { return ITEM_HEIGHT; }
}