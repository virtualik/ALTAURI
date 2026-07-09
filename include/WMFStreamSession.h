#pragma once

#ifdef _WIN32

#include <mfapi.h>
#include <mfidl.h>
#include <mfplay.h>
#include <shlwapi.h>
#include <string>
#include <atomic>
#include <mutex>

#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")

class WMFStreamSession : public IMFAsyncCallback {

public:
    enum class State {
        IDLE,
        CONNECTING,
        PLAYING,
        STOPPING,
        ERROR
    };

private:
    std::atomic<State> _state;
    std::atomic<bool> _isBuffering;

    IMFMediaSession* _session;
    IMFMediaSource* _source;
    IMFPresentationDescriptor* _presDesc;

    ULONG _refCount;
    std::mutex _mutex;

    std::string _currentUrl;
    std::string _errorMessage;
    HRESULT _lastError;
    float _volume;

    bool _mfInitialized;

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
        HRESULT hr = MFCreateMediaSession(nullptr, &_session);
        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "MFCreateMediaSession failed";
            _state.store(State::ERROR);
            return false;
        }
        hr = _session->BeginGetEvent(this, nullptr);
        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "BeginGetEvent failed";
            _state.store(State::ERROR);
            return false;
        }
        return true;
    }

    bool ResolveSource(const std::string& url) {
        IMFSourceResolver* resolver = nullptr;
        HRESULT hr = MFCreateSourceResolver(&resolver);
        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "MFCreateSourceResolver failed";
            _state.store(State::ERROR);
            return false;
        }

        int wlen = MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, nullptr, 0);
        if (wlen <= 0) {
            resolver->Release();
            _errorMessage = "URL conversion failed";
            _state.store(State::ERROR);
            return false;
        }

        wchar_t* wurl = new wchar_t[wlen];
        MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, wurl, wlen);

        MF_OBJECT_TYPE objectType;
        IUnknown* sourceUnknown = nullptr;
        hr = resolver->CreateObjectFromURL(
            wurl,
            MF_RESOLUTION_MEDIASOURCE | MF_RESOLUTION_READ,
            nullptr,
            &objectType,
            &sourceUnknown
        );

        delete[] wurl;
        resolver->Release();

        if (FAILED(hr) || !sourceUnknown) {
            _lastError = hr;
            _errorMessage = "CreateObjectFromURL failed";
            _state.store(State::ERROR);
            return false;
        }

        hr = sourceUnknown->QueryInterface(IID_PPV_ARGS(&_source));
        sourceUnknown->Release();

        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "QueryInterface IMFMediaSource failed";
            _state.store(State::ERROR);
            return false;
        }

        return true;
    }

    bool BuildTopology() {
        if (!_session || !_source) return false;

        HRESULT hr = _source->CreatePresentationDescriptor(&_presDesc);
        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "CreatePresentationDescriptor failed";
            _state.store(State::ERROR);
            return false;
        }

        DWORD streamCount = 0;
        _presDesc->GetStreamDescriptorCount(&streamCount);

        IMFTopology* topology = nullptr;
        hr = MFCreateTopology(&topology);
        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "MFCreateTopology failed";
            _state.store(State::ERROR);
            return false;
        }

        IMFMediaSink* audioSink = nullptr;
        hr = MFCreateAudioRendererActivate(&audioSink);

        if (FAILED(hr) || !audioSink) {
            topology->Release();
            _lastError = hr;
            _errorMessage = "MFCreateAudioRendererActivate failed";
            _state.store(State::ERROR);
            return false;
        }

        for (DWORD i = 0; i < streamCount; i++) {
            BOOL selected = FALSE;
            IMFStreamDescriptor* streamDesc = nullptr;
            _presDesc->GetStreamDescriptorByIndex(i, &selected, &streamDesc);

            if (!selected || !streamDesc) {
                if (streamDesc) streamDesc->Release();
                continue;
            }

            IMFActivate* sinkActivate = nullptr;
            hr = audioSink->QueryInterface(IID_PPV_ARGS(&sinkActivate));

            IMFTopologyNode* sourceNode = nullptr;
            hr = MFCreateTopologyNode(MF_TOPOLOGY_SOURCESTREAM_NODE, &sourceNode);
            if (SUCCEEDED(hr)) {
                sourceNode->SetUnknown(MF_TOPONODE_SOURCE, _source);
                sourceNode->SetUnknown(MF_TOPONODE_PRESENTATION_DESCRIPTOR, _presDesc);
                sourceNode->SetUnknown(MF_TOPONODE_STREAM_DESCRIPTOR, streamDesc);
                topology->AddNode(sourceNode);
            }

            IMFTopologyNode* outputNode = nullptr;
            hr = MFCreateTopologyNode(MF_TOPOLOGY_OUTPUT_NODE, &outputNode);
            if (SUCCEEDED(hr)) {
                IUnknown* activateUnknown = nullptr;
                audioSink->QueryInterface(IID_PPV_ARGS(&activateUnknown));
                outputNode->SetUnknown(MF_TOPONODE_NOSHUTDOWN_ON_REMOVE, activateUnknown);
                outputNode->SetUINT32(MF_TOPONODE_STREAMID, 0);
                outputNode->SetUINT32(MF_TOPONODE_PRIMARYOUTPUT, TRUE);

                IMFMediaTypeHandler* handler = nullptr;
                IUnknown* spSink = nullptr;
                audioSink->QueryInterface(IID_PPV_ARGS(&spSink));

                IMFTopologyNode* sinkNode = nullptr;
                hr = MFCreateTopologyNode(MF_TOPOLOGY_OUTPUT_NODE, &sinkNode);
                if (SUCCEEDED(hr)) {
                    sinkNode->SetObject(audioSink);
                    sinkNode->SetUINT32(MF_TOPONODE_STREAMID, 0);
                    sinkNode->SetUINT32(MF_TOPONODE_PRIMARYOUTPUT, TRUE);
                    topology->AddNode(sinkNode);

                    if (sourceNode) {
                        sourceNode->ConnectOutput(0, sinkNode, 0);
                    }
                    sinkNode->Release();
                }

                if (spSink) spSink->Release();
                if (activateUnknown) activateUnknown->Release();
                outputNode->Release();
            }

            streamDesc->Release();
        }

        audioSink->Release();

        hr = _session->SetTopology(0, topology);
        topology->Release();

        if (FAILED(hr)) {
            _lastError = hr;
            _errorMessage = "SetTopology failed";
            _state.store(State::ERROR);
            return false;
        }

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
    {
        HRESULT hr = MFStartup(MF_VERSION);
        if (SUCCEEDED(hr)) {
            _mfInitialized = true;
        }
    }

    ~WMFStreamSession() {
        Stop();
        TeardownSession();
        if (_mfInitialized) {
            MFShutdown();
            _mfInitialized = false;
        }
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
            case MESessionTopologySet: {
                PROPVARIANT varStart;
                PropVariantInit(&varStart);
                varStart.vt = VT_EMPTY;
                _session->Start(&GUID_NULL, &varStart);
                PropVariantClear(&varStart);
                break;
            }

            case MESessionStarted:
                _state.store(State::PLAYING);
                _isBuffering.store(false);
                break;

            case MESessionStopped:
                if (_state.load() == State::STOPPING) {
                    _state.store(State::IDLE);
                }
                break;

            case MESessionClosed:
                _state.store(State::IDLE);
                break;

            case MESessionEnded:
                _state.store(State::IDLE);
                break;

            case MEBufferingStarted:
                _isBuffering.store(true);
                break;

            case MEBufferingStopped:
                _isBuffering.store(false);
                break;

            case MEError:
                _lastError = hrEvent;
                {
                    PROPVARIANT varError;
                    PropVariantInit(&varError);
                    event->GetValue(&varError);
                    if (varError.vt == VT_UNKNOWN && varError.punkVal) {
                        HRESULT code = S_OK;
                        varError.punkVal->QueryInterface(IID_PPV_ARGS((void**)&code));
                    }
                    PropVariantClear(&varError);
                }
                _errorMessage = "Media Foundation error";
                _state.store(State::ERROR);
                break;

            case MESessionScrubSampleComplete:
            case MESessionCapabilitiesChanged:
            case MESessionTopologyStatus:
                break;

            default:
                break;
        }

        event->Release();

        if (_session && _state.load() != State::IDLE) {
            _session->BeginGetEvent(this, nullptr);
        }

        return S_OK;
    }

    bool Play(const std::string& url) {
        std::lock_guard<std::mutex> lock(_mutex);

        if (url.empty()) {
            _errorMessage = "Empty URL";
            _state.store(State::ERROR);
            return false;
        }

        if (_state.load() == State::PLAYING && _currentUrl == url) {
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
                _state.store(State::ERROR);
                return false;
            }
            _mfInitialized = true;
        }

        if (!CreateSession()) return false;
        if (!ResolveSource(url)) {
            TeardownSession();
            return false;
        }
        if (!BuildTopology()) {
            TeardownSession();
            return false;
        }

        return true;
    }

    void Stop() {
        std::lock_guard<std::mutex> lock(_mutex);

        if (_state.load() == State::IDLE) return;

        _state.store(State::STOPPING);

        if (_session) {
            _session->Stop();
            _session->Close();
        }

        TeardownSession();
        _state.store(State::IDLE);
        _isBuffering.store(false);
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
    bool HasError() const { return _state.load() == State::ERROR; }
    HRESULT GetLastError() const { return _lastError; }
    std::string GetErrorMessage() const {
        std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(_mutex));
        return _errorMessage;
    }
};

#endif