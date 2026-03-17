package ui;

import openfl.display.Window;
import openfl.display.Sprite;
import openfl.Lib;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.display.StageScaleMode;
import openfl.display.StageAlign;
import openfl.text.TextFieldAutoSize;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.view.DeviceView;
import core.view.DeviceWidgetFactory;
import core.logic.Impulse;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * DeviceWindow v8.4 (Force Position & Multi-Monitor)
 *
 * v8.4 Changes:
 * - FORCES window position after creation (fixes centering issue on Windows)
 * - Emits DEVICE_WINDOW_CHANGED on drag end and resize for auto-save
 */
class DeviceWindow {
    private var _window:Window;
    private var _container:Sprite;

    // Элементы UI
    private var _header:Sprite;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;
    public var deviceCanvas(default, null):Sprite;
    private var _titleLabel:TextField;

    // Логика устройств
    private var _deviceCards:Array<DeviceCard>;
    private var _impulseCallback:Impulse -> Void;

    // Коллбеки
    public var onGetAssemblyList:Void -> Array<{id:String, name:String, atom:Atom}>;
    public var onAssemblySelected:Atom -> Void;
    public var onShowEditor:Void -> Void;

    // Флаг для защиты от повторного dispose
    private var _isDisposed:Bool = false;

    // Размеры и позиция
    private var _initX:Float;
    private var _initY:Float;
    private var _initWidth:Float;
    private var _initHeight:Float;

    private static inline var DEFAULT_WIDTH:Int = 420;
    private static inline var DEFAULT_HEIGHT:Int = 320;
    private static inline var BG_COLOR:Int = 0x1a1a24;

    public function new(?initX:Float = 100, ?initY:Float = 100, ?initWidth:Float = DEFAULT_WIDTH, ?initHeight:Float = DEFAULT_HEIGHT) {
        _deviceCards = [];
        _initX = initX;
        _initY = initY;
        _initWidth = initWidth;
        _initHeight = initHeight;
        create();
    }

    private function create():Void {
        var config = {
            title: "Device Window",
            width: Std.int(_initWidth),
            height: Std.int(_initHeight),
            x: Std.int(_initX),
            y: Std.int(_initY),
            resizable: true,
            context: {
                background: BG_COLOR,
                antialiasing: 2,
                hardware: false
            }
        };

        _window = Lib.application.createWindow(config);

        if (_window != null && _window.stage != null) {
            // === FIX: Force position AFTER creation ===
            // Window managers often ignore x/y in config and center the window.
            // We explicitly move it back to the desired coordinates.
            _window.x = Std.int(_initX);
            _window.y = Std.int(_initY);
            // ========================================

            var stage = _window.stage;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            stage.color = BG_COLOR;
            stage.opaqueBackground = BG_COLOR;

            _container = new Sprite();
            stage.addChild(_container);

            _impulseCallback = onAtomDeleted;
            Impulsys.subscribeToImpulse("ATOM_DELETED", _impulseCallback);

            createHeader();
            createDeviceCanvas();
            createContextMenu();

            stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            stage.addEventListener(MouseEvent.CLICK, onStageClick);
            stage.addEventListener(Event.RESIZE, onWindowResize);

            stage.invalidate();
        } else {
            trace("Ошибка: окно или stage не созданы");
            if (_impulseCallback != null) {
                Impulsys.removeImpulse("ATOM_DELETED", _impulseCallback);
                _impulseCallback = null;
            }
        }
    }

    // =========================================================================
    // WINDOW SIZE & POSITION PERSISTENCE
    // =========================================================================

    public var windowWidth(get, never):Float;
    private function get_windowWidth():Float {
        return (_window != null) ? _window.width : _initWidth;
    }

    public var windowHeight(get, never):Float;
    private function get_windowHeight():Float {
        return (_window != null) ? _window.height : _initHeight;
    }

    public var windowX(get, never):Float;
    private function get_windowX():Float {
        return (_window != null) ? _window.x : _initX;
    }

    public var windowY(get, never):Float;
    private function get_windowY():Float {
        return (_window != null) ? _window.y : _initY;
    }

