// FILE: library/electro/DebugConsoleAtom.hx
package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     DEBUG CONSOLE ATOM v1.3                               ║
 * ║              (Passive Atom + TickGenerator Pulse Reset)                   ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Captures trace() output and exposes it as atom outputs.                  ║
 * ║  Use with DebugConsoleWidget for in-app log viewing.                      ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  Main.hx                                                            │  ║
 * ║  │                                                                     │  ║
 * ║  │  haxe.Log.trace = function(v, ?infos) {                             │  ║
 * ║  │      #if html5                                                      │  ║
 * ║  │      untyped console.log(v);                                        │  ║
 * ║  │      #end                                                           │  ║
 * ║  │      DebugConsoleAtom.log(Std.string(v));                           │  ║
 * ║  │  };                                                                 │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                              │                                            ║
 * ║                              ▼                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  DebugConsoleAtom (Passive Databank)                                │  ║
 * ║  │                                                                     │  ║
 * ║  │  STATIC API:                                                        │  ║
 * ║  │  • DebugConsoleAtom.log(msg) → dispatch to all active instances     │  ║
 * ║  │                                                                     │  ║
 * ║  │  INPUTS (manual control from other atoms):                          │  ║
 * ║  │  • log      (String) → Replace entire buffer with single message   │  ║
 * ║  │  • append   (String) → Append message to existing buffer            │  ║
 * ║  │  • clear    (Bool)   → Clear buffer on true pulse                   │  ║
 * ║  │  • maxLines (Int)    → Max lines before trimming (default 500)      │  ║
 * ║  │  • enabled  (Bool)   → Master enable/disable                        │  ║
 * ║  │                                                                     │  ║
 * ║  │  OUTPUTS (to DebugConsoleWidget):                                   │  ║
 * ║  │  • output    (String) → Full log content (newline-separated)        │  ║
 * ║  │  • changed   (Bool)   → Pulse on any log change                    │  ║
 * ║  │  • lineCount (Int)    → Current number of lines in buffer          │  ║
 * ║  │                                                                     │  ║
 * ║  │  DATABANK:                                                          │  ║
 * ║  │  • _logBuffer: Array<String> — in-memory log storage                │  ║
 * ║  │  • _maxLines:  Int          — auto-trim threshold                   │  ║
 * ║  │  • _enabled:   Bool         — processing gate                       │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                              │                                            ║
 * ║                              ▼                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  DebugConsoleWidget (Face)                                          │  ║
 * ║  │  Subscribes to "output" and "lineCount" contacts.                   │  ║
 * ║  │  Displays scrollable text area with Clear button.                   │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     v1.3 CHANGES                                          ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  v1.3 — TickGenerator Pulse Reset (Passive Atom Pattern)                  ║
 * ║  ──────────────────────────────────────────────────────                    ║
 * ║  - FIXED: Replaced update(dt) timer with TickGenerator.scheduleNextTick   ║
 * ║    for "changed" pulse reset. This atom is NOT an active driver           ║
 * ║    (isActive=false in AtomRegistry), so update(dt) was never called       ║
 * ║    by DriverManager, causing "changed" to stay true forever.              ║
 * ║  - FIXED: Added null/empty guard in static log() method.                  ║
 * ║  - FIXED: Added isDisposed check in static log() to prevent               ║
 * ║    use-after-free if atom is disposed while trace() is called.            ║
 * ║  - ADDED: Detailed ASCII architecture tables.                             ║
 * ║                                                                           ║
 * ║  v1.2 — Fixed Output Contract                                             ║
 * ║  ────────────────────────────────                                         ║
 * ║  - FIXED: Output contact named "output" (not "log").                      ║
 * ║  - FIXED: Silent reset of input contacts to prevent re-trigger.           ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class DebugConsoleAtom extends Atom
{
    // =========================================================================
    // REGISTRY — Static instance tracking
    // =========================================================================
    /**
     * All active DebugConsoleAtom instances.
     * Static log() dispatches messages to all registered instances.
     * Instances are added in constructor and removed in dispose().
     */
    private static var _instances:Array<DebugConsoleAtom> = [];

    // =========================================================================
    // DATABANK — Internal state
    // =========================================================================
    /** In-memory log buffer. Each element is one line (with timestamp). */
    private var _logBuffer:Array<String> = [];
    /** Maximum number of lines before auto-trimming oldest entries. */
    private var _maxLines:Int = 500;
    /** Master enable flag. When false, static log() skips this instance. */
    private var _enabled:Bool = true;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
     * Create a new DebugConsoleAtom.
     *
     * This is a PASSIVE atom (isActive=false) — it does not need
     * per-tick update(dt) calls from DriverManager. All processing
     * happens synchronously when trace() is called or when input
     * contacts change.
     *
     * @param id Unique runtime instance ID
     */
    public function new(id:String)
    {
        super(
            // === INPUTS ===
            [
                new Contact("", ContactType.INPUT, "log"),
                new Contact("", ContactType.INPUT, "append"),
                new Contact(false, ContactType.INPUT, "clear"),
                new Contact(500, ContactType.INPUT, "maxLines"),
                new Contact(true, ContactType.INPUT, "enabled")
            ],
            // === OUTPUTS ===
            [
                new Contact("", ContactType.OUTPUT, "output"),
                new Contact(false, ContactType.OUTPUT, "changed"),
                new Contact(0, ContactType.OUTPUT, "lineCount")
            ],
            null,   // No process function — passive atom
            id,
            "DebugConsole",
            false   // isActive = false (passive atom)
        );
        
        // Register this instance for static log() dispatch
        _instances.push(this);
    }

    // =========================================================================
    // STATIC API — Global trace() capture
    // =========================================================================
    /**
     * Send log message to ALL active DebugConsoleAtom instances.
     *
     * Called from custom trace() handler in Main.hx:
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  haxe.Log.trace = function(v, ?infos) {                         │
     * │      #if html5                                                  │
     * │      untyped console.log(v);                                    │
     * │      #end                                                       │
     * │      DebugConsoleAtom.log(Std.string(v));                       │
     * │  };                                                             │
     * └─────────────────────────────────────────────────────────────────┘
     *
     * Safety checks:
     * - Skip if msg is null or empty
     * - Skip if instance is disposed (use-after-free protection)
     * - Skip if instance is disabled via "enabled" input contact
     *
     * @param msg Log message string
     */
    public static function log(msg:String):Void
    {
        if (msg == null || msg == "") return;
        
        for (inst in _instances)
        {
            if (inst != null && !inst._isDisposed && inst._enabled)
            {
                inst._appendToBuffer(msg);
            }
        }
    }

	
    // =========================================================================
    // CONTACT HANDLER — Input processing
    // =========================================================================
    /**
     * Handle input contact changes.
     *
     * ┌─────────────────────────────────────────────────────────────────┐
     * │  Input Processing:                                              │
     * │                                                                 │
     * │  "log" (String)    → Replace mode: clear buffer, add message    │
     * │  "append" (String) → Append mode: add to existing buffer        │
     * │  "clear" (Bool)    → Clear buffer on true pulse                 │
     * │  "maxLines" (Int)  → Update trim threshold (10..10000)          │
     * │  "enabled" (Bool)  → Toggle processing on/off                   │
     * │                                                                 │
     * │  All pulse inputs use setValueSilent() to reset without         │
     * │  triggering a parasitic propagate cycle.                        │
     * └─────────────────────────────────────────────────────────────────┘
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isDisposed) return;

        switch (c.name)
        {
            case "log":
                // Replace mode: clear buffer and add new message
                if (c.value != null && c.value != "")
                {
                    _logBuffer = [];
                    _appendToBuffer(Std.string(c.value));
                    c.setValueSilent("");
                }

            case "append":
                // Append mode: add to existing buffer
                if (c.value != null && c.value != "")
                {
                    _appendToBuffer(Std.string(c.value));
                    c.setValueSilent("");
                }

            case "clear":
                // Clear buffer on true pulse
                if (c.value == true)
                {
                    _logBuffer = [];
                    _updateOutputs();
                    c.setValueSilent(false);
                }

            case "maxLines":
                // Update max lines (clamped to 10..10000)
                var v = Std.int(c.value);
                if (v >= 10 && v <= 10000)
                {
                    _maxLines = v;
                    // Trim buffer if it exceeds new limit
                    while (_logBuffer.length > _maxLines)
                    {
                        _logBuffer.shift();
                    }
                    _updateOutputs();
                }

            case "enabled":
                // Toggle processing
                _enabled = (c.value == true);
        }

        super.onContactChanged(c);
    }

    // =========================================================================
    // INTERNAL LOGIC — Buffer management
    // =========================================================================
    /**
     * Append a message to the log buffer with timestamp.
     *
     * Format: "HH:MM:SS | message"
     *
     * After appending, trims oldest entries if buffer exceeds _maxLines,
     * then updates all output contacts.
     *
     * @param msg Message to append
     */
    private function _appendToBuffer(msg:String):Void
    {
        // Add timestamp prefix
        var now = Date.now();
        var hours = StringTools.lpad(Std.string(now.getHours()), "0", 2);
        var minutes = StringTools.lpad(Std.string(now.getMinutes()), "0", 2);
        var seconds = StringTools.lpad(Std.string(now.getSeconds()), "0", 2);
        var logLine = '$hours:$minutes:$seconds | $msg';
        
        _logBuffer.push(logLine);

        // Trim oldest entries if buffer exceeds maxLines
        while (_logBuffer.length > _maxLines)
        {
            _logBuffer.shift();
        }

        _updateOutputs();
    }

    /**
     * Update all output contacts with current buffer state.
     *
     * Uses batched driver update pattern:
     * 1. setValueSilent() — write without triggering propagate
     * 2. propagateCurrentValue() — single propagation wave
     *
     * "changed" pulse is reset via TickGenerator.scheduleNextTick
     * (3 ticks ≈ 50ms at 60Hz) instead of update(dt) timer,
     * because this atom is passive and update(dt) is never called.
     */
    private function _updateOutputs():Void
    {
        // Join buffer into single newline-separated string
        var fullLog = _logBuffer.join("\n");
        
        // === OUTPUT: output (full log content) ===
        var output = getOutput("output");
        if (output != null)
        {
            output.setValueSilent(fullLog);
            output.propagateCurrentValue();
        }
        
        // === OUTPUT: lineCount (number of lines) ===
        var lineCount = getOutput("lineCount");
        if (lineCount != null)
        {
            lineCount.setValueSilent(_logBuffer.length);
            lineCount.propagateCurrentValue();
        }
        
        // === OUTPUT: changed (pulse) ===
        var changed = getOutput("changed");
        if (changed != null)
        {
            changed.value = true;
            
            // v1.3 FIX: Reset pulse via TickGenerator instead of update(dt).
            // This atom is passive (isActive=false), so DriverManager never
            // calls update(dt). Using scheduleNextTick ensures the pulse
            // resets after ~50ms (3 ticks at 60Hz).
            var changedRef = changed;
            TickGenerator.getInstance().scheduleNextTick(function()
            {
                TickGenerator.getInstance().scheduleNextTick(function()
                {
                    TickGenerator.getInstance().scheduleNextTick(function()
                    {
                        if (changedRef != null && !changedRef.isDisposed)
                        {
                            changedRef.value = false;
                        }
                    });
                });
            });
        }
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    /**
     * Dispose the atom and unregister from static instances.
     * Prevents use-after-free if trace() is called after disposal.
     */
    override public function dispose():Void
    {
        _instances.remove(this);
        super.dispose();
    }
}