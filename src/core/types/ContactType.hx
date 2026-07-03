package core.types;

/**
 * CONTACT TYPE
 * 
 * Enum defining the direction of data flow in a Contact.
 * 
 * Used by:
 * - Contact (to determine propagation rules)
 * - ConductorPort (to map internal/external sides)
 * - Blueprint.PinDef (to define assembly interface)
 */
enum ContactType 
{
    /** Receives data from external sources or linked contacts. */
    INPUT;
    
    /** Sends data to external destinations or linked contacts. */
    OUTPUT;
    
    /** Can both send and receive data (rare, usually for state synchronization). */
    BIDIRECTIONAL;
    
    /** Fallback type when direction is unknown or not yet resolved. */
    UNDEFINED;
}