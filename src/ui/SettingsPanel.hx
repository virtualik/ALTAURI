package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;
import ui.contextmenu.SidebarPosition;
import ui.NodeVisualMode;

/**
 * SETTINGS PANEL v1.7
 *
 * Fixes vs v1.6:
 *   - Panel height is now adaptive: capped to 680 but never exceeds
 *     (stageHeight - 40). Prevents the panel from sliding off-screen
 *     on short windows (the "Back button disappeared" bug).
 *   - Scroll is performed ONLY via scrollRect; _scrollContainer.y stays
 *     constant at 60. Eliminates the double-scroll artifact and the
 *     growing black gap below the content.
 *   - Back button compacted to 70x22, font 11px bold.
 *   - Added onStageResize() for repainting panel + dimmer on RESIZE.
 *   - _maxScrollY is recomputed inside updateScrollRect() against
 *     the real content bounds, so it stays correct after any change.
 */
class SettingsPanel extends Sprite
{
    private var _bg:Sprite;
    private var _title:TextField;
    private var _closeBtn:Sprite;

    private var _dimmer:Sprite;
    private var _scrollContainer:Sprite;

    private var _scrollY:Float = 0;
    private var _maxScrollY:Float = 0;
    private var _scrollStep:Float = 20.0;

    // Stage dimensions and panel height remembered by show(); used by
    // onStageResize() and updateScrollRect() so they never read stale values.
    private var _stageW:Float = 0;
    private var _stageH:Float = 0;
    private var _panelH:Float = 680;

    // Fixed panel width. Kept as a constant so drawBackground(), show() and
    // updateScrollRect() never disagree.
    private static inline var PANEL_W:Float = 400;
    // Maximum panel height on a tall stage. Shorter stages clamp lower.
    private static inline var PANEL_H_MAX:Float = 680;
    // Header band height (title + back button row).
    private static inline var HEADER_H:Float = 60;
    // Bottom inner padding inside the panel.
    private static inline var FOOTER_PAD:Float = 15;

    public var useEcsRender(get, set):Bool;
    private var _useEcsRender:Bool = true;

    public var wireType(get, set):WireType;
    private var _wireType:WireType = WireType.BEZIER;

    public var allowAssembly(get, set):Bool;
    private var _allowAssembly:Bool = true;

    public var contextMenuSidebarPosition(get, set):SidebarPosition;
    private var _contextMenuSidebarPosition:SidebarPosition = SidebarPosition.LEFT;
    private var _contextMenuRadioButtons:Array<RadioButton> = [];

    public var nodeVisualMode(get, set):NodeVisualMode;
    private var _nodeVisualMode:NodeVisualMode = NodeVisualMode.HEAVY;
    private var _visualModeButtons:Array<RadioButton> = [];

    private function get_nodeVisualMode():NodeVisualMode {
        return _nodeVisualMode;
    }

    private function set_nodeVisualMode(v:NodeVisualMode):NodeVisualMode {
        _nodeVisualMode = v;
        for (r in _visualModeButtons) {
            r.checked = (r.userData == v);
        }
        if (onSettingsChanged != null) {
            onSettingsChanged();
        }
        core.logic.Impulsys.quickEmit(core.logic.EventType.NODE_VISUAL_MODE_CHANGED, { mode: v });
        return v;
    }

    public var onSettingsChanged:Void -> Void = null;

    private var _ecsCheckbox:Checkbox;
    private var _assemblyCheckbox:Checkbox;
    private var _wireButtons:Array<RadioButton> = [];

    private function get_contextMenuSidebarPosition():SidebarPosition
    {
        return _contextMenuSidebarPosition;
    }

    private function set_contextMenuSidebarPosition(v:SidebarPosition):SidebarPosition
    {
        _contextMenuSidebarPosition = v;
        for (r in _contextMenuRadioButtons)
        {
            r.checked = (r.userData == v);
        }
        return v;
    }

