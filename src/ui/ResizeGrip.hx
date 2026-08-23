package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.Lib;

/**
 * RESIZE GRIP v1.0 (Manual Window Resize — Corner Grip)
 * Bottom-right corner grip that allows the user to manually resize the
 * main OS window in BOTH display modes (Editor and Device Panel).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ┌───────────────────────────────────────────────────────────────────┐
 *  │  Main Window                                                      │
 *  │  ┌─────────────────────────────────────────────────────────────┐  │
 *  │  │  Editor / Device content                                     │  │
 *  │  │                                                              │  │
 *  │  │                                                  ╱          │  │
 *  │  │                                               ╱   ← grip    │  │
 *  │  │                                   Main root   ╱    20×20    │  │
 *  │  └─────────────────────────────────────────────────╱───────────┘  │
 *  └───────────────────────────────────────────────────────────────────┘
 *
 *  Parent: Main root (added AFTER _settingsLayer → always on top,
 *  visible in both Editor and Device modes, hidden on HTML5).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * RESIZE STRATEGY (mirrors the v3.7 native drag pattern)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  MOUSE_DOWN on grip
 *        │
 *        ├── Windows: WindowController.nativeStartResize(HTBOTTOMRIGHT)
 *        │     SetTimer(15ms) tick injection (SAME timer/tick as drag)
 *        │     temporarily adds WS_THICKBOX to the borderless window
 *        │     SendMessage(WM_NCLBUTTONDOWN, HTBOTTOMRIGHT)
 *        │        → Windows enters the MODAL NATIVE RESIZE LOOP
 *        │        → DefWindowProc tracks the mouse, redraws, enforces
 *        │          native min-tracking size, live-updates WM_SIZE
 *        │     blocks until mouse-up, then restores borderless style
 *        │
 *        └── other platforms / native failed:
 *              Haxe-side fallback (absolute-delta model):
 *              capture start size + start mouse
 *              on MOUSE_MOVE: nw = max(MIN_W, startW + dx)
 *                             nh = max(MIN_H, startH + dy)
 *              win.resize(nw, nh)
 *
 *  After mouse-up: Lime fires stage RESIZE → Main.onResize →
 *  DisplayConfig.sceneWidth/Height → SCENE_RESIZED → NodeEditor.setSize /
 *  DevicePanel.setSize. The whole re-layout pipe ALREADY EXISTS.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * HTML5
 * ═══════════════════════════════════════════════════════════════════════════
 *  The browser owns the canvas size — manual resize is meaningless.
 *  Main.hx must NOT instantiate the grip on html5 (#if !html5 guard),
 *  so no extra visibility screening is needed inside this class.
 */
class ResizeGrip extends Sprite
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /** Grip square side (px) */
    public static inline var SIZE:Float = 20;

    /** Minimum window width enforced by Haxe fallback resize */
    public static inline var MIN_WIDTH:Int = 640;

    /** Minimum window height enforced by Haxe fallback resize */
    public static inline var MIN_HEIGHT:Int = 400;

    // =========================================================================
    // PUBLIC FIELDS (wired by Main.hx)
    // =========================================================================

    /**
     * WindowController reference for native Windows resize.
     * Assigned by Main: _resizeGrip.windowController = _windowController.
     * If null (or non-Windows), the Haxe fallback is used automatically.
     */
    public var windowController:WindowController;

    // =========================================================================
    // PRIVATE FIELDS (Haxe fallback state)
    // =========================================================================

    private var _dragging:Bool = false;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;
    private var _startW:Int = 0;
    private var _startH:Int = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new()
    {
        super();

        // Subtle background + diagonal hatch (classic Windows grip look)
        graphics.beginFill(0x2a2a34, 0.6);
        graphics.drawRect(0, 0, SIZE, SIZE);
        graphics.endFill();
        WindowGlyphs.drawGripHatch(graphics, SIZE, 0xAAAAAA);

        buttonMode = true;
        useHandCursor = true;
        mouseChildren = false;

        addEventListener(MouseEvent.MOUSE_DOWN, onGripMouseDown);
    }

    // =========================================================================
    // HANDLERS
    // =========================================================================

    /**
     * Start resize: native modal loop on Windows, Haxe fallback elsewhere.
     */
    private function onGripMouseDown(e:MouseEvent):Void
    {
        if (_dragging) return;

        // --- Native Windows resize first (bottom-right edge) ---
        #if windows
        if (windowController != null && windowController.nativeStartResize(WindowController.EDGE_BOTTOM_RIGHT))
        {
            return; // Modal resize completed (user released mouse)
        }
        #end

        // --- Haxe-side fallback (absolute-delta model with min clamp) ---
        var win = Lib.current.stage.window;
        if (win == null) return;

        _dragging = true;
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;
        _startW = win.width;
        _startH = win.height;

        if (stage != null)
        {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onGripMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onGripMouseUp);
        }
    }

    /**
     * MOUSE_MOVE during Haxe fallback resize.
     * New size = start size + delta, clamped to MIN_WIDTH/MIN_HEIGHT.
     */
    private function onGripMouseMove(e:MouseEvent):Void
    {
        if (!_dragging) return;

        var win = Lib.current.stage.window;
        if (win == null) return;

        var dx = e.stageX - _mouseStartX;
        var dy = e.stageY - _mouseStartY;

        var nw = Std.int(Math.max(MIN_WIDTH, _startW + dx));
        var nh = Std.int(Math.max(MIN_HEIGHT, _startH + dy));

        // Skip redundant resize calls (avoid Lime spam at pixel-level jitter)
        if (nw != win.width || nh != win.height)
        {
            win.resize(nw, nh);
        }
    }

    /** MOUSE_UP — end Haxe fallback resize, remove stage listeners */
    private function onGripMouseUp(_:MouseEvent):Void
    {
        _dragging = false;
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onGripMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onGripMouseUp);
        }
    }
}
