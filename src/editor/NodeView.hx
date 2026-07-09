package editor;
import core.base.Contact;
import openfl.display.Sprite;
import openfl.display.DisplayObjectContainer;
import openfl.display.InteractiveObject;
import openfl.display.DisplayObject;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.MouseEvent;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.geom.Point;
import core.base.Atom;
import core.base.Assembly;
import core.view.DeviceView;
import core.view.DeviceViewRegistry;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import ecs.ECS;
import core.view.InlineParameterEditor;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ParameterPriority;

/**
* NODE VIEW v3.4 (Interactive Target Guard + Cleanup)
*
* Visual representation of an Atom (node) on the schematic canvas.
*
* v3.4 Changes:
* - ADDED: isInteractiveTarget() guard to prevent node drag when clicking
*   on widgets (Button, TextInput, Toggle, etc.) or InlineParameterEditors.
* - FIXED: Removed erroneous _input field reference (copy-paste artifact).
* - All comments translated to English.
*
* v3.3 Changes:
* - ADDED: Inline name editing via double-click on title bar
* - ADDED: Name uniqueness check via parent Assembly
* - ADDED: Visual feedback for name conflicts (red border)
* - ADDED: setParentAssembly() for uniqueness validation
*
* ═══════════════════════════════════════════════════════════════════════════
* INLINE NAME EDITING:
* ═══════════════════════════════════════════════════════════════════════════
*
* ┌─────────────────────────────────────────────────────────────────────┐
* │  [Title Bar]                                                        │
* │                                                                     │
* │  Normal state:                                                      │
* │  ┌──────────────────────────────────────────────────────────────┐   │
* │  │  Atom Name                                        [⚙]       │   │
* │  └──────────────────────────────────────────────────────────────┘   │
* │                                                                     │
* │  Double-click on title bar → editing mode:                          │
* │  ┌──────────────────────────────────────────────────────────────┐   │
* │  │  [Atom Name______                              ]  [⚙]       │   │
* │  └──────────────────────────────────────────────────────────────┘   │
* │   ↑ TextField (INPUT)                                               │
* │                                                                     │
* │  ENTER → apply (with uniqueness check)                              │
* │  ESCAPE → cancel                                                    │
* │  Focus out → apply                                                  │
* │                                                                     │
* │  If name conflict:                                                  │
* │  ┌──────────────────────────────────────────────────────────────┐   │
* │  │  [Conflicting Name                             ]  [⚙]       │   │
* │  └──────────────────────────────────────────────────────────────┘   │
* │   ↑ Red border (1 second)                                           │
* │                                                                     │
* └─────────────────────────────────────────────────────────────────────┘
*/
class NodeView extends Sprite
{
// =========================================================================
// CONFIGURATION
// =========================================================================
	public static inline var PREVIEW_SCALE:Float = 0.7;
	public static inline var MIN_WIDTH:Float = 180;
	public static inline var MIN_BODY_HEIGHT:Float = 68;
	public static inline var WIDGET_PADDING:Float = 5;
	public static inline var TITLE_HEIGHT:Float = 22;
	public static inline var PORT_RADIUS:Float = 7;
	public static inline var PORT_SPACING:Float = 32;
	public static inline var INLINE_EDITOR_X_OFFSET:Float = 11;

// =========================================================================
// DYNAMIC SIZE (v3.0)
// =========================================================================
	private var _nodeWidth:Float = MIN_WIDTH;
	private var _nodeHeight:Float = MIN_BODY_HEIGHT + TITLE_HEIGHT;

// =========================================================================
// REFERENCES
// =========================================================================
	public var atom(default, null):Atom;
	public var assembly(default, null):Assembly;
	public var deviceView(default, null):DeviceView;
	public var nodeId(default, null):String;

// =========================================================================
// PORTS
// =========================================================================
	public var inputPorts(default, null):Map<String, Sprite>;
	public var outputPorts(default, null):Map<String, Sprite>;

// =========================================================================
// STATE
// =========================================================================
	private var _inlineEditors:Map<String, InlineParameterEditor> = new Map();
	public var selected(default, set):Bool = false;
	private function set_selected(value:Bool):Bool
	{
		selected = value;
		updateSelectionVisual();
		return value;
	}
	public var isSelected(get, set):Bool;
	private function get_isSelected():Bool return selected;
	private function set_isSelected(value:Bool):Bool { selected = value; return value; }
	public var hasWidget(default, null):Bool = false;

// =========================================================================
// INLINE NAME EDITING (v3.3)
// =========================================================================
	/** Input TextField for inline name editing (hidden by default) */
	private var _nameInput:TextField = null;
	/** Is name editing currently active? */
	private var _isEditingName:Bool = false;
	/** Reference to parent Assembly for uniqueness check */
	private var _parentAssembly:Assembly = null;

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
	public function new(atom:Atom, nodeId:String)
	{
		super();
		this.atom = atom;
		this.nodeId = nodeId;
		_theme = EditorTheme.getInstance();
		inputPorts = new Map<String, Sprite>();
		outputPorts = new Map<String, Sprite>();
		if (Std.isOfType(atom, Assembly))
		{
			this.assembly = cast(atom, Assembly);
		}
		buildUI();
		createPorts();
		createInlineEditors();
		acquireWidget();
		setupInteraction();
		ECS.register(nodeId, this, this.x, this.y);
		Impulsys.subscribeToImpulse(EventType.ASSEMBLY_PORTS_CHANGED, onAssemblyPortsChanged);
		Impulsys.subscribeToImpulse(EventType.REDRAW_WIRES, onWiresRedrawn);
		//trace('NodeView: Created for atom "${atom.displayName}" (id: ${nodeId})');
	}

// =========================================================================
// PARENT ASSEMBLY (v3.3 — for name uniqueness check)
// =========================================================================
	/**
	* Set reference to parent Assembly.
	* Called by NodeEditor after creating this NodeView.
	* Used for checking name uniqueness during inline editing.
	*
	* @param asm Parent Assembly containing this atom
	*/
	public function setParentAssembly(asm:Assembly):Void
	{
		_parentAssembly = asm;
	}

// =========================================================================
// DYNAMIC SIZING (v3.0)
// =========================================================================
	private function recalcSize():Void
	{
		var bodyWidth:Float = MIN_WIDTH;
		var widgetHeight:Float = 0;
		if (deviceView != null)
		{
			var ws = deviceView.getWidgetSize();
			var scaledW = ws.width * PREVIEW_SCALE;
			var scaledH = ws.height * PREVIEW_SCALE;
			bodyWidth = Math.max(bodyWidth, scaledW + WIDGET_PADDING * 2);
			widgetHeight = scaledH + WIDGET_PADDING;
			//trace('Widget size: ${ws.width} x ${ws.height}');
		}
		var portsHeight:Float = MIN_BODY_HEIGHT;
		var inputCount = (atom != null && atom.getInputs() != null) ? atom.getInputs().length : 0;
		var outputCount = (atom != null && atom.getOutputs() != null) ? atom.getOutputs().length : 0;
		var maxPorts = Std.int(Math.max(inputCount, outputCount));
		if (maxPorts > 0)
		{
			portsHeight = (maxPorts + 1) * PORT_SPACING;
		}
		var bodyHeight = portsHeight + widgetHeight;
		_nodeWidth = bodyWidth;
		_nodeHeight = TITLE_HEIGHT + bodyHeight;
	}

