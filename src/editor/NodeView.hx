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
import ecs.ECS;

/**
 * NODE VIEW v2.0 (ECS Integrated)
 * Visual representation of an Atom.
 *
 * CHANGES v2.0:
 * - Position managed by ECS (PositionComponent)
 * - Selection state managed by ECS (VisualComponent)
 * - Direct sprite manipulation during drag (immediate feedback)
 * - ECS updated in parallel for queries
 */
class NodeView extends Sprite {

    public var atom(default, null):Atom;
    public var nodeId(default, null):String;

    private var _assemblyInstance:Assembly;

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

    /**
     * Selection now uses ECS VisualComponent.
     * Local property kept for backward compatibility.
     */
    public var selected(default, set):Bool = false;

    private var _bgColor:Int = 0x333344;
    private var _borderColor:Int = 0x00AAFF;
    private var _selectedColor:Int = 0xFFCC00;

	/**
     * When true, position updates go through ECS.
     * When false, direct sprite manipulation only.
     */
    private var _ecsMode:Bool = true;

    /**
     * Set ECS rendering mode.
     */
    public function setEcsMode(enabled:Bool):Void {
        _ecsMode = enabled;
    }

    public function new(atom:Atom, nodeId:String) {
        super();
        this.atom = atom;
        this.nodeId = nodeId;

        if (Std.isOfType(atom, Assembly)) {
            this._assemblyInstance = cast(atom, Assembly);
        }

        inputPorts = new Map();
        outputPorts = new Map();

        draw();

        this.buttonMode = true;
        this.useHandCursor = true;

        addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);

        this.doubleClickEnabled = true;
        addEventListener(MouseEvent.DOUBLE_CLICK, onDoubleClick);

        // Register with ECS for position tracking and queries
        ECS.register(nodeId, this, this.x, this.y);
    }

    function set_selected(v:Bool):Bool {
        if (selected != v) {
            selected = v;

            // Update ECS VisualComponent
            ECS.setSelected(nodeId, v);

            // Immediate visual feedback
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

        if (_assemblyInstance != null) displayName = _assemblyInstance.blueprint.name;
        else if (atom != null) displayName = atom.name;
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

        var ins:Array<Contact> = [];
        var outs:Array<Contact> = [];

        if (_assemblyInstance != null) {
            ins = _assemblyInstance.getInputs();
            outs = _assemblyInstance.getOutputs();
        } else if (atom != null) {
            ins = atom.getInputs();
            outs = atom.getOutputs();
        }

        drawPorts(ins, ContactType.INPUT);
        drawPorts(outs, ContactType.OUTPUT);
    }

    private function drawPorts(contacts:Array<Contact>, type:ContactType):Void {
        var count = contacts.length;
        if (count == 0) return;

        var isInput = (type == ContactType.INPUT);
        var step = _height / (count + 1);

        for (i in 0...count) {
            var c = contacts[i];
            var port = new Sprite();

            // Белый сплошной круг без обводки
            port.graphics.beginFill(0xFFFFFF);
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

    private function onDoubleClick(e:MouseEvent):Void {
        Impulsys.emit(new Impulse("OPEN_ASSEMBLY_REQUEST", {
            atomId: this.nodeId
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
        Impulsys.emit(new Impulse("NODE_RIGHT_CLICKED", {
            id: this.nodeId,
            view: this,
            name: (_assemblyInstance != null) ? _assemblyInstance.blueprint.name : (atom != null ? atom.name : nodeId)
        } ));
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (!_isDragging) return;

        var parentPos = parent.globalToLocal(new Point(e.stageX, e.stageY));

        var newX = parentPos.x - _offsetX;
        var newY = parentPos.y - _offsetY;

        var dx = newX - this.x;
        var dy = newY - this.y;

        // Direct sprite manipulation for immediate visual feedback
        this.x = newX;
        this.y = newY;

        // Update ECS only in ECS mode
        if (_ecsMode) {
            ECS.updatePosition(nodeId, newX, newY);
        }

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

    /**
     * Update sprite position from external source (undo/redo, restore).
     * Also updates ECS to keep in sync.
     */
    public function setPosition(x:Float, y:Float):Void {
        this.x = x;
        this.y = y;
        ECS.updatePosition(nodeId, x, y);
    }

    public function dispose():Void {
        // Unregister from ECS
        ECS.unregister(nodeId);

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
        _assemblyInstance = null;
    }
}
