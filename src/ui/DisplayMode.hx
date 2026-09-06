// ui/DisplayMode.hx
package ui;

/**
 * DISPLAY MODE v1.0
 * The main window mode of the application: EDITOR (the graph editor) or
 * DEVICE_PANEL (the instrument panel). Controlled by Main / DisplayConfig.
 * NOTE: there lives an IDENTICALLY-NAMED enum ui.contextmenu.DisplayMode (the visual
 * mode of menu items) - a known name collision, a rename candidate.
 */
enum DisplayMode {
    EDITOR;
    DEVICE_PANEL;
}