	private function updateLayout():Void
	{
		recalcSize();
		redraw();
		createPorts();
		realignInlineEditors();
	}
	
/**
 * v3.5.2: Realign inline editors vertically with their corresponding ports.
 * Does NOT recreate editors (avoids callback subscription leaks).
 * Only updates Y positions of existing editors and hides port labels.
 */
	private function realignInlineEditors():Void
	{
		var inputs = atom.getInputs();
		if (inputs == null || inputs.length == 0) return;
		
		var inputCount = inputs.length;
		var outputCount = (atom.getOutputs() != null) ? atom.getOutputs().length : 0;
		var maxPorts = Std.int(Math.max(inputCount, outputCount));
		var portsHeight:Float = MIN_BODY_HEIGHT;
		if (maxPorts > 0)
		{
			portsHeight = (maxPorts + 1) * PORT_SPACING;
		}
		var stepY = (inputCount > 0) ? portsHeight / (inputCount + 1) : 0;
		
		for (i in 0...inputCount)
		{
			var contact = inputs[i];
			if (contact == null) continue;
			
			var editor = _inlineEditors.get(contact.name);
			if (editor != null)
			{
				// Update Y position to align with port
				var portY = TITLE_HEIGHT + stepY * (i + 1);
				editor.x = INLINE_EDITOR_X_OFFSET;
				editor.y = portY - 15; // Center vertically on port
				
				// === FIX: Hide port label (inline editor replaces it) ===
				// This is critical after updateLayout() recreates ports with visible labels
				var port = inputPorts.get(contact.name);
				if (port != null)
				{
					for (j in 0...port.numChildren)
					{
						var child = port.getChildAt(j);
						if (Std.isOfType(child, TextField))
						{
							child.visible = false;
						}
					}
				}
			}
		}
	}

// =========================================================================
// UI CONSTRUCTION
// =========================================================================
	private function buildUI():Void
	{
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
		// === v3.3 FIX: Enable mouse events on title label ===
		// Required for double-click detection on the text itself.
		_titleLabel.mouseEnabled = true;
		_titleLabel.doubleClickEnabled = true;
		_titleLabel.defaultTextFormat = new TextFormat(
			"_sans", 11, _theme.NODE_TEXT_COLOR, true, null, null, null, null, "left"
		);
		// === v3.3: Use displayName instead of name ===
		_titleLabel.text = atom != null ? (atom.displayName != null ? atom.displayName : atom.name) : "Node";
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
		// NOTE: Inline editors handle their own mouse events via isInteractiveTarget() guard.
		// No need to add listeners here — the guard in onMouseDown() checks the display hierarchy.
	}

	private function centerPreviewContainer():Void
	{
		if (deviceView == null)
		{
			_previewContainer.x = WIDGET_PADDING;
			_previewContainer.y = TITLE_HEIGHT + WIDGET_PADDING;
			return;
		}
		var ws = deviceView.getWidgetSize();
		var scaledW = ws.width * PREVIEW_SCALE;
		var scaledH = ws.height * PREVIEW_SCALE;
		var bodyWidth = _nodeWidth;
		_previewContainer.x = (bodyWidth - scaledW) / 2;
		_previewContainer.y = _nodeHeight - scaledH - WIDGET_PADDING;
	}

	public function redraw():Void
	{
		recalcSize();
		var w = _nodeWidth;
		var h = _nodeHeight;
		var g = _background.graphics;
		g.clear();
		g.beginFill(0x2a2a3a, 0.95);
		g.lineStyle(selected ? 2 : 1, selected ? _theme.NODE_SELECTED_COLOR : _theme.NODE_BORDER_COLOR);
		if (atom.isLogic)
		{
			var cut = 10.0;
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
		}
		else {
			g.drawRoundRect(0, 0, w, h, 8, 8);
			g.endFill();
		}
		var tg = _titleBar.graphics;
		tg.clear();
		tg.beginFill(0x3a3a4a, 0.9);
		if (atom.isLogic)
		{
			var cut = 10.0;
			tg.moveTo(cut, 0);
			tg.lineTo(w - cut, 0);
			tg.lineTo(w, cut);
			tg.lineTo(w, TITLE_HEIGHT);
			tg.lineTo(0, TITLE_HEIGHT);
			tg.lineTo(0, cut);
			tg.lineTo(cut, 0);
		}
		else {
			tg.drawRoundRectComplex(0, 0, w, TITLE_HEIGHT, 8, 8, 0, 0);
		}
		tg.endFill();
		_titleLabel.width = w - 30;
		_settingsButton.x = w - 15;
		// === v3.3: Update name input width if visible ===
		if (_nameInput != null && _nameInput.visible)
		{
			_nameInput.width = w - 50;
		}
		if (deviceView != null)
		{
			var ws = deviceView.getWidgetSize();
			var scaledH = ws.height * PREVIEW_SCALE;
			var separatorY = _nodeHeight - scaledH - WIDGET_PADDING - 5;
			var sepG = _background.graphics;
			sepG.lineStyle(1, 0x444455);
			sepG.moveTo(0, separatorY);
			sepG.lineTo(_nodeWidth, separatorY);
		}
		var sg = _selectionHighlight.graphics;
		sg.clear();
		if (selected)
		{
			sg.lineStyle(3, _theme.NODE_SELECTED_COLOR, 0.6);
			if (atom.isLogic)
			{
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
			}
			else
			{
				sg.drawRoundRect(-3, -3, w + 6, h + 6, 10, 10);
			}
		}
	}

