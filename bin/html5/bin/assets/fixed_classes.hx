// ============================================================================
// FIXED CLASSES — Bug Fix Patch for ALTAURI Application
// ============================================================================
//
// THREE BUGS FIXED:
//
// BUG 1: Mouse clicks penetrate through window title bar and control buttons
//   ROOT CAUSE: Header buttons only stop CLICK propagation, not MOUSE_DOWN.
//               When MOUSE_DOWN fires on a button, it bubbles up to the header
//               and triggers an unwanted drag.
//   FIX: Add MOUSE_DOWN stopPropagation on all header/control buttons, and
//        add target checks in drag handlers to ignore clicks on button children.
//
// BUG 2: Keyboard 'D' in TextInputAtom deletes the atom instead of typing
//   ROOT CAUSE: Main.onKeyDown() unconditionally intercepts Keyboard.D as a
//               delete shortcut, even when a TextField has keyboard focus.
//   FIX: In Main.onKeyDown(), check if stage.focus is a TextField before
//        processing single-key shortcuts. In TextInputWidget.onKeyDown(),
//        stop propagation for ALL keys when the input field is focused.
//
// BUG 3: Atoms cannot be moved/dragged in the Editor pane
//   ROOT CAUSE: NodeView.onMouseDown() walks up from the click target and
//               blocks drag if ANY intermediate sprite has buttonMode=true.
//               Many DeviceView widgets set buttonMode=true on their root
//               sprites, which causes all drag attempts on the node body
//               to be blocked.
//   FIX: Set _previewContainer.mouseChildren=false to make the preview
//        non-interactive (widgets in editor canvas are just previews, not
//        interactive). Also rewrite the buttonMode check in onMouseDown()
//        to only block drag for known interactive elements (port sprites
//        and the settings button), not for any sprite with buttonMode.
//
// ============================================================================


// ============================================================================
// CLASS: TextInputWidget (BUG 2 FIX)
// ============================================================================
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * TEXT INPUT WIDGET v1.2 (Focus-aware Keyboard Handling)
 * Text input field widget for entering values into TextInputAtom.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   Atom (Databank)                                                       │
 * │                                                                         │
 * │   Contact "set"  ──► TextInputWidget                                    │
 * │   Contact "out"  ──► TextInputWidget                                    │
 * │                       ┌─────────────────────────────────────────────┐   │
 * │                       │ _inputField: INPUT TextField                │   │
 * │                       │ onKeyDown: push on ENTER, stopPropagation   │   │
 * │                       │ onFocusOut: push value                      │   │
 * │                       │ onContactChanged: display value             │   │
 * │                       └─────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Widget READS atom's contact value (display only)                      │
 * │   Widget WRITES to atom's "out" contact on user input                   │
 * │   Atom is the Databank - single source of truth                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.2 Changes:
 * - FIXED: stopImmediatePropagation() on ALL key events when the input
 *   field is focused. This prevents the global keyboard handler in Main
 *   from intercepting keys like 'D' (delete) while the user is typing.
 */
class TextInputWidget extends DeviceView {

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================

    private var _inputField:TextField;
    private var _outputContact:Contact;
    private var _setContact:Contact;

