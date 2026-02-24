package editor;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import core.Atom;
import core.Assembly;
import core.Contact;
import core.ContactType;
import core.Impulsys;
import core.Impulse;

class NodeView extends Sprite {

    public var atom(default, null):Atom;
    public var nodeId(default, null):String;
    
    private var _assembly:Assembly; 

    public var inputPorts(default, null):Map<String, Sprite>;
    public var outputPorts(default, null):Map<String, Sprite>;

    private var _width:Float = 100;
    private var _height:Float = 60; // Базовая высота
    private var _isDragging:Bool = false;
    private var _offsetX:Float = 0;
    private var _offsetY:Float = 0;
    
    // Новое поле для отображения значения
    private var _valueDisplay:TextField;

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
        
        // Подписываемся на изменения значений
        bindToValues();
    }

    private function draw():Void {
        // 1. Background
        graphics.clear();
        graphics.beginFill(0x333344);
        graphics.lineStyle(2, 0x00AAFF);
        graphics.drawRoundRect(0, 0, _width, _height, 10, 10);
        graphics.endFill();

        // 2. Title
        var title = new TextField();
        var displayName = "Unknown";
        var displayType = "Node";

        if (atom != null) {
            displayName = atom.name;
            displayType = atom.type;
        } else if (_assembly != null) {
            displayName = _assembly.blueprint.name;
            displayType = "SELF";
        } else {
            displayName = nodeId;
        }

        title.text = displayName + "\n(" + displayType + ")";
        title.width = _width;
        title.height = 30;
        title.y = 5;
        title.selectable = false;
        title.mouseEnabled = false;
        var fmt = new TextFormat("_typewriter", 10, 0xFFFFFF);
        fmt.align = TextFormatAlign.CENTER;
        title.defaultTextFormat = fmt;
        addChild(title);

        // 3. Value Display (Зеленые цифры)
        _valueDisplay = new TextField();
        _valueDisplay.width = _width - 10;
        _valueDisplay.height = 20;
        _valueDisplay.x = 5;
        _valueDisplay.y = _height - 20; // Внизу блока
        
        var valFmt = new TextFormat("_typewriter", 10, 0x00FF00); // Зеленый!
        valFmt.align = TextFormatAlign.RIGHT;
        _valueDisplay.defaultTextFormat = valFmt;
        _valueDisplay.selectable = false;
        _valueDisplay.mouseEnabled = false;
        _valueDisplay.text = ""; // Пусто изначально
        addChild(_valueDisplay);

        // 4. Ports
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

    // Новая логика подписки
    private function bindToValues():Void {
        // Если есть атом, подписываемся на первый выход или вход, чтобы показывать значение
        if (atom != null) {
            var outputs = atom.getOutputs();
            var inputs = atom.getInputs();
            
            // Приоритет выходу (для датчиков), иначе входу (для дисплеев)
            var contact:Contact = null;
            if (outputs.length > 0) contact = outputs[0];
            else if (inputs.length > 0) contact = inputs[0];
            
            if (contact != null) {
                contact.subscribe(onValueUpdate);
                // Сразу обновим текущее значение
                onValueUpdate(contact.value);
            }
        }
    }

    private function onValueUpdate(val:Dynamic):Void {
        if (_valueDisplay == null) return;
        
        // Форматируем вывод
        if (val == null) {
            _valueDisplay.text = "null";
        } else if (Std.isOfType(val, Float)) {
            var f:Float = cast val;
            // Показываем 2 знака после запятой
            _valueDisplay.text = Std.string(Math.round(f * 100) / 100);
        } else {
            _valueDisplay.text = Std.string(val);
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

    // ... Остальные методы (onPortMouseDown, getPortPosition, onMouseDown, onMouseMove, onMouseUp) оставляем без изменений ...
    
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
             if (inputPorts.exists(s.name) || outputPorts.exists(s.name)) {
                 return;
             }
        }

        _isDragging = true;
        _offsetX = e.localX;
        _offsetY = e.localY;

        if (parent != null) parent.addChild(this);

        stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (!_isDragging) return;

        var parentPos = parent.globalToLocal(new Point(e.stageX, e.stageY));

        this.x = parentPos.x - _offsetX;
        this.y = parentPos.y - _offsetY;

        Impulsys.emit(new Impulse("EDITOR_NODE_MOVED", { id: this.nodeId, view: this } ));
    }

    private function onMouseUp(e:MouseEvent):Void {
        _isDragging = false;
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }
}