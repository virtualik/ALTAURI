package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.ui.Keyboard;
import core.base.Atom;
import core.base.Contact;
import core.logic.Impulsys;
import core.logic.EventType;
import library.electro.TextAreaAtom;

/**
 * TEXT AREA WIDGET v1.2 (Contact Name Fix + Mouse Wheel Scroll)
 *
 * Visual component (Face) for TextAreaAtom.
 * Provides a multi-line text editing area with configurable dimensions,
 * custom-drawn scrollbars, word wrap, and auto-scroll behavior.
 *
 * Architecture: "ATOM IS DATABANK & COMPUTE CORE"
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   TextAreaAtom (Databank)                                               │
 * │                                                                         │
 * │   Contact "textIn"    ◄─── TextAreaWidget (user input → atom)           │
 * │   Contact "textOut"   ───► TextAreaWidget (atom → display)              │
 * │   Contact "append"    ───► TextAreaWidget (external append → display)   │
 * │   Contact "editable"  ───► TextAreaWidget (enable/disable)              │
 * │   Contact "wordWrap"  ───► TextAreaWidget                               │
 * │   Contact "autoScroll"───► TextAreaWidget                               │
 * │   Contact "hScroll"   ───► TextAreaWidget                               │
 * │   Contact "vScroll"   ───► TextAreaWidget                               │
 * │   Contact "maxChars"  ───► TextAreaWidget (width)                       │
 * │   Contact "numLines"  ───► TextAreaWidget (height)                      │
 * │                                                                         │
 * │   Widget READS config from atom's contacts.                             │
 * │   Widget WRITES to atom via setTextFromWidget().                        │
 * │   Atom is the Databank — single source of truth.                        │
 * │                                                                         │
 * │   v1.2 CONTACT NAME CONTRACT (CRITICAL):                                │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Widget subscribes to: "textOut" (output) for text updates      │   │
 * │   │  Widget writes to:     "textIn"  (input)  for user edits        │   │
 * │   │                                                                 │   │
 * │   │  NEVER use "text" as contact name — it doesn't exist!           │   │
 * │   │  Atom has: "textIn" (input) and "textOut" (output).             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │   Widget READS config from atom's contacts.                             │
 * │   Widget WRITES to atom via setTextFromWidget().                        │
 * │   Atom is the Databank — single source of truth.                        │
 * │                                                                         │
 * │   ┌───────────────────────────────────────────────────────────────┐     │
 * │   │  ┌─────────────────────────────────────────────────────────┐  │     │
 * │   │  │  Line 1: Hello World                                    │▐ │     │
 * │   │  │  Line 2: This is a TextArea widget                      │▐ │     │
 * │   │  │  Line 3: with configurable parameters                   │▐ │     │
 * │   │  │  Line 4:                                                │█ │     │
 * │   │  │  Line 5:                                                │█ │     │
 * │   │  │  Line 6:                                                │█ │     │
 * │   │  │  Line 7:                                                │▄ │     │
 * │   │  │  Line 8:                                                │  │     │
 * │   │  └─────────────────────────────────────────────────────────┘  │     │
 * │   │  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀  │     │
 * │   │  Lines: 8 | Cursor: 3                                         │     │
 * │   └───────────────────────────────────────────────────────────────┘     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Sizing Formula:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  charWidth  = 8px  (monospace _typewriter at 12pt)                      │
 * │  lineHeight = 18px                                                      │
 * │  padding    = 8px                                                       │
 * │  scrollbar  = 14px (custom drawn)                                       │
 * │                                                                         │
 * │  widgetWidth  = maxChars × charWidth + padding×2 + (vScroll ? 14 : 0)   │
 * │  widgetHeight = numLines × lineHeight + padding×2 + (hScroll ? 14 : 0)  │
 * │                 + statusBarHeight(18)                                   │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v1.2 Changes:
 * - FIXED: syncFromAtom() now reads getOutput("textOut") instead of "text"
 * - FIXED: onContactChanged() now handles case "textOut" instead of "text"
 * - FIXED: onTextChange() fallback now writes to getInput("textIn")
 * - ADDED: MouseEvent.MOUSE_WHEEL handler with stopPropagation()
 *   to prevent scroll events from reaching parent NodeEditor (zoom).
 * - ADDED: Manual scrollV/scrollH adjustment on wheel for INPUT mode
 *   (OpenFL TextField doesn't always auto-scroll on wheel in INPUT mode).
 * - FIXED: updateScrollbarThumbs() called after wheel scroll for
 *   synchronous thumb position update.
 *
 * Sizing Formula:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  charWidth  = 8px  (monospace _typewriter at 12pt)                     │
 * │  lineHeight = 18px                                                     │
 * │  padding    = 8px                                                      │
 * │  scrollbar  = 14px (custom drawn)                                      │
 * │                                                                         │
 * │  widgetWidth  = maxChars × charWidth + padding×2 + (vScroll ? 14 : 0)  │
 * │  widgetHeight = numLines × lineHeight + padding×2 + (hScroll ? 14 : 0) │
 * │                 + statusBarHeight(18)                                   │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class TextAreaWidget extends DeviceView
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var CHAR_WIDTH:Float = 8.0;
    private static inline var LINE_HEIGHT:Float = 18.0;
    private static inline var PADDING:Float = 8.0;
    private static inline var SCROLLBAR_SIZE:Float = 14.0;
    private static inline var STATUS_HEIGHT:Float = 18.0;
    private static inline var MIN_CHARS:Int = 5;
    private static inline var MAX_CHARS:Int = 200;
    private static inline var MIN_LINES:Int = 1;
    private static inline var MAX_LINES:Int = 100;

    /** Number of lines to scroll per mouse wheel tick. */
    private static inline var WHEEL_SCROLL_LINES:Int = 3;

    // Scrollbar colors
    private static inline var SCROLL_BG_COLOR:Int = 0x1a1a24;
    private static inline var SCROLL_TRACK_COLOR:Int = 0x2a2a3a;
    private static inline var SCROLL_THUMB_COLOR:Int = 0x4a4a6a;
    private static inline var SCROLL_THUMB_HOVER:Int = 0x6a6a8a;
    private static inline var SCROLL_THUMB_DRAG:Int = 0x00AAFF;
    private static inline var SCROLL_BORDER_COLOR:Int = 0x333355;

    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _textField:TextField;
    private var _statusBar:TextField;
    private var _headerLabel:TextField;

    // Custom scrollbars
    private var _vScrollBar:Sprite;
    private var _vScrollTrack:Sprite;
    private var _vScrollThumb:Sprite;
    private var _hScrollBar:Sprite;
    private var _hScrollTrack:Sprite;
    private var _hScrollThumb:Sprite;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _textAreaAtom:TextAreaAtom;
    private var _isEditing:Bool = false;
    private var _lastText:String = "";
    private var _suppressUpdate:Bool = false;

    // Scrollbar drag state
    private var _isDraggingV:Bool = false;
    private var _isDraggingH:Bool = false;
    private var _dragStartY:Float = 0;
    private var _dragStartX:Float = 0;
    private var _dragStartScrollV:Int = 0;
    private var _dragStartScrollH:Int = 0;
    private var _vThumbHover:Bool = false;
    private var _hThumbHover:Bool = false;

    // =========================================================================
    // CONFIGURATION (cached from atom)
    // =========================================================================
    private var _maxChars:Int = 40;
    private var _numLines:Int = 8;
    private var _editable:Bool = true;
    private var _wordWrap:Bool = true;
    private var _autoScroll:Bool = true;
    private var _hScroll:Bool = false;
    private var _vScroll:Bool = true;

    // =========================================================================
    // DYNAMIC SIZE
    // =========================================================================
    public var widgetWidth(default, null):Float = 350;
    public var widgetHeight(default, null):Float = 190;

    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom)
    {
        super(atom);

        // Resolve TextAreaAtom reference
        if (Std.isOfType(atom, TextAreaAtom))
        {
            _textAreaAtom = cast(atom, TextAreaAtom);
        }

        syncConfigFromAtom();
        recalcSize();
        buildUI();
        syncFromAtom();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    override private function onActivate():Void
    {
        syncConfigFromAtom();
        recalcSize();
        rebuildUI();
        syncFromAtom();
    }

    /**
     * Read all configuration parameters from the atom's contacts.
     */
    private function syncConfigFromAtom():Void
    {
        if (_textAreaAtom != null)
        {
            _maxChars = _textAreaAtom.getMaxChars();
            _numLines = _textAreaAtom.getNumLines();
            _editable = _textAreaAtom.isEditable();
            _wordWrap = _textAreaAtom.isWordWrap();
            _autoScroll = _textAreaAtom.isAutoScroll();
            _hScroll = _textAreaAtom.isHScroll();
            _vScroll = _textAreaAtom.isVScroll();
        }
        else
        {
            // Fallback: read from contacts directly
            _maxChars = readIntInput("maxChars", 40);
            _numLines = readIntInput("numLines", 8);
            _editable = readBoolInput("editable", true);
            _wordWrap = readBoolInput("wordWrap", true);
            _autoScroll = readBoolInput("autoScroll", true);
            _hScroll = readBoolInput("hScroll", false);
            _vScroll = readBoolInput("vScroll", true);
        }
    }

    private function readIntInput(name:String, def:Int):Int
    {
        if (atom == null) return def;
        var c = atom.getInput(name);
        if (c != null && c.value != null)
        {
            var v = Std.int(c.value);
            return v;
        }
        return def;
    }

    private function readBoolInput(name:String, def:Bool):Bool
    {
        if (atom == null) return def;
        var c = atom.getInput(name);
        if (c != null && c.value != null) return (c.value == true);
        return def;
    }

    /**
     * Recalculate widget dimensions based on current configuration.
     */
    private function recalcSize():Void
    {
        var scrollW = _vScroll ? SCROLLBAR_SIZE : 0;
        var scrollH = _hScroll ? SCROLLBAR_SIZE : 0;

        widgetWidth = _maxChars * CHAR_WIDTH + PADDING * 2 + scrollW + 4;
        widgetHeight = _numLines * LINE_HEIGHT + PADDING * 2 + scrollH + STATUS_HEIGHT + 4;

        // Clamp to reasonable bounds
        if (widgetWidth < 100) widgetWidth = 100;
        if (widgetWidth > 800) widgetWidth = 800;
        if (widgetHeight < 60) widgetHeight = 60;
        if (widgetHeight > 600) widgetHeight = 600;
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        // === BACKGROUND ===
        _bg = new Sprite();
        addChild(_bg);
        drawBackground();

        // === HEADER LABEL ===
        _headerLabel = new TextField();
        _headerLabel.defaultTextFormat = new TextFormat("_typewriter", 9, 0x666688);
        _headerLabel.text = "TEXT AREA";
        _headerLabel.width = widgetWidth;
        _headerLabel.height = 14;
        _headerLabel.x = PADDING;
        _headerLabel.y = 2;
        _headerLabel.selectable = false;
        _headerLabel.mouseEnabled = false;
        addChild(_headerLabel);

        // === TEXT FIELD ===
        _textField = new TextField();
        _textField.x = PADDING;
        _textField.y = 16;
        _textField.width = widgetWidth - PADDING * 2 - (_vScroll ? SCROLLBAR_SIZE : 0) - 4;
        _textField.height = widgetHeight - 16 - PADDING * 2 - STATUS_HEIGHT - (_hScroll ? SCROLLBAR_SIZE : 0);
        _textField.multiline = true;
        _textField.wordWrap = _wordWrap;
        _textField.selectable = true;
        _textField.mouseEnabled = true;
        _textField.border = true;
        _textField.borderColor = 0x333355;
        _textField.background = true;
        _textField.backgroundColor = 0x0d0d18;
        _textField.textColor = 0x00FF88;

        var fmt = new TextFormat("_typewriter", 12, 0x00FF88);
        _textField.defaultTextFormat = fmt;

        applyEditableState();

        _textField.addEventListener(Event.CHANGE, onTextChange);
        _textField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
        _textField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
        _textField.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        _textField.addEventListener(Event.SCROLL, onScroll);
        addChild(_textField);

        // === CUSTOM SCROLLBARS ===
        buildScrollbars();

        // === STATUS BAR ===
        _statusBar = new TextField();
        _statusBar.defaultTextFormat = new TextFormat("_typewriter", 9, 0x555577);
        _statusBar.text = "Lines: 1 | Ln 1, Col 1";
        _statusBar.width = widgetWidth - PADDING * 2;
        _statusBar.height = STATUS_HEIGHT;
        _statusBar.x = PADDING;
        _statusBar.y = widgetHeight - STATUS_HEIGHT - 2;
        _statusBar.selectable = false;
        _statusBar.mouseEnabled = false;
        addChild(_statusBar);

        // === v1.2: MOUSE WHEEL HANDLER ===
        // Intercept mouse wheel to:
        //   1. Prevent event from reaching parent NodeEditor (zoom canvas)
        //   2. Manually scroll text (OpenFL INPUT TextField doesn't always
        //      auto-scroll on wheel)
        //   3. Synchronously update custom scrollbar thumb position
        addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
    }

    /**
     * Build custom scrollbars (vertical and horizontal).
     * OpenFL TextField does not draw scrollbars automatically,
     * so we create custom sprites for visual feedback and interaction.
     */
    private function buildScrollbars():Void
    {
        // === VERTICAL SCROLLBAR ===
        if (_vScroll)
        {
            _vScrollBar = new Sprite();
            _vScrollBar.x = widgetWidth - SCROLLBAR_SIZE - 2;
            _vScrollBar.y = 16;

            // Track (background)
            _vScrollTrack = new Sprite();
            _vScrollTrack.graphics.beginFill(SCROLL_TRACK_COLOR);
            _vScrollTrack.graphics.drawRect(0, 0, SCROLLBAR_SIZE - 2, _textField.height);
            _vScrollTrack.graphics.endFill();
            _vScrollTrack.graphics.lineStyle(1, SCROLL_BORDER_COLOR);
            _vScrollTrack.graphics.drawRect(0, 0, SCROLLBAR_SIZE - 2, _textField.height);
            _vScrollBar.addChild(_vScrollTrack);

            // Thumb (draggable)
            _vScrollThumb = new Sprite();
            _vScrollThumb.graphics.beginFill(SCROLL_THUMB_COLOR);
            _vScrollThumb.graphics.drawRoundRect(1, 0, SCROLLBAR_SIZE - 4, 40, 3, 3);
            _vScrollThumb.graphics.endFill();
            _vScrollThumb.buttonMode = true;
            _vScrollThumb.addEventListener(MouseEvent.MOUSE_DOWN, onVThumbMouseDown);
            _vScrollThumb.addEventListener(MouseEvent.MOUSE_OVER, onVThumbOver);
            _vScrollThumb.addEventListener(MouseEvent.MOUSE_OUT, onVThumbOut);
            _vScrollBar.addChild(_vScrollThumb);

            // Track click for jump-to-position
            _vScrollTrack.buttonMode = true;
            _vScrollTrack.addEventListener(MouseEvent.MOUSE_DOWN, onVTrackClick);

            addChild(_vScrollBar);
        }

        // === HORIZONTAL SCROLLBAR ===
        if (_hScroll)
        {
            _hScrollBar = new Sprite();
            _hScrollBar.x = PADDING;
            _hScrollBar.y = widgetHeight - STATUS_HEIGHT - SCROLLBAR_SIZE - 2;

            // Track (background)
            _hScrollTrack = new Sprite();
            _hScrollTrack.graphics.beginFill(SCROLL_TRACK_COLOR);
            _hScrollTrack.graphics.drawRect(0, 0, _textField.width, SCROLLBAR_SIZE - 2);
            _hScrollTrack.graphics.endFill();
            _hScrollTrack.graphics.lineStyle(1, SCROLL_BORDER_COLOR);
            _hScrollTrack.graphics.drawRect(0, 0, _textField.width, SCROLLBAR_SIZE - 2);
            _hScrollBar.addChild(_hScrollTrack);

            // Thumb (draggable)
            _hScrollThumb = new Sprite();
            _hScrollThumb.graphics.beginFill(SCROLL_THUMB_COLOR);
            _hScrollThumb.graphics.drawRoundRect(0, 1, 60, SCROLLBAR_SIZE - 4, 3, 3);
            _hScrollThumb.graphics.endFill();
            _hScrollThumb.buttonMode = true;
            _hScrollThumb.addEventListener(MouseEvent.MOUSE_DOWN, onHThumbMouseDown);
            _hScrollThumb.addEventListener(MouseEvent.MOUSE_OVER, onHThumbOver);
            _hScrollThumb.addEventListener(MouseEvent.MOUSE_OUT, onHThumbOut);
            _hScrollBar.addChild(_hScrollThumb);

            // Track click for jump-to-position
            _hScrollTrack.buttonMode = true;
            _hScrollTrack.addEventListener(MouseEvent.MOUSE_DOWN, onHTrackClick);

            addChild(_hScrollBar);
        }
    }

    /**
     * Full UI rebuild (called when configuration changes).
     */
    private function rebuildUI():Void
    {
        // Remove old children
        while (numChildren > 0) removeChildAt(0);

        // Remove old listeners
        if (_textField != null)
        {
            _textField.removeEventListener(Event.CHANGE, onTextChange);
            _textField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            _textField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _textField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            _textField.removeEventListener(Event.SCROLL, onScroll);
        }

        // Remove scrollbar listeners
        if (_vScrollThumb != null)
        {
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_DOWN, onVThumbMouseDown);
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_OVER, onVThumbOver);
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_OUT, onVThumbOut);
        }
        if (_hScrollThumb != null)
        {
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_DOWN, onHThumbMouseDown);
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_OVER, onHThumbOver);
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_OUT, onHThumbOut);
        }

        // v1.2: Remove wheel listener before rebuild
        removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

        buildUI();
    }

    private function drawBackground():Void
    {
        _bg.graphics.clear();
        _bg.graphics.beginFill(0x1a1a24, 0.95);
        _bg.graphics.lineStyle(1, _editable ? 0x00AAFF : 0x444455);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _bg.graphics.endFill();
    }

    /**
     * Apply editable/readonly state to the TextField.
     */
    private function applyEditableState():Void
    {
        if (_textField == null) return;
        if (_editable)
        {
            _textField.type = TextFieldType.INPUT;
            _textField.textColor = 0x00FF88;
            _textField.borderColor = 0x333355;
            _textField.backgroundColor = 0x0d0d18;
        }
        else
        {
            _textField.type = TextFieldType.DYNAMIC;
            _textField.textColor = 0x668866;
            _textField.borderColor = 0x2a2a3a;
            _textField.backgroundColor = 0x111118;
        }
    }

    // =========================================================================
    // v1.2: MOUSE WHEEL SCROLL HANDLER
    // =========================================================================
    /**
     * Handle mouse wheel for synchronous text scrolling.
     *
     * This handler solves TWO problems:
     *
     * 1. EVENT ISOLATION: stopPropagation() prevents the wheel event from
     *    reaching the parent NodeEditor/ViewportManager, which would
     *    otherwise interpret it as a canvas zoom command.
     *
     * 2. SYNCHRONOUS SCROLL: OpenFL TextField with type=INPUT does not
     *    always auto-scroll on mouse wheel (platform-dependent). We
     *    manually adjust scrollV/scrollH and immediately update the
     *    custom scrollbar thumb position in the same frame.
     *
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  Mouse Wheel Event Flow (v1.2):                                 │
     * │                                                                 │
     * │  User scrolls wheel over TextAreaWidget                         │
     * │       │                                                         │
     * │       ▼                                                         │
     * │  onMouseWheel(e)                                                │
     * │       │                                                         │
     * │       ├── e.stopPropagation()  ← Block parent (no zoom!)        │
     * │       │                                                         │
     * │       ├── Shift held?                                           │
     * │       │    ├── YES → scrollH += delta × WHEEL_SCROLL_LINES      │
     * │       │    └── NO  → scrollV -= delta × WHEEL_SCROLL_LINES      │
     * │       │              (delta > 0 = scroll up, < 0 = scroll down) │
     * │       │                                                         │
     * │       └── updateScrollbarThumbs()  ← Sync thumb position NOW    │
     * │                                                                 │
     * └─────────────────────────────────────────────────────────────────┘
     *
     * @param e Mouse wheel event (e.delta > 0 = scroll up, < 0 = scroll down)
     */
    private function onMouseWheel(e:MouseEvent):Void
    {
        if (_textField == null || isDisposed) return;

        // CRITICAL: Stop event from reaching parent NodeEditor (zoom canvas)
        e.stopPropagation();

        if (e.shiftKey && _hScroll && !_wordWrap)
        {
            // Horizontal scroll with Shift+Wheel
            var maxH = _textField.maxScrollH;
            if (maxH > 0)
            {
                var deltaH = -e.delta * WHEEL_SCROLL_LINES * 4; // pixels
                var newH = _textField.scrollH + Std.int(deltaH);
                if (newH < 0) newH = 0;
                if (newH > maxH) newH = maxH;
                _textField.scrollH = newH;
            }
        }
        else
        {
            // Vertical scroll (default)
            var maxV = _textField.maxScrollV;
            if (maxV > 1)
            {
                // e.delta > 0 means scroll UP (content moves down)
                // e.delta < 0 means scroll DOWN (content moves up)
                var deltaV = -e.delta * WHEEL_SCROLL_LINES;
                var newV = _textField.scrollV + Std.int(deltaV);
                if (newV < 1) newV = 1;
                if (newV > maxV) newV = maxV;
                _textField.scrollV = newV;
            }
        }

        // Synchronously update custom scrollbar thumb position
        updateScrollbarThumbs();
        updateStatusBar();
    }

    // =========================================================================
    // SCROLLBAR INTERACTION
    // =========================================================================

    /**
     * Update scrollbar thumb positions based on current scroll state.
     * Called on every scroll event, text change, and mouse wheel.
     */
    private function updateScrollbarThumbs():Void
    {
        if (_textField == null) return;

        // === VERTICAL SCROLLBAR ===
        if (_vScroll && _vScrollThumb != null && _vScrollTrack != null)
        {
            var maxScroll = _textField.maxScrollV;
            var currentScroll = _textField.scrollV;
            var trackHeight = _textField.height;

            if (maxScroll > 1)
            {
                // Calculate thumb height (proportional to visible/total lines)
                var visibleLines = _textField.bottomScrollV - _textField.scrollV + 1;
                var totalLines = _textField.numLines;
                var thumbHeight = Math.max(20, (visibleLines / totalLines) * trackHeight);

                // Calculate thumb position
                var scrollRatio = (currentScroll - 1) / (maxScroll - 1);
                var thumbY = scrollRatio * (trackHeight - thumbHeight);

                // Redraw thumb
                _vScrollThumb.graphics.clear();
                var thumbColor = _isDraggingV ? SCROLL_THUMB_DRAG : (_vThumbHover ? SCROLL_THUMB_HOVER : SCROLL_THUMB_COLOR);
                _vScrollThumb.graphics.beginFill(thumbColor);
                _vScrollThumb.graphics.drawRoundRect(1, thumbY, SCROLLBAR_SIZE - 4, thumbHeight, 3, 3);
                _vScrollThumb.graphics.endFill();
                _vScrollThumb.visible = true;
            }
            else
            {
                // No scroll needed - hide thumb
                _vScrollThumb.visible = false;
            }
        }

        // === HORIZONTAL SCROLLBAR ===
        if (_hScroll && _hScrollThumb != null && _hScrollTrack != null && !_wordWrap)
        {
            var maxScrollH = _textField.maxScrollH;
            var currentScrollH = _textField.scrollH;
            var trackWidth = _textField.width;

            if (maxScrollH > 0)
            {
                // Calculate thumb width (proportional to visible/total width)
                var visibleWidth = _textField.width;
                var totalWidth = _textField.textWidth + 20; // Approximate total width
                var thumbWidth = Math.max(30, (visibleWidth / totalWidth) * trackWidth);

                // Calculate thumb position
                var scrollRatio = currentScrollH / maxScrollH;
                var thumbX = scrollRatio * (trackWidth - thumbWidth);

                // Redraw thumb
                _hScrollThumb.graphics.clear();
                var thumbColor = _isDraggingH ? SCROLL_THUMB_DRAG : (_hThumbHover ? SCROLL_THUMB_HOVER : SCROLL_THUMB_COLOR);
                _hScrollThumb.graphics.beginFill(thumbColor);
                _hScrollThumb.graphics.drawRoundRect(thumbX, 1, thumbWidth, SCROLLBAR_SIZE - 4, 3, 3);
                _hScrollThumb.graphics.endFill();
                _hScrollThumb.visible = true;
            }
            else
            {
                // No scroll needed - hide thumb
                _hScrollThumb.visible = false;
            }
        }
    }

    // === VERTICAL SCROLLBAR HANDLERS ===

    private function onVThumbMouseDown(e:MouseEvent):Void
    {
        _isDraggingV = true;
        _dragStartY = e.stageY;
        _dragStartScrollV = _textField.scrollV;

        stage.addEventListener(MouseEvent.MOUSE_MOVE, onVThumbDrag);
        stage.addEventListener(MouseEvent.MOUSE_UP, onVThumbMouseUp);
        e.stopPropagation();
    }

    private function onVThumbDrag(e:MouseEvent):Void
    {
        if (!_isDraggingV || _textField == null) return;

        var deltaY = e.stageY - _dragStartY;
        var trackHeight = _textField.height;
        var maxScroll = _textField.maxScrollV;

        if (maxScroll > 1)
        {
            var scrollDelta = Std.int((deltaY / trackHeight) * maxScroll);
            var newScroll = Math.max(1, Math.min(maxScroll, _dragStartScrollV + scrollDelta));
            _textField.scrollV = Std.int(newScroll);
            updateScrollbarThumbs();
        }
    }

    private function onVThumbMouseUp(e:MouseEvent):Void
    {
        _isDraggingV = false;
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onVThumbDrag);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onVThumbMouseUp);
        updateScrollbarThumbs();
    }

    private function onVTrackClick(e:MouseEvent):Void
    {
        if (_textField == null || _vScrollTrack == null) return;

        // Jump to clicked position
        var localY = _vScrollTrack.mouseY;
        var trackHeight = _textField.height;
        var maxScroll = _textField.maxScrollV;

        if (maxScroll > 1)
        {
            var scrollRatio = localY / trackHeight;
            var newScroll = Math.max(1, Math.min(maxScroll, Std.int(scrollRatio * maxScroll)));
            _textField.scrollV = Std.int(newScroll);
            updateScrollbarThumbs();
        }
    }

    private function onVThumbOver(e:MouseEvent):Void
    {
        _vThumbHover = true;
        updateScrollbarThumbs();
    }

    private function onVThumbOut(e:MouseEvent):Void
    {
        _vThumbHover = false;
        updateScrollbarThumbs();
    }

    // === HORIZONTAL SCROLLBAR HANDLERS ===

    private function onHThumbMouseDown(e:MouseEvent):Void
    {
        _isDraggingH = true;
        _dragStartX = e.stageX;
        _dragStartScrollH = _textField.scrollH;

        stage.addEventListener(MouseEvent.MOUSE_MOVE, onHThumbDrag);
        stage.addEventListener(MouseEvent.MOUSE_UP, onHThumbMouseUp);
        e.stopPropagation();
    }

    private function onHThumbDrag(e:MouseEvent):Void
    {
        if (!_isDraggingH || _textField == null) return;

        var deltaX = e.stageX - _dragStartX;
        var trackWidth = _textField.width;
        var maxScrollH = _textField.maxScrollH;

        if (maxScrollH > 0)
        {
            var scrollDelta = Std.int((deltaX / trackWidth) * maxScrollH);
            var newScroll = Math.max(0, Math.min(maxScrollH, _dragStartScrollH + scrollDelta));
            _textField.scrollH = Std.int(newScroll);
            updateScrollbarThumbs();
        }
    }

    private function onHThumbMouseUp(e:MouseEvent):Void
    {
        _isDraggingH = false;
        stage.removeEventListener(MouseEvent.MOUSE_MOVE, onHThumbDrag);
        stage.removeEventListener(MouseEvent.MOUSE_UP, onHThumbMouseUp);
        updateScrollbarThumbs();
    }

    private function onHTrackClick(e:MouseEvent):Void
    {
        if (_textField == null || _hScrollTrack == null) return;

        // Jump to clicked position
        var localX = _hScrollTrack.mouseX;
        var trackWidth = _textField.width;
        var maxScrollH = _textField.maxScrollH;

        if (maxScrollH > 0)
        {
            var scrollRatio = localX / trackWidth;
            var newScroll = Math.max(0, Math.min(maxScrollH, Std.int(scrollRatio * maxScrollH)));
            _textField.scrollH = Std.int(newScroll);
            updateScrollbarThumbs();
        }
    }

    private function onHThumbOver(e:MouseEvent):Void
    {
        _hThumbHover = true;
        updateScrollbarThumbs();
    }

    private function onHThumbOut(e:MouseEvent):Void
    {
        _hThumbHover = false;
        updateScrollbarThumbs();
    }

    // =========================================================================
    // DATA SYNCHRONIZATION
    // =========================================================================
    /**
     * v1.2 FIX: Reads from getOutput("textOut") — the ACTUAL output contact name.
     *
     * Previous code used getOutput("text") which returned null because
     * the atom's output contact is named "textOut", not "text".
     * This caused initial text synchronization to silently fail.
     */
    override private function syncFromAtom():Void
    {
        if (atom == null || _textField == null) return;

        // v1.2 FIX: Use "textOut" — the actual output contact name
        var textOut = atom.getOutput("textOut");
        if (textOut != null && textOut.value != null)
        {
            var newText = Std.string(textOut.value);
            if (newText != _textField.text)
            {
                _suppressUpdate = true;
                _textField.text = newText;
                _lastText = newText;
                _suppressUpdate = false;

                if (_autoScroll)
                {
                    _textField.scrollV = _textField.maxScrollV;
                }

                updateScrollbarThumbs();
            }
        }
        else if (_textAreaAtom != null)
        {
            // Fallback: read directly from Databank if contact not yet available
            var databankText = _textAreaAtom.getText();
            if (databankText != _textField.text)
            {
                _suppressUpdate = true;
                _textField.text = databankText;
                _lastText = databankText;
                _suppressUpdate = false;

                if (_autoScroll)
                {
                    _textField.scrollV = _textField.maxScrollV;
                }

                updateScrollbarThumbs();
            }
        }

        updateStatusBar();
    }

    /**
     * v1.2 FIX: Handles "textOut" (not "text") for text updates from atom.
     *
     * DeviceView.subscribeToContacts() subscribes to ALL atom outputs.
     * When atom's "textOut" contact changes, this handler is called with
     * contact.name == "textOut". Previous code had case "text" which
     * NEVER matched, so external text updates were silently ignored.
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;

        switch (contact.name)
        {
            // v1.2 FIX: "textOut" — matches atom's actual output contact name
            case "textOut":
                if (!_isEditing)
                {
                    var newText = (newValue != null) ? Std.string(newValue) : "";
                    if (newText != _textField.text)
                    {
                        _suppressUpdate = true;
                        _textField.text = newText;
                        _lastText = newText;
                        _suppressUpdate = false;

                        if (_autoScroll)
                        {
                            _textField.scrollV = _textField.maxScrollV;
                        }

                        updateScrollbarThumbs();
                    }
                }

            case "editable":
                _editable = (newValue == true);
                applyEditableState();
                drawBackground();

            case "wordWrap":
                _wordWrap = (newValue == true);
                _textField.wordWrap = _wordWrap;
                updateScrollbarThumbs();

            case "autoScroll":
                _autoScroll = (newValue == true);
                if (_autoScroll)
                {
                    _textField.scrollV = _textField.maxScrollV;
                    updateScrollbarThumbs();
                }

            case "hScroll":
                _hScroll = (newValue == true);
                syncConfigFromAtom();
                recalcSize();
                rebuildUI();
                syncFromAtom();

            case "vScroll":
                _vScroll = (newValue == true);
                syncConfigFromAtom();
                recalcSize();
                rebuildUI();
                syncFromAtom();

            case "maxChars":
                var v = Std.int(newValue);
                if (v >= MIN_CHARS && v <= MAX_CHARS && v != _maxChars)
                {
                    _maxChars = v;
                    recalcSize();
                    rebuildUI();
                    syncFromAtom();
                }

            case "numLines":
                var v = Std.int(newValue);
                if (v >= MIN_LINES && v <= MAX_LINES && v != _numLines)
                {
                    _numLines = v;
                    recalcSize();
                    rebuildUI();
                    syncFromAtom();
                }

            case "changed":
                // Pulse received — sync text from Databank
                syncFromAtom();

            case "lineCount":
                updateStatusBar();
                updateScrollbarThumbs();
        }
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    /**
     * v1.2 FIX: Fallback path writes to getInput("textIn") — the actual
     * input contact name. Previous code used getOutput("text") which
     * returned null (wrong name AND wrong direction — output vs input).
     */
    private function onTextChange(e:Event):Void
    {
        if (_suppressUpdate || isDisposed) return;

        var currentText = _textField.text;
        if (currentText != _lastText)
        {
            _lastText = currentText;

            // Push to atom's databank
            if (_textAreaAtom != null)
            {
                _textAreaAtom.setTextFromWidget(currentText);
            }
            else
            {
                // v1.2 FIX: Write to INPUT "textIn" (not OUTPUT "text")
                // When atom is wrapped in Assembly, we don't have direct
                // _textAreaAtom reference, so we write through the contact.
                var textIn = atom.getInput("textIn");
                if (textIn != null) textIn.value = currentText;
            }

            updateStatusBar();
            updateScrollbarThumbs();
        }
    }

    private function onFocusIn(e:FocusEvent):Void
    {
        _isEditing = true;
        if (_textField != null)
        {
            _textField.borderColor = 0x00AAFF;
        }
    }

    private function onFocusOut(e:FocusEvent):Void
    {
        _isEditing = false;
        if (_textField != null)
        {
            _textField.borderColor = _editable ? 0x333355 : 0x2a2a3a;
        }

        // Final push to atom
        if (_textField != null && _textField.text != _lastText)
        {
            _lastText = _textField.text;
            if (_textAreaAtom != null)
            {
                _textAreaAtom.setTextFromWidget(_lastText);
            }
        }

        // Signal save
        Impulsys.quickEmit(EventType.VALUE_COMMITTED);
    }

    private function onKeyDown(e:KeyboardEvent):Void
    {
        // Stop global shortcuts while typing
        e.stopImmediatePropagation();

        // Update cursor position in status bar
        haxe.Timer.delay(updateStatusBar, 10);
    }

    private function onScroll(e:Event):Void
    {
        updateStatusBar();
        updateScrollbarThumbs();
    }

    // =========================================================================
    // STATUS BAR
    // =========================================================================
    private function updateStatusBar():Void
    {
        if (_statusBar == null || _textField == null) return;

        var lineCount = _textField.numLines;
        var scrollLine = _textField.scrollV;
        var maxScroll = _textField.maxScrollV;

        // Calculate cursor line and column
        var caretIndex = _textField.caretIndex;
        var cursorLine = 1;
        var cursorCol = 1;

        try
        {
            cursorLine = _textField.getLineIndexOfChar(caretIndex) + 1;
            var lineOffset = _textField.getLineOffset(cursorLine - 1);
            cursorCol = caretIndex - lineOffset + 1;
        }
        catch (e:Dynamic)
        {
            // Fallback if caretIndex is out of bounds
        }

        var editState = _editable ? "EDIT" : "READ";
        var wrapState = _wordWrap ? "WRAP" : "NOWRAP";

        _statusBar.text = '${editState} | Ln ${cursorLine}/${lineCount}, Col ${cursorCol} | ${wrapState}';

        // Report cursor line to atom
        if (_textAreaAtom != null)
        {
            _textAreaAtom.setCursorLine(cursorLine);
        }
    }

    // =========================================================================
    // FLUSH TRANSIENT STATE
    // =========================================================================
    override private function flushTransientState():Void
    {
        if (_textField != null && _textField.text != _lastText)
        {
            _lastText = _textField.text;
            if (_textAreaAtom != null)
            {
                _textAreaAtom.setTextFromWidget(_lastText);
            }
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_textField != null)
        {
            _textField.removeEventListener(Event.CHANGE, onTextChange);
            _textField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            _textField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            _textField.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            _textField.removeEventListener(Event.SCROLL, onScroll);
        }

        // Remove scrollbar listeners
        if (_vScrollThumb != null)
        {
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_DOWN, onVThumbMouseDown);
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_OVER, onVThumbOver);
            _vScrollThumb.removeEventListener(MouseEvent.MOUSE_OUT, onVThumbOut);
        }
        if (_hScrollThumb != null)
        {
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_DOWN, onHThumbMouseDown);
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_OVER, onHThumbOver);
            _hScrollThumb.removeEventListener(MouseEvent.MOUSE_OUT, onHThumbOut);
        }

        // v1.2: Remove wheel listener
        removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

        // Clean up stage listeners
        if (stage != null)
        {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onVThumbDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onVThumbMouseUp);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onHThumbDrag);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onHThumbMouseUp);
        }

        _bg = null;
        _textField = null;
        _statusBar = null;
        _headerLabel = null;
        _textAreaAtom = null;
        _vScrollBar = null;
        _vScrollTrack = null;
        _vScrollThumb = null;
        _hScrollBar = null;
        _hScrollTrack = null;
        _hScrollThumb = null;

        super.dispose();
    }
}