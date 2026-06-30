package library.drivers;

#if cpp
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// ЗАГОЛОВОК (HEADER)
// ============================================================================
// ВНИМАНИЕ: Намеренно пусто! 
// Мы НЕ включаем Windows.h и WASAPI заголовки сюда, чтобы их макросы 
// (ERROR, interface, min, max) не утекли в __boot__.cpp и не сломали Lime/OpenAL.
@:headerCode('
')

// ============================================================================
// C++ РЕАЛИЗАЦИЯ (CPP FILE CODE)
// ============================================================================
@:cppFileCode('
// Защита от агрессивных макросов Windows
#define WIN32_LEAN_AND_MEAN
#define WIN32_NO_STATUS
#define NOMINMAX
#pragma comment(lib, "ole32.lib")
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <string>
#include <mutex>
#include <map>

// ============================================================================
// C++ STATE STRUCT — хранит WASAPI объекты для каждого Haxe-инстанса
// ============================================================================
struct VuMeterState {
    IMMDeviceEnumerator* pEnumerator;
    IMMDevice* pDevice;
    IAudioMeterInformation* pMeter;
    
    // Стерео пики
    float peakL;
    float peakR;
    float peakMono;
    UINT32 channelCount;
    
    bool isValid;
    bool comInitialized;
    std::mutex mtx;

    VuMeterState()
        : pEnumerator(nullptr)
        , pDevice(nullptr)
        , pMeter(nullptr)
        , peakL(0.0f)
        , peakR(0.0f)
        , peakMono(0.0f)
        , channelCount(0)
        , isValid(false)
        , comInitialized(false)
    {}
};

// Глобальная карта: Haxe-указатель → C++ состояние
static std::map<void*, VuMeterState*> _vumeter_map;
static std::mutex _vumeter_map_mutex;

// ============================================================================
// ИНИЦИАЛИЗАЦИЯ WASAPI
// ============================================================================
static void _vumeter_init(void* haxePtr, int mode) {
    VuMeterState* st = new VuMeterState();

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) {
        st->comInitialized = true;
    } else if (hr == RPC_E_CHANGED_MODE) {
        // COM уже инициализирован в другом потоке — это ОК для нас
        st->comInitialized = false;
    } else {
        delete st;
        return;
    }

    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        (void**)&st->pEnumerator
    );

    if (FAILED(hr) || !st->pEnumerator) {
        if (st->comInitialized) CoUninitialize();
        delete st;
        return;
    }

    EDataFlow flow = (mode == 1) ? eCapture : eRender;

    hr = st->pEnumerator->GetDefaultAudioEndpoint(
        flow, eMultimedia, &st->pDevice
    );

    if (FAILED(hr) || !st->pDevice) {
        st->pEnumerator->Release();
        st->pEnumerator = nullptr;
        if (st->comInitialized) CoUninitialize();
        delete st;
        return;
    }

    hr = st->pDevice->Activate(
        __uuidof(IAudioMeterInformation), CLSCTX_ALL, NULL,
        (void**)&st->pMeter
    );

    if (SUCCEEDED(hr) && st->pMeter) {
        // Получаем количество каналов устройства
        st->pMeter->GetMeteringChannelCount(&st->channelCount);
        st->isValid = true;
    }

    {
        std::lock_guard<std::mutex> lock(_vumeter_map_mutex);
        _vumeter_map[haxePtr] = st;
    }
}

// ============================================================================
// ОСВОБОЖДЕНИЕ WASAPI
// ============================================================================
static void _vumeter_release(void* haxePtr) {
    VuMeterState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_vumeter_map_mutex);
        auto it = _vumeter_map.find(haxePtr);
        if (it != _vumeter_map.end()) {
            st = it->second;
            _vumeter_map.erase(it);
        }
    }

    if (st) {
        if (st->pMeter) { st->pMeter->Release(); st->pMeter = nullptr; }
        if (st->pDevice) { st->pDevice->Release(); st->pDevice = nullptr; }
        if (st->pEnumerator) { st->pEnumerator->Release(); st->pEnumerator = nullptr; }
        if (st->comInitialized) {
            CoUninitialize();
        }
        delete st;
    }
}

// ============================================================================
// ЧТЕНИЕ СТЕРЕО ПИКОВЫХ ЗНАЧЕНИЙ
// ============================================================================
struct StereoPeakResult {
    float peakL;
    float peakR;
    float peakMono;
    UINT32 channels;
    bool valid;
};

