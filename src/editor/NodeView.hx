package editor;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import ecs.ECS;
import Lambda;

/**
 * NodeView v2.1 (Port Sync Hotfix)
 * Визуальное представление атома на схеме с портами для проводов.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "NODEVIEW IS SCHEMATIC NODE"
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * NodeView - это УЗЕЛ на схеме с ПОРТАМИ для проводов.
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                         SCHEMATIC (Canvas)                              │
 * │                                                                         │
 * │   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐             │
 * │   │  NodeView   │      │  NodeView   │      │  NodeView   │             │
 * │   │   (atom1)   │──────│   (atom2)   │──────│   (atom3)   │             │
 * │   │             │ wire │             │ wire │             │             │
 * │   │ ○──[Atom]──○│      │ ○──[Atom]──○│      │ ○──[Atom]──○│             │
 * │   │ in       out│      │ in       out│      │ in       out│             │
 * │   └─────────────┘      └─────────────┘      └─────────────┘             │
 * │                                                                         │
 * │   ПОРТЫ: Кружки для подключения проводов                                │
 * │   ПРОВОДА: Соединения между портами                                     │
 * │   ДВОЙНОЙ КЛИК ПО СБОРКЕ: Открыть её внутри редактора                   │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                         NODEVIEW STRUCTURE                              │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────┐       │
 * │   │  [Title Bar: Atom Name]                                     │       │
 * │   ├─────────────────────────────────────────────────────────────┤       │
 * │   │                                                             │       │
 * │   │ ○ in0   ┌─────────────────────┐   out0 ○                    │       │
 * │   │ ○ in1   │    DeviceView       │   out1 ○                    │       │
 * │   │ ○ in2   │    (preview)        │   out2 ○                    │       │
 * │   │         │    scale = 0.6      │                             │       │
 * │   │         └─────────────────────┘                             │       │
 * │   │                                                             │       │
 * │   └─────────────────────────────────────────────────────────────┘       │
 * │                                                                         │
 * │   ПОРТЫ рисуются в NodeView, НЕ внутри DeviceView!                      │
 * │   DeviceView — только визуальный preview атома.                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * Ключевые принципы:
 * ─────────────────
 * 1. NodeView ВЛАДЕЕТ портами (inputPorts, outputPorts)
 * 2. DeviceView — только preview внутри (scale=0.6)
 * 3. Порты существуют НЕЗАВИСИМО от DeviceView
 * 4. Двойной клик по сборке → открыть её внутри редактора (импульс OPEN_ASSEMBLY_REQUEST)
 * 5. Перетаскивание → перемещение узла
 * 6. Клики на портах → создание проводов
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.1 Changes:
 * - ADDED: Listener for ASSEMBLY_PORTS_CHANGED. If the Assembly changes ports, NodeView updates immediately.
 * 
 * v2.0 Changes:
 * - ✅ FIXED: Конструктор принимает 2 параметра (atom, nodeId)
 * - ✅ FIXED: Свойство selected вместо isSelected
 * - ✅ FIXED: Порты inputPorts/outputPorts создаются из атома
 * - DeviceView показывается как preview
 * - Двойной клик по сборке открывает её внутри редактора

 * 
 * v2.0 Changes:
 * - ✅ FIXED: Конструктор принимает 2 параметра (atom, nodeId)
 * - ✅ FIXED: Свойство selected вместо isSelected
 * - ✅ FIXED: Порты inputPorts/outputPorts создаются из атома
 * - DeviceView показывается как preview
 * - Двойной клик по сборке открывает её внутри редактора
 */
class NodeView extends Sprite {
    
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    
    /** Scale factor for preview mode. 0.6 = 60% of full size. */
    public static inline var PREVIEW_SCALE:Float = 0.6;
    
    /** Default size for a node. */
    public static inline var DEFAULT_WIDTH:Float = 180;
    public static inline var DEFAULT_HEIGHT:Float = 90;
    
