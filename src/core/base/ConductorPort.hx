package core.base;

import core.types.ContactType;
import core.types.ContactType.*;

/**
 * CONDUCTOR PORT
 * 
 * A bidirectional gateway that exposes an Atom's internal contact to the outside world.
 * 
 * Each port has two sides:
 * - internal: Connected to the atom's internal logic
 * - external: Connected to wires and other atoms
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                        CONDUCTOR PORT                           │
 * │                                                                 │
 * │   INTERNAL SIDE          │          EXTERNAL SIDE               │
 * │   (Atom Logic)           │          (Wires/Other Atoms)         │
 * │        ●                 │                 ●                    │
 * │        │                 │                 │                    │
 * │   [internal:Contact] ────┼──── [external:Contact]               │
 * │        │                 │                 │                    │
 * │        ▼                 │                 ▼                    │
 * │   To Atom Process        │          To Other Atoms              │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 * 
 * Port Types:
 * - INPUT: external → internal (signal flows inward)
 * - OUTPUT: internal → external (signal flows outward)
 * - BIDIRECTIONAL: both directions allowed
 */
class ConductorPort
{
    // ========================================================================
    // PROPERTIES
    // ========================================================================
    
    /** Port name (must be unique within parent assembly). */
    public var name(default, null):String;
    
    /** Port type (INPUT, OUTPUT, or BIDIRECTIONAL). */
    public var type(default, null):ContactType;
    
    /** Internal contact (connects to atom's logic). */
    public var internal(default, null):Contact;
    
    /** External contact (connects to wires/other atoms). */
    public var external(default, null):Contact;
    
    /** Default value for this port (used in blueprint). */
    public var defaultValue:Dynamic;
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /**
     * Create a new ConductorPort.
     * 
     * @param name         Port name
     * @param type         Port type (INPUT, OUTPUT, BIDIRECTIONAL)
     * @param defaultValue Default value for the contacts
     */
    public function new(name:String, type:ContactType, ?defaultValue:Dynamic = null)
    {
        this.name = name;
        this.type = type;
        this.defaultValue = defaultValue;
        
        // Create internal contact
        this.internal = new Contact(defaultValue, type, name);
        
        // Create external contact
        this.external = new Contact(defaultValue, type, name);
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
        if (type == INPUT || type == BIDIRECTIONAL)
        {
            external.link(internal, suppressPropagation);
        }
        if (type == OUTPUT || type == BIDIRECTIONAL)
        {
            internal.link(external, suppressPropagation);
        }
    }
    
    /**
     * Unlink internal and external contacts.
     * 
     * Breaks connections in both directions.
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
     * 
     * Called when parent assembly is destroyed.
     */
    public function dispose():Void
    {
        if (internal != null) internal.dispose();
        if (external != null) external.dispose();
        
        internal = null;
        external = null;
        name = null;
        type = null;
    }
}