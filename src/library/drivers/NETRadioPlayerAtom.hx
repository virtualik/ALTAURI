#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;
import cpp.ConstCharStar;
import haxe.Timer;

// ============================================================================
// LINKER FLAGS — подключаем библиотеки Windows Media Foundation
// ============================================================================
@:buildXml('
<target id="haxe">
<lib name="mf.lib" />
<lib name="mfplat.lib" />
<lib name="mfplay.lib" />
<lib name="mfuuid.lib" />
<lib name="ole32.lib" />
<lib name="shlwapi.lib" />
</target>
')

// ============================================================================
// C++ HEADER — ТОЛЬКО стандартные заголовки, БЕЗ windows.h!
// ============================================================================
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <atomic>
#include <algorithm>
')

// ============================================================================
// C++ IMPLEMENTATION — WinHTTP (Metadata) + WMF (Audio Playback)
// ============================================================================
@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

// WMF Headers
#include <mfapi.h>
#include <mfplay.h>
#include <shlwapi.h>
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfplay.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")
#endif

// ============================================================================
// WMF AUDIO PLAYER STATE
// ============================================================================
#ifdef _WIN32
static IMFPMediaPlayer* g_pPlayer = NULL;
static bool g_mfStarted = false;
static std::string g_currentUrl;
static IMFPMediaItem* g_pCurrentMediaItem = NULL;

class RadioPlayerCallback : public IMFPMediaPlayerCallback {
public:
    RadioPlayerCallback() : m_refCount(1) {}
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (riid == IID_IUnknown || riid == __uuidof(IMFPMediaPlayerCallback)) {
            *ppv = static_cast<IMFPMediaPlayerCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_refCount); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG count = InterlockedDecrement(&m_refCount);
        if (count == 0) delete this;
        return count;
    }
    void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER *pEventHeader) {
        if (!pEventHeader) return;
        switch (pEventHeader->eEventType) {
            case MFP_EVENT_TYPE_MEDIAITEM_CREATED:
                if (SUCCEEDED(pEventHeader->hrEvent) && g_pPlayer) {
                    MFP_MEDIAITEM_CREATED_EVENT* pEvent = MFP_GET_MEDIAITEM_CREATED_EVENT(pEventHeader);
                    if (pEvent && pEvent->pMediaItem) {
                        // FIX: AddRef перед сохранением, чтобы избежать dangling pointer
                        IMFPMediaItem* pNewItem = pEvent->pMediaItem;
                        pNewItem->AddRef();
                        
                        // Устанавливаем трек в плеер
                        g_pPlayer->SetMediaItem(pNewItem);
                        
                        // Освобождаем старый трек, если есть
                        if (g_pCurrentMediaItem) {
                            g_pCurrentMediaItem->Release();
                        }
                        
                        // Сохраняем ссылку на новый трек
                        g_pCurrentMediaItem = pNewItem;
                    }
                }
                break;
            case MFP_EVENT_TYPE_MEDIAITEM_SET:
                if (SUCCEEDED(pEventHeader->hrEvent) && g_pPlayer) {
                    g_pPlayer->Play();
                }
                break;
            case MFP_EVENT_TYPE_ERROR:
                break;
        }
    }
private:
    LONG m_refCount;
};

static RadioPlayerCallback* g_pCallback = NULL;

extern "C" {
bool RP_Init() {
    if (g_mfStarted) return true;
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) return false;
    g_pCallback = new RadioPlayerCallback();
    hr = MFPCreateMediaPlayer(NULL, FALSE, 0, g_pCallback, NULL, &g_pPlayer);
    if (FAILED(hr) || !g_pPlayer) {
        if (g_pCallback) { g_pCallback->Release(); g_pCallback = NULL; }
        CoUninitialize();
        return false;
    }
    g_mfStarted = true;
    return true;
}

bool RP_SetURL(const char* url) {
    if (!g_pPlayer || !url) return false;
    g_currentUrl = std::string(url);
    int wlen = MultiByteToWideChar(CP_UTF8, 0, url, -1, NULL, 0);
    if (wlen <= 0) return false;
    wchar_t* wurl = new wchar_t[wlen];
    MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, wlen);
    HRESULT hr = g_pPlayer->CreateMediaItemFromURL(wurl, FALSE, 0, NULL);
    delete[] wurl;
    return SUCCEEDED(hr);
}

bool RP_Play() {
    if (!g_pPlayer) return false;
    HRESULT hr = g_pPlayer->Play();
    return SUCCEEDED(hr);
}

