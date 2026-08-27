#if (cpp || js)
package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;
#if cpp
import cpp.ConstCharStar;
#end
#if js
import js.html.Audio;
#end

// ============================================================================
// LINKER FLAGS — Windows Media Foundation libraries (Windows C++ ONLY)
// ============================================================================
#if (cpp && windows)
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
#end

// ============================================================================
// C++ HEADER — Standard headers only, NO windows.h here!
// ============================================================================
#if cpp
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <atomic>
#include <algorithm>
#include <cstdlib>
#include <ctime>
')

// ============================================================================
// C++ IMPLEMENTATION — WinHTTP (Metadata) + WMF/MFPlay (Audio Playback)
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
// METADATA STATE STRUCTURE (WinHTTP Worker Thread)
// ============================================================================
// Per-instance state shared between Haxe main thread and C++ worker thread.
// All fields are protected by mutex or are atomic for thread safety.
struct NetRadioState {
    std::atomic<bool> shouldPlay;       // Worker should actively read stream
    std::atomic<bool> shouldStop;       // Worker should stop current session
    std::atomic<bool> isRunning;        // Worker thread is alive
    std::string streamUrl;              // Current stream URL (protected by mtx)
    float pollInterval;                 // Reconnect delay in seconds (MAX cap)
    std::string title;                  // Parsed ICY title (protected by mtx)
    std::string artist;                 // Parsed ICY artist (protected by mtx)
    std::string track;                  // Parsed ICY track (protected by mtx)
    std::string rawMetadata;            // Raw ICY metadata string
    std::string errorMsg;               // Last error message
    bool hasError;                      // Error flag
    bool metadataChanged;               // Dirty flag for Haxe polling
    bool isConnected;                   // Connection status
    std::mutex mtx;                     // Protects string fields above
    std::thread* worker;                // Background thread handle
#ifdef _WIN32
    HINTERNET hRequest;                 // WinHTTP request handle (for cancellation)
    std::mutex hRequestMtx;             // Protects hRequest
#endif
    std::atomic<bool> isMfStopped;      // Set by MFP_EVENT_TYPE_STOP callback
    std::atomic<bool> hasComError;      // Set by MF error callbacks
    std::string comErrorMsg;            // Human-readable COM/MF error
    long lastComHr;                     // Last HRESULT from MF
    // === EXPONENTIAL BACKOFF STATE ===
    int reconnectAttempts;              // Counter for exponential backoff

    NetRadioState()
        : shouldPlay(false), shouldStop(false), isRunning(false),
          pollInterval(5.0f), hasError(false), metadataChanged(false),
          isConnected(false), worker(nullptr),
#ifdef _WIN32
          hRequest(NULL),
#endif
          isMfStopped(true), hasComError(false), lastComHr(0),
          reconnectAttempts(0) {}       // Initialize reconnect counter
};

// Global map: Haxe instance pointer -> C++ state
static std::map<void*, NetRadioState*> _netradio_map;
static std::mutex _netradio_map_mutex;
static NetRadioState* g_currentState = nullptr; // Global pointer for callback access

// ============================================================================
// WMF AUDIO PLAYER STATE (Global — shared across all instances)
// ============================================================================
// NOTE: MFPlay is initialized once per application and shared.
// This is acceptable because we have a single NETRadioPlayerAtom
// active at any given time in the typical ALTAURI use case.
#ifdef _WIN32
static IMFPMediaPlayer* g_pPlayer = NULL;
static bool g_mfStarted = false;
static std::string g_currentUrl;
static IMFPMediaItem* g_pCurrentMediaItem = NULL;

// ============================================================================
// MFPlay CALLBACK — Handles asynchronous WMF events
// ============================================================================
// MFPlay events are delivered on a dedicated MF thread.
// Event type constants (from mfplay.h):
//   MFP_EVENT_TYPE_PLAY            = 0   (Play completed)
//   MFP_EVENT_TYPE_PAUSE           = 1
//   MFP_EVENT_TYPE_STOP            = 2   (Stop completed — what we wait for)
//   MFP_EVENT_TYPE_POSITION_SET    = 3
//   MFP_EVENT_TYPE_RATE_SET        = 4
//   MFP_EVENT_TYPE_MEDIAITEM_CREATED = 5 (URL resolved to media item)
//   MFP_EVENT_TYPE_MEDIAITEM_SET   = 6   (Media item assigned to player)
//   MFP_EVENT_TYPE_FRAME_STEP      = 7
//   MFP_EVENT_TYPE_MEDIAITEM_CLEARED = 8
//   MFP_EVENT_TYPE_MF              = 9
//   MFP_EVENT_TYPE_ERROR           = 10  (Playback error)
//   MFP_EVENT_TYPE_PLAYBACK_ENDED  = 11
//   MFP_EVENT_TYPE_ACQUIRE_USER_CREDENTIALS = 12
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
        long hr = (long)pEventHeader->hrEvent;
        bool succeeded = (hr >= 0);
        
        switch (pEventHeader->eEventType) {
            // -- MEDIA ITEM CREATED --------------------------------------------------
            // CreateMediaItemFromURL() completed.
            // Now we must assign the item to the player via SetMediaItem().
            case MFP_EVENT_TYPE_MEDIAITEM_CREATED:
                if (succeeded && g_pPlayer) {
                    MFP_MEDIAITEM_CREATED_EVENT* pEvent = MFP_GET_MEDIAITEM_CREATED_EVENT(pEventHeader);
                    if (pEvent && pEvent->pMediaItem) {
                        IMFPMediaItem* pNewItem = pEvent->pMediaItem;
                        pNewItem->AddRef();
                        g_pPlayer->SetMediaItem(pNewItem);
                        if (g_pCurrentMediaItem) g_pCurrentMediaItem->Release();
                        g_pCurrentMediaItem = pNewItem;
                    }
                } else {
                    if (g_currentState) {
                        std::lock_guard<std::mutex> lock(g_currentState->mtx);
                        g_currentState->hasComError.store(true);
                        g_currentState->lastComHr = hr;
                        char buf[128];
                        sprintf(buf, "CreateMediaItem Failed: 0x%lX", (unsigned long)hr);
                        g_currentState->comErrorMsg = buf;
                        g_currentState->metadataChanged = true;
                    }
                }
                break;
                
            // -- MEDIA ITEM SET ------------------------------------------------------
            // SetMediaItem() completed. Now we can start playback.
            case MFP_EVENT_TYPE_MEDIAITEM_SET:
                if (succeeded && g_pPlayer) {
                    g_pPlayer->Play();
                } else {
                    if (g_currentState) {
                        std::lock_guard<std::mutex> lock(g_currentState->mtx);
                        g_currentState->hasComError.store(true);
                        g_currentState->lastComHr = hr;
                        char buf[128];
                        sprintf(buf, "SetMediaItem Failed: 0x%lX", (unsigned long)hr);
                        g_currentState->comErrorMsg = buf;
                        g_currentState->metadataChanged = true;
                    }
                }
                break;
                
            // -- STOP COMPLETED ------------------------------------------------------
            // Stop() is asynchronous. This event signals that the player
            // has fully stopped and is ready for a new SetMediaItem() call.
            case MFP_EVENT_TYPE_STOP:  // = 2
                if (g_currentState) {
                    g_currentState->isMfStopped.store(true);
                }
                break;
                
            // -- PLAY COMPLETED ------------------------------------------------------
            // Play() finished (successfully or with error).
            case MFP_EVENT_TYPE_PLAY:  // = 0
                if (!succeeded && g_currentState) {
                    std::lock_guard<std::mutex> lock(g_currentState->mtx);
                    g_currentState->hasComError.store(true);
                    g_currentState->lastComHr = hr;
                    char buf[128];
                    sprintf(buf, "Play Failed: 0x%lX", (unsigned long)hr);
                    g_currentState->comErrorMsg = buf;
                    g_currentState->metadataChanged = true;
                }
                break;
                
            // -- PLAYBACK ERROR ------------------------------------------------------
            // Real playback errors (codec issues, network failures, etc.)
            case MFP_EVENT_TYPE_ERROR:  // = 10
                if (g_currentState) {
                    std::lock_guard<std::mutex> lock(g_currentState->mtx);
                    g_currentState->hasComError.store(true);
                    g_currentState->lastComHr = hr;
                    char buf[128];
                    sprintf(buf, "MF Error: 0x%lX", (unsigned long)hr);
                    g_currentState->comErrorMsg = buf;
                    g_currentState->metadataChanged = true;
                }
                break;
        }
    }
