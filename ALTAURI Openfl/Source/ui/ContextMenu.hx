package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;

class ContextMenu extends Sprite {
    
    private var _items:Array<ContextMenuItem>;
    private var _spawnX:Float = 0;
    private var _spawnY:Float = 0;

    public function new() {
        super();
        _items = [];
        
        graphics.lineStyle(1, 0x888888);
        graphics.beginFill(0xEEEEEE);
        graphics.drawRoundRect(0, 0, 150, 10, 5);
        graphics.endFill();
    }
    
    public function addItem(label:String, action:String, ?data:Dynamic):Void {
        var item = new ContextMenuItem(label, action, data);
        item.y = _items.length * 25;
        addChild(item);
        _items.push(item);
        
        graphics.clear();
        graphics.lineStyle(1, 0x888888);
        graphics.beginFill(0xEEEEEE);
        graphics.drawRoundRect(0, 0, 150, (_items.length * 25) + 5, 5);
        graphics.endFill();
    }
    
    // Update show to store coordinates
    public function show(x:Float, y:Float):Void {
        _spawnX = x;
        _spawnY = y;
        
        this.x = x;
        this.y = y;
        visible = true;
        
        if (stage != null) {
            stage.addEventListener(MouseEvent.MOUSE_DOWN, onStageClick);
        }
    }
    
    public function hide():Void {
        visible = false;
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onStageClick);
        }
    }
    
    private function onStageClick(e:MouseEvent):Void {
        if (!this.hitTestPoint(e.stageX, e.stageY)) {
            hide();
        }
    }
    
    // Getter for coordinates
    public function getSpawnPosition():{x:Float, y:Float} {
        return { x: _spawnX, y: _spawnY };
    }
}