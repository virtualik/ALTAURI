package editor;

//import ui.WireType;
import ui.WireType.WireType as WireTypeEnum;
import openfl.display.Sprite;
//import openfl.display.Graphics;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
//import openfl.text.TextFormatAlign;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.Impulse;
//import system.managers.UndoManager;
//import system.commands.base.MacroCommand;
//import system.commands.editor.MoveNodeCommand;
//import system.commands.editor.ConnectCommand;
//import system.commands.editor.DeleteAtomCommand;
//import system.commands.editor.CreateAtomCommand;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import ecs.ECS;
import library.AtomRegistry;
//import utils.UID;

/**
 * NodeEditor v3.1 (ContextMenu Refactor)
 * Main editor coordinator. Delegates Pan/Zoom to ViewportManager
 * and Actions/Undo to EditorActionHandler.
 * Emits CANVAS_RIGHT_CLICKED for ContextMenuManager.
 */
class NodeEditor extends Sprite {
    
    // ========================================================================
    // CORE REFERENCES
    // ========================================================================

    private var _assembly:Assembly;
    private var _blueprint:core.data.Blueprint;
    private var _theme:EditorTheme;

    // ========================================================================
    // MANAGERS (NEW)
    // ========================================================================

    private var _viewport:ViewportManager;
    private var _actions:EditorActionHandler;
    private var _wireRenderer:WireRenderer;

    // ========================================================================
    // NODE MANAGEMENT
    // ========================================================================

    private var _nodes:Map<String, NodeView> = new Map();
    private var _canvas:Sprite;
    private var _bgHitArea:Sprite;

    // ========================================================================
    // SELECTION
    // ========================================================================

    private var _selectedNodes:Map<String, NodeView> = new Map();
    private var _selectedWireIds:Array<String> = [];

    // ========================================================================
    // LASSO
    // ========================================================================

    private var _lasso:Sprite;
    private var _isLassoing:Bool = false;
    private var _lassoStartX:Float = 0;
    private var _lassoStartY:Float = 0;

    // ========================================================================
    // NODE DRAG
    // ========================================================================

    private var _dragStartPositions:Map<String, {x:Float, y:Float}>;
    private var _draggingNode:NodeView = null;

    // ========================================================================
    // PORT CONNECTION DRAG
    // ========================================================================

    private var _isDraggingPort:Bool = false;
    private var _dragNodeId:String;
    private var _dragContactName:String;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _dragStartIsInput:Bool = false;

    // ========================================================================
    // EDGE PORTS
    // ========================================================================

    private var _frame:Sprite;
    private var _edgePortsContainer:Sprite;
    private var _edgePorts:Map<String, Sprite> = new Map();
    private var _fileNameField:TextField;
    private var _viewportMask:Sprite;
    private var _zoomDebounceTimer:haxe.Timer = null;
    private var _pendingZoom:Bool = false;
    

    // ========================================================================
    // SETTINGS
    // ========================================================================

    private var _useEcsRender:Bool = true;
    private var _allowAssembly:Bool = true;
    private var _forcedWidth:Float = 0;
    private var _forcedHeight:Float = 0;
    private var _lastVisibilityUpdate:Float = 0;
    private var _zoomRebuildTimer:haxe.Timer = null;
    
    // ========================================================================
    // CALLBACKS
    // ========================================================================