	private function updateSelectionVisual():Void
	{
		_selectionHighlight.visible = selected;
		redraw();
		ECS.setSelected(nodeId, selected);
	}

// =========================================================================
// PORTS CREATION
// =========================================================================
	private function createPorts():Void
	{
		for (name in inputPorts.keys())
		{
			var port = inputPorts.get(name);
			if (port != null && port.parent != null) port.parent.removeChild(port);
		}
		for (name in outputPorts.keys())
		{
			var port = outputPorts.get(name);
			if (port != null && port.parent != null) port.parent.removeChild(port);
		}
		inputPorts.clear();
		outputPorts.clear();
		var inputs = atom.getInputs();
		var outputs = atom.getOutputs();
		var portsHeight:Float = MIN_BODY_HEIGHT;
		var inputCount = (inputs != null) ? inputs.length : 0;
		var outputCount = (outputs != null) ? outputs.length : 0;
		var maxPorts = Std.int(Math.max(inputCount, outputCount));
		if (maxPorts > 0)
		{
			portsHeight = (maxPorts + 1) * PORT_SPACING;
		}
		if (inputs != null)
		{
			var count = inputs.length;
			var stepY = portsHeight / (count + 1);
			for (i in 0...count)
			{
				var c = inputs[i];
				if (c != null)
				{
					var port = createPortSprite(c.name, true);
					port.x = 0;
					port.y = TITLE_HEIGHT + stepY * (i + 1);
					addChild(port);
					inputPorts.set(c.name, port);
				}
			}
		}
		if (outputs != null)
		{
			var count = outputs.length;
			var stepY = portsHeight / (count + 1);
			for (i in 0...count)
			{
				var c = outputs[i];
				if (c != null)
				{
					var port = createPortSprite(c.name, false);
					port.x = _nodeWidth;
					port.y = TITLE_HEIGHT + stepY * (i + 1);
					addChild(port);
					outputPorts.set(c.name, port);
				}
			}
		}
		//trace('NodeView: Created ${Lambda.count(inputPorts)} input ports, ${Lambda.count(outputPorts)} output ports');
	}

	private function createPortSprite(name:String, isInput:Bool):Sprite
	{
		var port = new Sprite();
		var w = PORT_RADIUS * 2;
		var h = PORT_RADIUS * 2 + 4;
		var color = isInput ? 0xFFAA00 : 0x00AAFF;
		port.graphics.beginFill(color);
		port.graphics.lineStyle(1, 0xFFFFFF);
		if (isInput)
		{
			port.graphics.drawRect(-w / 2, -h / 2, w, h);
		}
		else {
			var bodyWidth = w * 0.7;
			port.graphics.drawRect(-w / 2, -h / 2, bodyWidth, h);
			var tipStartX = -w / 2 + bodyWidth;
			port.graphics.moveTo(tipStartX, -h / 2);
			port.graphics.lineTo(w / 2, 0);
			port.graphics.lineTo(tipStartX, h / 2);
			port.graphics.lineStyle(1.2, 0x00AAFF);
			port.graphics.moveTo(tipStartX, ( h / 2) - 1.7);
			port.graphics.lineTo(tipStartX, (-h / 2) + 1.7);
		}
		port.graphics.endFill();
		var hit = new Sprite();
		hit.graphics.beginFill(0xFF0000, 0);
		hit.graphics.drawRect(-w, -h, w * 2, h * 2);
		hit.graphics.endFill();
		port.addChild(hit);
		var label = new TextField();
		label.width = 77;
		label.height = 16;
		label.selectable = false;
		label.mouseEnabled = false;
		label.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFCC);
		label.y = -7;
		if (isInput)
		{
			label.x = w / 2 + 3;
			label.text = name;
		}
		else {
			label.x = -w / 2 - label.width - 3;
			label.y = -9;
			label.text = name;
			var fmt = new TextFormat("_sans", 11, 0xFFFFCC);
			fmt.align = "right";
			label.setTextFormat(fmt);
			label.defaultTextFormat = fmt;
		}

		port.addChild(label);
		port.name = name;
		port.buttonMode = true;
		port.useHandCursor = true;
		port.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			e.stopPropagation();
			onPortMouseDown(name, isInput, e);
		});
		port.addEventListener(MouseEvent.RIGHT_CLICK, function(e:MouseEvent)
		{
			e.stopPropagation();
			onPortRightClick(name, isInput, e);
		});
		return port;
	}

