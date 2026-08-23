package ui;

import openfl.display.Graphics;

/**
 * WINDOW GLYPHS v1.0 (Vector Window Control Icons)
 * Pure-vector painter for window control icons: maximize, restore, minimize, close.
 *
 * WHY VECTOR INSTEAD OF TEXT GLYPHS:
 * ────────────────────────────────
 * Text glyphs like "◱" (U+25F1) are missing from common fonts such as Arial.
 * Lime/FreeType on C++ targets has NO font fallback chain — a missing glyph
 * renders as tofu (empty box) or nothing at all. Vector drawing is 100%
 * font-independent, pixel-perfect on every target (Windows, Android, HTML5),
 * and matches the crisp look of native Windows 10/11 caption buttons.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * GLYPH CATALOG (drawn for a 28×26 small button canvas)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   MAXIMIZE                    RESTORE                      MINIMIZE
 *   (windowed → click           (fullscreen → click          (collapse window
 *    to go fullscreen)           to go windowed)              to taskbar)
 *
 *   ┌──────────────┐            ┌──────────────┐             ┌──────────────┐
 *   │              │            │         ┌────┼──┐          │              │
 *   │   ┌──────┐   │            │   ┌────┼────┼──┘          │              │
 *   │   │      │   │            │   │    │    │             │   ________   │
 *   │   │      │   │            │   └────┼────┘             │              │
 *   │   └──────┘   │            │        └─── (back square   │              │
 *   │              │            │         partially hidden    │              │
 *   └──────────────┘            └───────── by front square) ──┴──────────────┘
 *
 *   CLOSE (reserved for future use)        GRIP HATCH (resize corner)
 *   ┌──────────────┐                       ┌──────────────┐
 *   │   \      /   │                       │          ╱   │
 *   │    \    /    │                       │       ╱      │
 *   │     \  /     │                       │    ╱         │
 *   │      \/      │                       │ ╱            │
 *   │      /\      │                       │(3 anti-       │
 *   │     /  \     │                       │ diagonal      │
 *   └──────────────┘                       │  strokes)     └
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * USAGE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   var icon = new Sprite();
 *   WindowGlyphs.drawMaximize(icon.graphics, 28, 26, 0xFFFFFF);
 *   button.addChild(icon);
 *
 *   // Later, when window state changes:
 *   icon.graphics.clear();
 *   WindowGlyphs.drawRestore(icon.graphics, 28, 26, 0xFFFFFF, 0x555500);
 *
 * All functions are CLEAR-FREE: the caller is responsible for graphics.clear().
 * All functions are stateless statics — zero allocation, Zero-GC friendly.
 */
class WindowGlyphs
{
    // =========================================================================
    // GEOMETRY CONSTANTS
    // =========================================================================

    /** Stroke thickness of icon lines */
    private static inline var STROKE:Float = 1.5;

    /** Side of the maximize square */
    private static inline var MAX_SIZE:Float = 12.0;

    /** Side of each restore square */
    private static inline var RESTORE_SIZE:Float = 11.0;

    /** Half-length of the minimize line */
    private static inline var MIN_HALF:Float = 6.0;

    /** Vertical offset of the minimize line below button center */
    private static inline var MIN_DROP:Float = 5.0;

    /** Offset of the back square relative to front square center (restore) */
    private static inline var RESTORE_BACK_SHIFT:Float = 5.0;

    // =========================================================================
    // MAXIMIZE
    // =========================================================================

    /**
     * Draw a "maximize" icon: single outlined square, centered in w×h.
     *
     * @param g        Target graphics (caller must call g.clear() first)
     * @param w        Canvas width  (button width,  e.g. 28)
     * @param h        Canvas height (button height, e.g. 26)
     * @param color    Stroke color (e.g. 0xFFFFFF)
     */
    public static function drawMaximize(g:Graphics, w:Float, h:Float, color:Int):Void
    {
        var x = (w - MAX_SIZE) * 0.5;
        var y = (h - MAX_SIZE) * 0.5;

        g.lineStyle(STROKE, color);
        g.drawRect(x, y, MAX_SIZE, MAX_SIZE);
    }

    // =========================================================================
    // RESTORE
    // =========================================================================

