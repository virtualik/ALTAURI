package ecs.core;

import ecs.core.ComponentStorage;
import ecs.components.PositionComponent;
import ecs.components.VisualComponent;
import openfl.display.Sprite;

/**
 * RENDER WORLD v1.0 (Hybrid ECS)
 * Minimal World ONLY for rendering layer.
 * 
 * IMPORTANT:
 * - Does NOT touch your core logic (Atom/Contact/SignalQueue/Assembly)
 * - One instance per NodeEditor
 * - All rendering goes through here
 * 
 * Benefits:
 * - Cache-friendly sprite updates
 * - Single render pass per frame
 * - Easy profiling (one function to measure)
 * - Can be disabled/enabled instantly
 */
class World {
    
    private static var _instance:World;
    
    // Component storages (sparse-set, cache-friendly)
    private var _positionStorage:ComponentStorage<PositionComponent>;
    private var _visualStorage:ComponentStorage<VisualComponent>;
    
    // Systems
    private var _systems:Array<RenderSystem>;
    
    // State
    public var enabled:Bool = true;

    /**
     * Get singleton instance.
     */
    public static function getInstance():World {
        if (_instance == null) _instance = new World();
        return _instance;
    }

    private function new() {
        _positionStorage = new ComponentStorage<PositionComponent>();
        _visualStorage = new ComponentStorage<VisualComponent>();
        _systems = [];
    }

    // =========================================================================
    // ENTITY REGISTRATION
    // =========================================================================

    /**
     * Register a renderable entity (atom/node).
     * Call this when creating a NodeView.
     * 
     * @param atomId    Unique atom ID from your core
     * @param sprite    OpenFL sprite to render
     * @param x         Initial X position
     * @param y         Initial Y position
     */
    public function registerEntity(atomId:String, sprite:Sprite, x:Float, y:Float):Void {
        var pos = new PositionComponent(x, y);
        var vis = new VisualComponent(sprite);
        
        _positionStorage.add(atomId, pos);
        _visualStorage.add(atomId, vis);
    }

    /**
     * Unregister entity (when atom deleted).
     */
    public function unregisterEntity(atomId:String):Void {
        _positionStorage.remove(atomId);
        _visualStorage.remove(atomId);
    }

    // =========================================================================
    // COMPONENT UPDATES
    // =========================================================================

    /**
     * Update position of an entity.
     * Call this on mouse drag instead of directly updating sprite.x/y.
     */
    public function updatePosition(atomId:String, x:Float, y:Float):Void {
        var pos = _positionStorage.get(atomId);
        if (pos != null) {
            pos.x = x;
            pos.y = y;
        }
    }

    /**
     * Set selection state.
     */
    public function setSelected(atomId:String, selected:Bool):Void {
        var vis = _visualStorage.get(atomId);
        if (vis != null) {
            vis.isSelected = selected;
        }
    }

    /**
     * Check if entity is selected.
     */
    public function isSelected(atomId:String):Bool {
        var vis = _visualStorage.get(atomId);
        return vis != null ? vis.isSelected : false;
    }

    // =========================================================================
    // SYSTEMS
    // =========================================================================

    /**
     * Register a render system.
     */
    public function registerSystem(system:RenderSystem):Void {
        _systems.push(system);
        system.world = this;
    }

    /**
     * Main render call.
     * Call this once per frame from NodeEditor.
     */
    public function render():Void {
        if (!enabled) return;
        
        for (sys in _systems) {
            if (sys.enabled) {
                sys.render();
            }
        }
    }

    // =========================================================================
    // STORAGE ACCESS (for Query)
    // =========================================================================

    /**
     * Get position storage. Used by Query.
     */
    public function getPositionStorage():ComponentStorage<PositionComponent> {
        return _positionStorage;
    }

    /**
     * Get visual storage. Used by Query.
     */
    public function getVisualStorage():ComponentStorage<VisualComponent> {
        return _visualStorage;
    }

    // =========================================================================
    // QUICK ACCESS
    // =========================================================================

    /**
     * Get visual component directly.
     */
    public function getVisual(atomId:String):VisualComponent {
        return _visualStorage.get(atomId);
    }

    /**
     * Get position component directly.
     */
    public function getPosition(atomId:String):PositionComponent {
        return _positionStorage.get(atomId);
    }

    // =========================================================================
    // UTILITY
    // =========================================================================

    /**
     * Get total entity count.
     */
    public function getEntityCount():Int {
        return _positionStorage.count();
    }

    /**
     * Clear everything. Call on reset.
     */
    public function clear():Void {
        _positionStorage.clear();
        _visualStorage.clear();
    }

    /**
     * Reset singleton (for testing or hard reset).
     */
    public static function reset():Void {
        if (_instance != null) {
            _instance.clear();
            _instance = null;
        }
    }
}
