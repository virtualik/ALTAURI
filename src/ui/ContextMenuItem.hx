package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.display.DisplayObjectContainer;
import core.logic.Impulsys;
import core.logic.Impulse;

/**
 * CONTEXT MENU ITEM v1.0
 * Single item in a ContextMenu.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ContextMenuItem                                                       │
 * │                                                                         │
 * │   ┌──────────────────────────────────┐                                  │
 * │   │  Label Text                      │  ← 150x25                        │
 * │   └──────────────────────────────────┘                                  │
 * │                                                                         │
 * │   States:                                                               │
 * │   - Normal:  bg=0xFFFFFF, text=0x000000                                 │
 * │   - Hover:   bg=0x00AAFF, text=0x000000                                 │
 * │                                                                         │
 * │   On Click:                                                             │
 * │   - Emits CONTEXT_MENU_ACTION impulse via Impulsys                      │
 * │   - Payload: {action, data, x, y}                                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ContextMenuItem extends Sprite {
    public var action:String;
    public var data:Dynamic;
    
    private var _label:TextField;
    private var _isHighlighted:Bool = false;
    private var _width:Float = 150;
    private var _height:Float = 25;
    
    public function new(label:String, action:String, ?data:Dynamic) {
        super();
        this.action = action;
        this.data = data;
        
        mouseChildren = false;
        buttonMode = true;
        
        _label = new TextField();
        _label.text = label;
        _label.width = _width;
        _label.height = _height;
        _label.selectable = false;
        _label.mouseEnabled = false;
        
        var fmt = new TextFormat("_typewriter", 12, 0x000000);
        _label.defaultTextFormat = fmt;
        addChild(_label);
        
        draw();
        
        addEventListener(MouseEvent.MOUSE_OVER, onOver);
        addEventListener(MouseEvent.MOUSE_OUT, onOut);
        addEventListener(MouseEvent.CLICK, onClick);
    }
    
    private function draw():Void {
        graphics.clear();
        graphics.beginFill(_isHighlighted ? 0x00AAFF : 0xFFFFFF);
        graphics.drawRect(0, 0, _width, _height);
        graphics.endFill();
    }
    
    private function onOver(e:MouseEvent):Void { _isHighlighted = true; draw(); }
    private function onOut(e:MouseEvent):Void { _isHighlighted = false; draw(); }
    
    private function onClick(e:MouseEvent):Void {
        var coords = {x: 0.0, y: 0.0};
        var p:DisplayObjectContainer = this.parent;
        
        if (Std.isOfType(p, ContextMenu)) {
            coords = cast(p, ContextMenu).getSpawnPosition();
        }
        
        Impulsys.emit(new Impulse("CONTEXT_MENU_ACTION", {
            action: this.action,
            data: this.data,
            x: coords.x,
            y: coords.y
        }));
    }
}