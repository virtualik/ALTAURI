package editor;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.Impulse;

class NodeView extends Sprite {

    public var atom(default, null):Atom;
    public var nodeId(default, null):String;

    private var _assembly:Assembly;

    public var inputPorts(default, null):Map<String, Sprite>;
    public var outputPorts(default, null):Map<String, Sprite>;

    private var _width:Float = 100;
    private var _height:Float = 40;

    private var _isDragging:Bool = false;
    private var _offsetX:Float = 0;
    private var _offsetY:Float = 0;

    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;

    private var _settingsBtn:Sprite;
    
    public var selected(default, set):Bool = false;
    
    private var _bgColor:Int = 0x333344;
    private var _borderColor:Int = 0x00AAFF;
    private var _selectedColor:Int = 0xFFCC00;

    public function new(atom:Atom, nodeId:String, ?assembly:Assembly) {
        super();
        this.atom = atom;
        this.nodeId = nodeId;
        this._assembly = assembly;

        inputPorts = new Map();
        outputPorts = new Map();

        draw();

        this.buttonMode = true;
        this.useHandCursor = true;
        
        addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
    }
    
    function set_selected(v:Bool):Bool {
        if (selected != v) {
            selected = v;
            draw();
        }
        return v;
    }

    private function draw():Void {
        graphics.clear();
        graphics.beginFill(_bgColor);
        
        if (selected) {
            graphics.lineStyle(3, _selectedColor);
        } else {
            graphics.lineStyle(2, _borderColor);
        }
        
        graphics.drawRoundRect(0, 0, _width, _height, 10, 10);
        graphics.endFill();

        var title = new TextField();
        var displayName = "Unknown";
        if (atom != null) displayName = atom.name;
        else if (_assembly != null) displayName = _assembly.blueprint.name;
        else displayName = nodeId;

        title.text = displayName;
        title.width = _width - 20;
        title.height = _height;
        title.selectable = false;
        title.mouseEnabled = false;
        var fmt = new TextFormat("_typewriter", 10, 0xFFFFFF);
        fmt.align = TextFormatAlign.CENTER;
        title.defaultTextFormat = fmt;
        addChild(title);

        _settingsBtn = new Sprite();
        _settingsBtn.graphics.beginFill(0x888888, 0.8);
        _settingsBtn.graphics.drawCircle(_width - 10, _height / 2, 6);
        _settingsBtn.graphics.endFill();
        _settingsBtn.graphics.lineStyle(1, 0xFFFFFF);
        _settingsBtn.graphics.moveTo(-3, -3);
        _settingsBtn.graphics.lineTo(3, 3);
        _settingsBtn.x = 0;
        _settingsBtn.buttonMode = true;
        _settingsBtn.useHandCursor = true;
        _settingsBtn.mouseEnabled = true;
        _settingsBtn.addEventListener(MouseEvent.CLICK, onSettingsClick);
        addChild(_settingsBtn);

        if (atom != null) {
            drawPorts(atom.getInputs(), ContactType.INPUT);
            drawPorts(atom.getOutputs(), ContactType.OUTPUT);
        } else if (_assembly != null) {
            var ins = [for (c in _assembly.inputs) c];
            var outs = [for (c in _assembly.outputs) c];
            drawPorts(ins, ContactType.INPUT);
            drawPorts(outs, ContactType.OUTPUT);
        }
    }

    private function drawPorts(contacts:Array<Contact>, type:ContactType):Void {
        var count = contacts.length;
        if (count == 0) return;

        var isInput = (type == ContactType.INPUT);
        var step = _height / (count + 1);

        for (i in 0...count) {
            var c = contacts[i];
            var port = new Sprite();

            port.graphics.beginFill(isInput ? 0xFF8800 : 0x00FF88);
            port.graphics.lineStyle(1, 0xFFFFFF);
            port.graphics.drawCircle(0, 0, 5);
            port.graphics.endFill();

            port.x = isInput ? 0 : _width;
            port.y = step * (i + 1);

            port.buttonMode = true;
            port.useHandCursor = true;
            port.mouseEnabled = true;

            port.name = c.name;

            port.addEventListener(MouseEvent.MOUSE_DOWN, onPortMouseDown);

            addChild(port);

            if (isInput) inputPorts.set(c.name, port);
            else outputPorts.set(c.name, port);
        }
    }

