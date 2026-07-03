package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Assembly;
import library.electro.OscilloscopeAtom;
import ui.widgets.NumberInput;
import ui.widgets.NumberDisplay;
import ui.widgets.IHMIWidget;

/**
 * PROPERTIES WINDOW v2.3 (Fixed Close Button Interaction)
 * Atom properties editor with logic mode switch and oscilloscope shape selector.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   PropertiesWindow                                                      │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                  │
 * │   │  Atom: [name]              [x]   │  ← Title + close button          │
 * │   ├──────────────────────────────────┤                                  │
 * │   │                                  │                                  │
 * │   │  Simulation Mode:                │  ← Logic mode switch (Assembly)  │
 * │   │  [Digital (Delayed)]             │                                  │
 * │   │                                  │                                  │
 * │   │  Display Shape:                  │  ← Shape selector (Oscilloscope) │
 * │   │  [Rectangular]                   │                                  │
 * │   │  [Square]                        │                                  │
 * │   │  [Circular]                      │                                  │
 * │   │                                  │                                  │
 * │   │  In: [contact1]  [input]         │  ← NumberInput widgets           │
 * │   │  In: [contact2]  [input]         │                                  │
 * │   │                                  │                                  │
 * │   │  Out: [contact1] [display]       │  ← NumberDisplay widgets         │
 * │   │  Out: [contact2] [display]       │                                  │
 * │   │                                  │                                  │
 * │   └──────────────────────────────────┘                                  │
 * │                                                                         │
 * │   Title bar: drag to move window                                        │
 * │   [x] button: close window                                              │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.3 Changes:
 * - FIXED: Close button MOUSE_DOWN now calls stopPropagation() to prevent
 *   it from triggering the header drag.
 */
class PropertiesWindow extends Sprite {
    private var _bg:Sprite;
    private var _title:TextField;
    private var _content:Sprite;
    private var _target:Dynamic;
    private var _widgets:Array<IHMIWidget>;
    private var _isDisposed:Bool = false;
    