// =========================================================================
// INLINE EDITORS (v3.3)
// =========================================================================
	private function createInlineEditors():Void
	{
		// Clean up old editors
		for (name in _inlineEditors.keys())
		{
			var editor = _inlineEditors.get(name);
			if (editor != null)
			{
				editor.dispose();
				if (editor.parent != null) removeChild(editor);
			}
		}
		_inlineEditors.clear();
		
		var inputs = atom.getInputs();
		if (inputs == null) return;
		
		var yPos:Float = TITLE_HEIGHT + 10;
		for (contact in inputs)
		{
			if (contact == null) continue;
			if (contact.hasLinks()) continue;
			
			var pinDef = getPinDefForContact(contact);
			var shouldShow:Bool = false;
			if (pinDef != null)
			{
				var priority = (pinDef.priority != null) ? pinDef.priority : OPTIONAL;
				shouldShow = (pinDef.visibleInEditor != null) ? pinDef.visibleInEditor : (priority == CRITICAL || priority == IMPORTANT);
			}
			else
			{
				shouldShow = true;
			}
			if (!shouldShow) continue;
			
			var editor = new InlineParameterEditor(contact, pinDef);
			// === Fixed position from left edge ===
			editor.x = INLINE_EDITOR_X_OFFSET;
			editor.y = yPos;
			addChild(editor);
			_inlineEditors.set(contact.name, editor);
			
			// Hide port label for this contact
			var port = inputPorts.get(contact.name);
			if (port != null)
			{
				for (i in 0...port.numChildren)
				{
					var child = port.getChildAt(i);
					if (Std.isOfType(child, TextField))
					{
						child.visible = false;
					}
				}
			}
			
			yPos += 30;
		}
	}

	private function getPinDefForContact(contact:Contact):PinDef
	{
		if (atom == null || !(Std.isOfType(atom, Assembly))) return null;
		var asm:Assembly = cast(atom, Assembly);
		if (asm.blueprint == null || asm.blueprint.pins == null) return null;
		for (pin in asm.blueprint.pins)
		{
			if (pin.name == contact.name) return pin;
		}
		return null;
	}

	public function updateInlineEditorsVisibility():Void
	{
		var inputs = atom.getInputs();
		if (inputs == null) return;
		for (contact in inputs)
		{
			if (contact == null) continue;
			var editor = _inlineEditors.get(contact.name);
			if (editor == null) continue;
			var hasConnection = contact.hasLinks();
			var port = inputPorts.get(contact.name);
			if (hasConnection)
			{
				editor.hideEditor();
				if (port != null)
				{
					for (i in 0...port.numChildren)
					{
						var child = port.getChildAt(i);
						if (Std.isOfType(child, TextField))
						{
							child.visible = true;
						}
					}
				}
			}
			else
			{
				editor.showEditor();
				if (port != null)
				{
					for (i in 0...port.numChildren)
					{
						var child = port.getChildAt(i);
						if (Std.isOfType(child, TextField))
						{
							child.visible = false;
						}
					}
				}
			}
		}
		// v3.5.2: Just realign, don't recreate
		realignInlineEditors();
	}
	
// =========================================================================
// Forces all inline editors to be left-aligned.
// Call after any operations that might disrupt positioning.
// =========================================================================
	private function alignInlineEditors():Void
	{
		for (editor in _inlineEditors)
		{
			if (editor != null)
			{
				editor.x = INLINE_EDITOR_X_OFFSET;
			}
		}
	}

// =========================================================================
// PREVIEW WIDGET MANAGEMENT
// =========================================================================
	private function acquireWidget():Void
	{
		if (atom == null) return;
		var registry = DeviceViewRegistry.getInstance();
		deviceView = registry.getOrCreate(atom, true);
		if (deviceView == null)
		{
			//trace('NodeView: Could not get widget for atom ${atom.id}');
			return;
		}
		if (registry.isInDeviceWindow(atom.id))
		{
			hasWidget = false;
			//trace('NodeView: Widget for ${atom.id} is in DeviceWindow');
			return;
		}
		addWidgetToPreview();
	}

	private function addWidgetToPreview():Void
	{
		if (deviceView == null) return;
		if (deviceView.parent != null) deviceView.parent.removeChild(deviceView);
		deviceView.x = 0;
		deviceView.y = 0;
		deviceView.scaleX = PREVIEW_SCALE;
		deviceView.scaleY = PREVIEW_SCALE;
		_previewContainer.addChild(deviceView);
		enableDoubleClickRecursive(deviceView);
		DeviceViewRegistry.getInstance().setContainer(atom.id, DeviceViewRegistry.CONTAINER_NODE_VIEW);
		if (!deviceView.isActive) deviceView.activate();
		hasWidget = true;
		alignInlineEditors();
		updateLayout();
		if (stage != null)
		{
			stage.addEventListener(openfl.events.Event.ENTER_FRAME, _centerAfterFrame, false, 0, true);
		}
		else {
			centerPreviewContainer();
		}
		//trace('NodeView: Widget added for ${atom.id} (scale: ${deviceView.scaleX})');
	}

	private function _centerAfterFrame(e:openfl.events.Event):Void
	{
		if (stage != null)
		{
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _centerAfterFrame);
		}
		centerPreviewContainer();
	}

	private function enableDoubleClickRecursive(obj:DisplayObjectContainer):Void
	{
		if (obj == null) return;
		obj.doubleClickEnabled = true;
		for (i in 0...obj.numChildren)
		{
			var child = obj.getChildAt(i);
			if (Std.isOfType(child, DisplayObjectContainer)) enableDoubleClickRecursive(cast child);
			else if (Std.isOfType(child, InteractiveObject)) cast(child, InteractiveObject).doubleClickEnabled = true;
		}
	}

	public function releaseWidget():DeviceView
	{
		if (deviceView == null || !hasWidget) return null;
		if (deviceView.parent == _previewContainer) _previewContainer.removeChild(deviceView);
		hasWidget = false;
		updateLayout();
		//trace('NodeView: Released widget for ${atom.id}');
		return deviceView;
	}

	public function acceptWidget():Void
	{
		if (deviceView == null)
		{
			acquireWidget();
		}
		else {
			deviceView.scaleX = PREVIEW_SCALE;
			deviceView.scaleY = PREVIEW_SCALE;
			addWidgetToPreview();
			haxe.Timer.delay(function()
			{
				centerPreviewContainer();
			}, 50);
		}
		//trace('NodeView: Accepted widget back for ${atom.id}');
	}

