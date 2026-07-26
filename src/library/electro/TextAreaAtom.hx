// FILE: library/electro/TextAreaAtom.hx
package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT AREA ATOM v1.2 (Contact Name Consistency + Silent Append Reset)
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
 * │   │  - textIn     (String)  → Full text content (replaces all)      │   │
 * │   │  - append     (String)  → Append text to existing content       │   │
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
 * │   │  - textOut    (String)  → Current text content                  │   │
 * │   │  - changed    (Bool)    → Pulse on text change                  │   │
 * │   │  - lineCount  (Int)     → Current number of lines               │   │
 * │   │  - cursorLine (Int)     → Current cursor line number            │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Widget (TextAreaWidget) reads config from atom's contacts.            │
 * │   Widget writes to "textIn" contact or setTextFromWidget() on input.    │
 * │   Atom is the Databank — single source of truth.                        │
 * │                                                                         │
 * │   v1.2 CONTACT NAME CONTRACT (CRITICAL):                                │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Input:  "textIn"   ← Widget and external atoms write HERE      │   │
 * │   │  Output: "textOut"  ← Widget subscribes to THIS for updates     │   │
 * │   │                                                                 │   │
 * │   │  Both Widget and Atom MUST use these EXACT names.               │   │
 * │   │  Never use "text" as a contact name — it's ambiguous.           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
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
 *
 * v1.2 Changes:
 * - FIXED: append reset uses setValueSilent() instead of c.value = ""
 *   to prevent parasitic propagate cycle on every append operation.
 * - FIXED: restoreState() uses setValueSilent() for textIn to prevent
 *   double propagate wave during Load-Symmetric Reconstruction.
 * - ADDED: Explicit contact name contract documentation.
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
                new Contact("", INPUT, "textIn"),
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
                new Contact("", OUTPUT, "textOut"),
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
     *
     * Data flow for text operations:
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  textIn changed → _text = newValue → pushTextToOutput()         │
     * │  append changed → _text += newValue → pushTextToOutput()        │
     * │                   → setValueSilent("") to reset (no propagate)  │
     * │  clear == true  → _text = "" → pushTextToOutput()               │
     * │                   → setValueSilent(false) to reset              │
     * └─────────────────────────────────────────────────────────────────┘
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isDisposed) return;

        switch (c.name)
        {
            case "textIn":
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
                    // Data is appended exactly as received,
                    // allowing the sender to control formatting.
                    _text += appendStr;

                    pushTextToOutput();

                    // v1.2 FIX: Use setValueSilent to reset append input.
                    // Previous code used c.value = "" which triggered a
                    // parasitic propagate cycle:
                    //   c.value="" → propagate → onContactChanged("append")
                    //   → appendStr=="" → exit (wasted cycle)
                    // setValueSilent writes directly to _value without
                    // scheduling propagation, breaking the cycle cleanly.
                    c.setValueSilent("");
                }

            case "clear":
                if (c.value == true)
                {
                    _text = "";
                    pushTextToOutput();
                    // v1.2: Silent reset to prevent re-trigger
                    c.setValueSilent(false);
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
     *
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  pushTextToOutput()                                             │
     * │       │                                                         │
     * │       ├──► textOut.value = _text                                │
     * │       │                                                         │
     * │       ├──► lineCount.value = _text.split("\n").length           │
     * │       │                                                         │
     * │       └──► changed.value = true                                 │
     * │              │                                                  │
     * │              └──► scheduleNextTick ×3 → changed.value = false   │
     * │                   (pulse reset after ~50ms at 60Hz)             │
     * └─────────────────────────────────────────────────────────────────┘
     */
    private function pushTextToOutput():Void
    {
        var textOut = getOutput("textOut");
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
                        if (changedOut != null && !changedOut.isDisposed)
                        {
                            changedOut.value = false;
                        }
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
     *
     * v1.2: Uses setValueSilent for textIn sync to prevent
     * feedback loop (textIn.value = _text would re-trigger
     * onContactChanged → case "textIn" → pushTextToOutput again).
     */
    public function setTextFromWidget(newText:String):Void
    {
        if (newText != _text)
        {
            _text = newText;
            // Sync input contact silently — no propagate needed
            // because we already call pushTextToOutput() below.
            var textIn = getInput("textIn");
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

    /**
     * v1.2 FIX: Uses setValueSilent for both textIn and textOut
     * during restore to prevent propagate waves during loading.
     *
     * Load-Symmetric Reconstruction principle:
     * restoreState() must NOT trigger side-effect propagate chains.
     * The Assembly._processPendingSignals() handles final sync wave.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        super.restoreState(state);

        if (state.text != null)
        {
            _text = Std.string(state.text);

            // v1.2 FIX: Silent writes — no propagate during load.
            // Previous code used .value = which triggered:
            //   textIn.value → onContactChanged → pushTextToOutput
            //   → textOut.value (double write + propagate wave)
            var textOut = getOutput("textOut");
            if (textOut != null) textOut.setValueSilent(_text);

            var textIn = getInput("textIn");
            if (textIn != null) textIn.setValueSilent(_text);
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

        // Update line count output (silent — no propagate during load)
        var lineCountOut = getOutput("lineCount");
        if (lineCountOut != null)
        {
            lineCountOut.setValueSilent(_text.split("\n").length);
        }
    }
}