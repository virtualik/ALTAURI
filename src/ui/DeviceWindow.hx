package ui;

import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import lime.ui.Window;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import ui.ButtonComponent;

/**
 * DEVICE WINDOW v2.2 (Editor-Style Close Button)
 * Full-size device display window.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 *
 * DeviceWindow — an independent OS window containing device cards.
 * Cards (DeviceCard) are managed through DeviceViewRegistry and use
 * a single DeviceView instance for each atom.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SCHEMATIC                         DEVICE WINDOW                       │
 * │                                                                         │
 * │   ┌─────────────┐                    ┌────────────────────────────┐     │
 * │   │  NodeView   │  Double-click      │       DeviceWindow         │     │
 * │   │   (atom1)   │ ─────────────────► │   ┌────────────────────┐   │     │
 * │   │             │                    │   │   DeviceCard       │   │     │
 * │   │ [Widget]    │                    │   │ ┌────────────────┐ │   │     │
 * │   └─────────────┘                    │   │ │   DeviceView   │ │   │     │
 * │                                      │   │ │   (atom1)      │ │   │     │
 * │   Widget moved!                      │   │ └────────────────┘ │   │     │
 * │   NodeView shows                     │   └────────────────────┘   │     │
 * │   placeholder (no widget)            │                            │     │
 * │                                      │   [E] [C]          [X]     │     │
 * │                                      │                   ↑ 40x40  │     │
 * │                                      │              Editor-style  │     │
 * │                                      └────────────────────────────┘     │
 * │                                              │                          │
 * │   ◄──────────────────────────────────────────┘                          │
 * │              On close: Widget returns to registry,                      │
 * │              NodeView can re-acquire it on next activation.             │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.2 Changes:
 * - ADDED: Editor-style close button (ButtonComponent 40x40) in the same
 *   position as Main.hx: x = stageWidth - 45, y = 5 (top-right corner).
 * - REMOVED: Small header [X] button (replaced by the large one).
 * - SHIFTED: [E] and [C] buttons moved left to avoid overlap with the
 *   large close button.
 * - ADDED: Proper resize handling for close button position.
 * - ADDED: Proper cleanup in close() method.
 *
 * v2.1 Changes:
 * - FIXED: Header buttons [E], [C], [X] now stop MOUSE_DOWN propagation
 *   so they don't trigger window drag when clicked.
 * - FIXED: onMouseDown() now checks if the click target is a header button
 *   and skips drag initiation if so (defensive double-check).
 */
class DeviceWindow {
    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================
    private var _window:Window;
    private var _container:Sprite;
    private var _header:Sprite;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;
    private var _titleLabel:TextField;
    private var _deviceCards:Array<DeviceCard>;
    private var _impulseCallback:Impulse -> Void;
    private var _isDisposed:Bool = false;

    // Drag state for window header
    private var _dragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;

    // Cached dimensions (used for persistence)
    private var _initX:Float;
    private var _initY:Float;
    private var _initWidth:Float;
    private var _initHeight:Float;

    // =========================================================================
    // v2.2: EDITOR-STYLE CLOSE BUTTON
    // =========================================================================
    /**
     * Large close button (40x40) in the top-right corner.
     * Same style and position as Main.hx _btnClose.
     */
    private var _btnClose:ButtonComponent;

    // =========================================================================
    // PUBLIC PROPERTIES
    // =========================================================================
    public var deviceCanvas(default, null):Sprite;
    public var onGetAssemblyList:Void -> Array<{id:String, name:String, atom:Atom}>;
    public var onAssemblySelected:Atom -> Void;
    public var onShowEditor:Void -> Void;

    public var windowWidth(get, never):Float;
    private function get_windowWidth():Float return (_window != null) ? _window.width : _initWidth;

    public var windowHeight(get, never):Float;
    private function get_windowHeight():Float return (_window != null) ? _window.height : _initHeight;

