package core.logic;

/**
 * EVENT TYPE v1.0
 * Типобезопасный перечень всех событий системы (Impulse types).
 */
abstract EventType(String) from String to String {
    public inline function new(s:String) this = s;

    // === SYSTEM & LIFECYCLE ===
    public static var ATOM_DELETED(default, never) = new EventType("ATOM_DELETED");
    public static var ATOM_RESTORED(default, never) = new EventType("ATOM_RESTORED");
    public static var REDRAW_WIRES(default, never) = new EventType("REDRAW_WIRES");
    public static var ASSEMBLY_PORTS_CHANGED(default, never) = new EventType("ASSEMBLY_PORTS_CHANGED");
    public static var VALUE_COMMITTED(default, never) = new EventType("VALUE_COMMITTED");

    // === INTERACTION (Mouse/Click) ===
    public static var PORT_DRAG_START(default, never) = new EventType("PORT_DRAG_START");
    public static var NODE_CLICKED(default, never) = new EventType("NODE_CLICKED");
    public static var NODE_RIGHT_CLICKED(default, never) = new EventType("NODE_RIGHT_CLICKED");
    public static var WIRE_RIGHT_CLICKED(default, never) = new EventType("WIRE_RIGHT_CLICKED");
    public static var PORT_RIGHT_CLICKED(default, never) = new EventType("PORT_RIGHT_CLICKED");
    public static var CANVAS_RIGHT_CLICKED(default, never) = new EventType("CANVAS_RIGHT_CLICKED");

    // === EDITOR STATE ===
    public static var EDITOR_NODE_MOVED(default, never) = new EventType("EDITOR_NODE_MOVED");
    public static var NODE_DRAG_FINISHED(default, never) = new EventType("NODE_DRAG_FINISHED");
    public static var FORCE_UPDATE_NODE_POSITION(default, never) = new EventType("FORCE_UPDATE_NODE_POSITION");
    public static var CLOSE_CONTEXT_MENU(default, never) = new EventType("CLOSE_CONTEXT_MENU");

    // === NAVIGATION & COMMANDS ===
    public static var OPEN_ASSEMBLY_REQUEST(default, never) = new EventType("OPEN_ASSEMBLY_REQUEST");
    public static var REQUEST_NEW_ASSEMBLY_CONTEXT(default, never) = new EventType("REQUEST_NEW_ASSEMBLY_CONTEXT");
    public static var REQUEST_CLOSE_CURRENT_CONTEXT(default, never) = new EventType("REQUEST_CLOSE_CURRENT_CONTEXT");
    public static var ATOM_PROPERTIES_REQUEST(default, never) = new EventType("ATOM_PROPERTIES_REQUEST");

    // === CONTEXT MENU ===
    public static var CONTEXT_MENU_ACTION(default, never) = new EventType("CONTEXT_MENU_ACTION");
}