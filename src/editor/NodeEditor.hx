package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.Impulse;
import system.managers.UndoManager;
import system.commands.editor.MoveNodeCommand;
import system.commands.editor.ConnectCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.editor.CreateAtomCommand;
import system.commands.base.MacroCommand;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;

class NodeEditor extends Sprite {

    private var _assembly:Assembly;
    private var _blueprint:core.data.Blueprint;
    private var _nodes:Map<String, NodeView> = new Map();
    
    private var _canvas:Sprite; 
    
    private var _wireContainer:Sprite; 
    private var _wireSprites:Map<String, Sprite>; 
    private var _activeWires:Array<Sprite>; 
    
    private var _selectedNodes:Map<String, NodeView> = new Map();
    private var _selectedWireId:String = null;
    
    private var _frame:Sprite;
    private var _edgePortsContainer:Sprite;
    private var _edgePorts:Map<String, Sprite> = new Map();
    private var _fileNameField:TextField;
    
    private var _lasso:Sprite;
    private var _isLassoing:Bool = false;
    private var _lassoStartX:Float = 0;
    private var _lassoStartY:Float = 0;
    
    private var _dragStartPositions:Map<String, {x:Float, y:Float}>;
    
    private var _spawnCounter:Int = 0;

    private var _isDraggingPort:Bool = false;
    private var _dragNodeId:String;
    private var _dragContactName:String;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _dragStartIsInput:Bool = false;

    private var _ghostWire:Sprite;
    
    private var _draggingNode:NodeView = null;

    private var _isPanning:Bool = false;
    private var _panStartX:Float = 0;
    private var _panStartY:Float = 0;
    private var _canvasStartX:Float = 0;
    private var _canvasStartY:Float = 0;

    private var _cbRedraw:Impulse -> Void;

    public function new(assembly:Assembly) {
        super();
        this._assembly = assembly;
        this._blueprint = assembly.blueprint;

        _canvas = new Sprite();
        _canvas.graphics.beginFill(0x333333, 1);
        _canvas.graphics.drawRect(-5000, -5000, 10000, 10000);
        _canvas.graphics.endFill();
        addChild(_canvas);
        
        _canvas.addEventListener(MouseEvent.MOUSE_DOWN, onCanvasMouseDown);

        _wireContainer = new Sprite();
        _wireContainer.mouseEnabled = false;
        _canvas.addChild(_wireContainer);

        _wireSprites = new Map();
        _activeWires = [];

        restoreExistingAtoms();

        _ghostWire = new Sprite();
        _ghostWire.mouseEnabled = false;
        _canvas.addChild(_ghostWire);

        _lasso = new Sprite();
        _lasso.mouseEnabled = false;
        _canvas.addChild(_lasso);

        _frame = new Sprite();
        _frame.mouseEnabled = false;
        addChild(_frame);
        
        _edgePortsContainer = new Sprite();
        _edgePortsContainer.mouseEnabled = true; 
        addChild(_edgePortsContainer);
        
        _fileNameField = new TextField();
        _fileNameField.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF);
        _fileNameField.text = _blueprint.name;
        _fileNameField.autoSize = RIGHT;
        _fileNameField.mouseEnabled = false;
        addChild(_fileNameField);

        drawFrame();
        
        addEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);

        _cbRedraw = function(_) rebuildAllWires();

        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.subscribeToImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.subscribeToImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.subscribeToImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.subscribeToImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.subscribeToImpulse("ATOM_RESTORED", onAtomRestored);
        Impulsys.subscribeToImpulse("NODE_CLICKED", onNodeClicked);

        if (stage != null) {
            initListeners();
            drawFrame();
        }
        else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

        rebuildAllWires();
    }
    
    private function drawFrame(e:Event = null):Void {
        if (stage == null) return;

        var w:Float = stage.stageWidth;
        var h:Float = stage.stageHeight;
        var borderColor:Int = 0x00AAFF;

        _frame.graphics.clear();
        _frame.graphics.lineStyle(2, borderColor);
        _frame.graphics.drawRect(0, 0, w, h);

        _fileNameField.x = w - 10 - _fileNameField.width;
        _fileNameField.y = h - 20;

        _edgePortsContainer.removeChildren();
        _edgePorts = new Map();

        var leftIdx:Int = 0;
        var rightIdx:Int = 0;
        
        var leftCount:Int = 0;
        var rightCount:Int = 0;
        
        for (p in _assembly.ports) {
            if (p.type == INPUT) leftCount++; 
            else rightCount++;
        }

        var leftStep:Float = h / (leftCount + 1);
        var rightStep:Float = h / (rightCount + 1);

        for (p in _assembly.ports) {
            var c:Contact = p.internal;
            var portView:Sprite;

            if (p.type == INPUT) {
                portView = createEdgePort(c, false, p.name); 
                portView.x = 0; 
                portView.y = leftStep * (leftIdx + 1);
                leftIdx++;
            } else {
                portView = createEdgePort(c, true, p.name);
                portView.x = w; 
                portView.y = rightStep * (rightIdx + 1);
                rightIdx++;
            }

            _edgePortsContainer.addChild(portView);
            _edgePorts.set(p.name, portView);
        }

        updateEdgeWires();
    }
    
    private function createEdgePort(contact:Contact, isInput:Bool, portName:String):Sprite {
        var s = new Sprite();
        s.graphics.beginFill(isInput ? 0xFF8800 : 0x00FF88);
        s.graphics.lineStyle(1, 0xFFFFFF);
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

        return s;
    }
    
    private function updateEdgeWires():Void {
        if (_blueprint.internalConnections == null) return;
        
        for (link in _blueprint.internalConnections) {
            if (link.from.atomId == "SELF" || link.to.atomId == "SELF") {
                var wireID = getWireID(link);
                var spr = _wireSprites.get(wireID);
                if (spr != null) drawWireGraphics(spr.graphics, link);
            }
        }
    }

    public function getViewState():{x:Float, y:Float, zoom:Float} {
        return { x: _canvas.x, y: _canvas.y, zoom: _canvas.scaleX };
    }

    public function setViewState(state:{x:Float, y:Float, zoom:Float}):Void {
        if (state == null) return;
        _canvas.x = state.x;
        _canvas.y = state.y;
        var z = state.zoom;
        if (z < 0.1) z = 0.1;
        if (z > 5.0) z = 5.0;
        _canvas.scaleX = z;
        _canvas.scaleY = z;
        updateVisibility();
    }
    
    private function onCanvasMouseDown(e:MouseEvent):Void {
        deselectAll();
        
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
        _lasso.graphics.lineStyle(1, 0xFFFFFF, 0.8);
        _lasso.graphics.beginFill(0x00AAFF, 0.2);
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
            for (id in _nodes.keys()) {
                var view = _nodes.get(id);
                if (view != null) {
                    var nodeBounds:Rectangle = view.getBounds(_canvas);
                    if (lassoBounds.intersects(nodeBounds)) {
                        if (!_selectedNodes.exists(id)) {
                            view.selected = true;
                            _selectedNodes.set(id, view);
                        }
                    }
                }
            }
        }
        _lasso.graphics.clear();
    }
    
    private function onNodeClicked(impulse:Impulse):Void {
        var view:NodeView = impulse.data.view;
        var ctrl:Bool = impulse.data.ctrlKey;
        
        _isLassoing = false;
        _lasso.graphics.clear();
        Impulsys.quickEmit("CLOSE_CONTEXT_MENU");

        if (ctrl) {
            if (_selectedNodes.exists(view.nodeId)) {
                view.selected = false;
                _selectedNodes.remove(view.nodeId);
            } else {
                view.selected = true;
                _selectedNodes.set(view.nodeId, view);
            }
        } else {
            if (!_selectedNodes.exists(view.nodeId)) {
                deselectAll();
                view.selected = true;
                _selectedNodes.set(view.nodeId, view);
            }
        }
    }
    
    public function deselectAll():Void {
        for (node in _selectedNodes) node.selected = false;
        _selectedNodes = new Map();
        if (_selectedWireId != null) { 
            _selectedWireId = null;
            rebuildAllWires(); 
        }
    }
    
    private function clearAllWires():Void {
        for (key in _wireSprites.keys()) {
            var spr = _wireSprites.get(key);
            spr.graphics.clear();
            if(spr.parent != null) spr.parent.removeChild(spr);
        }
        _wireSprites = new Map();
    }

    private function getWireID(link:ConnectionDef):String {
        return '${link.from.atomId}_${link.from.contactName}->${link.to.atomId}_${link.to.contactName}';
    }

    private function rebuildAllWires():Void {
        clearAllWires();
        if (_blueprint.internalConnections == null) return;
        for (link in _blueprint.internalConnections) createWireSprite(link);
    }

    private function createWireSprite(link:ConnectionDef):Sprite {
        var spr = new Sprite();
        spr.mouseEnabled = true;
        spr.buttonMode = true;
        
        var color = 0x666666;
        var thickness = 2.0;
        var id = getWireID(link);
        
        if (id == _selectedWireId) {
            color = 0xFFCC00;
            thickness = 4;
        }
        
        drawWireGraphics(spr.graphics, link, color, thickness);
        
        spr.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
            e.stopPropagation();
            
            if (_selectedWireId == id) {
                deleteWire(link);
            } else {
                _selectedWireId = id;
                rebuildAllWires();
            }
        });

        if (link.from.atomId != "SELF" && link.to.atomId != "SELF") {
             spr.cacheAsBitmap = true;
        }
        _wireContainer.addChild(spr);
        _wireSprites.set(id, spr);
        return spr;
    }
    
    public function deleteWire(link:ConnectionDef):Void {
        _blueprint.internalConnections.remove(link);
        var cOut = resolveContact(link.from);
        var cIn = resolveContact(link.to);
        if (cOut != null && cIn != null) cOut.unlink(cIn);
        _selectedWireId = null;
        rebuildAllWires();
    }
    
    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") {
            var port = _assembly.ports.get(point.contactName);
            return (port != null) ? port.internal : null;
        } else {
            var atom = _assembly.internalAtoms.get(point.atomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            var c = a.getInput(point.contactName);
            if (c == null) c = a.getOutput(point.contactName);
            return c;
        }
    }

    private function drawWireGraphics(g:openfl.display.Graphics, link:ConnectionDef, ?color:Int = 0x666666, ?thickness:Float = 2):Void {
        var p1:{x:Float, y:Float} = null;
        var isFromInput = false;

        if (link.from.atomId == "SELF") {
            var portSpr = _edgePorts.get(link.from.contactName);
            if (portSpr == null) return;
            var pt = _canvas.globalToLocal(portSpr.localToGlobal(new Point(0, 0)));
            p1 = {x: pt.x, y: pt.y};
            isFromInput = (portSpr.x != 0); 
        } else {
            var fromView = _nodes.get(link.from.atomId);
            if (fromView == null) return;
            p1 = fromView.getPortPosition(link.from.contactName);
            isFromInput = fromView.inputPorts.exists(link.from.contactName);
        }

        var p2:{x:Float, y:Float} = null;
        var isToInput = false;

        if (link.to.atomId == "SELF") {
            var portSpr = _edgePorts.get(link.to.contactName);
            if (portSpr == null) return;
            var pt = _canvas.globalToLocal(portSpr.localToGlobal(new Point(0, 0)));
            p2 = {x: pt.x, y: pt.y};
            isToInput = (portSpr.x != 0);
        } else {
            var toView = _nodes.get(link.to.atomId);
            if (toView == null) return;
            p2 = toView.getPortPosition(link.to.contactName);
            isToInput = toView.inputPorts.exists(link.to.contactName);
        }

        g.clear();
        g.lineStyle(thickness, color);
        g.moveTo(p1.x, p1.y);

        var dist = Math.abs(p2.x - p1.x);
        var tension = dist * 0.5;
        if (tension < 50) tension = 50;

        var c1x = p1.x + (isFromInput ? -tension : tension);
        var c2x = p2.x + (isToInput ? -tension : tension);

        g.cubicCurveTo(c1x, p1.y, c2x, p2.y, p2.x, p2.y);
    }

    private function onNodeMoved(impulse:Impulse):Void {
        var sourceView:NodeView = impulse.data.view;
        var dx:Float = impulse.data.dx;
        var dy:Float = impulse.data.dy;

        if (_draggingNode == null) {
            _draggingNode = sourceView;
            _dragStartPositions = new Map();
            var isMovingGroup = _selectedNodes.exists(sourceView.nodeId);
            var nodesToMove = isMovingGroup ? _selectedNodes : [sourceView.nodeId => sourceView];

            for (id in nodesToMove.keys()) {
                var v = nodesToMove.get(id);
                _dragStartPositions.set(id, {x: v.x, y: v.y});
                for (link in _blueprint.internalConnections) {
                    if (link.from.atomId == id || link.to.atomId == id) {
                        var wireID = getWireID(link);
                        var spr = _wireSprites.get(wireID);
                        if (spr != null) {
                            spr.cacheAsBitmap = false;
                            if (_activeWires.indexOf(spr) == -1) _activeWires.push(spr);
                        }
                    }
                }
            }
        }

        if (_selectedNodes.exists(sourceView.nodeId)) {
            for (id in _selectedNodes.keys()) {
                if (id != sourceView.nodeId) {
                    var otherView = _selectedNodes.get(id);
                    otherView.x += dx;
                    otherView.y += dy;
                }
            }
        }
        updateActiveWires();
        updateEdgeWires();
    }

    private function onNodeDragFinished(impulse:Impulse):Void {
        var groupCommand = new MacroCommand();
        var hasChanges:Bool = false;

        if (_dragStartPositions != null) {
            for (id in _dragStartPositions.keys()) {
                var startPos = _dragStartPositions.get(id);
                var view = _nodes.get(id);
                if (view != null) {
                    groupCommand.addCommand(new MoveNodeCommand(_blueprint, id, startPos.x, startPos.y, view.x, view.y));
                    hasChanges = true;
                    for (atom in _blueprint.internalAtoms) {
                        if (atom.instanceId == id) { atom.x = view.x; atom.y = view.y; break; }
                    }
                }
            }
        }
        if (hasChanges) UndoManager.getInstance().storeExecuted(groupCommand);

        for (spr in _activeWires) {
             var wireId:String = null;
             for (k in _wireSprites.keys()) {
                 if (_wireSprites.get(k) == spr) {
                     wireId = k;
                     break;
                 }
             }
             
             if (wireId != null && wireId.indexOf("SELF") == -1) {
                 spr.cacheAsBitmap = true;
             }
        }
        _activeWires = [];
        _draggingNode = null;
        _dragStartPositions = null;
        
        updateEdgeWires();
    }

    private function updateActiveWires():Void {
        if (_activeWires.length == 0) return;
        for (link in _blueprint.internalConnections) {
             var id = getWireID(link);
             var spr = _wireSprites.get(id);
             if (spr != null && _activeWires.indexOf(spr) != -1) drawWireGraphics(spr.graphics, link);
        }
    }

    private function updateVisibility():Void {
        if (stage == null) return;
        
        var margin:Float = 150; 
        var viewLeft:Float = (-_canvas.x / _canvas.scaleX) - margin;
        var viewTop:Float = (-_canvas.y / _canvas.scaleY) - margin;
        var viewRight:Float = viewLeft + (stage.stageWidth / _canvas.scaleX) + (margin * 2);
        var viewBottom:Float = viewTop + (stage.stageHeight / _canvas.scaleY) + (margin * 2);

        for (id in _nodes.keys()) {
            var view = _nodes.get(id);
            if (view == null) continue;
            var isVisible = (view.x > viewLeft && view.x < viewRight && view.y > viewTop && view.y < viewBottom);
            if (view.visible != isVisible) view.visible = isVisible;
        }

        for (link in _blueprint.internalConnections) {
            var wireID = getWireID(link);
            var spr = _wireSprites.get(wireID);
            if (spr == null) continue;
            
            if (link.from.atomId == "SELF" || link.to.atomId == "SELF") {
                spr.visible = true;
                continue;
            }

            var fromView = _nodes.get(link.from.atomId);
            var toView = _nodes.get(link.to.atomId);
            var fromVisible = (fromView != null && fromView.visible);
            var toVisible = (toView != null && toView.visible);
            var wireVisible = (fromVisible || toVisible);
            if (spr.visible != wireVisible) spr.visible = wireVisible;
        }
    }

    private function onForceUpdatePosition(impulse:Impulse):Void {
        var data = impulse.data;
        var view = _nodes.get(data.id);
        if (view != null) {
            if (view.x != data.x || view.y != data.y) {
                view.x = data.x;
                view.y = data.y;
                rebuildAllWires();
            }
        }
    }

    private function restoreExistingAtoms():Void {
        if (_blueprint.internalAtoms == null) return;
        for (atomDef in _blueprint.internalAtoms) {
            var atomInstance = _assembly.internalAtoms.get(atomDef.instanceId);
            if (atomInstance != null) {
                createViewForAtom(cast atomInstance, atomDef.instanceId, atomDef.x, atomDef.y);
                var parts = atomDef.instanceId.split("_");
                var num = Std.parseInt(parts[parts.length-1]);
                if (num != null && num >= _spawnCounter) _spawnCounter = num + 1;
            }
        }
    }

    private function createViewForAtom(atom:Atom, id:String, x:Float, y:Float):Void {
        if (_nodes.exists(id)) return;
        var view = new NodeView(atom, id);
        view.x = x;
        view.y = y;
        _canvas.addChild(view);
        _nodes.set(id, view);
    }

    private function onAddedToStage_Frame(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage_Frame);
        stage.addEventListener(Event.RESIZE, drawFrame);
        drawFrame();
    }

    private function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        initListeners();
    }

    private function initListeners():Void {
        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
        stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
        stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
    }
    
    private function onMiddleMouseDown(e:MouseEvent):Void {
        _isPanning = true;
        _panStartX = e.stageX;
        _panStartY = e.stageY;
        _canvasStartX = _canvas.x;
        _canvasStartY = _canvas.y;
    }

    private function onMiddleMouseUp(e:MouseEvent):Void {
        if (_isPanning) {
            _isPanning = false;
            updateEdgeWires();
            updateVisibility();
        }
    }
    
    // --- ВОССТАНОВЛЕННЫЙ МЕТОД ---
    private function onMouseWheel(e:MouseEvent):Void {
        var zoomFactor:Float = 1.1;
        if (e.delta < 0) zoomFactor = 1 / 1.1;
        var mouseLocal:Point = _canvas.globalToLocal(new Point(e.stageX, e.stageY));
        var oldScale:Float = _canvas.scaleX;
        var newScale:Float = oldScale * zoomFactor;
        if (newScale < 0.1) newScale = 0.1;
        if (newScale > 5.0) newScale = 5.0;
        if (newScale == oldScale) return;

        _canvas.scaleX = newScale;
        _canvas.scaleY = newScale;
        _canvas.x = e.stageX - (mouseLocal.x * newScale);
        _canvas.y = e.stageY - (mouseLocal.y * newScale);
        
        updateEdgeWires();
        updateVisibility();
    }
    // ------------------------------

    public function getNodePositions():Array<{id:String, x:Float, y:Float}> {
        var positions = [];
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) positions.push({id: nodeId, x: view.x, y: view.y});
        }
        return positions;
    }

    public function createAtom(typeId:String, posX:Float, posY:Float):Atom {
        var bp = library.AtomRegistry.get(typeId);
        if (bp == null) return null;
        var localPoint = _canvas.globalToLocal(new Point(posX, posY));
        var instanceId = typeId + "_" + (_spawnCounter++);
        var cmd = new CreateAtomCommand(_blueprint, _assembly, typeId, instanceId, localPoint.x, localPoint.y);
        UndoManager.getInstance().executeAndStore(cmd);
        return _assembly.internalAtoms.get(instanceId);
    }

    private function onPortDragStart(impulse:Impulse):Void {
        _isDraggingPort = true;
        _dragNodeId = impulse.data.nodeId;
        _dragContactName = impulse.data.contactName;
        _dragStartX = impulse.data.startX;
        _dragStartY = impulse.data.startY;
        _dragStartIsInput = impulse.data.isInput;
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_isPanning) {
            var dx = e.stageX - _panStartX;
            var dy = e.stageY - _panStartY;
            _canvas.x = _canvasStartX + dx;
            _canvas.y = _canvasStartY + dy;
            updateEdgeWires();
            return;
        }

        if (_isDraggingPort) {
            drawGhostWire(_dragStartX, _dragStartY, e.stageX, e.stageY, _dragStartIsInput);
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        if (_isPanning) {
            _isPanning = false;
            return;
        }

        if (_isDraggingPort) {
            var target = findPortAt(e.stageX, e.stageY);
            
            if (target != null) {
                var isSameContact = (_dragNodeId == target.nodeId && _dragContactName == target.contactName);
                var startIsSource = !_dragStartIsInput;
                var targetIsSource = !target.isInput;

                if (!isSameContact && (startIsSource != targetIsSource)) {
                    
                    var realFromId:String;
                    var realFromContact:String;
                    var realToId:String;
                    var realToContact:String;

                    if (startIsSource) {
                        realFromId = _dragNodeId;
                        realFromContact = _dragContactName;
                        realToId = target.nodeId;
                        realToContact = target.contactName;
                    } else {
                        realFromId = target.nodeId;
                        realFromContact = target.contactName;
                        realToId = _dragNodeId;
                        realToContact = _dragContactName;
                    }

                    var cmd = new ConnectCommand(_blueprint, _assembly, realFromId, realFromContact, realToId, realToContact);
                    UndoManager.getInstance().executeAndStore(cmd);
                    rebuildAllWires();
                }
            }
            _isDraggingPort = false;
            _ghostWire.graphics.clear();
        }
    }
    
    private function onAtomDeleted(impulse:Impulse):Void {
        var id:String = impulse.data.id;
        var view = _nodes.get(id);
        if (view != null) {
            view.dispose();
            if (view.parent == _canvas) _canvas.removeChild(view);
            _nodes.remove(id);
            _selectedNodes.remove(id);
            rebuildAllWires();
        }
    }

    private function onAtomRestored(impulse:Impulse):Void {
        var id:String = impulse.data.id;
        var x:Float = impulse.data.x;
        var y:Float = impulse.data.y;
        var atom:Atom = impulse.data.atom;
        if (atom != null) {
            createViewForAtom(atom, id, x, y);
            rebuildAllWires();
        }
    }
    
    private function findPortAt(x:Float, y:Float):{nodeId:String, contactName:String, isInput:Bool} {
        for (name in _edgePorts.keys()) {
            var port = _edgePorts.get(name);
            var local = port.globalToLocal(new Point(x, y));
            if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) {
                var asmPort = _assembly.ports.get(name);
                var isInput:Bool;
                if (asmPort.type == INPUT) isInput = false; 
                else isInput = true;
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

    private function drawGhostWire(startX:Float, startY:Float, endX:Float, endY:Float, isInput:Bool):Void {
        var g = _ghostWire.graphics;
        g.clear();
        
        var p1 = _canvas.globalToLocal(new Point(startX, startY));
        var p2 = _canvas.globalToLocal(new Point(endX, endY));

        g.lineStyle(3, 0x00FF00, 0.8);
        g.moveTo(p1.x, p1.y);
        
        var dx = Math.abs(p2.x - p1.x) * 0.5;
        if (dx < 50) dx = 50;
        
        if (isInput) g.cubicCurveTo(p1.x - dx, p1.y, p2.x + dx, p2.y, p2.x, p2.y);
        else g.cubicCurveTo(p1.x + dx, p1.y, p2.x - dx, p2.y, p2.x, p2.y);
    }
    
    public function deleteAtom(id:String):Void {
        var cmd = new DeleteAtomCommand(_blueprint, _assembly, id);
        UndoManager.getInstance().executeAndStore(cmd);
    }
    
    public function getSelectedNodeIds():Array<String> {
        return [for (id in _selectedNodes.keys()) id];
    }
    
    public function dispose():Void {
        Impulsys.removeImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.removeImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.removeImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.removeImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.removeImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.removeImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.removeImpulse("ATOM_RESTORED", onAtomRestored);
        Impulsys.removeImpulse("NODE_CLICKED", onNodeClicked);
        
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onLassoMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onLassoUp);
            stage.removeEventListener(Event.RESIZE, drawFrame);
        }
        
        _canvas.removeEventListener(MouseEvent.MOUSE_DOWN, onCanvasMouseDown);
        clearAllWires();
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                view.dispose();
                if (view.parent != null) view.parent.removeChild(view);
            }
        }
        _nodes.clear();
    }
}