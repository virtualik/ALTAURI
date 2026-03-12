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
import core.view.PanelWidget;
import core.view.TextWidget;

/**
 * DeviceWindow v3.0 (DeviceView Integration)
 * Вторичное окно с DeviceView выбранной Assembly.
 * 
 * Features:
 * - ПКМ контекстное меню со списком всех Assembly в схеме
 * - Автоматическое создание DeviceView через DeviceWidgetFactory
 * - Прямой доступ к customSprite из Main
 */
class DeviceWindow {

    private var _window:Window;
    private var _header:Sprite;
    private var _contextMenu:Sprite;
    private var _menuVisible:Bool = false;
    
    /**
     * Публичный спрайт с прямым доступом из Main.
     */
    public var customSprite(default, null):Sprite;
    
    /**
     * Текущее отображаемое DeviceView.
     */
    private var _currentView:DeviceView;
    
    /**
     * Callback для получения списка всех Assembly в схеме.
     * Возвращает массив {id, name, assembly}.
     */
    public var onGetAssemblyList:Void -> Array<{id:String, name:String, assembly:Assembly}>;
    
    /**
     * Callback при выборе Assembly.
     */
    public var onAssemblySelected:Assembly -> Void;
    
    /**
     * Текущая выбранная сборка.
     */
    public var currentAssembly(default, set):Assembly;
    
    private var _titleLabel:TextField;

    public function new() {
        create();
    }
    
    private function set_currentAssembly(value:Assembly):Assembly {
        currentAssembly = value;
        
        // Обновляем заголовок
        if (_titleLabel != null && value != null) {
            _titleLabel.text = "  Device: " + value.blueprint.name;
        } else if (_titleLabel != null) {
            _titleLabel.text = "  Device";
        }
        
        // Создаём DeviceView
        if (value != null) {
            setDeviceView(value);
        }
        
        return value;
    }
    
    /**
     * Установить отображаемую сборку.
     */
    public function setDeviceView(asm:Assembly):Void {
        trace('DeviceWindow.setDeviceView: start for ${asm != null && asm.blueprint != null ? asm.blueprint.name : "null"}');
        
        // Удаляем старый view
        if (_currentView != null) {
            trace('DeviceWindow.setDeviceView: disposing old view');
            try {
                _currentView.deactivate();
                if (customSprite != null && customSprite.contains(_currentView)) {
                    customSprite.removeChild(_currentView);
                }
                _currentView.dispose();
            } catch (e:Dynamic) {
                trace('DeviceWindow: Error disposing old view: $e');
            }
            _currentView = null;
        }
        
        if (asm == null) {
            trace('DeviceWindow.setDeviceView: asm is null, returning');
            return;
        }
        
        if (customSprite == null) {
            trace('DeviceWindow.setDeviceView: ERROR - customSprite is null!');
            return;
        }
        
        // Создаём новый view через фабрику
        trace('DeviceWindow.setDeviceView: calling DeviceWidgetFactory.create');
        try {
            _currentView = DeviceWidgetFactory.create(asm);
            trace('DeviceWindow.setDeviceView: factory returned ${_currentView != null ? "view" : "null"}');
            
            if (_currentView != null) {
                trace('DeviceWindow.setDeviceView: adding to customSprite');
                customSprite.addChild(_currentView);
                trace('DeviceWindow.setDeviceView: activating view');
                _currentView.activate();
                trace('DeviceWindow.setDeviceView: view activated');
                
                // Центрируем
                if (customSprite.width > 0 && customSprite.height > 0) {
                    _currentView.x = (400 - _currentView.width) / 2;
                    _currentView.y = (270 - _currentView.height) / 2;
                }
                trace('DeviceWindow.setDeviceView: done');
            }
        } catch (e:Dynamic) {
            trace('DeviceWindow: Error creating DeviceView: $e');
            _currentView = null;
        }
    }