    private function onPortMouseDown(e:MouseEvent):Void {
        e.stopPropagation();

        var port:Sprite = cast e.target;
        var isInput = inputPorts.exists(port.name);
        var contactName = port.name;

        var globalPos = port.localToGlobal(new Point(0, 0));

        Impulsys.emit(new Impulse("PORT_DRAG_START", {
            nodeId: this.nodeId,
            contactName: contactName,
            isInput: isInput,
            startX: globalPos.x,
            startY: globalPos.y
        }));
    }

    private function onSettingsClick(e:MouseEvent):Void {
        e.stopPropagation();
        Impulsys.emit(new Impulse("ATOM_PROPERTIES_REQUEST", {
            atom: this.atom,
            view: this
        }));
    }

    public function getPortPosition(name:String):{x:Float, y:Float} {
        var port:Sprite = null;
        port = inputPorts.get(name);
        if (port != null) return { x: this.x + port.x, y: this.y + port.y };

        port = outputPorts.get(name);
        if (port != null) return { x: this.x + port.x, y: this.y + port.y };

        return { x: this.x, y: this.y };
    }

    private function onMouseDown(e:MouseEvent):Void {
        var targetSprite:Dynamic = e.target;
        if (Std.isOfType(targetSprite, Sprite)) {
             var s:Sprite = targetSprite;
             if (inputPorts.exists(s.name) || outputPorts.exists(s.name) || s == _settingsBtn) {
                 return;
             }
        }
        
        e.stopPropagation();

        Impulsys.emit(new Impulse("NODE_CLICKED", { 
            id: this.nodeId, 
            view: this, 
            ctrlKey: e.ctrlKey 
        } ));

        _isDragging = true;
        _offsetX = e.localX;
        _offsetY = e.localY;

        _dragStartX = this.x;
        _dragStartY = this.y;

        if (parent != null) parent.addChild(this);

        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    private function onRightMouseDown(e:MouseEvent):Void {
        e.stopPropagation();
        Impulsys.emit(new Impulse("NODE_CLICKED", { 
            id: this.nodeId, 
            view: this, 
            ctrlKey: e.ctrlKey 
        } ));
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (!_isDragging) return;

        var parentPos = parent.globalToLocal(new Point(e.stageX, e.stageY));
        
        // Calculate NEW position
        var newX = parentPos.x - _offsetX;
        var newY = parentPos.y - _offsetY;
        
        // Calculate Delta
        var dx = newX - this.x;
        var dy = newY - this.y;
        
        // Apply to self
        this.x = newX;
        this.y = newY;

        // Send update with DELTA
        Impulsys.emit(new Impulse("EDITOR_NODE_MOVED", { 
            id: this.nodeId, 
            view: this,
            dx: dx,
            dy: dy
        } ));
    }

    private function onMouseUp(e:MouseEvent):Void {
        if (!_isDragging) return;

        _isDragging = false;
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);

        if (_dragStartX != this.x || _dragStartY != this.y) {
            Impulsys.emit(new Impulse("NODE_DRAG_FINISHED", {
                id: this.nodeId,
                startX: _dragStartX,
                startY: _dragStartY,
                endX: this.x,
                endY: this.y
            }));
        }
    }

    public function dispose():Void {
        if (_settingsBtn != null) {
            _settingsBtn.removeEventListener(MouseEvent.CLICK, onSettingsClick);
        }

        for (port in inputPorts) {
            port.removeEventListener(MouseEvent.MOUSE_DOWN, onPortMouseDown);
        }
        for (port in outputPorts) {
            port.removeEventListener(MouseEvent.MOUSE_DOWN, onPortMouseDown);
        }

        inputPorts = null;
        outputPorts = null;
        atom = null;
        _assembly = null;
    }
}