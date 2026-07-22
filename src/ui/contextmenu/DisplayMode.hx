package ui.contextmenu;

/**
 * ════════════════════════════════════════════════════════════════════════════╗
 * ║                     DISPLAY MODE                                          ║
 * ║          (Enum for MenuItem visual representation)                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Defines how a MenuItem is rendered in the content panel:                 ║
 *    - LIST: Full-width row with icon + label + shortcut (for Editor commands)║
 *    - GRID: Compact tile with icon + label (for Atoms/Assemblies)            ║
 * ║                                                                           
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  DisplayMode (Enum)                                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  LIST  → 150px × 30px, horizontal layout                            │  ║
 * ║  │  GRID  → 100px × 80px, tile layout                                  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ═══════════════════════════════════════════════════════════════════════════╝
 */
enum DisplayMode
{
    /** Full-width row: icon + label + shortcut. Used for Editor commands. */
    LIST;
    
    /** Compact tile: icon + label. Used for Atoms/Assemblies grid. */
    GRID;
}