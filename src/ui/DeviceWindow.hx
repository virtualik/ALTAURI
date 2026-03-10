package ui;

import openfl.display.Window;
import openfl.Lib;
import openfl.events.Event;
import core.base.Assembly;

/**
 * Device Window
 * Вторичное окно приложения для отображения Device Panel.
 * Использует принципы WindowController для прозрачности.
 */
class DeviceWindow {

    private var _window:Window;
    private var _panel:DevicePanel;
    private var _assembly:Assembly;

    public function new(assembly:Assembly) {
        _assembly = assembly;
        create();
    }

    private function create():Void {
        // 1. Создаем новое нативное окно через Lime/OpenFL
        // Заголовок "Device" важен для поиска окна через WinAPI
        var config = {
            title: "Device",
            width: 420,
            height: 500,
			alwaysOnTop: true,
            parameters: {
                background: 0x000000 // Черный фон будет прозрачным (Color Key)
            }
        };

        // Создаем окно
        _window = Lib.application.createWindow(config);
        
        // 2. Добавляем контент (DevicePanel) на СЦЕНУ (stage) окна
        // ИСПРАВЛЕНИЕ: Window не имеет addChild, добавлять надо на stage
        if (_window != null && _window.stage != null) {
            _panel = new DevicePanel(_assembly);
            _window.stage.addChild(_panel);
        }

        // 3. Применяем хак прозрачности
        // Небольшая задержка нужна, чтобы ОС успела создать дескриптор окна (HWND)
        haxe.Timer.delay(() -> {
            applyWindowEffects();
        }, 100);
    }

    private function applyWindowEffects():Void {
        #if windows
        // Создаем временный контроллер
        var ctrl = new WindowController();
        var success = ctrl.applyTransparencyToWindow("Device");
        
        if (success) {
            trace("Device window transparency enabled.");
        } else {
            trace("Failed to enable Device window transparency.");
        }
        #end
    }

    public function close():Void {
        if (_panel != null) {
            _panel.dispose();
            // Удаляем панели со сцены, если она там есть
            if (_panel.parent != null) {
                _panel.parent.removeChild(_panel);
            }
            _panel = null;
        }
        if (_window != null) {
            _window.close();
            _window = null;
        }
    }
}