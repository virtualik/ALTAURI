package ecs.core;

/**
 * COMPONENT STORAGE v1.0
 * Sparse-set based, cache-friendly storage for any component type.
 * Used internally by World. Supports thousands of entities without performance loss.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   ComponentStorage<T>                                                   │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Data:                                                          │   │
 * │   │  - _components:Array<T>          → Dense component storage      │   │
 * │   │  - _entityToIndex:Map<String,Int>→ Entity → Array index         │   │
 * │   │  - _indexToEntity:Map<Int,String>→ Array index → Entity         │   │
 * │   │                                                                 │   │
 * │   │  Operations:                                                    │   │
 * │   │  - add(entityId, component)    → Add or update                  │   │
 * │   │  - get(entityId) → T           → Retrieve component             │   │
 * │   │  - remove(entityId)            → Swap-remove (O(1))             │   │
 * │   │  - has(entityId) → Bool        → Existence check                │   │
 * │   │  - getAllEntityIds()           → Iterator for Query             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class ComponentStorage<T> {
    private var _components:Array<T> = [];
    private var _entityToIndex:Map<String, Int> = new Map();
    private var _indexToEntity:Map<Int, String> = new Map();
    
    public function new() {}
    
    /**
     * Add component for entity. Replaces if exists.
     */
    public function add(entityId:String, component:T):Void {
        if (_entityToIndex.exists(entityId)) {
            // Update existing
            var idx = _entityToIndex.get(entityId);
            _components[idx] = component;
            return;
        }
        // Add new
        var index = _components.length;
        _components.push(component);
        _entityToIndex.set(entityId, index);
        _indexToEntity.set(index, entityId);
    }
    
    /**
     * Get component for entity. Returns null if not found.
     */
    public function get(entityId:String):T {
        var idx = _entityToIndex.get(entityId);
        return idx != null ? _components[idx] : null;
    }
    
    /**
     * Remove component for entity.
     * Uses swap-remove for O(1) performance.
     */
    public function remove(entityId:String):Void {
        var idx = _entityToIndex.get(entityId);
        if (idx == null) return;
        
        var lastIdx = _components.length - 1;
        if (idx != lastIdx) {
            // Swap with last
            var lastEntity = _indexToEntity.get(lastIdx);
            _components[idx] = _components[lastIdx];
            _entityToIndex.set(lastEntity, idx);
            _indexToEntity.set(idx, lastEntity);
        }
        _components.pop();
        _entityToIndex.remove(entityId);
        _indexToEntity.remove(lastIdx);
    }
    
    /**
     * Check if entity has this component.
     */
    public function has(entityId:String):Bool {
        return _entityToIndex.exists(entityId);
    }
    
    /**
     * Get all entity IDs that have this component.
     * Used by Query for intersection.
     */
    public function getAllEntityIds():Iterator<String> {
        return _entityToIndex.keys();
    }
    
    /**
     * Get total count of stored components.
     */
    public function count():Int {
        return _components.length;
    }
    
    /**
     * Clear all data.
     */
    public function clear():Void {
        _components = [];
        _entityToIndex = new Map();
        _indexToEntity = new Map();
    }
}