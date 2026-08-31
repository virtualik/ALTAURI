// ui/DisplayMode.hx
package ui;

/**
 * DISPLAY MODE v1.0
 * Режим главного окна приложения: EDITOR (графовый редактор) или
 * DEVICE_PANEL (панель приборов). Управляется Main / DisplayConfig.
 * ВНИМАНИЕ: живёт ОДНОИМЁННЫЙ enum ui.contextmenu.DisplayMode (визуальный
 * режим пунктов меню) — известная коллизия имён, кандидат на переименование.
 */
enum DisplayMode {
    EDITOR;
    DEVICE_PANEL;
}
