package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;

/**
 * SETTINGS PANEL v1.3
 * Application settings panel with ECS toggle, wire type selection, and Assembly toggle.
 */
class SettingsPanel extends Sprite {

    private var _bg:Sprite;
    private var _title:TextField;
    private var _closeBtn:Sprite;

    /**
     * ECS rendering toggle.
     */
    public var useEcsRender(get, set):Bool;
    private var _useEcsRender:Bool = true;

    /**
     * Wire rendering style.
     */
    public var wireType(get, set):WireType;
    private var _wireType:WireType = WireType.BEZIER;

    /**
     * Allow Assembly creation and editing.
     */
    public var allowAssembly(get, set):Bool;
    private var _allowAssembly:Bool = true;

    /**
     * Callback when settings change.
     */
    public var onSettingsChanged:Void -> Void = null;

    private var _ecsCheckbox:Checkbox;
    private var _assemblyCheckbox:Checkbox;
    private var _wireButtons:Array<RadioButton> = [];

    public function new() {
        super();

        drawBackground();
        createTitle();
        createCloseButton();
        createSettings();
    }

    private function drawBackground():Void {
        _bg = new Sprite();
        _bg.graphics.beginFill(0x1a1a24, 0.98);
        _bg.graphics.lineStyle(2, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, 400, 580, 15, 15);
        _bg.graphics.endFill();
        addChild(_bg);
    }

    private function createTitle():Void {
        _title = new TextField();
        _title.defaultTextFormat = new TextFormat("_typewriter", 18, 0xFFFFFF, true);
        _title.width = 380;
        _title.height = 40;
        _title.x = 10;
        _title.y = 15;
        _title.text = "Settings";
        _title.selectable = false;
        _title.mouseEnabled = false;
        addChild(_title);
    }

    private function createCloseButton():Void {
        _closeBtn = new Sprite();
        _closeBtn.graphics.beginFill(0xAA0000);
        _closeBtn.graphics.drawRoundRect(0, 0, 80, 30, 5, 5);
        _closeBtn.graphics.endFill();
        _closeBtn.x = 310;
        _closeBtn.y = 15;
        _closeBtn.buttonMode = true;
        _closeBtn.useHandCursor = true;

        var label = new TextField();
        label.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, false, null, null, null, null, TextFormatAlign.CENTER);
        label.width = 80;
        label.height = 30;
        label.text = "< Back";
        label.selectable = false;
        label.mouseEnabled = false;
        _closeBtn.addChild(label);