// =========================================================================
// INTERACTION
// =========================================================================

// =========================================================================
// INTERACTIVE TARGET GUARD (v3.4)
// =========================================================================

/**
 * v3.4: Walks up the display list from event target to this NodeView,
 * checking if any ancestor is an interactive element that should NOT
 * trigger node drag.
 *
 * Protected types:
 *   - DeviceView (any widget: Button, Toggle, TextInput, Oscilloscope...)
 *   - InlineParameterEditor (contact parameter fields)
 *   - TextField with type = INPUT (any text input)
 *
 * This is the PRIMARY defense. It catches ALL interactive elements
 * by walking up the display hierarchy, regardless of how deeply
 * the click target is nested inside a widget.
 *
 * @param target The original event target (e.target)
 * @return true if the click originated from an interactive element
 */
	private function isInteractiveTarget(target:DisplayObject):Bool
	{
		var current:DisplayObject = target;
		
		while (current != null && current != this)
		{
			// Guard A: Any DeviceView (widget preview)
			if (Std.isOfType(current, DeviceView)) return true;
			
			// Guard B: Any InlineParameterEditor
			if (Std.isOfType(current, InlineParameterEditor)) return true;
			
			// Guard C: Any INPUT TextField (catches future editors too)
			if (Std.isOfType(current, TextField))
			{
				var tf:TextField = cast current;
				if (tf.type == TextFieldType.INPUT) return true;
			}
			
			current = current.parent;
		}
		
		return false;
	}

/**
 * v3.4.3: Walks up the display list from event target to this NodeView,
 * checking if any ancestor is a port sprite (input or output).
 *
 * Port sprites contain child elements (hit area, label TextField) that
 * can become e.target instead of the port itself. This method handles
 * that by walking up the hierarchy.
 *
 * @param target The original event target (e.target)
 * @return true if the click originated from a port or its children
 */
private function isPortTarget(target:DisplayObject):Bool
{
    var current:DisplayObject = target;
    
    while (current != null && current != this)
    {
        if (Std.isOfType(current, Sprite))
        {
            var spr:Sprite = cast current;
            if (spr.name != null && spr.name != "")
            {
                if (inputPorts.exists(spr.name) || outputPorts.exists(spr.name))
                    return true;
            }
        }
        current = current.parent;
    }
    
    return false;
}

	private function setupInteraction():Void
	{
		mouseEnabled = true;
		buttonMode = true;
		useHandCursor = true;
		doubleClickEnabled = true;
		addEventListener(MouseEvent.DOUBLE_CLICK, onDoubleClick);
		addEventListener(MouseEvent.CLICK, onClick);
		addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
		addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
	}

/**
* v3.3: Double-click handler with name editing support.
*
* Priority:
* 1. If click is on a port → ignore (port handler takes over)
* 2. If click is on settings button → ignore
* 3. If click is in title bar area → start name editing
* 4. Otherwise → open Assembly (if applicable)
*/
	private function onDoubleClick(e:MouseEvent):Void
	{
		// === Guard 0 (v3.4.1): Name editing in progress ===
		if (_isEditingName) return;
		
		// === Guard 1 (v3.4.1): Interactive element ===
		// Prevents assembly open / name editing when user double-clicks
		// on a widget or inline editor.
		if (isInteractiveTarget(cast e.target)) return;
		
		// Check if click was on a port
		if (Std.isOfType(e.target, Sprite))
		{
			var target:Sprite = cast e.target;
			if (inputPorts.exists(target.name) || outputPorts.exists(target.name)) return;
		}
		// Check if click was on settings button
		var targetObj:DisplayObject = cast e.target;
		while (targetObj != null && targetObj != this)
		{
			if (targetObj == _settingsButton) return;
			targetObj = targetObj.parent;
		}
		// === v3.3: Check if double-click was in title bar area ===
		var localPoint = globalToLocal(new Point(e.stageX, e.stageY));
		if (localPoint.y >= 0 && localPoint.y < TITLE_HEIGHT && localPoint.x < _nodeWidth - 30)
		{
			e.stopPropagation();
			startNameEditing();
			return;
		}
		// Otherwise — existing logic (open Assembly)
		e.stopPropagation();
		if (Std.isOfType(atom, Assembly))
		{
			trace('NodeView: Double-click detected on Assembly. Emitting request for ID: ${atom.id}');
			Impulsys.quickEmit(EventType.OPEN_ASSEMBLY_REQUEST, { atomId: atom.id });
			return;
		}
		trace('NodeView: Double-click on simple atom ${atom.id} (ignored)');
	}

/**
* v3.4.2: Click handler with interactive element protection + selection clear.
*
* UX Philosophy:
* - Click on widget/inline editor = interact with widget, CLEAR ALL SELECTION
* - Click on empty area/title = select the node (deselecting others)
* - This keeps focus on widget interaction without visual selection noise
*
* Guard Logic:
* - isInteractiveTarget() → clear selection, don't select node
* - Port clicks → handled by port handlers, no selection change
* - Name editing → blocks all selection logic
*
* Order of guards:
*   1. Name editing in progress
*   2. Interactive element → CLEAR SELECTION + return
*   3. Port click → return (port handler takes over)
*   4. → Select node + emit NODE_CLICKED
*/
	private function onClick(e:MouseEvent):Void
	{
		// === Guard 1: Name editing in progress ===
		if (_isEditingName) return;
		
		// === Guard 2 (v3.4.2): Interactive element → CLEAR SELECTION ===
		// When clicking on widgets, inline editors, or text input fields:
		// 1. Signal to deselect ALL nodes (via null view/id)
		// 2. Do NOT select this node
		// 3. Stop propagation to prevent other handlers
		if (isInteractiveTarget(cast e.target))
		{
			// Signal "deselect all" by passing null view/id
			if (onSelect != null) onSelect(null);
			Impulsys.quickEmit(EventType.NODE_CLICKED, { view: null, id: null, ctrlKey: e.ctrlKey });
			e.stopPropagation();
			return;
		}
		
// === Guard 3 (v3.4.3): Port click → CLEAR SELECTION ===
		if (isPortTarget(cast e.target))
		{
			if (onSelect != null) onSelect(null);
			Impulsys.quickEmit(EventType.NODE_CLICKED, { view: null, id: null, ctrlKey: e.ctrlKey });
			e.stopPropagation();
			return;
		}
		
		// === All guards passed → Select node ===
		if (onSelect != null) onSelect(this);
		Impulsys.quickEmit(EventType.NODE_CLICKED, { view: this, id: nodeId, ctrlKey: e.ctrlKey });
		e.stopPropagation();
	}