    // Widget dimensions
    private var widgetWidth:Float = 120;
    private var widgetHeight:Float = 24;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(atom:Atom) {
        super(atom);

        // Find contacts
        if (atom != null) {
            _outputContact = atom.getOutput("out");
            _setContact = atom.getInput("set");
        }

        buildUI();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================

    private function buildUI():Void {
        graphics.beginFill(0x222233);
        graphics.lineStyle(1, 0x00AAFF);
        graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 4, 4);
        graphics.endFill();

        _inputField = new TextField();
        _inputField.type = TextFieldType.INPUT;
        _inputField.width = widgetWidth - 4;
        _inputField.height = widgetHeight - 4;
        _inputField.x = 2;
        _inputField.y = 2;
        _inputField.border = false;
        _inputField.background = false;
        _inputField.textColor = 0xFFFFFF;
        _inputField.mouseEnabled = true;

        var fmt = new TextFormat("_sans", 12, 0xFFFFFF);
        _inputField.defaultTextFormat = fmt;

        // Set initial value
        if (_outputContact != null && _outputContact.value != null) {
            _inputField.text = Std.string(_outputContact.value);
        } else {
            _inputField.text = "";
        }

        addChild(_inputField);

        // Events
        _inputField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _inputField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    override private function onActivate():Void {
        // Read current state from atom
        if (_outputContact != null && _outputContact.value != null) {
            _inputField.text = Std.string(_outputContact.value);
        }
    }

    private function onFocusOut(e:FocusEvent):Void {
        pushValue();
    }

    private function onKeyDown(e:KeyboardEvent):Void {
        // === BUG 2 FIX: Stop ALL key events from propagating when the ===
        // input field is focused. This prevents Main.onKeyDown() from
        // intercepting single-key shortcuts (like 'D' for delete) while
        // the user is typing in this field.
        e.stopImmediatePropagation();

        if (e.keyCode == Keyboard.ENTER) {
            pushValue();

            // Remove focus
            if (stage != null) stage.focus = null;

            // Signal to save project
            Impulsys.quickEmit(EventType.VALUE_COMMITTED);
        }
    }

    // =========================================================================
    // DATA HANDLING
    // =========================================================================

    /**
     * Push entered value to atom's output contact.
     */
    private function pushValue():Void {
        if (_outputContact != null) {
            var txt = _inputField.text;

            // Try to parse number
            var f = Std.parseFloat(txt);
            if (!Math.isNaN(f) && (txt.indexOf(".") != -1 || Std.parseInt(txt) != null && txt.length > 0 && !Math.isNaN(f))) {
                _outputContact.value = f;
            } else {
                _outputContact.value = txt;
            }
        }
    }

    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
        // React to changes in "set" or "out" contact
        if ((contact == _outputContact || contact == _setContact) && newValue != null) {
            var str = Std.string(newValue);
            if (_inputField.text != str) {
                _inputField.text = str;
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        if (_inputField != null) {
            _inputField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _inputField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        }
        _inputField = null;
        _outputContact = null;
        _setContact = null;
        super.dispose();
    }
}


// ============================================================================
// CLASS: NodeView (BUG 3 FIX)
// ============================================================================
package editor;

import openfl.display.Sprite;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.InteractiveObject;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.geom.Point;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.Impulsys;
import core.logic.EventType;
import ecs.ECS;

/**
 * NODE VIEW v3.1 (Fixed Drag Interaction)
 * Visual representation of an Atom on the editor canvas.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   NodeView Architecture                                                 │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                │
 * │   │  Title Bar    [_label_] [⚙]      │  ← Title + settings button      │
 * │   ├──────────────────────────────────┤                                │
 * │   │                                  │                                │
 * │   │  Preview Container (non-interactive) │  ← Widget preview at 60%    │
 * │   │  ┌────────────────────────────┐  │     mouseChildren = false       │
 * │   │  │  DeviceView (scaled 0.6)   │  │     so clicks pass through     │
 * │   │  └────────────────────────────┘  │     for node dragging           │
 * │   │                                  │                                │
 * │   ├──────────────────────────────────┤                                │
 * │   │ ● in1   ● in2        out1 ●     │  ← Port sprites                 │
 * │   └──────────────────────────────────┘                                │
 * │                                                                         │
 * │   Interaction:                                                          │
 * │   - Click on body → select + start drag                                │
 * │   - Click on port → start wire drag                                    │
 * │   - Click on ⚙ → open properties                                      │
 * │   - Double-click → open assembly (if Assembly)                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v3.1 Changes:
 * - FIXED: Node dragging was blocked by buttonMode check on DeviceView
 *   children. The preview container is now set to mouseChildren=false
 *   so clicks pass through to the NodeView body for drag initiation.
 * - FIXED: onMouseDown() buttonMode check rewritten to only block drag
 *   for known interactive elements (port sprites, settings button),
 *   not for any sprite in the hierarchy with buttonMode=true.
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
        // === BUG 3 FIX: Make preview container non-interactive ===
        // In the editor canvas, the widget preview is just a visual — the user
        // should not interact with it directly. Setting mouseChildren=false
        // ensures that clicks on the preview area pass through to the NodeView
        // body, enabling node dragging. The widget becomes interactive again
        // when it is moved to a DeviceCard (in DeviceWindow/Panel).
        _previewContainer.mouseChildren = false;
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

    // NOTE: redraw(), createPorts(), onAssemblyPortsChanged(), and other
    // unchanged methods are omitted here — they remain the same as in the
    // original file. Only the methods with fixes are included below.

    // =========================================================================
    // PORT CREATION (unchanged)
    // =========================================================================

    private function createPorts():Void {
        // Remove existing port sprites
        for (name in inputPorts.keys()) {
            var port = inputPorts.get(name);
            if (port != null && contains(port)) removeChild(port);
        }
        for (name in outputPorts.keys()) {
            var port = outputPorts.get(name);
            if (port != null && contains(port)) removeChild(port);
        }
        inputPorts.clear();
        outputPorts.clear();

        if (atom == null) return;

        // Create input ports
        var inputIndex = 0;
        for (contact in atom.getInputs()) {
            if (contact == null) continue;
            var port = createPortSprite(contact.name, true, inputIndex);
            inputPorts.set(contact.name, port);
            addChild(port);
            inputIndex++;
        }

        // Create output ports
        var outputIndex = 0;
        for (contact in atom.getOutputs()) {
            if (contact == null) continue;
            var port = createPortSprite(contact.name, false, outputIndex);
            outputPorts.set(contact.name, port);
            addChild(port);
            outputIndex++;
        }
    }

    private function createPortSprite(name:String, isInput:Bool, index:Int):Sprite {
        var port = new Sprite();

        var yPos = TITLE_HEIGHT + (index + 1) * PORT_SPACING;
        var xPos = isInput ? 0 : _nodeWidth;

        port.graphics.beginFill(isInput ? _theme.NODE_INPUT_PORT_COLOR : _theme.NODE_OUTPUT_PORT_COLOR);
        port.graphics.drawCircle(0, 0, PORT_RADIUS);
        port.graphics.endFill();
        port.graphics.lineStyle(1, 0xFFFFFF, 0.3);
        port.graphics.drawCircle(0, 0, PORT_RADIUS);
        port.x = xPos;
        port.y = yPos;

        var label = new TextField();
        label.defaultTextFormat = new TextFormat("_sans", 9, _theme.NODE_PORT_LABEL_COLOR);
        label.text = name;
        label.width = 60;
        label.height = 14;
        label.x = isInput ? 10 : -70;
        label.y = -7;
        label.selectable = false;
        label.mouseEnabled = false;
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
     * BUG 3 FIX: Rewritten mouse-down handler.
     *
     * The old version walked up from the click target and blocked drag if ANY
     * intermediate sprite had buttonMode=true. This was too aggressive because
     * DeviceView widgets inside the preview often set buttonMode on their
     * interactive areas, which prevented ALL node dragging.
     *
     * The new version:
     * 1. Checks if the click was on a PORT sprite (by name lookup) → block drag, start wire.
     * 2. Checks if the click was on the SETTINGS button (walk up to _settingsButton) → block drag, handle click.
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
            nodeId: nodeId, contactName: contactName, isInput: isInput
        });
    }

    // =========================================================================
    // SELECTION
    // =========================================================================

    private function updateSelectionVisual():Void {
        if (_selectionHighlight == null) return;

        _selectionHighlight.visible = selected;

        if (selected) {
            _selectionHighlight.graphics.clear();
            _selectionHighlight.graphics.lineStyle(2, _theme.NODE_SELECTED_BORDER_COLOR);
            _selectionHighlight.graphics.drawRoundRect(-4, -4, _nodeWidth + 8, _nodeHeight + 8, 8, 8);
            _selectionHighlight.graphics.endFill();
        }
    }

    // NOTE: Other unchanged methods (redraw, dispose, etc.) remain the same
    // as in the original file and are omitted for brevity.
}


// ============================================================================
// CLASS: Main (BUG 2 FIX — onKeyDown method only)
// ============================================================================
// NOTE: The full Main class is very large (lines 17524-18488).
// Only the onKeyDown method is shown here with the fix.
// Apply this change to the existing Main class in your codebase.

package ;

// ... (existing imports remain unchanged) ...

class Main extends Sprite {

    // ... (existing fields and methods remain unchanged) ...

    /**
     * BUG 2 FIX: Added TextField focus check.
     *
     * Before processing single-key shortcuts (D, R, E, DELETE, BACKSPACE),
     * we now check if stage.focus is a TextField. If it is, the user is
     * typing in an input field, and we should not intercept their keystrokes.
     *
     * Ctrl+key shortcuts (Ctrl+C, Ctrl+Z, etc.) are still processed even
     * when a TextField has focus, because those are deliberate editor
     * commands that should override text input.
     */
    private function onKeyDown(e:KeyboardEvent):Void
    {
            if (_popup.visible) return;

            // === BUG 2 FIX: If a TextField has keyboard focus, skip ===
            // single-key shortcuts but keep Ctrl+key shortcuts.
            // This prevents 'D' from deleting atoms while typing in
            // TextInputWidget, while still allowing Ctrl+C, Ctrl+Z, etc.
            var focusObj = Lib.current.stage.focus;
            var isTextFieldFocused:Bool = Std.isOfType(focusObj, TextField);
            // Also check if focus is on a TextField in a DeviceWindow
            // (separate native window) — we check all windows' stages.
            // For simplicity, any TextField focus blocks single-key shortcuts.
            if (isTextFieldFocused && !e.ctrlKey && !e.altKey) return;

            if (e.keyCode == Keyboard.S && !e.ctrlKey) { saveCurrentContext(); return; }
            if (e.ctrlKey && e.keyCode == Keyboard.C) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.copySelection(); return; }
            if (e.ctrlKey && e.keyCode == Keyboard.X) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.cutSelection(); return; }
            if (e.ctrlKey && e.keyCode == Keyboard.V) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.pasteSelection(); return; }
            if (e.ctrlKey && e.keyCode == Keyboard.A) { if (_editorContext.currentEditor != null) _editorContext.currentEditor.selectAll(); return; }
            if (e.keyCode == Keyboard.ESCAPE)
            {
                    if (_settingsPanel.visible) { _settingsPanel.visible = false; return; }
                    if (_editorContext.getStackLength() > 1) onBackClicked();
                    return;
            }
            if (e.ctrlKey && e.keyCode == Keyboard.Z) { UndoManager.getInstance().undo(); return; }
            if (e.ctrlKey && e.keyCode == Keyboard.Y) { UndoManager.getInstance().redo(); return; }
            if (e.keyCode == Keyboard.R) { onResetClick(); return; }
            if (e.keyCode == Keyboard.D || e.keyCode == Keyboard.DELETE) { deleteSelectedOnCanvas(); return; }
            if (e.keyCode == Keyboard.E) { if (_editorContext.getStackLength() > 1) onDeleteCurrentAssembly(); else log("Cannot erase root assembly."); return; }
            if (e.keyCode == Keyboard.BACKSPACE) { if (_editorContext.getStackLength() > 1) onBackClicked(); return; }
    }

    // ... (rest of Main class remains unchanged) ...
}