        _closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        addChild(_closeBtn);
    }

    private function createSettings():Void {
        var yPos = 80;

        // Section: Editor
        var sectionLabel = new TextField();
        sectionLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        sectionLabel.width = 380;
        sectionLabel.height = 25;
        sectionLabel.x = 15;
        sectionLabel.y = yPos;
        sectionLabel.text = "EDITOR";
        sectionLabel.selectable = false;
        addChild(sectionLabel);
        yPos += 35;

        // Assembly Toggle
        _assemblyCheckbox = new Checkbox("Allow Assembly", _allowAssembly);
        _assemblyCheckbox.x = 20;
        _assemblyCheckbox.y = yPos;
        _assemblyCheckbox.onChange = onAssemblyToggle;
        addChild(_assemblyCheckbox);
        yPos += 40;

        // Description
        var descAssembly = new TextField();
        descAssembly.defaultTextFormat = new TextFormat("_typewriter", 11, 0x888888);
        descAssembly.width = 360;
        descAssembly.height = 60;
        descAssembly.x = 20;
        descAssembly.y = yPos;
        descAssembly.text = "When enabled:\n- 'New Assembly' button is visible\n- 'Group to Assembly' in context menu\n- Double-click to enter nested assemblies";
        descAssembly.selectable = false;
        addChild(descAssembly);
        yPos += 70;

        // Section: Performance
        var perfLabel = new TextField();
        perfLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        perfLabel.width = 380;
        perfLabel.height = 25;
        perfLabel.x = 15;
        perfLabel.y = yPos;
        perfLabel.text = "PERFORMANCE";
        perfLabel.selectable = false;
        addChild(perfLabel);
        yPos += 35;

        // ECS Toggle
        _ecsCheckbox = new Checkbox("Use ECS Rendering", _useEcsRender);
        _ecsCheckbox.x = 20;
        _ecsCheckbox.y = yPos;
        _ecsCheckbox.onChange = onEcsToggle;
        addChild(_ecsCheckbox);
        yPos += 40;

        // Description
        var desc = new TextField();
        desc.defaultTextFormat = new TextFormat("_typewriter", 11, 0x888888);
        desc.width = 360;
        desc.height = 45;
        desc.x = 20;
        desc.y = yPos;
        desc.text = "ECS mode uses centralized RenderSystem for\nbatch updates. Disable for direct sprite\nmanipulation (legacy mode).";
        desc.selectable = false;
        addChild(desc);
        yPos += 60;

        // Section: Wire Style
        var wireSection = new TextField();
        wireSection.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        wireSection.width = 380;
        wireSection.height = 25;
        wireSection.x = 15;
        wireSection.y = yPos;
        wireSection.text = "WIRE TYPE";
        wireSection.selectable = false;
        addChild(wireSection);
        yPos += 35;

        // Wire type options - only Bezier and Straight now
        var wireOptions = [
            { label: "Bezier Curve", type: WireType.BEZIER, desc: "Smooth curved lines" },
            { label: "Straight Line", type: WireType.STRAIGHT, desc: "Horizontal tails + direct line" }
        ];

        for (opt in wireOptions) {
            var radio = new RadioButton(opt.label, _wireType == opt.type);
            radio.x = 20;
            radio.y = yPos;
            radio.userData = opt.type;
            radio.onSelect = onWireTypeSelect;
            addChild(radio);
            _wireButtons.push(radio);
            yPos += 30;

            var optDesc = new TextField();
            optDesc.defaultTextFormat = new TextFormat("_typewriter", 10, 0x666666);
            optDesc.width = 360;
            optDesc.height = 20;
            optDesc.x = 45;
            optDesc.y = yPos - 18;
            optDesc.text = opt.desc;
            optDesc.selectable = false;
            addChild(optDesc);
        }
        yPos += 15;

        // Section: Stats
        var statsLabel = new TextField();
        statsLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        statsLabel.width = 380;
        statsLabel.height = 25;
        statsLabel.x = 15;
        statsLabel.y = yPos;
        statsLabel.text = "STATISTICS";
        statsLabel.selectable = false;
        addChild(statsLabel);
        yPos += 35;

        var statsDesc = new TextField();
        statsDesc.defaultTextFormat = new TextFormat("_typewriter", 11, 0xAAAAAA);
        statsDesc.width = 360;
        statsDesc.height = 100;
        statsDesc.x = 20;
        statsDesc.y = yPos;
        statsDesc.text = "Node count: --\nWire count: --\nRender mode: --\nWire type: --\nAssembly: --";
        statsDesc.selectable = false;
        statsDesc.name = "statsDisplay";
        addChild(statsDesc);
    }

    private function onAssemblyToggle(value:Bool):Void {
        _allowAssembly = value;
        if (onSettingsChanged != null) {
            onSettingsChanged();
        }
    }

    private function onEcsToggle(value:Bool):Void {
        _useEcsRender = value;
        if (onSettingsChanged != null) {
            onSettingsChanged();
        }
    }

    private function onWireTypeSelect(radio:RadioButton):Void {
        _wireType = radio.userData;
        for (r in _wireButtons) {
            r.checked = (r == radio);
        }
        if (onSettingsChanged != null) {
            onSettingsChanged();
        }
    }

    private function onCloseClick(e:MouseEvent):Void {
        visible = false;
    }

    private function get_useEcsRender():Bool {
        return _useEcsRender;
    }

    private function set_useEcsRender(v:Bool):Bool {
        _useEcsRender = v;
        if (_ecsCheckbox != null) {
            _ecsCheckbox.checked = v;
        }
        return v;
    }

    private function get_wireType():WireType {
        return _wireType;
    }

    private function set_wireType(v:WireType):WireType {
        _wireType = v;
        for (r in _wireButtons) {
            r.checked = (r.userData == v);
        }
        return v;
    }

    private function get_allowAssembly():Bool {
        return _allowAssembly;
    }

    private function set_allowAssembly(v:Bool):Bool {
        _allowAssembly = v;
        if (_assemblyCheckbox != null) {
            _assemblyCheckbox.checked = v;
        }
        return v;
    }

    /**
     * Update statistics display.
     */
    public function updateStats(nodeCount:Int, wireCount:Int, ecsMode:Bool, wire:WireType, assemblyAllowed:Bool):Void {
        var statsDisplay = cast(getChildByName("statsDisplay"), TextField);
        if (statsDisplay != null) {
            var wireName = switch(wire) {
                case WireType.BEZIER: "Bezier";
                case WireType.STRAIGHT: "Straight";
            }
            statsDisplay.text = 'Node count: $nodeCount\nWire count: $wireCount\nRender mode: ${ecsMode ? "ECS" : "Direct"}\nWire type: $wireName\nAssembly: ${assemblyAllowed ? "Allowed" : "Disabled"}';
        }
    }

    /**
     * Show panel centered on stage.
     */
    public function show(stageWidth:Float, stageHeight:Float):Void {
        x = (stageWidth - width) / 2;
        y = (stageHeight - height) / 2;
        visible = true;
    }
}

