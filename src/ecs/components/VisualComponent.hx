package ecs.components;

import openfl.display.Sprite;

/**
 * VISUAL COMPONENT v1.0
 * Holds OpenFL sprite reference. Pure data, no logic.
 * 
 * Used by:
 * - RenderSystem (for drawing)
 * - Query (for selection checks)
 * 
 * Replaces direct sprite references in NodeView.
 */
class VisualComponent {
    
    /**
     * The display object to render.
     */
    public var sprite:Sprite;
    
    /**
     * Selection state.
     */
    public var isSelected:Bool = false;
    
    /**
     * Visibility flag.
     */
    public var isVisible:Bool = true;
    
    /**
     * Optional: custom alpha when not selected.
     */
    public var baseAlpha:Float = 0.85;
    
    /**
     * Optional: custom alpha when selected.
     */
    public var selectedAlpha:Float = 1.0;

    public function new(sprite:Sprite) {
        this.sprite = sprite;
    }

    /**
     * Apply selection visual.
     */
    public function applySelectionVisual():Void {
        sprite.alpha = isSelected ? selectedAlpha : baseAlpha;
    }

    /**
     * Show/hide the sprite.
     */
    public function applyVisibility():Void {
        sprite.visible = isVisible;
    }
}
