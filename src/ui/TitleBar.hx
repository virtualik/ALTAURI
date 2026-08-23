package ui;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.Lib;

/**
 * TITLE BAR v1.3 (Editor Chrome + Window Controls)
 * Top bar for the EDITOR mode: hosts window control buttons (minimize,
 * maximize/restore) and Main.hx editor control buttons, and provides
 * native window drag + double-click maximize, mirroring DevicePanel v3.8.
 *
 * v1.3 CHANGES (true SW_MAXIMIZE round):
 *  - REMOVED: manual restore-under-cursor block — with real SW_MAXIMIZE
 *    (WindowController v1.5) DefWindowProc performs the restore dance
 *    natively during caption drag of a zoomed window.
 *
 * v1.2 CHANGES (Windows field test, round 2):
 *  - IMPROVED: restore-before-drag now REPOSITIONS the restored window
 *    under the cursor (Windows 10 caption behavior) — the cursor keeps
 *    holding the caption at the same relative grab point instead of
 *    being stranded near the top edge of the screen.
 *
 * v1.1 CHANGES (Windows field test):
 *  - ADDED: Drag-while-fullscreen now restores the window first
 *    (standard OS behavior; see onBarMouseDown).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ARCHITECTURE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ┌─────────────────────────────────────────────────────────────────────┐
 *  │  Main.hx (owns lime.ui.Window + WindowController)                   │
 *  │        ▲ callbacks                     │ delegates                  │
 *  │        │                               ▼                             │
 *  │  ┌───────────────────────────────────────────────────────────────┐  │
 *  │  │  TitleBar (Sprite, 30px, child of Main._uiLayer)              │  │
 *  │  │                                                               │  │
 *  │  │  [ Selfrun / assembly name ... ]   [?][R][N][V][E][<][-][□][X]│  │
 *  │  │    ▲ drag zone (whole bar)        └─Main 40×40─┘ └vector 28×26┘│  │
 *  │  │                                    (addControlButton)  (native) │  │
 *  │  └───────────────────────────────────────────────────────────────┘  │
 *  └─────────────────────────────────────────────────────────────────────┘
 *
 * WHY NOT INSIDE NodeEditor:
 * ─────────────────────────
 *   1. LIFECYCLE: NodeEditor is created per-context on every
 *      EditorContext.push()/pop() (entering/leaving assemblies).
 *      Window controls must survive context switches without recreation.
 *   2. OWNERSHIP: Only Main.hx may control the OS window (v3.8 pattern).
 *      The bar is a "requester" that sends callbacks upward.
 *   3. DRY: Drag + tick injection + double-click already exist in
 *      DevicePanel; this class reuses the SAME pattern via
 *      WindowController (single native bridge owner).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * BUTTON LAYOUT (right-to-left, mixed sizes)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   barWidth
 *   ├────────────────────────────────────────────────────────────────┤
 *   │  ...free drag space... [?][R][N][V][E][<]   [-]   [□]    [X]   │
 *   │                                              28×26 28×26  40×40 │
 *   │  y centering: 40×40 buttons get y=-5 (extend 5px below bar),   │
 *   │  28×26 buttons get y=+2 — same convention as DevicePanel v3.5+ │
 *   └────────────────────────────────────────────────────────────────┘
 *   Registration order in Main.buildUI(): X, <, E, V, N, R, ?
 *   → controlButtons[0] is always [X] (rightmost), the rest flow leftward
 *     AFTER the two native window buttons, preserving existing order.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * STATE SYNC (DisplayConfig = Single Source of Truth)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   User clicks [□] ──► onToggleMaximize ──► Main ──► DisplayConfig.toggleFullscreen(win)
 *                                                            │
 *   DisplayConfig.isFullscreen setter ──► FULLSCREEN_TOGGLED ─┤
 *                                                            ▼
 *   Main._onFullscreenToggled() ──► titleBar.setMaximizedState(isFullscreen)
 *                                └─► devicePanel.setMaximizedState(...) (v3.9, unchanged)
 *
 *   Editor and Device maximize buttons can NEVER diverge: both are driven
 *   by the same FULLSCREEN_TOGGLED impulse from the same DisplayConfig flag.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * DRAG MODEL (identical to DevicePanel v3.6/v3.7)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   MOUSE_DOWN on bar background
 *        │
 *        ├── button target? ──► skip drag (buttons stopPropagation anyway)
 *        │
 *        ├── Windows: WindowController.nativeStartDrag()
 *        │            SendMessage(WM_NCLBUTTONDOWN, HTCAPTION)
 *        │            + SetTimer(15ms) tick injection → UI stays alive
 *        │            (blocks until mouse-up, then returns)
 *        │
 *        └── other platforms / native failed:
 *                     absolute-delta Haxe drag
 *                     onWindowDragStart() → Main captures win.x/win.y
 *                     onWindowDrag(dx,dy) → Main sets win.x = startX + dx
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * HTML5 NOTES
 * ═══════════════════════════════════════════════════════════════════════════
 *   - Minimize button is hidden (no OS taskbar concept in browser).
 *   - Maximize works: routes to Browser Fullscreen API via DisplayConfig.
 *   - Drag is a harmless no-op (lime Window.x setter ignores writes).
 */