void RP_Stop() { if (g_pPlayer) g_pPlayer->Stop(); }
void RP_SetVolume(float v) { if (g_pPlayer) g_pPlayer->SetVolume(v); }

void RP_Shutdown() {
    if (g_pPlayer) { g_pPlayer->Shutdown(); g_pPlayer->Release(); g_pPlayer = NULL; }
    if (g_pCallback) { g_pCallback->Release(); g_pCallback = NULL; }
    if (g_pCurrentMediaItem) { g_pCurrentMediaItem->Release(); g_pCurrentMediaItem = NULL; }
    if (g_mfStarted) { CoUninitialize(); g_mfStarted = false; }
    g_currentUrl.clear();
}
}
#endif

// ============================================================================
// METADATA STATE STRUCTURE (WinHTTP)
// ============================================================================
struct NetRadioState {
    std::atomic<bool> shouldPlay;
    std::atomic<bool> shouldStop;
    std::atomic<bool> isRunning;
    std::string streamUrl;
    float pollInterval;
    std::string title;
    std::string artist;
    std::string track;
    std::string rawMetadata;
    std::string errorMsg;
    bool hasError;
    bool metadataChanged;
    bool isConnected;
    std::mutex mtx;
    std::thread* worker;

    NetRadioState()
        : shouldPlay(false), shouldStop(false), isRunning(false),
          pollInterval(5.0f), hasError(false), metadataChanged(false),
          isConnected(false), worker(nullptr) {}
};

static std::map<void*, NetRadioState*> _netradio_map;
static std::mutex _netradio_map_mutex;

// ============================================================================
// URL PARSER
// ============================================================================
struct ParsedURL {
    std::string host;
    std::string path;
    uint16_t port;
    bool isHttps;
    bool valid;
    ParsedURL() : host(""), path("/"), port(80), isHttps(false), valid(false) {}
};

static ParsedURL parse_url(const std::string& url) {
    ParsedURL result;
    std::string u = url;
    size_t schemeEnd = u.find("://");
    if (schemeEnd == std::string::npos) return result;
    std::string scheme = u.substr(0, schemeEnd);
    std::transform(scheme.begin(), scheme.end(), scheme.begin(), ::tolower);
    if (scheme == "https") { result.isHttps = true; result.port = 443; }
    else if (scheme == "http") { result.port = 80; }
    else { return result; }

    size_t hostStart = schemeEnd + 3;
    size_t pathStart = u.find("/", hostStart);
    size_t portStart = u.find(":", hostStart);

    if (pathStart == std::string::npos) {
        result.path = "/";
        if (portStart != std::string::npos) {
            result.host = u.substr(hostStart, portStart - hostStart);
            std::string portStr = u.substr(portStart + 1);
            try { result.port = (uint16_t)std::stoi(portStr); } catch (...) {}
        } else { result.host = u.substr(hostStart); }
    } else {
        result.path = u.substr(pathStart);
        if (portStart != std::string::npos && portStart < pathStart) {
            result.host = u.substr(hostStart, portStart - hostStart);
            std::string portStr = u.substr(portStart + 1, pathStart - portStart - 1);
            try { result.port = (uint16_t)std::stoi(portStr); } catch (...) {}
        } else { result.host = u.substr(hostStart, pathStart - hostStart); }
    }
    result.valid = !result.host.empty();
    return result;
}

// ============================================================================
// METADATA PARSER
// ============================================================================
static void parse_icy_metadata(const std::string& meta, std::string& outTitle, std::string& outArtist, std::string& outTrack) {
    outTitle = ""; outArtist = ""; outTrack = "";
    std::string quote(1, 39);
    size_t pos = meta.find("StreamTitle=");
    if (pos == std::string::npos) pos = meta.find("streamtitle=");
    if (pos == std::string::npos) return;

    size_t quoteStart = meta.find(quote, pos);
    if (quoteStart == std::string::npos) return;
    quoteStart++;
    size_t quoteEnd = meta.find(quote, quoteStart);
    if (quoteEnd == std::string::npos) return;

    std::string fullTitle = meta.substr(quoteStart, quoteEnd - quoteStart);
    outTitle = fullTitle;
    size_t sep = fullTitle.find(" - ");
    if (sep != std::string::npos) {
        outArtist = fullTitle.substr(0, sep);
        outTrack = fullTitle.substr(sep + 3);
    } else { outTrack = fullTitle; }
}