    public var windowX(get, never):Float;
    private function get_windowX():Float return (_window != null) ? _window.x : _initX;

    public var windowY(get, never):Float;
    private function get_windowY():Float return (_window != null) ? _window.y : _initY;

    public var isOpen(get, never):Bool;
    private function get_isOpen():Bool return _window != null && !_isDisposed;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(?initX:Float = 100, ?initY:Float = 100, ?initWidth:Float = 420, ?initHeight:Float = 320) {
        _deviceCards = [];
        _initX = initX;
        _initY = initY;
        _initWidth = initWidth;
        _initHeight = initHeight;
        create();
    }

    // =========================================================================
    // WINDOW CREATION
    // =========================================================================
    private function create():Void {
        var config = {
            title: "Device Window",
            width: Std.int(_initWidth),
            height: Std.int(_initHeight),
            x: Std.int(_initX),
            y: Std.int(_initY),
            resizable: true,
            context: {
                background: 0x1a1a24,
                antialiasing: 0,
                borderless: true,
                hardware: false
            }
        };

        _window = Lib.application.createWindow(config);
        if (_window == null || _window.stage == null) {
            trace("DeviceWindow: Failed to create window");
            if (_impulseCallback != null) {
                Impulsys.removeImpulse(EventType.ATOM_DELETED, _impulseCallback);
                _impulseCallback = null;
            }
            return;
        }

        // Force position (window managers sometimes ignore config)
        _window.x = Std.int(_initX);
        _window.y = Std.int(_initY);

        var stage = _window.stage;
        stage.scaleMode = StageScaleMode.NO_SCALE;
        stage.align = StageAlign.TOP_LEFT;
        stage.color = 0x1a1a24;
        stage.opaqueBackground = 0x1a1a24;

        _container = new Sprite();
        stage.addChild(_container);

        _impulseCallback = onAtomDeleted;
        Impulsys.subscribeToImpulse(EventType.ATOM_DELETED, _impulseCallback);

        createHeader();
        createDeviceCanvas();
        createContextMenu();

        // =========================================================================
        // v2.2: CREATE EDITOR-STYLE CLOSE BUTTON
        // =========================================================================
        // Same position as Main.hx: x = stageWidth - 45, y = 5
        // Added to _container (not _header) so it sits on top of everything.
        var headerWidth = (_window != null && _window.stage != null) ? _window.stage.stageWidth : Std.int(_initWidth);
        _btnClose = new ButtonComponent("X", close);
        _btnClose.x = headerWidth - 45;
        _btnClose.y = 5;
        _container.addChild(_btnClose);
        // =========================================================================

        stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
        stage.addEventListener(MouseEvent.CLICK, onStageClick);
        stage.addEventListener(Event.RESIZE, onWindowResize);
        stage.invalidate();
    }

    // =========================================================================
    // UI CREATION
    // =========================================================================
    private function createHeader():Void {
        var headerWidth = (_window != null && _window.stage != null) ? _window.stage.stageWidth : Std.int(_initWidth);

        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, headerWidth, 30);
        _header.graphics.endFill();

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "  Device (Right-Click to Add)";
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // =========================================================================
        // v2.2: SHIFTED BUTTONS — moved left to avoid overlap with large [X]
        // Large close button occupies x: headerWidth-45 .. headerWidth-5
        // [C] button: headerWidth-90 .. headerWidth-62 (safe gap)
        // [E] button: headerWidth-120 .. headerWidth-92 (safe gap)
        // =========================================================================
        var editorBtn = createHeaderButton("E", 0x005500, function(_) {
            if (onShowEditor != null) onShowEditor();
        });
        editorBtn.x = headerWidth - 120;  // v2.2: shifted from -90
        _header.addChild(editorBtn);

        var clearBtn = createHeaderButton("C", 0x555500, function(_) clearDevices());
        clearBtn.x = headerWidth - 90;    // v2.2: shifted from -60
        _header.addChild(clearBtn);