static StereoPeakResult _vumeter_get_stereo_peak(void* haxePtr) {
    StereoPeakResult result = {0.0f, 0.0f, 0.0f, 0, false};
    
    VuMeterState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_vumeter_map_mutex);
        auto it = _vumeter_map.find(haxePtr);
        if (it != _vumeter_map.end()) {
            st = it->second;
        }
    }

    if (!st || !st->isValid || !st->pMeter) return result;

    result.channels = st->channelCount;
    
    // Если устройство имеет 2 и более каналов — используем стерео-метод
    if (st->channelCount >= 2) {
        float channelPeaks[2] = {0.0f, 0.0f};
        HRESULT hr = st->pMeter->GetChannelsPeakValues(2, channelPeaks);
        if (SUCCEEDED(hr)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->peakL = channelPeaks[0];
            st->peakR = channelPeaks[1];
            st->peakMono = (channelPeaks[0] > channelPeaks[1]) ? channelPeaks[0] : channelPeaks[1];
            
            result.peakL = st->peakL;
            result.peakR = st->peakR;
            result.peakMono = st->peakMono;
            result.valid = true;
        }
    } else {
        // Моно-устройство — дублируем значение в оба канала
        float peak = 0.0f;
        HRESULT hr = st->pMeter->GetPeakValue(&peak);
        if (SUCCEEDED(hr)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->peakL = peak;
            st->peakR = peak;
            st->peakMono = peak;
            
            result.peakL = peak;
            result.peakR = peak;
            result.peakMono = peak;
            result.valid = true;
        }
    }

    return result;
}
')

