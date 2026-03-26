package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import core.types.ContactType;
import library.AtomRegistry;
import editor.SelectionManager;
import editor.EditorActionHandler;
import editor.ViewportManager;
import editor.WireRenderer;
import editor.NodeView;
import editor.EditorTheme;
import core.view.DeviceViewRegistry;
import system.managers.UndoManager;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.base.MacroCommand;
import utils.UID;
import ecs.ECS;

using StringTools;

/**
 * NodeEditor v4.1 (Widget Restoration Fix)
 * Координатор визуального редактирования.
 *
 * v4.1 Changes:
 * - ADDED: restoreAllWidgets() method to return DeviceViews to NodeViews.
 * - FIXED: Widgets now properly return to schematic nodes when switching from Device Mode.
 *
 * v4.0 Changes (Refactored: Selection Extracted):
 * - Removed Selection logic -> SelectionManager.
 * - Removed Lasso logic -> SelectionManager.
 * - Clearer separation of concerns.
 */
class NodeEditor extends Sprite
{

	// =========================================================================
	// CORE
	// =========================================================================

	private var _assembly:Assembly;
	private var _blueprint:core.data.Blueprint;
	private var _theme:EditorTheme;

	// =========================================================================
	// MANAGERS
	// =========================================================================

	private var _viewport:ViewportManager;
	private var _actions:EditorActionHandler;
	private var _wireRenderer:WireRenderer;
	private var _selection:SelectionManager;

	// =========================================================================
	// NODE MANAGEMENT
	// =========================================================================

	private var _nodes:Map<String, NodeView> = new Map();
	private var _editorContainer:Sprite;
	private var _canvas:Sprite;
	private var _bgHitArea:Sprite;

	// =========================================================================
	// PORT DRAG
	// =========================================================================

	private var _isDraggingPort:Bool = false;
	private var _dragNodeId:String;
	private var _dragContactName:String;
	private var _dragStartX:Float = 0;
	private var _dragStartY:Float = 0;
	private var _dragStartIsInput:Bool = false;

	// =========================================================================
	// NODE DRAG
	// =========================================================================

	private var _draggingNode:NodeView = null;
	private var _dragStartPositions:Map<String, {x:Float, y:Float}>;

	// =========================================================================
	// EDGE PORTS
	// =========================================================================

	private var _frame:Sprite;
	private var _edgePortsContainer:Sprite;
	private var _edgePorts:Map<String, Sprite> = new Map();
	private var _fileNameField:openfl.text.TextField;
	private var _forcedWidth:Float = 0;
	private var _forcedHeight:Float = 0;

	// =========================================================================
	// VISIBILITY
	// =========================================================================

	private var _lastVisibilityUpdate:Float = 0;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================

	public function new(assembly:Assembly)
	{
		super();

		this._assembly = assembly;
		this._blueprint = assembly.blueprint;
		_theme = EditorTheme.getInstance();

		// Selection Manager
		_selection = new SelectionManager();

		// Layers
		_editorContainer = new Sprite();
		addChild(_editorContainer);

		_canvas = new Sprite();
		_editorContainer.addChild(_canvas);

		_canvas.graphics.beginFill(_theme.CANVAS_BG_COLOR, 1);
		_canvas.graphics.drawRect(-5000, -5000, 10000, 10000);
		_canvas.graphics.endFill();

		_bgHitArea = new Sprite();
		_bgHitArea.graphics.beginFill(_theme.CANVAS_HIT_AREA_COLOR, _theme.CANVAS_HIT_AREA_ALPHA);
		_bgHitArea.graphics.drawRect(-5000, -5000, 10000, 10000);
		_bgHitArea.graphics.endFill();
		_bgHitArea.mouseEnabled = true;
		_canvas.addChild(_bgHitArea);

		// Listeners
		_bgHitArea.addEventListener(MouseEvent.MOUSE_DOWN, onCanvasMouseDown);
		_bgHitArea.addEventListener(MouseEvent.RIGHT_CLICK, onCanvasRightClick);

		// Managers
		_viewport = new ViewportManager(_canvas);
		_actions = new EditorActionHandler(_assembly, _blueprint);

		_wireRenderer = new WireRenderer();
		_wireRenderer.configure(
			_blueprint, _assembly, _canvas,
			getNodeViewById, getEdgePortById,
			function() return _selection.getSelectedWireIds()
		);

		// Передаем ссылку на метод setWires, чтобы WireRenderer мог обновлять выделение
		_wireRenderer.setSelectionCallback(_selection.setWires);

		// Frame
		_frame = new Sprite();
		_frame.mouseEnabled = false;
		addChild(_frame);

		_edgePortsContainer = new Sprite();
		_edgePortsContainer.mouseEnabled = true;
		addChild(_edgePortsContainer);

		_fileNameField = new openfl.text.TextField();
		_fileNameField.defaultTextFormat = new openfl.text.TextFormat("_typewriter", 12, _theme.NODE_TEXT_COLOR);
		_fileNameField.text = _blueprint.name;
		_fileNameField.autoSize = LEFT;
		_fileNameField.selectable = false;
		addChild(_fileNameField);

		addEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);