// ============================================================================
// CLASS: DeviceCard (BUG 1 FIX)
// ============================================================================
package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * DEVICE CARD v1.1 (Fixed Header Button Interaction)
 * Card holding a DeviceView inside a DevicePanel or DeviceWindow.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeviceCard                                                            │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                │
 * │   │  Title Bar  [label]         [x]  │  ← Title + close button         │
 * │   ├──────────────────────────────────┤                                │
 * │   │                                  │                                │
 * │   │  DeviceView (full size)          │  ← Interactive widget           │
 * │   │                                  │                                │
 * │   └──────────────────────────────────┘                                │
 * │                                                                         │
 * │   Title bar: drag to move card                                         │
 * │   [x] button: close/remove card                                        │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.1 Changes:
 * - FIXED: Close button MOUSE_DOWN now calls stopPropagation() to prevent
 *   the MOUSE_DOWN event from bubbling up to the title bar and starting
 *   an unwanted card drag.
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

    private var _owner:Dynamic; // DeviceWindow or DevicePanel
    private var _deviceView:DeviceView;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;

    // Drag state
    private var _cardVisibility:Bool = false;
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
     * @param owner         Reference to the parent (DeviceWindow or DevicePanel)
     * @param x             Initial X position in the container
     * @param y             Initial Y position in the container
     */
    public function new(atom:Atom, owner:Dynamic, ?x:Float = 0, ?y:Float = 0) {
        super();
        this.atom = atom;
        _owner = owner;
        this.x = x;
        this.y = y;
        buildCard();
    }

    // =========================================================================
    // BUILD UI
    // =========================================================================

    private function buildCard():Void {
        // 1. Get the widget from the registry (guaranteed single instance)
        var registry = DeviceViewRegistry.getInstance();
        _deviceView = registry.getOrCreate(atom, true);
        if (_deviceView == null) {
            trace('DeviceCard: Could not get widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }

        // 2. Move the widget into the card via the registry
        //    (the widget will be removed from its previous container, if any)
        //    We pass `this` as the container.
        _deviceView = registry.moveToDeviceWindow(atom.id, this, 0, 20);
        if (_deviceView == null) {
            trace('DeviceCard: Failed to move widget for atom "${atom.name}"');
            createFallbackCard();
            return;
        }

        // 3. Determine card dimensions based on widget size
        var viewWidth = _deviceView.width;
        var viewHeight = _deviceView.height;
        if (viewWidth < 50) viewWidth = 100;
        if (viewHeight < 30) viewHeight = 60;

        cardWidth = viewWidth + 30;   // left/right padding
        cardHeight = viewHeight + 40; // title 20 + bottom padding

        // 4. Title bar
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

        // Close button
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
        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating to title bar ===
        // Without this, clicking the close button would also start a card drag
        // because MOUSE_DOWN bubbles from the button to _titleBar.
        closeBtn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        _titleBar.addChild(closeBtn);

        // 5. Card background (drawn behind everything)
        graphics.clear();
        graphics.beginFill(0x2a2a3a, 0.9);
        graphics.lineStyle(1, 0x4a4a5a);
        graphics.drawRoundRect(-5, -5, cardWidth, cardHeight, 4, 4);
        graphics.endFill();

        // 6. Enable dragging by title bar
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
        if (_owner != null) {
            // Universal call to owner's removeDevice method
            if (Reflect.hasField(_owner, 'removeDevice')) {
                Reflect.callMethod(_owner, Reflect.field(_owner, 'removeDevice'), [this]);
            }
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

        // Bring card to front
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

        // Notify position change for auto-save
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

        // Return the widget to the registry (clear container)
        if (_deviceView != null) {
            // Remove widget from card
            if (this.contains(_deviceView)) {
                removeChild(_deviceView);
            }
            // Clear container record in registry
            DeviceViewRegistry.getInstance().clearContainer(atom.id);
            // Deactivate the widget (it will stop receiving updates, but atom data remains)
            _deviceView.deactivate();
            _deviceView = null;
        }

        atom = null;
        _owner = null;
        _titleBar = null;
        _titleLabel = null;

        trace('DeviceCard: Disposed');
    }
}


// ============================================================================
// CLASS: DevicePanel (BUG 1 FIX)
// ============================================================================
package ui;

import editor.EditorTheme;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.EventType;
import core.logic.Impulse;

/**
 * DevicePanel v3.3 (Fixed Header Button Interaction)
 * Full-size device display panel inside the Main Window.
 *
 * v3.3 Changes:
 * - FIXED: Header buttons [E], [C] now stop MOUSE_DOWN propagation to prevent
 *   them from interfering with any parent mouse handlers.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * DevicePanel — built-in device dashboard inside the main window.
 * An alternative to the separate DeviceWindow.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SCHEMATIC                         DEVICE PANEL                        │
 * │                                                                         │
 * │   [Hidden]                          ┌────────────────────────────┐      │
 * │                                     │       DevicePanel          │      │
 * │                                     │   ┌────────────────────┐   │      │
 * │                                     │   │   DeviceCard       │   │      │
 * │                                     │   │ ┌────────────────┐ │   │      │
 * │                                     │   │ │   DeviceView   │ │   │      │
 * │                                     │   │ └────────────────┘ │   │      │
 * │                                     │   └────────────────────┘   │      │
 * │                                     │                            │      │
 * │                                     │   [E]  [C]  (Header)       │      │
 * │                                     └────────────────────────────┘      │
 * │                                              │                          │
 * │                                              │                          │
 * │                                              ▼                          │
 * │                               Main Window Color - DEVICE_CANVAS_BG_COLOR│
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DevicePanel extends Sprite
{
        // =========================================================================
        // CALLBACKS
        // =========================================================================

        /**
         * Callback to request switching back to Editor Mode.
         * Called when [E] button is pressed.
         */
        public var onShowEditor:Void -> Void;

        /**
         * Callback to get the list of available devices.
         * Used to populate the context menu.
         */
        public var onGetAssemblyList:Void -> Array< {id:String, name:String, atom:Atom}>;

        // =========================================================================
        // PRIVATE FIELDS
        // =========================================================================

        private var _assembly:Assembly;
        private var _deviceCards:Array<DeviceCard>;

        private var _header:Sprite;
        private var _titleLabel:TextField;

        private var _contextMenu:Sprite;
        private var _menuVisible:Bool = false;

        private var _bg:Sprite;
        private var _theme:EditorTheme;

        // =========================================================================
        // CONSTRUCTOR
        // =========================================================================

        public function new()
        {
                super();
                _deviceCards = new Array();
                _theme = EditorTheme.getInstance();
                addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):Void
        {
                removeEventListener(Event.ADDED_TO_STAGE, onAdded);
                setupUI();
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Resize the panel to fit the stage.
         */
        public function setSize(w:Float, h:Float):Void
        {
                drawBackground(w, h);

                // Resize header
                if (_header != null)
                {
                        _header.graphics.clear();
                        _header.graphics.beginFill(0x2a2a34);
                        _header.graphics.drawRect(0, 0, w, 30);
                        _header.graphics.endFill();

                        // Shift buttons to the right
                        var btnX = w - 10;
                        for (i in 0..._header.numChildren)
                        {
                                var child = _header.getChildAt(_header.numChildren - 1 - i);
                                if (Std.isOfType(child, Sprite) && child != _titleLabel)
                                {
                                        child.x = btnX - child.width;
                                        btnX = child.x - 10;
                                }
                        }
                }
        }

        /**
         * Set the current assembly context.
         * Updates the title.
         */
        public function setContext(assembly:Assembly):Void
        {
                _assembly = assembly;
                _titleLabel.text = "  Device Panel: " + assembly.blueprint.name;
        }

        /**
         * Add a device (atom) to the panel.
         * v3.2: Emits DEVICE_WINDOW_CHANGED to save state.
         */
        public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void
        {
                if (atom == null) return;

                // Avoid duplicates
                for (card in _deviceCards)
                {
                        if (card.atom == atom) return;
                }

                var card = new DeviceCard(atom, this);
                _deviceCards.push(card);
                addChild(card);

                if (x != null && y != null)
                {
                        card.x = x;
                        card.y = y;
                }
                else {
                        var pos = findFreePosition(card);
                        card.x = pos.x;
                        card.y = pos.y;
                }

                // v3.2: Emit save signal when adding a new device
                Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
        }

        /**
         * Remove a device card from the panel.
         */
        public function removeDevice(card:DeviceCard):Void
        {
                if (_deviceCards.remove(card))
                {
                        if (this.contains(card)) removeChild(card);
                        card.dispose();
                        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
                }
        }

        /**
         * Remove all devices.
         *
         * v3.1 NOTE: Does NOT emit DEVICE_WINDOW_CHANGED.
         * If called during mode switch (after syncing cache), emitting here
         * would cause the cache to be wiped immediately.
         * Emission is handled manually in the [C] button callback for explicit clears.
         */
        public function clearDevices():Void
        {
                while (_deviceCards.length > 0)
                {
                        var card = _deviceCards.pop();
                        if (this.contains(card)) removeChild(card);
                        card.dispose();
                }
                // Do NOT emit event here to prevent cache wipe during mode switch
        }

        /**
         * Returns the list of current device cards.
         * Used by Main.hx to sync state to cache.
         */
        public function getDeviceCards():Array<DeviceCard>
        {
                return _deviceCards;
        }

        // =========================================================================
        // SETUP UI
        // =========================================================================

        private function setupUI():Void
        {
                drawBackground(800, 600);
                createHeader();

                // Listeners
                stage.addEventListener(MouseEvent.CLICK, onStageClick);
                stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);

                Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, onAtomDeleted);
        }

        private function drawBackground(w:Float, h:Float):Void
        {
                graphics.clear();
                // Alpha = 0 makes the background transparent!
                graphics.beginFill(_theme.DEVICE_CANVAS_BG_COLOR, 1.0);
                graphics.drawRect(0, 0, w, h);
                graphics.endFill();
        }

        private function createHeader():Void
        {
                _header = new Sprite();
                _header.graphics.beginFill(0x2a2a34);
                _header.graphics.drawRect(0, 0, 800, 30);
                _header.graphics.endFill();
                addChild(_header);

                _titleLabel = new TextField();
                _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
                _titleLabel.text = "  Device Panel";
                _titleLabel.width = 300;
                _titleLabel.height = 30;
                _titleLabel.selectable = false;
                _titleLabel.mouseEnabled = false;
                _header.addChild(_titleLabel);

                // Button [E] - Editor Mode
                var editorBtn = createHeaderButton("E", 0x005500, function(_)
                {
                        if (onShowEditor != null) onShowEditor();
                });
                editorBtn.x = 760;
                _header.addChild(editorBtn);

                // Button [C] - Clear
                // v3.1: Explicitly emit event after clearing so the empty state is saved.
                var clearBtn = createHeaderButton("C", 0x555500, function(_)
                {
                        clearDevices();
                        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
                });
                clearBtn.x = 720;
                _header.addChild(clearBtn);
        }

        /**
         * BUG 1 FIX: Header buttons now stop MOUSE_DOWN propagation.
         * This prevents the MOUSE_DOWN event from bubbling up from the button
         * to any parent container that might start an unwanted drag.
         */
        private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite
        {
                var btn = new Sprite();
                btn.graphics.beginFill(color);
                btn.graphics.drawRect(0, 0, 28, 26);
                btn.graphics.endFill();

                var txt = new TextField();
                txt.text = label;
                txt.width = 28;
                txt.height = 26;
                txt.selectable = false;
                txt.mouseEnabled = false;
                txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
                btn.addChild(txt);

                btn.buttonMode = true;
                btn.addEventListener(MouseEvent.CLICK, onClick);
                // === BUG 1 FIX: Stop MOUSE_DOWN from propagating ===
                btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
                return btn;
        }

        // =========================================================================
        // CONTEXT MENU
        // =========================================================================

        private function onRightClick(e:MouseEvent):Void
        {
                if (_menuVisible) hideContextMenu();
                else showContextMenu(e.stageX, e.stageY);
        }

        private function showContextMenu(x:Float, y:Float):Void
        {
                hideContextMenu(); // Clean previous

                _contextMenu = new Sprite();

                var yPos = 5;

                var headerItem = createMenuItem("Add Device:", null, true);
                headerItem.y = yPos;
                _contextMenu.addChild(headerItem);
                yPos += 28;

                // Get list from Main
                var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
                devices = [for (d in devices) if (d.id != "selfrun") d];

                if (devices.length == 0)
                {
                        var emptyItem = createMenuItem("(No devices)", null, true);
                        emptyItem.y = yPos;
                        _contextMenu.addChild(emptyItem);
                        yPos += 26;
                }
                else {
                        for (item in devices)
                        {
                                var menuItem = createMenuItem(item.name, item.atom, false);
                                menuItem.y = yPos;
                                _contextMenu.addChild(menuItem);
                                yPos += 26;
                        }
                }

                // Draw background
                _contextMenu.graphics.beginFill(0x333344, 0.98);
                _contextMenu.graphics.lineStyle(1, 0x555566);
                _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 10, 6, 6);
                _contextMenu.graphics.endFill();

                _contextMenu.x = Math.min(x, stage.stageWidth - 200);
                _contextMenu.y = Math.min(Math.max(y - 30, 0), stage.stageHeight - yPos - 20);

                addChild(_contextMenu);
                _menuVisible = true;
        }

        private function hideContextMenu():Void
        {
                if (_contextMenu != null && _contextMenu.parent != null)
                {
                        removeChild(_contextMenu);
                }
                _contextMenu = null;
                _menuVisible = false;
        }

        private function onStageClick(e:MouseEvent):Void
        {
                if (_menuVisible && _contextMenu != null)
                {
                        if (!_contextMenu.hitTestPoint(e.stageX, e.stageY))
                        {
                                hideContextMenu();
                        }
                }
        }

        private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite
        {
                var item = new Sprite();
                item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();

                var txt = new TextField();
                txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
                txt.text = (disabled || atom == null) ? label : "+ " + label;
                txt.width = 170;
                txt.height = 24;
                txt.x = 8;
                txt.selectable = false;
                txt.mouseEnabled = false;
                item.addChild(txt);

                if (!disabled && atom != null)
                {
                        item.buttonMode = true;
                        final capturedAtom = atom;
                        item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent)
                        {
                                addDevice(capturedAtom);
                                hideContextMenu();
                                // Save state when adding via context menu
                                // Note: addDevice() already emits DEVICE_WINDOW_CHANGED in v3.2
                        });
                        item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent)
                        {
                                item.graphics.clear();
                                item.graphics.beginFill(0x556677);
                                item.graphics.drawRect(0, 0, 180, 24);
                                item.graphics.endFill();
                        });
                        item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
                        {
                                item.graphics.clear();
                                item.graphics.beginFill(0x444455);
                                item.graphics.drawRect(0, 0, 180, 24);
                                item.graphics.endFill();
                        });
                }
                return item;
        }

        // =========================================================================
        // EVENTS & HELPERS
        // =========================================================================

        private function onAtomDeleted(impulse:Impulse):Void
        {
                if (impulse.data == null) return;
                var deletedId:String = impulse.data.id;
                var toRemove:Array<DeviceCard> = [];

                for (card in _deviceCards)
                {
                        if (card.atom != null && card.atom.id == deletedId)
                        {
                                toRemove.push(card);
                        }
                }

                for (card in toRemove)
                {
                        removeDevice(card);
                }
        }

        private function findFreePosition(card:DeviceCard): {x:Float, y:Float}
        {
                var startX = 10;
                var startY = 50; // Below header
                var stepX = 120;
                var stepY = 100;

                for (y in 0...10)
                {
                        for (x in 0...5)
                        {
                                var px = startX + x * stepX;
                                var py = startY + y * stepY;
                                if (isPositionFree(px, py)) return {x: px, y: py};
                        }
                }
                return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
        }

        private function isPositionFree(x:Float, y:Float):Bool
        {
                for (card in _deviceCards)
                {
                        if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
                }
                return true;
        }

        public function dispose():Void
        {
                clearDevices();
                stage.removeEventListener(MouseEvent.CLICK, onStageClick);
                stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
                Impulsys.removeImpulse(EventType.ATOM_DELETED, onAtomDeleted);
        }
}