    private function onWindowResize(e:Event):Void {
        updateBackground();
        if (deviceCanvas != null && _window != null && _window.stage != null) {
            deviceCanvas.graphics.clear();
            deviceCanvas.graphics.beginFill(BG_COLOR);
            deviceCanvas.graphics.drawRect(0, 0, _window.stage.stageWidth, _window.stage.stageHeight - 30);
            deviceCanvas.graphics.endFill();
        }
        
        // Notify Main to save state
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
    // UI CREATION
    // =========================================================================

    private function createHeader():Void {
        var headerWidth = Std.int(_initWidth);
        if (_window != null && _window.stage != null) {
            headerWidth = _window.stage.stageWidth;
        }

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

        var editorBtn = createHeaderButton("E", 0x005500, function(_) {
            if (onShowEditor != null) {
                var mainWin = Lib.current.stage.window;
                if (mainWin != null) mainWin.visible = true;
            }
        });
        editorBtn.x = headerWidth - 90;
        _header.addChild(editorBtn);

        var clearBtn = createHeaderButton("C", 0x555500, function(_) clearDevices());
        clearBtn.x = headerWidth - 60;
        _header.addChild(clearBtn);

        var closeBtn = createHeaderButton("X", 0xAA0000, function(_) close());
        closeBtn.x = headerWidth - 30;
        _header.addChild(closeBtn);

        _header.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _header.buttonMode = true;

        _container.addChild(_header);
    }

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
        return btn;
    }

    private function createDeviceCanvas():Void {
        deviceCanvas = new Sprite();
        deviceCanvas.y = 30;

        var canvasHeight = Std.int(_initHeight - 30);
        if (_window != null && _window.stage != null) {
            canvasHeight = _window.stage.stageHeight - 30;
        }

        deviceCanvas.graphics.beginFill(BG_COLOR);
        deviceCanvas.graphics.drawRect(0, 0, Std.int(_initWidth), canvasHeight);
        deviceCanvas.graphics.endFill();

        _container.addChild(deviceCanvas);
    }

    private function createContextMenu():Void {
        _contextMenu = new Sprite();
        _contextMenu.visible = false;
        _container.addChild(_contextMenu);
    }

    // =========================================================================
    // DEVICE LOGIC
    // =========================================================================

    public function addDevice(atom:Atom, ?x:Float = null, ?y:Float = null, ?width:Float = null, ?height:Float = null):Void {
        if (_isDisposed) return;
        if (atom == null) return;
        if (deviceCanvas == null) return;

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

    public function removeDevice(card:DeviceCard):Void {
        if (_isDisposed) return;
        if (card == null) return;
        _deviceCards.remove(card);
        if (deviceCanvas != null && deviceCanvas.contains(card)) {
            deviceCanvas.removeChild(card);
        }
        card.dispose();
    }

    public function getDeviceCards():Array<DeviceCard> {
        return _deviceCards;
    }

    private function onAtomDeleted(impulse:Impulse):Void {
        if (_isDisposed) return;
        if (impulse == null || impulse.data == null) return;
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

    public function clearDevices():Void {
        if (_isDisposed) return;
        while (_deviceCards.length > 0) {
            var card = _deviceCards.pop();
            if (deviceCanvas != null && deviceCanvas.contains(card)) {
                deviceCanvas.removeChild(card);
            }
            card.dispose();
        }
    }

    // =========================================================================
    // CONTEXT MENU LOGIC
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

        var maxX = Std.int(_initWidth);
        var maxY = Std.int(_initHeight);
        if (_window != null && _window.stage != null) {
            maxX = _window.stage.stageWidth;
            maxY = _window.stage.stageHeight;
        }

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
    // DRAG LOGIC
    // =========================================================================

    private var _dragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;

    private function onMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;
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
        
        // Notify Main to save state (position changed)
        Impulsys.quickEmit(EventType.DEVICE_WINDOW_CHANGED);
    }

    // =========================================================================
    // CLOSE & DISPOSE
    // =========================================================================

    public function close():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        if (_impulseCallback != null) {
            Impulsys.removeImpulse("ATOM_DELETED", _impulseCallback);
            _impulseCallback = null;
        }

        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _window.stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.removeEventListener(MouseEvent.CLICK, onStageClick);
            _window.stage.removeEventListener(Event.RESIZE, onWindowResize);
        }

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