    /**
     * Draw a "restore" icon: two overlapping outlined squares (Windows 10/11
     * style). The front square is filled with bgColor so the back square's
     * hidden edges are cleanly masked — this is what creates the "stacked
     * windows" illusion.
     *
     * @param g        Target graphics (caller must call g.clear() first)
     * @param w        Canvas width
     * @param h        Canvas height
     * @param color    Stroke color (e.g. 0xFFFFFF)
     * @param bgColor  Opaque fill of the front square = button background
     *                 color (e.g. 0x555500). MUST be opaque to mask properly.
     */
    public static function drawRestore(g:Graphics, w:Float, h:Float, color:Int, bgColor:Int):Void
    {
        var cx = w * 0.5;
        var cy = h * 0.5;

        // Back square: shifted up-right from center
        var backX = cx + RESTORE_BACK_SHIFT - RESTORE_SIZE * 0.5;
        var backY = cy - RESTORE_SIZE * 0.5 - RESTORE_BACK_SHIFT * 0.5;

        // Front square: shifted down-left from center
        var frontX = cx - RESTORE_SIZE * 0.5 - RESTORE_BACK_SHIFT * 0.5;
        var frontY = cy + RESTORE_BACK_SHIFT * 0.5 - RESTORE_SIZE * 0.5;

        // 1. Draw back square outline
        g.lineStyle(STROKE, color);
        g.drawRect(backX, backY, RESTORE_SIZE, RESTORE_SIZE);

        // 2. Draw front square: opaque fill FIRST (masks back square edges),
        //    then outline on top
        g.lineStyle();
        g.beginFill(bgColor, 1.0);
        g.drawRect(frontX, frontY, RESTORE_SIZE, RESTORE_SIZE);
        g.endFill();

        g.lineStyle(STROKE, color);
        g.drawRect(frontX, frontY, RESTORE_SIZE, RESTORE_SIZE);
    }

    // =========================================================================
    // MINIMIZE
    // =========================================================================

    /**
     * Draw a "minimize" icon: single horizontal line below center
     * (Windows caption button convention).
     *
     * @param g        Target graphics (caller must call g.clear() first)
     * @param w        Canvas width
     * @param h        Canvas height
     * @param color    Stroke color
     */
    public static function drawMinimize(g:Graphics, w:Float, h:Float, color:Int):Void
    {
        var cx = w * 0.5;
        var cy = h * 0.5 + MIN_DROP;

        g.lineStyle(STROKE, color);
        g.moveTo(cx - MIN_HALF, cy);
        g.lineTo(cx + MIN_HALF, cy);
    }

    // =========================================================================
    // CLOSE (reserved for future use)
    // =========================================================================

    /**
     * Draw a "close" X icon: two crossing diagonal lines.
     * Reserved for a future vector close button (currently the app uses
     * ButtonComponent "X" text label, which renders fine in all fonts).
     *
     * @param g        Target graphics (caller must call g.clear() first)
     * @param w        Canvas width
     * @param h        Canvas height
     * @param color    Stroke color
     */
    public static function drawClose(g:Graphics, w:Float, h:Float, color:Int):Void
    {
        var pad = w * 0.3;
        g.lineStyle(STROKE, color);
        g.moveTo(pad, pad);
        g.lineTo(w - pad, h - pad);
        g.moveTo(w - pad, pad);
        g.lineTo(pad, h - pad);
    }

    // =========================================================================
    // RESIZE GRIP HATCH
    // =========================================================================

    /**
     * Draw diagonal hatch strokes for a corner resize grip
     * (classic Windows bottom-right "grip" visual).
     *
     * @param g        Target graphics
     * @param size     Grip square side (e.g. 20)
     * @param color    Stroke color (e.g. 0xAAAAAA)
     */
    public static function drawGripHatch(g:Graphics, size:Float, color:Int):Void
    {
        var inset = 3.0;
        g.lineStyle(2.0, color);

        // Three parallel anti-diagonal strokes
        for (i in 0...3)
        {
            var off = i * 5.0;
            g.moveTo(inset + off, size - inset);
            g.lineTo(size - inset, inset + off);
        }
    }
}