// ============================================================================
// CLASS: DeviceWindow (BUG 1 FIX)
// ============================================================================
package ui;

import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import lime.ui.Window;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;

/**
 * DEVICE WINDOW v2.1 (Fixed Header Button Interaction)
 * Full-size device display window.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * DeviceWindow — an independent OS window containing device cards.
 * Cards (DeviceCard) are managed through DeviceViewRegistry and use
 * a single DeviceView instance for each atom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SCHEMATIC                         DEVICE WINDOW                       │
 * │                                                                         │
 * │   ┌─────────────┐                    ┌────────────────────────────┐     │
 * │   │  NodeView   │  Double-click      │       DeviceWindow         │     │
 * │   │   (atom1)   │ ─────────────────► │   ┌────────────────────┐   │     │
 * │   │             │                    │   │   DeviceCard       │   │     │
 * │   │ [Widget]    │                    │   │ ┌────────────────┐ │   │     │
 * │   └─────────────┘                    │   │ │   DeviceView   │ │   │     │
 * │                                      │   │ │   (atom1)      │ │   │     │
 * │   Widget moved!                      │   │ └────────────────┘ │   │     │
 * │   NodeView shows                     │   └────────────────────┘   │     │
 * │   placeholder (no widget)            │                            │     │
 * │                                      │   [E]  [C]  [X] (Header)   │     │
 * │                                      └────────────────────────────┘     │
 * │                                              │                          │
 * │   ◄──────────────────────────────────────────┘                          │
 * │              On close: Widget returns to registry,                      │
 * │              NodeView can re-acquire it on next activation.             │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.1 Changes:
 * - FIXED: Header buttons [E], [C], [X] now stop MOUSE_DOWN propagation
 *   so they don't trigger window drag when clicked.
 * - FIXED: onMouseDown() now checks if the click target is a header button
 *   and skips drag initiation if so (defensive double-check).
 */
