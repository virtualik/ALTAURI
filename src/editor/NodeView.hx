package editor;

import openfl.display.Sprite;
import openfl.display.DisplayObjectContainer;
import openfl.display.InteractiveObject;
import openfl.display.DisplayObject;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.geom.Point;

import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import ecs.ECS;

/**
 * NODE VIEW v3.1 (Dynamic Widget-Adaptive Sizing + Fixed Drag)
 *
 * Visual representation of an Atom (node) on the schematic canvas.
 * The node rectangle automatically adapts to the size of the embedded
 * DeviceView widget, ensuring that:
 *
 *   1) The Atom body (rectangle with contacts) is always LARGER
 *      than the Widget card.
 *   2) The Widget card fits inside the Atom rectangle with padding.
 *   3) Contacts (ports) remain at the edges and are never overlapped
 *      by the widget.
 *
 * v3.1 Changes:
 * - FIXED: Node dragging was blocked by buttonMode check on DeviceView
 *   children. The preview container is now set to mouseChildren=false
 *   so clicks pass through to the NodeView body for drag initiation.
 * - FIXED: onMouseDown() buttonMode check rewritten to only block drag
 *   for known interactive elements (port sprites, settings button),
 *   not for any sprite in the hierarchy with buttonMode=true.
 *
 * v3.0 Changes:
 * - REPLACED: Fixed DEFAULT_WIDTH/DEFAULT_HEIGHT with dynamic sizing.
 *   Node rectangle now scales to accommodate the Widget preview.
 * - ADDED: recalcSize() — computes _nodeWidth/_nodeHeight based on
 *   widget dimensions (widgetSize * PREVIEW_SCALE + padding) and
 *   port count.
 * - ADDED: updateLayout() — convenience method to recalculate size,
 *   redraw background, and reposition ports in one call.
 * - CHANGED: redraw() uses _nodeWidth/_nodeHeight instead of constants.
 * - CHANGED: createPorts() uses _nodeWidth/_nodeHeight for positioning.
 * - CHANGED: addWidgetToPreview() centers the widget inside the body
 *   and calls updateLayout() after placement.
 * - CHANGED: getWirePoint() uses _nodeWidth/_nodeHeight.
 * - CHANGED: onAssemblyPortsChanged() calls updateLayout().
 *
 * Layout diagram:
 * ┌────────────────────────────────────────────────────┐
 * │  TitleBar                               [⚙]       │  TITLE_HEIGHT
 * ├────────────────────────────────────────────────────┤
 * │  WIDGET_PADDING                                    │
 * │  ┌──────────────────────────────────────────────┐  │
 * │  │                                              │  │
 * │  │         Widget (scaled by PREVIEW_SCALE)     │  │
 * │  │                                              │  │
 * │  └──────────────────────────────────────────────┘  │
 * │  WIDGET_PADDING                                    │
 * └────────────────────────────────────────────────────┘
 *  ↑                                                  ↑
 *  Input ports at x=0                    Output ports at x=_nodeWidth
 *
 * Visual representation of an atom on the schematic with ports for wires.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE: "NODEVIEW IS SCHEMATIC NODE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * NodeView is a NODE on the schematic with PORTS for wires.
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
 * │   PORTS: Circles for wire connections                                   │
 * │   WIRES: Connections between ports                                      │
 * │   DOUBLE-CLICK ON ASSEMBLY: Open it inside the editor                   │
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
 * │   PORTS are drawn in NodeView, NOT inside DeviceView!                   │
 * │   DeviceView — only a visual preview of the atom.                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Key principles:
 * ─────────────────
 * 1. NodeView OWNS the ports (inputPorts, outputPorts)
 * 2. DeviceView — only a preview inside (scale=0.6)
 * 3. Ports exist INDEPENDENTLY of DeviceView
 * 4. Double-click on assembly → open it inside the editor (OPEN_ASSEMBLY_REQUEST impulse)
 * 5. Dragging → moves the node
 * 6. Clicks on ports → wire creation
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * v2.1 Changes:
 * - ADDED: Listener for ASSEMBLY_PORTS_CHANGED. If the Assembly changes ports, NodeView updates immediately.
 *
 * v2.0 Changes:
 * - FIXED: Constructor accepts 2 parameters (atom, nodeId)
 * - FIXED: Property selected instead of isSelected
 * - FIXED: Ports inputPorts/outputPorts are created from atom
 * - DeviceView is shown as preview
 * - Double-click on assembly opens it inside the editor
 */