    /** Title bar height. */
    public static inline var TITLE_HEIGHT:Float = 22;
    
    /** Port radius. */
    public static inline var PORT_RADIUS:Float = 7;
    
    // =========================================================================
    // REFERENCES
    // =========================================================================
    
    /** Atom represented by this NodeView. Can be a simple Atom or an Assembly. */
    public var atom(default, null):Atom;
    
    /** Assembly reference if atom is an Assembly. */
    public var assembly(default, null):Assembly;
    
    /** DeviceView widget (managed by DeviceViewRegistry). Shown as preview inside the node. */
    public var deviceView(default, null):DeviceView;
    
    /** Unique identifier for this NodeView. */
    public var nodeId(default, null):String;
    
    // =========================================================================
    // PORTS
    // =========================================================================
    
    /** Input ports map: contactName -> Sprite. */
    public var inputPorts(default, null):Map<String, Sprite>;
    
    /** Output ports map: contactName -> Sprite. */
    public var outputPorts(default, null):Map<String, Sprite>;
    
    // =========================================================================
    // STATE
    // =========================================================================
    
    public var selected(default, set):Bool = false;
    
    private function set_selected(value:Bool):Bool {
        selected = value;
        updateSelectionVisual();
        return value;
    }
    
    public var isSelected(get, set):Bool;
    private function get_isSelected():Bool return selected;
    private function set_isSelected(value:Bool):Bool { selected = value; return value; }
    
    public var hasWidget(default, null):Bool = false;
    
    // =========================================================================
    // VISUAL COMPONENTS
    // =========================================================================
    
    private var _background:Sprite;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;
    private var _previewContainer:Sprite;
    private var _selectionHighlight:Sprite;
    private var _settingsButton:Sprite;
    private var _theme:EditorTheme;
    
    // =========================================================================
    // DRAG STATE
    // =========================================================================
    
    private var _isDragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;
    
    // =========================================================================
    // CALLBACKS
    // =========================================================================
    
    public var onOpenDeviceWindow:NodeView -> Void;
    public var onSelect:NodeView -> Void;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    
    public function new(atom:Atom, nodeId:String) {
        super();
        this.atom = atom;
        this.nodeId = nodeId;
        _theme = EditorTheme.getInstance();
        
        inputPorts = new Map<String, Sprite>();
        outputPorts = new Map<String, Sprite>();
        
        if (Std.isOfType(atom, Assembly)) {
            this.assembly = cast(atom, Assembly);
        }
        
        buildUI();
        createPorts();
        acquireWidget();
        setupInteraction();
        ECS.register(nodeId, this, this.x, this.y);
        
        // === v2.1 FIX: Listen for Assembly Port Changes ===
        Impulsys.subscribeToImpulse(EventType.ASSEMBLY_PORTS_CHANGED, onAssemblyPortsChanged);
        // ==================================================
        
        trace('NodeView: Created for atom "${atom.name}" (id: ${nodeId})');
    }
    
    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    
    private function buildUI():Void {
        _background = new Sprite();
        _background.doubleClickEnabled = true;
        addChild(_background);
        
        _titleBar = new Sprite();
        _titleBar.doubleClickEnabled = true;
        addChild(_titleBar);
        
        _titleLabel = new TextField();
        _titleLabel.width = DEFAULT_WIDTH - 30;
        _titleLabel.height = TITLE_HEIGHT;
        _titleLabel.x = 5;
        _titleLabel.y = 2;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _titleLabel.defaultTextFormat = new TextFormat(
            "_sans", 11, _theme.NODE_TEXT_COLOR, true, null, null, null, null, "left"
        );
        _titleLabel.text = atom != null ? atom.name : "Node";
        _titleBar.addChild(_titleLabel);
        
        _settingsButton = new Sprite();
        _settingsButton.graphics.beginFill(_theme.NODE_SETTINGS_BTN_COLOR);
        _settingsButton.graphics.drawCircle(0, 0, 8);
        _settingsButton.graphics.endFill();
        _settingsButton.graphics.lineStyle(1, _theme.NODE_SETTINGS_BTN_ICON);
        _settingsButton.graphics.drawCircle(0, 0, 5);
        _settingsButton.graphics.moveTo(-3, 0);
        _settingsButton.graphics.lineTo(3, 0);
        _settingsButton.graphics.moveTo(0, -3);
        _settingsButton.graphics.lineTo(0, 3);
        _settingsButton.x = DEFAULT_WIDTH - 15;
        _settingsButton.y = TITLE_HEIGHT / 2;
        _settingsButton.buttonMode = true;
        _settingsButton.useHandCursor = true;
        _settingsButton.addEventListener(MouseEvent.CLICK, onSettingsClick);
        _titleBar.addChild(_settingsButton);
        
        _previewContainer = new Sprite();
        _previewContainer.x = 25;
        _previewContainer.y = TITLE_HEIGHT + 5;
        addChild(_previewContainer);
        
        _selectionHighlight = new Sprite();
        _selectionHighlight.visible = false;
        addChildAt(_selectionHighlight, 0);
        
        redraw();
        setupInteraction();
    }
    