class DeviceWindow {

    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================

    private var _window:Window;
    private var _container:Sprite;
    private var _header:Sprite;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;
    private var _titleLabel:TextField;
    private var _deviceCards:Array<DeviceCard>;
    private var _impulseCallback:Impulse -> Void;
    private var _isDisposed:Bool = false;

    // Drag state for window header
    private var _dragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;

    // Cached dimensions (used for persistence)
    private var _initX:Float;
    private var _initY:Float;
    private var _initWidth:Float;
    private var _initHeight:Float;

    // =========================================================================
    // PUBLIC PROPERTIES
    // =========================================================================

    public var deviceCanvas(default, null):Sprite;
    public var onGetAssemblyList:Void -> Array<{id:String, name:String, atom:Atom}>;
    public var onAssemblySelected:Atom -> Void;
    public var onShowEditor:Void -> Void;

    public var windowWidth(get, never):Float;
    private function get_windowWidth():Float return (_window != null) ? _window.width : _initWidth;

    public var windowHeight(get, never):Float;
    private function get_windowHeight():Float return (_window != null) ? _window.height : _initHeight;

    public var windowX(get, never):Float;
    private function get_windowX():Float return (_window != null) ? _window.x : _initX;

    public var windowY(get, never):Float;
    private function get_windowY():Float return (_window != null) ? _window.y : _initY;

