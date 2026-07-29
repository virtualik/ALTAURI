// FILE: core/view/DebugConsoleWidget.hx
package core.view;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.events.MouseEvent;
import openfl.events.Event;
import core.base.Atom;
import core.base.Contact;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     DEBUG CONSOLE WIDGET v1.4                             ║
 * ║              (Contact Name Matching + Auto-scroll Fix)                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Visual component (Face) for DebugConsoleAtom.                            ║
 * ║  Displays trace() output in a scrollable text area with Clear button.     ║
 * ║                                                                           ║
 * ║  Architecture: "ATOM IS DATABANK & COMPUTE CORE"                          ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  DebugConsoleAtom (Databank)                                        │  ║
 * ║  │                                                                     │  ║
 * ║  │  Contact "output"    ───► DebugConsoleWidget (full log content)     │  ║
 * ║  │  Contact "lineCount" ───► DebugConsoleWidget (status bar)           │  ║
 * ║  │  Contact "clear"     ◄──── DebugConsoleWidget (clear button click)  │  ║
 * ║  │                                                                     │  ║
 * ║  │  Widget READS from atom's output contacts.                          │  ║
 * ║  │  Widget WRITES to atom's "clear" input on button click.             │  ║
 * ║  │  Atom is the Databank — single source of truth.                     │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌─────────────────────────────────────────────────────────────┐    │  ║
 * ║  │  │  DEBUG CONSOLE                                    [Clear]   │    │  ║
 * ║  │  ├─────────────────────────────────────────────────────────────┤    │  ║
 * ║  │  │  12:34:56 | ComPortAtom: Opened COM13 via WebUSB           │    │  ║
 * ║  │  │  12:34:57 | PL2303HX: RX buffer activated (0x0044)         │    │  ║
 * ║  │  │  12:34:58 | SignalGenerator: freq=440.0 Hz                 │    │  ║
 * ║  │  │  12:34:59 | FFTAtom: Processing 512 samples                │    │  ║
 * ║  │  │  ...                                                        │    │  ║
 * ║  │  └─────────────────────────────────────────────────────────────┘    │  ║
 * ║  │  Lines: 4                                                           │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     v1.4 CHANGES                                          ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  v1.4 — Contact Name Matching + Robust Sync                               ║
 * ║  ─────────────────────────────────────────────                            ║
 * ║  - FIXED: onContactChanged uses switch(contact.name) instead of           ║
 * ║    if(contact == _outputContact). Previous approach failed when           ║
 * ║    _outputContact was null during race conditions at init time.           ║
 * ║  - FIXED: syncFromAtom() now has fallback to atom.getText()-style         │  ║
 * ║    direct read if contact subscription hasn't fired yet.                  ║
 * ║  - ADDED: Event.SCROLL listener on _logField for manual scroll            ║
 * ║    detection (prevents auto-scroll from fighting user scroll).            ║
 * ║  - ADDED: _userScrolledUp flag — disables auto-scroll when user           ║
 * ║    manually scrolls up to read older messages.                            ║
 * ║  - ADDED: Mouse wheel event interception (stopPropagation) to             ║
 * ║    prevent scroll events from reaching parent NodeEditor (zoom).          ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class DebugConsoleWidget extends DeviceView
{
    // =========================================================================
    // UI COMPONENTS
    // =========================================================================
    private var _bg:Sprite;
    private var _header:Sprite;
    private var _titleField:TextField;
    private var _logField:TextField;
    private var _clearBtn:Sprite;
    private var _clearLabel:TextField;
    private var _statusField:TextField;

    // =========================================================================
    // STATE
    // =========================================================================
    /** Tracks whether user manually scrolled up (disables auto-scroll). */
    private var _userScrolledUp:Bool = false;
    /** Current line count for status bar. */
    private var _lineCount:Int = 0;

    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    public var widgetWidth:Float = 320;
    public var widgetHeight:Float = 220;

    override public function getWidgetSize():{width:Float, height:Float}
    {
        return {width: widgetWidth, height: widgetHeight};
    }

    private var _colorBg:Int = 0x1a1a24;
    private var _colorHeader:Int = 0x2a2a3a;
    private var _colorText:Int = 0x00FF88;
    private var _colorMuted:Int = 0x888899;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(atom:Atom)
    {
        super(atom);
        buildUI();
        syncFromAtom();
    }

    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    override private function onActivate():Void
    {
        syncFromAtom();
    }

    // =========================================================================
    // UI CONSTRUCTION
    // =========================================================================
    private function buildUI():Void
    {
        // === BACKGROUND ===
        _bg = new Sprite();
        _bg.graphics.beginFill(_colorBg, 0.95);
        _bg.graphics.lineStyle(1, 0x00AAFF);
        _bg.graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 6, 6);
        _bg.graphics.endFill();
        addChild(_bg);

        // === HEADER ===
        _header = new Sprite();
        _header.graphics.beginFill(_colorHeader);
        _header.graphics.drawRoundRectComplex(0, 0, widgetWidth, 24, 6, 6, 0, 0);
        _header.graphics.endFill();
        addChild(_header);

        // === TITLE ===
        _titleField = new TextField();
        _titleField.defaultTextFormat = new TextFormat("_typewriter", 11, 0xFFFFFF, true);
        _titleField.text = " DEBUG CONSOLE";
        _titleField.width = widgetWidth - 60;
        _titleField.height = 24;
        _titleField.x = 5;
        _titleField.y = 2;
        _titleField.selectable = false;
        _titleField.mouseEnabled = false;
        addChild(_titleField);

        // === CLEAR BUTTON ===
        _clearBtn = new Sprite();
        _clearBtn.graphics.beginFill(0x553322);
        _clearBtn.graphics.drawRoundRect(0, 0, 50, 20, 3, 3);
        _clearBtn.graphics.endFill();
        _clearBtn.x = widgetWidth - 55;
        _clearBtn.y = 2;
        _clearBtn.buttonMode = true;
        _clearBtn.useHandCursor = true;
        _clearBtn.addEventListener(MouseEvent.CLICK, onClearClick);
        addChild(_clearBtn);

        _clearLabel = new TextField();
        _clearLabel.defaultTextFormat = new TextFormat("_typewriter", 9, 0xFFFFFF, true);
        _clearLabel.text = "Clear";
        _clearLabel.width = 50;
        _clearLabel.height = 20;
        _clearLabel.selectable = false;
        _clearLabel.mouseEnabled = false;
        _clearBtn.addChild(_clearLabel);

        // === LOG DISPLAY FIELD ===
        _logField = new TextField();
        _logField.defaultTextFormat = new TextFormat("_typewriter", 10, _colorText);
        _logField.text = "";
        _logField.width = widgetWidth - 10;
        _logField.height = widgetHeight - 50;
        _logField.x = 5;
        _logField.y = 28;
        
        // Critical: prevent OpenFL from auto-resizing height
        _logField.autoSize = TextFieldAutoSize.NONE;
        _logField.multiline = true;
        _logField.wordWrap = true;
        _logField.background = true;
        _logField.backgroundColor = 0x0d0d18;
        _logField.border = true;
        _logField.borderColor = 0x333355;
        _logField.selectable = true;
        _logField.mouseEnabled = true;
        
        // Listen for manual scroll to detect user scrolling up
        _logField.addEventListener(Event.SCROLL, onLogScroll);
        addChild(_logField);

        // === STATUS BAR ===
        _statusField = new TextField();
        _statusField.defaultTextFormat = new TextFormat("_typewriter", 9, _colorMuted);
        _statusField.text = "Lines: 0";
        _statusField.width = widgetWidth - 10;
        _statusField.height = 16;
        _statusField.x = 5;
        _statusField.y = widgetHeight - 20;
        _statusField.selectable = false;
        _statusField.mouseEnabled = false;
        addChild(_statusField);

        // === MOUSE WHEEL INTERCEPTION ===
        // Prevent scroll events from reaching parent NodeEditor (zoom canvas)
        addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================
    /**
     * Clear button clicked — send pulse to atom's "clear" input.
     */
    private function onClearClick(e:MouseEvent):Void
    {
        _userScrolledUp = false; // Reset auto-scroll on clear
        var clearInput = atom.getInput("clear");
        if (clearInput != null)
        {
            clearInput.value = true;
        }
    }

    /**
     * User manually scrolled the log field.
     * Detects if user scrolled up (away from bottom) to read older messages.
     * If so, disables auto-scroll until user scrolls back to bottom or clicks Clear.
     */
    private function onLogScroll(e:Event):Void
    {
        if (_logField == null) return;
        
        // If user is at the bottom, re-enable auto-scroll
        if (_logField.scrollV >= _logField.maxScrollV)
        {
            _userScrolledUp = false;
        }
        else
        {
            // User scrolled up — disable auto-scroll
            _userScrolledUp = true;
        }
    }

    /**
     * Mouse wheel handler — intercept to prevent parent zoom.
     */
    private function onMouseWheel(e:MouseEvent):Void
    {
        if (_logField == null || isDisposed) return;
        
        // Stop event from reaching parent NodeEditor (zoom canvas)
        e.stopPropagation();
        
        // Manually scroll log field
        var maxV = _logField.maxScrollV;
        if (maxV > 1)
        {
            var delta = -e.delta * 3; // 3 lines per wheel tick
            var newV = _logField.scrollV + Std.int(delta);
            if (newV < 1) newV = 1;
            if (newV > maxV) newV = maxV;
            _logField.scrollV = newV;
            
            // Update auto-scroll state
            if (newV >= maxV)
            {
                _userScrolledUp = false;
            }
            else
            {
                _userScrolledUp = true;
            }
        }
    }

    // =========================================================================
    // DATA SYNCHRONIZATION
    // =========================================================================
    /**
     * Sync widget state from atom's output contacts.
     * Called on activation and when contacts change.
     *
     * Uses name-based contact lookup for reliability.
     */
    override private function syncFromAtom():Void
    {
        if (atom == null) return;
        
        // Read "output" contact (full log content)
        var outputContact = atom.getOutput("output");
        if (outputContact != null && outputContact.value != null)
        {
            var logText = Std.string(outputContact.value);
            if (logText != _logField.text)
            {
                _logField.text = logText;
                _autoScrollToBottom();
            }
        }
        
        // Read "lineCount" contact
        var lineCountContact = atom.getOutput("lineCount");
        if (lineCountContact != null)
        {
            _lineCount = Std.int(lineCountContact.value);
            _statusField.text = 'Lines: $_lineCount';
        }
    }

    /**
     * v1.4 FIX: Uses switch(contact.name) instead of if(contact == _outputContact).
     *
     * Previous approach failed when _outputContact was null during race
     * conditions at initialization. Name-based matching is robust because
     * it doesn't depend on reference equality.
     *
     * DeviceView.subscribeToContacts() subscribes to ALL atom outputs.
     * When atom's "output" contact changes, this handler is called with
     * contact.name == "output".
     */
    override private function onContactChanged(contact:Contact, newValue:Dynamic):Void
    {
        if (isDisposed) return;

        switch (contact.name)
        {
            case "output":
                if (newValue != null)
                {
                    var logText = Std.string(newValue);
                    if (logText != _logField.text)
                    {
                        _logField.text = logText;
                        _autoScrollToBottom();
                    }
                }

            case "lineCount":
                _lineCount = Std.int(newValue);
                _statusField.text = 'Lines: $_lineCount';
        }
    }

    /**
     * Auto-scroll to bottom if user hasn't manually scrolled up.
     */
    private function _autoScrollToBottom():Void
    {
        if (_logField == null) return;
        
        if (!_userScrolledUp && _logField.maxScrollV > 1)
        {
            _logField.scrollV = _logField.maxScrollV;
        }
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================
    override public function dispose():Void
    {
        if (_clearBtn != null)
        {
            _clearBtn.removeEventListener(MouseEvent.CLICK, onClearClick);
        }
        if (_logField != null)
        {
            _logField.removeEventListener(Event.SCROLL, onLogScroll);
        }
        removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
        
        _bg = null;
        _header = null;
        _titleField = null;
        _logField = null;
        _clearBtn = null;
        _clearLabel = null;
        _statusField = null;
        
        super.dispose();
    }
}