package core.base;

import core.types.ContactType;
import core.types.ContactType.*;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     CONDUCTOR PORT v2.0 (Dual Naming)                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  A bidirectional gateway that exposes an Atom's internal contact          ║
 * ║  to the outside world.                                                    ║
 * ║                                                                           ║
 * ║  v2.0: Supports DIFFERENT names for external and internal contacts.       ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        DUAL NAMING ARCHITECTURE                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                    CONDUCTOR PORT                                   │  ║
 * ║  │                                                                     │  ║
 * ║  │   EXTERNAL SIDE (Parent Schema)    │    INTERNAL SIDE (Inside)      │  ║
 * ║  │   ┌─────────────────────────┐      │    ┌────────────────────────┐  │  ║
 * ║  │   │ name: "PassThrough_in"  │      │    │ name: "incoming_1"     │  │  ║
 * ║  │   │ type: INPUT             │──────┼────│ type: INPUT            │  │  ║
 * ║  │   │ (visible to parent)     │      │    │ (visible on wall)      │  │  ║
 * ║  │   └─────────────────────────┘      │    └────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │   port.name = internalName (used for lookup in Assembly.ports map)  │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Naming Convention:                                                       ║
 * ║  ─────────────────                                                        ║
 * ║  External: "{AtomDisplayName}_{ContactName}" or "{ContactName}_N"         ║
 * ║  Internal: "incoming_N" (INPUT) or "outgoing_N" (OUTPUT)                  ║
 * ║                                                                           ║
 * ║  Example:                                                                 ║
 * ║  ─────────                                                                ║
 * ║  External name: "PassThrough_1_in"  (parent sees this on assembly node)   ║
 * ║  Internal name: "incoming_1"        (wall contact inside assembly)        ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 * 
 * ШПАРГАЛКА
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                    CONDUCTOR PORT DUAL NAMING                         │
 * ├───────────────────────────────────────────────────────────────────────┤
 * │                                                                       │
 * │  Assembly.ports map keyed by:  internalName (e.g., "incoming_1")      │
 * │  port.name                   = internalName                           │
 * │  port.internal.name          = internalName (wall contact inside)     │
 * │  port.external.name          = externalName (visible on parent)       │
 * │                                                                       │
 * │  WHEN TO USE WHICH:                                                   │
 * │  ─────────────────                                                    │
 * │  ✓ internalName:                                                      │
 * │    - Assembly.ports.get(name)                                         │
 * │    - blueprint.internalConnections INSIDE assembly (SELF.xxx)         │
 * │    - port.internal links                                              │
 * │                                                                       │
 * │  ✓ externalName:                                                      │
 * │    - blueprint.internalConnections in PARENT assembly                 │
 * │    - atom.getInput(name) / atom.getOutput(name) for Assembly          │
 * │    - NodeView.inputPorts/outputPorts keys                             │
 * │    - WireRenderer.getWirePoint()                                      │
 * │                                                                       │
 * └───────────────────────────────────────────────────────────────────────┘
 */
class ConductorPort
{
    // ========================================================================
    // PROPERTIES
    // ========================================================================
    
    /** Port name (used as key in Assembly.ports map). Equals internalName. */
    public var name(default, null):String;
    
    /** Port type (INPUT, OUTPUT, or BIDIRECTIONAL). */
    public var type(default, null):ContactType;
    
    /** Internal contact (connects to atom's logic, visible on wall inside). */
    public var internal(default, null):Contact;
    
    /** External contact (connects to wires/other atoms, visible on parent). */
    public var external(default, null):Contact;
    
    /** Default value for this port (used in blueprint). */
    public var defaultValue:Dynamic;
    
    /** v2.0: External display name (visible on parent schema). */
    public var externalName(default, null):String;
    
    /** v2.0: Internal display name (visible on wall inside assembly). */
    public var internalName(default, null):String;
    
    /** v1.1: Lifecycle flag for safe async operations. */
    public var isDisposed(default, null):Bool = false;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /**
     * Create a new ConductorPort with dual naming support.
     * 
     * @param externalName  Name visible on parent schema (e.g., "PassThrough_1_in")
     * @param internalName  Name visible on wall inside assembly (e.g., "incoming_1")
     * @param type          Port type (INPUT, OUTPUT, BIDIRECTIONAL)
     * @param defaultValue  Default value for the contacts
     * 
     * v2.0: If internalName is null, it defaults to externalName (backward compat).
     */
	public function new(externalName:String, type:ContactType, ?internalName:String = null, ?defaultValue:Dynamic = null)
	{
		this.externalName = externalName;
		this.internalName = (internalName != null) ? internalName : externalName;
		this.type = type;
		this.defaultValue = defaultValue;
		
		// port.name = internalName (used for lookup in Assembly.ports map)
		this.name = this.internalName;
		
		// Create internal contact with INTERNAL name (visible on wall)
		this.internal = new Contact(defaultValue, type, this.internalName);
		
		// Create external contact with EXTERNAL name (visible on parent)
		this.external = new Contact(defaultValue, type, this.externalName);
	}

    // ========================================================================
    // LINKING
    // ========================================================================
    
    /**
     * Link internal and external contacts.
     * 
     * Direction depends on port type:
     * - INPUT: external.link(internal) - signal flows inward
     * - OUTPUT: internal.link(external) - signal flows outward
     * - BIDIRECTIONAL: both directions
     * 
     * @param suppressPropagation If true, prevents immediate signal propagation
     */
    public function link(suppressPropagation:Bool = false):Void
    {
        if (isDisposed) return;
        
        if (type == INPUT || type == BIDIRECTIONAL)
        {
            if (external != null && internal != null)
                external.link(internal, suppressPropagation);
        }
        if (type == OUTPUT || type == BIDIRECTIONAL)
        {
            if (internal != null && external != null)
                internal.link(external, suppressPropagation);
        }
    }
    
    /**
     * Unlink internal and external contacts.
     */
    public function unlink():Void
    {
        if (external != null && internal != null)
        {
            external.unlink(internal);
            internal.unlink(external);
        }
    }
    
    // ========================================================================
    // DISPOSE
    // ========================================================================
    
    /**
     * Dispose port and both contacts.
     */
    public function dispose():Void
    {
        if (isDisposed) return;
        isDisposed = true;
        
        if (internal != null) internal.dispose();
        if (external != null) external.dispose();
        
        internal = null;
        external = null;
        name = null;
        type = null;
        externalName = null;
        internalName = null;
    }
}