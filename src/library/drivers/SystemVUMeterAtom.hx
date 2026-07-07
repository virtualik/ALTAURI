#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// HEADER
// ============================================================================
// INTENTIONALLY EMPTY!
// We do NOT include Windows.h and WASAPI headers here to prevent their macros
// (ERROR, interface, min, max) from leaking into __boot__.cpp and breaking
// Lime/OpenAL compilation.
@:headerCode('
')

// ============================================================================
// C++ IMPLEMENTATION (CPP FILE CODE)
// ============================================================================
@:cppFileCode('
// Protection from aggressive Windows macros
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
// C++ STATE STRUCT — stores WASAPI objects for each Haxe instance
// ============================================================================
struct VuMeterState {
    IMMDeviceEnumerator* pEnumerator;
    IMMDevice* pDevice;
    IAudioMeterInformation* pMeter;
    
    // Stereo peaks
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

// Global map: Haxe pointer → C++ state
static std::map<void*, VuMeterState*> _vumeter_map;
static std::mutex _vumeter_map_mutex;

// ============================================================================
// WASAPI INITIALIZATION
// ============================================================================
static void _vumeter_init(void* haxePtr, int mode) {
    VuMeterState* st = new VuMeterState();
    
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr)) {
        st->comInitialized = true;
    } else if (hr == RPC_E_CHANGED_MODE) {
        // COM already initialized in another thread — OK for us
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
        // Get device channel count
        st->pMeter->GetMeteringChannelCount(&st->channelCount);
        st->isValid = true;
    }
    
    {
        std::lock_guard<std::mutex> lock(_vumeter_map_mutex);
        _vumeter_map[haxePtr] = st;
    }
}

// ============================================================================
// WASAPI RELEASE
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
// STEREO PEAK VALUE READING
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
    
    // If device has 2+ channels — use stereo method
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
        // Mono device — duplicate value to both channels
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
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     SYSTEM VU METER ATOM v1.0                             ║
 * ║                     (Windows WASAPI Stereo Audio Meter)                   ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Hardware STEREO VU meter from Windows WASAPI.                            ║
 * ║  Reads real-time peak values from default audio endpoint.                 ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     SystemVUMeterAtom                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  A) COMPUTE MODULE:                                                 │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     update(dt) → GetChannelsPeakValues() → setValueSilent()         │  ║
 * ║  │                                                                     │  ║
 * ║  │  B) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "peakL"    : Float  (0.0 .. 1.0) — left channel                 │  ║
 * ║  │     "peakR"    : Float  (0.0 .. 1.0) — right channel                │  ║
 * ║  │     "peakMono" : Float  (0.0 .. 1.0) — max of L/R                   │  ║
 * ║  │     "percentL" : Int    (0 .. 100)                                  │  ║
 * ║  │     "percentR" : Int    (0 .. 100)                                  │  ║
 * ║  │     "dB_L"     : Float  (-inf .. 0)                                 │  ║
 * ║  │     "dB_R"     : Float  (-inf .. 0)                                 │  ║
 * ║  │     "channels" : Int            — channel count (2=stereo)          │  ║
 * ║  │     "active"   : Bool                                               │  ║
 * ║  │     "clipL"    : Bool           — peak L > 0.95                     │  ║
 * ║  │     "clipR"    : Bool           — peak R > 0.95                     │  ║
 * ║  │                                                                     │  ║
 * ║  │  C) INPUTS:                                                         │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "mode"     : Int    (0=Speakers, 1=Microphone)                  │  ║
 * ║  │                                                                     │  ║
 * ║  │  D) FACE (DeviceView):                                              │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     SystemVUMeterWidget for stereo VU visualization                 │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                      WASAPI FLOW                                          ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  init() → _initWasapi(mode)                                               ║
 * ║           ├── CoInitializeEx()                                            ║
 * ║           ├── CoCreateInstance(MMDeviceEnumerator)                        ║
 * ║           ├── GetDefaultAudioEndpoint(flow)                               ║
 * ║           ├── Activate(IAudioMeterInformation)                            ║
 * ║           └── GetMeteringChannelCount()                                   ║
 * ║                                                                           ║
 * ║  update(dt) → _vumeter_get_stereo_peak()                                  ║
 * ║               ├── GetChannelsPeakValues(2, peaks)  [if stereo]            ║
 * ║               └── GetPeakValue(&peak)              [if mono]              ║
 * ║                                                                           ║
 * ║  dispose() → _releaseWasapi()                                             ║
 * ║              ├── pMeter->Release()                                        ║
 * ║              ├── pDevice->Release()                                       ║
 * ║              ├── pEnumerator->Release()                                   ║
 * ║              └── CoUninitialize()                                         ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    APPLICATION                                            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  • Real-time system audio level monitoring                                ║
 * ║  • Microphone input level visualization                                   ║
 * ║  • Audio-driven signal generation                                         ║
 * ║  • Voice activity detection                                               ║
 * ║  • Stereo balance analysis                                                ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class SystemVUMeterAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var MODE_SPEAKERS:Int = 0;
    private static inline var MODE_MIC:Int      = 1;
    
    /**
     * Clip detection threshold.
     * Peak values above this are considered clipping.
     */
    private static inline var CLIP_THRESHOLD:Float = 0.95;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _mode:Int             = MODE_SPEAKERS;
    private var _lastMode:Int         = -1;
    
    /**
     * Renamed from _isActive to avoid conflict with Atom._isActive.
     * Indicates whether WASAPI device is successfully initialized.
     */
    private var _isDeviceActive:Bool  = false;
    private var _channels:Int         = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [ // INPUTS
                new Contact(MODE_SPEAKERS, INPUT, "mode")
            ],
            [ // OUTPUTS — STEREO
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
            true // isActive = true → register in DriverManager
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

    /**
     * Update every frame — main polling logic.
     * Called from DriverManager.update().
     *
     * Pattern:
     * 1. Check mode input — reinitialize WASAPI if changed
     * 2. Poll WASAPI via C++ — get stereo peaks
     * 3. Calculate derived values (percent, dB, clip)
     * 4. Silent write + single propagate (batched update pattern)
     *
     * @param dt Delta time in seconds
     */
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // 1. Read "mode" input — reinitialize WASAPI if changed
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

        // 2. Poll WASAPI via C++ — STEREO
        var peakL:Float    = 0.0;
        var peakR:Float    = 0.0;
        var peakMono:Float = 0.0;
        var channels:Int   = 0;
        var valid:Bool     = false;

        // {0}..{4} — local variables for result writing
        // {5}      — this (Haxe object), has .mPtr
        untyped __cpp__('
            StereoPeakResult _vu_result = _vumeter_get_stereo_peak((void*){5}.mPtr);
            {0} = _vu_result.peakL;
            {1} = _vu_result.peakR;
            {2} = _vu_result.peakMono;
            {3} = (int)_vu_result.channels;
            {4} = _vu_result.valid;
        ', peakL, peakR, peakMono, channels, valid, this);

        _channels = channels;

        // 3. Calculate derived values
        var percentL:Int = clampPercent(peakL * 100);
        var percentR:Int = clampPercent(peakR * 100);

        var dB_L:Float = (peakL > 0.0001) ? 20.0 * Math.log(peakL) / Math.log(10) : -120.0;
        var dB_R:Float = (peakR > 0.0001) ? 20.0 * Math.log(peakR) / Math.log(10) : -120.0;

        var clipL:Bool = peakL >= CLIP_THRESHOLD;
        var clipR:Bool = peakR >= CLIP_THRESHOLD;

        // 4. Silent write + propagate (pattern from MiniAudioAtom)
        //    This reduces TickGenerator load during batched updates.
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

        // Silent writes — no propagation triggered
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

        // Single propagation per output — triggers downstream atoms once
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

    /**
     * Clamp percent value to 0..100 range.
     *
     * @param v Raw percent value
     * @return Clamped integer value
     */
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
    /**
     * Initialize WASAPI device for specified mode.
     * Releases previous device if any.
     *
     * @param mode 0 = Speakers (eRender), 1 = Microphone (eCapture)
     */
    private function _initWasapi(mode:Int):Void
    {
        _releaseWasapi();
        _lastMode = mode;
        
        untyped __cpp__('
            _vumeter_init((void*){0}.mPtr, {1});
        ', this, mode);
        
        _isDeviceActive = true;
    }

    /**
     * Release WASAPI device and free COM resources.
     */
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
        
        if (state.mode != null)
        {
            _mode = Std.int(state.mode);
            _initWasapi(_mode);
        }
    }
}
#end