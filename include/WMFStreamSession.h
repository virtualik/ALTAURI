#pragma once

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#undef ERROR

#include <mfapi.h>
#include <mfidl.h>
#include <mferror.h>
#include <shlwapi.h>
#include <string>
#include <atomic>
#include <mutex>
#include <cstdio>

#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")

// === DUAL-OUTPUT LOGGING MACRO ===
#define WMF_LOG(fmt, ...) do { \
    char _wml_buf[1024]; \
    snprintf(_wml_buf, sizeof(_wml_buf), fmt, ##__VA_ARGS__); \
    OutputDebugStringA(_wml_buf); \
    printf("%s", _wml_buf); \
    fflush(stdout); \
} while(0)

/**
 * WMF STREAM SESSION v2.3 (Reconnect Loop Fix)
 *
 * ┌──────────────────────────────────────────────────────────────────────────┐
 * │  v2.3 CHANGES:                                                           │
 * │                                                                          │
 * │  1. Play() resets _connectionLost, _bufferingTimeout, _bufferingStartTime│
 * │     at the START of new playback. Without this, stale flags from a       │
 * │     previous session cause pollSessionState() to immediately trigger     │
 * │     startReconnect() right after a successful Play().                    │
 * │                                                                          │
 * │  2. MESessionClosed resets _bufferingStartTime to 0.                     │
 * │     Without this, CheckBufferingTimeout() can fire on a stale timestamp  │
 * │     from a previous session, causing false-positive timeout.             │
 * │                                                                          │
 * │  3. MESessionEnded clears _currentUrl BEFORE setting _connectionLost.    │
 * │     This prevents CheckAndResetConnectionLost() from firing on a URL     │
 * │     that was intentionally stopped by the user.                          │
 * └──────────────────────────────────────────────────────────────────────────┘
 */
class WMFStreamSession : public IMFAsyncCallback {
public:
    enum class State {
        IDLE       = 0,
        CONNECTING = 1,
        PLAYING    = 2,
        STOPPING   = 3,
        ERR        = 4
    };

private:
    std::atomic<State>  _state;
    std::atomic<bool>   _isBuffering;

    IMFMediaSession*            _session;
    IMFMediaSource*             _source;
    IMFPresentationDescriptor*  _presDesc;

// =========================================================================
// v2.2: CONNECTION MONITORING & RECONNECT SUPPORT
// =========================================================================
    std::atomic<bool> _connectionLost;
    std::atomic<bool> _bufferingTimeout;
    std::atomic<int>  _bufferingStartTime;

    ULONG       _refCount;
    std::mutex  _mutex;

    std::string _currentUrl;
    std::string _errorMessage;
    HRESULT     _lastError;
    float       _volume;
    bool        _mfInitialized;

    void TeardownSession() {
        if (_session) {
            _session->Shutdown();
            _session->Release();
            _session = nullptr;
        }
        if (_source) {
            _source->Shutdown();
            _source->Release();
            _source = nullptr;
        }
        if (_presDesc) {
            _presDesc->Release();
            _presDesc = nullptr;
        }
    }