    public function new() {
        super();
        _widgets = new Array();
        
        _bg = new Sprite();
        addChild(_bg);
        _drawBg(300, 200);
        
        _title = new TextField();
        _title.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _title.width = 280;
        _title.height = 20;
        _title.x = 10;
        _title.y = 5;
        _title.selectable = false;
        _title.mouseEnabled = false;
        addChild(_title);
        
        _content = new Sprite();
        _content.y = 30;
        _content.x = 10;
        addChild(_content);
        
        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0, 0, 15, 15);
        closeBtn.x = 280;
        closeBtn.y = 5;
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(_) _close());
        
        // === BUG 1 FIX v2.3: Stop MOUSE_DOWN from propagating to title ===
        // Without this, clicking close would also start a drag on the header.
        closeBtn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());
        
        addChild(closeBtn);
        
        _title.addEventListener(MouseEvent.MOUSE_DOWN, _onMouseDownHeader);
        
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
        } else {
            addEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        }
    }
    
    private function _onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, _onAddedToStage);
        if (stage != null) stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
    }
    
    private function _onMouseDownHeader(e:MouseEvent):Void {
        startDrag();
    }
    
    private function _onMouseUpStage(e:MouseEvent):Void {
        stopDrag();
    }
    
    public function show(target:Dynamic, x:Float, y:Float):Void {
        if (_isDisposed) return;
        
        _target = target;
        this.x = x;
        this.y = y;
        
        _clearContent();
        
        if (Std.isOfType(target, Atom)) {
            _populateAtom(cast target);
        } else {
            _title.text = "Properties";
            var tf = new TextField();
            tf.text = "Unknown object";
            tf.width = 250;
            _content.addChild(tf);
        }
        
        visible = true;
    }
    
    private function _clearContent():Void {
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
    
    public function close():Void {
        _close();
    }
    
    private function _close():Void {
        if (_isDisposed) return;
        visible = false;
        stopDrag();
        _clearContent();
    }
    
    private function _populateAtom(atom:Atom):Void {
        if (_isDisposed || atom == null) return;
        
        _title.text = "Atom: " + atom.name;
        var yPos = 0;
        
        // === v2.1 LOGIC MODE SWITCH ===
        var isLogicTarget = Std.isOfType(atom, Assembly);
        
        if (isLogicTarget) {
            var modeLabel = new TextField();
            modeLabel.text = "Simulation Mode:";
            modeLabel.width = 250;
            modeLabel.height = 20;
            modeLabel.selectable = false;
            modeLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
            modeLabel.y = yPos;
            _content.addChild(modeLabel);
            yPos += 22;
            
            var modeText = atom.isLogic ? "Digital (Delayed)" : "Analog (Immediate)";
            
            var modeBtn = new Sprite();
            modeBtn.graphics.beginFill(atom.isLogic ? 0x2A5A3A : 0x3A5A4A);
            modeBtn.graphics.drawRoundRect(0, 0, 250, 25, 4, 4);
            modeBtn.graphics.endFill();
            modeBtn.y = yPos;
            modeBtn.buttonMode = true;
            
            var tf = new TextField();
            tf.text = modeText;
            tf.width = 250;
            tf.height = 25;
            tf.selectable = false;
            tf.mouseEnabled = false;
            tf.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF, false, null, null, null, null, "center");
            modeBtn.addChild(tf);
            
            modeBtn.addEventListener(MouseEvent.CLICK, function(e) {
                atom.isLogic = !atom.isLogic;
                _populateAtom(atom);
                core.logic.Impulsys.quickEmit(core.logic.EventType.VALUE_COMMITTED);
            });
            
            _content.addChild(modeBtn);
            yPos += 35;
        }
        // ===============================
        
        // === v2.2 OSCILLOSCOPE DISPLAY SHAPE ===
        if (Std.isOfType(atom, OscilloscopeAtom)) {
            var oscAtom:OscilloscopeAtom = cast atom;
            
            var shapeLabel = new TextField();
            shapeLabel.text = "Display Shape:";
            shapeLabel.width = 250;
            shapeLabel.height = 20;
            shapeLabel.selectable = false;
            shapeLabel.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
            shapeLabel.y = yPos;
            _content.addChild(shapeLabel);
            yPos += 22;
            
            var shapes = [
                { label: "Rectangular", value: OscilloscopeAtom.SHAPE_RECTANGULAR },
                { label: "Square", value: OscilloscopeAtom.SHAPE_SQUARE },
                { label: "Circular", value: OscilloscopeAtom.SHAPE_CIRCULAR }
            ];
            
            for (shape in shapes) {
                var isSelected = (oscAtom.getDisplayShape() == shape.value);
                
                var btn = new Sprite();
                btn.graphics.beginFill(isSelected ? 0x2A5A3A : 0x3A3A4A);
                btn.graphics.drawRoundRect(0, 0, 250, 25, 4, 4);
                btn.graphics.endFill();
                btn.y = yPos;
                btn.buttonMode = true;
                
                var btf = new TextField();
                btf.text = shape.label;
                btf.width = 250;
                btf.height = 25;
                btf.selectable = false;
                btf.mouseEnabled = false;
                btf.defaultTextFormat = new TextFormat("_sans", 12, isSelected ? 0x00FF88 : 0xFFFFFF, false, null, null, null, null, "center");
                btn.addChild(btf);
                
                final capturedValue = shape.value;
                
                btn.addEventListener(MouseEvent.CLICK, function(e) {
                    oscAtom.setDisplayShape(capturedValue);
                    // Refresh UI
                    _populateAtom(atom);
                    // Notify change
                    core.logic.Impulsys.quickEmit(core.logic.EventType.VALUE_COMMITTED);
                });
                
                _content.addChild(btn);
                yPos += 30;
            }
            
            yPos += 10; // Extra spacing
        }
        // ======================================
        
        if (atom.getInputs() != null) {
            for (c in atom.getInputs()) {
                if (c == null || c.isDisposed) continue;
                
                try {
                    var input = new NumberInput(c, "In: " + c.name);
                    input.y = yPos;
                    _content.addChild(input);
                    _widgets.push(input);
                    yPos += 40;
                } catch (e:Dynamic) {
                    trace('ERROR: Failed to create NumberInput: $e');
                }
            }
        }
        
        if (atom.getOutputs() != null) {
            for (c in atom.getOutputs()) {
                if (c == null || c.isDisposed) continue;
                
                try {
                    var output = new NumberDisplay(c, "Out: " + c.name);
                    output.y = yPos;
                    _content.addChild(output);
                    _widgets.push(output);
                    yPos += 40;
                } catch (e:Dynamic) {
                    trace('ERROR: Failed to create NumberDisplay: $e');
                }
            }
        }
        
        _drawBg(300, yPos + 50);
    }
    
    private function _drawBg(w:Float, h:Float):Void {
        if (_isDisposed) return;
        
        _bg.graphics.clear();
        _bg.graphics.beginFill(0x222233, 0.95);
        _bg.graphics.lineStyle(1, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, w, h, 10, 10);
        _bg.graphics.endFill();
    }
    
    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;
        
        _clearContent();
        _widgets = null;
        
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_UP, _onMouseUpStage);
        }
        
        if (_bg != null && _bg.parent != null) {
            _bg.parent.removeChild(_bg);
            _bg = null;
        }
        
        if (_content != null && _content.parent != null) {
            _content.parent.removeChild(_content);
            _content = null;
        }
        
        if (_title != null && _title.parent != null) {
            _title.parent.removeChild(_title);
            _title = null;
        }
    }
}