/**
* v3.4.3: Right-click handler with full protection.
*
* Behavior:
* - Right-click on widget → clear selection, let widget handle context menu
* - Right-click on port → clear selection, emit PORT_RIGHT_CLICKED
* - Right-click on empty node area → emit NODE_RIGHT_CLICKED for node context menu
*/
	private function onRightClick(e:MouseEvent):Void
	{
		// === Guard 1 (v3.4.2): Interactive element → CLEAR SELECTION ===
		if (isInteractiveTarget(cast e.target))
		{
			if (onSelect != null) onSelect(null);
			Impulsys.quickEmit(EventType.NODE_CLICKED, { view: null, id: null, ctrlKey: false });
			e.stopPropagation();
			return;
		}
		
		// === Guard 2 (v3.4.3): Port click → CLEAR SELECTION ===
		if (isPortTarget(cast e.target))
		{
			if (onSelect != null) onSelect(null);
			Impulsys.quickEmit(EventType.NODE_CLICKED, { view: null, id: null, ctrlKey: false });
			
			// Find which port was clicked and emit PORT_RIGHT_CLICKED
			var current:DisplayObject = cast e.target;
			while (current != null && current != this)
			{
				if (Std.isOfType(current, Sprite))
				{
					var spr:Sprite = cast current;
					if (spr.name != null && spr.name != "")
					{
						if (inputPorts.exists(spr.name))
						{
							Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED, {
								nodeId: nodeId, contactName: spr.name, isInput: true,
								x: e.stageX, y: e.stageY
							});
							e.stopPropagation();
							return;
						}
						if (outputPorts.exists(spr.name))
						{
							Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED, {
								nodeId: nodeId, contactName: spr.name, isInput: false,
								x: e.stageX, y: e.stageY
							});
							e.stopPropagation();
							return;
						}
					}
				}
				current = current.parent;
			}
			e.stopPropagation();
			return;
		}
		
		// === Normal behavior: emit node right-click event ===
		Impulsys.quickEmit(EventType.NODE_RIGHT_CLICKED, { view: this, id: nodeId, x: e.stageX, y: e.stageY });
		e.stopPropagation();
	}

	private function onSettingsClick(e:MouseEvent):Void
	{
		e.stopPropagation();
		Impulsys.quickEmit(EventType.ATOM_PROPERTIES_REQUEST, { atom: atom, view: this });
	}

	// ┌─────────────────────────────────────────────────────────────────────┐
	// │                     MOUSE_DOWN Event Flow                           │
	// │                                                                     │
	// │  User clicks on ButtonWidget._btn                                   │
	// │                                                                     │
	// │  ┌───────────────────────────────────────────────────────────┐      │
	// │  │ Level 3: DeviceView.onWidgetMouseDown()                   │      │
	// │  │   → e.stopPropagation()                                   │      │
	// │  │   → Event STOPS here ✓                                    │      │
	// │  └───────────────────────────────────────────────────────────┘      │
	// │                                                                     │
	// │  If Level 3 somehow missed (e.g., direct TextField click):          │
	// │                                                                     │
	// │  ┌───────────────────────────────────────────────────────────┐      │
	// │  │ Level 2: InlineParameterEditor.onInputMouseDown()         │      │
	// │  │   → e.stopPropagation()                                   │      │
	// │  │   → Event STOPS here ✓                                    │      │
	// │  └───────────────────────────────────────────────────────────┘      │
	// │                                                                     │
	// │  If Levels 2+3 both missed (shouldn't happen, but just in case):    │
	// │                                                                     │
	// │  ┌───────────────────────────────────────────────────────────┐      │
	// │  │ Level 1: NodeView.onMouseDown()                           │      │
	// │  │   → isInteractiveTarget(e.target)                         │      │
	// │  │   → walks up: TextField? DeviceView? InlineEditor?        │      │
	// │  │   → found DeviceView → return (NO DRAG) ✓                 │      │
	// │  └───────────────────────────────────────────────────────────┘      │
	// │                                                                     │
	// │  Result: Node NEVER drags when clicking interactive elements ✓      │
	// └─────────────────────────────────────────────────────────────────────┘
	/**
	 * v3.4: Mouse-down handler with full interactive element protection.
	 *
	 * Order of guards:
	 *   1. Name editing in progress
	 *   2. Interactive element (widget / inline editor / input field)
	 *   3. Port click
	 *   4. Settings button click
	 *   5. → Start drag
	 *
	 * ─────────────────────────────────────────────────────────────────────
	 * Scenario 1: User clicks on TextField inside TextInputWidget
	 * ─────────────────────────────────────────────────────────────────────
	 *
	 *	User clicks on TextField inside TextInputWidget
	 *		│
	 *		▼
	 *	onMouseDown() is called on NodeView
	 *		│
	 *		├── Guard 1: _isEditingName? → NO
	 *		│
	 *		├── Guard 2: isInteractiveTarget(TextField)?
	 *		│       │
	 *		│       ├── current = TextField → not DeviceView, not InlineEditor
	 *		│       │   but tf.type == INPUT → return TRUE ✓
	 *		│       │
	 *		│       └── onMouseDown() → return (NO DRAG!) ✓
	 *		│
	 *		▼
	 *	Node does NOT move. TextField receives click normally.
	 *
	 * ─────────────────────────────────────────────────────────────────────
	 * Scenario 2: User clicks on empty node background
	 * ─────────────────────────────────────────────────────────────────────
	 *
	 *	User clicks on node background (empty area)
	 *		│
	 *		▼
	 *	onMouseDown() is called on NodeView
	 *		│
	 *		├── Guard 1: _isEditingName? → NO
	 *		│
	 *		├── Guard 2: isInteractiveTarget(Background Sprite)?
	 *		│       │
	 *		│       ├── current = Sprite → not DeviceView, not InlineEditor
	 *		│       ├── current = Sprite → not TextField
	 *		│       ├── current = NodeView (this) → loop ends
	 *		│       └── return FALSE
	 *		│
	 *		├── Guard 3: Port? → NO
	 *		├── Guard 4: Settings? → NO
	 *		│
	 *		└── → Start drag ✓ (node is being dragged)
	 */
	private function onMouseDown(e:MouseEvent):Void
	{
		// === Guard 1: Name editing in progress ===
		if (_isEditingName) return;
		
		// === Guard 2 (v3.4): Interactive element ===
		// Prevents node drag when user clicks on widgets (ButtonWidget,
		// TextInputWidget, ToggleWidget, etc.) or InlineParameterEditors.
		if (isInteractiveTarget(cast e.target)) return;
		
// === Guard 3 (v3.4.3): Port click → CLEAR SELECTION ===
// When clicking on a port (to start wire drag), clear all node selection.
// User is focused on wire creation, not node manipulation.
	if (isPortTarget(cast e.target))
	{
		if (onSelect != null) onSelect(null);
		Impulsys.quickEmit(EventType.NODE_CLICKED, { view: null, id: null, ctrlKey: e.ctrlKey });
		e.stopPropagation();
		return;
	}
		
		// === Guard 4: Settings button click ===
		var targetObj:DisplayObject = cast e.target;
		while (targetObj != null && targetObj != this)
		{
			if (targetObj == _settingsButton)
			{
				e.stopPropagation();
				return;
			}
			targetObj = targetObj.parent;
		}
		
		// === All guards passed → Start drag ===
		_dragOffsetX = e.localX;
		_dragOffsetY = e.localY;
		if (parent != null) parent.addChild(this);
		if (stage != null)
		{
			stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
			stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
		}
		e.stopPropagation();
	}

	private function onMouseMoveDrag(e:MouseEvent):Void
	{
		var parentPos = parent.globalToLocal(new Point(e.stageX, e.stageY));
		var newX = parentPos.x - _dragOffsetX;
		var newY = parentPos.y - _dragOffsetY;
		var dx = newX - this.x;
		var dy = newY - this.y;
		if (dx != 0 || dy != 0)
		{
			this.x = newX;
			this.y = newY;
			ECS.updatePosition(nodeId, newX, newY);
			Impulsys.quickEmit(EventType.EDITOR_NODE_MOVED, { id: this.nodeId, view: this, dx: dx, dy: dy });
		}
	}

	private function onMouseUpDrag(e:MouseEvent):Void
	{
		if (stage != null)
		{
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
			stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUpDrag);
		}
		Impulsys.quickEmit(EventType.NODE_DRAG_FINISHED, { view: this, id: nodeId });
	}

	private function onMouseUp(e:MouseEvent):Void
	{
		if (!_isDragging) return;
		_isDragging = false;
		stopDrag();
		if (stage != null) stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
		Impulsys.quickEmit(EventType.NODE_DRAG_FINISHED, { view: this, id: nodeId });
	}

