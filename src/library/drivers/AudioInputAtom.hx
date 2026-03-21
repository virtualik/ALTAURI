package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;

/**
 * AUDIO INPUT ATOM v1.1 (Fixed Contacts)
 * Captures audio from microphone and outputs sample buffers.
 *
 * v1.1 Changes:
 * - FIXED: Contact names now match AtomRegistry registration
 * - Outputs: "samples", "peak", "rms", "active"
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * AudioInputAtom - это активный атом-генератор аудио данных.
 *
 * Outputs:
 * ────────
 * - "samples" : Array<Float> - audio sample buffer (512 samples)
 * - "peak"    : Float - current peak level [0.0, 1.0]
 * - "rms"     : Float - RMS level [0.0, 1.0]
 * - "active"  : Bool - is capture active
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * AudioInputAtom - это активный атом-генератор аудио данных.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   AudioInputAtom                                                        │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   update(dt) {                                                          │
 * │       // Читаем аудио буфер                                             │
 * │       // Отправляем на выход "samples"                                  │
 * │   }                                                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   private var _sampleRate:Int = 44100;                                  │
 * │   private var _channelCount:Int = 1;                                    │
 * │   private var _bufferSize:Int = 512;                                    │
 * │   private var _isActive:Bool = false;                                   │
 * │   private var _totalSamples:Int = 0;                                    │
 * │   private var _lastPeak:Float = 0.0;                                    │
 * │                                                                         │
 * │   private var _inputBuffer:Array<Float>; // Ring buffer                 │
 * │   private var _writePos:Int = 0;                                        │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   OscilloscopeWidget отображает samples                                 │
 * │   DeviceWidgetFactory.create() возвращает OscilloscopeWidget            │
 * │                                                                         │
 * │   HEADLESS MODE:                                                        │
 * │   ──────────────                                                        │
 * │   Атом работает автономно - захватывает аудио                           │
 * │   и отправляет на выход.                                                │
 * │   DeviceView не нужен для работы.                                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Outputs:
 * ────────
 * - "samples" : Array<Float> - audio sample buffer (512 samples)
 * - "peak" : Float - current peak level [0.0, 1.0]
 * - "rms" : Float - RMS level [0.0, 1.0]
 *
 * State Serialization:
 * ─────────────────────
 * - Sample rate, channel count, buffer size
 * - Total samples captured
 * - Running state
 */
class AudioInputAtom extends Atom {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    /**
     * Default sample rate.
     */
    private static inline var DEFAULT_SAMPLE_RATE:Int = 44100;

    /**
     * Default buffer size for output.
     */
    private static inline var DEFAULT_BUFFER_SIZE:Int = 512;

    /**
     * Default channel count.
     */
    private static inline var DEFAULT_CHANNELS:Int = 1;

    // =========================================================================
    // DATABANK - Configuration
    // =========================================================================

    /**
     * Sample rate of the audio input.
     */
    private var _sampleRate:Int;

    /**
     * Number of audio channels.
     */
    private var _channelCount:Int;

    /**
     * Size of the output buffer.
     */
    private var _bufferSize:Int;

    // =========================================================================
    // DATABANK - State
    // =========================================================================

    /**
     * Is audio capture currently active?
     */
    private var _isCapturing:Bool = false;

    /**
     * Total samples captured since start.
     */
    private var _totalSamples:Int = 0;

    /**
     * Last peak level [0.0, 1.0].
     */
    private var _lastPeak:Float = 0.0;

    /**
     * Last RMS level [0.0, 1.0].
     */
    private var _lastRMS:Float = 0.0;

    /**
     * Internal ring buffer for sample accumulation.
     */
    private var _internalBuffer:Array<Float>;

    /**
     * Write position in internal buffer.
     */
    private var _writePos:Int = 0;

    /**
     * Samples collected in internal buffer.
     */
    private var _internalCollected:Int = 0;

    // =========================================================================
    // AUDIO CONTEXT (Platform-specific)
    // =========================================================================

    /**
     * Platform audio context reference.
     * In a real implementation, this would be:
     * - Flash: flash.media.Microphone
     * - HTML5: js.html.AudioContext + getUserMedia
     * - OpenFL: lime.media.AudioSource
     *
     * For now, we simulate audio input with generated signal.
     */
    private var _audioSource:Dynamic;

    /**
     * Time accumulator for sample generation (simulation).
     */
    private var _timeAccum:Float = 0.0;

    /**
     * Frequency for test signal generation.
     */
    private var _testFrequency:Float = 440.0;

