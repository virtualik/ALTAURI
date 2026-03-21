package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * DEVICE CARD v2.0 (Databank Architecture, Registry‑based)
 * Compact card representation of a device for the DeviceWindow.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * DeviceCard — это контейнер для единственного экземпляра DeviceView.
 * Он не создаёт новый виджет, а получает его из DeviceViewRegistry.
 * При создании карточки виджет перемещается из предыдущего контейнера
 * (например, NodeView) в карточку. При закрытии карточки виджет
 * возвращается в реестр (контейнер сбрасывается), и NodeView может
 * снова забрать его при следующей активации.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeviceCard                                                            │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  [Title Bar: Atom Name]  [x]                                   │   │
 * │   ├─────────────────────────────────────────────────────────────────┤   │
 * │   │                                                                  │   │
 * │   │  ┌───────────────────────────────────────────────────────────┐  │   │
 * │   │  │  DeviceView (получен из реестра, scale = 1.0)              │  │   │
 * │   │  └───────────────────────────────────────────────────────────┘  │   │
 * │   │                                                                  │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Перетаскивание за заголовок — перемещение карточки по окну.           │
 * │   Кнопка [x] — закрытие карточки, виджет возвращается в реестр.         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.0 Changes:
 * - Полностью переработан для работы с DeviceViewRegistry
 * - Виджет больше не создаётся через фабрику, а запрашивается из реестра
 * - При закрытии карточки виджет НЕ уничтожается, а возвращается в реестр
 * - Размер карточки автоматически подстраивается под размер виджета
 */
class DeviceCard extends Sprite {

    // =========================================================================
    // PUBLIC PROPERTIES
    // =========================================================================

    public var atom(default, null):Atom;
    public var cardWidth(default, null):Float = 100;
    public var cardHeight(default, null):Float = 80;

    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================

    private var _deviceWindow:DeviceWindow;
    private var _deviceView:DeviceView;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;

    // Drag state
    private var _cardDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;
    private var _isDisposed:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * Create a new DeviceCard for the given atom.
     * The card will automatically obtain the widget from DeviceViewRegistry
     * and place it inside itself.
     *
     * @param atom          The atom to display
     * @param deviceWindow  Reference to the parent DeviceWindow
     * @param x             Initial X position in the DeviceWindow canvas
     * @param y             Initial Y position in the DeviceWindow canvas
     */
    public function new(atom:Atom, deviceWindow:DeviceWindow, ?x:Float = 0, ?y:Float = 0) {
        super();
        this.atom = atom;
        _deviceWindow = deviceWindow;
        this.x = x;
        this.y = y;
        buildCard();
    }

    // =========================================================================
    // BUILD UI
    // =========================================================================

    private function buildCard():Void {
        // 1. Получаем виджет из реестра (гарантированно один экземпляр)
        var registry = DeviceViewRegistry.getInstance();
        _deviceView = registry.getOrCreate(atom, true);
        if (_deviceView == null) {
            trace('DeviceCard: Could not get widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }

        // 2. Перемещаем виджет в карточку с помощью реестра
        //    (виджет будет изъят из предыдущего контейнера, если был)
        _deviceView = registry.moveToDeviceWindow(atom.id, this, 0, 20);
        if (_deviceView == null) {
            trace('DeviceCard: Failed to move widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }

        // 3. Определяем размеры карточки на основе размеров виджета
        var viewWidth = _deviceView.width;
        var viewHeight = _deviceView.height;
        if (viewWidth < 50) viewWidth = 100;
        if (viewHeight < 30) viewHeight = 60;

        cardWidth = viewWidth + 30;   // отступы слева/справа
        cardHeight = viewHeight + 40; // заголовок 20 + нижний отступ

        // 4. Заголовок
        _titleBar = new Sprite();
        _titleBar.graphics.beginFill(0x3a3a4a);
        _titleBar.graphics.drawRect(0, 0, viewWidth + 20, 20);
        _titleBar.graphics.endFill();
        addChild(_titleBar);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 10, 0xFFFFFF);
        _titleLabel.text = " " + (atom != null ? atom.name : "Device");
        _titleLabel.width = viewWidth;
        _titleLabel.height = 20;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _titleBar.addChild(_titleLabel);

        // Кнопка закрытия
        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0x883333);
        closeBtn.graphics.drawRect(0, 0, 16, 16);
        closeBtn.graphics.endFill();
        closeBtn.x = viewWidth + 2;
        closeBtn.y = 2;
        var xText = new TextField();
        xText.text = "x";
        xText.width = 16;
        xText.height = 16;
        xText.selectable = false;
        xText.mouseEnabled = false;
        xText.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF, false, null, null, null, null, "center");
        closeBtn.addChild(xText);
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        _titleBar.addChild(closeBtn);

        // 5. Фон карточки (рисуем позади всего)
        graphics.clear();
        graphics.beginFill(0x2a2a3a, 0.9);
        graphics.lineStyle(1, 0x4a4a5a);
        graphics.drawRoundRect(-5, -5, cardWidth, cardHeight, 4, 4);
        graphics.endFill();

        // 6. Включаем перетаскивание за заголовок
        _titleBar.buttonMode = true;
        _titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);

        trace('DeviceCard: Built card for "${atom.name}"');
    }

    /**
     * Fallback when no widget is available.
     */
    private function createFallbackCard():Void {
        cardWidth = 80;
        cardHeight = 50;

        graphics.beginFill(0x333344);
        graphics.drawRoundRect(0, 0, cardWidth, cardHeight, 4, 4);
        graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        txt.text = atom != null ? atom.name : "?";
        txt.width = 80;
        txt.height = 50;
        txt.selectable = false;
        txt.mouseEnabled = false;
        addChild(txt);
    }

    // =========================================================================
    // CLOSE HANDLER
    // =========================================================================

    private function onCloseClick(e:MouseEvent):Void {
        e.stopPropagation();
        if (_deviceWindow != null) {
            _deviceWindow.removeDevice(this);
        }
    }

    // =========================================================================
    // DRAG LOGIC
    // =========================================================================

    private function onCardMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;
        _cardDragging = true;
        _dragStartX = this.x;
        _dragStartY = this.y;
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;

        // Поднимаем карточку наверх
        if (parent != null) parent.addChild(this);

        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
    }

    private function onCardMouseMove(e:MouseEvent):Void {
        if (!_cardDragging || _isDisposed) return;
        this.x = _dragStartX + (e.stageX - _mouseStartX);
        this.y = _dragStartY + (e.stageY - _mouseStartY);
    }

    private function onCardMouseUp(e:MouseEvent):Void {
        _cardDragging = false;
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }

        // Уведомляем об изменении позиции для автосохранения
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    /**
     * Clean up the card. The widget is returned to the registry (container cleared)
     * but NOT disposed, so it can be reused by NodeView.
     */
    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        if (_titleBar != null) {
            _titleBar.removeEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
        }

        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }

        // Возвращаем виджет в реестр (очищаем контейнер)
        if (_deviceView != null) {
            // Убираем виджет из карточки
            if (this.contains(_deviceView)) {
                removeChild(_deviceView);
            }
            // Очищаем запись о контейнере в реестре
            DeviceViewRegistry.getInstance().clearContainer(atom.id);
            // Деактивируем виджет (он перестанет получать обновления, но данные в атоме останутся)
            _deviceView.deactivate();
            _deviceView = null;
        }

        atom = null;
        _deviceWindow = null;
        _titleBar = null;
        _titleLabel = null;

        trace('DeviceCard: Disposed');
    }
}