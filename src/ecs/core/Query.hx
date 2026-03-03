package ecs.core;

import ecs.core.World;
import ecs.core.ComponentStorage;
import ecs.components.PositionComponent;
import ecs.components.VisualComponent;

/**
 * QUERY v1.0
 * Efficient, type-safe query system for the Hybrid Render ECS layer.
 *
 * Purpose:
 * - Find ALL entities that need rendering
 * - Return them in a clean array for RenderSystem
 * - O(N) performance (N = number of nodes, usually < 2000)
 * - No reflection, 100% type-safe
 */
class Query {

    /**
     * Get all renderable entities.
     * Entities must have BOTH PositionComponent AND VisualComponent.
     *
     * @return Array of RenderableEntity objects
     */
    public static function getRenderables(world:World):Array<RenderableEntity> {
        var result:Array<RenderableEntity> = [];

        var posStorage = world.getPositionStorage();
        var visStorage = world.getVisualStorage();

        if (posStorage == null || visStorage == null) {
            return result;
        }

        // Iterate over entities with Position
        for (entityId in posStorage.getAllEntityIds()) {
            // Check if they also have Visual
            var visual = visStorage.get(entityId);
            if (visual != null) {
                var position = posStorage.get(entityId);
                result.push({
                    entityId: entityId,
                    position: position,
                    visual: visual
                });
            }
        }

        return result;
    }

    /**
     * Get all selected entities.
     */
    public static function getSelected(world:World):Array<String> {
        var result:Array<String> = [];
        var renderables = getRenderables(world);

        for (r in renderables) {
            if (r.visual.isSelected) {
                result.push(r.entityId);
            }
        }

        return result;
    }

    /**
     * Get entity IDs in a rectangle region.
     * Useful for lasso selection.
     */
    public static function getInRect(world:World, x:Float, y:Float, w:Float, h:Float):Array<String> {
        var result:Array<String> = [];
        var renderables = getRenderables(world);

        for (r in renderables) {
            var px = r.position.x;
            var py = r.position.y;

            if (px >= x && px <= x + w && py >= y && py <= y + h) {
                result.push(r.entityId);
            }
        }

        return result;
    }
}

/**
 * Type definition for renderable entity.
 * Clean, readable, type-safe.
 */
typedef RenderableEntity = {
    var entityId:String;
    var position:PositionComponent;
    var visual:VisualComponent;
}