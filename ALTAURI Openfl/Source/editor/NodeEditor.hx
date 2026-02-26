package editor;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.Assembly;
import core.Atom;
import core.Contact;
import core.ContactType;
import core.Impulsys;
import core.Impulse;

class NodeEditor extends Sprite {

    private var _assembly:Assembly;
    private var _blueprint:core.Blueprint;
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

    public function new(assembly:Assembly) {
        super();
        this._assembly = assembly;
        this._blueprint = assembly.blueprint;

        // 1. Слой постоянных проводов
        _wireLayer = new Sprite();
        _wireLayer.mouseEnabled = false;
        addChild(_wireLayer);

        // 2. Узлы
        var selfView = new NodeView(null, "SELF", assembly);
        selfView.x = 150;
        selfView.y = 50;
        addChild(selfView);
        _nodes.set("SELF", selfView);

        restoreExistingAtoms();

        // 3. Слой временной линии
        _ghostWire = new Sprite();
        _ghostWire.mouseEnabled = false;
        _ghostWire.mouseChildren = false;
        addChild(_ghostWire);

        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);

        if (stage != null) initListeners();
        else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

        drawWires();
    }

    // --- МЕТОД ОЧИСТКИ ПАМЯТИ ---
    public function dispose():Void {
        // 1. Отписываемся от глобальной шины (Impulsys)
        Impulsys.removeImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.removeImpulse("EDITOR_NODE_MOVED", onNodeMoved);

        // 2. Снимаем слушителей со сцены
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

        // 3. Уничтожаем все NodeView
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            if (view != null) {
                view.dispose(); // Вызываем очистку внутри вида
                removeChild(view);
            }
        }
        _nodes.clear();

        // 4. Очищаем графику
        _wireLayer.graphics.clear();
        _ghostWire.graphics.clear();

        // 5. Обнуляем ссылки
        _assembly = null;
        _blueprint = null;
    }

    private function restoreExistingAtoms():Void {
        if (_blueprint.internalAtoms == null) return;

        for (atomDef in _blueprint.internalAtoms) {
            var atomInstance = _assembly.internalAtoms.get(atomDef.instanceId);

            if (atomInstance != null) {
                var view = new NodeView(cast atomInstance, atomDef.instanceId);

                if (atomDef.x != null && atomDef.y != null) {
                    view.x = atomDef.x;
                    view.y = atomDef.y;
                } else {
                    view.x = 0;
                    view.y = 0;
                }

                addChild(view);
                _nodes.set(atomDef.instanceId, view);

                var parts = atomDef.instanceId.split("_");
                var num = Std.parseInt(parts[parts.length-1]);
                if (num != null && num >= _spawnCounter) _spawnCounter = num + 1;
            }
        }
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
        var bp = core.AtomDefinitions.get(typeId);
        if (bp == null) return null;

        var instanceId = typeId + "_" + (_spawnCounter++);
        
        var atomDef = { instanceId: instanceId, typeId: typeId, x: posX, y: posY };
        _blueprint.internalAtoms.push(atomDef);

        var inputs = [];
        var outputs = [];
        for (pin in bp.pins) {
            var c = new core.Contact(pin.defaultValue, pin.type, pin.name);
            if (pin.type == ContactType.INPUT) inputs.push(c);
            else outputs.push(c);
        }

        var atom = new Atom(inputs, outputs, bp.logic, instanceId, typeId);
        _assembly.internalAtoms.set(instanceId, atom);

        var view = new NodeView(atom, instanceId);
        view.x = posX;
        view.y = posY;
        
        addChild(view);
        _nodes.set(instanceId, view);

        drawWires();

        return atom;
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
            if (target != null) {
                var fromId = _dragNodeId;
                var fromContact = _dragContactName;
                var toId = target.nodeId;
                var toContact = target.contactName;
                var fromIsInput = _dragStartIsInput;

                if (fromId != toId && fromIsInput != target.isInput) {
                    var link:core.Blueprint.ConnectionDef = {
                        from: { atomId: fromId, contactName: fromContact },
                        to: { atomId: toId, contactName: toContact }
                    };

                    var realFrom = fromIsInput ? link.to : link.from;
                    var realTo = fromIsInput ? link.from : link.to;

                    _blueprint.internalConnections.push(link);

                    var cOut:Contact = null;
                    var cIn:Contact = null;
                    
                    if (realFrom.atomId == "SELF") cOut = _assembly.outputs.get(realFrom.contactName);
                    else {
                        var atom = _assembly.internalAtoms.get(realFrom.atomId);
                        if (atom != null) cOut = cast(atom, Atom).getOutput(realFrom.contactName);
                    }

                    if (realTo.atomId == "SELF") cIn = _assembly.inputs.get(realTo.contactName);
                    else {
                        var atom = _assembly.internalAtoms.get(realTo.atomId);
                        if (atom != null) cIn = cast(atom, Atom).getInput(realTo.contactName);
                    }

                    if (cOut != null && cIn != null) {
                        cOut.link(cIn);
                    }
                    drawWires();
                }
            }
            _isDraggingPort = false;
            _ghostWire.graphics.clear();
        }
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

    private function onNodeMoved(impulse:Impulse):Void {
        drawWires();
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
        var g = _wireLayer.graphics;
        g.clear();
        g.lineStyle(2, 0x666666);

        for (link in _blueprint.internalConnections) {
            var fromView = _nodes.get(link.from.atomId);
            var toView = _nodes.get(link.to.atomId);

            if (fromView != null && toView != null) {
                var p1 = fromView.getPortPosition(link.from.contactName);
                var p2 = toView.getPortPosition(link.to.contactName);

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