    private function create():Void {
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
            createCustomSprite();
            createContextMenu();
            
            // ПКМ для контекстного меню
            _window.stage.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.addEventListener(MouseEvent.CLICK, onStageClick);
        }
    }

    private function createHeader():Void {
        _header = new Sprite();

        // Фон заголовка
        _header.graphics.beginFill(0x2a2a34);
        _header.graphics.drawRect(0, 0, 420, 30);
        _header.graphics.endFill();

        // Заголовок
        _titleLabel = new TextField();
        _titleLabel.defaultTextFormat = new TextFormat("_typewriter", 12, 0xFFFFFF, true);
        _titleLabel.text = "  Device (Right-Click to Select)";
        _titleLabel.width = 300;
        _titleLabel.height = 30;
        _titleLabel.selectable = false;
        _titleLabel.mouseEnabled = false;
        _header.addChild(_titleLabel);

        // Кнопка закрытия
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

        // Перетаскивание окна за заголовок
        _header.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        _header.buttonMode = true;

        _window.stage.addChild(_header);
    }

    private function createCustomSprite():Void {
        customSprite = new Sprite();
        customSprite.y = 30;
        
        // Фон спрайта
        customSprite.graphics.beginFill(0x222233);
        customSprite.graphics.drawRect(0, 0, 420, 290);
        customSprite.graphics.endFill();
        
        _window.stage.addChild(customSprite);
    }
    
    private function createContextMenu():Void {
        _contextMenu = new Sprite();
        _contextMenu.visible = false;
        _contextMenu.x = 10;
        _contextMenu.y = 40;
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
        // Очищаем старое меню
        while (_contextMenu.numChildren > 0) {
            _contextMenu.removeChildAt(0);
        }
        
        // Получаем список сборок через callback
        var assemblies:Array<{id:String, name:String, assembly:Assembly}> = [];
        if (onGetAssemblyList != null) {
            assemblies = onGetAssemblyList();
        }
        
        // Создаём пункты меню
        var yPos = 0;
        
        // Заголовок меню
        var headerItem = createMenuItem("Select Assembly:", null, true);
        headerItem.y = yPos;
        _contextMenu.addChild(headerItem);
        yPos += 28;
        
        // Разделитель
        var sep = new Sprite();
        sep.graphics.lineStyle(1, 0x444455);
        sep.graphics.moveTo(0, 0);
        sep.graphics.lineTo(180, 0);
        sep.y = yPos;
        _contextMenu.addChild(sep);
        yPos += 8;
        
        if (assemblies.length == 0) {
            var emptyItem = createMenuItem("(No assemblies available)", null, true);
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
        
        // Фон меню
        _contextMenu.graphics.clear();
        _contextMenu.graphics.beginFill(0x333344, 0.98);
        _contextMenu.graphics.lineStyle(1, 0x555566);
        _contextMenu.graphics.drawRoundRect(0, 0, 190, yPos + 4, 6, 6);
        _contextMenu.graphics.endFill();
        
        // Позиционируем меню
        _contextMenu.x = Math.min(x, 420 - 200);
        _contextMenu.y = Math.min(y, 320 - yPos - 10);
        
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
        txt.text = (disabled || assembly == null) ? label : "• " + label;
        txt.width = 170;
        txt.height = 24;
        txt.x = 8;
        txt.selectable = false;
        txt.mouseEnabled = false;
        item.addChild(txt);
        
        if (!disabled && assembly != null) {
            item.buttonMode = true;
            
            // Используем замыкание вместо Reflect
            final capturedAssembly = assembly;
            item.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
                trace('DeviceWindow: Menu item clicked for ${capturedAssembly.blueprint != null ? capturedAssembly.blueprint.name : "unknown"}');
                try {
                    currentAssembly = capturedAssembly;
                    if (onAssemblySelected != null) {
                        onAssemblySelected(capturedAssembly);
                    }
                } catch (ex:Dynamic) {
                    trace('DeviceWindow: Error selecting assembly: $ex');
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

    /**
     * Закрыть окно.
     */
    public function close():Void {
        if (_window != null && _window.stage != null) {
            _window.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _window.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            _window.stage.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            _window.stage.removeEventListener(MouseEvent.CLICK, onStageClick);
        }
        
        // Очищаем DeviceView
        if (_currentView != null) {
            _currentView.deactivate();
            _currentView.dispose();
            _currentView = null;
        }

        customSprite = null;
        _contextMenu = null;
        
        if (_window != null) {
            _window.close();
            _window = null;
        }
    }

    /**
     * Проверить, открыто ли окно.
     */
    public var isOpen(get, never):Bool;
    private function get_isOpen():Bool {
        return _window != null;
    }
}
