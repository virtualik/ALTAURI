package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.Impulse;
import system.managers.UndoManager;
import system.commands.editor.MoveNodeCommand;
import system.commands.editor.ConnectCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.editor.CreateAtomCommand;

/**
 * Node Editor
 * Main visual container for nodes and wires.
 */
class NodeEditor extends Sprite {

    private var _assembly:Assembly;
    private var _blueprint:core.data.Blueprint;
    private var _nodes:Map<String, NodeView> = new Map();
    private var _spawnCounter:Int = 0;

    private var _isDraggingPort:Bool = false;
    private var _dragNodeId:String;
    private var _dragContactName:String;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _dragStartIsInput:Bool = false;

    private var _wireLayer:Sprite;
    private var _ghostWire:Sprite;

    private var _cbRedraw:Impulse -> Void;

    public function new(assembly:Assembly) {
        super();
        this._assembly = assembly;
        this._blueprint = assembly.blueprint;

        _wireLayer = new Sprite();
        _wireLayer.mouseEnabled = false;
        addChild(_wireLayer);

        var selfView = new NodeView(null, "SELF", assembly);
        selfView.x = 150;
        selfView.y = 50;
        addChild(selfView);
        _nodes.set("SELF", selfView);

        restoreExistingAtoms();

        _ghostWire = new Sprite();
        _ghostWire.mouseEnabled = false;
        _ghostWire.mouseChildren = false;
        addChild(_ghostWire);

        _cbRedraw = function(_) drawWires();

        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.subscribeToImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.subscribeToImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.subscribeToImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.subscribeToImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.subscribeToImpulse("ATOM_RESTORED", onAtomRestored);

        if (stage != null) initListeners();
        else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

        drawWires();
    }

