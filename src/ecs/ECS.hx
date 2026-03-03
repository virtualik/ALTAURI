package ecs;

/**
 * ECS FACADE v1.0
 * Single import for the entire Hybrid Render ECS layer.
 * 
 * Usage:
 *   import ecs.ECS;
 *   
 *   // Initialize (call once in NodeEditor constructor)
 *   ECS.init();
 *   
 *   // Register node
 *   ECS.register(atomId, sprite, x, y);
 *   
 *   // Update position (on drag)
 *   ECS.updatePosition(atomId, newX, newY);
 *   
 *   // Render (every frame)
 *   ECS.render();
 *   
 *   // Cleanup (on atom delete)
 *   ECS.unregister(atomId);
 *   
 *   // Reset (on hard reset)
 *   ECS.reset();
 */
import ecs.core.World;
import ecs.core.RenderSystem;
import ecs.core.Query;
import ecs.components.PositionComponent;
import ecs.components.VisualComponent;
import openfl.display.Sprite;

class ECS {
    
    private static var _initialized:Bool = false;

    /**
     * Initialize the ECS render layer.
     * Call once in NodeEditor constructor.
     */
    public static function init():Void {
        if (_initialized) return;
        
        var world = World.getInstance();
        world.registerSystem(new RenderSystem());
        
        _initialized = true;
    }

    /**
     * Register a renderable node.
     */
    public static function register(atomId:String, sprite:Sprite, x:Float, y:Float):Void {
        World.getInstance().registerEntity(atomId, sprite, x, y);
    }

    /**
     * Unregister a node (on delete).
     */
    public static function unregister(atomId:String):Void {
        World.getInstance().unregisterEntity(atomId);
    }

    /**
     * Update node position.
     */
    public static function updatePosition(atomId:String, x:Float, y:Float):Void {
        World.getInstance().updatePosition(atomId, x, y);
    }

    /**
     * Set selection state.
     */
    public static function setSelected(atomId:String, selected:Bool):Void {
        World.getInstance().setSelected(atomId, selected);
    }

    /**
     * Check if selected.
     */
    public static function isSelected(atomId:String):Bool {
        return World.getInstance().isSelected(atomId);
    }

    /**
     * Render all nodes. Call every frame.
     */
    public static function render():Void {
        World.getInstance().render();
    }

    /**
     * Get all selected atom IDs.
     */
    public static function getSelected():Array<String> {
        return Query.getSelected(World.getInstance());
    }

    /**
     * Get atom IDs in rectangle (for lasso).
     */
    public static function getInRect(x:Float, y:Float, w:Float, h:Float):Array<String> {
        return Query.getInRect(World.getInstance(), x, y, w, h);
    }

    /**
     * Clear all selections.
     */
    public static function clearSelections():Void {
        var world = World.getInstance();
        var selected = Query.getSelected(world);
        for (id in selected) {
            world.setSelected(id, false);
        }
    }

    /**
     * Get entity count.
     */
    public static function getEntityCount():Int {
        return World.getInstance().getEntityCount();
    }

    /**
     * Enable/disable rendering.
     */
    public static function setEnabled(enabled:Bool):Void {
        World.getInstance().enabled = enabled;
    }

    /**
     * Full reset. Call on hard reset.
     */
    public static function reset():Void {
        World.reset();
        _initialized = false;
    }

    /**
     * Get direct World access for advanced usage.
     */
    public static function getWorld():World {
        return World.getInstance();
    }
}