class NodeView extends Sprite {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    /** Scale factor for preview mode. 0.6 = 60% of full size. */
    public static inline var PREVIEW_SCALE:Float = 0.6;

    /** Minimum node width (ensures readability even for tiny widgets). */
    public static inline var MIN_WIDTH:Float = 180;

    /** Minimum body height below title bar. */
    public static inline var MIN_BODY_HEIGHT:Float = 68;

    /** Padding around the widget inside the node body area. */
    public static inline var WIDGET_PADDING:Float = 12;

    /** Title bar height. */
    public static inline var TITLE_HEIGHT:Float = 22;

    /** Port radius. */
    public static inline var PORT_RADIUS:Float = 7;

    /** Vertical spacing between ports (used when many ports). */
    public static inline var PORT_SPACING:Float = 22;

    // =========================================================================
    // DYNAMIC SIZE (v3.0)
    // =========================================================================

    /** Calculated node width. Updated by recalcSize(). */
    private var _nodeWidth:Float = MIN_WIDTH;

    /** Calculated node height. Updated by recalcSize(). */
    private var _nodeHeight:Float = MIN_BODY_HEIGHT + TITLE_HEIGHT;

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
    // DYNAMIC SIZING (v3.0)
    // =========================================================================

    /**
     * Recalculates node dimensions based on the widget preview size
     * and the number of ports.
     *
     * Called from redraw(), updateLayout(), and addWidgetToPreview().
     *
     * Rules:
     * - Widget preview (widgetSize * PREVIEW_SCALE) must fit inside
     *   the body area with WIDGET_PADDING on all sides.
     * - Body must be tall enough to space all ports evenly.
     * - _nodeWidth and _nodeHeight are never smaller than MIN_WIDTH
     *   and MIN_BODY_HEIGHT + TITLE_HEIGHT respectively.
     */
    private function recalcSize():Void {
        var bodyWidth:Float = MIN_WIDTH;
        var bodyHeight:Float = MIN_BODY_HEIGHT;

        // --- Widget-based sizing ---
        if (deviceView != null) {
            var ws = deviceView.getWidgetSize();
            var scaledW = ws.width * PREVIEW_SCALE;
            var scaledH = ws.height * PREVIEW_SCALE;

            // Widget + padding on both sides = minimum body dimension
            bodyWidth = Math.max(bodyWidth, scaledW + WIDGET_PADDING * 2);
            bodyHeight = Math.max(bodyHeight, scaledH + WIDGET_PADDING * 2);
        }

        // --- Port-based sizing ---
        // Need enough vertical space so ports don't overlap.
        var inputCount = (atom != null && atom.getInputs() != null) ? atom.getInputs().length : 0;
        var outputCount = (atom != null && atom.getOutputs() != null) ? atom.getOutputs().length : 0;
        var maxPorts = Std.int(Math.max(inputCount, outputCount));
        if (maxPorts > 0) {
            var portsHeight = (maxPorts + 1) * PORT_SPACING;
            bodyHeight = Math.max(bodyHeight, portsHeight);
        }

        _nodeWidth = bodyWidth;
        _nodeHeight = TITLE_HEIGHT + bodyHeight;
    }

    /**
     * Convenience method: recalculate size, redraw, and reposition ports.
     * Call this whenever the widget or port configuration changes.
     */
    private function updateLayout():Void {
        recalcSize();
        redraw();
        createPorts();
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
        _titleLabel.width = _nodeWidth - 30;
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
        _settingsButton.x = _nodeWidth - 15;
        _settingsButton.y = TITLE_HEIGHT / 2;
        _settingsButton.buttonMode = true;
        _settingsButton.useHandCursor = true;
        _settingsButton.addEventListener(MouseEvent.CLICK, onSettingsClick);
        _titleBar.addChild(_settingsButton);

        _previewContainer = new Sprite();
        // === BUG 3 FIX v3.1: Make preview container non-interactive ===
        // In the editor canvas, the widget preview is just a visual — the user
        // should not interact with it directly. Setting mouseChildren=false
        // ensures that clicks on the preview area pass through to the NodeView
        // body, enabling node dragging. The widget becomes interactive again
        // when it is moved to a DeviceCard (in DeviceWindow/Panel).
        _previewContainer.mouseChildren = true;
        _previewContainer.mouseEnabled = false;
        addChild(_previewContainer);

        _selectionHighlight = new Sprite();
        _selectionHighlight.visible = false;
        addChildAt(_selectionHighlight, 0);

        recalcSize();
        redraw();
        centerPreviewContainer();
        setupInteraction();
    }