/**
 * SystemVUMeterAtom — Аппаратный СТЕРЕО VU-метр от Windows WASAPI.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   SystemVUMeterAtom                                                     │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │      update(dt) → GetChannelsPeakValues() → setValueSilent()            │
 * │                                                                         │
 * │   Б) OUTPUTS:                                                           │
 * │      "peakL"    : Float  (0.0 .. 1.0) — левый канал                   │
 * │      "peakR"    : Float  (0.0 .. 1.0) — правый канал                  │
 * │      "peakMono" : Float  (0.0 .. 1.0) — максимум из L/R               │
 * │      "percentL" : Int    (0 .. 100)                                    │
 * │      "percentR" : Int    (0 .. 100)                                    │
 * │      "dB_L"     : Float  (-inf .. 0)                                   │
 * │      "dB_R"     : Float  (-inf .. 0)                                   │
 * │      "channels" : Int            — количество каналов (2=стерео)       │
 * │      "active"   : Bool                                                 │
 * │      "clipL"    : Bool           — пик L > 0.95                        │
 * │      "clipR"    : Bool           — пик R > 0.95                        │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class SystemVUMeterAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================
    private static inline var MODE_SPEAKERS:Int = 0;
    private static inline var MODE_MIC:Int      = 1;

    private static inline var CLIP_THRESHOLD:Float = 0.95;

    // =========================================================================
    // СОСТОЯНИЕ
    // =========================================================================
    private var _mode:Int             = MODE_SPEAKERS;
    private var _lastMode:Int         = -1;
    private var _isDeviceActive:Bool  = false; // Переименовано, чтобы не конфликтовать с Atom._isActive
    private var _channels:Int         = 0;

    // =========================================================================
    // КОНСТРУКТОР
    // =========================================================================
    public function new(id:String)
    {
        super(
            [ // INPUTS
                new Contact(MODE_SPEAKERS, INPUT, "mode")
            ],
            [ // OUTPUTS — СТЕРЕО
                new Contact(0.0,    OUTPUT, "peakL"),
                new Contact(0.0,    OUTPUT, "peakR"),
                new Contact(0.0,    OUTPUT, "peakMono"),
                new Contact(0,      OUTPUT, "percentL"),
                new Contact(0,      OUTPUT, "percentR"),
                new Contact(-120.0, OUTPUT, "dB_L"),
                new Contact(-120.0, OUTPUT, "dB_R"),
                new Contact(0,      OUTPUT, "channels"),
                new Contact(false,  OUTPUT, "active"),
                new Contact(false,  OUTPUT, "clipL"),
                new Contact(false,  OUTPUT, "clipR")
            ],
            null,
            id,
            "SystemVUMeterAtom",
            true // isActive = true → регистрируемся в DriverManager
        );

        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        _initWasapi(_mode);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // 1. Читаем вход "mode" — если изменился, переинициализируем WASAPI
        var modeC = getInput("mode");
        if (modeC != null && modeC.value != null)
        {
            var newMode = Std.int(modeC.value);
            if (newMode != _lastMode)
            {
                _mode = newMode;
                _initWasapi(_mode);
            }
        }

        // 2. Опрос WASAPI через C++ — СТЕРЕО
        var peakL:Float    = 0.0;
        var peakR:Float    = 0.0;
        var peakMono:Float = 0.0;
        var channels:Int   = 0;
        var valid:Bool     = false;
        
        // {0}..{4} — локальные переменные для записи результатов
        // {5}      — this (Haxe object), у него есть .mPtr
        untyped __cpp__('
            StereoPeakResult _vu_result = _vumeter_get_stereo_peak((void*){5}.mPtr);
            {0} = _vu_result.peakL;
            {1} = _vu_result.peakR;
            {2} = _vu_result.peakMono;
            {3} = (int)_vu_result.channels;
            {4} = _vu_result.valid;
        ', peakL, peakR, peakMono, channels, valid, this);

        _channels = channels;

        // 3. Вычисляем производные значения
        var percentL:Int = clampPercent(peakL * 100);
        var percentR:Int = clampPercent(peakR * 100);

		// === ВРЕМЕННО ДЛЯ ТЕСТА ===
		// Если значения слишком маленькие, усиливаем их
		//if (percentL < 50 && peakL > 0) percentL = Std.int(peakL * 1000);
		//if (percentR < 50 && peakR > 0) percentR = Std.int(peakR * 1000);
		// ==========================
		
		
        var dB_L:Float = (peakL > 0.0001) ? 20.0 * Math.log(peakL) / Math.log(10) : -120.0;
        var dB_R:Float = (peakR > 0.0001) ? 20.0 * Math.log(peakR) / Math.log(10) : -120.0;

        var clipL:Bool = peakL >= CLIP_THRESHOLD;
        var clipR:Bool = peakR >= CLIP_THRESHOLD;

        // 4. Тихая запись + propagate (паттерн из MiniAudioAtom)
        var peakLC     = getOutput("peakL");
        var peakRC     = getOutput("peakR");
        var peakMonoC  = getOutput("peakMono");
        var percentLC  = getOutput("percentL");
        var percentRC  = getOutput("percentR");
        var dB_LC      = getOutput("dB_L");
        var dB_RC      = getOutput("dB_R");
        var channelsC  = getOutput("channels");
        var activeC    = getOutput("active");
        var clipLC     = getOutput("clipL");
        var clipRC     = getOutput("clipR");

        if (peakLC    != null) peakLC.setValueSilent(peakL);
        if (peakRC    != null) peakRC.setValueSilent(peakR);
        if (peakMonoC != null) peakMonoC.setValueSilent(peakMono);
        if (percentLC != null) percentLC.setValueSilent(percentL);
        if (percentRC != null) percentRC.setValueSilent(percentR);
        if (dB_LC     != null) dB_LC.setValueSilent(dB_L);
        if (dB_RC     != null) dB_RC.setValueSilent(dB_R);
        if (channelsC != null) channelsC.setValueSilent(channels);
        if (activeC   != null) activeC.setValueSilent(_isDeviceActive);
        if (clipLC    != null) clipLC.setValueSilent(clipL);
        if (clipRC    != null) clipRC.setValueSilent(clipR);

        // 5. Одно распространение на каждый выход
        if (peakLC    != null) peakLC.propagateCurrentValue();
        if (peakRC    != null) peakRC.propagateCurrentValue();
        if (peakMonoC != null) peakMonoC.propagateCurrentValue();
        if (percentLC != null) percentLC.propagateCurrentValue();
        if (percentRC != null) percentRC.propagateCurrentValue();
        if (dB_LC     != null) dB_LC.propagateCurrentValue();
        if (dB_RC     != null) dB_RC.propagateCurrentValue();
        if (channelsC != null) channelsC.propagateCurrentValue();
        if (activeC   != null) activeC.propagateCurrentValue();
        if (clipLC    != null) clipLC.propagateCurrentValue();
        if (clipRC    != null) clipRC.propagateCurrentValue();
    }

    private function clampPercent(v:Float):Int
    {
        var i = Std.int(v);
        if (i > 100) i = 100;
        if (i < 0) i = 0;
        return i;
    }

    override public function dispose():Void
    {
        _releaseWasapi();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // WASAPI INIT / RELEASE
    // =========================================================================
    private function _initWasapi(mode:Int):Void
    {
        _releaseWasapi();
        _lastMode = mode;

        untyped __cpp__('
            _vumeter_init((void*){0}.mPtr, {1});
        ', this, mode);

        _isDeviceActive = true;
    }

    private function _releaseWasapi():Void
    {
        untyped __cpp__('
            _vumeter_release((void*){0}.mPtr);
        ', this);

        _isDeviceActive = false;
    }

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result:Dynamic = { mode: _mode };
        if (base != null && Reflect.hasField(base, "isLogic"))
        {
            Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
        }
        return result;
    }

    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        super.restoreState(state);
        if (state.mode != null)
        {
            _mode = Std.int(state.mode);
            _initWasapi(_mode);
        }
    }
}
#end