#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>
')
@:cppFileCode('
#define MINIAUDIO_IMPLEMENTATION
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>

// Double buffer structure
struct DoubleBuffer {
    float buffers[2][4096 * 2];  // Two buffers
    std::atomic<int> writeIndex;  // 0 or 1 - which buffer C++ is writing to
    std::atomic<int> readyIndex;  // -1 or 0 or 1 - which buffer is ready for Haxe
    std::atomic<int> samplesWritten;  // How many samples written to current buffer
    int targetSize;  // Buffer size target
    
    DoubleBuffer() : writeIndex(0), readyIndex(-1), samplesWritten(0), targetSize(256) {
        memset(buffers, 0, sizeof(buffers));
    }
};

static void _altauri_audio_cb_double(
    ma_device*  pDevice,
    void*       pOutput,
    const void* pInput,
    ma_uint32   frameCount)
{
    ::library::drivers::MiniAudioAtom_obj* self =
        (::library::drivers::MiniAudioAtom_obj*)(pDevice->pUserData);
    
    if (!self || (bool)self->_isDisposed) return;
    
    DoubleBuffer* db = (DoubleBuffer*)self->_doubleBufferRaw;
    if (!db) return;
    
    const float* samples = (const float*)pInput;
    if (!samples) return;
    
    float gain = (float)self->_gain;
    int channel = (int)self->_channel;
    float quantum = (float)self->_quantum;
    
    float rmsAccum = 0.0f;
    bool clip = false;
    float lastSample = 0.0f;
    
    int writeIdx = db->writeIndex.load(std::memory_order_relaxed);
    float* buffer = db->buffers[writeIdx];
    int accum = db->samplesWritten.load(std::memory_order_relaxed);
    int targetSize = db->targetSize;
    
    for (ma_uint32 i = 0; i < frameCount; i++)
    {
        float left  = samples[i * 2]     * gain;
        float right = samples[i * 2 + 1] * gain;
        
        float mono = 0.0f;
        if (channel == 0) mono = (left + right) * 0.5f;
        else if (channel == 1) mono = left;
        else if (channel == 2) mono = right;
        
        if (mono >  1.0f) { mono =  1.0f; clip = true; }
        if (mono < -1.0f) { mono = -1.0f; clip = true; }
        
        rmsAccum += mono * mono;
        lastSample = mono;
        
        // Write ONLY if we havent reached target
        if (accum < targetSize) {
            int bufIdx = accum * 2;
            buffer[bufIdx]     = left;
            buffer[bufIdx + 1] = right;
            accum++;
        }
    }
    
    db->samplesWritten.store(accum, std::memory_order_relaxed);
    
    // If buffer is full, mark as ready and switch
    if (accum >= targetSize) {
        db->readyIndex.store(writeIdx, std::memory_order_release);
        int nextIdx = 1 - writeIdx;
        db->writeIndex.store(nextIdx, std::memory_order_release);
        db->samplesWritten.store(0, std::memory_order_relaxed);
    }
    
    float rms = sqrtf(rmsAccum / (float)frameCount);
    float quantized = roundf(lastSample / quantum) * quantum;
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

extern "C" int _scope_get_ready_index(void* raw) {
    if (!raw) return -1;
    return ((DoubleBuffer*)raw)->readyIndex.load(std::memory_order_acquire);
}

extern "C" void* _scope_get_buffer_ptr(void* raw, int index) {
    if (!raw || index < 0 || index > 1) return nullptr;
    return (void*)((DoubleBuffer*)raw)->buffers[index];
}

extern "C" void _scope_clear_ready(void* raw) {
    if (!raw) return;
    ((DoubleBuffer*)raw)->readyIndex.store(-1, std::memory_order_release);
}
')

class MiniAudioAtom extends Atom implements system.managers.Driver
{
    private static inline var MIN_QUANTUM:Float    = 0.001;
    private static inline var MAX_QUANTUM:Float    = 1.0;
    private static inline var PULSE_DURATION:Float = 0.05;
    
    private static inline var MODE_MIC:Int      = 0;
    private static inline var MODE_LOOPBACK:Int = 1;
    
    private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];
    
    private var _device:cpp.RawPointer<cpp.Void>  = null;
    private var _context:cpp.RawPointer<cpp.Void> = null;
    private var _deviceReady:Bool = false;
    
    private var _mode:Int          = MODE_LOOPBACK;
    private var _quantum:Float     = 0.01;
    private var _gain:Float        = 1.0;
    private var _channel:Int       = 0;
    private var _sampleRateIdx:Int = 0;
    
    private var _lastQuantum:Float  = 0.0;
    private var _isFirstSample:Bool = true;
    
    @:volatile private var _doubleBufferRaw:cpp.RawPointer<cpp.Void> = null;
    
    @:volatile private var _hasPending:Bool     = false;
    @:volatile private var _pendingSample:Float  = 0.0;
    @:volatile private var _pendingRms:Float     = 0.0;
    @:volatile private var _pendingClip:Bool     = false;
    @:volatile private var _pendingChanged:Bool  = false;
    
    private var _changedTimer:Float = 0.0;
    private var _tickTimer:Float    = 0.0;
    private var _clipTimer:Float    = 0.0;
    
    private var _bufferSize:Int = 256;
    
    // Zero-GC Ping-Pong Buffers
    private var _bufA:Array<Float>;
    private var _bufLA:Array<Float>;
    private var _bufRA:Array<Float>;
    
    private var _bufB:Array<Float>;
    private var _bufLB:Array<Float>;
    private var _bufRB:Array<Float>;
    
    private var _activeBuf:Int = 0;
    
    public function new(id:String)
    {
        super(
            [
                new Contact(MODE_LOOPBACK, INPUT, "mode"),
                new Contact(0.01, INPUT, "quantum"),
                new Contact(50.0, INPUT, "gain"),
                new Contact(0, INPUT, "channel"),
                new Contact(0, INPUT, "rate"),
                new Contact(256, INPUT, "bufferSize")
            ],
            [
                new Contact(0.0, OUTPUT, "sample"),
                new Contact(false, OUTPUT, "changed"),
                new Contact(0.0, OUTPUT, "rms"),
                new Contact(false, OUTPUT, "clip"),
                new Contact(false, OUTPUT, "tick"),
                new Contact(0.0, OUTPUT, "level"),
                new Contact("", OUTPUT, "device"),
                new Contact(null, OUTPUT, "buffer"),
                new Contact(null, OUTPUT, "bufferL"),
                new Contact(null, OUTPUT, "bufferR")
            ],
            null,
            id,
            "MiniAudioAtom",
            true
        );
        
        var sampleOut = getOutput("sample");
        if (sampleOut != null) sampleOut.ignoreOscillation = true;
        
        init();
    }
    
    override public function init():Void
    {
        // Pre-allocate Zero-GC Ping-Pong Buffers
        _bufA = new Array<Float>(); _bufLA = new Array<Float>(); _bufRA = new Array<Float>();
        _bufB = new Array<Float>(); _bufLB = new Array<Float>(); _bufRB = new Array<Float>();
        for (i in 0...4096) {
            _bufA.push(0.0); _bufLA.push(0.0); _bufRA.push(0.0);
            _bufB.push(0.0); _bufLB.push(0.0); _bufRB.push(0.0);
        }
        
        readInputs();
        openDevice();
    }
    
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        
        // Check double buffer for ready data
        checkDoubleBuffer();
        
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
                var db = snapRms > 0.0001 ? 20.0 * Math.log(snapRms) / Math.log(10) : -120.0;
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
        
        updatePulseTimers(dt);
        readInputs();
    }
    
    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }
    
    private function checkDoubleBuffer():Void
    {
        if (_doubleBufferRaw == null) return;
        
        var readyIndex:Int = -1;
        untyped __cpp__('{0} = ::_scope_get_ready_index({1});', readyIndex, _doubleBufferRaw);
        
        if (readyIndex >= 0)
        {
            propagateScopeBuffer(readyIndex);
            untyped __cpp__('::_scope_clear_ready({0});', _doubleBufferRaw);
        }
    }
    
    private function openDevice():Void
    {
        var sampleRate : Int = SAMPLE_RATES[_sampleRateIdx];
        var deviceType : Int = (_mode == MODE_LOOPBACK) ? 2 : 1;
        
        untyped __cpp__('
            DoubleBuffer* db = new DoubleBuffer();
            db->targetSize = {2};
            {0}->_doubleBufferRaw = (void*)db;
            
            ma_context* ctx = (ma_context*)malloc(sizeof(ma_context));
            ma_device*  dev = (ma_device*)malloc(sizeof(ma_device));
            
            if (!ctx || !dev) {
                delete db;
                {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            ma_result result = ma_context_init(NULL, 0, NULL, ctx);
            if (result != MA_SUCCESS) { 
                free(ctx); free(dev); delete db;
                {0}->_doubleBufferRaw = nullptr;
                return; 
            }
            
            {0}->_context = ctx;
            
            ma_device_config cfg = ma_device_config_init(
                {1} == 2 ? ma_device_type_loopback : ma_device_type_capture
            );
            cfg.sampleRate         = (ma_uint32){3};
            cfg.periodSizeInFrames = 256;
            cfg.capture.format     = ma_format_f32;
            cfg.capture.channels   = 2;
            cfg.dataCallback       = _altauri_audio_cb_double;
            cfg.pUserData          = (void*)({0}.mPtr);
            
            result = ma_device_init(ctx, &cfg, dev);
            if (result != MA_SUCCESS) {
                ma_context_uninit(ctx);
                free(ctx); free(dev); delete db;
                {0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            {0}->_device = dev;
            
            result = ma_device_start(dev);
            if (result != MA_SUCCESS) {
                ma_device_uninit(dev); ma_context_uninit(ctx);
                free(dev); free(ctx); delete db;
                {0}->_device = NULL; {0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            {0}->_deviceReady = true;
        ', this, deviceType, _bufferSize, sampleRate);
        
        if (_deviceReady) 
            setDeviceNameOutput((_mode == MODE_LOOPBACK) ? "Loopback @" + sampleRate + "Hz" : "Capture @" + sampleRate + "Hz");
        else 
            setDeviceNameOutput("ERROR: device init failed");
    }
    
    private function closeDevice():Void
    {
        if (!_deviceReady) return;
        _deviceReady = false;
        
        untyped __cpp__('
            ma_device*  dev = (ma_device*) {0}->_device;
            ma_context* ctx = (ma_context*){0}->_context;
            DoubleBuffer* db = (DoubleBuffer*){0}->_doubleBufferRaw;
            
            if (dev) { ma_device_stop(dev); ma_device_uninit(dev); free(dev); }
            if (ctx) { ma_context_uninit(ctx); free(ctx); }
            if (db)  { delete db; }
            
            {0}->_device = nullptr;
            {0}->_context = nullptr;
            {0}->_doubleBufferRaw = nullptr;
        ', this);
    }
    
    private function propagateScopeBuffer(readyIndex:Int):Void
    {
        if (_doubleBufferRaw == null) return;
        
        // Select inactive buffers (Ping-Pong)
        var targetBuf:Array<Float>;
        var targetBufL:Array<Float>;
        var targetBufR:Array<Float>;
        
        if (_activeBuf == 0) {
            targetBuf = _bufB; targetBufL = _bufLB; targetBufR = _bufRB;
            _activeBuf = 1;
        } else {
            targetBuf = _bufA; targetBufL = _bufLA; targetBufR = _bufRA;
            _activeBuf = 0;
        }
        
        // Get C++ raw pointer
        var rawPtr:cpp.RawPointer<cpp.Void> = untyped __cpp__('(void*)::_scope_get_buffer_ptr({0}, {1})', _doubleBufferRaw, readyIndex);
        var ptr:cpp.Pointer<cpp.Float32> = untyped __cpp__('(cpp::Float32*){0}', rawPtr);
        
        // Copy data
        if (ptr != null) {
            var count = _bufferSize;
            for (i in 0...count) {
                var idx = i * 2;
                var l:Float = ptr[idx];
                var r:Float = ptr[idx + 1];
                targetBuf[i] = (l + r) * 0.5;
                targetBufL[i] = l;
                targetBufR[i] = r;
            }
        }
        
        // Propagate
        var bufOut  = getOutput("buffer");
        var bufLOut = getOutput("bufferL");
        var bufROut = getOutput("bufferR");
        
        if (bufOut  != null) { bufOut.setValueSilent(targetBuf);  bufOut.propagateCurrentValue(); }
        if (bufLOut != null) { bufLOut.setValueSilent(targetBufL); bufLOut.propagateCurrentValue(); }
        if (bufROut != null) { bufROut.setValueSilent(targetBufR); bufROut.propagateCurrentValue(); }
    }
    
    private function updatePulseTimers(dt:Float):Void
    {
        if (_tickTimer > 0) { _tickTimer -= dt; if (_tickTimer <= 0) { var c = getOutput("tick"); if (c != null) c.value = false; } }
        if (_changedTimer > 0) { _changedTimer -= dt; if (_changedTimer <= 0) { var c = getOutput("changed"); if (c != null) c.value = false; } }
        if (_clipTimer > 0) { _clipTimer -= dt; if (_clipTimer <= 0) { var c = getOutput("clip"); if (c != null) c.value = false; } }
    }
    
    private function readInputs():Void
    {
        var modeC    = getInput("mode");
        var quantumC = getInput("quantum");
        var gainC    = getInput("gain");
        var channelC = getInput("channel");
        var rateC    = getInput("rate");
        var bufSizeC = getInput("bufferSize");
        
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
        
        if (bufSizeC != null && bufSizeC.value != null)
        {
            var bs = Std.int(bufSizeC.value);
            if (bs >= 64 && bs <= 4096 && bs != _bufferSize) _bufferSize = bs;
        }
    }
    
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
        _hasPending    = false;
        readInputs();
        openDevice();
    }
}
#end