    public var isOpen(get, never):Bool;
    private function get_isOpen():Bool return _window != null && !_isDisposed;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(?initX:Float = 100, ?initY:Float = 100, ?initWidth:Float = 420, ?initHeight:Float = 320) {
        _deviceCards = [];
        _initX = initX;
        _initY = initY;
        _initWidth = initWidth;
        _initHeight = initHeight;
        create();
    }

    // =========================================================================
    // WINDOW CREATION
    // =========================================================================

    private function create():Void {
        var config = {
            title: "Device Window",
            width: Std.int(_initWidth),
            height: Std.int(_initHeight),
            x: Std.int(_initX),
            y: Std.int(_initY),
            resizable: true,
            context: {
                background: 0x1a1a24,
                antialiasing: 0,
                borderless: true,
                hardware: false
            }
        };

        _window = Lib.application.createWindow(config);

        if (_window == null || _window.stage == null) {
            trace("DeviceWindow: Failed to create window");
            if (_impulseCallback != null) {
                Impulsys.removeImpulse(EventType.ATOM_DELETED, _impulseCallback);
                _impulseCallback = null;
            }
            return;
        }

        // Force position (window managers sometimes ignore config)
        _window.x = Std.int(_initX);
        _window.y = Std.int(_initY);

        var stage = _window.stage;
        stage.scaleMode = StageScaleMode.NO_SCALE;
        stage.align = StageAlign.TOP_LEFT;
        stage.color = 0x1a1a24;
        stage.opaqueBackground = 0x1a1a24;

        _container = new Sprite();
        stage.addChild(_container);

        _impulseCallback = onAtomDeleted;
        Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, _impulseCallback);

        createHeader();
        createDeviceCanvas();
        createContextMenu();

        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(MouseEvent.CLICK, onStageClick);
        stage.addEventListener(Event.RESIZE, onWindowResize);

