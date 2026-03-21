package core.view;

import core.base.Atom;

/**
 * DEVICE VIEW REGISTRY v1.0
 * Singleton реестр виджетов - обеспечивает принцип "Один Атом = Одно Лицо".
 *
 * Архитектура "Atom is Databank & Compute Core":
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                         АТОМ (Сущность)                                 │
 * │                              │                                          │
 * │        ┌─────────────────────┼─────────────────────┐                    │
 * │        │                     │                     │                    │
 * │        ▼                     ▼                     ▼                    │
 * │   А) COMPUTE            Б) DATABANK           В) FACE                   │
 * │   (вычисления)          (данные)              (DeviceView)              │
 * │                                                 │                       │
 * │                                                 │                       │
 * │                      ┌──────────────────────────┘                       │
 * │                      │                                                  │
 * │                      ▼                                                  │
 * │              DeviceViewRegistry                                         │
 * │              (гарантирует единственность)                               │
 * │                      │                                                  │
 * │         ┌────────────┴────────────┐                                     │
 * │         │                         │                                     │
 * │         ▼                         ▼                                     │
 * │    NodeView (preview)      DeviceWindow (full)                          │
 * │    scaled=0.6              scaled=1.0                                   │
 * │                                                                         │
 * │    Виджет ПЕРЕМЕЩАЕТСЯ между контейнерами,                              │
 * │    но ВСЕГДА один экземпляр на атом.                                    │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Принципы:
 * 1. Один атом = один DeviceView (Лицо)
 * 2. DeviceView может жить в NodeView ИЛИ в DeviceWindow
 * 3. При перемещении - тот же объект, только меняется parent и scale
 * 4. При удалении атома - виджет удаляется из реестра
 *
 * Headless Mode:
 * - Registry не создаёт виджеты автоматически
 * - Виджеты создаются только при запросе от UI
 * - Атомы работают независимо от наличия виджетов
 */
class DeviceViewRegistry {

    private static var _instance:DeviceViewRegistry;

    /**
     * Карта: atom.id -> DeviceView
     * Гарантирует единственность виджета для каждого атома.
     */
    private var _widgets:Map<String, DeviceView>;

    /**
     * Карта: atom.id -> текущий контейнер виджета
     * Для отслеживания где находится виджет (NodeView или DeviceWindow)
     */
    private var _containers:Map<String, String>;

    // Константы для идентификации контейнеров
    public static inline var CONTAINER_NODE_VIEW:String = "NodeView";
    public static inline var CONTAINER_DEVICE_WINDOW:String = "DeviceWindow";

    /**
     * Получить singleton instance.
     */
    public static function getInstance():DeviceViewRegistry {
        if (_instance == null) {
            _instance = new DeviceViewRegistry();
        }
        return _instance;
    }

    private function new() {
        _widgets = new Map<String, DeviceView>();
        _containers = new Map<String, String>();
    }

    // =========================================================================
    // ОСНОВНОЙ API
    // =========================================================================

    /**
     * Получить или создать виджет для атома.
     *
     * Это ГЛАВНЫЙ метод для получения Лица Атома.
     *
     * @param atom Атом для которого нужен виджет
     * @param createIfNotExists Если true - создаёт новый виджет при отсутствии
     * @return DeviceView или null если атом null или виджет не может быть создан
     */
    public function getOrCreate(atom:Atom, createIfNotExists:Bool = true):DeviceView {
        if (atom == null) return null;

        // Уже существует?
        if (_widgets.exists(atom.id)) {
            return _widgets.get(atom.id);
        }

        if (!createIfNotExists) return null;

        // Создаём новый через Factory
        var widget = DeviceWidgetFactory.create(atom);
        if (widget != null) {
            _widgets.set(atom.id, widget);
            // Контейнер ещё не назначен
            _containers.remove(atom.id);
            trace('DeviceViewRegistry: Created widget for atom "${atom.name}" (id: ${atom.id})');
        }

        return widget;
    }

    /**
     * Проверить существует ли виджет для атома.
     */
    public function exists(atomId:String):Bool {
        return _widgets.exists(atomId);
    }

    /**
     * Получить существующий виджет (без создания).
     */
    public function get(atomId:String):DeviceView {
        return _widgets.get(atomId);
    }

