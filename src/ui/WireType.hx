package ui;

/**
 * WIRE TYPE v1.0
 * Enum defining wire rendering styles.
 */
enum WireType {
    BEZIER;      // Smooth bezier curves (default)
    STRAIGHT;    // Direct point-to-point line
    CORNERS;     // Right-angle corners (stepped)
}