	public function redraw():Void {
        var w = DEFAULT_WIDTH;
        var h = DEFAULT_HEIGHT;

        var g = _background.graphics;
        g.clear();
        
        // Основная заливка
        g.beginFill(0x2a2a3a, 0.95);

        // Обводка (выделенный или обычный)
        g.lineStyle(selected ? 2 : 1, selected ? _theme.NODE_SELECTED_COLOR : _theme.NODE_BORDER_COLOR);

        // === ВЫБОР ФОРМЫ ПО РЕЖИМУ isLogic ===
        if (atom.isLogic) {
            // ЦИФРОВОЙ ВИД (Digital Chip):
            // Скошенные углы под 45 градусов (Chamfered Rectangle).
            // Напоминает микросхему или чип.
            var cut = 10.0; // Глубина скоса угла
            
            g.moveTo(cut, 0);
            g.lineTo(w - cut, 0);
            g.lineTo(w, cut);
            g.lineTo(w, h - cut);
            g.lineTo(w - cut, h);
            g.lineTo(cut, h);
            g.lineTo(0, h - cut);
            g.lineTo(0, cut);
            g.lineTo(cut, 0);
            g.endFill();

        } else {
            // АНАЛОГОВЫЙ ВИД (Analog):
            // Скругленные углы (Rounded Rectangle).
            // Мягкий, плавный вид.
            g.drawRoundRect(0, 0, w, h, 8, 8);
            g.endFill();
        }

        // Заголовок (TitleBar)
        var tg = _titleBar.graphics;
        tg.clear();
        tg.beginFill(0x3a3a4a, 0.9);
        
        // Заголовок повторяет форму верха корпуса
        if (atom.isLogic) {
            // Скошенный верх
            var cut = 10.0;
            tg.moveTo(cut, 0);
            tg.lineTo(w - cut, 0);
            tg.lineTo(w, cut);
            tg.lineTo(w, TITLE_HEIGHT);
            tg.lineTo(0, TITLE_HEIGHT);
            tg.lineTo(0, cut);
            tg.lineTo(cut, 0);
        } else {
            // Скругленный верх
            tg.drawRoundRectComplex(0, 0, w, TITLE_HEIGHT, 8, 8, 0, 0);
        }
        tg.endFill();

        // Подсветка выделения
        var sg = _selectionHighlight.graphics;
        sg.clear();
        if (selected) {
            sg.lineStyle(3, _theme.NODE_SELECTED_COLOR, 0.6);
            // Подсветка тоже повторяет форму
            if (atom.isLogic) {
                var cut = 12.0;
                sg.moveTo(cut, -3);
                sg.lineTo(w - cut, -3);
                sg.lineTo(w + 3, cut);
                sg.lineTo(w + 3, h - cut);
                sg.lineTo(w - cut, h + 3);
                sg.lineTo(cut, h + 3);
                sg.lineTo(-3, h - cut);
                sg.lineTo(-3, cut);
                sg.lineTo(cut, -3);
            } else {
                sg.drawRoundRect(-3, -3, w + 6, h + 6, 10, 10);
            }
        }
    }
    