// =========================================================================
// INLINE NAME EDITING (v3.3)
// =========================================================================
	/**
	* Begin inline name editing.
	* Replaces title label with an input TextField.
	*/
	private function startNameEditing():Void
	{
		if (_isEditingName) return;
		_isEditingName = true;
		// Hide title label
		_titleLabel.visible = false;
		// Create input field lazily (first time only)
		if (_nameInput == null)
		{
			_nameInput = new TextField();
			_nameInput.type = TextFieldType.INPUT;
			_nameInput.width = _nodeWidth - 50;
			_nameInput.height = TITLE_HEIGHT - 4;
			_nameInput.x = 5;
			_nameInput.y = 2;
			_nameInput.border = true;
			_nameInput.borderColor = 0x00AAFF;
			_nameInput.background = true;
			_nameInput.backgroundColor = 0x111122;
			_nameInput.textColor = 0xFFFFFF;
			_nameInput.selectable = true;
			_nameInput.mouseEnabled = true;
			var fmt = new TextFormat("_sans", 11, 0xFFFFFF, true);
			_nameInput.defaultTextFormat = fmt;
			_nameInput.addEventListener(KeyboardEvent.KEY_DOWN, onNameKeyDown);
			_nameInput.addEventListener(FocusEvent.FOCUS_OUT, onNameFocusOut);
			_titleBar.addChild(_nameInput);
		}
		// Populate with current name and show
		_nameInput.text = atom.displayName;
		_nameInput.visible = true;
		_nameInput.borderColor = 0x00AAFF; // Reset border color
		_nameInput.setSelection(0, _nameInput.text.length);
		if (stage != null) stage.focus = _nameInput;
		trace('NodeView: Started name editing for "${atom.displayName}"');
	}

	/**
	* Finish name editing — apply the new name.
	* Checks uniqueness via parent Assembly.
	*/
	private function finishNameEditing():Void
	{
		if (!_isEditingName) return;
		_isEditingName = false;
		var newName = StringTools.trim(_nameInput.text);
		// Empty name — revert
		if (newName.length == 0)
		{
			cancelNameEditing();
			return;
		}
		// Same name — just close
		if (newName == atom.displayName)
		{
			_nameInput.visible = false;
			_titleLabel.visible = true;
			return;
		}
		// === Uniqueness check ===
		if (_parentAssembly != null && _parentAssembly.hasAtomWithName(newName, atom.id))
		{
			// Name conflict — visual feedback
			trace('NodeView: Name "$newName" already exists in assembly!');
			_nameInput.borderColor = 0xFF3333;
			// Flash red for 1 second, then revert
			haxe.Timer.delay(function()
			{
				if (_nameInput != null)
				{
					_nameInput.borderColor = 0x00AAFF;
				}
			}, 1000);
			// Keep editing — don't apply
			_isEditingName = true; // Re-set so user can continue editing
			return;
		}
		// === Apply new name ===
		atom.displayName = newName;
		_titleLabel.text = newName;
		_nameInput.visible = false;
		_titleLabel.visible = true;
		// Save project
		Impulsys.quickEmit(EventType.VALUE_COMMITTED);
		trace('NodeView: Renamed atom to "$newName"');
	}

	/**
	* Cancel name editing — revert to original name.
	*/
	private function cancelNameEditing():Void
	{
		_isEditingName = false;
		if (_nameInput != null)
		{
			_nameInput.visible = false;
		}
		_titleLabel.visible = true;
	}

	/**
	* Handle keyboard events during name editing.
	* ENTER → apply, ESCAPE → cancel.
	*/
	private function onNameKeyDown(e:KeyboardEvent):Void
	{
		// Prevent global shortcuts (D, E, etc.) while editing
		e.stopImmediatePropagation();
		if (e.keyCode == Keyboard.ENTER)
		{
			finishNameEditing();
			if (stage != null) stage.focus = null;
		}
		else if (e.keyCode == Keyboard.ESCAPE)
		{
			cancelNameEditing();
			if (stage != null) stage.focus = null;
		}
	}

	/**
	* Handle focus-out during name editing.
	* Small delay to allow ENTER key to process first.
	*/
	private function onNameFocusOut(e:FocusEvent):Void
	{
		haxe.Timer.delay(function()
		{
			if (_isEditingName)
			{
				finishNameEditing();
			}
		}, 50);
	}