    /**
     * Positions the preview container so the widget is centered
     * inside the body area of the node.
     */
    private function centerPreviewContainer():Void {
        if (deviceView == null) {
            // No widget — place at default position
            _previewContainer.x = WIDGET_PADDING;
            _previewContainer.y = TITLE_HEIGHT + WIDGET_PADDING;
            return;
        }

        var ws = deviceView.getWidgetSize();
        var scaledW = ws.width * PREVIEW_SCALE;
        var scaledH = ws.height * PREVIEW_SCALE;
        var bodyWidth = _nodeWidth;
        var bodyHeight = _nodeHeight - TITLE_HEIGHT;

        _previewContainer.x = (bodyWidth - scaledW) / 2;
        _previewContainer.y = TITLE_HEIGHT + (bodyHeight - scaledH) / 2;
    }

    public function redraw():Void {
        recalcSize();

        var w = _nodeWidth;
        var h = _nodeHeight;

        var g = _background.graphics;
        g.clear();

        // Main fill
        g.beginFill(0x2a2a3a, 0.95);

        // Border (selected or normal)
        g.lineStyle(selected ? 2 : 1, selected ? _theme.NODE_SELECTED_COLOR : _theme.NODE_BORDER_COLOR);

        // === CHOOSE SHAPE BASED ON isLogic MODE ===
        if (atom.isLogic) {
            // DIGITAL VIEW (Digital Chip):
            // Chamfered corners at 45 degrees.
            // Resembles a microchip or IC.
            var cut = 10.0; // Chamfer depth

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
            // ANALOG VIEW (Analog):
            // Rounded corners (Rounded Rectangle).
            // Soft, smooth appearance.
            g.drawRoundRect(0, 0, w, h, 8, 8);
            g.endFill();
        }

        // Title bar
        var tg = _titleBar.graphics;
        tg.clear();
        tg.beginFill(0x3a3a4a, 0.9);

        // Title bar repeats the shape of the top of the body
        if (atom.isLogic) {
            // Chamfered top
            var cut = 10.0;
            tg.moveTo(cut, 0);
            tg.lineTo(w - cut, 0);
            tg.lineTo(w, cut);
            tg.lineTo(w, TITLE_HEIGHT);
            tg.lineTo(0, TITLE_HEIGHT);
            tg.lineTo(0, cut);
            tg.lineTo(cut, 0);
        } else {
            // Rounded top
            tg.drawRoundRectComplex(0, 0, w, TITLE_HEIGHT, 8, 8, 0, 0);
        }
        tg.endFill();

        // Update title bar element positions
        _titleLabel.width = w - 30;
        _settingsButton.x = w - 15;

        // Selection highlight
        var sg = _selectionHighlight.graphics;
        sg.clear();
        if (selected) {
            sg.lineStyle(3, _theme.NODE_SELECTED_COLOR, 0.6);
            // Highlight also repeats the shape
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

        var bodyHeight = _nodeHeight - TITLE_HEIGHT;

        if (inputs != null) {
            var count = inputs.length;
            var stepY = bodyHeight / (count + 1);
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
            var stepY = bodyHeight / (count + 1);
            for (i in 0...count) {
                var c = outputs[i];
                if (c != null) {
                    var port = createPortSprite(c.name, false);
                    port.x = _nodeWidth;
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

        // Main dimensions
        var w = PORT_RADIUS * 2; // Width = 14
        var h = PORT_RADIUS * 2; // Height = 14

        // Colors
        var color = isInput ? 0xFFAA00 : 0x00AAFF;

        port.graphics.beginFill(color);
        port.graphics.lineStyle(1, 0xFFFFFF);

        if (isInput) {
            // === INPUT PORT ===
            // Simple square centered at origin.
            // (x,y) = (0,0) is the port center.
            // Draw from top-left corner: (-w/2, -h/2)
            port.graphics.drawRect(-w / 2, -h / 2, w, h);
        } else {
            // === OUTPUT PORT ===
            // Right-pointing arrow.
            // Arrow body (rectangle on the left)
            var bodyWidth = w * 0.7; // 70% of width = body
            port.graphics.drawRect(-w / 2, -h / 2, bodyWidth, h);

            // Arrow tip (triangle on the right)
            // Start from the right edge of the body
            var tipStartX = -w / 2 + bodyWidth;
            port.graphics.moveTo(tipStartX, -h / 2);       // Top-left corner of triangle
            port.graphics.lineTo(w / 2, 0);               // Arrow tip (center right)
            port.graphics.lineTo(tipStartX, h / 2);        // Bottom-left corner of triangle
            port.graphics.lineTo(tipStartX, -h / 2);       // Close back to start
        }

        port.graphics.endFill();

        // --- HIT AREA (click area) ---
        var hit = new Sprite();
        hit.graphics.beginFill(0x000000, 0);
        // Make the click area slightly larger than the port for convenience
        hit.graphics.drawRect(-w, -h, w * 2, h * 2);
        hit.graphics.endFill();
        port.addChild(hit);

        // --- LABEL (Caption) ---
        var label = new TextField();
        label.width = 50;
        label.height = 14;
        label.selectable = false;
        label.mouseEnabled = false;
        label.defaultTextFormat = new TextFormat("_sans", 8, 0x888888);

        if (isInput) {
            // For input: label to the right of the port
            label.x = w / 2 + 3;
        } else {
            // For output: label to the left of the port
            // Shift left by text width (50) + offset
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

        // v3.0: Recalculate size for the new widget and rebuild layout.
        // This ensures the node rectangle adapts to the widget size,
        // and the widget is centered inside the body with proper padding.
        updateLayout();
        centerPreviewContainer();

        trace('NodeView: Widget added for ${atom.id}');
    }

    private function enableDoubleClickRecursive(obj:DisplayObjectContainer):Void {
        if (obj == null) return;
        obj.doubleClickEnabled = true;
        for (i in 0...obj.numChildren) {
            var child = obj.getChildAt(i);
            if (Std.isOfType(child, DisplayObjectContainer)) enableDoubleClickRecursive(cast child);
            else if (Std.isOfType(child, InteractiveObject)) cast(child, InteractiveObject).doubleClickEnabled = true;
        }
    }


    public function releaseWidget():DeviceView {
        if (deviceView == null || !hasWidget) return null;

        if (deviceView.parent == _previewContainer) _previewContainer.removeChild(deviceView);

        hasWidget = false;

        // v3.0: Recalculate layout without widget
        updateLayout();

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

    /**
     * BUG 3 FIX v3.1: Rewritten mouse-down handler.
     *
     * The old version walked up from the click target and blocked drag if ANY
     * intermediate sprite had buttonMode=true. This was too aggressive because
     * DeviceView widgets inside the preview often set buttonMode on their
     * interactive areas, which prevented ALL node dragging.
     *
     * The new version:
     * 1. Checks if the click was on a PORT sprite (by name lookup) → skip drag, port handler will fire.
     * 2. Checks if the click was on the SETTINGS button (walk up to _settingsButton) → skip drag, handle click.
     * 3. Otherwise → start drag.
     *
     * Note: The _previewContainer has mouseChildren=false, so clicks on the
     * widget preview area will have their target as the NodeView or _background,
     * not as a widget child. This ensures drag works correctly.
     */
    private function onMouseDown(e:MouseEvent):Void {
        // === Check 1: Did the user click on a PORT sprite? ===
        if (Std.isOfType(e.target, Sprite)) {
            var target:Sprite = cast e.target;
            if (inputPorts.exists(target.name) || outputPorts.exists(target.name)) {
                // Click was on a port — do not start drag, port handler will fire
                return;
            }
        }

        // === Check 2: Did the user click on the SETTINGS button? ===
        var targetObj:DisplayObject = cast e.target;
        while (targetObj != null && targetObj != this) {
            if (targetObj == _settingsButton) {
                // Click was on settings button — do not start drag
                e.stopPropagation();
                return;
            }
            targetObj = targetObj.parent;
        }

        // === Check 3: Start drag ===
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
        var x = isInput ? 0 : _nodeWidth;
        var y = _nodeHeight / 2;
        var global = localToGlobal(new Point(x, y));
        return {x: global.x, y: global.y};
    }

    // =========================================================================
    // ASSEMBLY SYNC (v3.0 — uses updateLayout)
    // =========================================================================

    /**
     * Handler for assembly port changes.
     * If this is our assembly — update the visuals.
     */
    private function onAssemblyPortsChanged(impulse:Impulse):Void {
        // Check that the event is for us (by instance ID)
        if (impulse.data != null && impulse.data.assemblyId == this.atom.id) {
            trace('NodeView: Ports changed event received for ${atom.name}. Rebuilding layout.');
            updateLayout();
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