    /**
     * Enable test signal mode (when no microphone available).
     */
    private var _useTestSignal:Bool = true;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * Create an AudioInputAtom.
     *
     * @param id Unique identifier
     * @param sampleRate Audio sample rate (default: 44100)
     * @param bufferSize Output buffer size (default: 512)
     */
    public function new(
        id:String,
        ?sampleRate:Int = DEFAULT_SAMPLE_RATE,
        ?bufferSize:Int = DEFAULT_BUFFER_SIZE
    ) {
        _sampleRate = sampleRate;
        _bufferSize = bufferSize;
        _channelCount = DEFAULT_CHANNELS;

        // Create outputs
        var outputs:Array<Contact> = [
            new Contact(null, OUTPUT, "samples"),  // Array<Float>
            new Contact(0.0, OUTPUT, "peak"),      // Float [0, 1]
            new Contact(0.0, OUTPUT, "rms"),       // Float [0, 1]
            new Contact(false, OUTPUT, "active")   // Bool
        ];

        // Create with no inputs, no process function
        // We'll handle data in update() since this is an active atom
        super(
            [],           // No inputs
            outputs,      // Three outputs
            null,         // No process function
            id,
            "AudioInput",
            true          // isActive = true (register with DriverManager)
        );

        // Initialize internal buffer
        _internalBuffer = [];
        for (i in 0..._bufferSize) {
            _internalBuffer.push(0.0);
        }

        trace('AudioInputAtom: Created (id: $id, sampleRate: $_sampleRate, bufferSize: $_bufferSize)');
    }

    // =========================================================================
    // LIFECYCLE
    // =========================================================================

    /**
     * Initialize audio capture.
     */
    override public function init():Void {
        super.init();
        startCapture();
    }

    /**
     * Update each frame - generate or capture audio samples.
     *
     * @param dt Delta time in seconds
     */
    override private function _onUpdate(dt:Float):Void {
        if (!_isCapturing) return;

        // Generate or capture samples
        if (_useTestSignal) {
            generateTestSignal(dt);
        } else {
            // Real audio capture would happen here
            captureRealAudio(dt);
        }
    }

    // =========================================================================
    // AUDIO CAPTURE
    // =========================================================================

    /**
     * Start audio capture.
     */
    public function startCapture():Void {
        if (_isCapturing) return;

        _isCapturing = true;

        // Update "active" output
        var activeContact = getOutput("active");
        if (activeContact != null) {
            activeContact.value = true;
        }

        trace('AudioInputAtom: Started capture');

        // In a real implementation, initialize audio context here
        // _audioSource = initAudioContext();
    }

    /**
     * Stop audio capture.
     */
    public function stopCapture():Void {
        if (!_isCapturing) return;

        _isCapturing = false;

        // Update "active" output
        var activeContact = getOutput("active");
        if (activeContact != null) {
            activeContact.value = false;
        }

        trace('AudioInputAtom: Stopped capture');
    }

    /**
     * Generate test signal (sine wave).
     * Used when no microphone is available.
     *
     * @param dt Delta time in seconds
     */
    private function generateTestSignal(dt:Float):Void {
        // Calculate how many samples to generate
        var samplesToGenerate = Std.int(_sampleRate * dt);
        if (samplesToGenerate < 1) samplesToGenerate = 1;

        // Generate samples
        var samples:Array<Float> = [];

        for (i in 0...samplesToGenerate) {
            // Sine wave with some noise
            var t = _timeAccum + (i / _sampleRate);
            var sample = Math.sin(2.0 * Math.PI * _testFrequency * t) * 0.7;

            // Add slight noise
            sample += (Math.random() - 0.5) * 0.1;

            // Clamp
            if (sample > 1.0) sample = 1.0;
            if (sample < -1.0) sample = -1.0;

            samples.push(sample);

            // Store in internal buffer
            _internalBuffer[_writePos] = sample;
            _writePos = (_writePos + 1) % _bufferSize;
            if (_internalCollected < _bufferSize) _internalCollected++;
        }

        _timeAccum += samplesToGenerate / _sampleRate;
        _totalSamples += samplesToGenerate;

        // Output samples when buffer is full enough
        if (_internalCollected >= _bufferSize) {
            outputSamples();
        }
    }

    /**
     * Capture real audio from microphone.
     * Placeholder for real implementation.
     *
     * @param dt Delta time in seconds
     */
    private function captureRealAudio(dt:Float):Void {
        // Real implementation would:
        // 1. Read from _audioSource
        // 2. Process samples
        // 3. Call outputSamples()

        // For now, fall back to test signal
        generateTestSignal(dt);
    }