// ============================================================================
// WORKER THREAD (Metadata only)
// ============================================================================
static void _netradio_worker_func(void* haxePtr) {
    NetRadioState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
        auto it = _netradio_map.find(haxePtr);
        if (it == _netradio_map.end()) return;
        st = it->second;
    }

    st->isRunning.store(true);

#ifdef _WIN32
    HINTERNET hSession = NULL;
    HINTERNET hConnect = NULL;
    HINTERNET hRequest = NULL;

    while (st->isRunning.load()) {
        if (!st->shouldPlay.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        std::string url;
        {
            std::lock_guard<std::mutex> lock(st->mtx);
            url = st->streamUrl;
        }

        if (url.empty()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "Empty URL";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            continue;
        }

        ParsedURL parsed = parse_url(url);
        if (!parsed.valid) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "Invalid URL: " + url;
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            continue;
        }

        hSession = WinHttpOpen(L"ALTAURI/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!hSession) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "WinHttpOpen failed";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            continue;
        }

        std::wstring wHost(parsed.host.begin(), parsed.host.end());
        hConnect = WinHttpConnect(hSession, wHost.c_str(), parsed.port, 0);
        if (!hConnect) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "WinHttpConnect failed";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            WinHttpCloseHandle(hSession); hSession = NULL;
            continue;
        }

        std::wstring wPath(parsed.path.begin(), parsed.path.end());
        DWORD flags = parsed.isHttps ? WINHTTP_FLAG_SECURE : 0;
        hRequest = WinHttpOpenRequest(hConnect, L"GET", wPath.c_str(), NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
        if (!hRequest) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "WinHttpOpenRequest failed";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); hConnect = NULL; hSession = NULL;
            continue;
        }

        WinHttpAddRequestHeaders(hRequest, L"icy-metadata: 1", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);

        DWORD secFlags = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &secFlags, sizeof(secFlags));

        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "WinHttpSendRequest failed";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
            hRequest = NULL; hConnect = NULL; hSession = NULL;
            continue;
        }

        if (!WinHttpReceiveResponse(hRequest, NULL)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "WinHttpReceiveResponse failed";
            st->shouldPlay.store(false); st->isConnected = false; st->metadataChanged = true;
            WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
            hRequest = NULL; hConnect = NULL; hSession = NULL;
            continue;
        }

        int metaint = 0;
        {
            WCHAR buf[256] = {0}; DWORD bufLen = sizeof(buf);
            const wchar_t metaintHeader[] = L"icy-metaint";
            if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CUSTOM, metaintHeader, buf, &bufLen, NULL)) {
                std::wstring ws(buf); std::string s(ws.begin(), ws.end());
                try { metaint = std::stoi(s); } catch (...) {}
            }
        }

        {
            WCHAR buf[512] = {0}; DWORD bufLen = sizeof(buf);
            const wchar_t nameHeader[] = L"icy-name";
            if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CUSTOM, nameHeader, buf, &bufLen, NULL)) {
                std::wstring ws(buf); std::string name(ws.begin(), ws.end());
                std::lock_guard<std::mutex> lock(st->mtx);
                if (st->title.empty()) { st->title = name; st->metadataChanged = true; }
            }
        }

        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->isConnected = true; st->hasError = false; st->errorMsg = ""; st->metadataChanged = true;
        }

        std::string lastRawMeta;
        while (st->isRunning.load() && st->shouldPlay.load()) {
            if (st->shouldStop.load()) { st->shouldStop.store(false); st->shouldPlay.store(false); break; }

            DWORD bytesAvailable = 0;
            if (!WinHttpQueryDataAvailable(hRequest, &bytesAvailable)) break;
            if (bytesAvailable == 0) { std::this_thread::sleep_for(std::chrono::milliseconds(50)); continue; }

            if (metaint > 0) {
                char audioBuf[8192]; DWORD toRead = metaint;
                while (toRead > 0 && st->isRunning.load() && st->shouldPlay.load()) {
                    DWORD chunkSize = (toRead < sizeof(audioBuf)) ? toRead : sizeof(audioBuf);
                    DWORD bytesRead = 0;
                    if (!WinHttpReadData(hRequest, audioBuf, chunkSize, &bytesRead)) goto connection_lost;
                    if (bytesRead == 0) {
                        std::this_thread::sleep_for(std::chrono::milliseconds(100));
                        DWORD avail = 0; WinHttpQueryDataAvailable(hRequest, &avail);
                        if (avail == 0) { std::this_thread::sleep_for(std::chrono::milliseconds(500)); WinHttpQueryDataAvailable(hRequest, &avail); if (avail == 0) goto connection_lost; }
                        continue;
                    }
                    toRead -= bytesRead;
                }

                char metaLenByte = 0; DWORD metaLenRead = 0;
                if (!WinHttpReadData(hRequest, &metaLenByte, 1, &metaLenRead) || metaLenRead == 0) goto connection_lost;
                
                int metaLen = (unsigned char)metaLenByte * 16;
                if (metaLen > 0) {
                    std::string metaBuf; metaBuf.resize(metaLen + 1, 0); DWORD metaRead = 0;
                    if (!WinHttpReadData(hRequest, &metaBuf[0], metaLen, &metaRead)) goto connection_lost;
                    metaBuf[metaRead] = 0;
                    
                    std::string rawMeta(metaBuf.c_str());
                    if (rawMeta != lastRawMeta && !rawMeta.empty()) {
                        lastRawMeta = rawMeta;
                        std::string newTitle, newArtist, newTrack;
                        parse_icy_metadata(rawMeta, newTitle, newArtist, newTrack);
                        if (!newTitle.empty()) {
                            std::lock_guard<std::mutex> lock(st->mtx);
                            st->rawMetadata = rawMeta; st->title = newTitle; st->artist = newArtist; st->track = newTrack; st->metadataChanged = true;
                        }
                    }
                }
            } else {
                char discardBuf[8192]; DWORD bytesRead = 0;
                DWORD chunkSize = (bytesAvailable < sizeof(discardBuf)) ? bytesAvailable : sizeof(discardBuf);
                if (!WinHttpReadData(hRequest, discardBuf, chunkSize, &bytesRead)) break;
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
                if (st->shouldStop.load()) { st->shouldStop.store(false); st->shouldPlay.store(false); break; }
            }
        }

