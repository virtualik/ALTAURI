package ui;

/**
 * WIRE TYPE v2.0
 * Enum defining wire rendering styles.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   WireType                                                              │
 * │                                                                         │
 * │   BEZIER:    ╭────────╮  (smooth cubic curve, default)                  │
 * │   STRAIGHT:  ╱─────────╱  (horizontal tails + direct diagonal)          │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
enum WireType {
    BEZIER;      // Smooth bezier curves (default)
    STRAIGHT;    // Horizontal tails + direct diagonal line
}