        stage.invalidate();
    }

    // =========================================================================
    // UI CREATION
    // =========================================================================

    private function createHeader():Void {
        var headerWidth = (_window != null && _window.stage != null) ? _window.stage.stageWidth : Std.int(_initWidth);

        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, headerWidth, 30);
        _header.graphics.endFill();

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "  Device (Right-Click to Add)";
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        var editorBtn = createHeaderButton("E", 0x005500, function(_) {
            if (onShowEditor != null) onShowEditor();
        });
        editorBtn.x = headerWidth - 90;
        _header.addChild(editorBtn);

        var clearBtn = createHeaderButton("C", 0x555500, function(_) clearDevices());
        clearBtn.x = headerWidth - 60;
        _header.addChild(clearBtn);

        var closeBtn = createHeaderButton("X", 0xAA0000, function(_) close());
        closeBtn.x = headerWidth - 30;
        _header.addChild(closeBtn);

        _header.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _header.buttonMode = true;

        _container.addChild(_header);
    }

    /**
     * BUG 1 FIX: Header buttons now stop MOUSE_DOWN propagation.
     * This prevents the MOUSE_DOWN event from bubbling up from the button
     * to the _header, which would start an unwanted window drag.
     */
    private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRect(0, 0, 28, 26);
        btn.graphics.endFill();

        var txt = new TextField();
        txt.text = label;
        txt.width = 28;
        txt.height = 26;
        txt.selectable = false;
        txt.mouseEnabled = false;
        txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
        btn.addChild(txt);

        btn.buttonMode = true;
        btn.addEventListener(MouseEvent.CLICK, onClick);
        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating to header ===
        // Without this, clicking the button would also trigger onMouseDown()
        // on the header, starting an unwanted window drag.
        btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        return btn;
    }

    private function createDeviceCanvas():Void {
        deviceCanvas = new Sprite();
        deviceCanvas.y = 30;
        var canvasHeight = (_window != null && _window.stage != null) ? _window.stage.stageHeight - 30 : Std.int(_initHeight - 30);
        deviceCanvas.graphics.beginFill(0x1a1a24);
        deviceCanvas.graphics.drawRect(0, 0, (_window != null ? _window.stage.stageWidth : _initWidth), canvasHeight);
        deviceCanvas.graphics.endFill();
        _container.addChild(deviceCanvas);
    }

    private function createContextMenu():Void {
        _contextMenu = new Sprite();
        _contextMenu.visible = false;
        _container.addChild(_contextMenu);
    }

    // =========================================================================
    // DEVICE MANAGEMENT
    // =========================================================================

    /**
     * Add a device (atom) to the window. Creates a DeviceCard that will
     * obtain the widget from the registry.
     *
     * @param atom  The atom to display
     * @param x     Desired X position in the canvas (optional)
     * @param y     Desired Y position in the canvas (optional)
     */
    public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void {
        if (_isDisposed || atom == null || deviceCanvas == null) return;

        // Avoid duplicates
        for (card in _deviceCards) {
            if (card.atom == atom) return;
        }

        var card = new DeviceCard(atom, this);
        _deviceCards.push(card);
        deviceCanvas.addChild(card);

        if (x != null && y != null) {
            card.x = x;
            card.y = y;
        } else {
            var pos = findFreePosition(card);
            card.x = pos.x;
            card.y = pos.y;
        }

        trace('DeviceWindow: Added device "${atom.name}" at (${card.x}, ${card.y})');
    }

    /**
     * Remove a device card from the window.
     */
    public function removeDevice(card:DeviceCard):Void {
        if (_isDisposed || card == null) return;
        _deviceCards.remove(card);
        if (deviceCanvas != null && deviceCanvas.contains(card)) {
            deviceCanvas.removeChild(card);
        }
        card.dispose();
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    /**
     * Remove all devices from the window.
     */
    public function clearDevices():Void {
        while (_deviceCards.length > 0) {
            var card = _deviceCards.pop();
            if (deviceCanvas != null && deviceCanvas.contains(card)) {
                deviceCanvas.removeChild(card);
            }
            card.dispose();
        }
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    /**
     * Get all current device cards.
     */
    public function getDeviceCards():Array<DeviceCard> {
        return _deviceCards;
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    private function onAtomDeleted(impulse:Impulse):Void {
        if (_isDisposed || impulse == null || impulse.data == null) return;
        var deletedId:String = impulse.data.id;
        var toRemove:Array<DeviceCard> = [];
        for (card in _deviceCards) {
            if (card.atom != null && card.atom.id == deletedId) {
                toRemove.push(card);
            }
        }
        for (card in toRemove) {
            removeDevice(card);
        }
    }

    private function onWindowResize(e:Event):Void {
        updateBackground();
        if (deviceCanvas != null && _window != null && _window.stage != null) {
            deviceCanvas.graphics.clear();
            deviceCanvas.graphics.beginFill(0x1a1a24);
            deviceCanvas.graphics.drawRect(0, 0, _window.stage.stageWidth, _window.stage.stageHeight - 30);
            deviceCanvas.graphics.endFill();
        }
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    private function updateBackground():Void {
        if (_container != null && _window != null && _window.stage != null && _header != null) {
            var newWidth = _window.stage.stageWidth;
            _header.graphics.clear();
            _header.graphics.beginFill(0x2a2a34);
            _header.graphics.drawRect(0, 0, newWidth, 30);
            _header.graphics.endFill();
        }
    }

    // =========================================================================
    // WINDOW DRAG (header)
    // =========================================================================

    /**
     * BUG 1 FIX: Added target check to skip drag if the user clicked
     * on a header button child. Even though buttons now stopPropagation
     * on MOUSE_DOWN, this defensive check ensures that if somehow the
     * event still reaches this handler, we don't start a drag.
     */
    private function onMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;

        // === BUG 1 FIX: Check if click target is inside a header button ===
        // Walk up from the click target. If we find a child of _header that
        // has buttonMode=true (one of the [E]/[C]/[X] buttons), skip drag.
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != _header) {
            if (Std.isOfType(targetObj, Sprite)) {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == _header) {
                    // Clicked on a header button — do not start drag
                    return;
                }
            }
            targetObj = targetObj.parent;
        }

        _dragging = true;
        _dragOffsetX = e.localX;
        _dragOffsetY = e.localY;
        _window.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        _window.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_isDisposed || !_dragging) return;
        if (_window != null) {
            _window.x = Std.int(_window.x + (e.stageX - _dragOffsetX));
            _window.y = Std.int(_window.y + (e.stageY - _dragOffsetY));
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        _dragging = false;
        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    // =========================================================================
    // CONTEXT MENU
    // =========================================================================

    private function onRightClick(e:MouseEvent):Void {
        if (_isDisposed) return;
        e.stopPropagation();
        showContextMenu(e.stageX, e.stageY);
    }

    private function onStageClick(e:MouseEvent):Void {
        if (_isDisposed) return;
        if (_menuVisible) hideContextMenu();
    }

    private function showContextMenu(x:Float, y:Float):Void {
        while (_contextMenu.numChildren > 0) _contextMenu.removeChildAt(0);

        var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
        devices = [for (d in devices) if (d.id != "selfrun") d];

        var yPos = 0;
        var headerItem = createMenuItem("Add Device:", null, true);
        headerItem.y = yPos;
        _contextMenu.addChild(headerItem);
        yPos += 28;

        var sep = new Sprite();
        sep.graphics.lineStyle(1, 0x444455);
        sep.graphics.moveTo(0, 0);
        sep.graphics.lineTo(180, 0);
        sep.y = yPos;
        _contextMenu.addChild(sep);
        yPos += 8;

        if (devices.length == 0) {
            var emptyItem = createMenuItem("(No devices available)", null, true);
            emptyItem.y = yPos;
            _contextMenu.addChild(emptyItem);
            yPos += 26;
        } else {
            for (item in devices) {
                var menuItem = createMenuItem(item.name, item.atom, false);
                menuItem.y = yPos;
                _contextMenu.addChild(menuItem);
                yPos += 26;
            }
        }

        _contextMenu.graphics.clear();
        _contextMenu.graphics.beginFill(0x333344, 0.98);
        _contextMenu.graphics.lineStyle(1, 0x555566);
        _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 4, 6, 6);
        _contextMenu.graphics.endFill();

        var maxX = (_window != null && _window.stage != null) ? _window.stage.stageWidth : _initWidth;
        var maxY = (_window != null && _window.stage != null) ? _window.stage.stageHeight : _initHeight;

        _contextMenu.x = Math.min(x, maxX - 200);
        _contextMenu.y = Math.min(Math.max(y - 30, 0), maxY - yPos - 10);

        _menuVisible = true;
        _contextMenu.visible = true;
    }

    private function hideContextMenu():Void {
        _menuVisible = false;
        _contextMenu.visible = false;
    }

    private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite {
        var item = new Sprite();
        item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
        item.graphics.drawRect(0, 0, 180, 24);
        item.graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
        txt.text = (disabled || atom == null) ? label : "+ " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);

        if (!disabled && atom != null) {
            item.buttonMode = true;
            final capturedAtom = atom;
            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
                addDevice(capturedAtom);
                if (onAssemblySelected != null) onAssemblySelected(capturedAtom);
                hideContextMenu();
            });
            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) {
                item.graphics.clear();
                item.graphics.beginFill(0x556677);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) {
                item.graphics.clear();
                item.graphics.beginFill(0x444455);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
        }
        return item;
    }

    // =========================================================================
    // UTILITY
    // =========================================================================

    private function findFreePosition(card:DeviceCard):{x:Float, y:Float} {
        var startX = 10;
        var startY = 10;
        var stepX = 120;
        var stepY = 100;
        for (y in 0...3) {
            for (x in 0...4) {
                var px = startX + x * stepX;
                var py = startY + y * stepY;
                if (isPositionFree(px, py)) return {x: px, y: py};
            }
        }
        return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
    }

    private function isPositionFree(x:Float, y:Float):Bool {
        for (card in _deviceCards) {
            if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
        }
        return true;
    }

    // =========================================================================
    // CLOSE & DISPOSE
    // =========================================================================

    public function close():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        if (_impulseCallback != null) {
            Impulsys.removeImpulse(EventType.ATOM_DELETED, _impulseCallback);
            _impulseCallback = null;
        }

        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _window.stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.removeEventListener(MouseEvent.CLICK, onStageClick);
            _window.stage.removeEventListener(Event.RESIZE, onWindowResize);
        }

        clearDevices();
        deviceCanvas = null;
        _contextMenu = null;
        _container = null;

        if (_window != null) {
            _window.close();
            _window = null;
        }

        onGetAssemblyList = null;
        onAssemblySelected = null;
        onShowEditor = null;
    }
}