private:
    LONG m_refCount;
};

static RadioPlayerCallback* g_pCallback = NULL;

// ============================================================================
// C-STYLE API — Called from Haxe via @:native bindings (Windows)
// ============================================================================
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

    void RP_Stop() { 
        if (g_pPlayer) g_pPlayer->Stop(); 
    }

    void RP_SetVolume(float v) { 
        if (g_pPlayer) g_pPlayer->SetVolume(v); 
    }

    void RP_Shutdown() {
        if (g_pPlayer) { g_pPlayer->Shutdown(); g_pPlayer->Release(); g_pPlayer = NULL; }
        if (g_pCallback) { g_pCallback->Release(); g_pCallback = NULL; }
        if (g_pCurrentMediaItem) { g_pCurrentMediaItem->Release(); g_pCurrentMediaItem = NULL; }
        if (g_mfStarted) { CoUninitialize(); g_mfStarted = false; }
        g_currentUrl.clear();
    }

    bool RP_IsMfStopped() {
        if (g_currentState) return g_currentState->isMfStopped.load();
        return false;
    }
}
#else
// ============================================================================
// STUB IMPLEMENTATIONS FOR NON-WINDOWS C++ TARGETS (Android, Linux, etc.)
// ============================================================================
// These stubs allow the class to compile and link on all C++ platforms.
// Audio playback on these platforms requires platform-specific implementation.
// Current behavior: RP_Init() returns false, all playback functions are no-ops.
extern "C" {
    bool RP_Init() { return false; }
    bool RP_SetURL(const char* url) { return false; }
    bool RP_Play() { return false; }
    void RP_Stop() {}
    void RP_SetVolume(float v) {}
    void RP_Shutdown() {}
    bool RP_IsMfStopped() { return true; }
}
#endif

// ============================================================================
// URL PARSER
// ============================================================================
// Extracts scheme, host, port, path from a URL string.
// Supports http:// and https:// schemes.
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
// ICY METADATA PARSER
// ============================================================================
// Extracts StreamTitle from ICY metadata block.
// Format: StreamTitle=\'Artist - Track\';
// Splits on " - " separator if present.
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
// WORKER THREAD — Metadata Extraction (WinHTTP on Windows, idle on others)
// ============================================================================
// This thread does NOT play audio. It only:
//   1. Opens HTTP connection with icy-metadata: 1 header
//   2. Reads icy-metaint from response headers
//   3. Skips audio chunks (metaint bytes at a time)
//   4. Reads metadata length byte + metadata block
//   5. Parses StreamTitle and notifies Haxe via metadataChanged flag
//
// Audio playback is handled independently by WMF/MFPlay (Windows)
// or platform-specific APIs (other targets).
//
// On non-Windows C++ targets, this thread simply sleeps in a loop
// until isRunning is set to false. No network I/O is performed.
static void _netradio_worker_func(void* haxePtr) {
    NetRadioState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
        std::map<void*, NetRadioState*>::iterator it = _netradio_map.find(haxePtr);
        if (it != _netradio_map.end()) st = it->second;
    }
    if (!st) return;
    
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
        { std::lock_guard<std::mutex> lock(st->mtx); url = st->streamUrl; }
        
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
        if (!hSession) { continue; }
        
        std::wstring wHost(parsed.host.begin(), parsed.host.end());
        hConnect = WinHttpConnect(hSession, wHost.c_str(), parsed.port, 0);
        if (!hConnect) { WinHttpCloseHandle(hSession); continue; }
        
        std::wstring wPath(parsed.path.begin(), parsed.path.end());
        DWORD flags = parsed.isHttps ? WINHTTP_FLAG_SECURE : 0;
        hRequest = WinHttpOpenRequest(hConnect, L"GET", wPath.c_str(), NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
        if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); continue; }
        
        // Save hRequest so main thread can cancel blocking reads via RP_CancelRequest()
        {
            std::lock_guard<std::mutex> lock(st->hRequestMtx);
            st->hRequest = hRequest;
        }
        
        WinHttpAddRequestHeaders(hRequest, L"icy-metadata: 1", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        DWORD secFlags = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &secFlags, sizeof(secFlags));
        
        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) goto connection_lost;
        if (!WinHttpReceiveResponse(hRequest, NULL)) goto connection_lost;
        
        // Read icy-metaint header (bytes between metadata blocks)
        int metaint = 0;
        {
            WCHAR buf[256] = {0}; DWORD bufLen = sizeof(buf);
            const wchar_t metaintHeader[] = L"icy-metaint";
            if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CUSTOM, metaintHeader, buf, &bufLen, NULL)) {
                std::wstring ws(buf); std::string s(ws.begin(), ws.end());
                try { metaint = std::stoi(s); } catch (...) {}
            }
        }
        
        { std::lock_guard<std::mutex> lock(st->mtx); st->isConnected = true; st->hasError = false; st->errorMsg = ""; st->metadataChanged = true; }
        
        // === Metadata reading loop ===
        // Wrapped in braces to allow goto over std::string lastRawMeta (C++ restriction)
        {
            std::string lastRawMeta;
            while (st->isRunning.load() && st->shouldPlay.load()) {
                if (st->shouldStop.load()) { st->shouldStop.store(false); st->shouldPlay.store(false); break; }
                
                DWORD bytesAvailable = 0;
                if (!WinHttpQueryDataAvailable(hRequest, &bytesAvailable)) break;
                if (bytesAvailable == 0) { std::this_thread::sleep_for(std::chrono::milliseconds(50)); continue; }
                
                if (metaint > 0) {
                    // Skip audio chunk (metaint bytes)
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
                    
                    // Read metadata length byte (length = byte * 16)
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
                    // No ICY metadata — just drain the stream to keep connection alive
                    char discardBuf[8192]; DWORD bytesRead = 0;
                    DWORD chunkSize = (bytesAvailable < sizeof(discardBuf)) ? bytesAvailable : sizeof(discardBuf);
                    if (!WinHttpReadData(hRequest, discardBuf, chunkSize, &bytesRead)) break;
                    std::this_thread::sleep_for(std::chrono::milliseconds(200));
                }
            }
        }
        
    connection_lost:
        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->isConnected = false;
        }
        
        // Safe cleanup of hRequest
        {
            std::lock_guard<std::mutex> lock(st->hRequestMtx);
            if (st->hRequest != NULL) {
                WinHttpCloseHandle(st->hRequest);
                st->hRequest = NULL;
            }
        }
        if (hConnect) { WinHttpCloseHandle(hConnect); hConnect = NULL; }
        if (hSession) { WinHttpCloseHandle(hSession); hSession = NULL; }
        
        // === RECONNECT DELAY WITH EXPONENTIAL BACKOFF ===
        if (st->shouldPlay.load() && st->isRunning.load()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            
            // Increment reconnect counter
            st->reconnectAttempts++;
            
            // Calculate delay with exponential backoff
            int baseDelayMs = 1000;  // 1 second base
            int maxDelayMs = (int)(st->pollInterval * 1000);  // Cap at pollInterval (e.g., 5000ms)
            
            // Exponential: 2^attempts * baseDelay
            int delayMs = baseDelayMs * (1 << st->reconnectAttempts);
            if (delayMs > maxDelayMs) delayMs = maxDelayMs;
            
            // Add jitter +/-20% to prevent thundering herd
            int jitterRange = delayMs / 5;  // 20%
            int jitter = (rand() % (jitterRange * 2 + 1)) - jitterRange;
            delayMs += jitter;
            
            // Log retry attempt
            char errBuf[128];
            sprintf(errBuf, "Connection lost (retry #%d in %dms)", st->reconnectAttempts, delayMs);
            st->errorMsg = errBuf;
            st->metadataChanged = true;
            
            // Wait with isRunning check
            for (int w = 0; w < delayMs / 100 && st->isRunning.load(); w++) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
    }
    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);
