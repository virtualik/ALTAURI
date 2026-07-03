package editor;

/**
 * EDITOR THEME v1.0
 * Centralized storage for all visual editor constants.
 * Allows easy re-skinning of the application.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   EditorTheme (Singleton)                                               │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Visual Constants:                                              │   │
 * │   │  - NODE_BG_COLOR           // Node background fill              │   │
 * │   │  - NODE_BORDER_COLOR       // Normal border color               │   │
 * │   │  - NODE_SELECTED_COLOR     // Selected border color             │   │
 * │   │  - WIRE_COLOR_DEFAULT      // Standard wire color               │   │
 * │   │  - WIRE_COLOR_SELECTED     // Selected wire color               │   │
 * │   │  - CANVAS_BG_COLOR         // Editor canvas background          │   │
 * │   │  - LASSO_BORDER_COLOR      // Selection lasso border            │   │
 * │   │  - FRAME_BORDER_COLOR      // Editor container frame            │   │
 * │   │  ... (all visual constants)                                     │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var theme = EditorTheme.getInstance();                                │
 * │   graphics.beginFill(theme.NODE_BG_COLOR);                              │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class EditorTheme
{
    // =========================================================================
    // SINGLETON
    // =========================================================================
    private static var _instance:EditorTheme;
    
    /**
     * Get singleton instance.
     * @return EditorTheme instance
     */
    public static function getInstance():EditorTheme
    {
        if (_instance == null) _instance = new EditorTheme();
        return _instance;
    }
    
    private function new() {}
    
    // =========================================================================
    // NODES & ATOMS
    // =========================================================================
    /** Background fill of a standard node */
    public var NODE_BG_COLOR:Int = 0x777777;
    
    /** Border color when node is not selected */
    public var NODE_BORDER_COLOR:Int = 0x33AAFF;
    
    /** Border color when node is selected */
    public var NODE_SELECTED_COLOR:Int = 0xFFCC00;
    
    /** Title text color inside node */
    public var NODE_TEXT_COLOR:Int = 0xFFFFFF;
    
    // =========================================================================
    // PORTS & CONTACTS
    // =========================================================================
    /** Default color for ports (circles) */
    public var PORT_COLOR_DEFAULT:Int = 0xFFFFFF;
    
    /** Settings button color */
    public var NODE_SETTINGS_BTN_COLOR:Int = 0x999999;
    
    /** Settings button icon color */
    public var NODE_SETTINGS_BTN_ICON:Int = 0xFFFFFF;
    
    // =========================================================================
    // WIRES
    // =========================================================================
    /** Color of a standard active wire */
    public var WIRE_COLOR_DEFAULT:Int = 0x666666;
    
    /** Color of a selected wire */
    public var WIRE_COLOR_SELECTED:Int = 0xFFCC00;
    
    /** Color of the wire being dragged (Ghost Wire) */
    public var WIRE_COLOR_GHOST:Int = 0x00FF00;
    
    /** Thickness of wires in pixels */
    public var WIRE_THICKNESS:Float = 4.0;
    
    // =========================================================================
    // CANVAS & BACKGROUND
    // =========================================================================
    /** Editor canvas background color */
    public var CANVAS_BG_COLOR:Int = 0x333333;
    
    /** Device canvas background color */
    public var DEVICE_CANVAS_BG_COLOR:Int = 0x444444;
    
    /** Hit area color (invisible for hit testing) */
    public var CANVAS_HIT_AREA_COLOR:Int = 0x0AA000;
    
    /** Hit area alpha for visibility during debugging */
    public var CANVAS_HIT_AREA_ALPHA:Float = 0.11;
    
    // =========================================================================
    // SELECTION & LASSO
    // =========================================================================
    /** Lasso border color */
    public var LASSO_BORDER_COLOR:Int = 0xFFFFFF;
    
    /** Lasso fill color */
    public var LASSO_FILL_COLOR:Int = 0x000000;
    
    /** Lasso fill alpha (0.0 - 1.0) */
    public var LASSO_FILL_ALPHA:Float = 0.3;
    
    // =========================================================================
    // MAIN UI (Main.hx specific)
    // =========================================================================
    /** Main application background */
    public var APP_BG_COLOR:Int = 0xFFFFFF;
    
    /** Alternative black background (for transparency) */
    public var APP_BG_BLACK:Int = 0xFFFFFF;
    
    /** Opaque background color for panels */
    public var OPAQUE_BACKGROUND_COLOR:Int = 0x1a1a24;
    
    /** Container frame border color */
    public var FRAME_BORDER_COLOR:Int = 0x00AAFF;
    
    /** Container frame fill color (Windows specific semi-transparency) */
    public var FRAME_FILL_COLOR:Int = 0x333333;
    
    /** Container frame fill alpha */
    public var FRAME_FILL_ALPHA:Float = 1.0;
    
    /** Debug/Path text fields background */
    public var DEBUG_BG_COLOR:Int = 0x333333;
    
    /** Debug text color (green for visibility) */
    public var DEBUG_TEXT_COLOR:Int = 0x00FF00;
    
    /** Path text color */
    public var PATH_TEXT_COLOR:Int = 0x888888;
    
    /** Title text color */
    public var TITLE_TEXT_COLOR:Int = 0x00AAFF;
    
    // =========================================================================
    // BUTTONS
    // =========================================================================
    /** Button background color */
    public var BUTTON_BG_COLOR:Int = 0x3a3a4a;
    
    /** Button background color on hover */
    public var BUTTON_BG_OVER_COLOR:Int = 0x4a4a5a;
    
    /** Button border color */
    public var BUTTON_BORDER_COLOR:Int = 0x666666;
    
    /** Button border color on hover */
    public var BUTTON_BORDER_OVER_COLOR:Int = 0x888888;
}