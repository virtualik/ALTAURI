package ui.contextmenu;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     SIDEBAR POSITION                                      ║
 * ║          (Enum for sidebar placement in context menu)                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║ Defines which side of the context menu the category sidebar appears on:   ║
 * ║  - LEFT:  Sidebar on left, content panel on right (default)               ║
 * ║  - RIGHT: Content panel on left, sidebar on right                         ║
 * ║                                                                           ║
 * ║ Architecture:                                                             ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  LEFT Layout:                                                       │  ║
 * ║  │  ┌────────────┬──────────────────────────────────────────────────┐  │  ║
 * ║  │  │ Sidebar    │ Content Panel                                    │  │  ║
 * ║  │  │ (150px)    │ (450px)                                          │  │  ║
 * ║  │  └────────────┴──────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  RIGHT Layout:                                                      │  ║
 * ║  │  ┌──────────────────────────────────────────────────┬────────────┐  │  ║
 * ║  │  │ Content Panel                                    │ Sidebar    │  │  ║
 * ║  │  │ (450px)                                          │ (150px)    │  │  ║
 * ║  │  └──────────────────────────────────────────────────┴────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
enum SidebarPosition
{
    /** Sidebar on left side (default). */
    LEFT;
    
    /** Sidebar on right side. */
    RIGHT;
}