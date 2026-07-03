package core.types;

/**
 * PRIORITY
 * 
 * Priority levels for the TickGenerator's task queues.
 * Determines the execution order of scheduled tasks within a single tick.
 * 
 * Execution Order: CRITICAL -> NORMAL -> BACKGROUND
 * 
 * Used by:
 * - TickGenerator (to sort and execute task queues)
 * - Contact (when scheduling propagation)
 * - Atom (when scheduling calculations)
 */
enum Priority 
{
    /** 
     * Highest priority. Processed first.
     * Used for: User input, hardware drivers, critical state updates.
     */
    CRITICAL;
    
    /** 
     * Default priority. Processed second.
     * Used for: Standard logic calculations, signal propagation.
     */
    NORMAL;
    
    /** 
     * Lowest priority. Processed last.
     * Used for: Visualization updates, logging, non-essential background tasks.
     */
    BACKGROUND;
}