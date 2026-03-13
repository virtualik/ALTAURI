package ui;

import openfl.display.Window;
import openfl.display.Sprite;
import openfl.Lib;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import core.base.Assembly;
import core.base.Atom;
import core.view.DeviceView;
import core.view.DeviceWidgetFactory;
import core.logic.Impulse;
import core.logic.Impulsys;

/**
 * DeviceWindow v4.1 (State Save/Load Support)
 */
class DeviceWindow {

    private var _window:Window;
    private var _header:Sprite;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;

    public var deviceCanvas(default, null):Sprite;
    private var _deviceCards:Array<DeviceCard>;

    private var _impulseCallback:Impulse -> Void;

    public var onGetAssemblyList:Void -> Array<{id:String, name:String, assembly:Assembly}>;
    public var onAssemblySelected:Assembly -> Void;

    private var _titleLabel:TextField;

    public function new() {
        _deviceCards = [];
        create();
    }

    public function addDevice(asm:Assembly, ?x:Float = null, ?y:Float = null):Void {
        if (asm == null) return;
        if (deviceCanvas == null) return;

        var card = new DeviceCard(asm, this);
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
    }

    public function removeDevice(card:DeviceCard):Void {
        if (card == null) return;

        _deviceCards.remove(card);
        if (deviceCanvas != null && deviceCanvas.contains(card)) {
            deviceCanvas.removeChild(card);
        }
        card.dispose();
    }

    /**
     * Получить список всех карточек устройств.
     * Используется в Main.hx для сохранения позиций.
     */
    public function getDeviceCards():Array<DeviceCard> {
        return _deviceCards;
    }

    private function onAtomDeleted(impulse:Impulse):Void {
        if (impulse == null || impulse.data == null) return;
        var deletedId:String = impulse.data.id;

        var toRemove:Array<DeviceCard> = [];
        for (card in _deviceCards) {
            if (card.assembly != null && card.assembly.id == deletedId) {
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
        var maxX = 380;
        var maxY = 240;

        for (y in 0...3) {
            for (x in 0...4) {
                var px = startX + x * stepX;
                var py = startY + y * stepY;

                if (isPositionFree(px, py)) {
                    return {x: px, y: py};
                }
            }
        }
        return {x: startX + Math.random() * 200, y: startY + Math.random() * 150};
    }

    private function isPositionFree(x:Float, y:Float):Bool {
        for (card in _deviceCards) {
            if (Math.abs(card.x - x) < 100 && Math.abs(card.y - y) < 80) {
                return false;
            }
        }
        return true;
    }

    public function clearDevices():Void {
        while (_deviceCards.length > 0) {
            var card = _deviceCards.pop();
            if (deviceCanvas != null && deviceCanvas.contains(card)) {
                deviceCanvas.removeChild(card);
            }
            card.dispose();
        }
    }

    private function create():Void {
        _impulseCallback = onAtomDeleted;
        Impulsys.subscribeToImpulse("ATOM_DELETED", _impulseCallback);
        var config = {
            title: "Device",
            width: 420,
            height: 320,
            borderless: true,
            alwaysOnTop: true,
            parameters: {
                background: 0x1a1a24
            }
        };

        _window = Lib.application.createWindow(config);

        if (_window != null && _window.stage != null) {
            createHeader();
            createDeviceCanvas();
            createContextMenu();

            _window.stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.addEventListener(MouseEvent.CLICK, onStageClick);
        }
    }

    private function createHeader():Void {
        _header = new Sprite();
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 420, 30);
        _header.graphics.endFill();

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "  Device (Right-Click to Add)";
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        var clearBtn = new Sprite();
        clearBtn.graphics.beginFill(0x555500);
        clearBtn.graphics.drawRect(0, 0, 30, 30);
        clearBtn.graphics.endFill();
        clearBtn.x = 360;

        var cText = new TextField();
        cText.text = "C";
        cText.width = 30;
        cText.height = 30;
        cText.selectable = false;
        cText.mouseEnabled = false;
        cText.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF, true, null, null, null, null, "center");
        clearBtn.addChild(cText);

        clearBtn.buttonMode = true;
        clearBtn.addEventListener(MouseEvent.CLICK, function(e) { clearDevices(); });
        _header.addChild(clearBtn);

        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0xAA0000);
        closeBtn.graphics.drawRect(0, 0, 30, 30);
        closeBtn.graphics.endFill();
        closeBtn.x = 390;

