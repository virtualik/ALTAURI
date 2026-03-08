package;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;

/**
 * TRANSPARENCY TEST - Layered Window with Color Key
 *
 * Keys:
 * F4 - Toggle transparency
 * F5 - Toggle blur
 * F6 - Debug info
 * F7 - Set 50% opacity
 * 
 * IMPORTANT: 
 * - Black pixels (0x000000) become TRANSPARENT
 * - All other colors with alpha=1.0 remain OPAQUE
 * - Do NOT use black for visible UI elements!
 */
class Main extends Sprite {
    
    private var _windowController:ui.WindowController;
    private var _shapes:Sprite;
    private var _statusText:TextField;
    
    public function new() {
        super();
        
        if (stage != null) init();
        else addEventListener(Event.ADDED_TO_STAGE, init);
    }
    
    private function init(e:Event = null):Void {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        
        // CRITICAL: Set BLACK background (will be transparent)
        stage.color = 0x000000;
        
        // Create container for shapes
        _shapes = new Sprite();
        addChild(_shapes);
        
        _windowController = new ui.WindowController();
        
        #if windows
        haxe.Timer.delay(function() {
            trace("=== Enabling Layered Window transparency ===");
            var success = _windowController.enableLayeredTransparency();
            trace("Result: " + success);
            haxe.Timer.delay(drawTestContent, 100);
        }, 300);
        #end
        
        // Status text
        _statusText = new TextField();
        _statusText.width = 500;
        _statusText.height = 30;
        _statusText.x = 10;
        _statusText.y = stage.stageHeight - 40;
        _statusText.selectable = false;
        _statusText.background = false;
        var fmt = new TextFormat("_sans", 14, 0xFFFFFF);
        _statusText.defaultTextFormat = fmt;
        _statusText.text = "F4=Toggle F5=Blur F6=Debug F7=Opacity | ESC=Exit";
        addChild(_statusText);
        
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        stage.addEventListener(Event.RESIZE, onResize);
    }
    
    private function drawTestContent():Void {
        _shapes.graphics.clear();
        
        // ========== TEST SHAPES ==========
        // BLACK background areas will be TRANSPARENT
        // All other colors with alpha=1.0 will be OPAQUE
        
        // Row 1: Solid shapes at top (should be OPAQUE - can't see through)
        // RED square
        _shapes.graphics.beginFill(0xFF0000, 1.0);
        _shapes.graphics.drawRect(20, 20, 150, 150);
        _shapes.graphics.endFill();
        
        // GREEN circle
        _shapes.graphics.beginFill(0x00FF00, 1.0);
        _shapes.graphics.drawCircle(270, 95, 75);
        _shapes.graphics.endFill();
        
        // BLUE square
        _shapes.graphics.beginFill(0x0000FF, 1.0);
        _shapes.graphics.drawRect(380, 20, 150, 150);
        _shapes.graphics.endFill();
        
        // YELLOW triangle
        _shapes.graphics.beginFill(0xFFFF00, 1.0);
        _shapes.graphics.moveTo(600, 20);
        _shapes.graphics.lineTo(700, 170);
        _shapes.graphics.lineTo(500, 170);
        _shapes.graphics.lineTo(600, 20);
        _shapes.graphics.endFill();
        
        // Row 2: Semi-transparent shapes
        // 50% transparent RED
        _shapes.graphics.beginFill(0xFF0000, 0.5);
        _shapes.graphics.drawRect(20, 200, 150, 150);
        _shapes.graphics.endFill();
        
        // 30% transparent GREEN
        _shapes.graphics.beginFill(0x00FF00, 0.3);
        _shapes.graphics.drawCircle(270, 275, 75);
        _shapes.graphics.endFill();
        
        // 70% transparent BLUE
        _shapes.graphics.beginFill(0x0000FF, 0.7);
        _shapes.graphics.drawRect(380, 200, 150, 150);
        _shapes.graphics.endFill();
        
        // 10% transparent YELLOW
        _shapes.graphics.beginFill(0xFFFF00, 0.1);
        _shapes.graphics.moveTo(600, 200);
        _shapes.graphics.lineTo(700, 350);
        _shapes.graphics.lineTo(500, 350);
        _shapes.graphics.lineTo(600, 200);
        _shapes.graphics.endFill();
        
        // Row 3: Black shapes (should be TRANSPARENT - color key!)
        // BLACK fully opaque - will be TRANSPARENT
        _shapes.graphics.beginFill(0x000000, 1.0);
        _shapes.graphics.drawRect(20, 380, 100, 100);
        _shapes.graphics.endFill();
        
        // BLACK 50% transparent
        _shapes.graphics.beginFill(0x000000, 0.5);
        _shapes.graphics.drawRect(140, 380, 100, 100);
        _shapes.graphics.endFill();
        
        // BLACK 10% transparent
        _shapes.graphics.beginFill(0x000000, 0.1);
        _shapes.graphics.drawRect(260, 380, 100, 100);
        _shapes.graphics.endFill();
        
        // WHITE shapes to test contrast
        _shapes.graphics.beginFill(0xFFFFFF, 1.0);
        _shapes.graphics.drawRect(380, 380, 100, 100);
        _shapes.graphics.endFill();
        
        _shapes.graphics.beginFill(0xFFFFFF, 0.5);
        _shapes.graphics.drawRect(500, 380, 100, 100);
        _shapes.graphics.endFill();
        
        _shapes.graphics.beginFill(0xFFFFFF, 0.1);
        _shapes.graphics.drawRect(620, 380, 100, 100);
        _shapes.graphics.endFill();
        
        trace("Test shapes drawn - black=transparent, others opaque!");
    }
    
    private function onResize(e:Event):Void {
        if (_statusText != null) {
            _statusText.y = stage.stageHeight - 40;
        }
        drawTestContent();
    }
    
    private function onKeyDown(e:KeyboardEvent):Void {
        #if windows
        switch (e.keyCode) {
            case Keyboard.F4:
                _windowController.toggleTransparency();
                haxe.Timer.delay(drawTestContent, 50);
                
            case Keyboard.F5:
                _windowController.toggleBlurBehind();
                
            case Keyboard.F6:
                _windowController.debugWindowInfo();
                
            case Keyboard.F7:
                _windowController.setOpacity(128);
        }
        #end
        
        if (e.keyCode == Keyboard.ESCAPE) {
            #if sys
            Sys.exit(0);
            #end
        }
    }
}
