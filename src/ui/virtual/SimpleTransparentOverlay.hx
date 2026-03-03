package ui.virtual;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.Lib;
import core.base.Assembly;

/**
 * SimpleTransparentOverlay - Simple transparent overlay panel
 * 
 * This version creates an overlay panel on the existing stage
 * without creating a new window (for maximum compatibility).
 * 
 * For a separate window, use TransparentOverlayWindow instead.
 */
class SimpleTransparentOverlay extends Sprite {
    
    private var _assembly:Assembly;
    private var _header:Sprite;
    private var _content:Sprite;
    private var _closeBtn:Sprite;
    
    // Drag state
    private var _isDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    
    private var _width:Int = 400;
    private var _height:Int = 500;
    
    public function new(assembly:Assembly) {
        super();
        _assembly = assembly;
        buildUI();
        setupEvents();
    }
    
    /**
     * Show overlay
     */
    public function show():Void {
        if (stage == null) {
            Lib.current.stage.addChild(this);
        }
        
        // Center on stage
        x = (Lib.current.stage.stageWidth - _width) / 2;
        y = (Lib.current.stage.stageHeight - _height) / 2;
        
        visible = true;
    }
    
    /**
     * Hide overlay
     */
    public function hide():Void {
        visible = false;
    }
    
    /**
     * Close overlay
     */
    public function close():Void {
        if (parent != null) {
            parent.removeChild(this);
        }
    }
    
    private function buildUI():Void {
        // Semi-transparent background
        var bg = new Shape();
        bg.graphics.beginFill(0x1a1a2e, 0.95);
        bg.graphics.drawRoundRectComplex(0, 0, _width, _height, 12, 12, 12, 12);
        bg.graphics.endFill();
        addChild(bg);
        
        // Header
        _header = new Sprite();
        _header.graphics.beginFill(0x16213e, 0.98);
        _header.graphics.drawRoundRectComplex(0, 0, _width, 36, 12, 12, 0, 0);
        _header.graphics.endFill();
        addChild(_header);
        
        // Accent line
        var accent = new Shape();
        accent.graphics.lineStyle(2, 0x00aaff);
        accent.graphics.lineTo(_width, 0);
        accent.y = 36;
        addChild(accent);
        
        // Close button
        _closeBtn = new Sprite();
        _closeBtn.graphics.beginFill(0xff4757, 0.9);
        _closeBtn.graphics.drawCircle(0, 0, 10);
        _closeBtn.graphics.endFill();
        _closeBtn.graphics.lineStyle(2, 0xffffff);
        _closeBtn.graphics.moveTo(-4, -4);
        _closeBtn.graphics.lineTo(4, 4);
        _closeBtn.graphics.moveTo(4, -4);
        _closeBtn.graphics.lineTo(-4, 4);
        _closeBtn.x = _width - 20;
        _closeBtn.y = 18;
        _closeBtn.buttonMode = true;
        _header.addChild(_closeBtn);
        
        // Content
        _content = new Sprite();
        _content.y = 40;
        addChild(_content);
        
        buildContent();
    }
    
    private function buildContent():Void {
        // Info panel
        var info = new Shape();
        info.graphics.beginFill(0x0f0f23, 0.8);
        info.graphics.drawRoundRect(10, 10, _width - 20, 80, 8);
        info.graphics.endFill();
        _content.addChild(info);
        
        // Assembly name
        if (_assembly != null && _assembly.blueprint != null) {
            var portY = 110;
            
            if (_assembly.ports != null) {
                for (port in _assembly.ports) {
                    var portView = new Sprite();
                    var color = port.type == INPUT ? 0x00ff88 : 0xff8844;
                    portView.graphics.beginFill(color);
                    portView.graphics.drawCircle(20, 0, 8);
                    portView.graphics.endFill();
                    portView.y = portY;
                    portY += 30;
                    _content.addChild(portView);
                }
            }
        }
    }
    
    private function setupEvents():Void {
        _header.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
        addEventListener(MouseEvent.MOUSE_UP, onUp);
        addEventListener(MouseEvent.MOUSE_MOVE, onMove);
        _closeBtn.addEventListener(MouseEvent.CLICK, onClose);
    }
    
    private function onDown(e:MouseEvent):Void {
        _isDragging = true;
        _dragStartX = e.stageX - x;
        _dragStartY = e.stageY - y;
        _header.alpha = 0.8;
    }
    
    private function onUp(e:MouseEvent):Void {
        _isDragging = false;
        _header.alpha = 1.0;
    }
    
    private function onMove(e:MouseEvent):Void {
        if (!_isDragging) return;
        x = e.stageX - _dragStartX;
        y = e.stageY - _dragStartY;
    }
    
    private function onClose(e:MouseEvent):Void {
        close();
    }
    
    public function getRootSprite():Sprite {
        return _content;
    }
}