/**
 * Simple checkbox component.
 */
class Checkbox extends Sprite {

    public var checked(default, set):Bool = false;
    public var onChange:Bool -> Void = null;

    private var _box:Sprite;
    private var _check:Sprite;
    private var _label:TextField;

    public function new(labelText:String, initialValue:Bool = false) {
        super();

        checked = initialValue;

        _box = new Sprite();
        _box.graphics.beginFill(0x333344);
        _box.graphics.lineStyle(1, 0x00AAFF);
        _box.graphics.drawRect(0, 0, 20, 20);
        _box.graphics.endFill();
        addChild(_box);

        _check = new Sprite();
        _check.graphics.lineStyle(2, 0x00FF88);
        _check.graphics.moveTo(4, 10);
        _check.graphics.lineTo(8, 14);
        _check.graphics.lineTo(16, 4);
        _check.visible = checked;
        addChild(_check);

        _label = new TextField();
        _label.defaultTextFormat = new TextFormat("_typewriter", 13, 0xFFFFFF);
        _label.width = 300;
        _label.height = 22;
        _label.x = 28;
        _label.y = 0;
        _label.text = labelText;
        _label.selectable = false;
        _label.mouseEnabled = false;
        addChild(_label);

        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.CLICK, onClick);
    }

    private function onClick(e:MouseEvent):Void {
        checked = !checked;
        if (onChange != null) {
            onChange(checked);
        }
    }

    function set_checked(v:Bool):Bool {
        checked = v;
        if (_check != null) {
            _check.visible = v;
        }
        return v;
    }
}

/**
 * Radio button component.
 */
class RadioButton extends Sprite {

    public var checked(default, set):Bool = false;
    public var onSelect:RadioButton -> Void = null;
    public var userData:Dynamic = null;

    private var _outer:Sprite;
    private var _inner:Sprite;
    private var _label:TextField;

    public function new(labelText:String, initialValue:Bool = false) {
        super();

        checked = initialValue;

        _outer = new Sprite();
        _outer.graphics.beginFill(0x333344);
        _outer.graphics.lineStyle(1, 0x00AAFF);
        _outer.graphics.drawCircle(10, 10, 9);
        _outer.graphics.endFill();
        addChild(_outer);

        _inner = new Sprite();
        _inner.graphics.beginFill(0x00FF88);
        _inner.graphics.drawCircle(10, 10, 5);
        _inner.graphics.endFill();
        _inner.visible = checked;
        addChild(_inner);

        _label = new TextField();
        _label.defaultTextFormat = new TextFormat("_typewriter", 13, 0xFFFFFF);
        _label.width = 300;
        _label.height = 22;
        _label.x = 25;
        _label.y = 0;
        _label.text = labelText;
        _label.selectable = false;
        _label.mouseEnabled = false;
        addChild(_label);

        buttonMode = true;
        useHandCursor = true;
        addEventListener(MouseEvent.CLICK, onClick);
    }

    private function onClick(e:MouseEvent):Void {
        if (!checked) {
            checked = true;
            if (onSelect != null) {
                onSelect(this);
            }
        }
    }

    function set_checked(v:Bool):Bool {
        checked = v;
        if (_inner != null) {
            _inner.visible = v;
        }
        return v;
    }
}
