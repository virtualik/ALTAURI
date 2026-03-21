package library.electro;

import core.base.Atom;
import core.base.Contact;

/**
 * OSCILLOSCOPE ATOM v2.0 (Databank Architecture)
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * OscilloscopeAtom - это пассивный атом-накопитель данных.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeAtom                                                      │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   onContactChanged(c) {                                                 │
 * │       if (c.name == "in" && c.value != null) {                          │
 * │           processInput(c.value);  // Накапливает данные                 │
 * │       }                                                                 │
 * │   }                                                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   private var _buffer:Array<Float>;        // Кольцевой буфер 512       │
 * │   private var _writeIndex:Int = 0;         // Текущая позиция записи    │
 * │   private var _samplesCollected:Int = 0;   // Сколько сэмплов собрано   │
 * │   private var _totalSamples:Int = 0;       // Общий счётчик             │
 * │                                                                         │
 * │   public function getBuffer():Array<Float>  // API для DeviceView       │
 * │   public function getWriteIndex():Int                                   │
 * │   public function getSamplesCollected():Int                             │
 * │                                                                         │
 * │   getPersistentState() { return { buffer, writeIndex, ... }; }          │
 * │   restoreState(state) { ... }                                           │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   OscilloscopeWidget читает из Databank:                                │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │ var buffer = oscAtom.getBuffer();                               │   │
 * │   │ var idx = oscAtom.getWriteIndex();                              │   │
 * │   │ drawWave(buffer, idx, oscAtom.getSamplesCollected());           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Headless Mode:                                                        │
 * │   ──────────────                                                        │
 * │   Атом работает автономно - накапливает данные в буфер.                 │
 * │   DeviceView не нужен для работы.                                       │
 * │   Данные могут быть сохранены через getPersistentState().               │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v2.0 Changes:
 * - COMPLETE REWRITE for Databank architecture
 * - Buffer moved FROM OscilloscopeWidget TO OscilloscopeAtom
 * - Works in Headless mode (no UI required)
 * - Multiple DeviceViews see the SAME buffer
 * - State serialization via getPersistentState/restoreState
 *
 * v1.2 (Old):
 * - Was passive, no buffer
 * - Widget had to manage its own buffer
 * - Data lost when widget closed
 */
class OscilloscopeAtom extends Atom {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    /**
     * Size of the ring buffer.
     * 512 samples = ~12ms of audio at 44.1kHz
     * Good for visualizing 1-3 periods of most signals
     */
    private static inline var BUFFER_SIZE:Int = 512;

    // =========================================================================
    // DATABANK - Core Data Storage
    // =========================================================================

    /**
     * Ring buffer for incoming samples.
     * Overwrites old data when full.
     */
    private var _buffer:Array<Float>;

    /**
     * Current write position in the ring buffer.
     * Range: [0, BUFFER_SIZE-1]
     */
    private var _writeIndex:Int = 0;

    /**
     * Number of valid samples in buffer.
     * Increases until BUFFER_SIZE, then stays constant.
     */
    private var _samplesCollected:Int = 0;

    /**
     * Total number of samples received.
     * Used for statistics and debugging.
     */
    private var _totalSamples:Int = 0;

    /**
     * Last received value (for simple displays).
     */
    private var _lastValue:Float = 0.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    public function new(id:String) {
        // OscilloscopeAtom has:
        // - One INPUT contact "in" (receives samples)
        // - No outputs (passive display atom)
        super(
            [
                // Input for sample buffer - MUST be named "in"
                new Contact(null, INPUT, "in")
            ],
            [],  // No outputs - this is a display atom
            null, // No process function - we handle in onContactChanged
            id,
            "Oscilloscope",
            false // Not an active driver
        );

        // Initialize ring buffer with zeros
        _buffer = [];
        for (i in 0...BUFFER_SIZE) {
            _buffer.push(0.0);
        }

        trace('OscilloscopeAtom: Created with buffer size $BUFFER_SIZE');
    }

    // =========================================================================
    // DATA PROCESSING (Compute Module)
    // =========================================================================

    /**
     * Called when Contact value changes.
     *
     * This is where we process incoming data.
     * Works in BOTH Headless and Normal modes.
     *
     * @param c Contact that changed
     */
    override public function onContactChanged(c:Contact):Void {
        if (this._isDisposed) return;

        // Process input contact
        if (c.name == "in" && c.value != null) {
            processInput(c.value);
        }
    }

    /**
     * Process incoming data and store in Databank.
     *
     * Accepts:
     * - Float (single sample)
     * - Int (converted to Float)
     * - Array<Float> (multiple samples)
     * - Array<Dynamic> (converted to Float)
     *
     * @param value Input data
     */
    private function processInput(value:Dynamic):Void {
        _totalSamples++;

        if (Std.isOfType(value, Float)) {
            addSample(cast(value, Float));

        } else if (Std.isOfType(value, Int)) {
            addSample(cast(value, Int) * 1.0);

        } else if (Std.isOfType(value, Array)) {
            var arr:Array<Dynamic> = cast value;

            if (arr.length > 0) {
                // Check if it's Array<Float>
                if (Std.isOfType(arr[0], Float)) {
                    var floatArr:Array<Float> = cast arr;
                    addSamples(floatArr);
                } else {
                    // Convert to Float
                    for (item in arr) {
                        if (Std.isOfType(item, Float)) {
                            addSample(cast(item, Float));
                        } else if (Std.isOfType(item, Int)) {
                            addSample(cast(item, Int) * 1.0);
                        }
                    }
                }
            }
        }
    }