    public function new()
    {
        super();

        _dimmer = new Sprite();
        _dimmer.mouseEnabled = true;
        addChildAt(_dimmer, 0);

        // Initial paint at max height; show() will resize to actual stage.
        drawBackground(PANEL_H_MAX);
        createTitle();
        createCloseButton();

        _scrollContainer = new Sprite();
        _scrollContainer.x = 0;
        _scrollContainer.y = HEADER_H;
        addChild(_scrollContainer);

        mouseEnabled = true;
        addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

        createSettings();
    }

    /**
     * Draw the rounded panel background. Height is parameterised because
     * show() repaints with an adaptive height when the stage is short.
     */
    private function drawBackground(panelH:Float):Void
    {
        _bg = new Sprite();
        _bg.graphics.beginFill(0x1a1a24, 0.98);
        _bg.graphics.lineStyle(2, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, PANEL_W, panelH, 15, 15);
        _bg.graphics.endFill();
        addChild(_bg);
    }

    private function createTitle():Void
    {
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

    /**
     * Compact Back button: 70x22, bold 11px label.
     * Positioned at the right end of the header band.
     */
    private function createCloseButton():Void
    {
        _closeBtn = new Sprite();
        _closeBtn.graphics.beginFill(0xAA0000);
        _closeBtn.graphics.drawRoundRect(0, 0, 70, 22, 4, 4);
        _closeBtn.graphics.endFill();
        _closeBtn.x = 320;  // PANEL_W - 70 - 10
        _closeBtn.y = 18;
        _closeBtn.buttonMode = true;
        _closeBtn.useHandCursor = true;

        var label = new TextField();
        label.defaultTextFormat = new TextFormat("_typewriter", 11, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
        label.width = 70;
        label.height = 22;
        label.text = "< Back";
        label.selectable = false;
        label.mouseEnabled = false;
        _closeBtn.addChild(label);

        _closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        addChild(_closeBtn);
    }

    private function createSettings():Void
    {
        var yPos = 0;

        var sectionLabel = new TextField();
        sectionLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        sectionLabel.width = 380;
        sectionLabel.height = 25;
        sectionLabel.x = 15;
        sectionLabel.y = yPos;
        sectionLabel.text = "EDITOR";
        sectionLabel.selectable = false;
        _scrollContainer.addChild(sectionLabel);
        yPos += 35;

        _assemblyCheckbox = new Checkbox("Allow Assembly", _allowAssembly);
        _assemblyCheckbox.x = 20;
        _assemblyCheckbox.y = yPos;
        _assemblyCheckbox.onChange = onAssemblyToggle;
        _scrollContainer.addChild(_assemblyCheckbox);
        yPos += 40;

        var descAssembly = new TextField();
        descAssembly.defaultTextFormat = new TextFormat("_typewriter", 11, 0x888888);
        descAssembly.width = 360;
        descAssembly.height = 100;
        descAssembly.x = 20;
        descAssembly.y = yPos;
        descAssembly.text = "When enabled:\n- 'New Assembly' button is visible\n- 'Group to Assembly' in context menu\n- Double-click to enter nested assemblies";
        descAssembly.selectable = false;
        _scrollContainer.addChild(descAssembly);
        yPos += 100;

        var perfLabel = new TextField();
        perfLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        perfLabel.width = 380;
        perfLabel.height = 25;
        perfLabel.x = 15;
        perfLabel.y = yPos;
        perfLabel.text = "PERFORMANCE";
        perfLabel.selectable = false;
        _scrollContainer.addChild(perfLabel);
        yPos += 35;

        _ecsCheckbox = new Checkbox("Use ECS Rendering", _useEcsRender);
        _ecsCheckbox.x = 20;
        _ecsCheckbox.y = yPos;
        _ecsCheckbox.onChange = onEcsToggle;
        _ecsCheckbox.alpha = 0.4;
        _ecsCheckbox.mouseEnabled = false;
        _ecsCheckbox.mouseChildren = false;
        _scrollContainer.addChild(_ecsCheckbox);
        yPos += 40;

        var desc = new TextField();
        desc.defaultTextFormat = new TextFormat("_typewriter", 11, 0x888888);
        desc.width = 360;
        desc.height = 45;
        desc.x = 20;
        desc.y = yPos;
        desc.text = "ECS mode uses centralized RenderSystem for\nbatch updates. Disable for direct sprite\nmanipulation (legacy mode).";
        desc.selectable = false;
        desc.alpha = 0.4;
        _scrollContainer.addChild(desc);
        yPos += 60;

        var wireSection = new TextField();
        wireSection.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        wireSection.width = 380;
        wireSection.height = 25;
        wireSection.x = 15;
        wireSection.y = yPos;
        wireSection.text = "WIRE TYPE";
        wireSection.selectable = false;
        _scrollContainer.addChild(wireSection);
        yPos += 35;

        var wireOptions = [
            { label: "Bezier Curve", type: WireType.BEZIER, desc: "Smooth curved lines" },
            { label: "Straight Line", type: WireType.STRAIGHT, desc: "Horizontal tails + direct line" }
        ];

        for (opt in wireOptions)
        {
            var radio = new RadioButton(opt.label, _wireType == opt.type);
            radio.x = 20;
            radio.y = yPos;
            radio.userData = opt.type;
            radio.onSelect = onWireTypeSelect;
            _scrollContainer.addChild(radio);
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
            _scrollContainer.addChild(optDesc);
        }
        yPos += 15;

        var contextMenuSection = new TextField();
        contextMenuSection.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        contextMenuSection.width = 380;
        contextMenuSection.height = 25;
        contextMenuSection.x = 15;
        contextMenuSection.y = yPos;
        contextMenuSection.text = "CONTEXT MENU";
        contextMenuSection.selectable = false;
        _scrollContainer.addChild(contextMenuSection);
        yPos += 35;

        var sidebarOptions = [
            { label: "Sidebar Left", position: SidebarPosition.LEFT, desc: "Categories on left side" },
            { label: "Sidebar Right", position: SidebarPosition.RIGHT, desc: "Categories on right side" }
        ];

        for (opt in sidebarOptions)
        {
            var radio = new RadioButton(opt.label, _contextMenuSidebarPosition == opt.position);
            radio.x = 20;
            radio.y = yPos;
            radio.userData = opt.position;
            radio.onSelect = onContextMenuSidebarSelect;
            _scrollContainer.addChild(radio);
            _contextMenuRadioButtons.push(radio);
            yPos += 30;

            var optDesc = new TextField();
            optDesc.defaultTextFormat = new TextFormat("_typewriter", 10, 0x666666);
            optDesc.width = 360;
            optDesc.height = 20;
            optDesc.x = 45;
            optDesc.y = yPos - 18;
            optDesc.text = opt.desc;
            optDesc.selectable = false;
            _scrollContainer.addChild(optDesc);
        }
        yPos += 15;

        var visSection = new TextField();
        visSection.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        visSection.width = 380;
        visSection.height = 25;
        visSection.x = 15;
        visSection.y = yPos;
        visSection.text = "VISUALIZATION";
        visSection.selectable = false;
        _scrollContainer.addChild(visSection);
        yPos += 35;

        var visOptions = [
            { label: "Light (Ports Only)", mode: NodeVisualMode.LIGHT, desc: "Minimalist, best for complex schemas" },
            { label: "Medium (Inline Editors)", mode: NodeVisualMode.MEDIUM, desc: "Ports + inline parameter editors" },
            { label: "Heavy (Full Detail)", mode: NodeVisualMode.HEAVY, desc: "Ports + inline editors + widget preview" }
        ];

        for (opt in visOptions)
        {
            var radio = new RadioButton(opt.label, _nodeVisualMode == opt.mode);
            radio.x = 20;
            radio.y = yPos;
            radio.userData = opt.mode;
            radio.onSelect = onNodeVisualModeSelect;
            _scrollContainer.addChild(radio);
            _visualModeButtons.push(radio);
            yPos += 30;

            var optDesc = new TextField();
            optDesc.defaultTextFormat = new TextFormat("_typewriter", 10, 0x666666);
            optDesc.width = 360;
            optDesc.height = 20;
            optDesc.x = 45;
            optDesc.y = yPos - 18;
            optDesc.text = opt.desc;
            optDesc.selectable = false;
            _scrollContainer.addChild(optDesc);
        }
        yPos += 25;

        var statsLabel = new TextField();
        statsLabel.defaultTextFormat = new TextFormat("_typewriter", 14, 0x00AAFF, true);
        statsLabel.width = 380;
        statsLabel.height = 25;
        statsLabel.x = 15;
        statsLabel.y = yPos;
        statsLabel.text = "STATISTICS";
        statsLabel.selectable = false;
        _scrollContainer.addChild(statsLabel);
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
        _scrollContainer.addChild(statsDesc);
        yPos += 120;

        // Initial estimate; updateScrollRect() will recompute against real bounds.
        _maxScrollY = Math.max(0, yPos - 500);
    }

    private function onAssemblyToggle(value:Bool):Void
    {
        _allowAssembly = value;
        if (onSettingsChanged != null) onSettingsChanged();
    }

    private function onEcsToggle(value:Bool):Void
    {
        _useEcsRender = value;
        if (onSettingsChanged != null) onSettingsChanged();
    }

    private function onWireTypeSelect(radio:RadioButton):Void
    {
        _wireType = radio.userData;
        for (r in _wireButtons)
        {
            r.checked = (r == radio);
        }
        if (onSettingsChanged != null) onSettingsChanged();
    }

    /**
     * Scroll by wheel. Only scrollRect moves; _scrollContainer.y stays
     * at HEADER_H. This was the root cause of the "content crawling
     * upward and a black panel growing below" artifact in v1.6.
     */
    private function onMouseWheel(e:MouseEvent):Void
    {
        e.stopPropagation();
        _scrollY -= e.delta * _scrollStep;
        if (_scrollY < 0) _scrollY = 0;
        if (_scrollY > _maxScrollY) _scrollY = _maxScrollY;
        updateScrollRect();
    }

    /**
     * Recompute the scroll viewport. The visible height is derived from
     * the current panel height, and _maxScrollY is recomputed against
     * the actual content bounds so the last item is always reachable
     * and never scrolls past the panel bottom.
     */
    private function updateScrollRect():Void
    {
        var visibleHeight:Float = (_panelH > 0 ? _panelH : PANEL_H_MAX) - HEADER_H - FOOTER_PAD;

        var contentH:Float = 0;
        for (i in 0..._scrollContainer.numChildren) {
            var ch = _scrollContainer.getChildAt(i);
            var bottom:Float = ch.y + ch.height;
            if (bottom > contentH) contentH = bottom;
        }
        _maxScrollY = Math.max(0, contentH - visibleHeight);
        if (_scrollY > _maxScrollY) _scrollY = _maxScrollY;
        if (_scrollY < 0) _scrollY = 0;

        _scrollContainer.scrollRect = new Rectangle(0, _scrollY, PANEL_W, visibleHeight);
    }

    private function onContextMenuSidebarSelect(radio:RadioButton):Void
    {
        _contextMenuSidebarPosition = radio.userData;
        for (r in _contextMenuRadioButtons)
        {
            r.checked = (r == radio);
        }
        if (onSettingsChanged != null) onSettingsChanged();
    }

    private function onNodeVisualModeSelect(radio:RadioButton):Void {
        nodeVisualMode = radio.userData;
    }

    private function onCloseClick(e:MouseEvent):Void
    {
        visible = false;
    }

    private function get_useEcsRender():Bool { return _useEcsRender; }
    private function set_useEcsRender(v:Bool):Bool
    {
        _useEcsRender = v;
        if (_ecsCheckbox != null) _ecsCheckbox.checked = v;
        return v;
    }

    private function get_wireType():WireType { return _wireType; }
    private function set_wireType(v:WireType):WireType
    {
        _wireType = v;
        for (r in _wireButtons) r.checked = (r.userData == v);
        return v;
    }

    private function get_allowAssembly():Bool { return _allowAssembly; }
    private function set_allowAssembly(v:Bool):Bool
    {
        _allowAssembly = v;
        if (_assemblyCheckbox != null) _assemblyCheckbox.checked = v;
        return v;
    }

    public function updateStats(nodeCount:Int, wireCount:Int, ecsMode:Bool, wire:WireType, assemblyAllowed:Bool):Void
    {
        // Search both _scrollContainer and self: v1.6 attached statsDisplay
        // to _scrollContainer but earlier code occasionally looked it up on self.
        var statsDisplay = cast(_scrollContainer.getChildByName("statsDisplay"), TextField);
        if (statsDisplay == null) {
            statsDisplay = cast(getChildByName("statsDisplay"), TextField);
        }
        if (statsDisplay != null)
        {
            var wireName = switch (wire) {
                case WireType.BEZIER: "Bezier";
                case WireType.STRAIGHT: "Straight";
            }
            statsDisplay.text = 'Node count: $nodeCount\nWire count: $wireCount\nRender mode: ${ecsMode ? "ECS" : "Direct"}\nWire type: $wireName\nAssembly: ${assemblyAllowed ? "Allowed" : "Disabled"}';
        }
    }

    /**
     * Show the panel centered on the stage.
     *
     * The panel height is clamped to (stageHeight - 40) so the header
     * (and therefore the Back button) is always visible even on short
     * windows. The background sprite is repainted at the chosen height
     * so the rounded border matches the content area exactly.
     */
    public function show(stageWidth:Float, stageHeight:Float):Void
    {
        var panelH:Float = Math.min(PANEL_H_MAX, stageHeight - 40);
        if (panelH < 200) panelH = 200;  // hard floor

        // Repaint background at adaptive height.
        _bg.graphics.clear();
        _bg.graphics.beginFill(0x1a1a24, 0.98);
        _bg.graphics.lineStyle(2, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, PANEL_W, panelH, 15, 15);
        _bg.graphics.endFill();

        // Center horizontally; clamp Y so the panel never slides off the top.
        x = (stageWidth - PANEL_W) / 2;
        y = Math.max(20, (stageHeight - panelH) / 2);

        // Dimmer covers the whole stage (in stage coordinates, hence -x/-y).
        _dimmer.graphics.clear();
        _dimmer.graphics.beginFill(0x000000, 0.5);
        _dimmer.graphics.drawRect(-x, -y, stageWidth, stageHeight);
        _dimmer.graphics.endFill();

        // Remember for onStageResize() and updateScrollRect().
        _stageW = stageWidth;
        _stageH = stageHeight;
        _panelH = panelH;

        // Reset scroll state.
        _scrollY = 0;
        _scrollContainer.y = HEADER_H;   // constant; never move the container
        updateScrollRect();

        visible = true;
    }

    /**
     * Called by Main on Event.RESIZE. Repositions the panel and refreshes
     * the scroll viewport against the new stage dimensions. No-op when
     * the panel is currently hidden.
     */
    public function onStageResize(stageWidth:Float, stageHeight:Float):Void
    {
        if (!visible) return;
        show(stageWidth, stageHeight);
    }

    /**
     * Dispose panel and clean up listeners.
     */
    public function dispose():Void
    {
        removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
    }
}

class Checkbox extends Sprite
{
    public var checked(default, set):Bool = false;
    public var onChange:Bool -> Void = null;

    private var _box:Sprite;
    private var _check:Sprite;
    private var _label:TextField;

    public function new(labelText:String, initialValue:Bool = false)
    {
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

    private function onClick(e:MouseEvent):Void
    {
        checked = !checked;
        if (onChange != null) onChange(checked);
    }

    function set_checked(v:Bool):Bool
    {
        checked = v;
        if (_check != null) _check.visible = v;
        return v;
    }
}

class RadioButton extends Sprite
{
    public var checked(default, set):Bool = false;
    public var onSelect:RadioButton -> Void = null;
    public var userData:Dynamic = null;

    private var _outer:Sprite;
    private var _inner:Sprite;
    private var _label:TextField;

    public function new(labelText:String, initialValue:Bool = false)
    {
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

    private function onClick(e:MouseEvent):Void
    {
        if (!checked)
        {
            checked = true;
            if (onSelect != null) onSelect(this);
        }
    }

    function set_checked(v:Bool):Bool
    {
        checked = v;
        if (_inner != null) _inner.visible = v;
        return v;
    }
}
