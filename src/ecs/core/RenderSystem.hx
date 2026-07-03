package ecs.core;

import ecs.core.World;
import ecs.core.Query;
import openfl.display.Sprite;

/**
 * RENDER SYSTEM v1.0
 * The ONLY place where all visual updates happen.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   RenderSystem                                                          │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Main Loop (render()):                                          │   │
 * │   │  ┌───────────────────────────────────────────────────────────┐  │   │
 * │   │  │  1. Query.getRenderables(world)                           │  │   │
 * │   │  │  2. For each renderable entity:                           │  │   │
 * │   │  │     - Update sprite.x, sprite.y from PositionComponent    │  │   │
 * │   │  │     - Update sprite.alpha from selection state            │  │   │
 * │   │  └───────────────────────────────────────────────────────────┘  │   │
 * │   │                                                                 │   │
 * │   │  Batch Operations:                                              │   │
 * │   │  - setSelectionBatch(ids, selected)  → Multi-select             │   │
 * │   │  - clearAllSelections()              → Deselect all             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Benefits:                                                             │
 * │   - Single cache-friendly pass over all nodes                           │
 * │   - O(N) performance instead of scattered loops                         │
 * │   - Easy to add zoom, selection, layers, wire batching                  │
 * │   - Completely separate from core logic                                 │
 * │   - One function to profile                                             │
 * │                                                                         │
 * │   Future Extensions:                                                    │
 * │   - Zoom scale                                                          │
 * │   - Layer ordering                                                      │
 * │   - Visibility culling                                                  │
 * │   - Port position updates                                               │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class RenderSystem {
    public var enabled:Bool = true;
    public var world:World;
    
    public function new() {}
    
    /**
     * Main render method.
     * Call from World.render() every frame.
     */
    public function render():Void {
        // Single query - all renderable entities
        var renderables = Query.getRenderables(world);
        
        for (r in renderables) {
            var sprite = r.visual.sprite;
            
            // === POSITION UPDATE ===
            sprite.x = r.position.x;
            sprite.y = r.position.y;
            
            // === SELECTION VISUAL ===
            sprite.alpha = r.visual.isSelected ? 1.0 : 0.85;
        }
    }
    
    /**
     * Batch selection update.
     * More efficient than individual setSelected calls for multi-select.
     */
    public function setSelectionBatch(atomIds:Array<String>, selected:Bool):Void {
        for (id in atomIds) {
            world.setSelected(id, selected);
        }
    }
    
    /**
     * Clear all selections.
     */
    public function clearAllSelections():Void {
        var renderables = Query.getRenderables(world);
        for (r in renderables) {
            r.visual.isSelected = false;
        }
    }
}