    bool CreateSession() {
        WMF_LOG("🎵 [WMF] CreateSession()...\n");
        HRESULT hr = MFCreateMediaSession(nullptr, &_session);
        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] MFCreateMediaSession failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "MFCreateMediaSession failed";
            _state.store(State::ERR);
            return false;
        }
        WMF_LOG("✅ [WMF] MFCreateMediaSession OK\n");

        hr = _session->BeginGetEvent(this, nullptr);
        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] BeginGetEvent failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "BeginGetEvent failed";
            _state.store(State::ERR);
            return false;
        }
        WMF_LOG("✅ [WMF] BeginGetEvent OK\n");
        return true;
    }

    bool ResolveSource(const std::string& url) {
        WMF_LOG("🎵 [WMF] ResolveSource('%s')...\n", url.c_str());

        IMFSourceResolver* resolver = nullptr;
        HRESULT hr = MFCreateSourceResolver(&resolver);
        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] MFCreateSourceResolver failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "MFCreateSourceResolver failed";
            _state.store(State::ERR);
            return false;
        }

        int wlen = MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, nullptr, 0);
        if (wlen <= 0) {
            resolver->Release();
            _errorMessage = "URL conversion failed";
            _state.store(State::ERR);
            return false;
        }

        wchar_t* wurl = new wchar_t[wlen];
        MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, wurl, wlen);

        MF_OBJECT_TYPE objectType = MF_OBJECT_INVALID;
        IUnknown* sourceUnknown = nullptr;

        DWORD dwResolutionFlags =
            MF_RESOLUTION_MEDIASOURCE |
            MF_RESOLUTION_READ;

        WMF_LOG("🎵 [WMF] CreateObjectFromURL with flags=0x%X...\n", dwResolutionFlags);

        hr = resolver->CreateObjectFromURL(
            wurl,
            dwResolutionFlags,
            nullptr,
            &objectType,
            &sourceUnknown
        );

        delete[] wurl;
        resolver->Release();

        if (FAILED(hr) || !sourceUnknown) {
            WMF_LOG("❌ [WMF] CreateObjectFromURL failed: 0x%lX (objectType=%d)\n",
                   (unsigned long)hr, (int)objectType);
            _lastError = hr;
            _errorMessage = "CreateObjectFromURL failed: 0x" + std::to_string(hr);
            _state.store(State::ERR);
            return false;
        }

        WMF_LOG("✅ [WMF] CreateObjectFromURL OK (objectType=%d)\n", (int)objectType);

        if (objectType != MF_OBJECT_MEDIASOURCE) {
            WMF_LOG("⚠️ [WMF] Warning: objectType=%d (expected MF_OBJECT_MEDIASOURCE=%d)\n",
                   (int)objectType, (int)MF_OBJECT_MEDIASOURCE);
            // v2.3 FIX: If objectType is not MEDIASOURCE, release and fail
            // objectType=2 means BYTESTREAM — server returned data but not a media source
            // This happens when server is down or URL is invalid
            sourceUnknown->Release();
            _lastError = MF_E_UNSUPPORTED_FORMAT;
            _errorMessage = "Not a media source (objectType=" + std::to_string((int)objectType) + ")";
            _state.store(State::ERR);
            return false;
        }

        hr = sourceUnknown->QueryInterface(IID_PPV_ARGS(&_source));
        sourceUnknown->Release();

        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] QueryInterface IMFMediaSource failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "QueryInterface IMFMediaSource failed";
            _state.store(State::ERR);
            return false;
        }

        WMF_LOG("✅ [WMF] IMFMediaSource obtained\n");
        return true;
    }

    bool BuildTopology() {
        WMF_LOG("🎵 [WMF] BuildTopology()...\n");

        if (!_session || !_source) {
            WMF_LOG("❌ [WMF] _session or _source is null!\n");
            return false;
        }

        HRESULT hr = _source->CreatePresentationDescriptor(&_presDesc);
        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] CreatePresentationDescriptor failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "CreatePresentationDescriptor failed";
            _state.store(State::ERR);
            return false;
        }

        DWORD streamCount = 0;
        _presDesc->GetStreamDescriptorCount(&streamCount);
        WMF_LOG("🎵 [WMF] Stream count: %d\n", (int)streamCount);

        if (streamCount == 0) {
            _errorMessage = "No streams found in source";
            _state.store(State::ERR);
            return false;
        }

        IMFTopology* topology = nullptr;
        hr = MFCreateTopology(&topology);
        if (FAILED(hr)) {
            _presDesc->Release();
            _presDesc = nullptr;
            _lastError = hr;
            _errorMessage = "MFCreateTopology failed";
            _state.store(State::ERR);
            return false;
        }

        IMFActivate* audioActivate = nullptr;
        hr = MFCreateAudioRendererActivate(&audioActivate);
        if (FAILED(hr) || !audioActivate) {
            topology->Release();
            _presDesc->Release();
            _presDesc = nullptr;
            _lastError = hr;
            _errorMessage = "MFCreateAudioRendererActivate failed";
            _state.store(State::ERR);
            return false;
        }
        WMF_LOG("✅ [WMF] Audio renderer activate created\n");

        bool hasAudioStream = false;

        for (DWORD i = 0; i < streamCount; i++) {
            BOOL selected = FALSE;
            IMFStreamDescriptor* streamDesc = nullptr;
            hr = _presDesc->GetStreamDescriptorByIndex(i, &selected, &streamDesc);

            if (FAILED(hr) || !streamDesc) {
                if (streamDesc) streamDesc->Release();
                continue;
            }

            IMFMediaTypeHandler* typeHandler = nullptr;
            hr = streamDesc->GetMediaTypeHandler(&typeHandler);

            if (SUCCEEDED(hr) && typeHandler) {
                GUID majorType;
                hr = typeHandler->GetMajorType(&majorType);

                if (SUCCEEDED(hr)) {
                    bool isAudio = (majorType == MFMediaType_Audio);
                    WMF_LOG("🎵 [WMF] Stream %d: %s (selected=%d)\n",
                           (int)i, isAudio ? "AUDIO" : "NON-AUDIO", (int)selected);

                    if (isAudio) {
                        hasAudioStream = true;
                        _presDesc->SelectStream(i);

                        IMFTopologyNode* sourceNode = nullptr;
                        hr = MFCreateTopologyNode(MF_TOPOLOGY_SOURCESTREAM_NODE, &sourceNode);
                        if (SUCCEEDED(hr) && sourceNode) {
                            sourceNode->SetUnknown(MF_TOPONODE_SOURCE, _source);
                            sourceNode->SetUnknown(MF_TOPONODE_PRESENTATION_DESCRIPTOR, _presDesc);
                            sourceNode->SetUnknown(MF_TOPONODE_STREAM_DESCRIPTOR, streamDesc);
                            topology->AddNode(sourceNode);

                            IMFTopologyNode* sinkNode = nullptr;
                            hr = MFCreateTopologyNode(MF_TOPOLOGY_OUTPUT_NODE, &sinkNode);
                            if (SUCCEEDED(hr) && sinkNode) {
                                sinkNode->SetObject(audioActivate);
                                sinkNode->SetUINT32(MF_TOPONODE_STREAMID, 0);
                                sinkNode->SetUINT32(MF_TOPONODE_PRIMARYOUTPUT, TRUE);
                                topology->AddNode(sinkNode);

                                sourceNode->ConnectOutput(0, sinkNode, 0);
                                WMF_LOG("✅ [WMF] Connected stream %d to audio renderer\n", (int)i);

                                sinkNode->Release();
                            }
                            sourceNode->Release();
                        }
                    }
                }
                typeHandler->Release();
            }

            streamDesc->Release();
        }

        audioActivate->Release();

        if (!hasAudioStream) {
            topology->Release();
            _presDesc->Release();
            _presDesc = nullptr;
            _errorMessage = "No audio stream found in source";
            _state.store(State::ERR);
            WMF_LOG("❌ [WMF] No audio stream found!\n");
            return false;
        }

        WMF_LOG("🎵 [WMF] SetTopology()...\n");
        hr = _session->SetTopology(0, topology);
        topology->Release();

        if (FAILED(hr)) {
            WMF_LOG("❌ [WMF] SetTopology failed: 0x%lX\n", (unsigned long)hr);
            _lastError = hr;
            _errorMessage = "SetTopology failed: 0x" + std::to_string(hr);
            _state.store(State::ERR);
            return false;
        }

        WMF_LOG("✅ [WMF] SetTopology OK — waiting for events...\n");
        return true;
    }

