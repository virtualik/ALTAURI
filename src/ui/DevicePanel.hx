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
 * DEVICE PANEL v2.1
 * Panel for interacting with Atoms in Runtime mode.
 * Supports Compact Mode for VirtualDevice Player (transparent background, no controls).
 */
class DevicePanel extends Sprite {

    private var _target:Dynamic; // Atom or Assembly
    private var _assembly:Assembly;
    private var _widgets:Array<IHMIWidget>;

    // UI Elements
    private var _header:Sprite;
    private var _titleField:TextField;
    private var _selectBtn:Sprite;
    private var _contextMenu:ContextMenu;
    private var _content:Sprite;
    
    private var _isCompact:Bool = false;

    public function new(assembly:Assembly) {
        super();
        _assembly = assembly;
        _target = assembly; // Default target is the Assembly itself
        _widgets = new Array();

        // Always create content container first
        _content = new Sprite();
        _content.y = 50; // Offset for header
        addChild(_content);

        setupHeader();
        drawBackground();
        layoutWidgets();
    }

    /**
     * Toggles compact mode.
     * In Compact Mode: No background, no header, pure widgets.
     */
    public function setCompactMode(val:Bool):Void {
        _isCompact = val;
        
        if (_isCompact) {
            // Clear graphics (background)
            this.graphics.clear();
            // Hide header
            if (_header != null) _header.visible = false;
            // Adjust content position
            _content.y = 0;
        } else {
            drawBackground();
            if (_header != null) _header.visible = true;
            _content.y = 50;
        }
    }

    private function drawBackground():Void {
        // Draw main background
        graphics.clear();
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, 400, 500);
        graphics.endFill();
    }

    private function setupHeader():Void {
        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 400, 40);
        _header.y = 0;
        addChild(_header);

        // Title
        _titleField = new TextField();
        _titleField.width = 200;
        _titleField.height = 40;
        _titleField.x = 10;
        _titleField.y = 0;
        _titleField.selectable = false;
        var fmt = new TextFormat("_typewriter", 14, 0xFFFFFF);
        fmt.align = "left";
        _titleField.defaultTextFormat = fmt;
        _titleField.text = "Device: SELF";
        _header.addChild(_titleField);

        // Select Button
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
        // Create menu on the fly
        if (_contextMenu != null) removeChild(_contextMenu);
        
        _contextMenu = new ContextMenu();
        
        // Add SELF (Root)
        _contextMenu.addItem("[ SELF ]", "SELECT_ATOM", {id: "SELF"});

        // Add all internal atoms
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

        // Subscribe once
        Impulsys.subscribeToImpulse("CONTEXT_MENU_ACTION", onMenuAction);
    }

    private function onMenuAction(impulse:Impulse):Void {
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
        _target = target;
        _titleField.text = "Device: " + name;
        
        // Clear old widgets
        for (w in _widgets) w.dispose();
        _widgets = [];
        while (_content.numChildren > 0) _content.removeChildAt(0);

        layoutWidgets();
    }

    private function layoutWidgets():Void {
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
            for (c in atom.getInputs()) inputs.set(c.name, c);
            for (c in atom.getOutputs()) outputs.set(c.name, c);
        }

        // Draw Inputs (Left side)
        if (inputs != null) {
            var i = 0;
            for (name in inputs.keys()) {
                var contact = inputs.get(name);
                var widget = new NumberInput(contact, name);
                widget.x = 20;
                widget.y = 10 + i * 60;
                _content.addChild(widget);
                _widgets.push(widget);
                i++;
            }
        }

        // Draw Outputs (Right side)
        if (outputs != null) {
            var i = 0;
            for (name in outputs.keys()) {
                var contact = outputs.get(name);
                var widget = new NumberDisplay(contact, name);
                widget.x = 220;
                widget.y = 10 + i * 60;
                _content.addChild(widget);
                _widgets.push(widget);
                i++;
            }
        }
    }

    public function dispose():Void {
        for (w in _widgets) w.dispose();
        _selectBtn.removeEventListener(MouseEvent.CLICK, onSelectClick);
        Impulsys.removeImpulse("CONTEXT_MENU_ACTION", onMenuAction);
    }
}