// FILE: library/electro/TextAreaAtom.hx
package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * TEXT AREA ATOM v1.3 (Bounded Scrollback Buffer)
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
 * │   │  - bufferLines (Int)    → Scrollback buffer limit (lines)       │   │
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
 * │   v1.3 BUFFER INVARIANT:                                                │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  _text is BOUNDED at all times:                                 │   │
 * │   │    ≤ _bufferLines lines                    (Pass 1, tail trim)  │   │
 * │   │    ≤ _bufferLines * (_maxChars + 1) chars  (Pass 2, hard cap)   │   │
 * │   │  Enforced on EVERY ingestion path: textIn, append, widget edit, │   │
 * │   │  restoreState — and on bufferLines/maxChars config changes.     │   │
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
 * │ bufferLines      │ 256           │
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
 *
 * v1.3 Changes:
 * - ADDED: "bufferLines" input — bounded scrollback buffer (default 256
 *   lines, clamped 10..5000). _text can no longer grow without bound.
 *   Root-cause fix for the "Memory exhausted" crash in high-frequency
 *   loops (Selfrun soak test: unbounded append + O(N) garbage per append).
 * - ADDED: trimBuffer() — line-based tail trim (Pass 1) + hard character
 *   cap _bufferLines * (_maxChars + 1) (Pass 2) as backstop for streams
 *   without newlines (e.g. "BeginBeginBegin...").
 * - CHANGED: lineCount is computed by zero-allocation counter
 *   countLines() instead of String.split("\n") — identical semantics.
 * - CHANGED: buffer limit enforced on ALL ingestion paths: textIn,
 *   append, setTextFromWidget, restoreState, and on bufferLines /
 *   maxChars runtime changes.
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
    private var _bufferLines:Int = 256;   // v1.3: scrollback limit (lines)

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
                new Contact(8, INPUT, "numLines"),
                new Contact(256, INPUT, "bufferLines")   // v1.3
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
     * │  textIn changed → _text = newValue → trimBuffer()               │
     * │                   → pushTextToOutput()                          │
     * │  append changed → _text += newValue → trimBuffer()              │
     * │                   → pushTextToOutput()                          │
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

                    // v1.3: Bulk text from outside is subject to the
                    // buffer limit too — a huge textIn must not blow it.
                    trimBuffer();

                    pushTextToOutput();
                }

            case "append":
                var appendStr = Std.string(c.value);
                if (appendStr != "" && appendStr != "null")
                {
                    // Data is appended exactly as received,
                    // allowing the sender to control formatting.
                    _text += appendStr;

                    // v1.3: Enforce scrollback limit after every append.
                    // This is the root-cause fix for unbounded _text
                    // growth ("Memory exhausted" in high-frequency loops).
                    trimBuffer();

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
                if (v >= 5 && v <= 200)
                {
                    _maxChars = v;
                    // v1.3: Hard cap depends on maxChars — re-enforce.
                    retrimIfChanged();
                }

            case "numLines":
                var v = Std.int(c.value);
                if (v >= 1 && v <= 100) _numLines = v;

            case "bufferLines":
                var v = Std.int(c.value);
                if (v >= 10 && v <= 5000)
                {
                    _bufferLines = v;
                    // v1.3: Shrinking the buffer trims immediately.
                    retrimIfChanged();
                }
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
     * │       ├──► lineCount.value = countLines()  (zero-alloc, v1.3)   │
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
            // v1.3: Zero-allocation line counting.
            // Was: _text.split("\n").length — allocated a full array
            // plus string copies on every append.
            lineCountOut.value = countLines();
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
    // BUFFER MANAGEMENT (v1.3)
    // =========================================================================

    /**
     * Enforce the scrollback buffer limit on _text (v1.3).
     *
     * Pass 1 — line-based tail trim: keeps the last _bufferLines lines.
     *          Counts '\n' terminators from the END and stops scanning
     *          as soon as the limit is exceeded — O(K), not O(N).
     * Pass 2 — hard character cap: _bufferLines * (_maxChars + 1) chars
     *          (+1 accounts for each line's '\n'). Backstop for streams
     *          without newlines (e.g. "BeginBeginBegin..."), where
     *          Pass 1 never triggers.
     *
     * Both passes keep the TAIL of the text — in a terminal the newest
     * data is at the end, so the oldest content scrolls away.
     */
    private function trimBuffer():Void
    {
        if (_text == null || _text.length == 0) return;

        // ── Pass 1: keep the last _bufferLines lines ──
        var nl = 0;
        var i = _text.length - 1;
        while (i >= 0)
        {
            if (_text.charCodeAt(i) == 10) // '\n'
            {
                nl++;
                if (nl > _bufferLines)
                {
                    _text = _text.substr(i + 1);
                    break;
                }
            }
            i--;
        }

        // ── Pass 2: hard cap for newline-less streams ──
        var hardCap = _bufferLines * (_maxChars + 1);
        if (_text.length > hardCap)
        {
            _text = _text.substr(_text.length - hardCap);
        }
    }

    /**
     * v1.3: Zero-allocation line counter.
     *
     * Semantically identical to _text.split("\n").length
     * ("" → 1, "a" → 1, "a\n" → 2, "a\nb" → 2, ...),
     * but allocates nothing — no array, no string copies.
     */
    private function countLines():Int
    {
        if (_text == null || _text.length == 0) return 1;
        var n = 1;
        for (i in 0..._text.length)
        {
            if (_text.charCodeAt(i) == 10) n++;
        }
        return n;
    }

    /**
     * v1.3 helper: re-enforce the buffer limit after a config change
     * (bufferLines / maxChars). Pushes to outputs only when the text
     * actually shrank — no spurious "changed" pulses on config-only
     * updates.
     */
    private function retrimIfChanged():Void
    {
        var before = _text;
        trimBuffer();
        if (_text != before) pushTextToOutput();
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
    public function getBufferLines():Int return _bufferLines;   // v1.3

    /**
     * Called by widget when user edits text.
     * Updates internal state and output contacts.
     *
     * v1.2: Uses setValueSilent for textIn sync to prevent
     * feedback loop (textIn.value = _text would re-trigger
     * onContactChanged → case "textIn" → pushTextToOutput again).
     *
     * v1.3: Widget edits obey the same buffer limit as programmatic
     * ingestion — pasting a huge block through the widget must not
     * bypass the invariant.
     */
    public function setTextFromWidget(newText:String):Void
    {
        if (newText != _text)
        {
            _text = newText;

            // v1.3: Enforce buffer limit on widget-originated text.
            trimBuffer();

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
            numLines: _numLines,
            bufferLines: _bufferLines   // v1.3
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
     *
     * v1.3: trimBuffer() runs AFTER config restoration (so
     * _bufferLines/_maxChars are current) — a project saved with an
     * oversized text blob must not resurrect it on load.
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
        if (state.bufferLines != null)   // v1.3
        {
            var v = Std.int(state.bufferLines);
            if (v >= 10 && v <= 5000) _bufferLines = v;
        }

        // v1.3: Enforce buffer limit on restored text, then re-sync
        // contacts silently (still no propagate during load).
        trimBuffer();
        var textOutSync = getOutput("textOut");
        if (textOutSync != null) textOutSync.setValueSilent(_text);

        var textInSync = getInput("textIn");
        if (textInSync != null) textInSync.setValueSilent(_text);

        // Update line count output (silent — no propagate during load)
        var lineCountOut = getOutput("lineCount");
        if (lineCountOut != null)
        {
            lineCountOut.setValueSilent(countLines());
        }
    }
}