connection_lost:
        { std::lock_guard<std::mutex> lock(st->mtx); st->isConnected = false; }
        if (hRequest) { WinHttpCloseHandle(hRequest); hRequest = NULL; }
        if (hConnect) { WinHttpCloseHandle(hConnect); hConnect = NULL; }
        if (hSession) { WinHttpCloseHandle(hSession); hSession = NULL; }

        if (st->shouldPlay.load() && st->isRunning.load()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true; st->errorMsg = "Connection lost"; st->metadataChanged = true;
            int waitMs = (int)(st->pollInterval * 1000);
            for (int w = 0; w < waitMs / 100 && st->isRunning.load(); w++) std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);
#else
    while (st->isRunning.load()) std::this_thread::sleep_for(std::chrono::milliseconds(500));
#endif

    st->isRunning.store(false);
}
')

/**
* NET RADIO PLAYER ATOM v4.1 (Fixed Memory Leak + Race Condition)
*/
class NETRadioPlayerAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.1;
    private static inline var DEFAULT_POLL_INTERVAL:Float = 5.0;

    @:native("RP_Init") private static extern function nativeInit():Bool;
    @:native("RP_SetURL") private static extern function nativeSetURL(url:ConstCharStar):Bool;
    @:native("RP_Play") private static extern function nativePlay():Bool;
    @:native("RP_Stop") private static extern function nativeStop():Void;
    @:native("RP_SetVolume") private static extern function nativeSetVolume(v:Float):Void;
    @:native("RP_Shutdown") private static extern function nativeShutdown():Void;

    private var _lastUrl:String = "";
    private var _currentUrl:String = "";
    private var _lastTitle:String = "";
    private var _lastArtist:String = "";
    private var _lastTrack:String = "";
    private var _lastRawMeta:String = "";
    private var _lastError:String = "";
    private var _lastState:Bool = false;
    private var _lastPlayCtrl:Bool = false;
    private var _pollInterval:Float = DEFAULT_POLL_INTERVAL;
    private var _volume:Float = 1.0;
    private var _isWmfInitialized:Bool = false;
    private var _updatedTimer:Float = 0.0;
    
    // FIX: Таймер для отложенного вызова SetURL после Stop
    private var _pendingSetUrlTimer:Timer = null;

    public function new(id:String)
    {
        super(
            [
                new Contact("", INPUT, "stream_url"),
                new Contact(DEFAULT_POLL_INTERVAL, INPUT, "poll_interval"),
                new Contact(false, INPUT, "playCtrl"),
                new Contact(1.0, INPUT, "volume")
            ],
            [
                new Contact("", OUTPUT, "title"),
                new Contact("", OUTPUT, "artist"),
                new Contact("", OUTPUT, "track"),
                new Contact("", OUTPUT, "raw_metadata"),
                new Contact(false, OUTPUT, "updated"),
                new Contact(false, OUTPUT, "state"),
                new Contact("", OUTPUT, "error")
            ],
            null,
            id,
            "NETRadioPlayerAtom",
            true
        );
        init();
    }

    override public function init():Void
    {
        _isWmfInitialized = nativeInit();
        if (!_isWmfInitialized) {
            trace("NETRadioPlayer: WMF Initialization failed!");
        }

        untyped __cpp__('
            NetRadioState* st = new NetRadioState();
            st->isRunning.store(true);
            st->shouldPlay.store(false);
            st->shouldStop.store(false);
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                _netradio_map[(void*){0}.mPtr] = st;
            }
            st->worker = new std::thread(_netradio_worker_func, (void*){0}.mPtr);
        ', this);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        readInputs();
        pollCppState();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        // FIX: Отменить pending таймер
        if (_pendingSetUrlTimer != null) {
            _pendingSetUrlTimer.stop();
            _pendingSetUrlTimer = null;
        }
        
        stopAudio();
        nativeShutdown();
        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                auto it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) { st = it->second; _netradio_map.erase(it); }
            }
            if (st) {
                st->shouldStop.store(true); st->shouldPlay.store(false); st->isRunning.store(false);
                if (st->worker && st->worker->joinable()) st->worker->join();
                delete st->worker; delete st;
            }
        ', this);
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    private function readInputs():Void
    {
        var urlC = getInput("stream_url");
        if (urlC != null && urlC.value != null) {
            var newUrl:String = Std.string(urlC.value);
            if (newUrl != _lastUrl) {
                _lastUrl = newUrl;
                _currentUrl = "";
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    { std::lock_guard<std::mutex> lock(_netradio_map_mutex); auto it = _netradio_map.find((void*){0}.mPtr); if (it != _netradio_map.end()) st = it->second; }
                    if (st) { std::lock_guard<std::mutex> dataLock(st->mtx); st->streamUrl = std::string((const char*){1}.__s); }
                ', this, newUrl);
            }
        }

        var pollC = getInput("poll_interval");
        if (pollC != null && pollC.value != null) {
            var newInterval:Float = Std.parseFloat(Std.string(pollC.value));
            if (!Math.isNaN(newInterval) && newInterval >= 1.0 && newInterval != _pollInterval) {
                _pollInterval = newInterval;
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    { std::lock_guard<std::mutex> lock(_netradio_map_mutex); auto it = _netradio_map.find((void*){0}.mPtr); if (it != _netradio_map.end()) st = it->second; }
                    if (st) { std::lock_guard<std::mutex> dataLock(st->mtx); st->pollInterval = (float){1}; }
                ', this, newInterval);
            }
        }

        var volC = getInput("volume");
        if (volC != null && volC.value != null) {
            var newVol:Float = Std.parseFloat(Std.string(volC.value));
            if (!Math.isNaN(newVol) && newVol >= 0.0 && newVol <= 2.0) {
                _volume = newVol;
                nativeSetVolume(_volume);
            }
        }

        var playC = getInput("playCtrl");
        if (playC != null && playC.value != null) {
            var newPlay:Bool = (playC.value == true);
            if (newPlay != _lastPlayCtrl) {
                _lastPlayCtrl = newPlay;
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    { std::lock_guard<std::mutex> lock(_netradio_map_mutex); auto it = _netradio_map.find((void*){0}.mPtr); if (it != _netradio_map.end()) st = it->second; }
                    if (st) {
                        if ({1}) { st->shouldPlay.store(true); st->shouldStop.store(false); st->streamUrl = std::string((const char*){2}.__s); }
                        else { st->shouldStop.store(true); st->shouldPlay.store(false); }
                    }
                ', this, newPlay, _lastUrl);

                if (newPlay) {
                    startAudio();
                } else {
                    stopAudio();
                    //_currentUrl = ""; // ЛОМАЕТ ПОВТОРНЫЙ СТАРТ 
                }
            }
        }
    }

    private function startAudio():Void
    {
        if (_lastUrl == "" || _lastUrl == null) return;
        if (!_isWmfInitialized) {
            trace("NETRadioPlayer: WMF not initialized, cannot play audio.");
            return;
        }
        
        // FIX: Отменить предыдущий таймер, если есть
        if (_pendingSetUrlTimer != null) {
            _pendingSetUrlTimer.stop();
            _pendingSetUrlTimer = null;
        }
        
        // Если URL изменился или мы сбросили _currentUrl при Stop
        if (_currentUrl != _lastUrl) {
            trace("NETRadioPlayer: Loading new URL: " + _lastUrl);
            
            // FIX: Дать WMF время завершить предыдущую операцию Stop (200мс)
            var urlToLoad = _lastUrl;
            _pendingSetUrlTimer = Timer.delay(function() {
                _pendingSetUrlTimer = null;
                if (!_isDisposed) {
                    var success = nativeSetURL(urlToLoad);
                    if (!success) {
                        trace("NETRadioPlayer: WMF SetURL failed!");
                        setError(true, "WMF SetURL failed");
                    }
                }
            }, 1000);
            
            _currentUrl = _lastUrl;
            return; 
        }
        
        // Сюда попадаем, если URL не менялся
        trace("NETRadioPlayer: Resuming playback...");
        var success = nativePlay();
        if (!success) {
            trace("NETRadioPlayer: WMF Play failed!");
            setError(true, "WMF Play failed");
        }
    }

    private function stopAudio():Void
    {
        // FIX: Отменить pending SetURL, если есть
        if (_pendingSetUrlTimer != null) {
            _pendingSetUrlTimer.stop();
            _pendingSetUrlTimer = null;
        }
        nativeStop();
    }

    private function clearMetadata():Void
    {
        setOutput("title", ""); setOutput("artist", ""); setOutput("track", "");
        setOutput("raw_metadata", ""); setOutput("state", false); setOutput("error", "");
    }

    private function setError(hasError:Bool, errorMsg:String):Void
    {
        if (hasError != _lastState) {
            _lastState = hasError;
            setOutput("state", hasError);
        }
        if (errorMsg != _lastError) {
            _lastError = errorMsg;
            setOutput("error", errorMsg);
        }
    }

    private function pollCppState():Void
    {
        var cppTitle:String = ""; var cppArtist:String = ""; var cppTrack:String = "";
        var cppRawMeta:String = ""; var cppError:String = ""; var cppHasError:Bool = false; var cppChanged:Bool = false;

        untyped __cpp__('
            NetRadioState* st = nullptr;
            { std::lock_guard<std::mutex> lock(_netradio_map_mutex); auto it = _netradio_map.find((void*){0}.mPtr); if (it != _netradio_map.end()) st = it->second; }
            if (st) {
                std::lock_guard<std::mutex> dataLock(st->mtx);
                if (st->metadataChanged) {
                    {1} = ::String(st->title.c_str()); {2} = ::String(st->artist.c_str()); {3} = ::String(st->track.c_str());
                    {4} = ::String(st->rawMetadata.c_str()); {5} = ::String(st->errorMsg.c_str());
                    {6} = st->hasError; {7} = true; st->metadataChanged = false;
                }
            }
        ', this, cppTitle, cppArtist, cppTrack, cppRawMeta, cppError, cppHasError, cppChanged);

        if (cppChanged) {
            if (cppTitle != _lastTitle) { _lastTitle = cppTitle; setOutput("title", cppTitle); }
            if (cppArtist != _lastArtist) { _lastArtist = cppArtist; setOutput("artist", cppArtist); }
            if (cppTrack != _lastTrack) { _lastTrack = cppTrack; setOutput("track", cppTrack); }
            if (cppRawMeta != _lastRawMeta) { _lastRawMeta = cppRawMeta; setOutput("raw_metadata", cppRawMeta); }
            if (cppHasError != _lastState) { _lastState = cppHasError; setOutput("state", cppHasError); }
            if (cppError != _lastError) { _lastError = cppError; setOutput("error", cppError); }

            var updatedC = getOutput("updated");
            if (updatedC != null) { updatedC.value = true; _updatedTimer = PULSE_DURATION; }
        }
    }

    private function setOutput(name:String, value:Dynamic):Void {
        var c = getOutput(name);
        if (c != null) { c.setValueSilent(value); c.propagateCurrentValue(); }
    }

    private function updatePulseTimers(dt:Float):Void {
        if (_updatedTimer > 0) { _updatedTimer -= dt; if (_updatedTimer <= 0) { var c = getOutput("updated"); if (c != null) c.value = false; } }
    }
}
#end