public:
    WMFStreamSession()
        : _state(State::IDLE)
        , _isBuffering(false)
        , _session(nullptr)
        , _source(nullptr)
        , _presDesc(nullptr)
        , _refCount(1)
        , _lastError(S_OK)
        , _volume(1.0f)
        , _mfInitialized(false)
        , _connectionLost(false)
        , _bufferingTimeout(false)
        , _bufferingStartTime(0)
    {
        WMF_LOG("🎵 [WMF] WMFStreamSession constructor\n");

        HRESULT hrCom = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(hrCom) && hrCom != RPC_E_CHANGED_MODE) {
            WMF_LOG("❌ [WMF] CoInitializeEx failed: 0x%X\n", hrCom);
            return;
        }
        WMF_LOG("✅ [WMF] CoInitializeEx OK\n");

        HRESULT hr = MFStartup(MF_VERSION);
        if (SUCCEEDED(hr)) {
            _mfInitialized = true;
            WMF_LOG("✅ [WMF] MFStartup OK (version=0x%X)\n", MF_VERSION);
        } else {
            WMF_LOG("❌ [WMF] MFStartup failed: 0x%X\n", hr);
        }
    }

    ~WMFStreamSession() {
        WMF_LOG("🎵 [WMF] ~WMFStreamSession destructor\n");
        Stop();
        TeardownSession();
        if (_mfInitialized) {
            MFShutdown();
            _mfInitialized = false;
        }
        CoUninitialize();
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (riid == IID_IUnknown || riid == IID_IMFAsyncCallback) {
            *ppv = static_cast<IMFAsyncCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() {
        return InterlockedIncrement(&_refCount);
    }

    STDMETHODIMP_(ULONG) Release() {
        ULONG count = InterlockedDecrement(&_refCount);
        if (count == 0) {
            delete this;
        }
        return count;
    }

    STDMETHODIMP GetParameters(DWORD* pdwFlags, DWORD* pdwQueue) {
        return E_NOTIMPL;
    }

    STDMETHODIMP Invoke(IMFAsyncResult* pResult) {
        if (!pResult || !_session) return S_OK;

        IMFMediaEvent* event = nullptr;
        HRESULT hr = _session->EndGetEvent(pResult, &event);
        if (FAILED(hr) || !event) {
            if (_session && _state.load() != State::STOPPING) {
                _session->BeginGetEvent(this, nullptr);
            }
            if (event) event->Release();
            return S_OK;
        }

        MediaEventType eventType;
        event->GetType(&eventType);

        HRESULT hrEvent = S_OK;
        event->GetStatus(&hrEvent);

        switch (eventType) {
            case MESessionTopologySet:
                WMF_LOG("✅ [WMF] EVENT: MESessionTopologySet\n");
                {
                    PROPVARIANT varStart;
                    PropVariantInit(&varStart);
                    varStart.vt = VT_EMPTY;
                    HRESULT startHr = _session->Start(&GUID_NULL, &varStart);
                    WMF_LOG("🎵 [WMF] Session->Start() called, hr=0x%lX\n", (unsigned long)startHr);
                    PropVariantClear(&varStart);
                }
                break;

            case MESessionStarted:
                WMF_LOG("✅✅✅ [WMF] EVENT: MESessionStarted — PLAYING! hr=0x%lX\n", (unsigned long)hrEvent);
                _state.store(State::PLAYING);
                _isBuffering.store(false);
                // v2.3 FIX: Clear connection lost flag on successful start
                _connectionLost.store(false);
                break;

            case MESessionStopped:
                WMF_LOG("⏸ [WMF] EVENT: MESessionStopped\n");
                break;

            case MESessionClosed:
                WMF_LOG("🔒 [WMF] EVENT: MESessionClosed — session fully stopped\n");
                _state.store(State::IDLE);
                // v2.3 FIX: Reset buffering timer on close to prevent
                // stale timestamp from triggering false timeout on next session
                _bufferingStartTime.store(0);
                break;

            case MESessionEnded:
                WMF_LOG("🏁 [WMF] EVENT: MESessionEnded\n");
                _state.store(State::IDLE);
                // v2.3 FIX: Signal connection loss only if we had a URL
                // (i.e., this wasn't an intentional stop)
                if (_currentUrl.length() > 0) {
                    _connectionLost.store(true);
                    _errorMessage = "Stream ended unexpectedly";
                }
                break;

            case MEBufferingStarted:
                WMF_LOG("⏳ [WMF] EVENT: MEBufferingStarted\n");
                _isBuffering.store(true);
                _bufferingStartTime.store(GetTickCount());
                _bufferingTimeout.store(false);
                break;

            case MEBufferingStopped:
                WMF_LOG("✅ [WMF] EVENT: MEBufferingStopped\n");
                _isBuffering.store(false);
                _bufferingStartTime.store(0);
                break;

            case MEError:
                WMF_LOG("❌❌❌ [WMF] EVENT: MEError hr=0x%lX\n", (unsigned long)hrEvent);
                _lastError = hrEvent;
                _errorMessage = "Media Foundation error: 0x" + std::to_string(hrEvent);
                _state.store(State::ERR);
                _connectionLost.store(true);
                break;

            case MESourceStarted:
                WMF_LOG("📡 [WMF] EVENT: MESourceStarted\n");
                break;

            case MENewStream:
                WMF_LOG("🆕 [WMF] EVENT: MENewStream\n");
                break;

            case MEUpdatedStream:
                WMF_LOG("🔄 [WMF] EVENT: MEUpdatedStream\n");
                break;

            default:
                WMF_LOG("📋 [WMF] EVENT: type=%d hr=0x%lX\n", (int)eventType, (unsigned long)hrEvent);
                break;
        }

        event->Release();

        if (_session && _state.load() != State::IDLE && _state.load() != State::ERR) {
            _session->BeginGetEvent(this, nullptr);
        }

        return S_OK;
    }

    bool Play(const std::string& url) {
        WMF_LOG("\n🎵🎵🎵 [WMF] Play() called with URL: %s\n", url.c_str());

        std::lock_guard<std::mutex> lock(_mutex);

        if (url.empty()) {
            _errorMessage = "Empty URL";
            _state.store(State::ERR);
            return false;
        }

        // ═════════════════════════════════════════════════════════════════
        // v2.3 FIX: Reset ALL reconnect flags at start of new playback.
        // Without this, stale flags from a previous failed session cause
        // pollSessionState() to immediately trigger startReconnect()
        // right after a successful Play(), creating an infinite loop.
        // ═════════════════════════════════════════════════════════════════
        _connectionLost.store(false);
        _bufferingTimeout.store(false);
        _bufferingStartTime.store(0);

        if (_state.load() == State::PLAYING && _currentUrl == url) {
            WMF_LOG("🎵 [WMF] Already playing same URL, resuming...\n");
            if (_session) {
                PROPVARIANT varStart;
                PropVariantInit(&varStart);
                varStart.vt = VT_EMPTY;
                _session->Start(&GUID_NULL, &varStart);
                PropVariantClear(&varStart);
            }
            return true;
        }

        if (_state.load() != State::IDLE) {
            WMF_LOG("🎵 [WMF] Stopping previous session (state=%d)...\n", (int)_state.load());
            TeardownSession();
            _state.store(State::IDLE);
        }

        _currentUrl = url;
        _errorMessage.clear();
        _lastError = S_OK;
        _state.store(State::CONNECTING);

        if (!_mfInitialized) {
            HRESULT hr = MFStartup(MF_VERSION);
            if (FAILED(hr)) {
                _errorMessage = "MFStartup failed";
                _state.store(State::ERR);
                return false;
            }
            _mfInitialized = true;
        }

        WMF_LOG("🎵 [WMF] Step 1/3: CreateSession...\n");
        if (!CreateSession()) {
            WMF_LOG("❌ [WMF] CreateSession FAILED\n");
            return false;
        }

        WMF_LOG("🎵 [WMF] Step 2/3: ResolveSource...\n");
        if (!ResolveSource(url)) {
            WMF_LOG("❌ [WMF] ResolveSource FAILED: %s\n", _errorMessage.c_str());
            TeardownSession();
            return false;
        }

        WMF_LOG("🎵 [WMF] Step 3/3: BuildTopology...\n");
        if (!BuildTopology()) {
            WMF_LOG("❌ [WMF] BuildTopology FAILED: %s\n", _errorMessage.c_str());
            TeardownSession();
            return false;
        }

        WMF_LOG("✅✅✅ [WMF] Play() completed successfully! Waiting for MESessionTopologySet...\n\n");
        return true;
    }

    // ═════════════════════════════════════════════════════════════════════
    // v2.0 SYNCHRONOUS STOP
    // ═════════════════════════════════════════════════════════════════════
    void Stop() {
        WMF_LOG("🎵 [WMF] Stop() called\n");

        std::unique_lock<std::mutex> lock(_mutex);

        if (_state.load() == State::IDLE) {
            WMF_LOG("🎵 [WMF] Stop() — already IDLE, nothing to do\n");
            return;
        }

        _state.store(State::STOPPING);

        if (_session) {
            WMF_LOG("🎵 [WMF] Calling _session->Stop()...\n");
            _session->Stop();

            WMF_LOG("🎵 [WMF] Calling _session->Close()...\n");
            _session->Close();

            lock.unlock();

            int timeout = 20;
            while (_state.load() == State::STOPPING && timeout-- > 0) {
                Sleep(10);
            }

            if (timeout <= 0) {
                WMF_LOG("⚠️ [WMF] Stop() TIMEOUT — MESessionClosed not received in 200ms\n");
            } else {
                WMF_LOG("✅ [WMF] Stop() — MESessionClosed received after %d ms\n",
                       (100 - timeout) * 10);
            }

            lock.lock();
        }

        TeardownSession();
        _state.store(State::IDLE);
        _isBuffering.store(false);
        // v2.3 FIX: Clear URL on stop so MESessionEnded won't
        // trigger _connectionLost for intentional stops
        _currentUrl.clear();
        // v2.3 FIX: Reset reconnect flags on intentional stop
        _connectionLost.store(false);
        _bufferingTimeout.store(false);
        _bufferingStartTime.store(0);

        WMF_LOG("✅ [WMF] Stop() complete — session fully torn down\n");
    }

    void SetVolume(float v) {
        std::lock_guard<std::mutex> lock(_mutex);
        _volume = v;

        if (_session) {
            IMFGetService* getService = nullptr;
            HRESULT hr = _session->QueryInterface(IID_PPV_ARGS(&getService));
            if (SUCCEEDED(hr) && getService) {
                IMFSimpleAudioVolume* audioVolume = nullptr;
                hr = getService->GetService(
                    MR_POLICY_VOLUME_SERVICE,
                    IID_PPV_ARGS(&audioVolume)
                );
                if (SUCCEEDED(hr) && audioVolume) {
                    audioVolume->SetMasterVolume(v);
                    audioVolume->Release();
                }
                getService->Release();
            }
        }
    }

    State GetState() const { return _state.load(); }
    bool IsPlaying() const { return _state.load() == State::PLAYING; }
    bool IsBuffering() const { return _isBuffering.load(); }
    bool HasError() const { return _state.load() == State::ERR; }
    HRESULT GetLastError() const { return _lastError; }

    std::string GetErrorMessage() const {
        std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(_mutex));
        return _errorMessage;
    }

    // =========================================================================
    // v2.2: RECONNECT SUPPORT API
    // =========================================================================

    bool CheckAndResetConnectionLost() {
        return _connectionLost.exchange(false);
    }

	bool CheckBufferingTimeout(DWORD timeoutMs = 15000) {
		if (!_isBuffering.load()) return false;
		
		int startTime = _bufferingStartTime.load();
		if (startTime == 0) return false;  // Timer was reset
		
		DWORD elapsed = GetTickCount() - (DWORD)startTime;
		if (elapsed > timeoutMs) {
			_bufferingTimeout.store(true);
			_errorMessage = "Buffering timeout (" + std::to_string(timeoutMs/1000) + "s)";
			return true;
		}
		return false;
	}

    bool CheckAndResetBufferingTimeout() {
        return _bufferingTimeout.exchange(false);
    }

    std::string GetStateString() const {
        switch (_state.load()) {
            case State::IDLE:       return "IDLE";
            case State::CONNECTING: return "CONNECTING";
            case State::PLAYING:    return "PLAYING";
            case State::STOPPING:   return "STOPPING";
            case State::ERR:        return "ERROR";
            default:                return "UNKNOWN";
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// CLEANUP: Undefine aggressive Windows macros
// ═══════════════════════════════════════════════════════════════════════════
#ifdef ERROR
#undef ERROR
#endif
#ifdef interface
#undef interface
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

#endif  // #ifdef _WIN32