// ============================================================================
// CLASS: PropertiesWindow (BUG 1 FIX)
// ============================================================================
package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Assembly;
import library.electro.OscilloscopeAtom;
import ui.widgets.NumberInput;
import ui.widgets.NumberDisplay;
import ui.widgets.IHMIWidget;

/**
 * PropertiesWindow v2.3 (Fixed Close Button Interaction)
 * FIXED: Widget lifecycle, null checks, proper cleanup
 * ADDED: Display Shape selector for OscilloscopeAtom.
 *
 * v2.3 Changes:
 * - FIXED: Close button MOUSE_DOWN now calls stopPropagation() to prevent
 *   it from triggering the header drag.
 */
class PropertiesWindow extends Sprite {
    private var _bg:Sprite;
    private var _title:TextField;
    private var _content:Sprite;
    private var _target:Dynamic;
    private var _widgets:Array<IHMIWidget>;
    private var _isDisposed:Bool = false;

    public function new() {
        super();
        _widgets = new Array();
        _bg = new Sprite();
        addChild(_bg);
        _drawBg(300, 200);

        _title = new TextField();
        _title.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _title.width = 280;
        _title.height = 20;
        _title.x = 10;
        _title.y = 5;
        _title.selectable = false;
        _title.mouseEnabled = false;
        addChild(_title);

        _content = new Sprite();
        _content.y = 30;
        _content.x = 10;
        addChild(_content);

        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0, 0, 15, 15);
        closeBtn.x = 280;
        closeBtn.y = 5;
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(_) _close());
        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating to title ===
        // Without this, clicking close would also start a drag on the title.
        closeBtn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        addChild(closeBtn);

        _title.addEventListener(MouseEvent.MOUSE_DOWN, _onMouseDownHeader);
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
        } else {
            addEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        }
    }

    private function _onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        if (stage != null) stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
    }

    private function _onMouseDownHeader(e:MouseEvent):Void {
        startDrag();
    }

    private function _onMouseUpStage(e:MouseEvent):Void {
        stopDrag();
    }

    public function show(target:Dynamic, x:Float, y:Float):Void {
        if (_isDisposed) return;
        _target = target;
        this.x = x;
        this.y = y;
        _clearContent();
        if (Std.isOfType(target, Atom)) {
            _populateAtom(cast target);
        } else {
            _title.text = "Properties";
            var tf = new TextField();
            tf.text = "Unknown object";
            tf.width = 250;
            _content.addChild(tf);
        }
    }

    // NOTE: _populateAtom, _clearContent, _close, and other unchanged methods
    // remain the same as in the original file.
    // The only change in this class is the closeBtn MOUSE_DOWN stopPropagation.
}