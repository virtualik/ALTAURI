// FILE: library\electro\TextAreaAtom.hx
package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
* TEXT AREA ATOM v1.0 (Configurable Multi-Line Text)
*
* Passive atom for multi-line text display and editing.
* Extends the concept of TextInputAtom with full textarea configuration.
*
* Architecture: "ATOM IS DATABANK & COMPUTE CORE"
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   TextAreaAtom (Databank)                                               │
* │                                                                         │
* │   ┌─────────────────────────────────────────────────────────────────┐   │
* │   │  CONFIGURATION INPUTS:                                          │   │
* │   │  - text       (String)  → Full text content                     │   │
* │   │  - append     (String)  → Append line to existing text          │   │
* │   │  - clear      (Bool)    → Clear all text on true                │   │
* │   │  - editable   (Bool)    → Enable/disable user editing           │   │
* │   │  - wordWrap   (Bool)    → Word wrap mode                        │   │
* │   │  - autoScroll (Bool)    → Auto-scroll to bottom on new text     │   │
* │   │  - hScroll    (Bool)    → Horizontal scrollbar visibility       │   │
* │   │  - vScroll    (Bool)    → Vertical scrollbar visibility         │   │
* │   │  - maxChars   (Int)     → Max characters per line (width)       │   │
* │   │  - numLines   (Int)     → Number of visible lines (height)      │   │
* │   │                                                                 │   │
* │   │  OUTPUTS:                                                       │   │
* │   │  - text       (String)  → Current text content                  │   │
* │   │  - changed    (Bool)    → Pulse on text change                  │   │
* │   │  - lineCount  (Int)     → Current number of lines               │   │
* │   │  - cursorLine (Int)     → Current cursor line number            │   │
* │   └─────────────────────────────────────────────────────────────────┘   │
* │                                                                         │
* │   Widget (TextAreaWidget) reads config from atom's contacts.            │
* │   Widget writes to "text" contact on user input.                        │
* │   Atom is the Databank — single source of truth.                        │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*
* Default Configuration:
* ┌──────────────────┬───────────────┐
* │ Parameter        │ Default       │
* ├──────────────────┼───────────────┤
* │ maxChars         │ 40            │
* │ numLines         │ 8             │
* │ editable         │ true          │
* │ wordWrap         │ true          │
* │ autoScroll       │ true          │
* │ hScroll          │ false         │
* │ vScroll          │ true          │
* └──────────────────┴───────────────┘
*/
class TextAreaAtom extends Atom
{
    // =========================================================================
    // DATABANK — Configuration State
    // =========================================================================
    private var _text:String = "";
    private var _editable:Bool = true;
    private var _wordWrap:Bool = true;
    private var _autoScroll:Bool = true;
    private var _hScroll:Bool = false;
    private var _vScroll:Bool = true;
    private var _maxChars:Int = 40;
    private var _numLines:Int = 8;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            // === INPUTS ===
            [
                new Contact("", INPUT, "text"),
                new Contact("", INPUT, "append"),
                new Contact(false, INPUT, "clear"),
                new Contact(true, INPUT, "editable"),
                new Contact(true, INPUT, "wordWrap"),
                new Contact(true, INPUT, "autoScroll"),
                new Contact(false, INPUT, "hScroll"),
                new Contact(true, INPUT, "vScroll"),
                new Contact(40, INPUT, "maxChars"),
                new Contact(8, INPUT, "numLines")
            ],
            // === OUTPUTS ===
            [
                new Contact("", OUTPUT, "text"),
                new Contact(false, OUTPUT, "changed"),
                new Contact(1, OUTPUT, "lineCount"),
                new Contact(1, OUTPUT, "cursorLine")
            ],
            null,   // No process function — passive atom
            id,
            "TextArea"
        );
    }

    // =========================================================================
    // COMPUTE MODULE
    // =========================================================================
    /**
    * Called when any contact value changes.
    * Routes configuration changes and text operations.
    */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isDisposed) return;

        switch (c.name)
        {
            case "text":
                var newText = Std.string(c.value);
                if (newText != _text)
                {
                    _text = newText;
                    pushTextToOutput();
                }

            case "append":
                var appendStr = Std.string(c.value);
                if (appendStr != "" && appendStr != "null")
                {
                    if (_text.length > 0)
                    {
                        _text += "\n" + appendStr;
                    }
                    else
                    {
                        _text = appendStr;
                    }
                    pushTextToOutput();
                    // Reset append input to prevent re-trigger
                    c.value = "";
                }

            case "clear":
                if (c.value == true)
                {
                    _text = "";
                    pushTextToOutput();
                    c.value = false;
                }

            case "editable":
                _editable = (c.value == true);

            case "wordWrap":
                _wordWrap = (c.value == true);

            case "autoScroll":
                _autoScroll = (c.value == true);

            case "hScroll":
                _hScroll = (c.value == true);

            case "vScroll":
                _vScroll = (c.value == true);

            case "maxChars":
                var v = Std.int(c.value);
                if (v >= 5 && v <= 200) _maxChars = v;

            case "numLines":
                var v = Std.int(c.value);
                if (v >= 1 && v <= 100) _numLines = v;
        }

        super.onContactChanged(c);
    }

    /**
    * Push current text to output and fire changed pulse.
    */
    private function pushTextToOutput():Void
    {
        var textOut = getOutput("text");
        if (textOut != null) textOut.value = _text;

        var lineCountOut = getOutput("lineCount");
        if (lineCountOut != null)
        {
            var lines = _text.split("\n");
            lineCountOut.value = lines.length;
        }

        var changedOut = getOutput("changed");
        if (changedOut != null)
        {
            changedOut.value = true;
            // Reset pulse after 3 ticks (~50ms at 60Hz)
            core.logic.TickGenerator.getInstance().scheduleNextTick(function()
            {
                core.logic.TickGenerator.getInstance().scheduleNextTick(function()
                {
                    core.logic.TickGenerator.getInstance().scheduleNextTick(function()
                    {
                        if (changedOut != null) changedOut.value = false;
                    });
                });
            });
        }
    }

    // =========================================================================
    // PUBLIC API (for Widget)
    // =========================================================================
    public function getText():String return _text;
    public function isEditable():Bool return _editable;
    public function isWordWrap():Bool return _wordWrap;
    public function isAutoScroll():Bool return _autoScroll;
    public function isHScroll():Bool return _hScroll;
    public function isVScroll():Bool return _vScroll;
    public function getMaxChars():Int return _maxChars;
    public function getNumLines():Int return _numLines;

    /**
    * Called by widget when user edits text.
    * Updates internal state and output contacts.
    */
    public function setTextFromWidget(newText:String):Void
    {
        if (newText != _text)
        {
            _text = newText;
            // Sync input contact silently
            var textIn = getInput("text");
            if (textIn != null) textIn.setValueSilent(_text);
            pushTextToOutput();
        }
    }

    /**
    * Called by widget to report cursor line.
    */
    public function setCursorLine(line:Int):Void
    {
        var c = getOutput("cursorLine");
        if (c != null) c.value = line;
    }

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result:Dynamic = {
            text: _text,
            editable: _editable,
            wordWrap: _wordWrap,
            autoScroll: _autoScroll,
            hScroll: _hScroll,
            vScroll: _vScroll,
            maxChars: _maxChars,
            numLines: _numLines
        };
        if (base != null)
        {
            for (field in Reflect.fields(base))
            {
                Reflect.setField(result, field, Reflect.field(base, field));
            }
        }
        return result;
    }

    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        super.restoreState(state);

        if (state.text != null)
        {
            _text = Std.string(state.text);
            var textOut = getOutput("text");
            if (textOut != null) textOut.value = _text;
            var textIn = getInput("text");
            if (textIn != null) textIn.value = _text;
        }
        if (state.editable != null) _editable = state.editable;
        if (state.wordWrap != null) _wordWrap = state.wordWrap;
        if (state.autoScroll != null) _autoScroll = state.autoScroll;
        if (state.hScroll != null) _hScroll = state.hScroll;
        if (state.vScroll != null) _vScroll = state.vScroll;
        if (state.maxChars != null)
        {
            var v = Std.int(state.maxChars);
            if (v >= 5 && v <= 200) _maxChars = v;
        }
        if (state.numLines != null)
        {
            var v = Std.int(state.numLines);
            if (v >= 1 && v <= 100) _numLines = v;
        }

        // Update line count output
        var lineCountOut = getOutput("lineCount");
        if (lineCountOut != null)
        {
            lineCountOut.value = _text.split("\n").length;
        }
    }
}