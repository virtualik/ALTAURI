package ecs.components;

/**
 * POSITION COMPONENT v1.0
 * Pure data component. No logic.
 *
 * Used by:
 * - RenderSystem (for drawing)
 * - Query (for spatial queries)
 *
 * Replaces old x/y fields in NodeView.
 * Cache-friendly when stored in ComponentStorage.
 */
class PositionComponent {

    public var x:Float;
    public var y:Float;

    public function new(x:Float = 0, y:Float = 0) {
        this.x = x;
        this.y = y;
    }

    /**
     * Set both coordinates at once.
     */
    public function set(x:Float, y:Float):Void {
        this.x = x;
        this.y = y;
    }

    /**
     * Add offset.
     */
    public function translate(dx:Float, dy:Float):Void {
        this.x += dx;
        this.y += dy;
    }

    /**
     * Copy from another position.
     */
    public function copyFrom(other:PositionComponent):Void {
        this.x = other.x;
        this.y = other.y;
    }

    /**
     * Clone this component.
     */
    public function clone():PositionComponent {
        return new PositionComponent(x, y);
    }
}