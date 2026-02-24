package editor;

import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.events.MouseEvent;
import core.Assembly;
import core.Atom;
import core.AtomDefinitions;
import core.Blueprint;
import core.Blueprint.ConnectionDef;
import core.ContactType;
import core.Contact;
import core.Impulsys;
import core.Impulse;

class NodeEditor extends Sprite {
    
    private var _assembly:Assembly;
    private var _blueprint:Blueprint;
    
    private var _wireLayer:Sprite;
    private var _nodes:Map<String, NodeView>;
    private var _externalPinsView:NodeView; 
    
    // --- Wire Drag State ---
    private var _isDraggingWire:Bool = false;
    private var _dragStartData:Dynamic; 
    private var _ghostWire:Sprite; 
    
    private var _spawnCounter:Int = 0;

    public function new(assembly:Assembly) {
        super();
        _assembly = assembly;
        _blueprint = assembly.blueprint;
        
        _nodes = new Map();
        
        // Layer for permanent wires
        _wireLayer = new Sprite();
        _wireLayer.mouseEnabled = false;
        addChild(_wireLayer);
        
        // Layer for "ghost" wire (dragging)
        _ghostWire = new Sprite();
        _ghostWire.mouseEnabled = false;
        addChild(_ghostWire);

        Impulsys.subscribeToImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.subscribeToImpulse("PORT_DRAG_START", onPortDragStart);

        layoutNodes();
        drawWires();
    }

    // --- Node Movement ---
    
    private function onNodeMoved(impulse:Impulse):Void {
        drawWires();
    }
    
    // --- Wire Logic ---

    private function onPortDragStart(impulse:Impulse):Void {
        _isDraggingWire = true;
        _dragStartData = impulse.data;
        
        stage.addEventListener(MouseEvent.MOUSE_MOVE, onWireDragMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onWireDragEnd);
        
        drawGhostWire(_dragStartData.startX, _dragStartData.startY);
    }
    
    private function onWireDragMove(e:MouseEvent):Void {
        if (!_isDraggingWire) return;
        drawGhostWire(_dragStartData.startX, _dragStartData.startY, e.stageX, e.stageY);
    }
    