    private function updateSelectionVisual():Void {
        _selectionHighlight.visible = selected;
        redraw();
        ECS.setSelected(nodeId, selected);
    }
    
    // =========================================================================
    // PORTS CREATION
    // =========================================================================
    
    private function createPorts():Void {
        for (name in inputPorts.keys()) {
            var port = inputPorts.get(name);
            if (port != null && port.parent != null) port.parent.removeChild(port);
        }
        for (name in outputPorts.keys()) {
            var port = outputPorts.get(name);
            if (port != null && port.parent != null) port.parent.removeChild(port);
        }
        inputPorts.clear();
        outputPorts.clear();
        
        var inputs = atom.getInputs();
        var outputs = atom.getOutputs();
        
        if (inputs != null) {
            var count = inputs.length;
            var stepY = (DEFAULT_HEIGHT - TITLE_HEIGHT - 10) / (count + 1);
            for (i in 0...count) {
                var c = inputs[i];
                if (c != null) {
                    var port = createPortSprite(c.name, true);
                    port.x = 0;
                    port.y = TITLE_HEIGHT + stepY * (i + 1);
                    addChild(port);
                    inputPorts.set(c.name, port);
                }
            }
        }
        
        if (outputs != null) {
            var count = outputs.length;
            var stepY = (DEFAULT_HEIGHT - TITLE_HEIGHT - 10) / (count + 1);
            for (i in 0...count) {
                var c = outputs[i];
                if (c != null) {
                    var port = createPortSprite(c.name, false);
                    port.x = DEFAULT_WIDTH;
                    port.y = TITLE_HEIGHT + stepY * (i + 1);
                    addChild(port);
                    outputPorts.set(c.name, port);
                }
            }
        }
        
        trace('NodeView: Created ${Lambda.count(inputPorts)} input ports, ${Lambda.count(outputPorts)} output ports');
    }
    
