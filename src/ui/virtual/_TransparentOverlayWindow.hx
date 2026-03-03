package ui.virtual;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.display.Stage;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.Lib;
import core.base.Assembly;
import lime.ui.Window;
import lime.ui.WindowAttributes;
import lime.app.Application;
import lime.system.System;

/**
 * TransparentOverlayWindow - Separate borderless transparent window
 * 
 * Creates a NEW system window (not a panel on existing stage):
 * - Borderless (no title bar, no borders)
 * - Transparent background
 * - Always on top
 * - Draggable by header
 * - Separate from main application window
 * 
 * Usage:
 *   var overlay = new TransparentOverlayWindow(assembly);
 *   overlay.show();
 */
class TransparentOverlayWindow {
    
    private var _assembly:Assembly;
    private var _window:Window;
    private var _stage:Stage;
    private var _rootSprite:Sprite;
    
    // UI
    private var _header:Sprite;
    private var _content:Sprite;
    private var _closeBtn:Sprite;
    
    // Drag
    private var _isDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _windowStartX:Int = 0;
    private var _windowStartY:Int = 0;
    
    private var _width:Int = 400;
    private var _height:Int = 500;
    
    public function new(assembly:Assembly) {
        _assembly = assembly;
    }
    
    /**
     * Show the transparent overlay window
     */
    public function show():Void {
        // Method 1: Try Lime Application.createWindow
        #if desktop
        createLimeWindow();
        #end
    }
    
    #if desktop
    private function createLimeWindow():Void {
        var app = Application.current;
        
        if (app == null) {
            trace("ERROR: No Application found. Using fallback method.");
            createFallbackWindow();
            return;
        }
        
        try {
            // Create window attributes
            var attrs = new WindowAttributes();
            attrs.width = _width;
            attrs.height = _height;
            attrs.borderless = true;
            attrs.transparent = true;
            attrs.alwaysOnTop = true;
            attrs.resizable = true;
            attrs.title = "Overlay";
            
            // Create the window
            _window = app.createWindow(attrs);
            
            if (_window == null) {
                trace("ERROR: createWindow returned null. Using fallback.");
                createFallbackWindow();
                return;
            }
            
            trace("New window created successfully");
            
            // Setup window
            centerWindow();
            
            // Create OpenFL stage for this window
            _stage = new Stage(_width, _height, 0x00000000, null, true, true);
            _stage.color = 0x00000000;
            
            _rootSprite = new Sprite();
            _stage.addChild(_rootSprite);
            
            buildUI();
            setupEvents();
            
            _stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
            
            // Add window close handler
            _window.onClose.add(onWindowClose);
            
        } catch (e:Dynamic) {
            trace("ERROR creating Lime window: " + Std.string(e));
            createFallbackWindow();
        }
    }
    
    private function createFallbackWindow():Void {
        // Fallback: Create a sprite on current stage
        // This appears as overlay panel, not separate window
        trace("Using fallback overlay panel");
        
        _rootSprite = new Sprite();
        buildUI();
        setupEventsSprite();
        
        // Add to current stage
        Lib.current.stage.addChild(_rootSprite);
        
        // Center
        _rootSprite.x = (Lib.current.stage.stageWidth - _width) / 2;
        _rootSprite.y = (Lib.current.stage.stageHeight - _height) / 2;
    }
    #end
    
    private function buildUI():Void {
        // Main container
        var container = new Sprite();
        container.graphics.beginFill(0x1a1a2e, 0.95);
        container.graphics.drawRoundRectComplex(0, 0, _width, _height, 12, 12, 12, 12);
        container.graphics.endFill();
        _rootSprite.addChild(container);
        
        // Header (draggable)
        _header = new Sprite();
        _header.graphics.beginFill(0x16213e, 0.98);
        _header.graphics.drawRoundRectComplex(0, 0, _width, 40, 12, 12, 0, 0);
        _header.graphics.endFill();
        container.addChild(_header);
        
        // Accent line
        var accent = new Shape();
        accent.graphics.lineStyle(2, 0x00aaff);
        accent.graphics.lineTo(_width, 0);
        accent.y = 40;
        container.addChild(accent);
        
        // Close button
        _closeBtn = new Sprite();
        _closeBtn.graphics.beginFill(0xff4757, 0.9);
        _closeBtn.graphics.drawCircle(0, 0, 12);
        _closeBtn.graphics.endFill();
        _closeBtn.graphics.lineStyle(2, 0xffffff);
        _closeBtn.graphics.moveTo(-5, -5);
        _closeBtn.graphics.lineTo(5, 5);
        _closeBtn.graphics.moveTo(5, -5);
        _closeBtn.graphics.lineTo(-5, 5);
        _closeBtn.x = _width - 20;
        _closeBtn.y = 20;
        _closeBtn.buttonMode = true;
        _closeBtn.useHandCursor = true;
        _header.addChild(_closeBtn);
        
        // Content
        _content = new Sprite();
        _content.y = 50;
        container.addChild(_content);
        
        buildContent();
    }
    
