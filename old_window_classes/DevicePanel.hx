package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import core.base.Atom;
import core.base.Assembly;
import core.base.Contact;
import ui.widgets.IHMIWidget;
import ui.widgets.NumberInput;
import ui.widgets.NumberDisplay;
import ui.ContextMenu;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * DevicePanel v2.1
 * FIXED: setTarget is public method
 */
class DevicePanel extends Sprite {
    private var _target:Dynamic;
    private var _assembly:Assembly;
    private var _widgets:Array<IHMIWidget>;
    private var _header:Sprite;
    private var _titleField:TextField;
    private var _selectBtn:Sprite;
    private var _contextMenu:ContextMenu;
    private var _content:Sprite;
    private var _isCompact:Bool = false;
    private var _isDisposed:Bool = false;

    public function new(assembly:Assembly) {
        super();
        if (assembly == null) {
            trace('ERROR: DevicePanel created with null assembly');
            return;
        }
        _assembly = assembly;
        _target = assembly;
        _widgets = new Array();
        _content = new Sprite();
        _content.y = 50;
        addChild(_content);
        setupHeader();
        drawBackground();
        layoutWidgets();
    }

    public function setCompactMode(val:Bool):Void {
        if (_isDisposed) return;
        _isCompact = val;
        if (_isCompact) {
            this.graphics.clear();
            if (_header != null) _header.visible = false;
            _content.y = 0;
        } else {
            drawBackground();
            if (_header != null) _header.visible = true;
            _content.y = 50;
        }
    }

    private function drawBackground():Void {
        if (_isDisposed) return;
        graphics.clear();
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, 400, 500);
        graphics.endFill();
    }

    private function setupHeader():Void {
        if (_isDisposed) return;
        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 400, 40);
        _header.y = 0;
        addChild(_header);

        _titleField = new TextField();
        _titleField.width = 200;
        _titleField.height = 40;
        _titleField.x = 10;
        _titleField.y = 0;
        _titleField.selectable = false;
        _titleField.mouseEnabled = false;
        var fmt = new TextFormat("_typewriter", 14, 0xFFFFFF);
        fmt.align = "left";
        _titleField.defaultTextFormat = fmt;
        _titleField.text = "Device: SELF";
        _header.addChild(_titleField);

        _selectBtn = new Sprite();
        _selectBtn.graphics.beginFill(0x444455);
        _selectBtn.graphics.drawRoundRect(0, 5, 120, 30, 5, 5);
        _selectBtn.x = 270;
        _selectBtn.buttonMode = true;
        _selectBtn.useHandCursor = true;
        var btnTxt = new TextField();
        btnTxt.text = "Select Atom";
        btnTxt.width = 120;
        btnTxt.height = 30;
        btnTxt.selectable = false;
        btnTxt.mouseEnabled = false;
        var btnFmt = new TextFormat("_typewriter", 12, 0xFFFFFF, null, null, null, null, null, "center");
        btnTxt.defaultTextFormat = btnFmt;
        btnTxt.y = 5;
        _selectBtn.addChild(btnTxt);
        _selectBtn.addEventListener(MouseEvent.CLICK, onSelectClick);
        _header.addChild(_selectBtn);
    }

    private function onSelectClick(e:MouseEvent):Void {
        if (_isDisposed) return;
        if (_contextMenu != null) removeChild(_contextMenu);
        _contextMenu = new ContextMenu();
        _contextMenu.addItem("[ SELF ]", "SELECT_ATOM", {id: "SELF"});
        if (_assembly != null && _assembly.internalAtoms != null) {
            for (id in _assembly.internalAtoms.keys()) {
                var atom = _assembly.internalAtoms.get(id);
                var name = Std.isOfType(atom, Atom) ? cast(atom, Atom).name : "Unknown";
                _contextMenu.addItem(name + " ("+id+")", "SELECT_ATOM", {id: id});
            }
        }
        _contextMenu.x = 270;
        _contextMenu.y = 45;
        addChild(_contextMenu);
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
    }

    private function onMenuAction(impulse:Impulse):Void {
        if (_isDisposed) return;
        if (impulse.data.action != "SELECT_ATOM") return;
        var id:String = impulse.data.data.id;
        if (_contextMenu != null) {
            removeChild(_contextMenu);
            _contextMenu = null;
        }
        Impulsys.removeImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        if (id == "SELF") {
            setTarget(_assembly, "SELF");
        } else {
            var atom = _assembly.internalAtoms.get(id);
            if (atom != null) setTarget(atom, id);
        }
    }

    public function setTarget(target:Dynamic, name:String):Void {
        if (_isDisposed) return;
        _target = target;
        if (_titleField != null) _titleField.text = "Device: " + name;
        clearWidgets();
        layoutWidgets();
    }

    private function clearWidgets():Void {
        if (_widgets == null) return;
        for (w in _widgets) {
            if (w != null) {
                try {
                    w.dispose();
                } catch (e:Dynamic) {
                    trace('WARN: Error disposing widget: $e');
                }
            }
        }
        _widgets = [];
        while (_content.numChildren > 0) {
            _content.removeChildAt(0);
        }
    }

    private function layoutWidgets():Void {
        if (_isDisposed || _target == null) return;

        var inputs:Map<String, Contact> = null;
        var outputs:Map<String, Contact> = null;

        if (Std.isOfType(_target, Assembly)) {
            var asm:Assembly = cast _target;
            inputs = asm.inputs;
            outputs = asm.outputs;
        } else if (Std.isOfType(_target, Atom)) {
            inputs = new Map();
            outputs = new Map();
            var atom:Atom = cast _target;
            if (atom.getInputs() != null) {
                for (c in atom.getInputs()) {
                    if (c != null) inputs.set(c.name, c);
                }
            }
            if (atom.getOutputs() != null) {
                for (c in atom.getOutputs()) {
                    if (c != null) outputs.set(c.name, c);
                }
            }
        }

        var yPos:Int = 10;
        if (inputs != null) {
            for (name in inputs.keys()) {
                var contact = inputs.get(name);
                if (contact == null) continue;
                try {
                    var widget = new NumberInput(contact, name);
                    widget.x = 20;
                    widget.y = yPos;
                    _content.addChild(widget);
                    _widgets.push(widget);
                    yPos += 60;
                } catch (e:Dynamic) {
                    trace('ERROR: Failed to create NumberInput for $name: $e');
                }
            }
        }

        if (outputs != null) {
            yPos = 10;
            for (name in outputs.keys()) {
                var contact = outputs.get(name);
                if (contact == null) continue;
                try {
                    var widget = new NumberDisplay(contact, name);
                    widget.x = 220;
                    widget.y = yPos;
                    _content.addChild(widget);
                    _widgets.push(widget);
                    yPos += 60;
                } catch (e:Dynamic) {
                    trace('ERROR: Failed to create NumberDisplay for $name: $e');
                }
            }
        }
    }

    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        clearWidgets();
        if (_selectBtn != null) {
            _selectBtn.removeEventListener(MouseEvent.CLICK, onSelectClick);
        }
        Impulsys.removeImpulse("CONTEXT_MENU_ACTION", onMenuAction);
        if (_contextMenu != null && _contextMenu.parent != null) {
            _contextMenu.parent.removeChild(_contextMenu);
            _contextMenu = null;
        }
        _widgets = null;
        _content = null;
        _header = null;
        _titleField = null;
        _selectBtn = null;
        _assembly = null;
        _target = null;
    }
}