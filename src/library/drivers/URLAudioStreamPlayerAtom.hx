#if cpp
package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// LINKER FLAGS — Windows Media Foundation libraries (Windows C++ ONLY)
// ============================================================================
#if (cpp && windows)
@:buildXml('
<target id="haxe">
<lib name="mf.lib" />
<lib name="mfplat.lib" />
<lib name="mfuuid.lib" />
<lib name="ole32.lib" />
<lib name="shlwapi.lib" />
</target>
')
#end

@:cppFileCode('
#include <string>
#include <map>
#include <mutex>
#include <thread>
#include <atomic>
#include <algorithm>
#include <cstdlib>
#include <cstdint>
#include <chrono>

#if defined(_WIN32)
// v2.0.1 (Task 103, hotfix): winhttp.h does NOT include windows.h by itself -
// it expects the base Win32 types (LPVOID, DWORD, APIENTRY, ...) to be already
// declared. Without windows.h first, line 54 "typedef LPVOID HINTERNET;" dies
// with C4430/C2146/C2143. Same proven order as the retired NETRadio atom:
// windows.h THEN winhttp.h. WIN32_LEAN_AND_MEAN / NOMINMAX mirror the preamble
// of WMFStreamSession.h (its #ifndef guards make its own windows.h include a
// no-op), so ERROR/min/max stay clean for all headers parsed after this block.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#include "../../../../include/WMFStreamSession.h"
#else
// ========================================================================
// STUB IMPLEMENTATION FOR NON-WINDOWS PLATFORMS (Android, iOS, Linux)
// This prevents "unknown type name" errors during cross-platform compilation.
// ========================================================================
class WMFStreamSessionStub {
public:
enum class State { IDLE = 0, CONNECTING = 1, PLAYING = 2, STOPPING = 3, ERR = 4 };
WMFStreamSessionStub() {}
~WMFStreamSessionStub() {}
bool Play(const std::string& url) { return false; }
void Stop() {}
void SetVolume(float v) {}
State GetState() const { return State::IDLE; }
bool IsPlaying() const { return false; }
bool IsBuffering() const { return false; }
std::string GetErrorMessage() const { return "Audio not implemented on this platform yet"; }
bool CheckAndResetConnectionLost() { return false; }
bool CheckBufferingTimeout(unsigned int timeoutMs) { return false; }
};
// Alias to ensure existing Haxe __cpp__ blocks compile without modifications
using WMFStreamSession = WMFStreamSessionStub;
#endif

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
#ifdef TRUE
#undef TRUE
#endif
#ifdef FALSE
#undef FALSE
#endif
#ifdef CALLBACK
#undef CALLBACK
#endif
#ifdef WINAPI
#undef WINAPI
#endif
#ifdef CONST
#undef CONST
#endif
#ifdef _WIN32_
#undef _WIN32_
#endif
#ifdef WIN32_LEAN_AND_MEAN
#undef WIN32_LEAN_AND_MEAN
#endif
#ifdef NOMINMAX
#undef NOMINMAX
#endif

static std::map<void*, WMFStreamSession*> _urlaudio_sessions;
static std::mutex _urlaudio_sessions_mutex;

// ============================================================================
// v2.0 (Task 102, series URL_RADIO) — ICY METADATA WORKER.
// Transplanted from the retired NETRadioPlayerAtom and made per-instance.
// Reads the SAME stream URL the WMF audio session plays: connects with
// "icy-metadata: 1", reads icy-metaint, skips audio chunks, parses the ICY
// metadata block (StreamTitle -> artist/track). FULLY INDEPENDENT from the
// audio session — audio connection loss does not stop metadata extraction
// and vice versa; this worker reconnects with its own exponential backoff.
// ============================================================================
struct URLAudioMetaState {
    std::atomic<bool> shouldPlay;       // Worker should actively read stream
    std::atomic<bool> shouldStop;       // Worker should stop current session
    std::atomic<bool> isRunning;        // Worker thread is alive
    std::atomic<bool> urlChanged;       // URL switched mid-read -> reconnect
    std::string streamUrl;              // Current stream URL (protected by mtx)
    float pollInterval;                 // Reconnect delay cap in seconds (MAX)
    std::string title;                  // Parsed ICY title (protected by mtx)
    std::string artist;                 // Parsed ICY artist (protected by mtx)
    std::string track;                  // Parsed ICY track (protected by mtx)
    std::string rawMetadata;            // Raw ICY metadata string
    std::string errorMsg;               // Last error message (internal)
    bool hasError;                      // Error flag (internal)
    bool metadataChanged;               // Dirty flag for Haxe polling
    bool isConnected;                   // Connection status (internal)
    std::mutex mtx;                     // Protects string fields above
    std::thread* worker;                // Background thread handle
#ifdef _WIN32
    HINTERNET hRequest;                 // WinHTTP request handle (for cancellation)
    std::mutex hRequestMtx;             // Protects hRequest
#endif
    int reconnectAttempts;              // Exponential backoff counter

    URLAudioMetaState()
        : shouldPlay(false), shouldStop(false), isRunning(false),
          urlChanged(false), pollInterval(5.0f), hasError(false),
          metadataChanged(false), isConnected(false), worker(nullptr),
#ifdef _WIN32
          hRequest(NULL),
#endif
          reconnectAttempts(0) {}
};

// Global map: Haxe instance pointer -> metadata state
static std::map<void*, URLAudioMetaState*> _urlaudio_meta_map;
static std::mutex _urlaudio_meta_map_mutex;

// ============================================================================
// URL PARSER (transplant) — scheme/host/port/path, http/https
// ============================================================================
struct URLAudioParsedURL {
    std::string host;
    std::string path;
    uint16_t port;
    bool isHttps;
    bool valid;
    URLAudioParsedURL() : host(""), path("/"), port(80), isHttps(false), valid(false) {}
};

static URLAudioParsedURL urla_parse_url(const std::string& url) {
    URLAudioParsedURL result;
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
// ICY METADATA PARSER (transplant) — StreamTitle=Artist-Track format
// ============================================================================
static void urla_parse_icy_metadata(const std::string& meta, std::string& outTitle, std::string& outArtist, std::string& outTrack) {
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
// METADATA WORKER THREAD — WinHTTP (Windows), idle on other C++ targets
// ============================================================================
static void _urlaudio_meta_worker_func(void* haxePtr) {
    URLAudioMetaState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
        std::map<void*, URLAudioMetaState*>::iterator it = _urlaudio_meta_map.find(haxePtr);
        if (it != _urlaudio_meta_map.end()) st = it->second;
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

        URLAudioParsedURL parsed = urla_parse_url(url);
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

        // Save hRequest so the main thread can cancel blocking reads
        {
            std::lock_guard<std::mutex> lock(st->hRequestMtx);
            st->hRequest = hRequest;
        }

        WinHttpAddRequestHeaders(hRequest, L"icy-metadata: 1", (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
        DWORD secFlags = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &secFlags, sizeof(secFlags));

        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) goto meta_connection_lost;
        if (!WinHttpReceiveResponse(hRequest, NULL)) goto meta_connection_lost;

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

        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->isConnected = true; st->hasError = false; st->errorMsg = "";
            st->reconnectAttempts = 0; st->metadataChanged = true;
        }

        // === Metadata reading loop ===
        // Wrapped in braces to allow goto over std::string lastRawMeta (C++ restriction)
        {
            std::string lastRawMeta;
            while (st->isRunning.load() && st->shouldPlay.load()) {
                if (st->shouldStop.load()) { st->shouldStop.store(false); st->shouldPlay.store(false); break; }

                // v2.0: URL switched while connected -> drop this connection and
                // reconnect to the new stream (shouldPlay stays true).
                if (st->urlChanged.exchange(false)) break;

                DWORD bytesAvailable = 0;
                if (!WinHttpQueryDataAvailable(hRequest, &bytesAvailable)) break;
                if (bytesAvailable == 0) { std::this_thread::sleep_for(std::chrono::milliseconds(50)); continue; }

                if (metaint > 0) {
                    // Skip audio chunk (metaint bytes)
                    char audioBuf[8192]; DWORD toRead = metaint;
                    while (toRead > 0 && st->isRunning.load() && st->shouldPlay.load()) {
                        DWORD chunkSize = (toRead < sizeof(audioBuf)) ? toRead : sizeof(audioBuf);
                        DWORD bytesRead = 0;
                        if (!WinHttpReadData(hRequest, audioBuf, chunkSize, &bytesRead)) goto meta_connection_lost;
                        if (bytesRead == 0) {
                            std::this_thread::sleep_for(std::chrono::milliseconds(100));
                            DWORD avail = 0; WinHttpQueryDataAvailable(hRequest, &avail);
                            if (avail == 0) { std::this_thread::sleep_for(std::chrono::milliseconds(500)); WinHttpQueryDataAvailable(hRequest, &avail); if (avail == 0) goto meta_connection_lost; }
                            continue;
                        }
                        toRead -= bytesRead;
                    }

                    // Read metadata length byte (length = byte * 16)
                    char metaLenByte = 0; DWORD metaLenRead = 0;
                    if (!WinHttpReadData(hRequest, &metaLenByte, 1, &metaLenRead) || metaLenRead == 0) goto meta_connection_lost;
                    int metaLen = (unsigned char)metaLenByte * 16;

                    if (metaLen > 0) {
                        std::string metaBuf; metaBuf.resize(metaLen + 1, 0); DWORD metaRead = 0;
                        if (!WinHttpReadData(hRequest, &metaBuf[0], metaLen, &metaRead)) goto meta_connection_lost;
                        metaBuf[metaRead] = 0;
                        std::string rawMeta(metaBuf.c_str());

                        if (rawMeta != lastRawMeta && !rawMeta.empty()) {
                            lastRawMeta = rawMeta;
                            std::string newTitle, newArtist, newTrack;
                            urla_parse_icy_metadata(rawMeta, newTitle, newArtist, newTrack);
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

    meta_connection_lost:
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

        // === RECONNECT DELAY WITH EXPONENTIAL BACKOFF (transplant) ===
        if (st->shouldPlay.load() && st->isRunning.load()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;

            st->reconnectAttempts++;

            int baseDelayMs = 1000;
            int maxDelayMs = (int)(st->pollInterval * 1000);

            int delayMs = baseDelayMs * (1 << st->reconnectAttempts);
            if (delayMs > maxDelayMs) delayMs = maxDelayMs;

            int jitterRange = delayMs / 5;
            int jitter = (rand() % (jitterRange * 2 + 1)) - jitterRange;
            delayMs += jitter;

            char errBuf[128];
            sprintf(errBuf, "Connection lost (retry #%d in %dms)", st->reconnectAttempts, delayMs);
            st->errorMsg = errBuf;
            st->metadataChanged = true;

            for (int w = 0; w < delayMs / 100 && st->isRunning.load(); w++) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
    }
    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);
#else
    // Non-Windows C++ targets: worker thread is idle (no WinHTTP).
    while (st->isRunning.load()) std::this_thread::sleep_for(std::chrono::milliseconds(500));
#endif
    st->isRunning.store(false);
}

// ============================================================================
// CANCEL METADATA REQUEST — unblocks WinHttpReadData on dispose()
// (transplant of the RP_CancelRequest pattern)
// ============================================================================
static void urla_meta_cancel(void* haxePtr) {
    URLAudioMetaState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
        std::map<void*, URLAudioMetaState*>::iterator it = _urlaudio_meta_map.find(haxePtr);
        if (it != _urlaudio_meta_map.end()) st = it->second;
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

/**
* URL AUDIO STREAM PLAYER ATOM v2.0.1 (All-in-One Net Radio: WMF audio + auto-reconnect + ICY metadata)
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │  v2.0.1 HOTFIX (Task 103 — фикс компиляции MSVC):                       │
* │                                                                         │
* │  winhttp.h не подключает windows.h сам: его строка 54                   │
* │  "typedef LPVOID HINTERNET;" требует базовых типов Win32                │
* │  (LPVOID / DWORD / APIENTRY), которых в TU ещё не было —                │
* │  отсюда каскад C4430 / C2146 / C2143. Фикс: windows.h +                 │
* │  WIN32_LEAN_AND_MEAN + NOMINMAX ПЕРЕД winhttp.h — ровно тот             │
* │  порядок, что держал покойный NETRadioPlayerAtom (эталон                │
* │  сверен с git). Порядок winhttp.h -> WMFStreamSession.h не              │
* │  менялся; guard-ы зеркальны преамбуле WMFStreamSession.h.               │
* └─────────────────────────────────────────────────────────────────────────┘
*
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │  v2.0 CHANGES (Task 102, series URL_RADIO — Вариант A, Путь 1):         │
* │                                                                         │
* │  ALL-IN-ONE NET RADIO. Радио-семейство сведено к ОДНОМУ атому — этому. │
* │  NETRadioPlayerAtom (аудио через глобальный MFPlay-синглтон,            │
* │  deprecated mfplay.h) отправлен на пенсию; его проверенный ICY-воркер   │
* │  пересажен СЮДА пер-инстансным WinHTTP-потоком.                         │
* │                                                                         │
* │  НОВОЕ — ICY-ВОРКЕР МЕТАДАННЫХ (пер-инстансный, map-keyed):             │
* │    • читает ТОТ ЖЕ URL потока, что играет WMF-сессия                    │
* │    • пропускает аудио-чанки (icy-metaint), парсит StreamTitle           │
* │    • новые выходы: title / artist / track (+ импульс "updated")         │
* │    • собственный реконнект с экспоненциальным бэкоффом                  │
* │    • флаг urlChanged: горячая смена URL переподключает метаданные       │
* │    • dispose: cancel + join (паттерн RP_CancelRequest)                  │
* │                                                                         │
* │  НОВОЕ — хуки FAULT_ISOLATION (канон Task 98):                          │
* │    • Play() отвергнут сессией            -> markAsFaulted(PLAY_FAILED)  │
* │    • капитуляция реконнекта (10 попыток) -> markAsFaulted(CONN_LOST)    │
* │    • здоровый проход (state -> PLAYING)  -> clearFault()                │
* │    • осознанный stop                     -> clearFault()+clearMetadata  │
* │                                                                         │
* │  ИЗМЕНЕНО — горячая смена URL: смена URL при игре теперь немедленно     │
* │  перезапускает воспроизведение на новом URL (v1.5 останавливала звук и  │
* │  ждала ручного переключения play).                                      │
* └─────────────────────────────────────────────────────────────────────────┘
*
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │  v1.5 CHANGES (Task 96, Fix C — idempotent init):                       │
* │                                                                         │
* │  ROOT CAUSE: init() runs TWICE in the constructor flow — once via       │
* │  DriverManager.register() (Atom base constructor, isActive=true,        │
* │  calls driver.init() immediately) and once explicitly from the          │
* │  constructor body. The second call allocated a SECOND                   │
* │  WMFStreamSession (COM session) and OVERWROTE the map entry —           │
* │  session #1 was orphaned for the lifetime of the process.               │
* │                                                                         │
* │  FIX: map-keyed idempotency guard in init() — if this atom instance     │
* │  (mPtr) already owns a session, init() is a no-op. dispose() erases     │
* │  the map entry, so the guard never blocks a legitimate re-init.         │
* └─────────────────────────────────────────────────────────────────────────┘
*
* ┌─────────────────────────────────────────────────────────────────────────┐
* │  v1.3 CHANGES (resolves infinite reconnect loop):                       │
* │                                                                         │
* │  ROOT CAUSE: executeReconnect() did NOT set _reconnectTimer after       │
* │  a failed Play(). So on the next frame, _reconnectTimer was still       │
* │  <= 0, and executeReconnect() was called again — infinite loop.         │
* │                                                                         │
* │  CHANGE 1: executeReconnect() now sets _reconnectTimer after failure:   │
* │    • Play() == true  → _reconnectAttempts = 0, wait for PLAYING         │
* │    • Play() == false → _reconnectAttempts++, set exponential delay      │
* │    • attempts > MAX  → stop reconnecting, show error                    │
* │                                                                         │
* │  CHANGE 2: pollSessionState() no longer calls startReconnect() if       │
* │  _isReconnecting is already true (prevents double-triggering).          │
* │                                                                         │
* │  CHANGE 3: startReconnect() resets _connectionLost flag via C++ before  │
* │  scheduling, preventing stale flag from re-triggering.                  │
* └─────────────────────────────────────────────────────────────────────────┘
*
* RECONNECT FLOW:
* ┌─────────────────────────────────────────────────────────────────────────┐
* │                                                                         │
* │  MEError / BufferingTimeout                                             │
* │       │                                                                 │
* │       ▼                                                                 │
* │  pollSessionState() detects connectionLost                              │
* │       │                                                                 │
* │       ▼                                                                 │
* │  startReconnect():                                                      │
* │    _isReconnecting = true                                               │
* │    _reconnectAttempts = 1                                               │
* │    _reconnectTimer = ~1.0s (exponential backoff)                        │
* │       │                                                                 │
* │       ▼  (after timer expires)                                          │
* │  executeReconnect():                                                    │
* │    Stop() + Play(url)                                                   │
* │       │                                                                 │
* │       ├── Play() == true  → _reconnectAttempts = 0                      │
* │       │     Wait for MESessionStarted (pollSessionState checks)         │
* │       │                                                                 │
* │       └── Play() == false → _reconnectAttempts++                        │
* │             _reconnectTimer = ~2.0s (next attempt)                      │
* │             If attempts > 10 → give up                                  │
* │                                                                         │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class URLAudioStreamPlayerAtom extends Atom implements system.managers.Driver
{
	private var _lastUrl:String = "";
	private var _currentUrl:String = "";
	private var _lastPlayCtrl:Bool = false;
	private var _volume:Float = 1.0;
	private var _lastPlayingState:Bool = false;
	private var _lastBuffering:Bool = false;
	private var _lastError:String = "";
	private var _lastStateInt:Int = 0;
	
	// =========================================================================
	// v2.0: ICY METADATA DATABANK (Task 102)
	// =========================================================================
	private var _lastTitle:String = "";
	private var _lastArtist:String = "";
	private var _lastTrack:String = "";
	private var _updatedTimer:Float = 0.0;

	// =========================================================================
	// v1.2: AUTO-RECONNECT STATE
	// =========================================================================
	private var _isReconnecting:Bool = false;
	private var _waitingForPlaying:Bool = false;
	private var _reconnectAttempts:Int = 0;
	private var _reconnectTimer:Float = 0.0;

	private static inline var MAX_RECONNECT_ATTEMPTS:Int = 10;
	private static inline var BASE_RECONNECT_DELAY:Float = 1.0;
	private static inline var MAX_RECONNECT_DELAY:Float = 30.0;
	private static inline var BUFFERING_TIMEOUT_SEC:Float = 15.0;
	/** v2.0: Duration of the "updated" pulse on metadata change (seconds) */
	private static inline var PULSE_DURATION:Float = 0.1;

	public function new(id:String)
	{
		super(
			[
				new Contact("", INPUT, "url"),
				new Contact(false, INPUT, "play"),
				new Contact(1.0, INPUT, "volume")
			],
			[
				new Contact(false, OUTPUT, "isPlaying"),
				new Contact(false, OUTPUT, "isBuffering"),
				new Contact("", OUTPUT, "error"),
				new Contact(0, OUTPUT, "state"),
				new Contact("", OUTPUT, "title"),
				new Contact("", OUTPUT, "artist"),
				new Contact("", OUTPUT, "track"),
				new Contact(false, OUTPUT, "updated")
			],
			null, id, "URLAudioStreamPlayer", true
		);
		init();
	}

	override public function init():Void
	{
		untyped __cpp__('
			// FIX C (v1.5, Task 96) — IDEMPOTENCY GUARD.
			// init() runs TWICE in the constructor flow: once via
			// DriverManager.register() (the Atom base constructor,
			// isActive=true, calls driver.init() — a VIRTUAL call
			// that lands here before the derived constructor body runs)
			// and once explicitly from the constructor body. The second
			// call used to allocate a SECOND WMFStreamSession (COM
			// session) and OVERWRITE the map entry — orphaning session
			// #1 for the lifetime of the process. Map-keyed guard: if
			// this atom instance (mPtr) already owns a session, init()
			// is a no-op. (v1.4 inline reconnect fixes remain intact.)
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				if (_urlaudio_sessions.find((void*){0}.mPtr) != _urlaudio_sessions.end()) {
					return; // Already initialized — idempotent no-op.
				}
			}
			WMFStreamSession* session = new WMFStreamSession();
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				_urlaudio_sessions[(void*){0}.mPtr] = session;
			}
			// v2.0 (Task 102): per-instance ICY metadata worker — spawned in the same
			// guarded region, so the idempotency guard above covers BOTH resources.
			URLAudioMetaState* mst = new URLAudioMetaState();
			{
				std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
				_urlaudio_meta_map[(void*){0}.mPtr] = mst;
			}
			mst->worker = new std::thread(_urlaudio_meta_worker_func, (void*){0}.mPtr);
		', this);
	}

	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;

		readInputs();
		pollSessionState();
		pollMetadata();       // v2.0 (Task 102): ICY metadata polling
		updatePulseTimers(dt); // v2.0 (Task 102): "updated" pulse countdown

		// === v1.2: RECONNECT TIMER MANAGEMENT ===
		if (_isReconnecting)
		{
			_reconnectTimer -= dt;
			if (_reconnectTimer <= 0)
			{
				executeReconnect();
			}
		}
	}

	override public function dispose():Void
	{
		// v2.0 (Task 102): stop the ICY metadata worker FIRST —
		// unblock a possible blocking WinHttpReadData, then join the thread.
		untyped __cpp__('
			urla_meta_cancel((void*){0}.mPtr);
			URLAudioMetaState* mst = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
				auto it = _urlaudio_meta_map.find((void*){0}.mPtr);
				if (it != _urlaudio_meta_map.end()) {
					mst = it->second;
					_urlaudio_meta_map.erase(it);
				}
			}
			if (mst) {
				mst->shouldStop.store(true);
				mst->shouldPlay.store(false);
				mst->isRunning.store(false);
				if (mst->worker && mst->worker->joinable()) mst->worker->join();
				delete mst->worker; delete mst;
			}
		', this);

		untyped __cpp__('
			WMFStreamSession* session = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				auto it = _urlaudio_sessions.find((void*){0}.mPtr);
				if (it != _urlaudio_sessions.end()) {
					session = it->second;
					_urlaudio_sessions.erase(it);
				}
			}
			if (session) {
				session->Stop();
				delete session;
			}
		', this);

		DriverManager.getInstance().unregister(this.id);
		super.dispose();
	}

	private function readInputs():Void
	{
		var urlC = getInput("url");
		if (urlC != null && urlC.value != null)
		{
			var newUrl:String = Std.string(urlC.value);
			if (newUrl != _lastUrl)
			{
				trace('🎵 URLAudioStreamPlayer: URL changed: "${_lastUrl}" → "${newUrl}"');
				_lastUrl = newUrl;
				cancelReconnect();

				untyped __cpp__('
					WMFStreamSession* session = nullptr;
					{
						std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
						auto it = _urlaudio_sessions.find((void*){0}.mPtr);
						if (it != _urlaudio_sessions.end()) session = it->second;
					}
					if (session) {
						session->Stop();
					}
				', this);
				// v2.0 (Task 102): point the metadata worker at the new URL.
				untyped __cpp__('
					URLAudioMetaState* mst = nullptr;
					{
						std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
						auto it = _urlaudio_meta_map.find((void*){0}.mPtr);
						if (it != _urlaudio_meta_map.end()) mst = it->second;
					}
					if (mst) {
						std::lock_guard<std::mutex> dataLock(mst->mtx);
						mst->streamUrl = std::string((const char*){1}.__s);
						mst->reconnectAttempts = 0;
						mst->urlChanged.store(true);
					}
				', this, newUrl);
				clearMetadata();
				// Hot URL switch (v2.0): if we were playing, restart audio on the new
				// URL immediately — v1.5 stopped audio and waited for a manual play toggle.
				if (_lastPlayCtrl)
				{
					startPlayback();
				}
			}
		}

		var volC = getInput("volume");
		if (volC != null && volC.value != null)
		{
			var newVol:Float = Std.parseFloat(Std.string(volC.value));
			if (!Math.isNaN(newVol) && newVol >= 0.0 && newVol <= 2.0 && newVol != _volume)
			{
				_volume = newVol;
				untyped __cpp__('
					WMFStreamSession* session = nullptr;
					{
						std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
						auto it = _urlaudio_sessions.find((void*){0}.mPtr);
						if (it != _urlaudio_sessions.end()) session = it->second;
					}
					if (session) session->SetVolume({1});
				', this, _volume);
			}
		}

		var playC = getInput("play");
		if (playC != null && playC.value != null)
		{
			var newPlay:Bool = (playC.value == true);
			if (newPlay != _lastPlayCtrl)
			{
				trace('🎵 URLAudioStreamPlayer: Play control changed: ${_lastPlayCtrl} → ${newPlay}');
				_lastPlayCtrl = newPlay;

				if (newPlay)
				{
					cancelReconnect();
					startPlayback();
					// v2.0 (Task 102): start metadata extraction for the current URL.
					untyped __cpp__('
						URLAudioMetaState* mst = nullptr;
						{
							std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
							auto it = _urlaudio_meta_map.find((void*){0}.mPtr);
							if (it != _urlaudio_meta_map.end()) mst = it->second;
						}
						if (mst) {
							{
								std::lock_guard<std::mutex> dataLock(mst->mtx);
								mst->streamUrl = std::string((const char*){1}.__s);
								mst->reconnectAttempts = 0;
							}
							mst->shouldStop.store(false);
							mst->shouldPlay.store(true);
						}
					', this, _lastUrl);
				}
				else
				{
					cancelReconnect();
					stopPlayback();
					// v2.0 (Task 102): stop metadata extraction too.
					untyped __cpp__('
						URLAudioMetaState* mst = nullptr;
						{
							std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
							auto it = _urlaudio_meta_map.find((void*){0}.mPtr);
							if (it != _urlaudio_meta_map.end()) mst = it->second;
						}
						if (mst) { mst->shouldStop.store(true); mst->shouldPlay.store(false); }
					', this);
				}
			}
		}
	}

	private function startPlayback():Void
	{
		trace('🎵 URLAudioStreamPlayer: startPlayback() called, URL="${_lastUrl}"');
		if (_lastUrl == "" || _lastUrl == null)
		{
			trace('⚠️ URLAudioStreamPlayer: URL is empty, cannot start playback');
			return;
		}

		_currentUrl = _lastUrl;
		trace('🎵 URLAudioStreamPlayer: Starting playback for URL: ${_currentUrl}');

		var playOk:Bool = false; // v2.0 (Task 102): captured for the fault hook

		untyped __cpp__('
			WMFStreamSession* session = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				auto it = _urlaudio_sessions.find((void*){0}.mPtr);
				if (it != _urlaudio_sessions.end()) session = it->second;
			}
			if (session) {
				std::string url = std::string((const char*){1}.__s);
				printf("🎵 Calling session->Play() with URL: %s\\n", url.c_str());
				bool result = session->Play(url);
				printf("🎵 session->Play() returned: %s\\n", result ? "true" : "false");
				{2} = result;
			} else {
				printf("⚠️ URLAudioStreamPlayer: Session is null!\\n");
				{2} = false;
			}
		', this, _currentUrl, playOk);

		// v2.0 (Task 102): synchronous setup failure — latch the fault
		// (red frame). A manual play toggle or URL change is the retry.
		if (!playOk)
		{
			var errC = getOutput("error");
			if (errC != null) { errC.setValueSilent("Play failed (session rejected URL)"); errC.propagateCurrentValue(); }
			markAsFaulted("RADIO_PLAY_FAILED", "session->Play() rejected the URL (network or format error)");
		}
	}

	private function stopPlayback():Void
	{
		untyped __cpp__('
			WMFStreamSession* session = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				auto it = _urlaudio_sessions.find((void*){0}.mPtr);
				if (it != _urlaudio_sessions.end()) session = it->second;
			}
			if (session) {
				session->Stop();
			}
		', this);

		// === v2.3 CHANGE: Clear URL and reset flags on stop ===
		_currentUrl = "";
		_isReconnecting = false;
		_waitingForPlaying = false;
		_reconnectAttempts = 0;
		_reconnectTimer = 0;
		// v2.0 (Task 102): intentional stop = fault reset (ComPort closeDevice
		// semantics) + drop stale metadata from the old stream.
		clearFault();
		clearMetadata();
	}

	private function pollSessionState():Void
	{
		var cppPlaying:Bool = false;
		var cppBuffering:Bool = false;
		var cppError:String = "";
		var cppState:Int = 0;
		var cppConnectionLost:Bool = false;
		var cppBufferingTimeout:Bool = false;

		untyped __cpp__('
			WMFStreamSession* session = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				auto it = _urlaudio_sessions.find((void*){0}.mPtr);
				if (it != _urlaudio_sessions.end()) session = it->second;
			}
			if (session) {
				{1} = session->IsPlaying();
				{2} = session->IsBuffering();
				{3} = ::String(session->GetErrorMessage().c_str());
				{4} = (int)session->GetState();
				{5} = session->CheckAndResetConnectionLost();
				{6} = session->CheckBufferingTimeout({7});
			}
		', this, cppPlaying, cppBuffering, cppError, cppState,
		   cppConnectionLost, cppBufferingTimeout, Std.int(BUFFERING_TIMEOUT_SEC * 1000));

		// ═════════════════════════════════════════════════════════════════
		// v1.3 CHANGE: DETECT CONNECTION LOSS
		// Only trigger startReconnect if:
		//   1. Connection was lost OR buffering timed out
		//   2. User wants playback (_lastPlayCtrl == true)
		//   3. We are NOT already reconnecting (prevents double-trigger)
		// ═════════════════════════════════════════════════════════════════
		if ((cppConnectionLost || cppBufferingTimeout) && _lastPlayCtrl && !_isReconnecting)
		{
			trace('🔌 URLAudioStreamPlayer: Connection lost detected! Starting reconnect...');
			startReconnect(cppError);
		}

		// ═════════════════════════════════════════════════════════════════
		// v1.3 CHANGE: DETECT SUCCESSFUL RECONNECT
		// Only clear reconnect state if we were reconnecting AND
		// the C++ state is PLAYING (MESessionStarted received)
		// ═════════════════════════════════════════════════════════════════
		if (_isReconnecting && cppPlaying && cppState == 2)
		{
			trace('✅ URLAudioStreamPlayer: Reconnect successful after $_reconnectAttempts attempt(s)');
			_isReconnecting = false;
			_waitingForPlaying = false;   // ← ADD: reset waiting flag
			_reconnectAttempts = 0;
			_reconnectTimer = 0;

			var errC = getOutput("error");
			if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }

			var stateC = getOutput("state");
			if (stateC != null) { stateC.setValueSilent(2); stateC.propagateCurrentValue(); }
		}

		// ═════════════════════════════════════════════════════════════════
		// v1.4 CHANGE: DETECT FAILED RECONNECT
		// Play() returned true (accepted URL), but stream failed to reach
		// PLAYING state (connection lost or buffering timeout occurred).
		// Schedule next retry attempt.
		// ═════════════════════════════════════════════════════════════════
		if (_waitingForPlaying && (cppConnectionLost || cppBufferingTimeout))
		{
			trace('⏳ URLAudioStreamPlayer: Play() accepted, but failed to reach PLAYING. Scheduling retry...');
			_waitingForPlaying = false;
			_reconnectAttempts++;

			if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
			{
				trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
				_isReconnecting = false;
				_reconnectTimer = 0;

				var errC = getOutput("error");
				if (errC != null) { errC.setValueSilent("Connection lost. Max retries exceeded."); errC.propagateCurrentValue(); }

				var stateC = getOutput("state");
				if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
				markAsFaulted("RADIO_CONNECTION_LOST", "Max reconnect attempts exceeded"); // v2.0 (Task 102)
				return;
			}

			var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
			if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;

			var jitter = delay * 0.2 * (Math.random() * 2 - 1);
			delay += jitter;

			_reconnectTimer = delay;
			_isReconnecting = true;

			trace('🔄 Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');

			var errC = getOutput("error");
			if (errC != null) { errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...'); errC.propagateCurrentValue(); }
		}

		// === Update output contacts ===
		if (cppPlaying != _lastPlayingState)
		{
			_lastPlayingState = cppPlaying;
			var c = getOutput("isPlaying");
			if (c != null) { c.setValueSilent(cppPlaying); c.propagateCurrentValue(); }
		}

		if (cppBuffering != _lastBuffering)
		{
			_lastBuffering = cppBuffering;
			var c = getOutput("isBuffering");
			if (c != null) { c.setValueSilent(cppBuffering); c.propagateCurrentValue(); }
		}

		if (cppError != _lastError)
		{
			_lastError = cppError;
			var c = getOutput("error");
			if (c != null) { c.setValueSilent(cppError); c.propagateCurrentValue(); }
		}

		// Debug state
		if (cppState != _lastStateInt)
		{
			trace('📊 URLAudioStreamPlayer: State changed: ${_lastStateInt} → $cppState (${getGameStateName(cppState)})');
			_lastStateInt = cppState;
			// v2.0 (Task 102): healthy pass — PLAYING reached clears the fault latch
			// (clearFault is a no-op when the atom is not faulted).
			if (cppState == 2) clearFault();
			var c = getOutput("state");
			if (c != null) { c.setValueSilent(cppState); c.propagateCurrentValue(); }
		}
	}

	// =========================================================================
	// v1.3: AUTO-RECONNECT LOGIC (RESOLVED)
	// =========================================================================

	/**
	* Initiate reconnect sequence with exponential backoff.
	* Called by pollSessionState() when connection loss is detected.
	*/
	private function startReconnect(errorMsg:String):Void
	{
		if (_reconnectAttempts >= MAX_RECONNECT_ATTEMPTS)
		{
			trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
			_isReconnecting = false;

			var errC = getOutput("error");
			if (errC != null)
			{
				errC.setValueSilent("Connection lost. Max retries exceeded.");
				errC.propagateCurrentValue();
			}

			var stateC = getOutput("state");
			if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
			markAsFaulted("RADIO_CONNECTION_LOST", "Max reconnect attempts exceeded"); // v2.0 (Task 102)
			return;
		}

		_isReconnecting = true;
		_reconnectAttempts++;

		var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
		if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;

		var jitter = delay * 0.2 * (Math.random() * 2 - 1);
		delay += jitter;

		_reconnectTimer = delay;

		trace('🔄 URLAudioStreamPlayer: Reconnect attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS in ${Math.round(delay * 10) / 10}s');

		var errC = getOutput("error");
		if (errC != null)
		{
			errC.setValueSilent('Connection lost. Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...');
			errC.propagateCurrentValue();
		}

		var stateC = getOutput("state");
		if (stateC != null)
		{
			stateC.setValueSilent(3);
			stateC.propagateCurrentValue();
		}

		var bufC = getOutput("isBuffering");
		if (bufC != null)
		{
			bufC.setValueSilent(true);
			bufC.propagateCurrentValue();
		}
	}

	/**
	* Execute reconnect attempt: Stop + Play with same URL.
	*
	* ═════════════════════════════════════════════════════════════════════
	* v1.3 CHANGE: This method now properly handles the result of Play():
	*
	*   Play() == true  → Reset counter, wait for MESessionStarted
	*                      (pollSessionState will detect PLAYING state)
	*
	*   Play() == false → Increment counter, set exponential delay
	*                      for the NEXT attempt. If max reached → give up.
	*
	* Previously, _reconnectTimer was never set after failure,
	* causing executeReconnect() to be called every frame (infinite loop).
	* ═════════════════════════════════════════════════════════════════════
	*/
	private function executeReconnect():Void
	{
		if (_currentUrl == "" || _currentUrl == null)
		{
			trace('⚠️ URLAudioStreamPlayer: Cannot reconnect - no URL');
			_isReconnecting = false;
			_reconnectAttempts = 0;
			_reconnectTimer = 0;
			return;
		}

		// v1.3 CHANGE: Check max attempts BEFORE trying
		if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
		{
			trace('❌ URLAudioStreamPlayer: Max reconnect attempts reached. Giving up.');
			_isReconnecting = false;
			_reconnectAttempts = 0;
			_reconnectTimer = 0;

			var errC = getOutput("error");
			if (errC != null)
			{
				errC.setValueSilent("Connection lost. Max retries exceeded.");
				errC.propagateCurrentValue();
			}

			var stateC = getOutput("state");
			if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
			markAsFaulted("RADIO_CONNECTION_LOST", "Max reconnect attempts exceeded"); // v2.0 (Task 102)
			return;
		}

		trace('🔄 URLAudioStreamPlayer: Executing reconnect attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS for URL: $_currentUrl');

		var playResult:Bool = false;

		untyped __cpp__('
			WMFStreamSession* session = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
				auto it = _urlaudio_sessions.find((void*){0}.mPtr);
				if (it != _urlaudio_sessions.end()) session = it->second;
			}
			if (session) {
				session->Stop();
				std::string url = std::string((const char*){1}.__s);
				bool result = session->Play(url);
				{2} = result;
				printf("🔄 [URLAudio] Reconnect Play() returned: %s\\n", result ? "true" : "false");
			} else {
				printf("⚠️ [URLAudio] Reconnect: Session is null!\\n");
				{2} = false;
			}
		', this, _currentUrl, playResult);

		// ═════════════════════════════════════════════════════════════════
		// v1.3 CHANGE: Handle Play() result properly
		// ═════════════════════════════════════════════════════════════════
		if (playResult)
		{
			// Play() accepted - reset all reconnect state
			_isReconnecting = false;
			_waitingForPlaying = true;
			_reconnectAttempts = 0;
			_reconnectTimer = 0;

			trace('✅ Play() accepted, waiting for PLAYING state...');

			var errC = getOutput("error");
			if (errC != null)
			{
				errC.setValueSilent("Connecting...");
				errC.propagateCurrentValue();
			}
		}
		else
		{
			// Play() failed — increment counter and schedule next attempt
			_reconnectAttempts++;

			if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
			{
				// Max attempts reached — give up
				trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
				_isReconnecting = false;
				_reconnectTimer = 0;

				var errC = getOutput("error");
				if (errC != null)
				{
					errC.setValueSilent("Connection lost. Max retries exceeded.");
					errC.propagateCurrentValue();
				}

				var stateC = getOutput("state");
				if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
				markAsFaulted("RADIO_CONNECTION_LOST", "Max reconnect attempts exceeded"); // v2.0 (Task 102)
				return;
			}

			// Calculate next delay with exponential backoff
			var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
			if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;

			var jitter = delay * 0.2 * (Math.random() * 2 - 1);
			delay += jitter;

			_reconnectTimer = delay;

			trace('⏳ Play() failed. Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');

			var errC = getOutput("error");
			if (errC != null)
			{
				errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...');
				errC.propagateCurrentValue();
			}
		}
	}

	/**
	* Cancel pending reconnect (called on URL change or Stop).
	*/
	private function cancelReconnect():Void
	{
		if (_isReconnecting)
		{
			trace('🛑 URLAudioStreamPlayer: Reconnect cancelled');
			_isReconnecting = false;
			_reconnectAttempts = 0;
			_reconnectTimer = 0;

			// Clear error display
			var errC = getOutput("error");
			if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }
		}
	}

	// =========================================================================
	// v2.0 (Task 102): ICY METADATA POLLING — C++ worker -> Haxe outputs
	// =========================================================================
	/**
	* Poll the per-instance ICY metadata worker for fresh title/artist/track.
	* Mirrors the proven NETRadio pollCppState pattern: read under st->mtx
	* when the dirty flag is set, copy, clear the flag, write to output
	* contacts on change, pulse "updated".
	*/
	private function pollMetadata():Void
	{
		var mTitle:String = "";
		var mArtist:String = "";
		var mTrack:String = "";
		var mChanged:Bool = false;

		untyped __cpp__('
			URLAudioMetaState* st = nullptr;
			{
				std::lock_guard<std::mutex> lock(_urlaudio_meta_map_mutex);
				auto it = _urlaudio_meta_map.find((void*){0}.mPtr);
				if (it != _urlaudio_meta_map.end()) st = it->second;
			}
			if (st) {
				std::lock_guard<std::mutex> dataLock(st->mtx);
				if (st->metadataChanged) {
					{1} = ::String(st->title.c_str());
					{2} = ::String(st->artist.c_str());
					{3} = ::String(st->track.c_str());
					{4} = true;
					st->metadataChanged = false;
				}
			}
		', this, mTitle, mArtist, mTrack, mChanged);

		if (mChanged)
		{
			if (mTitle != _lastTitle) { _lastTitle = mTitle; setOutput("title", mTitle); }
			if (mArtist != _lastArtist) { _lastArtist = mArtist; setOutput("artist", mArtist); }
			if (mTrack != _lastTrack) { _lastTrack = mTrack; setOutput("track", mTrack); }

			var updatedC = getOutput("updated");
			if (updatedC != null) { updatedC.value = true; _updatedTimer = PULSE_DURATION; }
		}
	}

	/**
	* v2.0 (Task 102): Reset all metadata outputs to empty values.
	* Called on intentional stop and on URL switch (stale stream data).
	*/
	private function clearMetadata():Void
	{
		_lastTitle = "";
		_lastArtist = "";
		_lastTrack = "";
		setOutput("title", "");
		setOutput("artist", "");
		setOutput("track", "");
	}

	/**
	* v2.0 (Task 102): Write value to an output contact using the batched
	* pattern: setValueSilent() + propagateCurrentValue().
	*/
	private function setOutput(name:String, value:Dynamic):Void
	{
		var c = getOutput(name);
		if (c != null) { c.setValueSilent(value); c.propagateCurrentValue(); }
	}

	/**
	* v2.0 (Task 102): Countdown "updated" pulse timer (NETRadio pattern).
	* The "updated" output is a short-lived Bool pulse that fires every
	* time the ICY metadata changes.
	*/
	private function updatePulseTimers(dt:Float):Void
	{
		if (_updatedTimer > 0)
		{
			_updatedTimer -= dt;
			if (_updatedTimer <= 0)
			{
				_updatedTimer = 0;
				var c = getOutput("updated");
				if (c != null) c.value = false;
			}
		}
	}

	/**
	* Convert C++ WMFStreamSession::State enum to human-readable string.
	* Used for debug logging in pollSessionState().
	*
	* Mapping (from WMFStreamSession.h):
	*   0 = IDLE
	*   1 = CONNECTING
	*   2 = PLAYING
	*   3 = STOPPING
	*   4 = ERR
	*/
	private function getGameStateName(state:Int):String
	{
		return switch (state)
		{
			case 0: "IDLE";
			case 1: "CONNECTING";
			case 2: "PLAYING";
			case 3: "STOPPING";
			case 4: "ERR";
			default: "UNKNOWN(" + state + ")";
		}
	}
}
#end
