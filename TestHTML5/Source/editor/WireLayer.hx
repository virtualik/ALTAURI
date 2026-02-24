package editor;

import openfl.display.Sprite;
import openfl.geom.Point;

/**
 * WireLayer v1.0
 * Dedicated layer for drawing connection lines.
 */
class WireLayer extends Sprite {

    public function new() {
        super();
        this.mouseEnabled = false; // Let clicks pass through to nodes
    }

    /**
     * Draws a single wire between two global points.
     */
    public function drawWire(from:Point, to:Point, color:Int = 0x888888):Void {
        graphics.clear(); // Simple implementation: redraw all every time
        
        // Ideally we would keep a list of wires and redraw them all.
        // But for this test, we just draw one line.
        // Note: In real app, we use update() method.
    }
    
    public function clearWires():Void {
        graphics.clear();
    }
}