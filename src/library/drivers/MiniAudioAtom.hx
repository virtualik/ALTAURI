#if cpp
package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// Path relative to generated .cpp in bin/windows/obj/.../src/library/drivers/
// 4 levels up to project root, then /include
#include "../../../../include/miniaudio.h"
#include <math.h>
')
@:cppFileCode('
#define MINIAUDIO_IMPLEMENTATION
#include "../../../../include/miniaudio.h"
#include <math.h>

// ================================================
// C++ callback for miniaudio
// ================================================
static void _altauri_audio_cb(
ma_device*  pDevice,
void*       pOutput,
const void* pInput,
ma_uint32   frameCount)
{
::library::drivers::MiniAudioAtom_obj* self =
(::library::drivers::MiniAudioAtom_obj*)(pDevice->pUserData);

if (!self || (bool)self->_isDisposed) return;

const float* samples = (const float*)pInput;
if (!samples) return;

float bufferSample = 0.0f;
float rmsAccum     = 0.0f;
bool  clip         = false;

for (ma_uint32 i = 0; i < frameCount; i++)
{
float left  = samples[i * 2]     * (float)self->_gain;
float right = samples[i * 2 + 1] * (float)self->_gain;

float mono = (left + right) * 0.5f;
if ((int)self->_channel == 1) mono = left;
else if ((int)self->_channel == 2) mono = right;

if (mono >  1.0f) { mono =  1.0f; clip = true; }
if (mono < -1.0f) { mono = -1.0f; clip = true; }

rmsAccum    += mono * mono;
bufferSample = mono;

// v2.0: Accumulate samples for oscilloscope buffer
// Store stereo pair even if mono is selected
int bufIdx = (int)self->_scopeWriteIndex;
if (bufIdx >= 0 && bufIdx < 4096) {
::Array< ::Dynamic > ringBuf = (::Array< ::Dynamic >)self->_scopeRingBuffer;
if (ringBuf != nullptr && bufIdx < ringBuf->length) {
::Dynamic sample = ringBuf->__get(bufIdx);
if (sample != nullptr) {
// Correct hxcpp way to set fields on a Dynamic object
sample->__SetField("l", left, hx::paccDynamic);
sample->__SetField("r", right, hx::paccDynamic);
}
}
}

self->_scopeWriteIndex = (bufIdx + 1) % 4096;
self->_scopeSamplesAccum++;

if ((int)self->_scopeSamplesAccum >= (int)self->_bufferSize) {
self->_scopeBufferReady = true;
}
}

float* rmsBuffer = (float*)self->_rmsBufferRaw;
if (rmsBuffer)
{
float bufferMean = rmsAccum / (float)frameCount;
int   rmsIdx     = (int)self->_rmsIndex;
self->_rmsSum -= rmsBuffer[rmsIdx];
rmsBuffer[rmsIdx] = bufferMean;
self->_rmsSum += bufferMean;
self->_rmsIndex = (rmsIdx + 1) % 1024;
}

float rms = sqrtf((float)self->_rmsSum / 1024.0f);

float quantum   = (float)self->_quantum;
float quantized = roundf(bufferSample / quantum) * quantum;

if (quantized >  1.0f) quantized =  1.0f;
if (quantized < -1.0f) quantized = -1.0f;

bool changed = (!(bool)self->_isFirstSample) &&
(quantized != (float)self->_lastQuantum);

self->_pendingSample  = quantized;
self->_pendingRms     = rms;
self->_pendingClip    = clip;
self->_pendingChanged = changed;
self->_lastQuantum    = quantized;
self->_isFirstSample  = false;
self->_hasPending     = true;
}
')
/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     MINI AUDIO ATOM v2.0                                  ║
* ║                     (Audio Capture Driver with Buffer Output)             ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v2.0 Changes:                                                            ║
* ║  - ADDED: Output contacts "buffer", "bufferL", "bufferR" (Array<Float>)   ║
* ║  - ADDED: Input contact "bufferSize" (Int, default 256)                   ║
* ║  - ADDED: Stereo ring buffer (4096 samples) for oscilloscope              ║
* ║  - Audio callback now writes to ring buffer every frame                   ║
* ║  - propagateScopeBuffer() copies buffer to Haxe Arrays and emits          ║
* ║                                                                           ║
* ║  Architecture:                                                            ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Audio Thread (C++) ──► Ring Buffer ──► Main Thread (Haxe)          │  ║
* ║  │                                                                     │  ║
* ║  │  propagateScopeBuffer():                                            │  ║
* ║  │    1. Copy last _bufferSize samples from ring buffer                │  ║
* ║  │    2. Create 3 Haxe Arrays: mono, left, right                       │  ║
* ║  │    3. setValueSilent() + propagateCurrentValue() for each output    │  ║
* ║  │    4. Reset _scopeSamplesAccum counter                              │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class MiniAudioAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var MIN_QUANTUM:Float    = 0.001;
    private static inline var MAX_QUANTUM:Float    = 1.0;
    private static inline var PULSE_DURATION:Float = 0.05;
    private static inline var MODE_MIC:Int      = 0;
    private static inline var MODE_LOOPBACK:Int = 1;
    private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];

    // =========================================================================
    // MINIAUDIO STATE
    // =========================================================================
    private var _device:cpp.RawPointer<cpp.Void>  = null;
    private var _context:cpp.RawPointer<cpp.Void> = null;
    private var _deviceReady:Bool = false;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    private var _mode:Int          = MODE_LOOPBACK;
    private var _quantum:Float     = 0.01;
    private var _gain:Float        = 1.0;
    private var _channel:Int       = 0;
    private var _sampleRateIdx:Int = 0;

    // =========================================================================
    // QUANTIZATION STATE
    // =========================================================================
    private var _lastQuantum:Float  = 0.0;
    private var _isFirstSample:Bool = true;

    // =========================================================================
    // RMS BUFFER
    // =========================================================================
    private var _rmsBufferRaw:cpp.RawPointer<cpp.Void> = null;
    private var _rmsIndex:Int  = 0;
    private var _rmsSum:Float  = 0.0;

    // =========================================================================
    // PENDING FIELDS
    // =========================================================================
    @:volatile private var _hasPending:Bool     = false;
    @:volatile private var _pendingSample:Float  = 0.0;
    @:volatile private var _pendingRms:Float     = 0.0;
    @:volatile private var _pendingClip:Bool     = false;
    @:volatile private var _pendingChanged:Bool  = false;

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private var _changedTimer:Float = 0.0;
    private var _tickTimer:Float    = 0.0;
    private var _clipTimer:Float    = 0.0;

    // =========================================================================
    // v2.0: SCOPE BUFFER STATE
    // =========================================================================
    /** Ring buffer for oscilloscope output (stereo) */
    private var _scopeRingBuffer:Array<{l:Float, r:Float}>;
    /** Current write position in ring buffer */
    private var _scopeWriteIndex:Int = 0;
    /** Number of samples accumulated since last flush */
    private var _scopeSamplesAccum:Int = 0;
    /** Buffer size for oscilloscope output (configurable) */
    private var _bufferSize:Int = 256;
    /** Flag: buffer ready to send to Haxe */
    @:volatile private var _scopeBufferReady:Bool = false;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(MODE_LOOPBACK, INPUT, "mode"),
                new Contact(0.01, INPUT, "quantum"),
                new Contact(50.0, INPUT, "gain"),
                new Contact(0, INPUT, "channel"),
                new Contact(0, INPUT, "rate"),
                new Contact(256, INPUT, "bufferSize")  // v2.0: NEW
            ],
            [
                new Contact(0.0, OUTPUT, "sample"),
                new Contact(false, OUTPUT, "changed"),
                new Contact(0.0, OUTPUT, "rms"),
                new Contact(false, OUTPUT, "clip"),
                new Contact(false, OUTPUT, "tick"),
                new Contact(0.0, OUTPUT, "level"),
                new Contact("", OUTPUT, "device"),
                new Contact(null, OUTPUT, "buffer"),   // v2.0: NEW (mono)
                new Contact(null, OUTPUT, "bufferL"),  // v2.0: NEW (left)
                new Contact(null, OUTPUT, "bufferR")   // v2.0: NEW (right)
            ],
            null,
            id,
            "MiniAudioAtom",
            true
        );

        var sampleOut = getOutput("sample");
        if (sampleOut != null) sampleOut.ignoreOscillation = true;

        // v2.0: Initialize scope ring buffer
        _scopeRingBuffer = [];
        for (i in 0...4096) _scopeRingBuffer.push({l: 0.0, r: 0.0});

        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        readInputs();
        openDevice();
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        if (_hasPending)
        {
            _hasPending = false;

            var snapSample  = _pendingSample;
            var snapRms     = _pendingRms;
            var snapClip    = _pendingClip;
            var snapChanged = _pendingChanged;

            var sampleOut = getOutput("sample");
            var rmsOut    = getOutput("rms");
            var levelOut  = getOutput("level");

            if (sampleOut != null) sampleOut.setValueSilent(snapSample);
            if (rmsOut    != null) rmsOut.setValueSilent(snapRms);

            if (levelOut != null)
            {
                var db = snapRms > 0.0001
                    ? 20.0 * Math.log(snapRms) / Math.log(10)
                    : -120.0;
                levelOut.setValueSilent(db);
            }

            var tickOut = getOutput("tick");
            if (tickOut != null) { tickOut.value = true; _tickTimer = PULSE_DURATION; }

            if (snapChanged)
            {
                var c = getOutput("changed");
                if (c != null) { c.value = true; _changedTimer = PULSE_DURATION; }
            }

            if (snapClip)
            {
                var c = getOutput("clip");
                if (c != null) { c.value = true; _clipTimer = PULSE_DURATION; }
            }

            if (sampleOut != null) sampleOut.propagateCurrentValue();
            if (rmsOut    != null) rmsOut.propagateCurrentValue();
            if (levelOut  != null) levelOut.propagateCurrentValue();
        }

	    // === v2.0: Process scope buffer ===
		if (_scopeBufferReady)
		{
			//trace('🔍 MiniAudioAtom: _scopeBufferReady = true, calling propagateScopeBuffer()');
			_scopeBufferReady = false;
			propagateScopeBuffer();
		}
		
        // v2.0: Process scope buffer
        if (_scopeBufferReady)
        {
            _scopeBufferReady = false;
            propagateScopeBuffer();
        }

        readInputs();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // DEVICE OPENING
    // =========================================================================
    private function openDevice():Void
    {
        var sampleRate : Int = SAMPLE_RATES[_sampleRateIdx];
        var deviceType : Int = (_mode == MODE_LOOPBACK) ? 2 : 1;

        untyped __cpp__('
            printf("MiniAudioAtom: === STARTING AUDIO DEVICE ===\\n");
            printf("MiniAudioAtom: DeviceType=%d (1=Capture, 2=Loopback)\\n", {2});
            printf("MiniAudioAtom: SampleRate=%d\\n", {3});

            // Allocate RMS buffer
            {0}->_rmsBufferRaw = calloc(1024, sizeof(float));
            if (!{0}->_rmsBufferRaw) {
                printf("MiniAudioAtom: FAILED to allocate RMS buffer\\n");
                return;
            }
            printf("MiniAudioAtom: RMS buffer allocated\\n");

            // Create context and device
            ma_context* ctx = (ma_context*)malloc(sizeof(ma_context));
            ma_device*  dev = (ma_device*)malloc(sizeof(ma_device));
            if (!ctx || !dev) {
                printf("MiniAudioAtom: malloc FAILED\\n");
                return;
            }
            printf("MiniAudioAtom: Memory allocated\\n");

            // === FIX: Simple initialization without WASAPI specifics ===
            // MiniAudio will choose the best backend automatically
            ma_result result = ma_context_init(NULL, 0, NULL, ctx);
            if (result != MA_SUCCESS) {
                printf("MiniAudioAtom: ma_context_init FAILED: %d\\n", result);
                free(ctx); free(dev);
                return;
            }
            printf("MiniAudioAtom: ma_context_init SUCCESS\\n");
            {0}->_context = ctx;

            // Configure device
            ma_device_config cfg = ma_device_config_init(
                {2} == 2 ? ma_device_type_loopback : ma_device_type_capture
            );
            cfg.sampleRate         = (ma_uint32){3};
            cfg.periodSizeInFrames = 256;
            cfg.capture.format     = ma_format_f32;
            cfg.capture.channels   = 2;
            cfg.dataCallback       = _altauri_audio_cb;
            cfg.pUserData          = (void*)({0}.mPtr);

            printf("MiniAudioAtom: ma_device_init...\\n");
            result = ma_device_init(ctx, &cfg, dev);
            if (result != MA_SUCCESS) {
                printf("MiniAudioAtom: ma_device_init FAILED: %d\\n", result);
                printf(">>> TIP: Loopback may not be supported on this system\\n");
                printf(">>> Try Mode=0 (Microphone) instead\\n");
                ma_context_uninit(ctx);
                free(ctx); free(dev);
                {0}->_context = NULL;
                return;
            }
            printf("MiniAudioAtom: ma_device_init SUCCESS\\n");
            {0}->_device = dev;

            printf("MiniAudioAtom: ma_device_start...\\n");
            result = ma_device_start(dev);
            if (result != MA_SUCCESS) {
                printf("MiniAudioAtom: ma_device_start FAILED: %d\\n", result);
                ma_device_uninit(dev);
                ma_context_uninit(ctx);
                free(dev); free(ctx);
                {0}->_device = NULL;
                {0}->_context = NULL;
                return;
            }
            printf("MiniAudioAtom: SUCCESS - AUDIO DEVICE IS RUNNING!\\n");
            printf("MiniAudioAtom: Mode=%s\\n", {2} == 2 ? "LOOPBACK" : "MICROPHONE");
            {0}->_deviceReady = true;
        ', this, deviceType, deviceType, sampleRate);

        if (_deviceReady)
        {
            setDeviceNameOutput((_mode == MODE_LOOPBACK) ? "Loopback @" + sampleRate + "Hz" : "Capture @" + sampleRate + "Hz");
        }
        else
        {
            setDeviceNameOutput("ERROR: device init failed");
        }
    }

    // =========================================================================
    // DEVICE CLOSING
    // =========================================================================
    private function closeDevice():Void
    {
        if (!_deviceReady) return;
        _deviceReady = false;

        untyped __cpp__('
            ma_device*  dev = (ma_device*) {0}->_device;
            ma_context* ctx = (ma_context*){0}->_context;

            if (dev) {
                ma_device_stop(dev);
                ma_device_uninit(dev);
                free(dev);
            }
            if (ctx) {
                ma_context_uninit(ctx);
                free(ctx);
            }
            if ({0}->_rmsBufferRaw) {
                free({0}->_rmsBufferRaw);
            }

            {0}->_device      = nullptr;
            {0}->_context     = nullptr;
            {0}->_rmsBufferRaw = nullptr;
        ', this);
    }

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private function updatePulseTimers(dt:Float):Void
    {
        if (_tickTimer > 0)
        {
            _tickTimer -= dt;
            if (_tickTimer <= 0) { var c = getOutput("tick");    if (c != null) c.value = false; }
        }
        if (_changedTimer > 0)
        {
            _changedTimer -= dt;
            if (_changedTimer <= 0) { var c = getOutput("changed"); if (c != null) c.value = false; }
        }
        if (_clipTimer > 0)
        {
            _clipTimer -= dt;
            if (_clipTimer <= 0) { var c = getOutput("clip");    if (c != null) c.value = false; }
        }
    }

    // =========================================================================
    // INPUT READING
    // =========================================================================
    private function readInputs():Void
    {
        var modeC    = getInput("mode");
        var quantumC = getInput("quantum");
        var gainC    = getInput("gain");
        var channelC = getInput("channel");
        var rateC    = getInput("rate");
        var bufSizeC = getInput("bufferSize");  // v2.0: NEW

        if (modeC    != null && modeC.value    != null) _mode    = Std.int(modeC.value);
        if (gainC    != null && gainC.value    != null) _gain    = gainC.value;
        if (channelC != null && channelC.value != null) _channel = Std.int(channelC.value);

        if (rateC != null && rateC.value != null)
        {
            var idx = Std.int(rateC.value);
            if (idx >= 0 && idx < SAMPLE_RATES.length) _sampleRateIdx = idx;
        }

        if (quantumC != null && quantumC.value != null)
        {
            var q:Float = quantumC.value;
            if (q >= MIN_QUANTUM && q <= MAX_QUANTUM) _quantum = q;
        }

        // v2.0: Update buffer size
        if (bufSizeC != null && bufSizeC.value != null)
        {
            var bs = Std.int(bufSizeC.value);
            if (bs >= 64 && bs <= 4096 && bs != _bufferSize)
            {
                _bufferSize = bs;
               // trace('MiniAudioAtom: bufferSize changed to $_bufferSize');
            }
        }
    }

    // =========================================================================
    // v2.0: SCOPE BUFFER PROPAGATION
    // =========================================================================
    /**
    * Copy ring buffer to Haxe Arrays and emit via contacts.
    * 
    * Process:
    * 1. Calculate start position (go back _bufferSize samples)
    * 2. Copy samples to 3 Haxe Arrays: mono, left, right
    * 3. setValueSilent() + propagateCurrentValue() for each output
    * 4. Reset _scopeSamplesAccum counter
    */
    private function propagateScopeBuffer():Void
    {
		//trace('🔍 [1] MiniAudioAtom: propagateScopeBuffer() STARTED');
		
        var buffer:Array<Float>  = [];
        var bufferL:Array<Float> = [];
        var bufferR:Array<Float> = [];

        // Calculate start position (go back _bufferSize samples)
        var startIdx = _scopeWriteIndex - _bufferSize;
        if (startIdx < 0) startIdx += 4096;

        for (i in 0..._bufferSize)
        {
            var idx = (startIdx + i) % 4096;
            if (idx >= 0 && idx < _scopeRingBuffer.length)
            {
                var sample = _scopeRingBuffer[idx];
                if (sample != null)
                {
                    var mono = (sample.l + sample.r) * 0.5;
                    buffer.push(mono);
                    bufferL.push(sample.l);
                    bufferR.push(sample.r);
                }
                else
                {
                    buffer.push(0.0);
                    bufferL.push(0.0);
                    bufferR.push(0.0);
                }
            }
        }
		
		//trace('🔍 [2] MiniAudioAtom: propagateScopeBuffer() STARTED');
        
		// Write to contacts
        var bufOut  = getOutput("buffer");
        var bufLOut = getOutput("bufferL");
        var bufROut = getOutput("bufferR");

        if (bufOut  != null) { bufOut.setValueSilent(buffer);  bufOut.propagateCurrentValue();  }
        if (bufLOut != null) { bufLOut.setValueSilent(bufferL); bufLOut.propagateCurrentValue(); }
        if (bufROut != null) { bufROut.setValueSilent(bufferR); bufROut.propagateCurrentValue(); }

        // Reset accumulator
        _scopeSamplesAccum = 0;
    }

    // =========================================================================
    // UTILITIES
    // =========================================================================
    /**
    * Set the device name output contact.
    */
    private function setDeviceNameOutput(name:String):Void
    {
        var c = getOutput("device");
        if (c != null) c.value = name;
    }

    public function restart():Void
    {
        closeDevice();
        _isFirstSample = true;
        _lastQuantum   = 0.0;
        _rmsSum        = 0.0;
        _rmsIndex      = 0;
        _hasPending    = false;

        // v2.0: Reset scope buffer
        _scopeWriteIndex = 0;
        _scopeSamplesAccum = 0;
        _scopeBufferReady = false;

        readInputs();
        openDevice();
       //trace("restart() called");
    }
}
#end