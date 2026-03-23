package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
//import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Assembly;
//import core.base.Contact;
import ui.widgets.NumberInput;
import ui.widgets.NumberDisplay;
import ui.widgets.IHMIWidget;

/**
 * PropertiesWindow v2.1
 * FIXED: Widget lifecycle, null checks, proper cleanup
 * ADDED: Logic Mode switch for Assembly.
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
        // Show toggle for Assembly or Atoms with process logic
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
                // Refresh UI
                _populateAtom(atom);
                // Save change
                core.logic.Impulsys.quickEmit(core.logic.EventType.VALUE_COMMITTED);
            });

            _content.addChild(modeBtn);
            yPos += 35;
        }
        // ===============================

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