package ui.contextmenu;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.FocusEvent;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     SEARCH BAR                                            ║
 * ║          (Text input for filtering menu entries)                          ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Text input field at the top of the content panel for filtering           ║
 *  menu entries by name.                                                      ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  SearchBar (Sprite)                                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  ───────────────────────────────────────────────────────────────  │  ║
 *   │  │  Visual:                                                      │  │  ║
 * ║  │  │  ┌─────────────────────────────────────────────────────────┐  │  │  ║
 * ║  │  │  │  🔍 [Search entries...]                                 │  │  │  
 * ║  │  │  │  ← Full width of content panel, 35px tall               │  │  │  
 * ║  │  │  ─────────────────────────────────────────────────────────┘  │  │  ║
 * ║  │  │                                                             │  │  ║
 * ║  │  │  Events:                                                      │  │  ║
 * ║  │  │  - onSearch: String -> Void (fires on each keystroke)         │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class SearchBar extends Sprite
{
    /** Callback when search text changes. */
    public var onSearch:String -> Void;
    
    /** Input text field. */
    private var _input:TextField;
    
    /** Placeholder text. */
    private static inline var PLACEHOLDER:String = "Search entries...";
    
    /** Fixed height. */
    private static inline var BAR_HEIGHT:Float = 35.0;
    
    /**
     * Create a new search bar.
     * 
     * @param width Width of the search bar
     */
    public function new(width:Float)
    {
        super();
        buildUI(width);
    }
    
    /**
     * Build the search bar UI.
     * 
     * @param width Width of the search bar
     */
    private function buildUI(width:Float):Void
    {
        // Background
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x444455);
        graphics.drawRoundRect(0, 0, width, BAR_HEIGHT, 5, 5);
        graphics.endFill();
        
        // Search icon placeholder (text-based)
        var icon = new TextField();
        icon.defaultTextFormat = new TextFormat("_sans", 14, 0x888888);
        icon.text = "🔍";
        icon.width = 30;
        icon.height = BAR_HEIGHT;
        icon.x = 5;
        icon.y = 0;
        icon.selectable = false;
        icon.mouseEnabled = false;
        addChild(icon);
        
        // Input field
        _input = new TextField();
        _input.type = TextFieldType.INPUT;
        _input.defaultTextFormat = new TextFormat("_sans", 13, 0xFFFFFF);
        _input.text = "";
        _input.width = width - 40;
        _input.height = BAR_HEIGHT - 10;
        _input.x = 35;
        _input.y = 5;
        _input.border = false;
        _input.background = false;
        _input.selectable = true;
        _input.mouseEnabled = true;
        addChild(_input);
        
        // Placeholder
        var placeholder = new TextField();
        placeholder.defaultTextFormat = new TextFormat("_sans", 13, 0x666666);
        placeholder.text = PLACEHOLDER;
        placeholder.width = width - 40;
        placeholder.height = BAR_HEIGHT - 10;
        placeholder.x = 35;
        placeholder.y = 5;
        placeholder.selectable = false;
        placeholder.mouseEnabled = false;
        placeholder.name = "placeholder";
        addChild(placeholder);
        
        // Events
        _input.addEventListener(Event.CHANGE, onInputChange);
        _input.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _input.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
    }
    
    /**
     * Handle input change.
     */
    private function onInputChange(e:Event):Void
    {
        // Hide placeholder when typing
        var placeholder = getChildByName("placeholder");
        if (placeholder != null)
        {
            placeholder.visible = (_input.text.length == 0);
        }
        
        // Notify
        if (onSearch != null)
        {
            onSearch(_input.text);
        }
    }
    
    /**
     * Handle focus in.
     */
    private function onFocusIn(e:FocusEvent):Void
    {
        graphics.clear();
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x00AAFF);
        graphics.drawRoundRect(0, 0, width, BAR_HEIGHT, 5, 5);
        graphics.endFill();
    }
    
    /**
     * Handle focus out.
     */
    private function onFocusOut(e:FocusEvent):Void
    {
        graphics.clear();
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x444455);
        graphics.drawRoundRect(0, 0, width, BAR_HEIGHT, 5, 5);
        graphics.endFill();
    }
    
    /**
     * Get current search text.
     */
    public function getSearchText():String
    {
        return _input.text;
    }
    
    /**
     * Clear search text.
     */
    public function clearSearch():Void
    {
        _input.text = "";
        var placeholder = getChildByName("placeholder");
        if (placeholder != null) placeholder.visible = true;
        if (onSearch != null) onSearch("");
    }
    
    /**
     * Get search bar height.
     */
    public function getBarHeight():Float { return BAR_HEIGHT; }
    
    /**
     * Cleanup.
     */
    public function dispose():Void
    {
        _input.removeEventListener(Event.CHANGE, onInputChange);
        _input.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _input.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        onSearch = null;
    }
}