    /**
     * Зарегистрировать уже созданный виджет.
     * Используется когда виджет создан вручную, но нужно его зарегистрировать.
     */
    public function register(atomId:String, widget:DeviceView):Void {
        if (atomId == null || widget == null) return;

        // Если уже есть виджет для этого атома - сначала удаляем старый
        if (_widgets.exists(atomId)) {
            var old = _widgets.get(atomId);
            if (old != null && old != widget) {
                old.dispose();
            }
        }

        _widgets.set(atomId, widget);
        trace('DeviceViewRegistry: Registered widget for atom id: $atomId');
    }

    /**
     * Удалить виджет из реестра.
     * Вызывается при удалении атома из проекта.
     *
     * @param atomId ID атома
     * @param disposeWidget Если true - вызывает dispose() на виджете
     */
    public function remove(atomId:String, disposeWidget:Bool = true):Void {
        var widget = _widgets.get(atomId);
        if (widget != null) {
            if (disposeWidget) {
                widget.dispose();
            }
            _widgets.remove(atomId);
            _containers.remove(atomId);
            trace('DeviceViewRegistry: Removed widget for atom id: $atomId');
        }
    }

    // =========================================================================
    // УПРАВЛЕНИЕ КОНТЕЙНЕРОМ
    // =========================================================================

    /**
     * Установить текущий контейнер виджета.
     *
     * @param atomId ID атома
     * @param containerType "NodeView" или "DeviceWindow"
     */
    public function setContainer(atomId:String, containerType:String):Void {
        if (atomId == null) return;
        _containers.set(atomId, containerType);
    }

    /**
     * Получить текущий контейнер виджета.
     *
     * @return "NodeView", "DeviceWindow" или null если виджет не существует
     */
    public function getContainer(atomId:String):String {
        return _containers.get(atomId);
    }

    /**
     * Clear container registration for an atom.
     * Call when widget is removed from any container without moving to another.
     */
    public function clearContainer(atomId:String):Void {
        _containers.remove(atomId);
    }

    /**
     * Проверить находится ли виджет в NodeView.
     */
    public function isInNodeView(atomId:String):Bool {
        return _containers.get(atomId) == CONTAINER_NODE_VIEW;
    }

    /**
     * Проверить находится ли виджет в DeviceWindow.
     */
    public function isInDeviceWindow(atomId:String):Bool {
        return _containers.get(atomId) == CONTAINER_DEVICE_WINDOW;
    }

    // =========================================================================
    // ПЕРЕМЕЩЕНИЕ ВИДЖЕТОВ
    // =========================================================================

    /**
     * Переместить виджет в DeviceWindow.
     *
     * Если виджет сейчас в NodeView - он будет изъят оттуда
     * и перемещён в DeviceWindow с полным масштабом.
     *
     * @param atomId ID атома
     * @param targetContainer Sprite для добавления виджета
     * @param posX Позиция X в новом контейнере
     * @param posY Позиция Y в новом контейнере
     * @return DeviceView или null
     */
    public function moveToDeviceWindow(atomId:String, targetContainer:openfl.display.Sprite,
                                        ?posX:Float = 0, ?posY:Float = 0):DeviceView {
        var widget = _widgets.get(atomId);
        if (widget == null) return null;

        // Если уже в DeviceWindow - просто обновляем позицию
        if (isInDeviceWindow(atomId)) {
            widget.x = posX;
            widget.y = posY;
            return widget;
        }

        // Извлекаем из текущего родителя (NodeView)
        if (widget.parent != null) {
            widget.parent.removeChild(widget);
        }

        // Устанавливаем полный масштаб
        widget.scaleX = 1.0;
        widget.scaleY = 1.0;

        // Добавляем в новый контейнер
        widget.x = posX;
        widget.y = posY;
        targetContainer.addChild(widget);

        // Обновляем контейнер
        setContainer(atomId, CONTAINER_DEVICE_WINDOW);

        // Активируем если не активен
        if (!widget.isActive) {
            widget.activate();
        }

        trace('DeviceViewRegistry: Moved widget $atomId to DeviceWindow');
        return widget;
    }

