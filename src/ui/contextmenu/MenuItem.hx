package ui.contextmenu;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.MenuCategory;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
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
/**
 * MENU ITEM v2.0 (PNG Icon Support + Fallback)
 * Single clickable entry in content panel.
 * 
 * v2.0 Changes:
 * - Replaced text-based icons with PNG loading from assets.
 * - Added programmatic fallback (colored square + first letter) if PNG is missing.
 * - Supports 32x32 icons natively.
 */
class MenuItem extends Sprite
{
    public var entry:MenuEntry;
    public var onClick:MenuEntry -> Void;
    public var displayMode:DisplayMode;
    
    private var _bg:Sprite;
    private var _iconContainer:Sprite; // Holds either Bitmap or fallback graphics
    private var _labelField:TextField;
    private var _shortcutField:TextField;
    
    private static inline var LIST_WIDTH:Float = 150.0;
    private static inline var LIST_HEIGHT:Float = 30.0;
    private static inline var GRID_WIDTH:Float = 77.0;  // change sinchroniusly with ITEM_WIDTH in MenuItemGrid class constant.
    private static inline var GRID_HEIGHT:Float = 60.0; // change sinchroniusly with ITEM_HEIGHT in MenuItemGrid class constant.
    private static inline var ICON_SIZE:Float = 32.0;
    
    private static inline var COLOR_NORMAL_BG:Int = 0x222233;
    private static inline var COLOR_HOVER_BG:Int = 0x334455;
    private static inline var COLOR_NORMAL_TEXT:Int = 0xFFFFFF;
    private static inline var COLOR_HOVER_TEXT:Int = 0x00AAFF;
    private static inline var COLOR_SHORTCUT:Int = 0x888888;
    
    public function new(entry:MenuEntry, mode:DisplayMode = DisplayMode.LIST)
    {
        super();
        this.entry = entry;
        this.displayMode = mode;
        buildUI();
    }
    
    private function buildUI():Void
    {
        _bg = new Sprite();
        addChild(_bg);
        
        _iconContainer = new Sprite();
        addChild(_iconContainer);
        
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
     * Attempts to load PNG. If fails, draws a fallback colored square.
     */
    private function loadIcon():Void
    {
        _iconContainer.graphics.clear();
        while (_iconContainer.numChildren > 0) _iconContainer.removeChildAt(0);
        
        // Only atoms and assemblies have icons in assets
        if (entry.categoryId != MenuCategory.ATOMS && entry.categoryId != MenuCategory.ASSEMBLIES)
        {
            drawFallbackIcon();
            return;
        }
        
        var path = "";
        if (entry.categoryId == MenuCategory.ATOMS) {
            path = "assets/icons/atoms/" + entry.icon + ".png";
        } else if (entry.categoryId == MenuCategory.ASSEMBLIES) {
            // If it's the default placeholder
            if (entry.icon == "default_assembly") {
                path = "assets/icons/assemblies/default.png";
            } else {
                path = "assets/icons/assemblies/" + entry.icon + ".png";
            }
        }
        
        var bmpData:BitmapData = null;
        try {
            bmpData = openfl.Assets.getBitmapData(path);
        } catch (e:Dynamic) {
            // Asset not found
			trace("Asset not found");
        }
        
        if (bmpData != null)
        {
            var bmp = new Bitmap(bmpData);
            // Center the 32x32 icon within the container
            bmp.x = (ICON_SIZE - bmpData.width) / 2;
            bmp.y = (ICON_SIZE - bmpData.height) / 2;
            _iconContainer.addChild(bmp);
        }
        else
        {
            // Fallback if PNG is missing
            drawFallbackIcon();
        }
    }
    
    /**
     * Draws a colored square with the first letter of the name.
     * Used when PNG is missing or for Editor commands.
     */
    private function drawFallbackIcon():Void
    {
        // Generate a deterministic color based on the name
        var color = getDeterministicColor(entry.displayName);
        
        _iconContainer.graphics.beginFill(color);
        _iconContainer.graphics.drawRoundRect(0, 0, ICON_SIZE, ICON_SIZE, 6, 6);
        _iconContainer.graphics.endFill();
        
        // Draw first letter
        var letter = entry.displayName.length > 0 ? entry.displayName.charAt(0).toUpperCase() : "?";
        var tf = new TextField();
        tf.defaultTextFormat = new TextFormat("_sans", 16, 0xFFFFFF, true, null, null, null, null, "center");
        tf.text = letter;
        tf.width = ICON_SIZE;
        tf.height = ICON_SIZE;
        tf.y = 2; // slight visual adjustment
        tf.selectable = false;
        tf.mouseEnabled = false;
        _iconContainer.addChild(tf);
    }
    
    private function getDeterministicColor(str:String):Int
    {
        var hash = 0;
        for (i in 0...str.length) {
            hash = str.charCodeAt(i) + ((hash << 5) - hash);
        }
        // Map hash to a nice looking color (avoiding too dark/light)
        var r = (hash & 0xFF) % 100 + 100; // 100-200
        var g = ((hash >> 8) & 0xFF) % 100 + 100;
        var b = ((hash >> 16) & 0xFF) % 100 + 150; // slightly more blue
        return (r << 16) | (g << 8) | b;
    }
    
    private function layoutList():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_NORMAL_BG);
        _bg.graphics.drawRect(0, 0, LIST_WIDTH, LIST_HEIGHT);
        _bg.graphics.endFill();
        
        _iconContainer.x = 6;
        _iconContainer.y = (LIST_HEIGHT - ICON_SIZE) / 2;
        
        _labelField.x = 40;
        _labelField.y = 5;
        _labelField.width = LIST_WIDTH - 5;
        _labelField.height = LIST_HEIGHT;
        
        _shortcutField.x = LIST_WIDTH - 55;
        _shortcutField.y = 0;
        
        loadIcon();
    }
    
    private function layoutGrid():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(COLOR_NORMAL_BG);
        _bg.graphics.drawRoundRect(0, 0, GRID_WIDTH, GRID_HEIGHT, 6, 6);
        _bg.graphics.endFill();
        
        _iconContainer.x = (GRID_WIDTH - ICON_SIZE) / 2;
        _iconContainer.y = 10;
        
        _labelField.x = 5;
        _labelField.y = ICON_SIZE + 10;
        _labelField.width = GRID_WIDTH - 10;
        _labelField.height = 30;
        
        var fmt = new TextFormat("_sans", 10, COLOR_NORMAL_TEXT, false, null, null, null, null, "center");
        _labelField.defaultTextFormat = fmt;
        _labelField.setTextFormat(fmt);
        
        loadIcon();
    }
    
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
    
    private function onMouseOver(e:MouseEvent):Void { drawHover(); }
    private function onMouseOut(e:MouseEvent):Void { drawNormal(); }
    
    private function onClickHandler(e:MouseEvent):Void
    {
        if (onClick != null) onClick(entry);
    }
    
    public function getItemWidth():Float { return displayMode == DisplayMode.LIST ? LIST_WIDTH : GRID_WIDTH; }
    public function getItemHeight():Float { return displayMode == DisplayMode.LIST ? LIST_HEIGHT : GRID_HEIGHT; }
}