    /**
     * Output accumulated samples to contacts.
     */
    private function outputSamples():Void {
        // Copy internal buffer for output
        var outputBuffer:Array<Float> = [];

        // Read from oldest to newest
        var startIdx = (_writePos >= _bufferSize) ? _writePos : 0;

        for (i in 0..._bufferSize) {
            var idx = (startIdx + i) % _bufferSize;
            outputBuffer.push(_internalBuffer[idx]);
        }

        // Calculate peak and RMS
        var peak = 0.0;
        var sumSquares = 0.0;

        for (sample in outputBuffer) {
            var abs = Math.abs(sample);
            if (abs > peak) peak = abs;
            sumSquares += sample * sample;
        }

        var rms = Math.sqrt(sumSquares / outputBuffer.length);

        _lastPeak = peak;
        _lastRMS = rms;

        // Output to contacts
        var samplesContact = getOutput("samples");
        var peakContact = getOutput("peak");
        var rmsContact = getOutput("rms");

        if (samplesContact != null) {
            samplesContact.value = outputBuffer;
        }

        if (peakContact != null) {
            peakContact.value = peak;
        }

        if (rmsContact != null) {
            rmsContact.value = rms;
        }
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================

    /**
     * Get the sample rate.
     */
    public function getSampleRate():Int {
        return _sampleRate;
    }

    /**
     * Get the buffer size.
     */
    public function getBufferSize():Int {
        return _bufferSize;
    }

    /**
     * Get the channel count.
     */
    public function getChannelCount():Int {
        return _channelCount;
    }

    /**
     * Check if capture is active.
     */
    public function isCapturing():Bool {
        return _isCapturing;
    }

    /**
     * Get total samples captured.
     */
    public function getTotalSamples():Int {
        return _totalSamples;
    }

    /**
     * Get last peak level.
     */
    public function getLastPeak():Float {
        return _lastPeak;
    }

    /**
     * Get last RMS level.
     */
    public function getLastRMS():Float {
        return _lastRMS;
    }

    /**
     * Set test signal frequency.
     */
    public function setTestFrequency(freq:Float):Void {
        _testFrequency = freq;
    }

    /**
     * Enable or disable test signal mode.
     */
    public function setUseTestSignal(use:Bool):Void {
        _useTestSignal = use;
    }

    // =========================================================================
    // STATE SERIALIZATION (Databank Persistence)
    // =========================================================================

    /**
     * Get state for project saving.
     */
    override public function getPersistentState():Dynamic {
        return {
            sampleRate: _sampleRate,
            channelCount: _channelCount,
            bufferSize: _bufferSize,
            isCapturing: _isCapturing,
            totalSamples: _totalSamples,
            testFrequency: _testFrequency,
            useTestSignal: _useTestSignal
        };
    }

    /**
     * Restore state from saved data.
     */
    override public function restoreState(state:Dynamic):Void {
        if (state == null) return;

        if (state.sampleRate != null && Std.isOfType(state.sampleRate, Int)) {
            _sampleRate = state.sampleRate;
        }

        if (state.channelCount != null && Std.isOfType(state.channelCount, Int)) {
            _channelCount = state.channelCount;
        }

        if (state.bufferSize != null && Std.isOfType(state.bufferSize, Int)) {
            // Need to resize internal buffer
            _bufferSize = state.bufferSize;
            _internalBuffer = [];
            for (i in 0..._bufferSize) {
                _internalBuffer.push(0.0);
            }
            _writePos = 0;
            _internalCollected = 0;
        }

        if (state.totalSamples != null && Std.isOfType(state.totalSamples, Int)) {
            _totalSamples = state.totalSamples;
        }

        if (state.testFrequency != null && Std.isOfType(state.testFrequency, Float)) {
            _testFrequency = state.testFrequency;
        }

        if (state.useTestSignal != null && Std.isOfType(state.useTestSignal, Bool)) {
            _useTestSignal = state.useTestSignal;
        }

        // Restore capturing state
        if (state.isCapturing != null && Std.isOfType(state.isCapturing, Bool)) {
            if (state.isCapturing && !_isCapturing) {
                startCapture();
            } else if (!state.isCapturing && _isCapturing) {
                stopCapture();
            }
        }

        trace('AudioInputAtom: Restored state (sampleRate: $_sampleRate, capturing: $_isCapturing)');
    }

    // =========================================================================
    // DISPOSE
    // =========================================================================

    override public function dispose():Void {
        // Stop capture
        stopCapture();

        // Clear audio source
        _audioSource = null;

        // Clear buffers
        _internalBuffer = null;

        super.dispose();

        trace('AudioInputAtom: Disposed');
    }
}