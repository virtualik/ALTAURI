package ui.contextmenu;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     MENU BOUNDS CALCULATOR                                ║
 * ║          (Smart positioning to keep menu within stage bounds)             ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Calculates menu position so it stays fully visible on stage.             ║
 * ║  Handles edge cases:                                                      ║
 * ║  - Menu would overflow right edge → anchor to left of cursor              ║
 * ║  - Menu would overflow bottom edge → anchor to top of cursor              ║
 * ║  - Menu is too big for stage → shrink to fit with max dimensions          ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  MenuBoundsCalculator (Static)                                      │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  Methods:                                                     │  │  ║
 * ║  │  │  - clamp() → {x, y, width, height}                            │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Algorithm:                                                               ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  1. Calculate requested menu dimensions                             │  ║
 * ║  │  2. Check horizontal overflow:                                      │  ║
 * ║  │     - If x + width > stageWidth - margin → x = stageWidth - width   │  ║
 * ║  │  3. Check vertical overflow:                                        │  ║
 * ║  │     - If y + height > stageHeight - margin → y = stageHeight - h    │  ║
 * ║  │  4. Clamp to minimum margins on all sides                           │  ║
 * ║  │  5. If menu exceeds max dimensions → shrink to fit                  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class MenuBoundsCalculator
{
    /** Default margin from stage edges (pixels). */
    public static inline var DEFAULT_MARGIN:Float = 8.0;
    
    /** Maximum menu width (pixels). */
    public static inline var MAX_WIDTH:Float = 600.0;
    
    /** Maximum menu height (pixels). */
    public static inline var MAX_HEIGHT:Float = 500.0;
    
    /** Minimum menu width (pixels). */
    public static inline var MIN_WIDTH:Float = 300.0;
    
    /** Minimum menu height (pixels). */
    public static inline var MIN_HEIGHT:Float = 200.0;
    
    /**
     * Calculate menu position and dimensions to fit within stage bounds.
     * 
     * @param requestedX     Requested X position (cursor X)
     * @param requestedY     Requested Y position (cursor Y)
     * @param menuWidth      Requested menu width
     * @param menuHeight     Requested menu height
     * @param stageWidth     Stage width
     * @param stageHeight    Stage height
     * @param margin         Margin from stage edges (default: 8px)
     * @return Object with clamped {x, y, width, height}
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     * │  EXAMPLE:                                                           │
     * │                                                                     │
     * │  Stage: 1920x1080, Cursor: (1800, 900), Menu: 400x300              │
     * │                                                                     │
     * │  1. Check right edge: 1800 + 400 = 2200 > 1920 - 8                  │
     * │     → x = 1920 - 8 - 400 = 1512                                    │
     * │                                                                     │
     * │  2. Check bottom edge: 900 + 300 = 1200 > 1080 - 8                  │
     * │     → y = 1080 - 8 - 300 = 772                                     │
     * │                                                                     │
     * │  Result: {x: 1512, y: 772, width: 400, height: 300}                │
     * └─────────────────────────────────────────────────────────────────────┘
     */
    public static function clamp(
        requestedX:Float,
        requestedY:Float,
        menuWidth:Float,
        menuHeight:Float,
        stageWidth:Float,
        stageHeight:Float,
        ?margin:Float = null
    ): {x:Float, y:Float, width:Float, height:Float}
    {
        if (margin == null) margin = DEFAULT_MARGIN;
        
        // Clamp menu dimensions to min/max bounds
        var width = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, menuWidth));
        var height = Math.max(MIN_HEIGHT, Math.min(MAX_HEIGHT, menuHeight));
        
        // If menu is larger than stage (minus margins), shrink it
        var maxAvailableWidth = stageWidth - (margin * 2);
        var maxAvailableHeight = stageHeight - (margin * 2);
        
        if (width > maxAvailableWidth) width = maxAvailableWidth;
        if (height > maxAvailableHeight) height = maxAvailableHeight;
        
        // Calculate position
        var x = requestedX;
        var y = requestedY;
        
        // Horizontal overflow check
        if (x + width > stageWidth - margin)
        {
            // Menu would overflow right edge → anchor to left of cursor
            x = stageWidth - margin - width;
        }
        if (x < margin)
        {
            // Menu would overflow left edge → clamp to margin
            x = margin;
        }
        
        // Vertical overflow check
        if (y + height > stageHeight - margin)
        {
            // Menu would overflow bottom edge → anchor to top of cursor
            y = stageHeight - margin - height;
        }
        if (y < margin)
        {
            // Menu would overflow top edge → clamp to margin
            y = margin;
        }
        
        return {
            x: x,
            y: y,
            width: width,
            height: height
        };
    }
    
    /**
     * Calculate default menu dimensions based on content.
     * 
     * @param entryCount Number of menu entries
     * @param columns Number of columns in grid (default: 3)
     * @return {width, height} estimated dimensions
     */
    public static function estimateDimensions(entryCount:Int, ?columns:Int = 3): {width:Float, height:Float}
    {
        if (columns == null) columns = 3;
        
        // Estimate: 3 columns × ~120px per item = ~360px width + sidebar ~150px
        var width = 150.0 + (columns * 120.0);
        
        // Estimate: ~80px per row, 3 columns
        var rows = Math.ceil(entryCount / columns);
        var height = 100.0 + (rows * 80.0); // 100px for search + recent
        
        return {
            width: Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, width)),
            height: Math.max(MIN_HEIGHT, Math.min(MAX_HEIGHT, height))
        };
    }
}