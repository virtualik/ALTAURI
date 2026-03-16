package editor;

/**
 * EDITOR STATE v1.0
 * Глобальное состояние редактора для координации между компонентами.
 * 
 * Purpose:
 * - Track zoom state across ViewportManager and NodeView
 * - Prevent mass DeviceView activation during zoom
 * - Centralized state for editor-wide coordination
 */
class EditorState {
    private static var _isZooming:Bool = false;
    private static var _isPanning:Bool = false;
    
    /**
     * Set zoom state.
     * Called by ViewportManager during zoom operations.
     */
    public static function setIsZooming(value:Bool):Void {
        _isZooming = value;
    }
    
    /**
     * Check if zoom is in progress.
     * Called by NodeView to defer DeviceView activation.
     */
    public static function isZooming():Bool {
        return _isZooming;
    }
    
    /**
     * Set pan state.
     */
    public static function setIsPanning(value:Bool):Void {
        _isPanning = value;
    }
    
    /**
     * Check if pan is in progress.
     */
    public static function isPanning():Bool {
        return _isPanning;
    }
    
    /**
     * Reset all states.
     */
    public static function reset():Void {
        _isZooming = false;
        _isPanning = false;
    }
}