// =========================================================================
// PORT INTERACTION
// =========================================================================
	private function onPortMouseDown(contactName:String, isInput:Bool, e:MouseEvent):Void
	{
		var port = isInput ? inputPorts.get(contactName) : outputPorts.get(contactName);
		if (port == null) return;
		var globalPos = port.localToGlobal(new Point(0, 0));
		Impulsys.quickEmit(EventType.PORT_DRAG_START, {
			nodeId: nodeId, contactName: contactName, isInput: isInput, startX: globalPos.x, startY: globalPos.y
		});
	}

	private function onPortRightClick(contactName:String, isInput:Bool, e:MouseEvent):Void
	{
		Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED, {
			nodeId: nodeId, contactName: contactName, isInput: isInput, x: e.stageX, y: e.stageY
		});
	}

// =========================================================================
// POSITION
// =========================================================================
	public function setPosition(x:Float, y:Float):Void
	{
		this.x = x;
		this.y = y;
		ECS.updatePosition(nodeId, x, y);
	}

	public function getPortPosition(contactName:String): {x:Float, y:Float}
	{
		var port = inputPorts.get(contactName);
		if (port == null) port = outputPorts.get(contactName);
		if (port == null) return {x: this.x, y: this.y};
		var global = port.localToGlobal(new Point(0, 0));
		return {x: global.x, y: global.y};
	}

	public function getWirePoint(contactName:String, isInput:Bool): {x:Float, y:Float}
	{
		var ports = isInput ? inputPorts : outputPorts;
		var port = ports.get(contactName);
		if (port != null)
		{
			var global = port.localToGlobal(new Point(0, 0));
			return {x: global.x, y: global.y};
		}
		var x = isInput ? 0 : _nodeWidth;
		var y = _nodeHeight / 2;
		var global = localToGlobal(new Point(x, y));
		return {x: global.x, y: global.y};
	}

// =========================================================================
// ASSEMBLY SYNC (v3.0)
// =========================================================================
	private function onAssemblyPortsChanged(impulse:Impulse):Void
	{
		if (impulse.data != null && impulse.data.assemblyId == this.atom.id)
		{
			trace('NodeView: Ports changed event received for ${atom.displayName}. Rebuilding layout.');
			updateLayout();
			//updateInlineEditorsVisibility();
			alignInlineEditors();
		}
	}
	
	private function onWiresRedrawn(impulse:Impulse):Void
	{
		//updateInlineEditorsVisibility();
		alignInlineEditors();
	}

// =========================================================================
// DISPOSE
// =========================================================================
	public function dispose():Void
	{
		Impulsys.removeImpulse(EventType.ASSEMBLY_PORTS_CHANGED, onAssemblyPortsChanged);
		Impulsys.removeImpulse(EventType.REDRAW_WIRES, onWiresRedrawn);
		ECS.unregister(nodeId);
		removeEventListener(MouseEvent.DOUBLE_CLICK, onDoubleClick);
		removeEventListener(MouseEvent.CLICK, onClick);
		removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
		removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		if (_settingsButton != null)
		{
			_settingsButton.removeEventListener(MouseEvent.CLICK, onSettingsClick);
		}
		// === v3.3: Clean up inline name editor ===
		if (_nameInput != null)
		{
			_nameInput.removeEventListener(KeyboardEvent.KEY_DOWN, onNameKeyDown);
			_nameInput.removeEventListener(FocusEvent.FOCUS_OUT, onNameFocusOut);
			if (_nameInput.parent != null) _nameInput.parent.removeChild(_nameInput);
			_nameInput = null;
		}
		_isEditingName = false;
		_parentAssembly = null;
		for (name in _inlineEditors.keys())
		{
			var editor = _inlineEditors.get(name);
			if (editor != null) editor.dispose();
		}
		_inlineEditors.clear();
		if (deviceView != null && deviceView.parent == _previewContainer)
		{
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