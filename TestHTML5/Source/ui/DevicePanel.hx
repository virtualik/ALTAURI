package ui;

import openfl.display.Sprite;
import core.Atom;
import core.Assembly;
import core.Contact;
import core.ContactType;
import ui.hmi.IHMIWidget;
import ui.hmi.NumberInput;
import ui.hmi.NumberDisplay;

/**
 * DEVICE PANEL v1.0
 * Automatically generates a UI panel for an Atom or Assembly.
 * It creates Inputs on the left, Outputs on the right.
 */
class DevicePanel extends Sprite {
    
    private var _target:Dynamic; // Atom or Assembly
    private var _widgets:Array<IHMIWidget>;
    
    public function new(target:Dynamic) {
        super();
        _target = target;
        _widgets = new Array();
        
        drawBackground();
        layoutWidgets();
    }
    
    private function drawBackground():Void {
        graphics.beginFill(0x1a1a24);
        graphics.drawRect(0, 0, 400, 300);
        graphics.endFill();
    }
    
    private function layoutWidgets():Void {
        // Get Maps of contacts
        var inputs:Map<String, Contact> = null;
        var outputs:Map<String, Contact> = null;
        
        // Check if it's an Assembly or Atom
        if (Std.is(_target, Assembly)) {
            var asm:Assembly = cast _target;
            inputs = asm.inputs;
            outputs = asm.outputs;
        } else if (Std.is(_target, Atom)) {
            // Simple Atom doesn't have map, create dummy map from arrays
            inputs = new Map();
            outputs = new Map();
            var atom:Atom = cast _target;
            for (c in atom.getInputs()) inputs.set(c.name, c);
            for (c in atom.getOutputs()) outputs.set(c.name, c);
        }
        
        // Create Inputs (Left side)
        if (inputs != null) {
            var i = 0;
            for (name in inputs.keys()) {
                var contact = inputs.get(name);
                var widget = new NumberInput(contact, name);
                widget.x = 20;
                widget.y = 40 + i * 60;
                addChild(widget);
                _widgets.push(widget);
                i++;
            }
        }
        
        // Create Outputs (Right side)
        if (outputs != null) {
            var i = 0;
            for (name in outputs.keys()) {
                var contact = outputs.get(name);
                var widget = new NumberDisplay(contact, name);
                widget.x = 220; // Right side
                widget.y = 40 + i * 60;
                addChild(widget);
                _widgets.push(widget);
                i++;
            }
        }
    }
    
    public function dispose():Void {
        for (w in _widgets) w.dispose();
    }
}