    public var isOpen(get, never):Bool;
    private function get_isOpen():Bool {
        return _window != null && !_isDisposed;
    }
}

// =========================================================================
// DEVICE CARD
// =========================================================================

class DeviceCard extends Sprite {
    public var atom(default, null):Atom;
    private var _deviceWindow:DeviceWindow;
    private var _deviceView:DeviceView;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;
    private var _cardDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;
    private var _isDisposed:Bool = false;

    public var cardWidth(default, null):Float = 100;
    public var cardHeight(default, null):Float = 80;

    public function new(atom:Atom, deviceWindow:DeviceWindow) {
        super();
        this.atom = atom;
        _deviceWindow = deviceWindow;
        buildCard();
    }

    private function buildCard():Void {
        try {
            _deviceView = DeviceWidgetFactory.create(atom);
        } catch (e:Dynamic) {
            _deviceView = null;
        }

        if (_deviceView == null) {
            createFallbackCard();
            return;
        }

        _deviceView.activate();

        var viewWidth = _deviceView.width;
        var viewHeight = _deviceView.height;

        _titleBar = new Sprite();
        _titleBar.graphics.beginFill(0x3a3a4a);
        _titleBar.graphics.drawRect(0, 0, viewWidth + 20, 20);
        _titleBar.graphics.endFill();
        addChild(_titleBar);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 10, 0xFFFFFF);
        _titleLabel.text = " " + (atom != null ? atom.name : "Device");
        _titleLabel.width = viewWidth;
        _titleLabel.height = 20;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _titleBar.addChild(_titleLabel);

        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0x883333);
        closeBtn.graphics.drawRect(0, 0, 16, 16);
        closeBtn.graphics.endFill();
        closeBtn.x = viewWidth + 2;
        closeBtn.y = 2;
        var xText = new TextField();
        xText.text = "x";
        xText.width = 16;
        xText.height = 16;
        xText.selectable = false;
        xText.mouseEnabled = false;
        xText.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF, false, null, null, null, null, "center");
        closeBtn.addChild(xText);
        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        _titleBar.addChild(closeBtn);

        _deviceView.y = 20;
        _deviceView.x = 0;
        addChild(_deviceView);

        cardWidth = viewWidth + 30;
        cardHeight = viewHeight + 30;

        graphics.clear();
        graphics.beginFill(0x2a2a3a, 0.9);
        graphics.lineStyle(1, 0x4a4a5a);
        graphics.drawRoundRect(-5, -5, cardWidth, cardHeight, 4, 4);
        graphics.endFill();

        _titleBar.buttonMode = true;
        _titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
    }

    private function createFallbackCard():Void {
        cardWidth = 80;
        cardHeight = 50;

        graphics.beginFill(0x333344);
        graphics.drawRoundRect(0, 0, cardWidth, cardHeight, 4, 4);
        graphics.endFill();
        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        txt.text = atom != null ? atom.name : "?";
        txt.width = 80;
        txt.height = 50;
        txt.selectable = false;
        txt.mouseEnabled = false;
        addChild(txt);
    }

    private function onCloseClick(e:MouseEvent):Void {
        e.stopPropagation();
        if (_deviceWindow != null) {
            _deviceWindow.removeDevice(this);
        }
    }

    private function onCardMouseDown(e:MouseEvent):Void {
        if (_isDisposed) return;
        _cardDragging = true;
        _dragStartX = this.x;
        _dragStartY = this.y;
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;
        if (parent != null) parent.addChild(this);
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
    }

    private function onCardMouseMove(e:MouseEvent):Void {
        if (!_cardDragging || _isDisposed) return;
        this.x = _dragStartX + (e.stageX - _mouseStartX);
        this.y = _dragStartY + (e.stageY - _mouseStartY);
    }

    private function onCardMouseUp(e:MouseEvent):Void {
        _cardDragging = false;
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
    }

    public function dispose():Void {
        if (_isDisposed) return;
        _isDisposed = true;

        if (_titleBar != null) {
            _titleBar.removeEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
        }

        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }

        if (_deviceView != null) {
            _deviceView.deactivate();
            _deviceView.dispose();
            _deviceView = null;
        }

        atom = null;
        _deviceWindow = null;
        _titleBar = null;
        _titleLabel = null;
    }
}