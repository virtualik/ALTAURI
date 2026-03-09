package editor;

/**
 * EDITOR THEME v1.0
 * Centralized storage for all visual editor constants.
 * Allows easy re-skinning of the application.
 */
class EditorTheme {

    // Singleton
    private static var _instance:EditorTheme;
    public static function getInstance():EditorTheme {
        if (_instance == null) _instance = new EditorTheme();
        return _instance;
    }

    // =========================================================================
    // NODES & ATOMS
    // =========================================================================

    // Background fill of a standard node
    public var NODE_BG_COLOR:Int = 0x777777;

    // Border color when node is not selected
    public var NODE_BORDER_COLOR:Int = 0x33AAFF;

    // Border color when node is selected
    public var NODE_SELECTED_COLOR:Int = 0xFFCC00;

    // Title text color inside node
    public var NODE_TEXT_COLOR:Int = 0xFFFFFF;

    // =========================================================================
    // PORTS & CONTACTS
    // =========================================================================

    // Default color for ports (circles)
    public var PORT_COLOR_DEFAULT:Int = 0xFFFFFF;
    
    // Settings button color
    public var NODE_SETTINGS_BTN_COLOR:Int = 0x999999;
    public var NODE_SETTINGS_BTN_ICON:Int = 0xFFFFFF;

    // =========================================================================
    // WIRES
    // =========================================================================

    // Color of a standard active wire
    public var WIRE_COLOR_DEFAULT:Int = 0x666666;

    // Color of a selected wire
    public var WIRE_COLOR_SELECTED:Int = 0xFFCC00;

    // Color of the wire being dragged (Ghost Wire)
    public var WIRE_COLOR_GHOST:Int = 0x00FF00;

    // Thickness of wires
    public var WIRE_THICKNESS:Float = 4.0;

    // =========================================================================
    // CANVAS & BACKGROUND
    // =========================================================================

    // Main canvas background color
    public var CANVAS_BG_COLOR:Int = 0x333333;

    // Hit area color (invisible for hit testing)
    public var CANVAS_HIT_AREA_COLOR:Int = 0x000000;
    public var CANVAS_HIT_AREA_ALPHA:Float = 0.01;

    // =========================================================================
    // SELECTION & LASSO
    // =========================================================================

    // Lasso border color
    public var LASSO_BORDER_COLOR:Int = 0xFFFFFF;

    // Lasso fill color
    public var LASSO_FILL_COLOR:Int = 0x000000;
    
    // Lasso fill alpha
    public var LASSO_FILL_ALPHA:Float = 0.3;

    // =========================================================================
    // MAIN UI (Main.hx specific)
    // =========================================================================

    // Main application background
    public var APP_BG_COLOR:Int = 0x111111;

    // Container frame border color
    public var FRAME_BORDER_COLOR:Int = 0x00AAFF;
    
    // Container frame fill color (Windows specific semi-transparency)
    public var FRAME_FILL_COLOR:Int = 0x333333;
    public var FRAME_FILL_ALPHA:Float = 1.0;

    // Debug/Path text fields
    public var DEBUG_BG_COLOR:Int = 0x333333;
    public var DEBUG_TEXT_COLOR:Int = 0x00FF00;
    
    public var PATH_TEXT_COLOR:Int = 0x888888;
    public var TITLE_TEXT_COLOR:Int = 0x00AAFF;

    // Buttons (if configured in Main)
    public var BUTTON_BG_COLOR:Int = 0x3a3a4a;
    public var BUTTON_BG_OVER_COLOR:Int = 0x4a4a5a;
    public var BUTTON_BORDER_COLOR:Int = 0x666666;
    public var BUTTON_BORDER_OVER_COLOR:Int = 0x888888;

    private function new() {}
}