    public function dispose():Void {
        Impulsys.removeImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.removeImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.removeImpulse("NODE_DRAG_FINISHED", onNodeDragFinished);
        Impulsys.removeImpulse("FORCE_UPDATE_NODE_POSITION", onForceUpdatePosition);
        Impulsys.removeImpulse("REDRAW_WIRES", _cbRedraw);
        Impulsys.removeImpulse("ATOM_DELETED", onAtomDeleted);
        Impulsys.removeImpulse("ATOM_RESTORED", onAtomRestored);

        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                view.dispose();
                removeChild(view);
            }
        }
        _nodes.clear();

        if (_wireLayer != null) _wireLayer.graphics.clear();
        if (_ghostWire != null) _ghostWire.graphics.clear();

        _assembly = null;
        _blueprint = null;
        _cbRedraw = null;
    }

    public function deleteAtom(id:String):Void {
        var cmd = new DeleteAtomCommand(_blueprint, _assembly, id);
        UndoManager.getInstance().executeAndStore(cmd);
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
        addChild(view);
        _nodes.set(id, view);
    }

    private function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        initListeners();
    }

    private function initListeners():Void {
        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    public function getNodePositions():Array<{id:String, x:Float, y:Float}> {
        var positions = [];
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                positions.push({id: nodeId, x: view.x, y: view.y});
            }
        }
        return positions;
    }

    public function createAtom(typeId:String, posX:Float, posY:Float):Atom {
        var bp = library.AtomRegistry.get(typeId);
        if (bp == null) return null;

        var instanceId = typeId + "_" + (_spawnCounter++);

        var cmd = new CreateAtomCommand(_blueprint, _assembly, typeId, instanceId, posX, posY);
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
        if (_isDraggingPort) {
            drawGhostWire(_dragStartX, _dragStartY, e.stageX, e.stageY, _dragStartIsInput);
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        if (_isDraggingPort) {
            var target = findPortAt(e.stageX, e.stageY);

            if (target != null && _dragNodeId != target.nodeId && _dragStartIsInput != target.isInput) {
                var fromId = _dragNodeId;
                var fromContact = _dragContactName;
                var toId = target.nodeId;
                var toContact = target.contactName;

                var realFromId = _dragStartIsInput ? toId : fromId;
                var realFromContact = _dragStartIsInput ? toContact : fromContact;
                var realToId = _dragStartIsInput ? fromId : toId;
                var realToContact = _dragStartIsInput ? fromContact : toContact;

                var cmd = new ConnectCommand(
                    _blueprint, _assembly,
                    realFromId, realFromContact,
                    realToId, realToContact
                );
                UndoManager.getInstance().executeAndStore(cmd);
            }

            _isDraggingPort = false;
            _ghostWire.graphics.clear();
            drawWires();
        }
    }

    private function onAtomDeleted(impulse:Impulse):Void {
        var id:String = impulse.data.id;
        var view = _nodes.get(id);
        if (view != null) {
            view.dispose();
            removeChild(view);
            _nodes.remove(id);
            drawWires();
        }
    }

    private function onAtomRestored(impulse:Impulse):Void {
        var id:String = impulse.data.id;
        var x:Float = impulse.data.x;
        var y:Float = impulse.data.y;
        var atom:Atom = impulse.data.atom;

        if (atom != null) {
            createViewForAtom(atom, id, x, y);
            drawWires();
        }
    }

    private function onNodeDragFinished(impulse:Impulse):Void {
        var data = impulse.data;

        var cmd = new MoveNodeCommand(
            _blueprint,
            data.id,
            data.startX,
            data.startY,
            data.endX,
            data.endY
        );

        UndoManager.getInstance().storeExecuted(cmd);

        for (atom in _blueprint.internalAtoms) {
            if (atom.instanceId == data.id) {
                atom.x = data.endX;
                atom.y = data.endY;
                break;
            }
        }
    }

    private function onForceUpdatePosition(impulse:Impulse):Void {
        var data = impulse.data;
        var view = _nodes.get(data.id);
        if (view != null) {
            if (view.x != data.x || view.y != data.y) {
                view.x = data.x;
                view.y = data.y;
                drawWires();
            }
        }
    }

    private function onNodeMoved(impulse:Impulse):Void {
        drawWires();
    }

    private function findPortAt(x:Float, y:Float):{nodeId:String, contactName:String, isInput:Bool} {
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                for (name in view.inputPorts.keys()) {
                    var port = view.inputPorts.get(name);
                    if (port != null) {
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) {
                            return {nodeId: nodeId, contactName: name, isInput: true};
                        }
                    }
                }
                for (name in view.outputPorts.keys()) {
                    var port = view.outputPorts.get(name);
                    if (port != null) {
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) {
                            return {nodeId: nodeId, contactName: name, isInput: false};
                        }
                    }
                }
            }
        }
        return null;
    }

    private function drawGhostWire(startX:Float, startY:Float, endX:Float, endY:Float, isInput:Bool):Void {
        var g = _ghostWire.graphics;
        g.clear();
        g.lineStyle(3, 0x00FF00, 0.8);
        g.moveTo(startX, startY);
        var dx = Math.abs(endX - startX) * 0.5;
        if (dx < 50) dx = 50;

        if (isInput) g.cubicCurveTo(startX - dx, startY, endX + dx, endY, endX, endY);
        else g.cubicCurveTo(startX + dx, startY, endX - dx, endY, endX, endY);
    }

    private function drawWires():Void {
        if (_blueprint == null || _wireLayer == null) return;

        var g = _wireLayer.graphics;
        g.clear();
        g.lineStyle(2, 0x666666);

        for (link in _blueprint.internalConnections) {
            var fromView = _nodes.get(link.from.atomId);
            var toView = _nodes.get(link.to.atomId);

            if (fromView != null && toView != null) {
                var p1 = fromView.getPortPosition(link.from.contactName);
                var p2 = toView.getPortPosition(link.to.contactName);

                if (p1 == null || p2 == null) continue;

                g.moveTo(p1.x, p1.y);

                var isFromInput = fromView.inputPorts.exists(link.from.contactName);
                var isToInput = toView.inputPorts.exists(link.to.contactName);

                var dist = Math.abs(p2.x - p1.x);
                var tension = dist * 0.5;
                if (tension < 50) tension = 50;

                var c1x = p1.x + (isFromInput ? -tension : tension);
                var c2x = p2.x + (isToInput ? -tension : tension);

                g.cubicCurveTo(c1x, p1.y, c2x, p2.y, p2.x, p2.y);
            }
        }
    }
}