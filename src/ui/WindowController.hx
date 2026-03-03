package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import openfl.Lib;
import lime.ui.Window;
import lime.system.System;

/**
 * WindowController - Runtime window mode switching
 * 
 * Features:
 * - Toggle borderless mode
 * - Toggle fullscreen
 * - Draggable borderless window
 * 
 * Keyboard shortcuts:
 * - F1: Toggle borderless
 * - F2: Toggle fullscreen
 * - F3: Center window
 * - F11: Toggle maximize
 */
class WindowController {
    
    private var _window:Window;
    private var _isDragging:Bool = false;
    private var _dragStartX:Float = 0;
    private var _dragStartY:Float = 0;
    private var _windowStartX:Int = 0;
    private var _windowStartY:Int = 0;
    
    public function new() {
        _window = Lib.current.stage.window;
        
        // Setup keyboard shortcuts
        Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        // Setup drag support for borderless mode
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        Lib.current.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
        
        trace("WindowController initialized");
        trace("  F1: Toggle borderless");
        trace("  F2: Toggle fullscreen");
        trace("  F3: Center window");
        trace("  F11: Toggle maximize");
    }
    
    /**
     * Toggle borderless mode
     */
    public function toggleBorderless():Void {
        _window.borderless = !_window.borderless;
        trace("Borderless: " + _window.borderless);
    }
    
    /**
     * Toggle fullscreen
     */
    public function toggleFullscreen():Void {
        _window.fullscreen = !_window.fullscreen;
        trace("Fullscreen: " + _window.fullscreen);
    }
    
    /**
     * Toggle maximize
     */
    public function toggleMaximize():Void {
        _window.maximized = !_window.maximized;
        trace("Maximized: " + _window.maximized);
    }
    
    /**
     * Minimize window
     */
    public function minimize():Void {
        _window.minimized = true;
        trace("Minimized");
    }
    
    /**
     * Restore from minimized/maximized
     */
    public function restore():Void {
        _window.minimized = false;
        _window.maximized = false;
        trace("Restored");
    }
    
    /**
     * Center window on primary screen
     */
    public function centerWindow():Void {
        // Get primary display
        var display = System.getDisplay(0);
        if (display != null) {
            var displayWidth = Std.int(display.bounds.width);
            var displayHeight = Std.int(display.bounds.height);
            
            _window.x = Std.int((displayWidth - _window.width) / 2);
            _window.y = Std.int((displayHeight - _window.height) / 2);
            trace("Window centered at: " + _window.x + ", " + _window.y);
        }
    }
    
    /**
     * Set window position
     */
    public function setPosition(x:Int, y:Int):Void {
        _window.x = x;
        _window.y = y;
    }
    
    /**
     * Set window size
     */
    public function setSize(width:Int, height:Int):Void {
        _window.width = width;
        _window.height = height;
    }
    
    /**
     * Get current window state
     */
    public function getState():WindowState {
        return {
            x: _window.x,
            y: _window.y,
            width: _window.width,
            height: _window.height,
            borderless: _window.borderless,
            fullscreen: _window.fullscreen,
            maximized: _window.maximized,
            minimized: _window.minimized,
            visible: _window.visible
        };
    }
    
    /**
     * Print window info
     */
    public function printInfo():Void {
        trace("=== Window Info ===");
        trace("Position: " + _window.x + ", " + _window.y);
        trace("Size: " + _window.width + " x " + _window.height);
        trace("Borderless: " + _window.borderless);
        trace("Fullscreen: " + _window.fullscreen);
        trace("Maximized: " + _window.maximized);
        trace("Minimized: " + _window.minimized);
        trace("Visible: " + _window.visible);
        
        // Display info
        var display = System.getDisplay(0);
        if (display != null) {
            trace("Display: " + display.name);
            trace("Display bounds: " + display.bounds);
        }
    }
    
    // === Event Handlers ===
    
    private function onKeyDown(e:KeyboardEvent):Void {
        // Don't process if not on stage
        if (e.target != Lib.current.stage) return;
        
        switch (e.keyCode) {
            case Keyboard.F1:
                toggleBorderless();
                
            case Keyboard.F2:
                toggleFullscreen();
                
            case Keyboard.F3:
                centerWindow();
                
            case Keyboard.F11:
                toggleMaximize();
        }
    }
    
    private function onMouseDown(e:MouseEvent):Void {
        // Only allow drag in borderless mode
        if (!_window.borderless) return;
        
        // Only drag from top area (like title bar) - first 40 pixels
        if (e.stageY > 40) return;
        
        _isDragging = true;
        _dragStartX = e.stageX;
        _dragStartY = e.stageY;
        _windowStartX = _window.x;
        _windowStartY = _window.y;
    }
    
    private function onMouseUp(e:MouseEvent):Void {
        _isDragging = false;
    }
    
    private function onMouseMove(e:MouseEvent):Void {
        if (!_isDragging) return;
        
        var dx = e.stageX - _dragStartX;
        var dy = e.stageY - _dragStartY;
        
        _window.x = Std.int(_windowStartX + dx);
        _window.y = Std.int(_windowStartY + dy);
    }
}

typedef WindowState = {
    x:Int,
    y:Int,
    width:Int,
    height:Int,
    borderless:Bool,
    fullscreen:Bool,
    maximized:Bool,
    minimized:Bool,
    visible:Bool
};