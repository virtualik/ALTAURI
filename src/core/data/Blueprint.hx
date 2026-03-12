package core.data;

import core.types.ContactType;

// --- Type Definitions (Module Level) ---

typedef PinDef = {
    name: String,
    type: ContactType,
    ?defaultValue: Dynamic,
    ?dataType: String
}

typedef AtomDef = {
    instanceId: String,
    typeId: String,
    ?x: Float,
    ?y: Float
}

typedef ConnectionPoint = {
    atomId: String,
    contactName: String
}

typedef ConnectionDef = {
    from: ConnectionPoint,
    to: ConnectionPoint
}

// --- Main Class ---

/**
 * Blueprint Data Structure.
 * Defines the schematic of an Atom or Assembly.
 */
class Blueprint {

    public var id:String;
    public var name:String;
    public var category:String;
    public var deviceType:String;  // Тип устройства для DeviceView: "led", "toggle", "button", "text", "panel"

    public var pins(default, null):Array<PinDef>;
    public var internalAtoms(default, null):Array<AtomDef>;
    public var internalConnections(default, null):Array<ConnectionDef>;

    public var logic(default, null):Array<Dynamic> -> Array<Dynamic>;

    public function new(
        id:String,
        name:String,
        pins:Array<PinDef>,
        ?logic:Array<Dynamic> -> Array<Dynamic>,
        ?internalAtoms:Array<AtomDef>,
        ?internalConnections:Array<ConnectionDef>,
        ?category:String = "General"
    ) {
        this.id = id;
        this.name = name;
        this.pins = pins;
        this.logic = logic;
        this.internalAtoms = (internalAtoms != null) ? internalAtoms : [];
        this.internalConnections = (internalConnections != null) ? internalConnections : [];
        this.category = category;
    }
}
