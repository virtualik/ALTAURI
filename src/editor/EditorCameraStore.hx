package editor;

/**
 * EDITOR CAMERA STORE v1.0
 * ═══════════════════════════════════════════════════════════════════════════
 * EXTRACTED FROM EditorContext v2.13 — Episod C of the Editor de-god-ification.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Stateless-with-respect-to-current-assembly storage for per-blueprint camera
 * states. Each assembly (identified by blueprint.id) gets its own viewport
 * snapshot, restored whenever the user re-enters that assembly.
 *
 * EditorContext lifecycle hooks:
 *   ─ push(assembly)    → if has(bpId) get(bpId) → editor.setViewState(state)
 *                          else editor.centerOnContent()
 *   ─ pop()             → save(editedId, currentEditor.getViewState())
 *   ─ clear()           → clear()
 *
 * NOTE on separation from EditorEntry.parentCameraState:
 *   EditorEntry.parentCameraState is a PER-STACK-ENTRY scratch — captured in
 *   push() so that the NEXT pop() can restore the immediate parent viewport.
 *   It belongs to the stack data structure (one entry = one drill-down).
 *
 *   EditorCameraStore._states is a CROSS-PUSH/POP PERSISTENT store — survives
 *   across multiple enter/exit cycles for the same blueprint.id. It belongs
 *   to the long-term editor session state.
 *
 *   Mixing them would conflate per-stack-entry scratch with persistent state,
 *   which is why this class exists: to make the boundary explicit.
 *
 * Why this class is "stateful" (not stateless like PortNameResolver /
 * BlueprintSynchronizer):
 *   Camera state MUST be persisted somewhere; the alternative is passing
 *   the Map through every call site. Since the store has no other behaviour
 *   than get/save/has/clear, encapsulating the Map here keeps EditorContext
 *   free of the storage concern while preserving the only legitimate state
 *   in the editor subsystem.
 *
 * Migration guide for EditorContext callers:
 *   ─ _cameraStates = new Map()                    → _camStore = new EditorCameraStore()
 *   ─ _cameraStates.exists(bpId)                   → _camStore.has(bpId)
 *   ─ _cameraStates.get(bpId)                      → _camStore.get(bpId)
 *   ─ _cameraStates.set(bpId, state)               → _camStore.save(bpId, state)
 *   ─ _cameraStates.clear()                        → _camStore.clear()
 */
class EditorCameraStore
{
        /** Map: blueprint.id → {x, y, zoom} */
        private var _states:Map<String, {x:Float, y:Float, zoom:Float}>;

        public function new()
        {
                _states = new Map();
        }

        /**
         * Returns true if a saved viewport state exists for the given
         * blueprint.id.
         */
        public function has(bpId:String):Bool
        {
                return _states.exists(bpId);
        }

        /**
         * Returns the saved viewport state for the given blueprint.id,
         * or null if none has been saved.
         *
         * Caller (EditorContext.push) uses this to restore the camera when
         * re-entering an assembly the user has previously visited.
         */
        public function get(bpId:String):{x:Float, y:Float, zoom:Float}
        {
                return _states.get(bpId);
        }

        /**
         * Stores the viewport state for the given blueprint.id.
         *
         * Caller (EditorContext.pop) uses this on exit so the next enter
         * restores the camera the user left behind.
         */
        public function save(bpId:String, state:{x:Float, y:Float, zoom:Float}):Void
        {
                _states.set(bpId, state);
        }

        /**
         * Wipes all stored camera states.
         *
         * Called by EditorContext.clear() on project reload — a fresh
         * project has no previously-visited assemblies to restore.
         */
        public function clear():Void
        {
                _states.clear();
        }
}