    /**
     * Переместить виджет обратно в NodeView.
     *
     * Используется при закрытии DeviceWindow.
     *
     * @param atomId ID атома
     * @param targetContainer Sprite (NodeView) для добавления виджета
     * @param scaleFactor Масштаб для preview (обычно 0.6)
     * @param posX Позиция X
     * @param posY Позиция Y
     * @return DeviceView или null
     */
    public function moveToNodeView(atomId:String, targetContainer:openfl.display.Sprite,
                                    scaleFactor:Float = 0.6, ?posX:Float = 0, ?posY:Float = 0):DeviceView {
        var widget = _widgets.get(atomId);
        if (widget == null) return null;

        // Если уже в NodeView - просто обновляем
        if (isInNodeView(atomId)) {
            widget.x = posX;
            widget.y = posY;
            widget.scaleX = scaleFactor;
            widget.scaleY = scaleFactor;
            return widget;
        }

        // Извлекаем из текущего родителя (DeviceWindow/DeviceCard)
        if (widget.parent != null) {
            widget.parent.removeChild(widget);
        }

        // Устанавливаем масштаб preview
        widget.scaleX = scaleFactor;
        widget.scaleY = scaleFactor;

        // Добавляем в NodeView
        widget.x = posX;
        widget.y = posY;
        targetContainer.addChild(widget);

        // Обновляем контейнер
        setContainer(atomId, CONTAINER_NODE_VIEW);

        trace('DeviceViewRegistry: Moved widget $atomId to NodeView');
        return widget;
    }

    // =========================================================================
    // ИНФОРМАЦИЯ И ДИАГНОСТИКА
    // =========================================================================

    /**
     * Получить количество зарегистрированных виджетов.
     */
    public function getCount():Int {
        var count = 0;
        for (key in _widgets.keys()) count++;
        return count;
    }

    /**
     * Получить все ID атомов с виджетами.
     */
    public function getAtomIds():Array<String> {
        var ids:Array<String> = [];
        for (id in _widgets.keys()) {
            ids.push(id);
        }
        return ids;
    }

    /**
     * Получить все виджеты в указанном контейнере.
     */
    public function getWidgetsInContainer(containerType:String):Array<DeviceView> {
        var result:Array<DeviceView> = [];
        for (atomId in _containers.keys()) {
            if (_containers.get(atomId) == containerType) {
                var widget = _widgets.get(atomId);
                if (widget != null) {
                    result.push(widget);
                }
            }
        }
        return result;
    }

    /**
     * Диагностический вывод состояния реестра.
     */
    public function debugPrint():Void {
        trace('=== DeviceViewRegistry Debug ===');
        trace('Total widgets: ${getCount()}');

        var nodeViewCount = 0;
        var deviceWindowCount = 0;
        var noContainerCount = 0;

        for (atomId in _widgets.keys()) {
            var container = _containers.get(atomId);
            if (container == CONTAINER_NODE_VIEW) nodeViewCount++;
            else if (container == CONTAINER_DEVICE_WINDOW) deviceWindowCount++;
            else noContainerCount++;
        }

        trace('  In NodeView: $nodeViewCount');
        trace('  In DeviceWindow: $deviceWindowCount');
        trace('  No container: $noContainerCount');
        trace('================================');
    }

    // =========================================================================
    // ОЧИСТКА
    // =========================================================================

    /**
     * Удалить все виджеты из реестра.
     * Используется при полной перезагрузке проекта.
     *
     * @param disposeWidgets Если true - вызывает dispose() на всех виджетах
     */
    public function clear(disposeWidgets:Bool = true):Void {
        if (disposeWidgets) {
            for (widget in _widgets) {
                if (widget != null) {
                    try {
                        widget.dispose();
                    } catch (e:Dynamic) {
                        trace('DeviceViewRegistry: Error disposing widget: $e');
                    }
                }
            }
        }

        _widgets.clear();
        _containers.clear();
        trace('DeviceViewRegistry: Cleared all widgets');
    }

    /**
     * Полный сброс singleton.
     * Используется при выходе из приложения или полном reset.
     */
    public static function reset():Void {
        if (_instance != null) {
            _instance.clear(true);
            _instance = null;
        }
    }
}