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

    public function drawWire(from:Point, to:Point, color:Int = 0x888888):Void {
        graphics.clear(); 
        // Logic for drawing wires is currently inside NodeEditor.
        // This class serves as a container.
    }

    public function clearWires():Void {
        graphics.clear();
    }
}