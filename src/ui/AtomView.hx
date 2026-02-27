package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Atom;
import core.base.Contact;
import ui.IAtomView;

/**
 * ATOM VIEW v1.0
 * Visual representation of an Atom using OpenFL.
 */
class AtomView extends Sprite implements IAtomView {

    public var atom(get, null):Atom;

    private var _atom:Atom;
    private var _skin:AtomSkin;
    private var _context:String;

    private var _label:TextField;
    private var _contactViews:Array<Sprite>;

    public function new(atom:Atom, context:String = "Editor") {
        super();
        _atom = atom;
        _context = context;

        var baseSkin = SkinManager.getInstance().getSkinForType(atom.type);
        _skin = (_context == "Device") ? baseSkin.deviceSkin : baseSkin.editorSkin;
        if (_skin == null) _skin = baseSkin;

        setupView();
        bindToAtom();
    }

    private function setupView():Void {
        this.buttonMode = true;
        this.useHandCursor = true;

        drawBackground();
        drawLabel();
        drawPorts();
    }

    private function drawBackground():Void {
        graphics.clear();
        graphics.beginFill(_skin.backgroundColor);
        graphics.lineStyle(2, _skin.borderColor);

        if (_skin.cornerRadius > 0) {
            graphics.drawRoundRect(0, 0, _skin.width, _skin.height, _skin.cornerRadius, _skin.cornerRadius);
        } else {
            graphics.drawRect(0, 0, _skin.width, _skin.height);
        }
        graphics.endFill();
    }

    private function drawLabel():Void {
        _label = new TextField();
        _label.selectable = false;
        _label.mouseEnabled = false;
        _label.width = _skin.width;
        _label.height = 20;
        _label.y = (_skin.height - 20) / 2;

        var format:TextFormat = new TextFormat("_typewriter", 10, _skin.textColor);
        format.align = TextFormatAlign.CENTER;
        _label.defaultTextFormat = format;
        _label.text = _atom.name;

        addChild(_label);
    }

    private function drawPorts():Void {
        if (_contactViews != null) {
            for (v in _contactViews) removeChild(v);
        }
        _contactViews = [];

        var inputs = _atom.getInputs();
        for (i in 0...inputs.length) {
            var port = createPortView(inputs[i]);
            port.x = 0;
            port.y = (_skin.height / (inputs.length + 1)) * (i + 1);
            addChild(port);
            _contactViews.push(port);
        }

        var outputs = _atom.getOutputs();
        for (i in 0...outputs.length) {
            var port = createPortView(outputs[i]);
            port.x = _skin.width;
            port.y = (_skin.height / (outputs.length + 1)) * (i + 1);
            addChild(port);
            _contactViews.push(port);
        }
    }

    private function createPortView(c:Contact):Sprite {
        var s = new Sprite();
        s.graphics.beginFill(0x00AAFF);
        s.graphics.lineStyle(1, 0xFFFFFF);
        s.graphics.drawCircle(0, 0, 4);
        s.graphics.endFill();

        s.buttonMode = true;
        s.name = c.name;
        return s;
    }

    private function bindToAtom():Void {
        for (out in _atom.getOutputs()) {
            out.subscribe(onDataChange);
        }
        update();
    }

    private function onDataChange(val:Dynamic):Void {
        update();
    }

    public function update():Void {
        // Logic for visual updates based on atom state
    }

    public function dispose():Void {
        for (out in _atom.getOutputs()) {
            out.unsubscribe(onDataChange);
        }
        _atom = null;
    }

    private function get_atom():Atom {
        return _atom;
    }
}