package ui.contextmenu;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import ui.contextmenu.data.MenuEntry;
import ui.contextmenu.data.RecentMenuTracker;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     RECENT SECTION                                        ║
 * ║          (Displays last N menu actions)                                   ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           
 * ║  Section at the top of the content panel showing the last 5 menu          ║
 *  actions for quick access.                                                  ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  RecentSection (Sprite)                                             │  ║
 * ║  │                                                                     │  ║
 * ║  │  ───────────────────────────────────────────────────────────────  │  ║
 * ║  │  │  Visual:                                                      │  │  ║
 * ║  │  │  ─────────────────────────────────────────────────────────┐  │  │  ║
 * ║  │  │  │  Recent:                                                │  │  │  ║
 * │  │  │  │  [Delete Selected] [Add Button] [Copy]                  │  │  │  ║
 * │  │  │  │  ← Horizontal list of recent entries, 25px tall each    │  │  │  ║
 * │  │  │  └─────────────────────────────────────────────────────────┘  │  │  ║
 * │  │  │                                                             │  │  ║
 * │  │  │  Data source: RecentMenuTracker.getInstance().getRecent()   │  │  ║
 * │  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * │  └─────────────────────────────────────────────────────────────────────┘  ║
 *                                                                            ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class RecentSection extends Sprite
{
    /** Callback when a recent entry is clicked. */
    public var onEntryClick:MenuEntry -> Void;
    
    /** Array of entry buttons. */
    private var _entryButtons:Array<Sprite>;
    
    /** Section title. */
    private var _titleLabel:TextField;
    
    /** Fixed height. */
    private static inline var SECTION_HEIGHT:Float = 60.0;
    
    /**
     * Create a new recent section.
     * 
     * @param width Width of the section
     */
    public function new(width:Float)
    {
        super();
        _entryButtons = [];
        buildUI(width);
        refresh();
    }
    
    /**
     * Build the section UI.
     * 
     * @param width Width of the section
     */
    private function buildUI(width:Float):Void
    {
        // Title
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_sans", 11, 0x888888, true);
        _titleLabel.text = "Recent:";
        _titleLabel.width = 100;
        _titleLabel.height = 20;
        _titleLabel.x = 10;
        _titleLabel.y = 5;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        addChild(_titleLabel);
        
        // Separator line
        graphics.lineStyle(1, 0x333344);
        graphics.moveTo(0, 30);
        graphics.lineTo(width, 30);
    }
    
    /**
     * Refresh the recent entries display.
     */
    public function refresh():Void
    {
        // Clear old buttons
        for (btn in _entryButtons)
        {
            if (btn.parent != null) btn.parent.removeChild(btn);
        }
        _entryButtons = [];
        
        // Get recent entries
        var recent = RecentMenuTracker.getInstance().getRecent();
        if (recent.length == 0) return;
        
        var xPos:Float = 10;
        var yPos:Float = 35;
        
        for (entry in recent)
        {
            var btn = createEntryButton(entry);
            btn.x = xPos;
            btn.y = yPos;
            addChild(btn);
            _entryButtons.push(btn);
            xPos += btn.width + 5;
            
            // Wrap to next line if needed
            if (xPos > width - 100)
            {
                xPos = 10;
                yPos += 25;
            }
        }
    }
    
    /**
     * Create a button for a recent entry.
     * 
     * @param entry Menu entry to display
     * @return Sprite button
     */
    private function createEntryButton(entry:MenuEntry):Sprite
    {
        var btn = new Sprite();
        
        // Background
        btn.graphics.beginFill(0x333344);
        btn.graphics.drawRoundRect(0, 0, 120, 22, 3, 3);
        btn.graphics.endFill();
        
        // Label
        var label = new TextField();
        label.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        label.text = entry.displayName;
        label.width = 110;
        label.height = 22;
        label.x = 5;
        label.y = 0;
        label.selectable = false;
        label.mouseEnabled = false;
        btn.addChild(label);
        
        // Interaction
        btn.buttonMode = true;
        btn.useHandCursor = true;
        btn.addEventListener(openfl.events.MouseEvent.CLICK, function(e) {
            if (onEntryClick != null) onEntryClick(entry);
        });
        
        return btn;
    }
    
    /**
     * Get section height.
     */
    public function getSectionHeight():Float { return SECTION_HEIGHT; }
    
    /**
     * Cleanup.
     */
    public function dispose():Void
    {
        _entryButtons = [];
        onEntryClick = null;
    }
}