#else
    // Non-Windows C++ targets: worker thread is idle.
    // No WinHTTP available; metadata extraction requires platform-specific
    // HTTP client (e.g., libcurl, Android HttpURLConnection via JNI).
    while (st->isRunning.load()) std::this_thread::sleep_for(std::chrono::milliseconds(500));
#endif
    st->isRunning.store(false);
}

// ============================================================================
// CANCEL REQUEST — Unblocks WinHttpReadData on dispose()
// ============================================================================
// Called from the MAIN thread before join() to prevent UI freeze.
// WinHttpCloseHandle() causes any pending WinHttpReadData() to fail
// with ERROR_WINHTTP_OPERATION_CANCELLED, allowing the worker thread
// to exit cleanly.
// On non-Windows targets, this is a no-op (no blocking I/O to cancel).
extern "C" void RP_CancelRequest(void* haxePtr) {
    NetRadioState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
        std::map<void*, NetRadioState*>::iterator it = _netradio_map.find(haxePtr);
        if (it != _netradio_map.end()) st = it->second;
    }
    if (st) {
#ifdef _WIN32
        std::lock_guard<std::mutex> lock(st->hRequestMtx);
        if (st->hRequest) {
            WinHttpCloseHandle(st->hRequest);
            st->hRequest = NULL;
        }
#endif
    }
}
')
#end

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     NET RADIO PLAYER ATOM v6.1                            ║
* ║                     (Internet Radio Metadata + Audio Playback)            ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Multi-platform internet radio player with conditional compilation:       ║
* ║                                                                           ║
* ║  ┌─────────────────┬──────────────────────────────────────────────────┐   ║
* ║  │ PLATFORM        │ IMPLEMENTATION                                   │   ║
* ║  ├─────────────────┼──────────────────────────────────────────────────┤   ║
* ║  │ Windows (C++)   │ WinHTTP worker thread (ICY metadata extraction)  │   ║
* ║  │                 │ + WMF/MFPlay pipeline (audio playback)           │   ║
* ║  │                 │ Full dual-engine architecture                    │   ║
* ║  ├─────────────────┼──────────────────────────────────────────────────┤   ║
* ║  │ Android (C++)   │ Stub C++ functions (compile-safe, no-op)         │   ║
* ║  │                 │ Worker thread runs idle (no WinHTTP)             │   ║
* ║  │                 │ Audio engine not available (RP_Init returns false)│   ║
* ║  │                 │ Future: Android MediaPlayer via JNI              │   ║
* ║  ├─────────────────┼──────────────────────────────────────────────────┤   ║
* ║  │ HTML5 (JS)      │ js.html.Audio element for playback               │   ║
* ║  │                 │ No ICY metadata (browser CORS limitation)        │   ║
* ║  │                 │ Volume capped at 0.0-1.0 (browser limitation)    │   ║
* ║  └─────────────────┴──────────────────────────────────────────────────┘   ║
* ║                                                                           ║
* ║  Windows dual-engine architecture (detailed):                             ║
* ║    • WinHTTP worker thread — extracts ICY metadata (title/artist/track)   ║
* ║    • WMF/MFPlay pipeline — plays the actual audio stream                  ║
* ║                                                                           ║
* ║  These two engines are INDEPENDENT consumers of the same URL:             ║
* ║    - WinHTTP reads the stream, skips audio bytes, parses metadata         ║
* ║    - MFPlay receives the URL via CreateMediaItemFromURL() and plays it    ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    NETRadioPlayerAtom                               │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  A) COMPUTE MODULE (Haxe Main Thread — update(dt))           │   │  ║
* ║  │  │     ─────────────────────────────────────────                │   │  ║
* ║  │  │     1. readInputs()                                          │   │  ║
* ║  │  │        - stream_url, poll_interval, playCtrl, volume         │   │  ║
* ║  │  │     2. pollCppState() [C++ targets only]                     │   │  ║
* ║  │  │        - Read metadata from C++ NetRadioState                │   │  ║
* ║  │  │        - Read COM errors from MF callbacks                   │   │  ║
* ║  │  │     3. MF Stop/Play sequencing [Windows C++ only]            │   │  ║
* ║  │  │        - Wait for MFP_EVENT_TYPE_STOP (flag isMfStopped)     │   │  ║
* ║  │  │        - Delay 1s before next SetURL (pendingSetUrlDelay)    │   │  ║
* ║  │  │        - Guarantees STA apartment (no Timer.delay)           │   │  ║
* ║  │  │     4. JS Audio error checking [HTML5 only]                  │   │  ║
* ║  │  │        - Monitor audio element error state                   │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  B) WORKER THREAD (C++ — _netradio_worker_func)              │   │  ║
* ║  │  │     ─────────────────────────────────────────                │   │  ║
* ║  │  │     Windows (WinHTTP):                                       │   │  ║
* ║  │  │       1. Parse URL (scheme/host/port/path)                   │   │  ║
* ║  │  │       2. Open HTTP connection with icy-metadata: 1           │   │  ║
* ║  │  │       3. Read icy-metaint header                             │   │  ║
* ║  │  │       4. Loop: skip metaint audio bytes, read metadata       │   │  ║
* ║  │  │       5. Parse StreamTitle -> title/artist/track              │   │  ║
* ║  │  │       6. Write to NetRadioState (mutex-protected)            │   │  ║
* ║  │  │       7. On disconnect: exponential backoff, reconnect       │   │  ║
* ║  │  │     Non-Windows C++ (Android, etc.):                         │   │  ║
* ║  │  │       - Thread sleeps in idle loop (no network I/O)          │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  C) AUDIO PIPELINE (Platform-specific)                       │   │  ║
* ║  │  │     ─────────────────────────────────                        │   │  ║
* ║  │  │     Windows (WMF/MFPlay):                                    │   │  ║
* ║  │  │       Main Thread (STA):                                     │   │  ║
* ║  │  │         RP_SetURL() -> CreateMediaItemFromURL()               │   │  ║
* ║  │  │       MF Thread (callback):                                  │   │  ║
* ║  │  │         MFP_EVENT_TYPE_MEDIAITEM_CREATED -> SetMediaItem()    │   │  ║
* ║  │  │         MFP_EVENT_TYPE_MEDIAITEM_SET     -> Play()            │   │  ║
* ║  │  │         MFP_EVENT_TYPE_STOP              -> isMfStopped=true  │   │  ║
* ║  │  │         MFP_EVENT_TYPE_PLAY              -> log err if fail   │   │  ║
* ║  │  │         MFP_EVENT_TYPE_ERROR             -> log HRESULT       │   │  ║
* ║  │  │     Android (C++ stubs):                                     │   │  ║
* ║  │  │       - All RP_* functions return false / no-op              │   │  ║
* ║  │  │       - Future: JNI bridge to android.media.MediaPlayer      │   │  ║
* ║  │  │     HTML5 (js.html.Audio):                                   │   │  ║
* ║  │  │       - audio.src = url; audio.play(); audio.pause();        │   │  ║
* ║  │  │       - Volume via audio.volume (0.0-1.0 range)              │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  D) DATABANK (Haxe)                                          │   │  ║
* ║  │  │     ─────────────────────                                    │   │  ║
* ║  │  │     _lastUrl, _currentUrl         — URL tracking             │   │  ║
* ║  │  │     _lastTitle/Artist/Track       — Last metadata values     │   │  ║
* ║  │  │     _lastError, _lastState        — Error state              │   │  ║
* ║  │  │     _isWaitingForStop             — MF stop sequencing       │   │  ║
* ║  │  │     _pendingSetUrlDelay           — Delay timer (dt-based)   │   │  ║
* ║  │  │     _pendingUrlToLoad             — URL queued after stop    │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  E) FACE (DeviceView)                                        │   │  ║
* ║  │  │     ─────────────────────                                    │   │  ║
* ║  │  │     NETRadioPlayerWidget (minimal placeholder)               │   │  ║
* ║  │  │     Shows error state via border color change                │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     STOP -> PLAY SEQUENCING (Windows)                     ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  IMFPMediaPlayer::Stop() is ASYNCHRONOUS. If Play() or SetURL() is        ║
* ║  called before the stop completes, we get a race condition that can       ║
* ║  hang the MF state machine.                                               ║
* ║                                                                           ║
* ║  Solution:                                                                ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  stopAudio()                                                     │     ║
* ║  │    ├── isMfStopped.store(false)                                  │     ║
* ║  │    └── nativeStop() -> g_pPlayer->Stop()                         │     ║
* ║  │         │                                                        │     ║
* ║  │         ▼                                                        │     ║
* ║  │  update(dt) polling loop                                         │     ║
* ║  │    └── while (!RP_IsMfStopped()) {  wait  }                      │     ║
* ║  │         │                                                        │     ║
* ║  │         ▼  (MFP_EVENT_TYPE_STOP fires on MF thread)              │     ║
* ║  │  _isWaitingForStop = false                                       │     ║
* ║  │  _pendingSetUrlDelay = 1.0  (1 second safety margin)             │     ║
* ║  │         │                                                        │     ║
* ║  │         ▼  (dt-based countdown, runs on MAIN thread)             │     ║
* ║  │  nativeSetURL(newUrl)                                            │     ║
* ║  │    └── CreateMediaItemFromURL() -> MEDIAITEM_CREATED -> Play()   │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
* ║                                                                           ║
* ║  IMPORTANT: All MF calls happen in update(dt), which runs on the          ║
* ║  MAIN thread — the SAME thread where RP_Init() called                     ║
* ║  CoInitializeEx(COINIT_APARTMENTTHREADED). This guarantees correct        ║
* ║  STA apartment usage. NO haxe.Timer.delay is used.                        ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                      THREAD SAFETY (Windows C++)                          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌────────────────────────────┐      ┌──────────────────────────────┐     ║
* ║  │  WinHTTP Worker Thread     │      │  MF Thread (callback)        │     ║
* ║  │  ─────────────────────     │      │  ──────────────────────      │     ║
* ║  │  Writes:                   │      │  Writes:                     │     ║
* ║  │  • title/artist/track      │      │  • isMfStopped (atomic)      │     ║
* ║  │  • rawMetadata             │      │  • hasComError (atomic)      │     ║
* ║  │  • isConnected             │      │  • comErrorMsg               │     ║
* ║  │  • hasError/errorMsg       │      │                              │     ║
* ║  │  (all under st->mtx)       │      │  (under st->mtx for strings) │     ║
* ║  └─────────────┬──────────────┘      └──────────────┬───────────────┘     ║
* ║                │                                    │                     ║
* ║                ▼                                    ▼                     ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  NetRadioState (shared)                                          │     ║
* ║  │  • mtx (mutex) — protects string fields                          │     ║
* ║  │  • hRequestMtx — protects HINTERNET handle                       │     ║
* ║  │  • atomic<bool> — lock-free flags                                │     ║
* ║  └────────────────────────────┬─────────────────────────────────────┘     ║
* ║                               │                                           ║
* ║                               ▼                                           ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  Haxe Main Thread (update/pollCppState)                          │     ║
* ║  │  • Reads metadata under st->mtx                                  │     ║
* ║  │  • Reads atomic flags directly                                   │     ║
* ║  │  • Writes to output contacts (setValueSilent + propagate)        │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                   SAFE DISPOSE PATTERN (Windows C++)                      ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  WinHttpReadData() is a BLOCKING call. If the network hangs, the worker   ║
* ║  thread will be stuck inside it. A plain st->isRunning.store(false) +     ║
* ║  st->worker->join() would DEADLOCK the UI thread.                         ║
* ║                                                                           ║
* ║  Solution:                                                                ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  dispose()                                                       │     ║
* ║  │    ├── RP_CancelRequest(this)                                    │     ║
* ║  │    │     └── WinHttpCloseHandle(hRequest)                        │     ║
* ║  │    │           └── WinHttpReadData() returns with error          │     ║
* ║  │    │                 └── worker thread exits cleanly             │     ║
* ║  │    ├── stopAudio() + nativeShutdown()                            │     ║
* ║  │    └── st->worker->join()  <- now guaranteed to complete         │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                 EXPONENTIAL BACKOFF (v5.6+)                               ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  On connection loss, delay before reconnect:                              ║
* ║                                                                           ║
* ║  Attempt 1:  1.0s +/- 0.2s                                                ║
* ║  Attempt 2:  2.0s +/- 0.4s                                                ║
* ║  Attempt 3:  4.0s +/- 0.8s                                                ║
* ║  Attempt 4:  8.0s +/- 1.6s                                                ║
* ║  Attempt 5: 16.0s +/- 3.2s                                                ║
* ║  Attempt 6: 32.0s +/- 6.4s                                                ║
* ║  Attempt 7+: 60.0s +/- 12s (capped at pollInterval)                       ║
* ║                                                                           ║
* ║  On successful connection: counter resets to 0                            ║
* ║                                                                           ║
* ║  Benefits:                                                                ║
* ║  • Fast recovery for short outages                                        ║
* ║  • Reduced load on server during long outages                             ║
* ║  • Jitter prevents thundering herd with multiple clients                  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    APPLICATION                                            ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  • Internet radio streaming with real-time metadata display               ║
* ║  • ICY (Shoutcast/Icecast) protocol support (Windows only)                ║
* ║  • Automatic reconnection on stream drop (Windows only)                   ║
* ║  • Volume control (0.0-2.0 Windows, 0.0-1.0 HTML5)                       ║
* ║  • Error reporting via "state" and "error" output contacts                ║
* ║  • Hot URL switching with proper MF stop/play sequencing (Windows)        ║
* ║  • Cross-platform compilation: Windows, Android, HTML5                    ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    VERSION HISTORY                                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v6.1 (Current) — Idempotent init (Task 96, Fix C)                        ║
* ║    • ADDED: map-keyed idempotency guard in init() — the double            ║
* ║      init() in the constructor flow (DriverManager.register()             ║
* ║      callback + explicit call) used to allocate a SECOND                  ║
* ║      NetRadioState + worker thread and overwrite the map entry,           ║
* ║      orphaning state #1 and its thread for the process lifetime.          ║
* ║    • NOTE: RP_Init() was already idempotent (g_mfStarted) — the           ║
* ║      double WMF init was harmless; the leak was state + thread only.      ║
* ║                                                                           ║
* ║  v6.0 — Multi-Platform Conditional Compilation                            ║
* ║    • ADDED: #if (cpp || js) top-level guard for cross-platform support    ║
* ║    • ADDED: #if (cpp && windows) guard on @:buildXml (WMF libs)           ║
* ║    • ADDED: #if cpp guard on @:headerCode and @:cppFileCode               ║
* ║    • ADDED: C++ stub RP_* functions for non-Windows targets (#else)       ║
* ║    • ADDED: HTML5 js.html.Audio implementation for playback               ║
* ║    • ADDED: Platform-specific init/update/dispose/readInputs paths        ║
* ║    • ADDED: Platform support matrix in class documentation                ║
* ║    • RESOLVED: Android compilation errors (undeclared RP_* identifiers)   ║
* ║    • RESOLVED: Android linker errors (mf.lib, ole32.lib, etc.)            ║
* ║                                                                           ║
* ║  v5.6 — Exponential Backoff for Reconnect                                 ║
* ║    • ADDED: reconnectAttempts counter in NetRadioState                    ║
* ║    • ADDED: Exponential delay calculation (2^attempts * 1s)               ║
* ║    • ADDED: Jitter +/-20% to prevent thundering herd                      ║
* ║    • ADDED: Cap at pollInterval (max delay)                               ║
* ║    • ADDED: Reset counter on successful connection                        ║
* ║    • ADDED: Logging of retry attempt number                               ║
* ║                                                                           ║
* ║  v5.5 — MFPlay Event Types Correction                                     ║
* ║    • CHANGED: case 8 (MEDIAITEM_CLEARED) to MFP_EVENT_TYPE_STOP (=2)      ║
* ║    • CHANGED: case 0 (PLAY) now only reports error if !succeeded          ║
* ║    • ADDED: MFP_EVENT_TYPE_ERROR (=10) handling for real playback errors  ║
* ║                                                                           ║
* ║  v5.4 — RP_IsMfStopped() Signature Adjustment                             ║
* ║    • Changed RP_IsMfStopped() to take no arguments (uses g_currentState)  ║
* ║    • Avoids Haxe .mPtr issue with Bool primitives                         ║
* ║                                                                           ║
* ║  v5.3 — Bool .mPtr Issue Resolution                                       ║
* ║    • Introduced dedicated C++ function RP_IsMfStopped()                   ║
* ║    • Replaced inline __cpp__ Bool write with safe extern function         ║
* ║                                                                           ║
* ║  v5.2 — MSVC Compilation Adjustments                                      ║
* ║    • Replaced MFP_EVENT_TYPE_PLAYBACK_STOPPED with integer literal 8      ║
* ║    • Wrapped metadata loop in braces for goto over std::string            ║
* ║    • Used explicit iterator type for std::map                             ║
* ║                                                                           ║
* ║  v5.1 — Thread-Safe Stop/Play + No UI Freeze                              ║
* ║    • ADDED: isMfStopped flag + MFP_EVENT_TYPE_STOP handling               ║
* ║    • ADDED: RP_CancelRequest() for safe dispose                           ║
* ║    • ADDED: COM error logging (hasComError, comErrorMsg)                  ║
* ║    • REMOVED: haxe.Timer.delay (replaced with dt-based delay)             ║
* ║    • GUARANTEED: STA apartment for all MF calls via update(dt)            ║
* ║                                                                           ║
* ║  v5.0 — Initial Dual-Engine Architecture                                  ║
* ║    • WinHTTP worker thread for ICY metadata extraction                    ║
* ║    • WMF/MFPlay pipeline for audio playback                               ║
* ║    • Asynchronous MF event handling via RadioPlayerCallback               ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class NETRadioPlayerAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    /** Duration of "updated" pulse on metadata change (seconds) */
    private static inline var PULSE_DURATION:Float = 0.1;
    /** Default metadata poll/reconnect interval (seconds) — also MAX cap for backoff */
    private static inline var DEFAULT_POLL_INTERVAL:Float = 5.0;

    // =========================================================================
    // C++ NATIVE BINDINGS (C++ targets only)
    // =========================================================================
    #if cpp
    @:native("RP_Init") private static extern function nativeInit():Bool;
    @:native("RP_SetURL") private static extern function nativeSetURL(url:ConstCharStar):Bool;
    @:native("RP_Play") private static extern function nativePlay():Bool;
    @:native("RP_Stop") private static extern function nativeStop():Void;
    @:native("RP_SetVolume") private static extern function nativeSetVolume(v:Float):Void;
    @:native("RP_Shutdown") private static extern function nativeShutdown():Void;
    /** Query whether MF player has fully stopped (async stop completion) */
    @:native("RP_IsMfStopped") private static extern function nativeIsMfStopped():Bool;
    #end

    // =========================================================================
    // HTML5 AUDIO ELEMENT (JS target only)
    // =========================================================================
    #if js
    /** Browser Audio element for stream playback */
    private var _audioElement:Audio;
    /** Flag indicating whether the audio element has a valid source loaded */
    private var _jsAudioReady:Bool = false;
    #end

    // =========================================================================
    // DATABANK — Last known values (for change detection)
    // =========================================================================
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

    // =========================================================================
    // MF STOP/PLAY SEQUENCING STATE (Windows C++ only)
    // =========================================================================
    #if cpp
    /** Countdown timer (seconds) before next SetURL after stop */
    private var _pendingSetUrlDelay:Float = 0.0;
    /** True while waiting for MFP_EVENT_TYPE_STOP from MF */
    private var _isWaitingForStop:Bool = false;
    /** URL queued to be loaded after stop completes */
    private var _pendingUrlToLoad:String = null;
    #end

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
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
            null, id, "NETRadioPlayerAtom", true
        );
        init();
    }

    // =========================================================================
    // LIFECYCLE — Driver Interface
    // =========================================================================
    /**
    * Initialize audio engine and spawn the metadata worker thread (C++ only).
    *
    * Platform behavior:
    *   Windows C++: RP_Init() initializes WMF on the main thread (STA apartment).
    *                Spawns background worker thread for ICY metadata extraction.
    *   Android C++: RP_Init() returns false (stub). Worker thread runs idle.
    *                Audio engine is not available; class compiles but does not play.
    *   HTML5 JS:    Creates js.html.Audio element for browser-based playback.
    *                No metadata extraction (browser CORS limitation for ICY).
    */
    override public function init():Void
    {
        #if cpp
        _isWmfInitialized = nativeInit();
        if (!_isWmfInitialized)
        {
            #if windows
            trace("NETRadioPlayer: WMF Initialization failed!");
            #else
            trace("NETRadioPlayer: Native audio engine not available on this platform (stub mode).");
            #end
        }
        untyped __cpp__('
            // FIX C (v6.1, Task 96) — IDEMPOTENCY GUARD.
            // init() runs TWICE in the constructor flow: once via
            // DriverManager.register() (the Atom base constructor,
            // isActive=true, calls driver.init() — a VIRTUAL call that
            // lands here before the derived constructor body runs) and
            // once explicitly from the constructor body. The second
            // call used to allocate a SECOND NetRadioState + worker
            // thread and OVERWRITE the map entry — orphaning state #1
            // and its thread for the lifetime of the process (idle
            // loop on atomics: a silent leak, no crash) while also
            // re-pointing the global g_currentState. Map-keyed guard:
            // if this atom instance (mPtr) already owns a state, init()
            // is a no-op. RP_Init() above is already idempotent
            // (g_mfStarted), so WMF is unaffected either way.
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                if (_netradio_map.find((void*){0}.mPtr) != _netradio_map.end()) {
                    return; // Already initialized — idempotent no-op.
                }
            }
            NetRadioState* st = new NetRadioState();
            st->isRunning.store(true);
            st->shouldPlay.store(false);
            st->shouldStop.store(false);
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                _netradio_map[(void*){0}.mPtr] = st;
                g_currentState = st;
            }
            st->worker = new std::thread(_netradio_worker_func, (void*){0}.mPtr);
        ', this);
        #elseif js
        _audioElement = new Audio();
        _audioElement.crossOrigin = "anonymous";
        _audioElement.preload = "none";
        _isWmfInitialized = true;
        _jsAudioReady = false;
        trace("NETRadioPlayer: HTML5 Audio element initialized.");
        #end
    }

    /**
    * Main update loop. Called every frame by DriverManager.
    *
    * Responsibilities:
    *   1. Read input contacts (URL, playCtrl, volume, poll_interval)
    *   2. Poll C++ state for new metadata and COM errors (C++ targets)
    *   3. Manage MF stop/play sequencing (Windows C++ only)
    *   4. Monitor audio element errors (HTML5 only)
    *   5. Update pulse timers
    *
    * CRITICAL (Windows): All MF calls (nativeSetURL, nativePlay, nativeStop)
    * happen here on the MAIN thread — the same thread where RP_Init() called
    * CoInitializeEx(COINIT_APARTMENTTHREADED). This guarantees correct
    * STA apartment usage.
    *
    * @param dt Delta time in seconds
    */
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        
        readInputs();
        
        #if cpp
        pollCppState();
        #end
        
        updatePulseTimers(dt);
        
        #if cpp
        // === PHASE 1: Wait for MF to fully stop asynchronously ===
        if (_isWaitingForStop)
        {
            var isStopped:Bool = nativeIsMfStopped();
            if (isStopped)
            {
                _isWaitingForStop = false;
                _pendingSetUrlDelay = 1.0;  // 1 second safety margin
                trace("NETRadioPlayer: MF fully stopped, waiting 1s before next action...");
            }
        }
        // === PHASE 2: Handle delayed SetURL (runs on Main Thread — STA safe) ===
        else if (_pendingSetUrlDelay > 0)
        {
            _pendingSetUrlDelay -= dt;
            if (_pendingSetUrlDelay <= 0)
            {
                _pendingSetUrlDelay = 0;
                if (_pendingUrlToLoad != null)
                {
                    trace("NETRadioPlayer: Loading delayed URL: " + _pendingUrlToLoad);
                    var success = nativeSetURL(_pendingUrlToLoad);
                    if (!success) setError(true, "WMF SetURL failed");
                    _pendingUrlToLoad = null;
                }
                else
                {
                    // No URL to load — check if we should just resume playback
                    var playC = getInput("playCtrl");
                    if (playC != null && playC.value == true)
                    {
                        trace("NETRadioPlayer: Resuming playback...");
                        nativePlay();
                    }
                }
            }
        }
        #elseif js
        // === HTML5: Monitor audio element for errors ===
        if (_audioElement != null && _audioElement.error != null)
        {
            var errCode = _audioElement.error.code;
            var errMsg = "HTML5 Audio error (code " + errCode + ")";
            if (errCode == 1) errMsg = "Audio load aborted";
            else if (errCode == 2) errMsg = "Audio network error";
            else if (errCode == 3) errMsg = "Audio decode error";
            else if (errCode == 4) errMsg = "Audio format not supported";
            setError(true, errMsg);
        }
        #end
    }

    /**
    * Safe disposal pattern:
    *
    * Windows C++:
    *   1. RP_CancelRequest() — unblocks WinHttpReadData() in worker thread
    *   2. stopAudio() + nativeShutdown() — releases WMF resources
    *   3. st->worker->join() — now guaranteed to complete quickly
    *   4. Delete C++ state
    *
    * Android C++:
    *   1. RP_CancelRequest() — no-op (no blocking I/O)
    *   2. stopAudio() + nativeShutdown() — no-op (stubs)
    *   3. st->worker->join() — completes quickly (idle loop exits)
    *   4. Delete C++ state
    *
    * HTML5 JS:
    *   1. Pause and release Audio element
    *   2. Clear source URL
    */
    override public function dispose():Void
    {
        #if cpp
        // Step 1: Unblock worker thread (prevents UI freeze on dispose)
        untyped __cpp__('RP_CancelRequest((void*){0}.mPtr);', this);
        
        // Step 2: Stop audio and shutdown audio engine
        stopAudio();
        nativeShutdown();
        
        // Step 3: Clean up C++ state and join worker thread
        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                std::map<void*, NetRadioState*>::iterator it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) {
                    st = it->second;
                    _netradio_map.erase(it);
                    if (g_currentState == st) g_currentState = nullptr;
                }
            }
            if (st) {
                st->shouldStop.store(true); st->shouldPlay.store(false); st->isRunning.store(false);
                if (st->worker && st->worker->joinable()) st->worker->join();
                delete st->worker; delete st;
            }
        ', this);
        #elseif js
        // Step 1: Release HTML5 Audio element
        if (_audioElement != null)
        {
            _audioElement.pause();
            _audioElement.removeAttribute("src");
            _audioElement.load();
            _audioElement = null;
        }
        _jsAudioReady = false;
        #end
        
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // INPUT READING
    // =========================================================================
    /**
    * Read all input contacts and propagate changes to audio engine or C++ state.
    *
    * Inputs:
    *   - stream_url (String)    -> C++ st->streamUrl / JS audio.src
    *   - poll_interval (Float)  -> st->pollInterval (C++ only)
    *   - volume (Float)         -> nativeSetVolume() / audio.volume
    *   - playCtrl (Bool)        -> startAudio() / stopAudio()
    */
    private function readInputs():Void
    {
        var urlC = getInput("stream_url");
        if (urlC != null && urlC.value != null)
        {
            var newUrl:String = Std.string(urlC.value);
            if (newUrl != _lastUrl)
            {
                _lastUrl = newUrl;
                _currentUrl = "";
                #if cpp
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                        std::map<void*, NetRadioState*>::iterator it = _netradio_map.find((void*){0}.mPtr);
                        if (it != _netradio_map.end()) st = it->second;
                    }
                    if (st) { std::lock_guard<std::mutex> dataLock(st->mtx); st->streamUrl = std::string((const char*){1}.__s); }
                ', this, newUrl);
                #elseif js
                if (_audioElement != null)
                {
                    _audioElement.src = newUrl;
                    _jsAudioReady = (newUrl != "" && newUrl != null);
                }
                #end
            }
        }
        
        var volC = getInput("volume");
        if (volC != null && volC.value != null)
        {
            var newVol:Float = Std.parseFloat(Std.string(volC.value));
            if (!Math.isNaN(newVol) && newVol >= 0.0 && newVol <= 2.0)
            {
                _volume = newVol;
                #if cpp
                nativeSetVolume(_volume);
                #elseif js
                if (_audioElement != null)
                {
                    // Browser audio volume is clamped to 0.0-1.0
                    _audioElement.volume = Math.max(0.0, Math.min(1.0, _volume));
                }
                #end
            }
        }
        
        var playC = getInput("playCtrl");
        if (playC != null && playC.value != null)
        {
            var newPlay:Bool = (playC.value == true);
            if (newPlay != _lastPlayCtrl)
            {
                _lastPlayCtrl = newPlay;
                #if cpp
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                        std::map<void*, NetRadioState*>::iterator it = _netradio_map.find((void*){0}.mPtr);
                        if (it != _netradio_map.end()) st = it->second;
                    }
                    if (st) {
                        if ({1}) { st->shouldPlay.store(true); st->shouldStop.store(false); st->streamUrl = std::string((const char*){2}.__s); }
                        else { st->shouldStop.store(true); st->shouldPlay.store(false); }
                    }
                ', this, newPlay, _lastUrl);
                #end
                
                if (newPlay) startAudio();
                else stopAudio();
            }
        }
    }

    // =========================================================================
    // AUDIO CONTROL — Platform-Specific Stop/Play Sequencing
    // =========================================================================
    /**
    * Begin audio playback with proper stop sequencing.
    *
    * Windows C++:
    *   If URL has changed:
    *     - Initiate stop (if currently playing)
    *     - Queue new URL for loading after stop completes
    *   If URL is the same:
    *     - Resume playback directly via nativePlay()
    *   If already waiting for stop:
    *     - Just queue the URL (will be loaded when stop completes)
    *
    * Android C++:
    *   No-op (audio engine not available, _isWmfInitialized == false).
    *
    * HTML5 JS:
    *   Set audio source if URL changed, then call audio.play().
    */
    private function startAudio():Void
    {
        if (_lastUrl == "" || _lastUrl == null || !_isWmfInitialized) return;
        
        #if cpp
        // Already waiting for previous stop — just queue the action
        if (_isWaitingForStop)
        {
            trace("NETRadioPlayer: Still stopping, queuing action...");
            _pendingUrlToLoad = _lastUrl;
            return;
        }
        
        // URL changed — need to stop current playback first
        if (_currentUrl != _lastUrl)
        {
            trace("NETRadioPlayer: URL changed, initiating stop...");
            stopAudio();
            _pendingUrlToLoad = _lastUrl;
            _currentUrl = _lastUrl;
            return;
        }
        
        // Same URL — just resume
        trace("NETRadioPlayer: Resuming playback...");
        var success = nativePlay();
        if (!success) setError(true, "WMF Play failed");
        
        #elseif js
        if (_audioElement != null)
        {
            if (_currentUrl != _lastUrl)
            {
                _audioElement.src = _lastUrl;
                _currentUrl = _lastUrl;
                _jsAudioReady = true;
            }
            var playPromise = _audioElement.play();
            if (playPromise != null)
            {
                playPromise.then(function() {
                    trace("NETRadioPlayer: HTML5 playback started.");
                    setError(false, "");
                }).catchError(function(err:Dynamic) {
                    trace("NETRadioPlayer: HTML5 play() rejected: " + Std.string(err));
                    setError(true, "Play rejected: " + Std.string(err));
                });
            }
        }
        #end
    }

    /**
    * Begin stop sequence.
    *
    * Windows C++:
    *   1. Reset isMfStopped flag to false
    *   2. Call nativeStop() -> triggers async MF stop
    *   3. Set _isWaitingForStop = true
    *   4. update() will poll nativeIsMfStopped() until MF fires MFP_EVENT_TYPE_STOP
    *
    * Android C++:
    *   No-op (stubs).
    *
    * HTML5 JS:
    *   Pause the audio element immediately (synchronous).
    */
    private function stopAudio():Void
    {
        #if cpp
        _pendingSetUrlDelay = 0;
        _pendingUrlToLoad = null;
        
        // Reset stop flag before calling Stop
        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                std::map<void*, NetRadioState*>::iterator it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) st = it->second;
            }
            if (st) { st->isMfStopped.store(false); }
        ', this);
        
        nativeStop();
        _isWaitingForStop = true;  // Now wait for MFP_EVENT_TYPE_STOP
        
        #elseif js
        if (_audioElement != null)
        {
            _audioElement.pause();
        }
        #end
    }

    // =========================================================================
    // STATE POLLING — C++ to Haxe Data Transfer (C++ targets only)
    // =========================================================================
    #if cpp
    /**
    * Poll C++ NetRadioState for metadata changes and COM errors.
    *
    * Pattern (batched driver update):
    *   1. Read under st->mtx if metadataChanged flag is set
    *   2. Copy to local variables
    *   3. Clear metadataChanged flag in C++
    *   4. Compare with _last* fields and write to output contacts
    *   5. Single propagateCurrentValue() per output (not per change)
    *
    * Also reads hasComError flag set by MF callbacks (PLAY/ERROR events).
    *
    * On non-Windows C++ targets (Android, etc.), the metadata fields will
    * remain empty because the worker thread does not perform network I/O.
    */
    private function pollCppState():Void
    {
        var cppTitle:String = ""; var cppArtist:String = ""; var cppTrack:String = "";
        var cppRawMeta:String = ""; var cppError:String = ""; var cppHasError:Bool = false; var cppChanged:Bool = false;
        var cppComError:Bool = false; var cppComErrorMsg:String = "";
        
        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                std::map<void*, NetRadioState*>::iterator it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) st = it->second;
            }
            if (st) {
                std::lock_guard<std::mutex> dataLock(st->mtx);
                if (st->metadataChanged) {
                    {1} = ::String(st->title.c_str()); {2} = ::String(st->artist.c_str()); {3} = ::String(st->track.c_str());
                    {4} = ::String(st->rawMetadata.c_str()); {5} = ::String(st->errorMsg.c_str());
                    {6} = st->hasError; {7} = true; st->metadataChanged = false;
                }
                // Read COM/MF errors
                if (st->hasComError.load()) {
                    {8} = true;
                    {9} = ::String(st->comErrorMsg.c_str());
                    st->hasComError.store(false);
                    st->comErrorMsg = "";
                }
            }
        ', this, cppTitle, cppArtist, cppTrack, cppRawMeta, cppError, cppHasError, cppChanged, cppComError, cppComErrorMsg);
        
        // Report COM errors to Haxe
        if (cppComError)
        {
            trace("NETRadioPlayer COM Error: " + cppComErrorMsg);
            setError(true, cppComErrorMsg);
        }
        
        if (cppChanged)
        {
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
    #end

    // =========================================================================
    // OUTPUT HELPERS
    // =========================================================================
    /** Reset all metadata outputs to empty/default values */
    private function clearMetadata():Void
    {
        setOutput("title", ""); setOutput("artist", ""); setOutput("track", "");
        setOutput("raw_metadata", ""); setOutput("state", false); setOutput("error", "");
    }

    /**
    * Set error state and message.
    * @param hasError true = error state, false = normal state
    * @param errorMsg Human-readable error description
    */
    private function setError(hasError:Bool, errorMsg:String):Void
    {
        if (hasError != _lastState)
        {
            _lastState = hasError;
            setOutput("state", hasError);
        }
        if (errorMsg != _lastError)
        {
            _lastError = errorMsg;
            setOutput("error", errorMsg);
        }
    }

    /**
    * Write value to output contact using batched pattern:
    *   setValueSilent() + propagateCurrentValue()
    * This avoids triggering _propagate() for every intermediate write.
    */
    private function setOutput(name:String, value:Dynamic):Void
    {
        var c = getOutput(name);
        if (c != null) { c.setValueSilent(value); c.propagateCurrentValue(); }
    }

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    /**
    * Countdown "updated" pulse timer.
    * The "updated" output is a short-lived Bool pulse (PULSE_DURATION seconds)
    * that fires every time metadata changes.
    */
    private function updatePulseTimers(dt:Float):Void
    {
        if (_updatedTimer > 0) { 
            _updatedTimer -= dt; 
            if (_updatedTimer <= 0) { 
                var c = getOutput("updated"); 
                if (c != null) c.value = false; 
            } 
        }
    }
}
#end
