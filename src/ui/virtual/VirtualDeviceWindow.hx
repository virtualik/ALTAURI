package ui.virtual;

import openfl.display.NativeWindow;
import openfl.display.NativeWindowInitOptions;
// import openfl.display.NativeWindowType; // Убираем LIGHTWEIGHT
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import core.base.Assembly;
import ui.DevicePanel;

/**
 * VIRTUAL DEVICE WINDOW v1.3
 * Fixed transparency for Windows (HL).
 * Using standard window type without chrome instead of lightweight.
 */
class VirtualDeviceWindow {

    private var _window:NativeWindow;
    private var _stage:openfl.display.Stage;
    private var _container:Sprite;
    private var _devicePanel:DevicePanel;
    private var _assembly:Assembly;

    private var _isDragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;

    public function new(assembly:Assembly) {
        _assembly = assembly;

        // 1. Настройка опций окна
        var options = new NativeWindowInitOptions();
        options.transparent = true;      // Включаем поддержку альфа-канала
        options.systemChrome = "none";   // Убираем рамки окна (Title Bar)
        options.resizable = false;       // Фиксируем размер для простоты
        // ВАЖНО: НЕ используем NativeWindowType.LIGHTWEIGHT.
        // На Windows обычное окно без хрома (borderless) лучше поддерживает перxel-perfect прозрачность.
        
        // 2. Создаем окно
        _window = new NativeWindow(options);
        _window.width = 450;
        _window.height = 350;

        // 3. Настройка Stage
        _stage = _window.stage;
        
        // Используем прозрачный черный (Alpha=0). 
        // Если он не работает, система игнорирует флаг transparent.
        _stage.color = 0x00000000; 

        // 4. Контейнер (ловец кликов)
        _container = new Sprite();
        // Рисуем прозрачную зону для захвата мыши
        _container.graphics.beginFill(0x000000, 0.0); 
        _container.graphics.drawRect(0, 0, _window.width, _window.height);
        _container.graphics.endFill();
        
        _stage.addChild(_container);

        // 5. Добавляем Панель Устройства
        _devicePanel = new DevicePanel(_assembly);
        _devicePanel.setCompactMode(true); 
        _container.addChild(_devicePanel);

        // 6. Логика перетаскивания
        _container.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
        _stage.addEventListener(MouseEvent.MOUSE_UP, onDragStop);
        _stage.addEventListener(MouseEvent.MOUSE_MOVE, onDragMove);

        // 7. Закрытие (ПКМ)
        _container.addEventListener(MouseEvent.RIGHT_CLICK, onClose);
    }

    private function onDragStart(e:MouseEvent):Void {
        _isDragging = true;
        _dragOffsetX = e.stageX;
        _dragOffsetY = e.stageY;
    }

    private function onDragStop(e:MouseEvent):Void {
        _isDragging = false;
    }

    private function onDragMove(e:MouseEvent):Void {
        if (!_isDragging) return;

        var newX = _window.x + (e.stageX - _dragOffsetX);
        var newY = _window.y + (e.stageY - _dragOffsetY);
        
        _window.x = Std.int(newX);
        _window.y = Std.int(newY);
    }

    private function onClose(e:MouseEvent):Void {
        // Убиваем виджеты перед закрытием
        _devicePanel.dispose();
        _window.close();
    }

    public function show():Void {
        _window.visible = true;
        _window.activate();
    }
}