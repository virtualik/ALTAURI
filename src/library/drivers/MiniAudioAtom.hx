package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;
#if cpp
@:headerCode('
// Путь относительно сгенерированного .cpp в bin/windows/obj/.../src/library/drivers/
// 4 уровня вверх до корня проекта, затем в /include
#include "../../../../include/miniaudio.h"
#include <math.h>
')
@:cppFileCode('
#define MINIAUDIO_IMPLEMENTATION
#include "../../../../include/miniaudio.h"

// ================================================
// C++ callback для miniaudio
// ================================================
// Глобальный callback для miniaudio
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
class MiniAudioAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================
    private static inline var MIN_QUANTUM:Float    = 0.001;
    private static inline var MAX_QUANTUM:Float    = 1.0;
    private static inline var PULSE_DURATION:Float = 0.05;
    private static inline var MODE_MIC:Int      = 0;
    private static inline var MODE_LOOPBACK:Int = 1;
    private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];
    
    // =========================================================================
    // MINIAUDIO СОСТОЯНИЕ
    // =========================================================================
    private var _device:cpp.RawPointer<cpp.Void>  = null;
    private var _context:cpp.RawPointer<cpp.Void> = null;
    private var _deviceReady:Bool = false;
    
    // =========================================================================
    // ПАРАМЕТРЫ
    // =========================================================================
    private var _mode:Int          = MODE_MIC;
    private var _quantum:Float     = 0.01;
    private var _gain:Float        = 1.0;
    private var _channel:Int       = 0;
    private var _sampleRateIdx:Int = 0;
    
    // =========================================================================
    // СОСТОЯНИЕ КВАНТОВАНИЯ
    // =========================================================================
    private var _lastQuantum:Float  = 0.0;
    private var _isFirstSample:Bool = true;
    
    // =========================================================================
    // RMS БУФЕР
    // =========================================================================
    private var _rmsBufferRaw:cpp.RawPointer<cpp.Void> = null;
    private var _rmsIndex:Int  = 0;
    private var _rmsSum:Float  = 0.0;
    
    // =========================================================================
    // PENDING-ПОЛЯ
    // =========================================================================
    @:volatile private var _hasPending:Bool     = false;
    @:volatile private var _pendingSample:Float  = 0.0;
    @:volatile private var _pendingRms:Float     = 0.0;
    @:volatile private var _pendingClip:Bool     = false;
    @:volatile private var _pendingChanged:Bool  = false;
    
    // =========================================================================
    // PULSE ТАЙМЕРЫ
    // =========================================================================
    private var _changedTimer:Float = 0.0;
    private var _tickTimer:Float    = 0.0;
    private var _clipTimer:Float    = 0.0;
    
    // =========================================================================
    // КОНСТРУКТОР
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(MODE_MIC, INPUT, "mode"),
                new Contact(0.01, INPUT, "quantum"),
                new Contact(1.0, INPUT, "gain"),
                new Contact(0, INPUT, "channel"),
                new Contact(0, INPUT, "rate")
            ],
            [
                new Contact(0.0, OUTPUT, "sample"),
                new Contact(false, OUTPUT, "changed"),
                new Contact(0.0, OUTPUT, "rms"),
                new Contact(false, OUTPUT, "clip"),
                new Contact(false, OUTPUT, "tick"),
                new Contact(0.0, OUTPUT, "level"),
                new Contact("", OUTPUT, "device")
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
    // ОТКРЫТИЕ УСТРОЙСТВА
    // =========================================================================
    private function openDevice():Void
    {
        var sampleRate : Int = SAMPLE_RATES[_sampleRateIdx];
        var deviceType : Int = (_mode == MODE_LOOPBACK) ? 2 : 1;
        
        untyped __cpp__('
            printf("MiniAudioAtom: === STARTING AUDIO DEVICE ===\\n");
            printf("MiniAudioAtom: DeviceType=%d (1=Capture, 2=Loopback)\\n", {2});
            printf("MiniAudioAtom: SampleRate=%d\\n", {3});
            
            // Выделяем RMS буфер
            {0}->_rmsBufferRaw = calloc(1024, sizeof(float));
            if (!{0}->_rmsBufferRaw) {
                printf("MiniAudioAtom: FAILED to allocate RMS buffer\\n");
                return;
            }
            printf("MiniAudioAtom: RMS buffer allocated\\n");
            
            // Создаем context и device
            ma_context* ctx = (ma_context*)malloc(sizeof(ma_context));
            ma_device*  dev = (ma_device*)malloc(sizeof(ma_device));
            
            if (!ctx || !dev) {
                printf("MiniAudioAtom: malloc FAILED\\n");
                return;
            }
            printf("MiniAudioAtom: Memory allocated\\n");
            
            // === ИСПРАВЛЕНИЕ: Простая инициализация без WASAPI специфик ===
            // MiniAudio сам выберет лучший бэкенд
            ma_result result = ma_context_init(NULL, 0, NULL, ctx);
            if (result != MA_SUCCESS) {
                printf("MiniAudioAtom: ma_context_init FAILED: %d\\n", result);
                free(ctx); free(dev);
                return;
            }
            printf("MiniAudioAtom: ma_context_init SUCCESS\\n");
            
            {0}->_context = ctx;
            
            // Настраиваем device
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
    // ЗАКРЫТИЕ УСТРОЙСТВА
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
    // PULSE ТАЙМЕРЫ
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
    // ЧТЕНИЕ ВХОДОВ
    // =========================================================================
    private function readInputs():Void
    {
        var modeC    = getInput("mode");
        var quantumC = getInput("quantum");
        var gainC    = getInput("gain");
        var channelC = getInput("channel");
        var rateC    = getInput("rate");
        
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
    }
    
    // =========================================================================
    // УТИЛИТЫ
    // =========================================================================
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
        openDevice();
    }
}
#end