        var xText = new TextField();
        xText.text = "X";
        xText.width = 30;
        xText.height = 30;
        xText.selectable = false;
        xText.mouseEnabled = false;
        xText.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, "center");
        closeBtn.addChild(xText);

        closeBtn.buttonMode = true;
        closeBtn.addEventListener(MouseEvent.CLICK, function(e) { close(); });
        _header.addChild(closeBtn);

        _header.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _header.buttonMode = true;

        _window.stage.addChild(_header);
    }

    private function createDeviceCanvas():Void {
        deviceCanvas = new Sprite();
        deviceCanvas.y = 30;

        deviceCanvas.graphics.beginFill(0x222233);
        deviceCanvas.graphics.drawRect(0, 0, 420, 290);
        deviceCanvas.graphics.endFill();

        _window.stage.addChild(deviceCanvas);
    }

    private function createContextMenu():Void {
        _contextMenu = new Sprite();
        _contextMenu.visible = false;
        _window.stage.addChild(_contextMenu);
    }

    private function onRightClick(e:MouseEvent):Void {
        e.stopPropagation();
        showContextMenu(e.stageX, e.stageY);
    }

    private function onStageClick(e:MouseEvent):Void {
        if (_menuVisible) {
            hideContextMenu();
        }
    }

    private function showContextMenu(x:Float, y:Float):Void {
        while (_contextMenu.numChildren > 0) {
            _contextMenu.removeChildAt(0);
        }

        var assemblies:Array<{id:String, name:String, assembly:Assembly}> = [];
        if (onGetAssemblyList != null) {
            assemblies = onGetAssemblyList();
        }

        assemblies = [for (a in assemblies) if (a.id != "selfrun" && a.assembly.blueprint.id != "selfrun") a];

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

        if (assemblies.length == 0) {
            var emptyItem = createMenuItem("(No devices available)", null, true);
            emptyItem.y = yPos;
            _contextMenu.addChild(emptyItem);
            yPos += 26;
        } else {
            for (item in assemblies) {
                var menuItem = createMenuItem(item.name, item.assembly, false);
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

        _contextMenu.x = Math.min(x, 420 - 200);
        _contextMenu.y = Math.min(Math.max(y - 30, 0), 320 - yPos - 10);

        _menuVisible = true;
        _contextMenu.visible = true;
    }

    private function hideContextMenu():Void {
        _menuVisible = false;
        _contextMenu.visible = false;
    }

    private function createMenuItem(label:String, assembly:Assembly, disabled:Bool):Sprite {
        var item = new Sprite();
        item.graphics.beginFill(disabled ? 0x333344 : 0x444455);
        item.graphics.drawRect(0, 0, 180, 24);
        item.graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_typewriter", 11, disabled ? 0x777788 : 0xFFFFFF);
        txt.text = (disabled || assembly == null) ? label : "+ " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);

        if (!disabled && assembly != null) {
            item.buttonMode = true;

            final capturedAssembly = assembly;

            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
                addDevice(capturedAssembly);
                if (onAssemblySelected != null) {
                    onAssemblySelected(capturedAssembly);
                }
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

    private var _dragging:Bool = false;
    private var _dragOffsetX:Float = 0;
    private var _dragOffsetY:Float = 0;

    private function onMouseDown(e:MouseEvent):Void {
        _dragging = true;
        _dragOffsetX = e.localX;
        _dragOffsetY = e.localY;

        _window.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        _window.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    }

    private function onMouseMove(e:MouseEvent):Void {
        if (_dragging && _window != null) {
            var newX = _window.x + (e.stageX - _dragOffsetX);
            var newY = _window.y + (e.stageY - _dragOffsetY);

            _window.x = Std.int(newX);
            _window.y = Std.int(newY);
        }
    }

    private function onMouseUp(e:MouseEvent):Void {
        _dragging = false;
        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }
    }

    public function close():Void {
        Impulsys.removeImpulse("ATOM_DELETED", _impulseCallback);

        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _window.stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.removeEventListener(MouseEvent.CLICK, onStageClick);
        }

        clearDevices();
        deviceCanvas = null;
        _contextMenu = null;

        if (_window != null) {
            _window.close();
            _window = null;
        }
    }

    public var isOpen(get, never):Bool;
    private function get_isOpen():Bool {
        return _window != null;
    }
}