    private function onWireDragEnd(e:MouseEvent):Void {
        _isDraggingWire = false;
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onWireDragMove);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onWireDragEnd);
        
        _ghostWire.graphics.clear();
        
        // --- DETECT TARGET ---
        var targetData:Dynamic = null;
        
        for (nodeId in _nodes.keys()) {
            var view = _nodes.get(nodeId);
            
            // Check Input Ports
            for (portName in view.inputPorts.keys()) {
                var port = view.inputPorts.get(portName);
                if (port.hitTestPoint(e.stageX, e.stageY, true)) {
                    targetData = { nodeId: nodeId, contactName: portName, isInput: true };
                    break;
                }
            }
            // Check Output Ports
            if (targetData == null) {
                for (portName in view.outputPorts.keys()) {
                    var port = view.outputPorts.get(portName);
                    if (port.hitTestPoint(e.stageX, e.stageY, true)) {
                        targetData = { nodeId: nodeId, contactName: portName, isInput: false };
                        break;
                    }
                }
            }
            if (targetData != null) break;
        }
        
        // --- VALIDATE CONNECTION ---
        if (targetData != null) {
            var from:Dynamic = null;
            var to:Dynamic = null;
            
            if (!_dragStartData.isInput && targetData.isInput) {
                from = _dragStartData;
                to = targetData;
            } else if (_dragStartData.isInput && !targetData.isInput) {
                from = targetData;
                to = _dragStartData;
            } else {
                trace("Invalid connection.");
                return;
            }
            
            if (from.nodeId == to.nodeId) {
                trace("Cannot connect to self.");
                return;
            }
            
            createConnection(from.nodeId, from.contactName, to.nodeId, to.contactName);
        }
    }
    
    private function drawGhostWire(x1:Float, y1:Float, x2:Float = -1, y2:Float = -1):Void {
        _ghostWire.graphics.clear();
        if (x2 < 0) return;
        
        _ghostWire.graphics.lineStyle(2, 0xAAAAAA, 0.8);
        _ghostWire.graphics.moveTo(x1, y1);
        _ghostWire.graphics.lineTo(x2, y2);
    }
    
    // --- Data Manipulation ---

    private function createConnection(fromNodeId:String, fromPort:String, toNodeId:String, toPort:String):Void {
        // 1. Add to Blueprint
        var conn:ConnectionDef = {
            from: { atomId: fromNodeId, contactName: fromPort },
            to: { atomId: toNodeId, contactName: toPort }
        };
        _blueprint.internalConnections.push(conn);
        
        // 2. Link Runtime Contacts
        var fromAtom:Atom = (fromNodeId == "SELF") 
            ? _externalPinsView.atom 
            : cast _assembly.internalAtoms.get(fromNodeId);
            
        var toAtom:Atom = (toNodeId == "SELF") 
            ? _externalPinsView.atom 
            : cast _assembly.internalAtoms.get(toNodeId);
            
        if (fromAtom == null || toAtom == null) return;
        
        var fromContact:Contact = null;
        for (c in fromAtom.getOutputs()) if (c.name == fromPort) fromContact = c;
        
        var toContact:Contact = null;
        for (c in toAtom.getInputs()) if (c.name == toPort) toContact = c;
        
        if (fromContact != null && toContact != null) {
            fromContact.link(toContact);
            trace("Connected: " + fromNodeId + "." + fromPort + " -> " + toNodeId + "." + toPort);
        }
        
        // 3. Redraw
        drawWires();
    }
    
    private function onMenuAction(impulse:Impulse):Void {
        if (impulse.data.action == "ADD_ATOM") {
            var atomData:Dynamic = impulse.data.data;
            var stageX:Float = impulse.data.x;
            var stageY:Float = impulse.data.y;
            var localPos = this.globalToLocal(new Point(stageX, stageY));
            createAtom(atomData.typeId, localPos.x, localPos.y);
        }
    }
    
    public function createAtom(typeId:String, posX:Float, posY:Float):Void {
        var bp = AtomDefinitions.get(typeId);
        if (bp == null) return;
        
        var instanceId = typeId + "_" + (_spawnCounter++);
        var atomDef = { instanceId: instanceId, typeId: typeId };
        _blueprint.internalAtoms.push(atomDef);
        
        var inputs = [];
        var outputs = [];
        for (pin in bp.pins) {
            var c = new Contact(pin.defaultValue, pin.type, pin.name);
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
    }

    private function layoutNodes():Void {
        var extInputs = [];
        var extOutputs = [];
        for (p in _blueprint.pins) {
            var c = new Contact(p.defaultValue, p.type, p.name);
            if (p.type == ContactType.INPUT) extInputs.push(c);
            else extOutputs.push(c);
        }
        var dummySelfAtom = new Atom(extInputs, extOutputs, function(v) return v, "self_atom", "External IO");
        
        _externalPinsView = new NodeView(dummySelfAtom, "SELF");
        _externalPinsView.x = 50;
        _externalPinsView.y = 100;
        
        addChild(_externalPinsView);
        _nodes.set("SELF", _externalPinsView);

        var xPos = 250;
        if (_blueprint.internalAtoms != null) {
            for (atomDef in _blueprint.internalAtoms) {
                var atomObj = _assembly.internalAtoms.get(atomDef.instanceId);
                if (atomObj == null) continue;
                
                var realAtom:Atom = cast atomObj;
                var view = new NodeView(realAtom, atomDef.instanceId);
                
                view.x = xPos;
                view.y = 100;
                
                addChild(view);
                _nodes.set(atomDef.instanceId, view);
                
                xPos += 200;
            }
        }
    }

    public function drawWires():Void {
        _wireLayer.graphics.clear();
        
        if (_blueprint.internalConnections == null) return;

        for (conn in _blueprint.internalConnections) {
            var fromView = _nodes.get(conn.from.atomId);
            var toView = _nodes.get(conn.to.atomId);
            
            if (fromView == null || toView == null) continue;
            
            var p1 = fromView.getPortPosition(conn.from.contactName);
            var p2 = toView.getPortPosition(conn.to.contactName);
            
            var dx = p2.x - p1.x;
            var strength = Math.abs(dx) * 0.5;
            
            var cp1x = p1.x + (dx > 0 ? strength : -strength); 
            var cp2x = p2.x + (dx > 0 ? -strength : strength);
            
            _wireLayer.graphics.lineStyle(3, 0x00AAFF, 0.8);
            _wireLayer.graphics.moveTo(p1.x, p1.y);
            _wireLayer.graphics.cubicCurveTo(cp1x, p1.y, cp2x, p2.y, p2.x, p2.y);
        }
    }
    
    public function dispose():Void {
        Impulsys.removeImpulse("EDITOR_NODE_MOVED", onNodeMoved);
        Impulsys.removeImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        Impulsys.removeImpulse("PORT_DRAG_START", onPortDragStart);
    }
}