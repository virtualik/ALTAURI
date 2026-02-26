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
// --- Импорты ядра ---
import core.SignalQueue;
import core.SignalQueue.Priority; 

class NodeView extends Sprite {

    public var atom(default, null):Atom;
    public var nodeId(default, null):String;
    
    private var _assembly:Assembly; 

    public var inputPorts(default, null):Map<String, Sprite>;
    public var outputPorts(default, null):Map<String, Sprite>;

    private var _width:Float = 100;
    private var _height:Float = 60;
    private var _isDragging:Bool = false;
    private var _offsetX:Float = 0;
    private var _offsetY:Float = 0;
    
    private var _valueDisplay:TextField;
    
    // Поле для запоминания подписки
    private var _subscribedContact:Contact = null;
    
    // Кнопка настроек
    private var _settingsBtn:Sprite;

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
        
        bindToValues();
    }

    private function draw():Void {
        graphics.clear();
        graphics.beginFill(0x333344);
        graphics.lineStyle(2, 0x00AAFF);
        graphics.drawRoundRect(0, 0, _width, _height, 10, 10);
        graphics.endFill();

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

        _valueDisplay = new TextField();
        _valueDisplay.width = _width - 10;
        _valueDisplay.height = 20;
        _valueDisplay.x = 5;
        _valueDisplay.y = _height - 20;
        
        var valFmt = new TextFormat("_typewriter", 10, 0x00FF00);
        valFmt.align = TextFormatAlign.RIGHT;
        _valueDisplay.defaultTextFormat = valFmt;
        _valueDisplay.selectable = false;
        _valueDisplay.mouseEnabled = false;
        _valueDisplay.text = "";
        addChild(_valueDisplay);

        // --- Кнопка Настроек (Settings Wrench) ---
        _settingsBtn = new Sprite();
        _settingsBtn.graphics.beginFill(0x888888, 0.8);
        _settingsBtn.graphics.drawCircle(_width - 10, 10, 6); // Правый верхний угол
        _settingsBtn.graphics.endFill();
        
        // Рисуем "гаечный ключ" (упрощенно - линия)
        _settingsBtn.graphics.lineStyle(1, 0xFFFFFF);
        _settingsBtn.graphics.moveTo(-3, -3);
        _settingsBtn.graphics.lineTo(3, 3);
        
        _settingsBtn.buttonMode = true;
        _settingsBtn.useHandCursor = true;
        _settingsBtn.mouseEnabled = true; // Важно!
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

    private function bindToValues():Void {
        if (atom != null) {
            var outputs = atom.getOutputs();
            var inputs = atom.getInputs();
            var contact:Contact = null;
            if (outputs.length > 0) contact = outputs[0];
            else if (inputs.length > 0) contact = inputs[0];
            
            if (contact != null) {
                _subscribedContact = contact; 
                _subscribedContact.subscribe(onValueUpdate);
                onValueUpdate(contact.value);
            }
        }
    }

    private function onValueUpdate(val:Dynamic):Void {
        if (_valueDisplay == null) return;
        
        SignalQueue.getInstance().schedule(function() {
            if (_valueDisplay == null) return;
            
            if (val == null) {
                _valueDisplay.text = "null";
            } else if (Std.isOfType(val, Float)) {
                var f:Float = cast val;
                _valueDisplay.text = Std.string(Math.round(f * 100) / 100);
            } else {
                _valueDisplay.text = Std.string(val);
            }
        }, BACKGROUND);
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
    
    // --- ОБРАБОТЧИК КЛИКА НА НАСТРОЙКИ ---
    private function onSettingsClick(e:MouseEvent):Void {
        e.stopPropagation(); // Чтобы не тащить нод
        
        // Отправляем импульс, что пользователь хочет свойства
        Impulsys.emit(new Impulse("ATOM_PROPERTIES_REQUEST", {
            atom: this.atom,
            view: this // Передаем ссылку на вид, чтобы показать попап рядом
        }));
        
        trace("Settings clicked for: " + (atom != null ? atom.name : "Assembly"));
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
        // Проверяем, не кликнули ли мы по кнопке настроек или портам
        var targetSprite:Dynamic = e.target;
        if (Std.isOfType(targetSprite, Sprite)) {
             var s:Sprite = targetSprite;
             // Если это порт или кнопка настроек - не перетаскиваем нод
             if (inputPorts.exists(s.name) || outputPorts.exists(s.name) || s == _settingsBtn) {
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

    // --- Метод очистки ---
    public function dispose():Void {
        // 1. Отписываемся от данных
        if (_subscribedContact != null) {
            _subscribedContact.unsubscribe(onValueUpdate);
            _subscribedContact = null;
        }
        
        // 2. Убираем слушители кнопки настроек
        if (_settingsBtn != null) {
            _settingsBtn.removeEventListener(MouseEvent.CLICK, onSettingsClick);
        }
        
        // 3. Убираем слушители портов
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