    private function createPortSprite(name:String, isInput:Bool):Sprite {
        var port = new Sprite();

        // Основные размеры
        var w = PORT_RADIUS * 2; // Ширина = 14
        var h = PORT_RADIUS * 2; // Высота = 14
        
        // Цвета
        var color = isInput ? 0xFFAA00 : 0x00AAFF;

        port.graphics.beginFill(color);
        port.graphics.lineStyle(1, 0xFFFFFF);

        if (isInput) {
            // === INPUT PORT ===
            // Простой квадрат по центру
            // (x,y) = (0,0) - это центр порта.
            // Рисуем от левого верхнего угла: (-w/2, -h/2)
            port.graphics.drawRect(-w / 2, -h / 2, w, h);
        } else {
            // === OUTPUT PORT ===
            // Стрелка вправо.
            // Тело стрелки (прямоугольник слева)
            var bodyWidth = w * 0.7; // 70% ширины - тело
            port.graphics.drawRect(-w / 2, -h / 2, bodyWidth, h);
            
            // Наконечник стрелки (треугольник справа)
            // Начинаем от правого края тела
            var tipStartX = -w / 2 + bodyWidth;
            port.graphics.moveTo(tipStartX, -h / 2);       // Левый верхний угол треугольника
            port.graphics.lineTo(w / 2, 0);               // Кончик стрелки (центр справа)
            port.graphics.lineTo(tipStartX, h / 2);        // Левый нижний угол треугольника
            port.graphics.lineTo(tipStartX, -h / 2);       // Замыкаем к началу
        }

        port.graphics.endFill();

        // --- HIT AREA (область клика) ---
        var hit = new Sprite();
        hit.graphics.beginFill(0x000000, 0);
        // Делаем область клика чуть больше самого порта для удобства
        hit.graphics.drawRect(-w, -h, w * 2, h * 2);
        hit.graphics.endFill();
        port.addChild(hit);

        // --- LABEL (Подпись) ---
        var label = new TextField();
        label.width = 50;
        label.height = 14;
        label.selectable = false;
        label.mouseEnabled = false;
        label.defaultTextFormat = new TextFormat("_sans", 8, 0x888888);

        if (isInput) {
            // Для входа: подпись справа от порта
            label.x = w / 2 + 3;
        } else {
            // Для выхода: подпись слева от порта
            // Сдвигаем влево на ширину текста (50) + отступ
            label.x = -w / 2 - 53;
        }
        label.y = -7;
        label.text = name;
        port.addChild(label);

        port.name = name;

        port.buttonMode = true;
        port.useHandCursor = true;

        port.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
            e.stopPropagation();
            onPortMouseDown(name, isInput, e);
        });

        port.addEventListener(MouseEvent.RIGHT_CLICK, function(e:MouseEvent) {
            e.stopPropagation();
            onPortRightClick(name, isInput, e);
        });

        return port;
    }
    
    // =========================================================================
    // PREVIEW WIDGET MANAGEMENT
    // =========================================================================
    
    private function acquireWidget():Void {
        if (atom == null) return;
        
        var registry = DeviceViewRegistry.getInstance();
        
        deviceView = registry.getOrCreate(atom, true);
        if (deviceView == null) {
            trace('NodeView: Could not get widget for atom ${atom.id}');
            return;
        }
        
        if (registry.isInDeviceWindow(atom.id)) {
            hasWidget = false;
            trace('NodeView: Widget for ${atom.id} is in DeviceWindow');
            return;
        }
        
        addWidgetToPreview();
    }
    
    private function addWidgetToPreview():Void {
        if (deviceView == null) return;
        
        if (deviceView.parent != null) deviceView.parent.removeChild(deviceView);
        
        deviceView.scaleX = PREVIEW_SCALE;
        deviceView.scaleY = PREVIEW_SCALE;
        _previewContainer.addChild(deviceView);
        
        enableDoubleClickRecursive(deviceView);
        
        DeviceViewRegistry.getInstance().setContainer(atom.id, DeviceViewRegistry.CONTAINER_NODE_VIEW);
        
        if (!deviceView.isActive) deviceView.activate();
        
        hasWidget = true;
        trace('NodeView: Widget added for ${atom.id}');
    }
    
    private function enableDoubleClickRecursive(obj:openfl.display.DisplayObjectContainer):Void {
        if (obj == null) return;
        obj.doubleClickEnabled = true;
        for (i in 0...obj.numChildren) {
            var child = obj.getChildAt(i);
            if (Std.isOfType(child, openfl.display.DisplayObjectContainer)) enableDoubleClickRecursive(cast child);
            else if (Std.isOfType(child, openfl.display.InteractiveObject)) cast(child, openfl.display.InteractiveObject).doubleClickEnabled = true;
        }
    }
    
    
    public function releaseWidget():DeviceView {
        if (deviceView == null || !hasWidget) return null;
        
        if (deviceView.parent == _previewContainer) _previewContainer.removeChild(deviceView);
        
        hasWidget = false;
        trace('NodeView: Released widget for ${atom.id}');
        return deviceView;
    }
    
    public function acceptWidget():Void {
        if (deviceView == null) acquireWidget();
        else addWidgetToPreview();
        trace('NodeView: Accepted widget back for ${atom.id}');
    }
    
    // =========================================================================
    // INTERACTION
    // =========================================================================
    
    private function setupInteraction():Void {
        mouseEnabled = true;
        buttonMode = true;
        useHandCursor = true;
        doubleClickEnabled = true;
        addEventListener(MouseEvent.DOUBLE_CLICK, onDoubleClick);
        addEventListener(MouseEvent.CLICK, onClick);
        addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
    }
    
    private function onDoubleClick(e:MouseEvent):Void {
        trace('NodeView onDoubleClick');
        if (Std.isOfType(e.target, Sprite)) {
            var target:Sprite = cast e.target;
            if (inputPorts.exists(target.name) || outputPorts.exists(target.name)) return;
        }

        e.stopPropagation();

        if (Std.isOfType(atom, Assembly)) {
            trace('NodeView: Double-click detected on Assembly. Emitting request for ID: ${atom.id}');
            Impulsys.quickEmit(EventType.OPEN_ASSEMBLY_REQUEST, { atomId: atom.id });
            return;
        }
        
        trace('NodeView: Double-click on simple atom ${atom.id} (ignored)');
    }
    
    private function onClick(e:MouseEvent):Void {
        if (Std.isOfType(e.target, Sprite)) {
            var target:Sprite = cast e.target;
            if (inputPorts.exists(target.name) || outputPorts.exists(target.name)) return;
        }
        
        if (onSelect != null) onSelect(this);
        
        Impulsys.quickEmit(EventType.NODE_CLICKED, { view: this, id: nodeId, ctrlKey: e.ctrlKey });
        
        e.stopPropagation();
    }
    
    private function onRightClick(e:MouseEvent):Void {
        Impulsys.quickEmit(EventType.NODE_RIGHT_CLICKED, { view: this, id: nodeId, x: e.stageX, y: e.stageY });
        e.stopPropagation();
    }
    
    private function onSettingsClick(e:MouseEvent):Void {
        e.stopPropagation();
        Impulsys.quickEmit(EventType.ATOM_PROPERTIES_REQUEST, { atom: atom, view: this });
    }
    
	private function onMouseDown(e:MouseEvent):Void {
		// === ИСПРАВЛЕНИЕ: Проверяем, не кликнул ли пользователь по вложенному интерактивному элементу ===
		// Если цель события - это кнопка или объект с buttonMode, то перетаскивать узел НЕ нужно.
		var targetObj:openfl.display.DisplayObject = cast e.target;
		while (targetObj != null && targetObj != this) {
			if (Std.isOfType(targetObj, openfl.display.Sprite)) {
				var s = cast(targetObj, openfl.display.Sprite);
				// Если у дочернего спрайта включен buttonMode/useHandCursor, считаем его кнопкой
				if (s.buttonMode || s.useHandCursor) {
					// Останавливаем всплытие, чтобы не сработал Lasso в редакторе,
					// но НЕ запускаем drag. Событие дойдет до дочернего виджета.
					e.stopPropagation();
					return;
				}
			}
			targetObj = targetObj.parent;
		}
		// ==========================================================================================

		if (Std.isOfType(e.target, Sprite)) {
			var target:Sprite = cast e.target;
			// Старая проверка портов остается
			if (inputPorts.exists(target.name) || outputPorts.exists(target.name)) return;
		}

		_dragOffsetX = e.localX;
		_dragOffsetY = e.localY;

		if (parent != null) parent.addChild(this);

		if (stage != null) {
			stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
			stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
		}

		e.stopPropagation();
	}

    private function onMouseMoveDrag(e:MouseEvent):Void {
        var parentPos = parent.globalToLocal(new Point(e.stageX, e.stageY));
        var newX = parentPos.x - _dragOffsetX;
        var newY = parentPos.y - _dragOffsetY;

        var dx = newX - this.x;
        var dy = newY - this.y;

        if (dx != 0 || dy != 0) {
            this.x = newX;
            this.y = newY;
            ECS.updatePosition(nodeId, newX, newY);
            Impulsys.quickEmit(EventType.EDITOR_NODE_MOVED, { id: this.nodeId, view: this, dx: dx, dy: dy });
        }
    }

    private function onMouseUpDrag(e:MouseEvent):Void {
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
        }
        Impulsys.quickEmit(EventType.NODE_DRAG_FINISHED, { view: this, id: nodeId });
    }
    
    private function onMouseUp(e:MouseEvent):Void {
        if (!_isDragging) return;
        _isDragging = false;
        stopDrag();
        if (stage != null) stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        Impulsys.quickEmit(EventType.NODE_DRAG_FINISHED, { view: this, id: nodeId });
    }
    
    // =========================================================================
    // PORT INTERACTION
    // =========================================================================
    
    private function onPortMouseDown(contactName:String, isInput:Bool, e:MouseEvent):Void {
        var port = isInput ? inputPorts.get(contactName) : outputPorts.get(contactName);
        if (port == null) return;
        var globalPos = port.localToGlobal(new Point(0, 0));
        Impulsys.quickEmit(EventType.PORT_DRAG_START, {
            nodeId: nodeId, contactName: contactName, isInput: isInput, startX: globalPos.x, startY: globalPos.y
        });
    }
    
    private function onPortRightClick(contactName:String, isInput:Bool, e:MouseEvent):Void {
        Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED, {
            nodeId: nodeId, contactName: contactName, isInput: isInput, x: e.stageX, y: e.stageY
        });
    }
    
    // =========================================================================
    // POSITION
    // =========================================================================
    
    public function setPosition(x:Float, y:Float):Void {
        this.x = x;
        this.y = y;
        ECS.updatePosition(nodeId, x, y);
    }
    
    public function getPortPosition(contactName:String):{x:Float, y:Float} {
        var port = inputPorts.get(contactName);
        if (port == null) port = outputPorts.get(contactName);
        if (port == null) return {x: this.x, y: this.y};
        var global = port.localToGlobal(new Point(0, 0));
        return {x: global.x, y: global.y};
    }
    
    public function getWirePoint(contactName:String, isInput:Bool):{x:Float, y:Float} {
        var ports = isInput ? inputPorts : outputPorts;
        var port = ports.get(contactName);
        if (port != null) {
            var global = port.localToGlobal(new Point(0, 0));
            return {x: global.x, y: global.y};
        }
        var x = isInput ? 0 : DEFAULT_WIDTH;
        var y = DEFAULT_HEIGHT / 2;
        var global = localToGlobal(new Point(x, y));
        return {x: global.x, y: global.y};
    }

    // =========================================================================
    // ASSEMBLY SYNC (v2.1)
    // =========================================================================

    /**
     * Обработчик изменения портов сборки.
     * Если это наша сборка — обновляем визуал.
     */
    private function onAssemblyPortsChanged(impulse:Impulse):Void {
        // Проверяем, что событие для нас (по ID экземпляра)
        if (impulse.data != null && impulse.data.assemblyId == this.atom.id) {
            trace('NodeView: Ports changed event received for ${atom.name}. Rebuilding ports.');
            createPorts();
            redraw(); 
        }
    }
    
    // =========================================================================
    // DISPOSE
    // =========================================================================
    
    public function dispose():Void {
        // === v2.1 FIX: Unsubscribe ===
        Impulsys.removeImpulse(EventType.ASSEMBLY_PORTS_CHANGED, onAssemblyPortsChanged);
        // ==============================

        ECS.unregister(nodeId);
        
        removeEventListener(MouseEvent.DOUBLE_CLICK, onDoubleClick);
        removeEventListener(MouseEvent.CLICK, onClick);
        removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        
        if (_settingsButton != null) {
            _settingsButton.removeEventListener(MouseEvent.CLICK, onSettingsClick);
        }
        
        if (deviceView != null && deviceView.parent == _previewContainer) {
            _previewContainer.removeChild(deviceView);
        }
        
        inputPorts.clear();
        outputPorts.clear();
        
        deviceView = null;
        atom = null;
        assembly = null;
        onOpenDeviceWindow = null;
        onSelect = null;
        
        _background = null;
        _titleBar = null;
        _titleLabel = null;
        _previewContainer = null;
        _selectionHighlight = null;
        _settingsButton = null;
        
        trace('NodeView: Disposed');
    }
}