    private function buildContent():Void {
        // Info panel
        var infoBg = new Shape();
        infoBg.graphics.beginFill(0x0f0f23, 0.8);
        infoBg.graphics.drawRoundRect(10, 10, _width - 20, 100, 8);
        infoBg.graphics.endFill();
        _content.addChild(infoBg);
        
        // Assembly info
        if (_assembly != null && _assembly.blueprint != null) {
            // Blueprint name indicator
            var nameBg = new Shape();
            nameBg.graphics.beginFill(0x00aaff, 0.2);
            nameBg.graphics.drawRoundRect(20, 25, _width - 40, 24, 4);
            nameBg.graphics.endFill();
            _content.addChild(nameBg);
            
            // Port indicators
            var portY = 130;
            
            if (_assembly.ports != null) {
                for (port in _assembly.ports) {
                    var portView = new Sprite();
                    
                    // Port circle
                    var color = port.type == INPUT ? 0x00ff88 : 0xff8844;
                    portView.graphics.beginFill(color);
                    portView.graphics.drawCircle(25, 0, 10);
                    portView.graphics.endFill();
                    
                    // Port line
                    portView.graphics.lineStyle(2, color, 0.5);
                    portView.graphics.lineTo(100, 0);
                    
                    portView.y = portY;
                    portY += 35;
                    _content.addChild(portView);
                }
            }
        }
        
        // Status
        var status = new Shape();
        status.graphics.beginFill(0x00ff88);
        status.graphics.drawCircle(_width - 25, _height - 60, 8);
        status.graphics.endFill();
        _content.addChild(status);
    }
    
    private function setupEvents():Void {
        #if desktop
        // Window-based events
        _header.addEventListener(MouseEvent.MOUSE_DOWN, onHeaderDown);
        _stage.addEventListener(MouseEvent.MOUSE_UP, onHeaderUp);
        _stage.addEventListener(MouseEvent.MOUSE_MOVE, onHeaderMove);
        _closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
        #end
    }
    
    private function setupEventsSprite():Void {
        // Sprite-based events (fallback)
        _header.addEventListener(MouseEvent.MOUSE_DOWN, onSpriteDown);
        _rootSprite.addEventListener(MouseEvent.MOUSE_UP, onSpriteUp);
        _rootSprite.addEventListener(MouseEvent.MOUSE_MOVE, onSpriteMove);
        _closeBtn.addEventListener(MouseEvent.CLICK, onSpriteClose);
    }
    
    private function centerWindow():Void {
        #if desktop
        if (_window != null) {
            var display = System.getDisplay(0);
            if (display != null) {
                _window.x = Std.int((display.bounds.width - _width) / 2);
                _window.y = Std.int((display.bounds.height - _height) / 2);
            }
        }
        #end
    }
    
    // === Window-based handlers ===
    
    private function onEnterFrame(e:Event):Void {
        if (_stage != null) {
            _stage.render();
        }
    }
    
    private function onHeaderDown(e:MouseEvent):Void {
        #if desktop
        if (_window == null) return;
        
        _isDragging = true;
        _dragStartX = e.stageX;
        _dragStartY = e.stageY;
        _windowStartX = _window.x;
        _windowStartY = _window.y;
        _header.alpha = 0.7;
        #end
    }
    
    private function onHeaderUp(e:MouseEvent):Void {
        _isDragging = false;
        _header.alpha = 1.0;
    }
    
    private function onHeaderMove(e:MouseEvent):Void {
        #if desktop
        if (!_isDragging || _window == null) return;
        
        var dx = e.stageX - _dragStartX;
        var dy = e.stageY - _dragStartY;
        
        _window.x = Std.int(_windowStartX + dx);
        _window.y = Std.int(_windowStartY + dy);
        #end
    }
    
    private function onCloseClick(e:MouseEvent):Void {
        close();
    }
    
    private function onWindowClose():Void {
        cleanup();
    }
    
    // === Sprite-based handlers (fallback) ===
    
    private function onSpriteDown(e:MouseEvent):Void {
        _isDragging = true;
        _dragStartX = e.stageX - _rootSprite.x;
        _dragStartY = e.stageY - _rootSprite.y;
        _header.alpha = 0.7;
    }
    
    private function onSpriteUp(e:MouseEvent):Void {
        _isDragging = false;
        _header.alpha = 1.0;
    }
    
    private function onSpriteMove(e:MouseEvent):Void {
        if (!_isDragging) return;
        _rootSprite.x = e.stageX - _dragStartX;
        _rootSprite.y = e.stageY - _dragStartY;
    }
    
    private function onSpriteClose(e:MouseEvent):Void {
        close();
    }
    
    // === Public API ===
    
    public function close():Void {
        #if desktop
        if (_window != null) {
            _window.close();
        }
        #end
        cleanup();
    }
    
    private function cleanup():Void {
        if (_stage != null) {
            _stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
        }
        
        if (_rootSprite != null && _rootSprite.parent != null) {
            _rootSprite.parent.removeChild(_rootSprite);
        }
        
        _window = null;
        _stage = null;
        _rootSprite = null;
    }
    
    public function setPosition(x:Int, y:Int):Void {
        #if desktop
        if (_window != null) {
            _window.x = x;
            _window.y = y;
        } else if (_rootSprite != null) {
            _rootSprite.x = x;
            _rootSprite.y = y;
        }
        #end
    }
    
    public function setSize(w:Int, h:Int):Void {
        _width = w;
        _height = h;
        
        #if desktop
        if (_window != null) {
            _window.width = w;
            _window.height = h;
        }
        #end
    }
    
    public function getRootSprite():Sprite {
        return _content;
    }
}