    private var _cbRedraw:Impulse -> Void;
    private var _cbPortsChanged:Impulse -> Void;

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    public function new(assembly:Assembly) {
        super();
        this._assembly = assembly;
        this._blueprint = assembly.blueprint;
        _theme = EditorTheme.getInstance();

        ECS.init();

        // Create canvas
        _canvas = new Sprite();
        _canvas.graphics.beginFill(_theme.CANVAS_BG_COLOR, 1);
        _canvas.graphics.drawRect(-5000, -5000, 10000, 10000);
        _canvas.graphics.endFill();
        addChild(_canvas);

        // Background hit area
        _bgHitArea = new Sprite();
        _bgHitArea.graphics.beginFill(_theme.CANVAS_HIT_AREA_COLOR, _theme.CANVAS_HIT_AREA_ALPHA);
        _bgHitArea.graphics.drawRect(-5000, -5000, 10000, 10000);
        _bgHitArea.graphics.endFill();
        _bgHitArea.mouseEnabled = true;
        _canvas.addChild(_bgHitArea);

        // Viewport mask
        _viewportMask = new Sprite();
        _viewportMask.mouseEnabled = false;
        addChild(_viewportMask);
        _canvas.mask = _viewportMask;

        _bgHitArea.addEventListener(MouseEvent.MOUSE_DOWN, onCanvasMouseDown);
        _bgHitArea.addEventListener(MouseEvent.RIGHT_CLICK, onCanvasRightClick); // <--- NEW: Context Menu Trigger

        // Lasso
        _lasso = new Sprite();
        _lasso.mouseEnabled = false;
        _canvas.addChild(_lasso);

        // Init ViewportManager
        _viewport = new ViewportManager(_canvas);

        // Init ActionHandler
        _actions = new EditorActionHandler(_assembly, _blueprint);

        // Init WireRenderer
        _wireRenderer = new WireRenderer();
        _wireRenderer.configure(
            _blueprint,
            _assembly,
            _canvas,
            getNodeViewById,
            getEdgePortById,
            getSelectedWireIdsInternal
        );
        _wireRenderer.setSelectionCallback(onWireSelectionChanged);

        // Frame & edge ports
        _frame = new Sprite();
        _frame.mouseEnabled = false;
        addChild(_frame);

        _edgePortsContainer = new Sprite();
        _edgePortsContainer.mouseEnabled = true;
        addChild(_edgePortsContainer);

        _fileNameField = new TextField();
        _fileNameField.defaultTextFormat = new TextFormat("_typewriter", 12, _theme.NODE_TEXT_COLOR);
        _fileNameField.text = _blueprint.name;
        _fileNameField.autoSize = RIGHT;
        _fileNameField.mouseEnabled = false;
        addChild(_fileNameField);

        addEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);

