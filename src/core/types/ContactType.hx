package core.types;

/**
 * Enum defining the direction of data flow in a Contact.
 */
enum ContactType {
    INPUT;      // Receives data
    OUTPUT;     // Sends data
    BIDIRECTIONAL; // Can do both (rare, usually for state)
    UNDEFINED;  // Fallback
}
