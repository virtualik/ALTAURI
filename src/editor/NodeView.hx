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
import Lambda;

/**
 * NODE VIEW v2.1 (Memory Leak Fixed)
 * Visual representation of an Atom.
 *
 * FIX v2.1:
 * - dispose() now removes ALL event listeners
 * - dispose() removes children from sprite
 * - Clear all sprite references
 */
class NodeView extends Sprite {

    public var atom(default, null):Atom;
    public var nodeId(default, null):String;

    private var _assemblyInstance:Assembly;

    public var inputPorts(default, null):Map<String, Sprite>;
    public var outputPorts(default, null):Map<String, Sprite>;

	private var _width:Float = 100;
	private var _height:Float;

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

    private var _ecsMode:Bool = true;
    
    // Store event handlers for proper removal
    private var _mouseDownHandler:MouseEvent -> Void;
    private var _rightMouseDownHandler:MouseEvent -> Void;
    private var _doubleClickHandler:MouseEvent -> Void;
    private var _settingsClickHandler:MouseEvent -> Void;
    private var _mouseMoveHandler:MouseEvent -> Void;
    private var _mouseUpHandler:MouseEvent -> Void;

    public function setEcsMode(enabled:Bool):Void {
        _ecsMode = enabled;
    }

	private function calculateHeight():Float {
		var inputCount = 0;
		var outputCount = 0;
		
		if (_assemblyInstance != null) {
			inputCount = Lambda.count(_assemblyInstance.inputs);
			outputCount = Lambda.count(_assemblyInstance.outputs);
		} else if (atom != null) {
			inputCount = atom.getInputs() != null ? atom.getInputs().length : 0;
			outputCount = atom.getOutputs() != null ? atom.getOutputs().length : 0;
		}
		
		var maxPorts = Std.int(Math.max(inputCount, outputCount));
		
		// Минимум 40, плюс 20 на каждый дополнительный порт
		return Math.max(40, 30 + maxPorts * 20);
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

        // Create handlers for later removal
        _mouseDownHandler = onMouseDown;
        _rightMouseDownHandler = onRightMouseDown;
        _doubleClickHandler = onDoubleClick;
        _settingsClickHandler = onSettingsClick;

        draw();

        this.buttonMode = true;
        this.useHandCursor = true;

        addEventListener(MouseEvent.MOUSE_DOWN, _mouseDownHandler);
        addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, _rightMouseDownHandler);

        this.doubleClickEnabled = true;
        addEventListener(MouseEvent.DOUBLE_CLICK, _doubleClickHandler);

        // Register with ECS for position tracking and queries
        ECS.register(nodeId, this, this.x, this.y);
    }

    function set_selected(v:Bool):Bool {
        if (selected != v) {
            selected = v;
            ECS.setSelected(nodeId, v);
            redraw();
        }
        return v;
    }

    private function draw():Void {
		_height = calculateHeight();  // ИСПРАВЛЕНИЕ: Рассчитать высоту
		
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
        _settingsBtn.addEventListener(MouseEvent.CLICK, _settingsClickHandler);
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

	public function redraw():Void {
		// Запомнить позицию в display list
		var parentContainer = this.parent;
		var index = (parentContainer != null) ? parentContainer.getChildIndex(this) : -1;
		
		// Сохранить состояние
		var wasSelected = selected;
		var prevX = this.x;
		var prevY = this.y;
		
		// Очистить детей
		while (numChildren > 0) {
			removeChildAt(0);
		}
		
		// Очистить карты портов
		inputPorts = new Map();
		outputPorts = new Map();
		
		// Перерисовать
		draw();
		
		// ИСПРАВЛЕНИЕ: Восстановить позицию в display list
		if (parentContainer != null && index >= 0 && index < parentContainer.numChildren) {
			parentContainer.setChildIndex(this, index);
		}
		
		// Восстановить состояние
		this.x = prevX;
		this.y = prevY;
		selected = wasSelected;
		
		// Обновить ECS
		ECS.updatePosition(nodeId, this.x, this.y);
		ECS.setSelected(nodeId, wasSelected);
	}

	private function drawPorts(contacts:Array<Contact>, type:ContactType):Void {
        var count = contacts.length;
        if (count == 0) return;

        var isInput = (type == ContactType.INPUT);
        var step = _height / (count + 1);

        for (i in 0...count) {
            var c = contacts[i];
            var port = new Sprite();

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

        // Create handlers if not exists
        if (_mouseMoveHandler == null) _mouseMoveHandler = onMouseMove;
        if (_mouseUpHandler == null) _mouseUpHandler = onMouseUp;

        stage.addEventListener(MouseEvent.MOUSE_MOVE, _mouseMoveHandler);
        stage.addEventListener(MouseEvent.MOUSE_UP, _mouseUpHandler);
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

        this.x = newX;
        this.y = newY;

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
        
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, _mouseMoveHandler);
            stage.removeEventListener(MouseEvent.MOUSE_UP, _mouseUpHandler);
        }

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

    public function setPosition(x:Float, y:Float):Void {
        this.x = x;
        this.y = y;
        ECS.updatePosition(nodeId, x, y);
    }

    /**
     * Properly dispose the NodeView.
     * FIX v2.1: Complete cleanup of all references.
     */
    public function dispose():Void {
        // 1. Unregister from ECS
        ECS.unregister(nodeId);

        // 2. Remove all event listeners from this sprite
        removeEventListener(MouseEvent.MOUSE_DOWN, _mouseDownHandler);
        removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, _rightMouseDownHandler);
        removeEventListener(MouseEvent.DOUBLE_CLICK, _doubleClickHandler);

        // 3. Remove stage listeners if still attached
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, _mouseMoveHandler);
            stage.removeEventListener(MouseEvent.MOUSE_UP, _mouseUpHandler);
        }

        // 4. Clean settings button
        if (_settingsBtn != null) {
            _settingsBtn.removeEventListener(MouseEvent.CLICK, _settingsClickHandler);
            if (contains(_settingsBtn)) removeChild(_settingsBtn);
            _settingsBtn = null;
        }

        // 5. Clean port sprites
        if (inputPorts != null) {
            for (port in inputPorts) {
                if (port != null) {
                    port.removeEventListener(MouseEvent.MOUSE_DOWN, onPortMouseDown);
                    if (contains(port)) removeChild(port);
                }
            }
            inputPorts.clear();
            inputPorts = null;
        }
        
        if (outputPorts != null) {
            for (port in outputPorts) {
                if (port != null) {
                    port.removeEventListener(MouseEvent.MOUSE_DOWN, onPortMouseDown);
                    if (contains(port)) removeChild(port);
                }
            }
            outputPorts.clear();
            outputPorts = null;
        }

        // 6. Clear graphics
        graphics.clear();

        // 7. Remove all children
        while (numChildren > 0) {
            removeChildAt(0);
        }

        // 8. Clear references
        atom = null;
        _assemblyInstance = null;
        _mouseDownHandler = null;
        _rightMouseDownHandler = null;
        _doubleClickHandler = null;
        _settingsClickHandler = null;
        _mouseMoveHandler = null;
        _mouseUpHandler = null;
    }
}
