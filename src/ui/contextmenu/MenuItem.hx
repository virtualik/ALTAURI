package ui.contextmenu;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import ui.contextmenu.data.MenuEntry;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU ITEM                                             ║
 * ║          (Single clickable entry in content panel)                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Visual representation of a MenuEntry in the content panel.               ║
 * ║  Supports two display modes:                                              ║
 * ║  - List mode (Editor commands): icon + label + shortcut, full width       ║
 * ║  - Grid mode (Atoms/Assemblies): icon + label, compact tile               ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuItem (Sprite)                                                  │  ║
 * ║  │                                                                     │  ║
 * ║  │  List mode (150px × 30px):                                          │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  [Icon] Label text                        [Shortcut]          │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  Grid mode (100px × 80px):                                          │  ║
 * ║  │  ┌────────┐                                                         │  ║
 * ║  │  │ [Icon] │                                                         │  ║
 * ║  │  └────────┘                                                         │  ║
 * ║  │   Label text                                                        │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  States:                                                                  ║
 * ║    - Normal: bg=0x222233, text=0xFFFFFF                                   ║
 * ║   - Hover: bg=0x334455, text=0x00AAFF                                     ║
 * ║   - Disabled: bg=0x1a1a24, text=0x555566                                  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class MenuItem extends Sprite
{
    /** Entry data model. */
    public var entry:MenuEntry;
    
    /** Callback when item is clicked. */
    public var onClick:MenuEntry -> Void;
    
    /** Display mode. */
    public var displayMode:DisplayMode;
    
    /** Background sprite. */
    private var _bg:Sprite;
    
    /** Icon placeholder (text-based for now). */
    private var _iconField:TextField;
    
    /** Label text field. */
    private var _labelField:TextField;
    
    /** Shortcut text field (list mode only). */
    private var _shortcutField:TextField;
    
    /** Dimensions. */
    private static inline var LIST_WIDTH:Float = 150.0;
    private static inline var LIST_HEIGHT:Float = 30.0;
    private static inline var GRID_WIDTH:Float = 100.0;
    private static inline var GRID_HEIGHT:Float = 80.0;
    private static inline var ICON_SIZE:Float = 32.0;
    
    /** Colors. */
    private static inline var COLOR_NORMAL_BG:Int = 0x222233;
    private static inline var COLOR_HOVER_BG:Int = 0x334455;
    private static inline var COLOR_NORMAL_TEXT:Int = 0xFFFFFF;
    private static inline var COLOR_HOVER_TEXT:Int = 0x00AAFF;
    private static inline var COLOR_SHORTCUT:Int = 0x888888;
    private static inline var COLOR_ICON:Int = 0x00AAFF;
    
    /**
     * Create a new menu item.
     * 
     * @param entry Entry data model
     * @param mode Display mode (LIST or GRID)
     */
    public function new(entry:MenuEntry, mode:DisplayMode = DisplayMode.LIST)
    {
        super();
        this.entry = entry;
        this.displayMode = mode;
        buildUI();
    }
    
    /**
     * Build the visual UI elements based on display mode.
     */
    private function buildUI():Void
    {
        _bg = new Sprite();
        addChild(_bg);
        
        _iconField = new TextField();
        _iconField.defaultTextFormat = new TextFormat("_sans", 16, COLOR_ICON);
        _iconField.text = getIconChar();
        _iconField.width = ICON_SIZE;
        _iconField.height = ICON_SIZE;
        _iconField.selectable = false;
        _iconField.mouseEnabled = false;
        addChild(_iconField);
        
        _labelField = new TextField();
        _labelField.defaultTextFormat = new TextFormat("_sans", 12, COLOR_NORMAL_TEXT);
        _labelField.text = entry.displayName;
        _labelField.selectable = false;
        _labelField.mouseEnabled = false;
        addChild(_labelField);
        
        if (displayMode == DisplayMode.LIST)
        {
            _shortcutField = new TextField();
            _shortcutField.defaultTextFormat = new TextFormat("_sans", 10, COLOR_SHORTCUT);
            _shortcutField.text = entry.shortcut != null ? entry.shortcut : "";
            _shortcutField.width = 50;
            _shortcutField.height = LIST_HEIGHT;
            _shortcutField.selectable = false;
            _shortcutField.mouseEnabled = false;
            addChild(_shortcutField);
            
            layoutList();
        }
        else
        {
            layoutGrid();
        }
        
        drawNormal();
        
        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
        addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        addEventListener(MouseEvent.CLICK, onClickHandler);
    }
    
    /**
     * Get icon character based on entry type.
     * TODO: Replace with PNG icons from assets/icons/
     */
    private function getIconChar():String
    {
        if (entry.categoryId == "editor")
        {
            switch (entry.actionId)
            {
                case "DELETE_ALL_SELECTED", "DELETE_SELECTED_ATOMS", "DELETE_WIRES": return "🗑";
                case "GROUP_ATOMS": return "📦";
                case "ADD_PORT": return "➕";
                case "REMOVE_PORT": return "➖";
                default: return "⚙";
            }
        }
        else if (entry.categoryId == "atoms" || entry.categoryId == "assemblies")
        {
            return "";
        }
        else if (entry.categoryId == "recent")
        {
            return "🕐";
        }
        return "•";
    }
    
    /**
     * Layout elements for list mode.
     */
    private function layoutList():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_NORMAL_BG);
        _bg.graphics.drawRect(0, 0, LIST_WIDTH, LIST_HEIGHT);
        _bg.graphics.endFill();
        
        _iconField.x = 5;
        _iconField.y = (LIST_HEIGHT - ICON_SIZE) / 2;
        
        _labelField.x = 40;
        _labelField.y = 0;
        _labelField.width = LIST_WIDTH - 100;
        _labelField.height = LIST_HEIGHT;
        
        _shortcutField.x = LIST_WIDTH - 55;
        _shortcutField.y = 0;
    }
    
    /**
     * Layout elements for grid mode.
     */
    private function layoutGrid():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_NORMAL_BG);
        _bg.graphics.drawRoundRect(0, 0, GRID_WIDTH, GRID_HEIGHT, 6, 6);
        _bg.graphics.endFill();
        
        _iconField.x = (GRID_WIDTH - ICON_SIZE) / 2;
        _iconField.y = 10;
        
        _labelField.x = 5;
        _labelField.y = ICON_SIZE + 15;
        _labelField.width = GRID_WIDTH - 10;
        _labelField.height = 30;
        
        var fmt = new TextFormat("_sans", 10, COLOR_NORMAL_TEXT, false, null, null, null, null, "center");
        _labelField.defaultTextFormat = fmt;
        _labelField.setTextFormat(fmt);
    }
    
    /**
     * Draw normal state.
     */
    private function drawNormal():Void
    {
        if (displayMode == DisplayMode.LIST)
        {
            _bg.graphics.clear();
            _bg.graphics.beginFill(COLOR_NORMAL_BG);
            _bg.graphics.drawRect(0, 0, LIST_WIDTH, LIST_HEIGHT);
            _bg.graphics.endFill();
        }
        else
        {
            _bg.graphics.clear();
            _bg.graphics.beginFill(COLOR_NORMAL_BG);
            _bg.graphics.drawRoundRect(0, 0, GRID_WIDTH, GRID_HEIGHT, 6, 6);
            _bg.graphics.endFill();
        }
        _labelField.textColor = COLOR_NORMAL_TEXT;
    }
    
    /**
     * Draw hover state.
     */
    private function drawHover():Void
    {
        if (displayMode == DisplayMode.LIST)
        {
            _bg.graphics.clear();
            _bg.graphics.beginFill(COLOR_HOVER_BG);
            _bg.graphics.drawRect(0, 0, LIST_WIDTH, LIST_HEIGHT);
            _bg.graphics.endFill();
        }
        else
        {
            _bg.graphics.clear();
            _bg.graphics.beginFill(COLOR_HOVER_BG);
            _bg.graphics.drawRoundRect(0, 0, GRID_WIDTH, GRID_HEIGHT, 6, 6);
            _bg.graphics.endFill();
        }
        _labelField.textColor = COLOR_HOVER_TEXT;
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
        drawNormal();
    }
    
    /**
     * Click handler.
     */
    private function onClickHandler(e:MouseEvent):Void
    {
        if (onClick != null)
        {
            onClick(entry);
        }
    }
    
    /**
     * Get item width based on display mode.
     */
    public function getItemWidth():Float
    {
        return displayMode == DisplayMode.LIST ? LIST_WIDTH : GRID_WIDTH;
    }
    
    /**
     * Get item height based on display mode.
     */
    public function getItemHeight():Float
    {
        return displayMode == DisplayMode.LIST ? LIST_HEIGHT : GRID_HEIGHT;
    }
}