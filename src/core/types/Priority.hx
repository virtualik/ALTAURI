package core.types;

/**
 * Priority levels for the Signal Queue.
 * Lower values are processed first.
 */
enum Priority {
    CRITICAL;   // User input, drivers - processed first
    NORMAL;     // Default logic
    BACKGROUND; // Visualization, logs - processed last
}