        // v2.2: REMOVED small [X] button — replaced by large ButtonComponent
        // var closeBtn = createHeaderButton("X", 0xAA0000, function(_) close());
        // closeBtn.x = headerWidth - 30;
        // _header.addChild(closeBtn);

        _header.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _header.buttonMode = true;
        _container.addChild(_header);
    }

    /**
     * BUG 1 FIX: Header buttons now stop MOUSE_DOWN propagation.
     * This prevents the MOUSE_DOWN event from bubbling up from the button
     * to the _header, which would start an unwanted window drag.
     */
    private function createHeaderButton(label:String, color:Int, onClick:MouseEvent->Void):Sprite {
        var btn = new Sprite();
        btn.graphics.beginFill(color);
        btn.graphics.drawRect(0, 0, 28, 26);
        btn.graphics.endFill();

        var txt = new TextField();
        txt.text = label;
        txt.width = 28;
        txt.height = 26;
        txt.selectable = false;
        txt.mouseEnabled = false;
        txt.defaultTextFormat = new TextFormat("_sans", 11, 0xFFFFFF, true, null, null, null, null, "center");
        btn.addChild(txt);

        btn.buttonMode = true;
        btn.addEventListener(MouseEvent.CLICK, onClick);

        // === BUG 1 FIX: Stop MOUSE_DOWN from propagating to header ===
        // Without this, clicking the button would also trigger onMouseDown()
        // on the header, starting an unwanted window drag.
        btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());

        return btn;
    }

    private function createDeviceCanvas():Void {
        deviceCanvas = new Sprite();
        deviceCanvas.y = 30;
        var canvasHeight = (_window != null && _window.stage != null) ? _window.stage.stageHeight - 30 : Std.int(_initHeight - 30);
        deviceCanvas.graphics.beginFill(0x1a1a24);
        deviceCanvas.graphics.drawRect(0, 0, (_window != null ? _window.stage.stageWidth : _initWidth), canvasHeight);
        deviceCanvas.graphics.endFill();
        _container.addChild(deviceCanvas);
    }

    private function createContextMenu():Void {
        _contextMenu = new Sprite();
        _contextMenu.visible = false;
        _container.addChild(_contextMenu);
    }

    // =========================================================================
    // DEVICE MANAGEMENT
    // =========================================================================
    /**
     * Add a device (atom) to the window. Creates a DeviceCard that will
     * obtain the widget from the registry.
     *
     * @param atom  The atom to display
     * @param x     Desired X position in the canvas (optional)
     * @param y     Desired Y position in the canvas (optional)
     */
    public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null):Void {
        if (_isDisposed || atom == null || deviceCanvas == null) return;

        // Avoid duplicates
        for (card in _deviceCards) {
            if (card.atom == atom) return;
        }

        var card = new DeviceCard(atom, this);
        _deviceCards.push(card);
        deviceCanvas.addChild(card);

        if (x != null && y != null) {
            card.x = x;
            card.y = y;
        } else {
            var pos = findFreePosition(card);
            card.x = pos.x;
            card.y = pos.y;
        }
        trace('DeviceWindow: Added device "${atom.name}" at (${card.x}, ${card.y})');
    }

    /**
     * Remove a device card from the window.
     */
    public function removeDevice(card:DeviceCard):Void {
        if (_isDisposed || card == null) return;
        _deviceCards.remove(card);
        if (deviceCanvas != null && deviceCanvas.contains(card)) {
            deviceCanvas.removeChild(card);
        }
        card.dispose();
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    /**
     * Remove all devices from the window.
     */
    public function clearDevices():Void {
        while (_deviceCards.length > 0) {
            var card = _deviceCards.pop();
            if (deviceCanvas != null && deviceCanvas.contains(card)) {
                deviceCanvas.removeChild(card);
            }
            card.dispose();
        }
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    /**
     * Get all current device cards.
     */
    public function getDeviceCards():Array<DeviceCard> {
        return _deviceCards;
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    private function onAtomDeleted(impulse:Impulse):Void {
        if (_isDisposed || impulse == null || impulse.data == null) return;
        var deletedId:String = impulse.data.id;
        var toRemove:Array<DeviceCard> = [];
        for (card in _deviceCards) {
            if (card.atom != null && card.atom.id == deletedId) {
                toRemove.push(card);
            }
        }
        for (card in toRemove) {
            removeDevice(card);
        }
    }

    private function onWindowResize(e:Event):Void {
        updateBackground();
        if (deviceCanvas != null && _window != null && _window.stage != null) {
            deviceCanvas.graphics.clear();
            deviceCanvas.graphics.beginFill(0x1a1a24);
            deviceCanvas.graphics.drawRect(0, 0, _window.stage.stageWidth, _window.stage.stageHeight - 30);
            deviceCanvas.graphics.endFill();
        }

        // =========================================================================
        // v2.2: REPOSITION CLOSE BUTTON ON RESIZE
        // =========================================================================
        // Keep the close button in the same position as Main.hx:
        // x = stageWidth - 45, y = 5
        if (_btnClose != null && _window != null && _window.stage != null) {
            _btnClose.x = _window.stage.stageWidth - 45;
            _btnClose.y = 5;
        }
        // =========================================================================

        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    private function updateBackground():Void {
        if (_container != null && _window != null && _window.stage != null && _header != null) {
            var newWidth = _window.stage.stageWidth;
            _header.graphics.clear();
            _header.graphics.beginFill(0x2a2a34);
            _header.graphics.drawRect(0, 0, newWidth, 30);
            _header.graphics.endFill();
        }
    }

    // =========================================================================
    // WINDOW DRAG (header)
    // =========================================================================
    /**
     * BUG 1 FIX: Added target check to skip drag if the user clicked
     * on a header button child. Even though buttons now stopPropagation
     * on MOUSE_DOWN, this defensive check ensures that if somehow the
     * event still reaches this handler, we don't start a drag.
     */
    private function onMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;

        // === BUG 1 FIX: Check if click target is inside a header button ===
        // Walk up from the click target. If we find a child of _header that
        // has buttonMode=true (one of the [E]/[C]/[X] buttons), skip drag.
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != _header) {
            if (Std.isOfType(targetObj, Sprite)) {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == _header) {
                    // Clicked on a header button — do not start drag
                    return;
                }
            }
            targetObj = targetObj.parent;
        }

        _dragging = true;
        _dragOffsetX = e.localX;
        _dragOffsetY = e.localY;
        _window.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        _window.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_isDisposed || !_dragging) return;
        if (_window != null) {
            _window.x = Std.int(_window.x + (e.stageX - _dragOffsetX));
            _window.y = Std.int(_window.y + (e.stageY - _dragOffsetY));
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        _dragging = false;
        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    // =========================================================================
    // CONTEXT MENU
    // =========================================================================
    private function onRightClick(e:MouseEvent):Void {
        if (_isDisposed) return;
        e.stopPropagation();
        showContextMenu(e.stageX, e.stageY);
    }

    private function onStageClick(e:MouseEvent):Void {
        if (_isDisposed) return;
        if (_menuVisible) hideContextMenu();
    }

    private function showContextMenu(x:Float, y:Float):Void {
        while (_contextMenu.numChildren > 0) _contextMenu.removeChildAt(0);

        var devices = (onGetAssemblyList != null) ? onGetAssemblyList() : [];
        devices = [for (d in devices) if (d.id != "selfrun") d];

        var yPos = 0;

        var headerItem = createMenuItem("Add Device:", null, true);
        headerItem.y = yPos;
        _contextMenu.addChild(headerItem);
        yPos += 28;

        var sep = new Sprite();
        sep.graphics.lineStyle(1, 0x444455);
        sep.graphics.moveTo(0, 0);
        sep.graphics.lineTo(180, 0);
        sep.y = yPos;
        _contextMenu.addChild(sep);
        yPos += 8;

        if (devices.length == 0) {
            var emptyItem = createMenuItem("(No devices available)", null, true);
            emptyItem.y = yPos;
            _contextMenu.addChild(emptyItem);
            yPos += 26;
        } else {
            for (item in devices) {
                var menuItem = createMenuItem(item.name, item.atom, false);
                menuItem.y = yPos;
                _contextMenu.addChild(menuItem);
                yPos += 26;
            }
        }

        _contextMenu.graphics.clear();
        _contextMenu.graphics.beginFill(0x333344, 0.98);
        _contextMenu.graphics.lineStyle(1, 0x555566);
        _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 4, 6, 6);
        _contextMenu.graphics.endFill();

        var maxX = (_window != null && _window.stage != null) ? _window.stage.stageWidth : _initWidth;
        var maxY = (_window != null && _window.stage != null) ? _window.stage.stageHeight : _initHeight;
        _contextMenu.x = Math.min(x, maxX - 200);
        _contextMenu.y = Math.min(Math.max(y - 30, 0), maxY - yPos - 10);

        _menuVisible = true;
        _contextMenu.visible = true;
    }

    private function hideContextMenu():Void {
        _menuVisible = false;
        _contextMenu.visible = false;
    }

    private function createMenuItem(label:String, atom:Atom, disabled:Bool):Sprite {
        var item = new Sprite();
        item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
        item.graphics.drawRect(0, 0, 180, 24);
        item.graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
        txt.text = (disabled || atom == null) ? label : "+ " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);

        if (!disabled && atom != null) {
            item.buttonMode = true;
            final capturedAtom = atom;
            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
                addDevice(capturedAtom);
                if (onAssemblySelected != null) onAssemblySelected(capturedAtom);
                hideContextMenu();
            });
            item.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) {
                item.graphics.clear();
                item.graphics.beginFill(0x556677);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
            item.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) {
                item.graphics.clear();
                item.graphics.beginFill(0x444455);
                item.graphics.drawRect(0, 0, 180, 24);
                item.graphics.endFill();
            });
        }

        return item;
    }

    // =========================================================================
    // UTILITY
    // =========================================================================
    private function findFreePosition(card:DeviceCard):{x:Float, y:Float} {
        var startX = 10;
        var startY = 10;
        var stepX = 120;
        var stepY = 100;

        for (y in 0...3) {
            for (x in 0...4) {
                var px = startX + x * stepX;
                var py = startY + y * stepY;
                if (isPositionFree(px, py)) return {x: px, y: py};
            }
        }
        return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
    }

    private function isPositionFree(x:Float, y:Float):Bool {
        for (card in _deviceCards) {
            if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) return false;
        }
        return true;
    }

    // =========================================================================
    // CLOSE & DISPOSE
    // =========================================================================
    public function close():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        if (_impulseCallback != null) {
            Impulsys.removeImpulse(EventType.ATOM_DELETED, _impulseCallback);
            _impulseCallback = null;
        }

        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _window.stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.removeEventListener(MouseEvent.CLICK, onStageClick);
            _window.stage.removeEventListener(Event.RESIZE, onWindowResize);
        }

        // =========================================================================
        // v2.2: CLEANUP CLOSE BUTTON
        // =========================================================================
        if (_btnClose != null) {
            if (_btnClose.parent != null) {
                _btnClose.parent.removeChild(_btnClose);
            }
            _btnClose = null;
        }
        // =========================================================================

        clearDevices();
        deviceCanvas = null;
        _contextMenu = null;
        _container = null;

        if (_window != null) {
            _window.close();
            _window = null;
        }

        onGetAssemblyList = null;
        onAssemblySelected = null;
        onShowEditor = null;
    }
}