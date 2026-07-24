package core.data;
import core.types.ContactType;

// ============================================================================
// TYPE DEFINITIONS (Package Level)
// ============================================================================
/**
* PARAMETER PRIORITY
*
* Determines the visibility and importance of a pin in the inline editor.
*/
enum ParameterPriority
{
    CRITICAL;    // Always show (main output)
    IMPORTANT;   // Show in Editor (frequency, mode)
    OPTIONAL;    // Only in Properties (fine-tuning)
    INTERNAL;    // Never show (technical contacts)
}

/**
* PIN DEFINITION
*
* Describes a single external port of an assembly.
*
* ┌─────────────────┬────────────────────────────────────────────┐
* │ Field           │ Description                                │
* ├─────────────────┼────────────────────────────────────────────┤
* │ name            │ Port name (must be unique within assembly) │
* │ type            │ ContactType (INPUT, OUTPUT, BIDIRECTIONAL) │
* │ defaultValue    │ Initial value for this port                │
* │ dataType        │ String representation of data type         │
* │ priority        │ ParameterPriority for inline editor        │
* │ visibleInEditor │ Show inline editor in NodeView?            │
* │ label           │ Short label (fallback to name if null)     │
* │ editable        │ Can be edited inline (default: true)       │
* └─────────────────┴────────────────────────────────────────────┘
*/
typedef PinDef =
{
    var name:String;              // Internal name (wall contact, used as map key)
    var type:ContactType;
    @:optional var defaultValue:Dynamic;
    @:optional var dataType:String;
    @:optional var priority:ParameterPriority;
    @:optional var visibleInEditor:Bool;
    @:optional var label:String;
    @:optional var editable:Bool;
    @:optional var externalName:String;  // v2.0: Name visible on parent schema
}

/**
* ATOM DEFINITION
*
* Describes an atom instance inside an assembly blueprint.
*
* ┌─────────────────┬────────────────────────────────────────────┐
* │ Field           │ Description                                │
* ├─────────────────┼────────────────────────────────────────────┤
* │ instanceId      │ Template ID (used in blueprint definition) │
* │ typeId          │ Atom type to instantiate                   │
* │ x               │ X position on the canvas                   │
* │ y               │ Y position on the canvas                   │
* │ values          │ Saved state (for restoreState)             │
* └──────────────────────────────────────────────────────────────┘
*/
typedef AtomDef =
{
    var instanceId:String;
    var typeId:String;
    @:optional var x:Float;
    @:optional var y:Float;
    @:optional var values:Dynamic;
}

/**
* CONNECTION POINT
*
* References a specific contact on a specific atom.
*/
typedef ConnectionPoint =
{
    var atomId:String;
    var contactName:String;
}

/**
* CONNECTION DEFINITION
*
* Describes a wire between two connection points.
*/
typedef ConnectionDef =
{
    var from:ConnectionPoint;
    var to:ConnectionPoint;
}

// ============================================================================
// BLUEPRINT CLASS
// ============================================================================
/**
* BLUEPRINT
*
* A serializable definition of an Assembly's structure.
*
* A Blueprint describes:
* - External interface (pins/ports)
* - Internal atom composition
* - Internal wiring between atoms
* - Logic processing function (for native atoms)
*
* Architecture:
* ┌─────────────────────────────────────────────────────────────────┐
* │                        BLUEPRINT                                │
* │                                                                 │
* │  ┌─────────────┐  ┌──────────────┐  ┌───────────────────────┐   │
* │  │ pins        │  │ internalAtoms│  │ internalConnections   │   │
* │  │ (Interface) │  │ (Components) │  │ (Wiring)              │   │
* │  └─────────────┘  └──────────────┘  └───────────────────────┘   │
* │                                                                 │
* └─────────────────────────────────────────────────────────────────┘
*/
class Blueprint
{
    // ========================================================================
    // PROPERTIES
    // ========================================================================
    /** Unique blueprint ID (used for type identification). */
    public var id:String;
    /** Human-readable name (displayed in UI). */
    public var name:String;
    /** Category for UI organization (e.g., "Electro", "Drivers"). */
    public var category:String;
    /** Device type for DeviceView factory (e.g., "led", "toggle", "panel"). */
    public var deviceType:String;
    /** If true, this is a system assembly and cannot be edited by the user. */
    public var isNative:Bool = false;
    /** If true, the atom requires active driver updates (registered in DriverManager). */
    public var isActive:Bool = false;
    /** Icon identifier for menu display (e.g., "signal_generator", "button").
    *  Maps to assets/icons/atoms/{iconId}.png. Null = use default icon. */
    public var iconId:String = null;
    /** External interface (input/output ports). */
    public var pins(default, null):Array<PinDef>;
    /** Internal atom definitions. */
    public var internalAtoms(default, null):Array<AtomDef>;
    /** Internal wiring between atoms. */
    public var internalConnections(default, null):Array<ConnectionDef>;
    /** Processing function for native atoms (inputs -> outputs). */
    public var logic(default, null):Array<Dynamic> -> Array<Dynamic>;
    /**
    * v3.0: Target platforms for this blueprint.
    *
    * Used for platform-specific filtering in context menus.
    * - null or empty array = available on all platforms
    * - ["cpp"] = only for C++ target (Windows/Linux native)
    * - ["html5"] = only for HTML5 target (browser)
    * - ["cpp", "html5"] = available on both
    *
    * Examples:
    *   ComPortAtom: platforms = ["cpp"]  (serial port not available in browser)
    *   MiniAudioAtom: platforms = ["cpp"]  (native audio API)
    *   Button: platforms = null  (works everywhere)
    */
    @:optional public var platforms:Array<String>;

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    /**
    * Create a new Blueprint.
    *
    * @param id                 Unique blueprint ID
    * @param name               Human-readable name
    * @param pins               External port definitions
    * @param logic              Processing function (for native atoms)
    * @param internalAtoms      Internal atom definitions
    * @param internalConnections Internal wiring
    * @param category           UI category
    * @param platforms          Target platforms (null = all platforms)
    */
    public function new(
        id:String,
        name:String,
        pins:Array<PinDef>,
        ?logic:Array<Dynamic> -> Array<Dynamic>,
        ?internalAtoms:Array<AtomDef>,
        ?internalConnections:Array<ConnectionDef>,
        ?category:String = "General",
        ?platforms:Array<String> = null
    )
    {
        this.id = id;
        this.name = name;
        this.pins = pins;
        this.logic = logic;
        this.internalAtoms = (internalAtoms != null) ? internalAtoms : [];
        this.internalConnections = (internalConnections != null) ? internalConnections : [];
        this.category = category;
        this.platforms = platforms;
    }
}