class TitleBar extends Sprite
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /** Fixed bar height. Matches DevicePanel header height (DisplayConfig.headerHeight). */
    public static inline var BAR_HEIGHT:Float = 30;

    /** Bar background color — matches DevicePanel header (0x2a2a34) for
        consistent chrome across Editor and Device modes. */
    private static inline var BG_COLOR:Int = 0x2a2a34;

    /** Small button background color — matches DevicePanel [C]/[□] buttons. */
    private static inline var BTN_COLOR:Int = 0x555500;

    // =========================================================================
    // CALLBACKS (wired by Main.hx)
    // =========================================================================

    /**
     * Request toggling maximize/restore of the main OS window.
     * Triggered by [□]/[◱] button click OR double-click on bar background.
     * Main implementation: DisplayConfig.toggleFullscreen(win).
     */
    public var onToggleMaximize:Void -> Void;

    /**
     * Request minimizing the window to taskbar.
     * Triggered by [-] button click.
     * Main implementation: WindowController.getInstance().minimize().
     * Hidden on HTML5 (no taskbar concept).
     */
    public var onMinimize:Void -> Void;

    /**
     * Haxe-side drag fallback: called once at drag start.
     * Main must capture current window position (win.x, win.y).
     */
    public var onWindowDragStart:Void -> Void;

    /**
     * Haxe-side drag fallback: called with DELTA from drag START
     * (absolute model — prevents accumulated rounding flicker).
     * Main must set win.x = startX + dx, win.y = startY + dy.
     */
    public var onWindowDrag:Float -> Float -> Void;

    // =========================================================================
    // PRIVATE FIELDS
    // =========================================================================

    /** Minimize button (28×26) with vector icon */
    private var _minBtn:Sprite;

    /** Maximize/Restore button (28×26) with vector icon */
    private var _maxBtn:Sprite;

    /** Icon sprite inside _maxBtn — redrawn on state change */
    private var _maxIcon:Sprite;

    /** Current maximize state mirror (icon selection only; truth is DisplayConfig) */
    private var _isMaximized:Bool = false;

    /**
     * Main's editor control buttons (40×40), registered right-to-left via
     * addControlButton(). Index 0 = [X] close (rightmost), then <, E, V, N, R, ?
     */
    private var _controlButtons:Array<Sprite> = [];

    /** Haxe-side drag state (absolute position model) */
    private var _dragging:Bool = false;
    private var _mouseStartX:Float = 0;
    private var _mouseStartY:Float = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new()
    {
        super();

        // Background (initial 800×30; resized by setSize)
        graphics.beginFill(BG_COLOR);
        graphics.drawRect(0, 0, 800, BAR_HEIGHT);
        graphics.endFill();

        // --- Minimize button [-] (vector icon, no text glyph) ---
        _minBtn = makeSmallButton(function(_)
        {
            if (onMinimize != null) onMinimize();
        });
        WindowGlyphs.drawMinimize(_minBtn.graphics, smallBtnW(), smallBtnH(), 0xFFFFFF);
        addChild(_minBtn);

        #if html5
        // No taskbar in the browser — hide minimize entirely
        _minBtn.visible = false;
        #end

        // --- Maximize/Restore button [□]/[◱] (vector icon, no text glyph) ---
        _maxBtn = makeSmallButton(function(_)
        {
            if (onToggleMaximize != null) onToggleMaximize();
        });
        _maxIcon = new Sprite();
        WindowGlyphs.drawMaximize(_maxIcon.graphics, smallBtnW(), smallBtnH(), 0xFFFFFF);
        _maxBtn.addChild(_maxIcon);
        addChild(_maxBtn);

        // --- Drag + double-click on bar background ---
        addEventListener(MouseEvent.MOUSE_DOWN, onBarMouseDown);
        doubleClickEnabled = true;
        addEventListener(MouseEvent.DOUBLE_CLICK, onBarDoubleClick);
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================

    /**
     * Register one of Main's editor control buttons (40×40) into the bar.
     * Buttons are laid out right-to-left in registration order.
     * Registration order in buildUI(): X, <, E, V, N, R, ?
     * → controlButtons[0] ([X]) is placed rightmost, directly next to [□].
     *
     * The button is re-parented INTO the bar (addChild), so Main must NOT
     * add it to _uiLayer separately anymore.
     */
    public function addControlButton(btn:Sprite):Void
    {
        if (btn == null) return;
        addChild(btn);
        _controlButtons.push(btn);
    }

    /**
     * Resize the bar and re-layout ALL buttons (native small buttons +
     * registered control buttons) in the right-to-left flow.
     *
     * Called by Main.layoutChrome() on: buildUI, stage RESIZE, SCENE_RESIZED.
     *
     * @param w New bar width  (stage.stageWidth)
     * @param h Unused (bar height is constant) — kept for setSize(w,h) symmetry
     */
    public function setSize(w:Float, h:Float = 0):Void
    {
        var cfg = DisplayConfig.getInstance();
        var pad:Float = cfg.buttonPadding;
        var sw:Float = cfg.smallButtonWidth;
        var sh:Float = cfg.smallButtonHeight;

        // Redraw background
        graphics.clear();
        graphics.beginFill(BG_COLOR);
        graphics.drawRect(0, 0, w, BAR_HEIGHT);
        graphics.endFill();

        var cursor:Float = w - pad;

        // 1. Close button [X] (first registered control button, 40×40, y=-5)
        if (_controlButtons.length > 0)
        {
            var closeBtn = _controlButtons[0];
            closeBtn.x = cursor - closeBtn.width;
            closeBtn.y = (BAR_HEIGHT - closeBtn.height) * 0.5; // = -5
            cursor = closeBtn.x - pad;
        }

        // 2. Maximize/Restore [□] (28×26, vertically centered)
        _maxBtn.x = cursor - sw;
        _maxBtn.y = (BAR_HEIGHT - sh) * 0.5;
        cursor = _maxBtn.x - pad;

        // 3. Minimize [-] (28×26)
        if (_minBtn.visible)
        {
            _minBtn.x = cursor - sw;
            _minBtn.y = (BAR_HEIGHT - sh) * 0.5;
            cursor = _minBtn.x - pad;
        }
        else
        {
            // Hidden (HTML5): keep position off-screen-left so the following
            // control buttons do not leave a phantom gap
            _minBtn.x = cursor - sw;
            _minBtn.y = (BAR_HEIGHT - sh) * 0.5;
            cursor = _minBtn.x - pad;
        }

        // 4. Remaining control buttons (<, E, V, N, R, ?) leftward
        for (i in 1..._controlButtons.length)
        {
            var b = _controlButtons[i];
            b.x = cursor - b.width;
            b.y = (BAR_HEIGHT - b.height) * 0.5; // = -5 for 40×40
            cursor = b.x - pad;
        }
    }

    /**
     * Update the maximize button icon from the actual fullscreen state.
     * Called by Main._onFullscreenToggled() (FULLSCREEN_TOGGLED impulse).
     *
     * @param isMaximized true = draw "restore" stacked squares,
     *                    false = draw "maximize" single square
     */
    public function setMaximizedState(isMaximized:Bool):Void
    {
        _isMaximized = isMaximized;
        if (_maxIcon == null) return;

        _maxIcon.graphics.clear();
        if (_isMaximized)
        {
            WindowGlyphs.drawRestore(_maxIcon.graphics, smallBtnW(), smallBtnH(), 0xFFFFFF, BTN_COLOR);
        }
        else
        {
            WindowGlyphs.drawMaximize(_maxIcon.graphics, smallBtnW(), smallBtnH(), 0xFFFFFF);
        }
    }

    // =========================================================================
    // SMALL BUTTON FACTORY
    // =========================================================================

    /**
     * Create a 28×26 small button (same geometry/style as DevicePanel
     * header buttons). Icon is painted by the caller directly into the
     * button's own graphics — NO TextField, NO text glyph.
     *
     * MOUSE_DOWN is stopped from bubbling so bar drag never triggers
     * when pressing a button (defense-in-depth with onBarMouseDown guard).
     */
    private function makeSmallButton(onClick:MouseEvent -> Void):Sprite
    {
        var w = smallBtnW();
        var h = smallBtnH();

        var btn = new Sprite();
        btn.graphics.beginFill(BTN_COLOR);
        btn.graphics.drawRect(0, 0, w, h);
        btn.graphics.endFill();

        btn.buttonMode = true;
        btn.addEventListener(MouseEvent.CLICK, onClick);
        btn.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) e.stopPropagation());

        return btn;
    }

    /** Small button width from DisplayConfig (28) */
    private function smallBtnW():Float return DisplayConfig.getInstance().smallButtonWidth;

    /** Small button height from DisplayConfig (26) */
    private function smallBtnH():Float return DisplayConfig.getInstance().smallButtonHeight;

    // =========================================================================
    // DRAG HANDLERS (absolute position model — see DevicePanel v3.5/v3.7)
    // =========================================================================

    /**
     * MOUSE_DOWN on bar background → start window drag.
     * 1. Skip if target is a button (walk-up guard, DevicePanel pattern)
     * 2. Windows: try native drag via WindowController (perfect 1:1 tracking,
     *    tick injection keeps rendering at ~60 FPS during modal loop)
     * 3. Fallback: Haxe-side absolute-delta drag
     */
    private function onBarMouseDown(e:MouseEvent):Void
    {
        if (_dragging) return;

        // Guard: click landed on a button (buttonMode + direct child of bar)
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != this)
        {
            if (Std.isOfType(targetObj, Sprite))
            {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == this) return;
            }
            targetObj = targetObj.parent;
        }

        // --- Native Windows drag first ---
        #if windows
        // =================================================================
        // v1.3 NOTE: With true SW_MAXIMIZE (WindowController v1.5) the
        // native caption drag performs the restore-under-cursor dance
        // AUTOMATICALLY when the user drags a zoomed window — the former
        // manual reposition block was removed because it would fight the
        // OS behavior (double restore, lost cursor ratio).
        // DisplayConfig.isFullscreen is re-synced by Main.onResize (IsZoomed)
        // right after the modal loop returns.
        // =================================================================
        if (WindowController.getInstance().nativeStartDrag())
        {
            return; // Modal drag completed (user released mouse)
        }
        #end

        // --- Haxe-side fallback (non-Windows or native failed) ---
        _dragging = true;
        _mouseStartX = e.stageX;
        _mouseStartY = e.stageY;

        if (onWindowDragStart != null) onWindowDragStart();

        if (stage != null)
        {
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onBarMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onBarMouseUp);
        }
    }

    /** MOUSE_MOVE during Haxe-side drag — delta from START (no accumulation) */
    private function onBarMouseMove(e:MouseEvent):Void
    {
        if (!_dragging) return;
        var dx = e.stageX - _mouseStartX;
        var dy = e.stageY - _mouseStartY;
        if (onWindowDrag != null) onWindowDrag(dx, dy);
    }

    /** MOUSE_UP — end Haxe-side drag, remove stage listeners */
    private function onBarMouseUp(_:MouseEvent):Void
    {
        _dragging = false;
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onBarMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onBarMouseUp);
        }
    }

    // =========================================================================
    // DOUBLE-CLICK (standard OS title bar behavior)
    // =========================================================================

    /**
     * Double-click on bar background toggles maximize/restore
     * (same as DevicePanel v3.8). Button targets are skipped.
     */
    private function onBarDoubleClick(e:MouseEvent):Void
    {
        var targetObj:openfl.display.DisplayObject = cast e.target;
        while (targetObj != null && targetObj != this)
        {
            if (Std.isOfType(targetObj, Sprite))
            {
                var s = cast(targetObj, Sprite);
                if (s.buttonMode && targetObj.parent == this) return;
            }
            targetObj = targetObj.parent;
        }

        if (onToggleMaximize != null) onToggleMaximize();
    }
}
