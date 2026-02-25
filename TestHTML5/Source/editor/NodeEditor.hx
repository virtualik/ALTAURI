package editor;

import openfl.display.Sprite;
import openfl.events.Event; // Добавили импорт Event
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

    // Drag state
    private var _isDraggingPort:Bool = false;
    private var _dragNodeId:String;
    private var _dragContactName:String;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _dragStartIsInput:Bool = false;

    private var _ghostWire:Sprite;

    public function new(assembly:Assembly) {
        super();
        this._assembly = assembly;
        this._blueprint = assembly.blueprint;

        // Create "SELF" node (Root of the assembly)
        // Передаем assembly, как обсуждали ранее
        var selfView = new NodeView(null, "SELF", assembly);
        selfView.x = 150;
        selfView.y = 50;
        addChild(selfView);
        _nodes.set("SELF", selfView);

        // Ghost wire container
        _ghostWire = new Sprite();
        addChild(_ghostWire);

        // Subscriptions
        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);
        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);

        // --- FIX: Wait for stage ---
        // Вместо прямой подписки, слушаем событие добавления на сцену
        if (stage != null) {
            initListeners();
        } else {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
        
        drawWires(); // Initial draw
    }

    private function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        initListeners();
    }

    private function initListeners():Void {
        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    // ... rest of methods (createAtom, onPortDragStart, etc) remain the same ...
    
    public function createAtom(typeId:String, posX:Float, posY:Float):Atom {
        var bp = core.AtomDefinitions.get(typeId);
        if (bp == null) return null;

        var instanceId = typeId + "_" + (_spawnCounter++);
        var atomDef = { instanceId: instanceId, typeId: typeId };
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

        // Ensure wires are on top
        addChild(_ghostWire);

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
                    
                    // 1. Сохраняем в Blueprint (для сохранения и отрисовки)
                    var link:core.Blueprint.ConnectionDef = {
                        from: { atomId: fromId, contactName: fromContact },
                        to: { atomId: toId, contactName: toContact }
                    };
                    
                    // Упорядочиваем: всегда Output -> Input
                    var realFrom = fromIsInput ? link.to : link.from;
                    var realTo = fromIsInput ? link.from : link.to;

                    _blueprint.internalConnections.push(link);

                    // 2. Создаем ФИЗИЧЕСКУЮ связь (вместо subscribe)
                    // Находим контакты
                    var cOut:Contact = null;
                    var cIn:Contact = null;

                    // Поиск выхода
                    if (realFrom.atomId == "SELF") cOut = _assembly.outputs.get(realFrom.contactName);
                    else {
                        var atom = _assembly.internalAtoms.get(realFrom.atomId);
                        if (atom != null) cOut = cast(atom, Atom).getOutput(realFrom.contactName);
                    }

                    // Поиск входа
                    if (realTo.atomId == "SELF") cIn = _assembly.inputs.get(realTo.contactName);
                    else {
                        var atom = _assembly.internalAtoms.get(realTo.atomId);
                        if (atom != null) cIn = cast(atom, Atom).getInput(realTo.contactName);
                    }

                    // 3. Используем метод link!
                    if (cOut != null && cIn != null) {
                        cOut.link(cIn); // Это создает постоянную связь. 
                                        // Теперь данные текут сами. 
                                        // И это можно разорвать через cOut.unlink(cIn)!
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
                // Check Inputs
                for (name in view.inputPorts.keys()) {
                    var port = view.inputPorts.get(name);
                    if (port != null) {
                        var local = port.globalToLocal(new Point(x, y));
                        if (Math.abs(local.x) < 10 && Math.abs(local.y) < 10) {
                            return {nodeId: nodeId, contactName: name, isInput: true};
                        }
                    }
                }
                // Check Outputs
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

    // --- DRAWING LOGIC ---

    private function drawGhostWire(startX:Float, startY:Float, endX:Float, endY:Float, isInput:Bool):Void {
        var g = _ghostWire.graphics;
        g.clear();
        g.lineStyle(3, 0x00FF00, 0.8); // Bright green ghost

        g.moveTo(startX, startY);

        // Рассчитываем "вынос" (натяжение) кривой
        var dx = Math.abs(endX - startX) * 0.5;
        // Минимальный вынос, чтобы провод не "ломался" на коротких дистанциях
        if (dx < 50) dx = 50; 

        if (isInput) {
            // Тянем ВХОД (слева) -> к Мышке
            // Контрольные точки идут влево от старта и вправо от конца (мышки)
            g.cubicCurveTo(startX - dx, startY, endX + dx, endY, endX, endY);
        } else {
            // Тянем ВЫХОД (справа) -> к Мышке
            // Контрольные точки идут вправо от старта и влево от конца
            g.cubicCurveTo(startX + dx, startY, endX - dx, endY, endX, endY);
        }
    }

        private function drawWires():Void {
        graphics.clear();
        graphics.lineStyle(2, 0x666666);

        for (link in _blueprint.internalConnections) {
            var fromView = _nodes.get(link.from.atomId);
            var toView = _nodes.get(link.to.atomId);

            if (fromView != null && toView != null) {
                var p1 = fromView.getPortPosition(link.from.contactName);
                var p2 = toView.getPortPosition(link.to.contactName);

                // --- УМНАЯ ЛОГИКА ИЗГИБА ---

                // 1. Определяем тип портов (Вход или Выход)
                var isFromInput = fromView.inputPorts.exists(link.from.contactName);
                var isToInput = toView.inputPorts.exists(link.to.contactName);

                // 2. Рассчитываем натяжение
                var dist = Math.abs(p2.x - p1.x);
                var tension = dist * 0.5;
                if (tension < 50) tension = 50; // Минимальный изгиб

                // 3. Рассчитываем контрольные точки Безье
                var c1x:Float;
                var c2x:Float;

                // Точка 1 (старт)
                if (isFromInput) {
                    // Если тянем ОТ входа (слева), кривая должна идти влево
                    c1x = p1.x - tension;
                } else {
                    // Если тянем ОТ выхода (справа), кривая идет вправо
                    c1x = p1.x + tension;
                }

                // Точка 2 (финиш)
                if (isToInput) {
                    // Если тянем КО входу (слева), кривая приходит слева
                    c2x = p2.x - tension;
                } else {
                    // Если тянем К выходу (справа), кривая приходит справа
                    c2x = p2.x + tension;
                }

                // Рисуем
                graphics.moveTo(p1.x, p1.y);
                graphics.cubicCurveTo(c1x, p1.y, c2x, p2.y, p2.x, p2.y);
            }
        }
    }
}