        // Subscribe to impulses
        _cbRedraw = function(_) _wireRenderer.rebuildAll();
        _cbPortsChanged = function(_) onPortsChanged();

        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.subscribeToImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.subscribeToImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.subscribeToImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.subscribeToImpulse("ASSEMBLY_PORTS_CHANGED", _cbPortsChanged);
        Impulsys.subscribeToImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.subscribeToImpulse("ATOM_RESTORED", onAtomRestored);
        Impulsys.subscribeToImpulse("NODE_CLICKED", onNodeClicked);
    }

    // ========================================================================
    // WIRERENDERER ACCESSORS
    // ========================================================================

    private function getNodeViewById(id:String):NodeView return _nodes.get(id);
    private function getEdgePortById(name:String):Sprite return _edgePorts.get(name);
    private function getSelectedWireIdsInternal():Array<String> return _selectedWireIds.copy();
    private function onWireSelectionChanged(newSelection:Array<String>):Void _selectedWireIds = newSelection;

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    private function onAddedToStage_Frame(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);
        stage.addEventListener(Event.RESIZE, onResize);
        initListeners();
        drawFrame();
        restoreExistingAtoms();
        _wireRenderer.rebuildAll();
    }

    private function onResize(e:Event):Void {
        if (_forcedWidth == 0 && _forcedHeight == 0) {
            drawFrame();
            _wireRenderer.rebuildAll();
        }
    }

    private function initListeners():Void {
        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
        stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
        stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
    }

    // ========================================================================
    // SIZE & FRAME
    // ========================================================================

    public function setSize(w:Float, h:Float):Void {
        _forcedWidth = w;
        _forcedHeight = h;
        drawFrame();
    }

    private function onPortsChanged():Void {
        drawFrame();
        _wireRenderer.rebuildAll();
    }

    private function drawFrame(e:Event = null):Void {
        var w:Float = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
        var h:Float = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);

        _frame.graphics.clear();
        _frame.graphics.lineStyle(5, _theme.FRAME_BORDER_COLOR);
        _frame.graphics.drawRect(0, 0, w, h);

        _viewportMask.graphics.clear();
        _viewportMask.graphics.beginFill(0xFFFFFF);
        _viewportMask.graphics.drawRect(0, 0, w, h);
        _viewportMask.graphics.endFill();

        _fileNameField.x = w - 10 - _fileNameField.width;
        _fileNameField.y = h - 20;

        _edgePortsContainer.removeChildren();
        _edgePorts = new Map();

        var leftPorts = _assembly.getOrderedPorts(INPUT);
        var rightPorts = _assembly.getOrderedPorts(OUTPUT);

        var leftStep:Float = h / (leftPorts.length + 1);
        var rightStep:Float = h / (rightPorts.length + 1);

        var leftIdx:Int = 0;
        for (p in leftPorts) {
            var c:Contact = p.internal;
            var portView = createEdgePort(c, false, p.name);
            portView.x = 0;
            portView.y = leftStep * (leftIdx + 1);
            _edgePortsContainer.addChild(portView);
            _edgePorts.set(p.name, portView);
            leftIdx++;
        }

        var rightIdx:Int = 0;
        for (p in rightPorts) {
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

    private function createEdgePort(contact:Contact, isInput:Bool, portName:String):Sprite {
        var s = new Sprite();
        s.graphics.beginFill(_theme.PORT_COLOR_DEFAULT);
        s.graphics.drawCircle(0, 0, 6);
        s.graphics.endFill();

        s.buttonMode = true;
        s.useHandCursor = true;
        s.name = portName;

        s.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
            e.stopPropagation();
            var globalPos = s.localToGlobal(new Point(0, 0));
            Impulsys.emit(new Impulse("PORT_DRAG_START", {
                nodeId: "SELF",
                contactName: portName,
                isInput: isInput,
                startX: globalPos.x,
                startY: globalPos.y
            }));
        });

        s.addEventListener(MouseEvent.RIGHT_CLICK, function(e:MouseEvent) {
            e.stopPropagation();
            Impulsys.emit(new Impulse("PORT_RIGHT_CLICKED", {
                portName: portName,
                x: e.stageX,
                y: e.stageY
            }));
        });

        return s;
    }

    // ========================================================================
    // VIEWPORT STATE (Delegated)
    // ========================================================================

    public function getViewState():{x:Float, y:Float, zoom:Float} {
        return _viewport.getViewState();
    }

    public function setViewState(state:{x:Float, y:Float, zoom:Float}):Void {
        _viewport.setViewState(state);
        updateVisibility();
    }

    private function updateVisibility():Void {
        var now = haxe.Timer.stamp();
        if (now - _lastVisibilityUpdate < 0.1) return; // Не чаще 10 раз в секунду
        _lastVisibilityUpdate = now;
        
        var w = _forcedWidth > 0 ? _forcedWidth : (stage != null ? stage.stageWidth : 1024);
        var h = _forcedHeight > 0 ? _forcedHeight : (stage != null ? stage.stageHeight : 600);
        _viewport.updateVisibility(_nodes.iterator(), w, h);
    }

    // ========================================================================
    // NODE MANAGEMENT
    // ========================================================================

    private function restoreExistingAtoms():Void {
        if (_blueprint.internalAtoms == null) return;

        for (atomDef in _blueprint.internalAtoms) {
            var runtimeId = _assembly.idMap.get(atomDef.instanceId);
            if (runtimeId == null) runtimeId = atomDef.instanceId;

            var atomInstance = _assembly.internalAtoms.get(runtimeId);
            if (atomInstance != null) {
                createViewForAtom(cast atomInstance, runtimeId, atomDef.x, atomDef.y);
            }
        }
    }

    private function createViewForAtom(atom:Atom, id:String, x:Float, y:Float):Void {
        if (_nodes.exists(id)) return;
        var view = new NodeView(atom, id);
        view.setPosition(x, y);
        _canvas.addChild(view);
        _nodes.set(id, view);
    }

    public function refreshAssemblyViews():Void {
        var toRefresh:Array<{id:String, view:NodeView, asm:Assembly, index:Int}> = [];

        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            var atom = _assembly.internalAtoms.get(nodeId);

            if (atom != null && Std.isOfType(atom, Assembly)) {
                var asm = cast(atom, Assembly);
                var idx = _canvas.getChildIndex(view);
                toRefresh.push({id: nodeId, view: view, asm: asm, index: idx});
            }
        }

        for (item in toRefresh) {
            AtomRegistry.registerBlueprint(item.asm.blueprint.id, item.asm.blueprint);
            item.view.redraw();

            if (_canvas.contains(item.view)) {
                _canvas.setChildIndex(item.view, item.index);
            }
        }

        _wireRenderer.rebuildAll();
        updateVisibility();
    }

    public function createAtom(typeId:String, posX:Float, posY:Float):Atom {
        var bp = library.AtomRegistry.get(typeId);
        if (bp == null) return null;
        var localPoint = _canvas.globalToLocal(new Point(posX, posY));
        _actions.createAtom(typeId, localPoint.x, localPoint.y);
        return null;
    }

    // ========================================================================
    // SELECTION
    // ========================================================================

    public function deselectAll():Void {
        ECS.clearSelections();
        for (node in _selectedNodes) node.selected = false;
        _selectedNodes = new Map();

        if (_selectedWireIds.length > 0) {
            _selectedWireIds = [];
            _wireRenderer.rebuildAll();
        }
    }

    public function selectAll():Void {
        deselectAll();
        for (id in _nodes.keys()) {
            var view = _nodes.get(id);
            if (view != null) {
                view.selected = true;
                _selectedNodes.set(id, view);
            }
        }
    }

    public function isSelected(nodeId:String):Bool return _selectedNodes.exists(nodeId);

    public function selectNode(nodeId:String, view:NodeView):Void {
        view.selected = true;
        _selectedNodes.set(nodeId, view);
    }

    public function getSelectedNodeIds():Array<String> return [for (id in _selectedNodes.keys()) id];
    public function getSelectedNodeCount():Int { var c = 0; for (id in _selectedNodes.keys()) c++; return c; }
    public function getSelectedWireIds():Array<String> return _selectedWireIds.copy();

    // ========================================================================
    // LASSO
    // ========================================================================

    private function onCanvasMouseDown(e:MouseEvent):Void {
        deselectAll();
        _canvas.addChild(_lasso);

        _isLassoing = true;
        var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
        _lassoStartX = local.x;
        _lassoStartY = local.y;

        stage.addEventListener(MouseEvent.MOUSE_MOVE, onLassoMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onLassoUp);
    }

    private function onLassoMove(e:MouseEvent):Void {
        if (!_isLassoing) return;
        var local = _canvas.globalToLocal(new Point(e.stageX, e.stageY));

        var x = Math.min(_lassoStartX, local.x);
        var y = Math.min(_lassoStartY, local.y);
        var w = Math.abs(local.x - _lassoStartX);
        var h = Math.abs(local.y - _lassoStartY);

        _lasso.graphics.clear();
        _lasso.graphics.lineStyle(1, _theme.LASSO_BORDER_COLOR, 0.8);
        _lasso.graphics.beginFill(_theme.LASSO_FILL_COLOR, _theme.LASSO_FILL_ALPHA);
        _lasso.graphics.drawRect(x, y, w, h);
        _lasso.graphics.endFill();
    }

    private function onLassoUp(e:MouseEvent):Void {
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onLassoMove);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onLassoUp);
        if (!_isLassoing) return;
        _isLassoing = false;

        if (_lasso.width > 5 && _lasso.height > 5) {
            var lassoBounds:Rectangle = _lasso.getBounds(_canvas);
            var idsInRect = ECS.getInRect(lassoBounds.x, lassoBounds.y, lassoBounds.width, lassoBounds.height);

            for (id in idsInRect) {
                var view = _nodes.get(id);
                if (view != null && !_selectedNodes.exists(id)) {
                    view.selected = true;
                    _selectedNodes.set(id, view);
                }
            }
        }
        _lasso.graphics.clear();
    }
    
    // ========================================================================
    // CANVAS CONTEXT MENU (NEW)
    // ========================================================================

    private function onCanvasRightClick(e:MouseEvent):Void {
        e.stopPropagation();
        Impulsys.emit(new Impulse("CANVAS_RIGHT_CLICKED", {
            x: e.stageX,
            y: e.stageY
        }));
    }

    // ========================================================================
    // NODE CLICK
    // ========================================================================

    private function onNodeClicked(impulse:Impulse):Void {
        var view:NodeView = impulse.data.view;
        var ctrl:Bool = impulse.data.ctrlKey;

        _isLassoing = false;
        _lasso.graphics.clear();
        Impulsys.quickEmit("CLOSE_CONTEXT_MENU");

        var isAlreadySelected = _selectedNodes.exists(view.nodeId);

        if (ctrl) {
            if (isAlreadySelected) {
                view.selected = false;
                _selectedNodes.remove(view.nodeId);
            } else {
                view.selected = true;
                _selectedNodes.set(view.nodeId, view);
            }
        } else {
            if (!isAlreadySelected) {
                deselectAll();
                view.selected = true;
                _selectedNodes.set(view.nodeId, view);
            }
        }
    }

    // ========================================================================
    // NODE DRAG
    // ========================================================================

    private function onNodeMoved(impulse:Impulse):Void {
        var sourceView:NodeView = impulse.data.view;
        var dx:Float = impulse.data.dx;
        var dy:Float = impulse.data.dy;

        if (_draggingNode == null) {
            _draggingNode = sourceView;
            _dragStartPositions = new Map();

            var isMovingGroup = _selectedNodes.exists(sourceView.nodeId);
            var nodesToMove = isMovingGroup ? _selectedNodes : [sourceView.nodeId => sourceView];

            var movingNodeIds:Array<String> = [];
            for (id in nodesToMove.keys()) {
                var v = nodesToMove.get(id);
                _dragStartPositions.set(id, {x: v.x, y: v.y});
                movingNodeIds.push(id);
            }

            _wireRenderer.setActiveWiresForNodes(movingNodeIds);
        }

        if (_selectedNodes.exists(sourceView.nodeId)) {
            for (id in _selectedNodes.keys()) {
                if (id != sourceView.nodeId) {
                    var otherView = _selectedNodes.get(id);
                    otherView.setPosition(otherView.x + dx, otherView.y + dy);
                }
            }
        }

        _wireRenderer.updateActiveWires();
        _wireRenderer.updateEdgeWires();
    }

    private function onNodeDragFinished(impulse:Impulse):Void {
        var moves:Array<{id:String, fromX:Float, fromY:Float, toX:Float, toY:Float}> = [];

        if (_dragStartPositions != null) {
            for (id in _dragStartPositions.keys()) {
                var startPos = _dragStartPositions.get(id);
                var view = _nodes.get(id);
                if (view != null) {
                    var templateId = _assembly.getTemplateId(id);
                    moves.push({id: templateId, fromX: startPos.x, fromY: startPos.y, toX: view.x, toY: view.y});

                    for (atom in _blueprint.internalAtoms) {
                        if (atom.instanceId == templateId) {
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

        _wireRenderer.updateEdgeWires();
    }

    // ========================================================================
    // PORT CONNECTION DRAG
    // ========================================================================

    private function onPortDragStart(impulse:Impulse):Void {
        _isDraggingPort = true;
        _dragNodeId = impulse.data.nodeId;
        _dragContactName = impulse.data.contactName;
        _dragStartX = impulse.data.startX;
        _dragStartY = impulse.data.startY;
        _dragStartIsInput = impulse.data.isInput;
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_viewport.isPanning()) {
            _viewport.handlePanMove(e.stageX, e.stageY);
            _wireRenderer.updateEdgeWires();
            updateVisibility();
            return;
        }

        if (_isDraggingPort) {
            _wireRenderer.drawGhostWire(_dragStartX, _dragStartY, e.stageX, e.stageY, _dragStartIsInput);
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        if (_viewport.isPanning()) { 
            _viewport.handlePanEnd(); 
            _wireRenderer.rebuildAll();
            updateVisibility();
            return; 
        }

        if (_isDraggingPort) {
            var target = findPortAt(e.stageX, e.stageY);

            if (target != null) {
                var isSameContact = (_dragNodeId == target.nodeId && _dragContactName == target.contactName);
                var startIsSource = !_dragStartIsInput;
                var targetIsSource = !target.isInput;

                if (!isSameContact && (startIsSource != targetIsSource)) {
                    var realFromId:String; var realFromContact:String;
                    var realToId:String; var realToContact:String;

                    if (startIsSource) {
                        realFromId = _dragNodeId; realFromContact = _dragContactName;
                        realToId = target.nodeId; realToContact = target.contactName;
                    } else {
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
    }

    private function findPortAt(x:Float, y:Float):{nodeId:String, contactName:String, isInput:Bool} {
        for (name in _edgePorts.keys()) {
            var port = _edgePorts.get(name);
            var local = port.globalToLocal(new Point(x, y));
            if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) {
                var asmPort = _assembly.ports.get(name);
                var isInput:Bool;
                if (asmPort.type == INPUT) isInput = false; else isInput = true;
                return { nodeId: "SELF", contactName: name, isInput: isInput };
            }
        }

        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                for (name in view.inputPorts.keys()) {
                    var port = view.inputPorts.get(name);
                    if (port != null) {
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: true};
                    }
                }
                for (name in view.outputPorts.keys()) {
                    var port = view.outputPorts.get(name);
                    if (port != null) {
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) return {nodeId: nodeId, contactName: name, isInput: false};
                    }
                }
            }
        }
        return null;
    }

    // ========================================================================
    // PAN & ZOOM (Delegated)
    // ========================================================================

    private function onMiddleMouseDown(e:MouseEvent):Void {
        _viewport.handlePanStart(e.stageX, e.stageY);
    }

    private function onMiddleMouseUp(e:MouseEvent):Void {
        if (_viewport.isPanning()) {
            _viewport.handlePanEnd();
            _wireRenderer.rebuildAll();
            updateVisibility();
        }
    }

    private function onMouseWheel(e:MouseEvent):Void {
        _viewport.handleZoom(e.delta, e.stageX, e.stageY, this);
        
        // Отменяем предыдущий таймер если есть
        if (_zoomRebuildTimer != null) {
            _zoomRebuildTimer.stop();
        }
        
        // Планируем rebuild через 80ms после последнего скролла
        _zoomRebuildTimer = haxe.Timer.delay(() -> {
            _wireRenderer.rebuildAll();
            updateVisibility();
        }, 1);
    }

    // ========================================================================
    // DELETE (Delegated)
    // ========================================================================

    public function deleteAtom(id:String):Void {
        _actions.deleteAtoms([id]);
    }

    public function deleteSelectedNodes():Array<String> {
        var ids = getSelectedNodeIds();
        _actions.deleteAtoms(ids);
        return ids;
    }

    public function deleteWire(link:ConnectionDef):Void {
        _blueprint.internalConnections.remove(link);
        var cOut = resolveContact(link.from);
        var cIn = resolveContact(link.to);
        if (cOut != null && cIn != null) cOut.unlink(cIn);
    }

    public function deleteSelectedWires():Void {
        if (_selectedWireIds.length == 0) return;
        _actions.deleteWires(_selectedWireIds);
        _selectedWireIds = [];
        _wireRenderer.rebuildAll();
    }

    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var port = _assembly.ports.get(point.contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            var realAtomId = _assembly.idMap.get(point.atomId);
            if (realAtomId == null) realAtomId = point.atomId;

            var atom = _assembly.internalAtoms.get(realAtomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            var c = a.getInput(point.contactName);
            if (c == null) c = a.getOutput(point.contactName);
            return c;
        }
    }

    // ========================================================================
    // ATOM EVENTS
    // ========================================================================

    private function onAtomDeleted(impulse:Impulse):Void {
        if (impulse.data.assemblyId != _assembly.id) return;

        var id:String = impulse.data.id;
        var view = _nodes.get(id);
        if (view != null) {
            view.dispose();
            if (view.parent == _canvas) _canvas.removeChild(view);
            _nodes.remove(id);
            _selectedNodes.remove(id);
            _wireRenderer.rebuildAll();
        }
    }

    private function onAtomRestored(impulse:Impulse):Void {
        if (impulse.data.assemblyId != _assembly.id) return;

        var id:String = impulse.data.id;
        var x:Float = impulse.data.x;
        var y:Float = impulse.data.y;
        var atom:Atom = impulse.data.atom;
        if (atom != null) {
            createViewForAtom(atom, id, x, y);
            _wireRenderer.rebuildAll();
        }
    }

    private function onForceUpdatePosition(impulse:Impulse):Void {
        var data = impulse.data;
        var view = _nodes.get(data.id);
        if (view != null) {
            if (view.x != data.x || view.y != data.y) {
                view.setPosition(data.x, data.y);
                _wireRenderer.rebuildAll();
            }
        }
    }

    // ========================================================================
    // CLIPBOARD (Delegated)
    // ========================================================================

    public function copySelection():Void {
        _actions.copySelection(getSelectedNodeIds());
    }

    public function cutSelection():Void {
        _actions.cutSelection(getSelectedNodeIds());
    }

    public function pasteSelection():Void {
        var idMap = _actions.pasteSelection(25.0);
        if (idMap != null) {
            deselectAll();
            for (newId in idMap) {
                var view = _nodes.get(newId);
                if (view != null) {
                    view.selected = true;
                    _selectedNodes.set(newId, view);
                }
            }
            trace('Pasted items');
        }
    }

    // ========================================================================
    // PROPERTIES
    // ========================================================================

    public function setUseEcsRender(value:Bool):Void { _useEcsRender = value; }
    public function getUseEcsRender():Bool { return _useEcsRender; }

    public function setWireType(type:WireTypeEnum):Void { _wireRenderer.wireType = type; }
    public function getWireType():WireTypeEnum { return _wireRenderer.wireType; }

    public function setAllowAssembly(value:Bool):Void { _allowAssembly = value; }
    public function getAllowAssembly():Bool { return _allowAssembly; }

    public function getNodeCount():Int { var c = 0; for (id in _nodes.keys()) c++; return c; }
    public function getWireCount():Int { return _wireRenderer.getWireCount(); }

    public function getNodePositions():Array<{id:String, x:Float, y:Float}> {
        var positions = [];
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) positions.push({id: nodeId, x: view.x, y: view.y});
        }
        return positions;
    }

    public function getSelectedNodeIdsFromECS():Array<String> { return ECS.getSelected(); }

    // ========================================================================
    // DISPOSAL
    // ========================================================================

    public function dispose():Void {
        if (stage != null) {
            stage.removeEventListener(Event.RESIZE, onResize);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
        }

        Impulsys.removeImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.removeImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.removeImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.removeImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.removeImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.removeImpulse("ASSEMBLY_PORTS_CHANGED", _cbPortsChanged);
        Impulsys.removeImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.removeImpulse("ATOM_RESTORED", onAtomRestored);
        Impulsys.removeImpulse("NODE_CLICKED", onNodeClicked);

        _bgHitArea.removeEventListener(MouseEvent.MOUSE_DOWN, onCanvasMouseDown);
        _bgHitArea.removeEventListener(MouseEvent.RIGHT_CLICK, onCanvasRightClick); // Cleanup

        _wireRenderer.dispose();

        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                view.dispose();
                if (view.parent != null) view.parent.removeChild(view);
            }
        }

        for (nodeId in _nodes.keys()) {
            ECS.unregister(nodeId);
        }
        _nodes.clear();
    }
}