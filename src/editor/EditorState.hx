package editor;

/**
 * EDITOR STATE v1.0
 * Global state for editor coordination between components.
 *
 * Purpose:
 * - Track zoom state across ViewportManager and NodeView
 * - Prevent mass DeviceView activation during zoom
 * - Centralized state for editor-wide coordination
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   EditorState (Static)                                                  │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Global Flags:                                                  │   │
 * │   │  - _isZooming:Bool   → ViewportManager sets during zoom         │   │
 * │   │  - _isPanning:Bool   → ViewportManager sets during pan          │   │
 * │   │                                                                 │   │
 * │   │  Public API:                                                    │   │
 * │   │  - setIsZooming(value)                                          │   │
 * │   │  - isZooming() → Bool                                           │   │
 * │   │  - setIsPanning(value)                                          │   │
 * │   │  - isPanning() → Bool                                           │   │
 * │   │  - reset()                                                      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage Example:                                                        │
 * │   ───────────────                                                       │
 * │   // In ViewportManager:                                                │
 * │   EditorState.setIsZooming(true);  // Start zoom                        │
 * │   ... zoom operation ...                                                │
 * │   EditorState.setIsZooming(false); // End zoom                          │
 * │                                                                         │
 * │   // In NodeView:                                                       │
 * │   if (!EditorState.isZooming()) {                                       │
 * │       activateDeviceView();  // Defer during zoom                       │
 * │   }                                                                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class EditorState
{
    // =========================================================================
    // STATE FLAGS
    // =========================================================================
    private static var _isZooming:Bool = false;
    private static var _isPanning:Bool = false;
    
    // =========================================================================
    // ZOOM STATE
    // =========================================================================
    /**
     * Set zoom state.
     * Called by ViewportManager during zoom operations.
     * 
     * @param value true = zoom in progress, false = zoom complete
     */
    public static function setIsZooming(value:Bool):Void
    {
        _isZooming = value;
    }
    
    /**
     * Check if zoom is in progress.
     * Called by NodeView to defer DeviceView activation.
     * 
     * @return true if zoom operation is active
     */
    public static function isZooming():Bool
    {
        return _isZooming;
    }
    
    // =========================================================================
    // PAN STATE
    // =========================================================================
    /**
     * Set pan state.
     * Called by ViewportManager during pan operations.
     * 
     * @param value true = pan in progress, false = pan complete
     */
    public static function setIsPanning(value:Bool):Void
    {
        _isPanning = value;
    }
    
    /**
     * Check if pan is in progress.
     * 
     * @return true if pan operation is active
     */
    public static function isPanning():Bool
    {
        return _isPanning;
    }
    
    // =========================================================================
    // RESET
    // =========================================================================
    /**
     * Reset all states to default.
     * Called on editor reset or hard reload.
     */
    public static function reset():Void
    {
        _isZooming = false;
        _isPanning = false;
    }
}