    /**
     * Add a single sample to the ring buffer.
     *
     * @param value Sample value (will be clamped to [-1, 1])
     */
    private function addSample(value:Float):Void {
        // Clamp to valid range
        if (value > 1.0) value = 1.0;
        if (value < -1.0) value = -1.0;

        // Store in buffer
        _buffer[_writeIndex] = value;
        _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;

        // Update counters
        if (_samplesCollected < BUFFER_SIZE) {
            _samplesCollected++;
        }

        _lastValue = value;
    }

    /**
     * Add multiple samples to the ring buffer.
     *
     * @param samples Array of sample values
     */
    private function addSamples(samples:Array<Float>):Void {
        if (samples == null || samples.length == 0) return;

        for (s in samples) {
            var val = s;
            // Clamp
            if (val > 1.0) val = 1.0;
            if (val < -1.0) val = -1.0;

            _buffer[_writeIndex] = val;
            _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;

            if (_samplesCollected < BUFFER_SIZE) {
                _samplesCollected++;
            }
        }

        if (samples.length > 0) {
            _lastValue = samples[samples.length - 1];
        }
    }

    // =========================================================================
    // PUBLIC API (For DeviceView)
    // =========================================================================

    /**
     * Get the ring buffer.
     * DeviceView reads from this to draw the waveform.
     *
     * @return Array of 512 samples
     */
    public function getBuffer():Array<Float> {
        return _buffer;
    }

    /**
     * Get current write position.
     * Used by DeviceView to determine the "end" of new data.
     *
     * @return Write index [0, BUFFER_SIZE-1]
     */
    public function getWriteIndex():Int {
        return _writeIndex;
    }

    /**
     * Get number of valid samples collected.
     * Less than BUFFER_SIZE means buffer is still filling.
     *
     * @return Sample count
     */
    public function getSamplesCollected():Int {
        return _samplesCollected;
    }

    /**
     * Get total samples received.
     * Used for statistics display.
     *
     * @return Total count
     */
    public function getTotalSamples():Int {
        return _totalSamples;
    }

    /**
     * Get the last received value.
     * Useful for simple numeric displays.
     *
     * @return Last sample value
     */
    public function getLastValue():Float {
        return _lastValue;
    }

    /**
     * Get the buffer size.
     *
     * @return BUFFER_SIZE constant
     */
    public function getBufferSize():Int {
        return BUFFER_SIZE;
    }

    /**
     * Clear the buffer and reset counters.
     * Useful for "Reset" button in UI.
     */
    public function clearBuffer():Void {
        _writeIndex = 0;
        _samplesCollected = 0;
        _totalSamples = 0;
        _lastValue = 0.0;

        // Clear buffer
        for (i in 0...BUFFER_SIZE) {
            _buffer[i] = 0.0;
        }

        trace('OscilloscopeAtom: Buffer cleared');
    }

    // =========================================================================
    // STATE SERIALIZATION (Databank Persistence)
    // =========================================================================

    /**
     * Get state for project saving.
     *
     * Returns the buffer and indices so the oscilloscope
     * can be restored to its exact state on load.
     *
     * @return State object with buffer data
     */
    override public function getPersistentState():Dynamic {
        return {
            buffer: _buffer.copy(),
            writeIndex: _writeIndex,
            samplesCollected: _samplesCollected,
            totalSamples: _totalSamples,
            lastValue: _lastValue
        };
    }

    /**
     * Restore state from saved data.
     *
     * Called when loading a project.
     * Restores the buffer to its previous state.
     *
     * @param state Saved state from getPersistentState()
     */
    override public function restoreState(state:Dynamic):Void {
        if (state == null) return;

        // Restore buffer
        if (state.buffer != null && Std.isOfType(state.buffer, Array)) {
            var savedBuffer:Array<Dynamic> = cast state.buffer;
            for (i in 0...Std.int(Math.min(savedBuffer.length, BUFFER_SIZE))) {
                if (Std.isOfType(savedBuffer[i], Float)) {
                    _buffer[i] = savedBuffer[i];
                }
            }
        }

        // Restore indices
        if (state.writeIndex != null && Std.isOfType(state.writeIndex, Int)) {
            _writeIndex = state.writeIndex;
            if (_writeIndex < 0) _writeIndex = 0;
            if (_writeIndex >= BUFFER_SIZE) _writeIndex = BUFFER_SIZE - 1;
        }

        if (state.samplesCollected != null && Std.isOfType(state.samplesCollected, Int)) {
            _samplesCollected = state.samplesCollected;
            if (_samplesCollected < 0) _samplesCollected = 0;
            if (_samplesCollected > BUFFER_SIZE) _samplesCollected = BUFFER_SIZE;
        }

        if (state.totalSamples != null && Std.isOfType(state.totalSamples, Int)) {
            _totalSamples = state.totalSamples;
            if (_totalSamples < 0) _totalSamples = 0;
        }

        if (state.lastValue != null && Std.isOfType(state.lastValue, Float)) {
            _lastValue = state.lastValue;
        }

        trace('OscilloscopeAtom: Restored state (${_samplesCollected} samples)');
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        _buffer = null;
        super.dispose();
    }
}