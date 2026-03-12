package core.types;

/**
 * Priority levels for the Signal Queue.
 */
enum Priority {
    CRITICAL;   // User input, drivers
    NORMAL;     // Default logic
    BACKGROUND; // Visualization, logs
}