/**
 * DeviceCard v1.1
 */
class DeviceCard extends Sprite {

    // ИСПРАВЛЕНО: public property
    public var assembly(default, null):Assembly;
    
    private var _deviceWindow:DeviceWindow;
    private var _deviceView:DeviceView;
    private var _titleBar:Sprite;
    private var _titleLabel:TextField;

    private var _cardDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;

    public function new(asm:Assembly, deviceWindow:DeviceWindow) {
        super();
        this.assembly = asm; // ИСПРАВЛЕНО: присвоение
        _deviceWindow = deviceWindow;
        buildCard();
    }

    private function buildCard():Void {
        try {
            _deviceView = DeviceWidgetFactory.create(assembly); // ИСПРАВЛЕНО: использование assembly
        } catch (e:Dynamic) {
            _deviceView = null;
        }

        if (_deviceView == null) {
            createFallbackCard();
            return;
        }

        _deviceView.activate();

        _titleBar = new Sprite();
        _titleBar.graphics.beginFill(0x3a3a4a);
        _titleBar.graphics.drawRect(0, 0, _deviceView.width + 20, 20);
        _titleBar.graphics.endFill();
        addChild(_titleBar);

        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 10, 0xFFFFFF);
        // ИСПРАВЛЕНО: использование assembly
        _titleLabel.text = " " + (assembly.blueprint != null ? assembly.blueprint.name : "Device");
        _titleLabel.width = _deviceView.width;
        _titleLabel.height = 20;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _titleBar.addChild(_titleLabel);

        var closeBtn = new Sprite();
        closeBtn.graphics.beginFill(0x883333);
        closeBtn.graphics.drawRect(0, 0, 16, 16);
        closeBtn.graphics.endFill();
        closeBtn.x = _deviceView.width + 2;
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

        graphics.clear();
        graphics.beginFill(0x2a2a3a, 0.9);
        graphics.lineStyle(1, 0x4a4a5a);
        graphics.drawRoundRect(-5, -5, _deviceView.width + 30, _deviceView.height + 30, 4, 4);
        graphics.endFill();

        _titleBar.buttonMode = true;
        _titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
    }

    private function createFallbackCard():Void {
        graphics.beginFill(0x333344);
        graphics.drawRoundRect(0, 0, 80, 50, 4, 4);
        graphics.endFill();

        var txt = new TextField();
        txt.defaultTextFormat = new TextFormat("_sans", 10, 0xFFFFFF);
        // ИСПРАВЛЕНО: использование assembly
        txt.text = assembly.blueprint != null ? assembly.blueprint.name : "?";
        txt.width = 80;
        txt.height = 50;
        txt.selectable = false;
        txt.mouseEnabled = false;
        addChild(txt);
    }

    private function onCloseClick(e:MouseEvent):Void {
        e.stopPropagation();
        _deviceWindow.removeDevice(this);
    }

    private function onCardMouseDown(e:MouseEvent):Void {
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
        if (!_cardDragging) return;
        var dx = e.stageX - _mouseStartX;
        var dy = e.stageY - _mouseStartY;
        this.x = _dragStartX + dx;
        this.y = _dragStartY + dy;
    }

    private function onCardMouseUp(e:MouseEvent):Void {
        _cardDragging = false;
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onCardMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onCardMouseUp);
        }
    }

    public function dispose():Void {
        if (_titleBar != null) _titleBar.removeEventListener(MouseEvent.MOUSE_DOWN, onCardMouseDown);
        if (_deviceView != null) {
            _deviceView.deactivate();
            _deviceView.dispose();
            _deviceView = null;
        }
        assembly = null; // ИСПРАВЛЕНО: использование assembly
        _deviceWindow = null;
        _titleBar = null;
        _titleLabel = null;
    }
}