		// Impulses
		Impulsys.subscribeToImpulse(EventType.PORT_DRAG_START, onPortDragStart);
		Impulsys.subscribeToImpulse(EventType.EDITOR_NODE_MOVED, onNodeMoved);
		Impulsys.subscribeToImpulse(EventType.NODE_DRAG_FINISHED, onNodeDragFinished);
		Impulsys.subscribeToImpulse(EventType.FORCE_UPDATE_NODE_POSITION, onForceUpdatePosition);
		Impulsys.subscribeToImpulse(EventType.REDRAW_WIRES, function(_) _wireRenderer.rebuildAll());
		Impulsys.subscribeToImpulse(EventType.ASSEMBLY_PORTS_CHANGED, function(_) { drawFrame(); _wireRenderer.rebuildAll(); });
		Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, onAtomDeleted);
		Impulsys.subscribeToImpulse(EventType.ATOM_RESTORED, onAtomRestored);
		Impulsys.subscribeToImpulse(EventType.NODE_CLICKED, onNodeClicked);
	}

	// =========================================================================
	// INIT
	// =========================================================================

	private function onAddedToStage_Frame(e:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);
		stage.addEventListener(Event.RESIZE, onResize);
		initListeners();
		drawFrame();
		restoreExistingAtoms();

		_selection.setContext(_assembly, _canvas, getNodeViewById);

		_wireRenderer.setSelectionCallback(_selection.setWires);

		_wireRenderer.rebuildAll();
	}

	private function onResize(e:Event):Void
	{
		if (_forcedWidth == 0 && _forcedHeight == 0) drawFrame();
	}

	private function initListeners():Void
	{
		stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
		stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
		stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
		stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
	}

	private function drawFrame(e:Event = null):Void
	{
		var w:Float = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
		var h:Float = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);

		_frame.graphics.clear();
		_frame.graphics.lineStyle(5, _theme.FRAME_BORDER_COLOR);
		_frame.graphics.drawRect(0, 0, w, h);

		_editorContainer.scrollRect = new Rectangle(0, 0, w, h);

		_fileNameField.x = w - 10 - _fileNameField.width;
		_fileNameField.y = h - 20;

		_edgePortsContainer.removeChildren();
		_edgePorts = new Map();

		var leftPorts = _assembly.getOrderedPorts(INPUT);
		var rightPorts = _assembly.getOrderedPorts(OUTPUT);

		var leftStep:Float = h / (leftPorts.length + 1);
		var rightStep:Float = h / (rightPorts.length + 1);

		var leftIdx:Int = 0;
		for (p in leftPorts)
		{
			var c:Contact = p.internal;
			var portView = createEdgePort(c, false, p.name);
			portView.x = 0;
			portView.y = leftStep * (leftIdx + 1);
			_edgePortsContainer.addChild(portView);
			_edgePorts.set(p.name, portView);
			leftIdx++;
		}

		var rightIdx:Int = 0;
		for (p in rightPorts)
		{
			var c:Contact = p.internal;
			var portView = createEdgePort(c, true, p.name);
			portView.x = w;
			portView.y = rightStep * (rightIdx + 1);
			_edgePortsContainer.addChild(portView);
			_edgePorts.set(p.name, portView);
			rightIdx++;
		}

		_wireRenderer.updateEdgeWires();
	}

	private function createEdgePort(contact:Contact, isInput:Bool, portName:String):Sprite
	{
		var s = new Sprite();
		s.graphics.beginFill(_theme.PORT_COLOR_DEFAULT);
		s.graphics.drawCircle(0, 0, 6);
		s.graphics.endFill();
		s.buttonMode = true;
		s.useHandCursor = true;
		s.name = portName;

		s.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			e.stopPropagation();
			var globalPos = s.localToGlobal(new Point(0, 0));
			Impulsys.quickEmit(EventType.PORT_DRAG_START,
			{
				nodeId: "SELF",
				contactName: portName,
				isInput: isInput,
				startX: globalPos.x,
				startY: globalPos.y
			});
		});

		s.addEventListener(MouseEvent.RIGHT_CLICK, function(e:MouseEvent)
		{
			e.stopPropagation();
			Impulsys.quickEmit(EventType.PORT_RIGHT_CLICKED,
			{
				portName: portName,
				x: e.stageX,
				y: e.stageY
			});
		});

		return s;
	}

	// =========================================================================
	// NODE MANAGEMENT
	// =========================================================================

	private function restoreExistingAtoms():Void
	{
		if (_blueprint.internalAtoms == null) return;
		for (atomDef in _blueprint.internalAtoms)
		{
			var runtimeId = _assembly.idMap.get(atomDef.instanceId);
			if (runtimeId == null) runtimeId = atomDef.instanceId;
			var atomInstance = _assembly.internalAtoms.get(runtimeId);
			if (atomInstance != null)
			{
				createViewForAtom(cast atomInstance, runtimeId, atomDef.x, atomDef.y);
			}
		}
	}

	private function createViewForAtom(atom:Atom, id:String, x:Float, y:Float):Void
	{
		if (_nodes.exists(id)) return;
		var view:NodeView = new NodeView(atom, id);
		view.setPosition(x, y);
		_canvas.addChild(view);
		_nodes.set(id, view);
	}

	public function createAtom(typeId:String, posX:Float, posY:Float):Atom
	{
		var bp = AtomRegistry.get(typeId);
		if (bp == null) return null;
		var localPoint = _canvas.globalToLocal(new Point(posX, posY));
		_actions.createAtom(typeId, localPoint.x, localPoint.y);
		return null;
	}

	public function refreshAssemblyViews():Void
	{
		for (view in _nodes)
		{
			if (Std.isOfType(view.atom, Assembly))
			{
				view.redraw();
			}
		}
		_wireRenderer.rebuildAll();
	}

	// =========================================================================
	// WIDGET RESTORATION (v4.1 FIX)
	// =========================================================================

	/**
	 * Returns all DeviceViews from external containers (DevicePanel/Window)
	 * back to their NodeViews.
	 * Called by Main.hx when switching from Device Mode to Editor Mode.
	 */
	public function restoreAllWidgets():Void
	{
		// trace('NodeEditor: Restoring widgets to NodeViews...');
		for (id in _nodes.keys())
		{
			var view = _nodes.get(id);
			if (view != null)
			{
				view.acceptWidget();
			}
		}
	}

	// =========================================================================
	// SELECTION API (Delegation)
	// =========================================================================

	public function deselectAll():Void
	{
		_selection.deselectAll();
		_wireRenderer.rebuildAll();
	}

	public function selectAll():Void
	{
		var allIds = [for (id in _nodes.keys()) id];
		_selection.selectAll(allIds);
	}

	public function selectNode(id:String, view:NodeView):Void _selection.selectNode(id, view);

	public function isSelected(nodeId:String):Bool return _selection.hasNode(nodeId);

	public function getSelectedNodeIds():Array<String> return _selection.getSelectedNodeIds();
	public function getSelectedNodeCount():Int return _selection.getSelectedNodeCount();
	public function getSelectedWireIds():Array<String> return _selection.getSelectedWireIds();
	public function clearWireSelection():Void {_selection.clearWires(); _wireRenderer.rebuildAll(); }
	// =========================================================================
	// CLIPBOARD API (Restored)
	// =========================================================================

	public function copySelection():Void
	{
		_actions.copySelection(getSelectedNodeIds());
	}

	public function cutSelection():Void
	{
		_actions.cutSelection(getSelectedNodeIds());
		deselectAll();
	}

	public function pasteSelection():Void
	{
		var idMap = _actions.pasteSelection(25.0);
		if (idMap != null)
		{
			deselectAll();
			for (newId in idMap)
			{
				var view = _nodes.get(newId);
				if (view != null)
				{
					_selection.selectNode(newId, view);
				}
			}
		}
	}

	// =========================================================================
	// SELECTION EVENTS
	// =========================================================================

	private function onCanvasMouseDown(e:MouseEvent):Void
	{
		var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
		_selection.handleCanvasMouseDown(local.x, local.y);
	}

	private function onCanvasRightClick(e:MouseEvent):Void
	{
		e.stopPropagation();
		Impulsys.quickEmit(EventType.CANVAS_RIGHT_CLICKED, {
			x: e.stageX,
			y: e.stageY
		});
	}

	private function onNodeClicked(impulse:Impulse):Void
	{
		var view:NodeView = impulse.data.view;
		var ctrl:Bool = impulse.data.ctrlKey;
		_selection.handleNodeClick(view.nodeId, view, ctrl);
	}

	// =========================================================================
	// MOUSE MOVE
	// =========================================================================

	private function onMouseMove(e:MouseEvent):Void
	{
		if (_viewport.isPanning())
		{
			_viewport.handlePanMove(e.stageX, e.stageY);
			_wireRenderer.updateEdgeWires();
			updateVisibility();
			return;
		}

		if (_isDraggingPort)
		{
			_wireRenderer.drawGhostWire(_dragStartX, _dragStartY, e.stageX, e.stageY, _dragStartIsInput);
			return;
		}

		if (_selection.isLassoing())
		{
			var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
			_selection.handleMouseMove(local.x, local.y);
		}
	}

	// =========================================================================
	// MOUSE UP
	// =========================================================================

	private function onMouseUp(e:MouseEvent):Void
	{
		if (_viewport.isPanning())
		{
			_viewport.handlePanEnd();
			_wireRenderer.rebuildAll();
			updateVisibility();
			return;
		}

		if (_isDraggingPort)
		{
			handleWireDragEnd(e);
			return;
		}

		if (_selection.isLassoing())
		{
			_selection.handleMouseUp();
			// После лассо/клика по пустому месту нужно перерисовать провода,
			// так как выделение могло сброситься.
			_wireRenderer.rebuildAll();
		}
	}

	private function handleWireDragEnd(e:MouseEvent):Void
	{
		var target = findPortAt(e.stageX, e.stageY);
		if (target != null)
		{
			var isSameContact = (_dragNodeId == target.nodeId && _dragContactName == target.contactName);
			var startIsSource = !_dragStartIsInput;
			var targetIsSource = !target.isInput;

			if (!isSameContact && (startIsSource != targetIsSource))
			{
				var realFromId:String; var realFromContact:String;
				var realToId:String; var realToContact:String;

				if (startIsSource)
				{
					realFromId = _dragNodeId; realFromContact = _dragContactName;
					realToId = target.nodeId; realToContact = target.contactName;
				}
				else
				{
					realFromId = target.nodeId; realFromContact = target.contactName;
					realToId = _dragNodeId; realToContact = _dragContactName;
				}

				_actions.connect(realFromId, realFromContact, realToId, realToContact);
				_wireRenderer.rebuildAll();
			}
		}

		_isDraggingPort = false;
		_wireRenderer.clearGhostWire();
	}

	// =========================================================================
	// NODE DRAG
	// =========================================================================

	private function onNodeMoved(impulse:Impulse):Void
	{
		var sourceView:NodeView = impulse.data.view;
		var dx:Float = impulse.data.dx;
		var dy:Float = impulse.data.dy;

		// 1. Инициализация (первый кадр перетаскивания)
		if (_draggingNode == null)
		{
			_draggingNode = sourceView;
			_dragStartPositions = new Map();

			// === FIX: Определяем тип перетаскивания ===
			var isMovingGroup = _selection.hasNode(sourceView.nodeId);
			var nodesToMove:Array<String> = [];

			if (isMovingGroup)
			{
				// Двигаем группу: берем всех выделенных
				nodesToMove = _selection.getSelectedNodeIds();
			}
			else
			{
				// Двигаем соло: берем только текущий узел
				nodesToMove = [sourceView.nodeId];
			}

			// Говорим рендереру следить за этими проводами
			_wireRenderer.setActiveWiresForNodes(nodesToMove);

			// Сохраняем стартовые позиции для Undo
			for (id in nodesToMove)
			{
				var v = _nodes.get(id);
				if (v != null) _dragStartPositions.set(id, {x: v.x, y: v.y});
			}
		}

		// 2. Перемещение
		// SourceView двигается сам в NodeView.onMouseMoveDrag.
		// Здесь мы двигаем "остальных".

		if (_selection.hasNode(sourceView.nodeId))
		{
			// Это групповое перетаскивание. Двигаем всех, кроме источника.
			for (id in _selection.getSelectedNodeIds())
			{
				if (id == sourceView.nodeId) continue; // Источник уже сдвинут

				var view = _nodes.get(id);
				if (view != null)
				{
					view.x += dx;
					view.y += dy;
					ECS.updatePosition(id, view.x, view.y);
				}
			}
		}
		// Если это был Single Drag (узел не выделен), то никого другого двигать не надо.

		// 3. Обновляем визуал проводов
		_wireRenderer.updateActiveWires();
		_wireRenderer.updateEdgeWires();
	}

	private function onNodeDragFinished(impulse:Impulse):Void
	{
		var moves:Array<{id:String, fromX:Float, fromY:Float, toX:Float, toY:Float}> = [];

		if (_dragStartPositions != null)
		{
			for (id in _dragStartPositions.keys())
			{
				var startPos = _dragStartPositions.get(id);
				var view = _nodes.get(id);
				if (view != null)
				{
					var templateId = _assembly.getTemplateId(id);
					moves.push({id: templateId, fromX: startPos.x, fromY: startPos.y, toX: view.x, toY: view.y});
					// Сохраняем в Blueprint
					for (atom in _blueprint.internalAtoms)
					{
						if (atom.instanceId == templateId)
						{
							atom.x = view.x;
							atom.y = view.y;
							break;
						}
					}
				}
			}
		}

		if (moves.length > 0) _actions.moveAtoms(moves);

		_wireRenderer.clearActiveWires();
		_draggingNode = null;
		_dragStartPositions = null;

		// Финализация выделения
		// Если мы перетащили узел, который НЕ был выделен,
		// делаем его единственным выделенным (стандартное поведение любого редактора).
		if (!_selection.hasNode(impulse.data.view.nodeId))
		{
			deselectAll();
			selectNode(impulse.data.view.nodeId, impulse.data.view);
		}

		_wireRenderer.rebuildAll();
	}

	// =========================================================================
	// VIEWPORT
	// =========================================================================

	public function getViewState(): {x:Float, y:Float, zoom:Float} return _viewport.getViewState();
	public function setViewState(state: {x:Float, y:Float, zoom:Float}):Void
	{
		_viewport.setViewState(state);
		updateVisibility();
	}

	private function onMiddleMouseDown(e:MouseEvent):Void _viewport.handlePanStart(e.stageX, e.stageY);
	private function onMiddleMouseUp(e:MouseEvent):Void
	{
		if (_viewport.isPanning())
		{
			_viewport.handlePanEnd();
			_wireRenderer.rebuildAll();
			updateVisibility();
		}
	}
	private function onMouseWheel(e:MouseEvent):Void
	{
		_viewport.handleZoom(e.delta, e.stageX, e.stageY, this);
		_wireRenderer.rebuildAll();
		updateVisibility();
	}

	private function updateVisibility():Void
	{
		var now = haxe.Timer.stamp();
		if (now - _lastVisibilityUpdate < 0.1) return;
		_lastVisibilityUpdate = now;

		var w = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
		var h = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);
		_viewport.updateVisibility(_nodes.iterator(), w, h);
	}

	// =========================================================================
	// DELETE
	// =========================================================================

	public function deleteSelectedNodes():Array<String>
	{
		var ids = _selection.getSelectedNodeIds();
		_actions.deleteAtoms(ids);
		return ids;
	}

	public function deleteSelectedWires():Void
	{
		var ids = _selection.getSelectedWireIds();
		if (ids.length == 0) return;
		_actions.deleteWires(ids);
		_selection.deselectAll();
		_wireRenderer.rebuildAll();
	}

	// =========================================================================
	// PORT DRAG START
	// =========================================================================

	private function onPortDragStart(impulse:Impulse):Void
	{
		_isDraggingPort = true;
		_dragNodeId = impulse.data.nodeId;
		_dragContactName = impulse.data.contactName;
		_dragStartX = impulse.data.startX;
		_dragStartY = impulse.data.startY;
		_dragStartIsInput = impulse.data.isInput;
	}

	// =========================================================================
	// EVENTS
	// =========================================================================

	private function onAtomDeleted(impulse:Impulse):Void
	{
		if (impulse.data.assemblyId != _assembly.id) return;
		var id:String = impulse.data.id;
		var view = _nodes.get(id);
		if (view != null)
		{
			view.dispose();
			if (view.parent == _canvas) _canvas.removeChild(view);
			_nodes.remove(id);
			_wireRenderer.rebuildAll();
		}
	}

	private function onAtomRestored(impulse:Impulse):Void
	{
		if (impulse.data.assemblyId != _assembly.id) return;
		var id:String = impulse.data.id;
		var x:Float = impulse.data.x;
		var y:Float = impulse.data.y;
		var atom:Atom = impulse.data.atom;
		if (atom != null)
		{
			createViewForAtom(atom, id, x, y);
			_wireRenderer.rebuildAll();
		}
	}

	private function onForceUpdatePosition(impulse:Impulse):Void
	{
		var data = impulse.data;
		var view = _nodes.get(data.id);
		if (view != null)
		{
			if (view.x != data.x || view.y != data.y)
			{
				view.setPosition(data.x, data.y);
				_wireRenderer.rebuildAll();
			}
		}
	}

	// =========================================================================
	// HELPERS
	// =========================================================================

	private function getNodeViewById(id:String):NodeView return _nodes.get(id);
	private function getEdgePortById(name:String):Sprite return _edgePorts.get(name);

	private function findPortAt(x:Float, y:Float): {nodeId:String, contactName:String, isInput:Bool}
	{
		// Edge Ports
		for (name in _edgePorts.keys())
		{
			var port = _edgePorts.get(name);
			var local = port.globalToLocal(new Point(x, y));
			if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10)
			{
				var asmPort = _assembly.ports.get(name);
				var isInput:Bool = (asmPort.type != INPUT);
				return { nodeId: "SELF", contactName: name, isInput: isInput };
			}
		}
		// Node Ports
		for (nodeId in _nodes.keys())
		{
			var view = _nodes.get(nodeId);
			if (view != null)
			{
				for (name in view.inputPorts.keys())
				{
					var port = view.inputPorts.get(name);
					if (port != null)
					{
						var local = port.globalToLocal(new Point(x, y));
						if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: true};
					}
				}
				for (name in view.outputPorts.keys())
				{
					var port = view.outputPorts.get(name);
					if (port != null)
					{
						var local = port.globalToLocal(new Point(x, y));
						if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: false};
					}
				}
			}
		}
		return null;
	}

	// =========================================================================
	// PROPERTIES
	// =========================================================================

	public function setSize(w:Float, h:Float):Void { _forcedWidth = w; _forcedHeight = h; drawFrame(); }
	public function setUseEcsRender(v:Bool):Void {} // Stub
	public function setWireType(v:ui.WireType):Void {} // Stub
	public function setAllowAssembly(v:Bool):Void {} // Stub

	public function getNodeCount():Int { var c = 0; for (id in _nodes.keys()) c++; return c; }
	public function getWireCount():Int return _wireRenderer.getWireCount();

	// =========================================================================
	// DISPOSE
	// =========================================================================

	public function dispose():Void
	{
		if (stage != null)
		{
			stage.removeEventListener(Event.RESIZE, onResize);
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
			stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
			stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
			stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
			stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
		}

		Impulsys.removeImpulse(EventType.PORT_DRAG_START, onPortDragStart);
		Impulsys.removeImpulse(EventType.EDITOR_NODE_MOVED, onNodeMoved);
		Impulsys.removeImpulse(EventType.NODE_DRAG_FINISHED, onNodeDragFinished);
		Impulsys.removeImpulse(EventType.FORCE_UPDATE_NODE_POSITION, onForceUpdatePosition);
		Impulsys.removeImpulse(EventType.REDRAW_WIRES, function(_) _wireRenderer.rebuildAll());
		Impulsys.removeImpulse(EventType.ASSEMBLY_PORTS_CHANGED, function(_) { drawFrame(); _wireRenderer.rebuildAll(); });
		Impulsys.removeImpulse(EventType.ATOM_DELETED, onAtomDeleted);
		Impulsys.removeImpulse(EventType.ATOM_RESTORED, onAtomRestored);
		Impulsys.removeImpulse(EventType.NODE_CLICKED, onNodeClicked);

		_selection.dispose();
		_wireRenderer.dispose();

		for (view in _nodes)
		{
			view.dispose();
		}

		for (nodeId in _nodes.keys()) ECS.unregister(nodeId);
		_nodes.clear();
	}
}