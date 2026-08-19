package ui;

/**
 * NODE VISUAL MODE v1.0
 * Enum defining the visualization detail level for NodeView.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   NodeVisualMode                                                        │
 * │                                                                         │
 * │   LIGHT:    Only title bar and connection ports.                        │
 * │             Ideal for complex schemas and clean screenshots.            │
 * │                                                                         │
 * │   MEDIUM:   Title + ports + embedded widget (scaled to 70%).            │
 * │             The default standard balance of space and information.      │
 * │                                                                         │
 * │   HEAVY:    Title + ports + full-size widget (100%) + inline editors.   │
 * │             Maximum detail for focused editing of specific atoms.       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
enum NodeVisualMode {
    LIGHT;
    MEDIUM;
    HEAVY;
}