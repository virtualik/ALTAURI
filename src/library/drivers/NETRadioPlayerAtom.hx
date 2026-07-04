#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// C++ HEADER — структуры и объявления
// ============================================================================
// ВАЖНО: НЕ включаем windows.h сюда! Это ломает системные файлы Lime.
// Все WinHTTP includes перенесены в @:cppFileCode ниже.
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <atomic>
#include <algorithm>
')

// ============================================================================
// C++ IMPLEMENTATION — WinHTTP + ICY protocol parser
// ============================================================================
@:cppFileCode('
// WinHTTP includes — только в этом файле, не в глобальном заголовке
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

// ============================================================================
// STATE STRUCTURE
// ============================================================================
struct NetRadioState {
    // --- Control flags ---
    std::atomic<bool> shouldPlay;
    std::atomic<bool> shouldStop;
    std::atomic<bool> isRunning;

    // --- Configuration ---
    std::string streamUrl;
    float pollInterval;

    // --- Output data (protected by mtx) ---
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
        : shouldPlay(false)
        , shouldStop(false)
        , isRunning(false)
        , pollInterval(5.0f)
        , hasError(false)
        , metadataChanged(false)
        , isConnected(false)
        , worker(nullptr)
    {}
};

// Global map: Haxe object pointer -> C++ state
static std::map<void*, NetRadioState*> _netradio_map;
static std::mutex _netradio_map_mutex;

// ============================================================================
// URL PARSER (simple)
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

    if (scheme == "https") {
        result.isHttps = true;
        result.port = 443;
    } else if (scheme == "http") {
        result.port = 80;
    } else {
        return result;
    }

    size_t hostStart = schemeEnd + 3;
    size_t pathStart = u.find("/", hostStart);
    size_t portStart = u.find(":", hostStart);

    if (pathStart == std::string::npos) {
        result.path = "/";
        if (portStart != std::string::npos) {
            result.host = u.substr(hostStart, portStart - hostStart);
            std::string portStr = u.substr(portStart + 1);
            try { result.port = (uint16_t)std::stoi(portStr); }
            catch (...) {}
        } else {
            result.host = u.substr(hostStart);
        }
    } else {
        result.path = u.substr(pathStart);
        if (portStart != std::string::npos && portStart < pathStart) {
            result.host = u.substr(hostStart, portStart - hostStart);
            std::string portStr = u.substr(portStart + 1, pathStart - portStart - 1);
            try { result.port = (uint16_t)std::stoi(portStr); }
            catch (...) {}
        } else {
            result.host = u.substr(hostStart, pathStart - hostStart);
        }
    }

    result.valid = !result.host.empty();
    return result;
}

// ============================================================================
// METADATA PARSER — extracts StreamTitle from ICY metadata block
// ============================================================================
//
// ICY metadata format example:
// ┌─────────────────────────────────────────────────────────────────────┐
// │  StreamTitle=Artist - Track;StreamUrl=http://example.com;         │
// │  └─ quote ─┘ └────── title content ──────┘ └─ quote ─┘           │
// │                                                                     │
// │  Quote character: ASCII 39 (single quote / apostrophe)             │
// │  We use std::string(1, 39) to avoid Haxe escape conflicts          │
// └─────────────────────────────────────────────────────────────────────┘
//
static void parse_icy_metadata(const std::string& meta,
                                std::string& outTitle,
                                std::string& outArtist,
                                std::string& outTrack) {
    outTitle = "";
    outArtist = "";
    outTrack = "";

    // Quote character = ASCII 39 (single quote)
    // Using std::string(1, 39) instead of octal escape to avoid Haxe parser conflicts
    std::string quote(1, 39);

    // Look for StreamTitle=...
    size_t pos = meta.find("StreamTitle=");
    if (pos == std::string::npos) {
        pos = meta.find("streamtitle=");
    }
    if (pos == std::string::npos) return;

    // Find opening quote
    size_t quoteStart = meta.find(quote, pos);
    if (quoteStart == std::string::npos) return;
    quoteStart++;

    // Find closing quote
    size_t quoteEnd = meta.find(quote, quoteStart);
    if (quoteEnd == std::string::npos) return;

    std::string fullTitle = meta.substr(quoteStart, quoteEnd - quoteStart);
    outTitle = fullTitle;

    // Split "Artist - Track"
    size_t sep = fullTitle.find(" - ");
    if (sep != std::string::npos) {
        outArtist = fullTitle.substr(0, sep);
        outTrack = fullTitle.substr(sep + 3);
    } else {
        outTrack = fullTitle;
    }
}

// ============================================================================
// WORKER THREAD
// ============================================================================
//
// Thread lifecycle:
// ┌─────────────────────────────────────────────────────────────────────┐
// │  init()                                                             │
// │    │                                                                │
// │    ├── Create NetRadioState                                         │
// │    ├── Store in _netradio_map[haxePtr]                              │
// │    └── Start std::thread(_netradio_worker_func)                     │
// │                                                                     │
// │  Worker Loop:                                                       │
// │    ┌──────────────────────────────────────────────────────────┐     │
// │    │  while (isRunning) {                                     │     │
// │    │    if (!shouldPlay) { sleep(100ms); continue; }          │     │
// │    │    Parse URL                                             │     │
// │    │    WinHttpOpen → Connect → OpenRequest                   │     │
// │    │    AddHeader("icy-metadata: 1")                          │     │
// │    │    SendRequest → ReceiveResponse                         │     │
// │    │    Read icy-metaint, icy-name headers                    │     │
// │    │    ┌────────────────────────────────────────────────┐    │     │
// │    │    │  Read Loop:                                    │    │     │
// │    │    │    Read metaint bytes of audio (discard)       │    │     │
// │    │    │    Read 1 byte metadata length                  │    │     │
// │    │    │    Read N bytes metadata block                  │    │     │
// │    │    │    Parse StreamTitle                            │    │     │
// │    │    │    Write to shared state (mutex-protected)      │    │     │
// │    │    └────────────────────────────────────────────────┘    │     │
// │    │    On error: set hasError, reconnect after interval      │     │
// │    │  }                                                       │     │
// │    └──────────────────────────────────────────────────────────┘     │
// │                                                                     │
// │  dispose()                                                          │
// │    ├── Set isRunning = false                                        │
// │    ├── worker->join()                                               │
// │    └── Delete state                                                 │
// └─────────────────────────────────────────────────────────────────────┘
//
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
        // --- Check if we should play ---
        if (!st->shouldPlay.load()) {
            // Idle: sleep and check again
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        // --- Get URL ---
        std::string url;
        {
            std::lock_guard<std::mutex> lock(st->mtx);
            url = st->streamUrl;
        }

        if (url.empty()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "Empty URL";
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            continue;
        }

        // --- Parse URL ---
        ParsedURL parsed = parse_url(url);
        if (!parsed.valid) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "Invalid URL: " + url;
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            continue;
        }

        // --- Open WinHTTP session ---
        hSession = WinHttpOpen(
            L"ALTAURI/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS,
            0
        );

        if (!hSession) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "WinHttpOpen failed";
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            continue;
        }

        // --- Connect ---
        std::wstring wHost(parsed.host.begin(), parsed.host.end());
        hConnect = WinHttpConnect(
            hSession,
            wHost.c_str(),
            parsed.port,
            0
        );

        if (!hConnect) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "WinHttpConnect failed to " + parsed.host;
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            WinHttpCloseHandle(hSession);
            hSession = NULL;
            continue;
        }

        // --- Open Request ---
        std::wstring wPath(parsed.path.begin(), parsed.path.end());
        DWORD flags = parsed.isHttps ? WINHTTP_FLAG_SECURE : 0;

        hRequest = WinHttpOpenRequest(
            hConnect,
            L"GET",
            wPath.c_str(),
            NULL,
            WINHTTP_NO_REFERER,
            WINHTTP_DEFAULT_ACCEPT_TYPES,
            flags
        );

        if (!hRequest) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "WinHttpOpenRequest failed";
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            WinHttpCloseHandle(hConnect);
            WinHttpCloseHandle(hSession);
            hConnect = NULL; hSession = NULL;
            continue;
        }

        // --- Add ICY metadata header ---
        // Using wide string literal with escaped backslashes for Haxe
        // In Haxe string: \\\\r\\\\n becomes \\r\\n in C++ code
        const wchar_t icyHeader[] = L"icy-metadata: 1\\r\\n";
        WinHttpAddRequestHeaders(
            hRequest,
            icyHeader,
            (DWORD)-1,
            WINHTTP_ADDREQ_FLAG_ADD
        );

        // --- Ignore SSL errors for self-signed certs ---
        DWORD secFlags = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS,
                         &secFlags, sizeof(secFlags));

        // --- Send Request ---
        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "WinHttpSendRequest failed";
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            WinHttpCloseHandle(hRequest);
            WinHttpCloseHandle(hConnect);
            WinHttpCloseHandle(hSession);
            hRequest = NULL; hConnect = NULL; hSession = NULL;
            continue;
        }

        // --- Receive Response ---
        if (!WinHttpReceiveResponse(hRequest, NULL)) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "WinHttpReceiveResponse failed";
            st->shouldPlay.store(false);
            st->isConnected = false;
            st->metadataChanged = true;
            WinHttpCloseHandle(hRequest);
            WinHttpCloseHandle(hConnect);
            WinHttpCloseHandle(hSession);
            hRequest = NULL; hConnect = NULL; hSession = NULL;
            continue;
        }

        // --- Read icy-metaint header ---
        int metaint = 0;
        {
            WCHAR buf[256] = {0};
            DWORD bufLen = sizeof(buf);
            const wchar_t metaintHeader[] = L"icy-metaint";
            if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CUSTOM,
                                    metaintHeader, buf, &bufLen, NULL)) {
                std::wstring ws(buf);
                std::string s(ws.begin(), ws.end());
                try { metaint = std::stoi(s); } catch (...) {}
            }
        }

        // --- Read icy-name header ---
        {
            WCHAR buf[512] = {0};
            DWORD bufLen = sizeof(buf);
            const wchar_t nameHeader[] = L"icy-name";
            if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CUSTOM,
                                    nameHeader, buf, &bufLen, NULL)) {
                std::wstring ws(buf);
                std::string name(ws.begin(), ws.end());
                std::lock_guard<std::mutex> lock(st->mtx);
                if (st->title.empty()) {
                    st->title = name;
                    st->metadataChanged = true;
                }
            }
        }

        // --- Connected! ---
        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->isConnected = true;
            st->hasError = false;
            st->errorMsg = "";
            st->metadataChanged = true;
        }

        // --- Read stream data loop ---
        std::string lastRawMeta;

        while (st->isRunning.load() && st->shouldPlay.load()) {
            // Check for stop request
            if (st->shouldStop.load()) {
                st->shouldStop.store(false);
                st->shouldPlay.store(false);
                break;
            }

            // Check available data
            DWORD bytesAvailable = 0;
            if (!WinHttpQueryDataAvailable(hRequest, &bytesAvailable)) {
                break;
            }

            if (bytesAvailable == 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                continue;
            }

            if (metaint > 0) {
                // --- ICY protocol: read metaint bytes of audio, then metadata ---

                // Read audio data (discard — OpenFL handles playback)
                char audioBuf[8192];
                DWORD totalAudioRead = 0;
                DWORD toRead = metaint;

                while (toRead > 0 && st->isRunning.load() && st->shouldPlay.load()) {
                    DWORD chunkSize = (toRead < sizeof(audioBuf)) ? toRead : sizeof(audioBuf);
                    DWORD bytesRead = 0;

                    if (!WinHttpReadData(hRequest, audioBuf, chunkSize, &bytesRead)) {
                        goto connection_lost;
                    }

                    if (bytesRead == 0) {
                        std::this_thread::sleep_for(std::chrono::milliseconds(100));

                        // Check if data became available
                        DWORD avail = 0;
                        WinHttpQueryDataAvailable(hRequest, &avail);
                        if (avail == 0) {
                            // Stream ended or timeout
                            std::this_thread::sleep_for(std::chrono::milliseconds(500));
                            WinHttpQueryDataAvailable(hRequest, &avail);
                            if (avail == 0) goto connection_lost;
                        }
                        continue;
                    }

                    totalAudioRead += bytesRead;
                    toRead -= bytesRead;
                }

                // Read metadata length byte
                char metaLenByte = 0;
                DWORD metaLenRead = 0;
                if (!WinHttpReadData(hRequest, &metaLenByte, 1, &metaLenRead) || metaLenRead == 0) {
                    goto connection_lost;
                }

                int metaLen = (unsigned char)metaLenByte * 16;

                if (metaLen > 0) {
                    // Read metadata block
                    std::string metaBuf;
                    metaBuf.resize(metaLen + 1, 0);
                    DWORD metaRead = 0;

                    if (!WinHttpReadData(hRequest, &metaBuf[0], metaLen, &metaRead)) {
                        goto connection_lost;
                    }

                    metaBuf[metaRead] = 0;
                    std::string rawMeta(metaBuf.c_str());

                    // Only update if metadata changed
                    if (rawMeta != lastRawMeta && !rawMeta.empty()) {
                        lastRawMeta = rawMeta;

                        std::string newTitle, newArtist, newTrack;
                        parse_icy_metadata(rawMeta, newTitle, newArtist, newTrack);

                        if (!newTitle.empty()) {
                            std::lock_guard<std::mutex> lock(st->mtx);
                            st->rawMetadata = rawMeta;
                            st->title = newTitle;
                            st->artist = newArtist;
                            st->track = newTrack;
                            st->metadataChanged = true;
                        }
                    }
                }

            } else {
                // No ICY metadata support — just read and discard audio
                char discardBuf[8192];
                DWORD bytesRead = 0;
                DWORD chunkSize = (bytesAvailable < sizeof(discardBuf))
                                  ? bytesAvailable : sizeof(discardBuf);

                if (!WinHttpReadData(hRequest, discardBuf, chunkSize, &bytesRead)) {
                    break;
                }

                // Sleep to avoid busy-loop
                std::this_thread::sleep_for(std::chrono::milliseconds(200));

                // Periodically check for stop
                if (st->shouldStop.load()) {
                    st->shouldStop.store(false);
                    st->shouldPlay.store(false);
                    break;
                }
            }
        }

        connection_lost:

        // --- Cleanup connection ---
        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->isConnected = false;
        }

        if (hRequest) { WinHttpCloseHandle(hRequest); hRequest = NULL; }
        if (hConnect) { WinHttpCloseHandle(hConnect); hConnect = NULL; }
        if (hSession) { WinHttpCloseHandle(hSession); hSession = NULL; }

        // If still should play, it means connection was lost — set error
        if (st->shouldPlay.load() && st->isRunning.load()) {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->hasError = true;
            st->errorMsg = "Connection lost";
            st->metadataChanged = true;

            // Wait before reconnect attempt
            int waitMs = (int)(st->pollInterval * 1000);
            for (int w = 0; w < waitMs / 100 && st->isRunning.load(); w++) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
    }

    // --- Final cleanup ---
    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);

#else
    // Non-Windows: stub
    while (st->isRunning.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
#endif

    st->isRunning.store(false);
}
')

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     NET RADIO PLAYER ATOM v1.0                            ║
 * ║                     (Internet Radio Metadata Driver)                      ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Connects to internet radio streams and extracts ICY metadata.            ║
 * ║  Uses WinHTTP on Windows for HTTP/HTTPS connections.                      ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     NETRadioPlayerAtom                              ║  ║
 * ║  │                                                                     ║  ║
 * ║  │  A) COMPUTE MODULE:                                                 ║  ║
 * ║  │     ─────────────────                                               ║  ║
 * ║  │     Background Thread (C++ / WinHTTP):                              ║  ║
 * ║  │       1. Parse stream URL                                           ║  ║
 * ║  │       2. Connect via WinHTTP with icy-metadata:1 header             ║  ║
 * ║  │       3. Read icy-metaint from response headers                     ║  ║
 * ║  │       4. Read stream: audio data + ICY metadata blocks              ║  ║
 * ║  │       5. Parse StreamTitle from metadata                            ║  ║
 * ║  │       6. Write to shared state (mutex-protected)                    ║  ║
 * ║  │                                                                     ║  ║
 * ║  │     update(dt) {                                                    ║  ║
 * ║  │       1. Read playCtrl input → signal thread                        ║  ║
 * ║  │       2. Poll C++ state for metadata changes                        ║  ║
 * ║  │       3. Write to output contacts (silent + propagate)              ║  ║
 * ║  │       4. Manage pulse timers                                        ║  ║
 * ║  │     }                                                               ║  ║
 * ║  │                                                                     ║  ║
 * ║  │  B) DATABANK:                                                       ║  ║
 * ║  │     ─────────────                                                   ║  ║
 * ║  │     _lastTitle:String     - Last reported title                     ║  ║
 * ║  │     _lastArtist:String    - Last reported artist                    ║  ║
 * ║  │     _lastTrack:String     - Last reported track                     ║  ║
 * ║  │     _lastRawMeta:String   - Last raw metadata                       ║  ║
 * ║  │     _lastError:String     - Last error message                      ║  ║
 * ║  │     _lastState:Bool       - Last error state                        ║  ║
 * ║  │     _pulseTimer:Float     - Timer for "updated" pulse               ║  ║
 * ║  │                                                                     ║  ║
 * ║  │  C) INPUTS:                                                         ║  ║
 * ║  │     ────────                                                        ║  ║
 * ║  │     "stream_url"    - Radio station URL (String)                    ║  ║
 * ║  │     "poll_interval" - Metadata poll interval (Float, default 5s)    ║  ║
 * ║  │     "playCtrl"      - true=connect, false=disconnect (Bool)         ║  ║
 * ║  │                                                                     ║  ║
 * ║  │  D) OUTPUTS:                                                        ║  ║
 * ║  │     ────────                                                        ║  ║
 * ║  │     "title"         - "Artist - Track" (String)                     ║  ║
 * ║  │     "artist"        - Extracted artist (String)                     ║  ║
 * ║  │     "track"         - Extracted track (String)                      ║  ║
 * ║  │     "raw_metadata"  - Raw ICY data (String)                         ║  ║
 * ║  │     "updated"       - Pulse on metadata update (Bool)               ║  ║
 * ║  │     "state"         - Error flag: true=error, false=OK (Bool)       ║  ║
 * ║  │     "error"         - Error message (String)                        ║  ║
 * ║  │                                                                     ║  ║
 * ║  │  E) FACE (DeviceView):                                              ║  ║
 * ║  │     ─────────────────                                               ║  ║
 * ║  │     NETRadioPlayerWidget — minimal placeholder rectangle            ║  ║
 * ║  │                                                                     ║  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    AUDIO PLAYBACK NOTE                                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  This atom extracts METADATA only.                                        ║
 * ║  For actual audio playback, connect "stream_url" to a                     ║
 * ║  NETRadioAudioPlayer assembly that uses openfl.media.Sound                ║
 * ║  for streaming audio decoding and output.                                 ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class NETRadioPlayerAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var PULSE_DURATION:Float = 0.1;
    private static inline var DEFAULT_POLL_INTERVAL:Float = 5.0;

    // =========================================================================
    // DATABANK — Last known values
    // =========================================================================
    private var _lastUrl:String = "";
    private var _lastTitle:String = "";
    private var _lastArtist:String = "";
    private var _lastTrack:String = "";
    private var _lastRawMeta:String = "";
    private var _lastError:String = "";
    private var _lastState:Bool = false;
    private var _lastPlayCtrl:Bool = false;
    private var _pollInterval:Float = DEFAULT_POLL_INTERVAL;

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private var _updatedTimer:Float = 0.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [ // INPUTS
                new Contact("", INPUT, "stream_url"),
                new Contact(DEFAULT_POLL_INTERVAL, INPUT, "poll_interval"),
                new Contact(false, INPUT, "playCtrl")
            ],
            [ // OUTPUTS
                new Contact("", OUTPUT, "title"),
                new Contact("", OUTPUT, "artist"),
                new Contact("", OUTPUT, "track"),
                new Contact("", OUTPUT, "raw_metadata"),
                new Contact(false, OUTPUT, "updated"),
                new Contact(false, OUTPUT, "state"),     // true = error
                new Contact("", OUTPUT, "error")
            ],
            null, // processFunc
            id,
            "NETRadioPlayerAtom",
            true  // isActive -> register in DriverManager
        );
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        // Create C++ state and start worker thread
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

        // 1. Read inputs and control thread
        readInputs();

        // 2. Poll C++ state for metadata changes
        pollCppState();

        // 3. Update pulse timers
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        // Stop and join worker thread
        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                auto it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) {
                    st = it->second;
                    _netradio_map.erase(it);
                }
            }
            if (st) {
                st->shouldStop.store(true);
                st->shouldPlay.store(false);
                st->isRunning.store(false);
                if (st->worker && st->worker->joinable()) {
                    st->worker->join();
                }
                delete st->worker;
                delete st;
            }
        ', this);

        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // INPUT READING
    // =========================================================================
    private function readInputs():Void
    {
        // --- stream_url ---
        var urlC = getInput("stream_url");
        if (urlC != null && urlC.value != null)
        {
            var newUrl:String = Std.string(urlC.value);
            if (newUrl != _lastUrl)
            {
                _lastUrl = newUrl;
                // Push URL to C++ thread
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                        auto it = _netradio_map.find((void*){0}.mPtr);
                        if (it != _netradio_map.end()) st = it->second;
                    }
                    if (st) {
                        std::lock_guard<std::mutex> dataLock(st->mtx);
                        st->streamUrl = std::string((const char*){1}.__s);
                    }
                ', this, newUrl);
            }
        }

        // --- poll_interval ---
        var pollC = getInput("poll_interval");
        if (pollC != null && pollC.value != null)
        {
            var newInterval:Float = Std.parseFloat(Std.string(pollC.value));
            if (!Math.isNaN(newInterval) && newInterval >= 1.0 && newInterval != _pollInterval)
            {
                _pollInterval = newInterval;
                untyped __cpp__('
                    NetRadioState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                        auto it = _netradio_map.find((void*){0}.mPtr);
                        if (it != _netradio_map.end()) st = it->second;
                    }
                    if (st) {
                        std::lock_guard<std::mutex> dataLock(st->mtx);
                        st->pollInterval = (float){1};
                    }
                ', this, newInterval);
            }
        }

		// --- playCtrl ---
		var playC = getInput("playCtrl");
		if (playC != null && playC.value != null)
		{
			var newPlay:Bool = (playC.value == true);
			if (newPlay != _lastPlayCtrl)
			{
				_lastPlayCtrl = newPlay;
				untyped __cpp__('
					NetRadioState* st = nullptr;
					{
						std::lock_guard<std::mutex> lock(_netradio_map_mutex);
						auto it = _netradio_map.find((void*){0}.mPtr);
						if (it != _netradio_map.end()) st = it->second;
					}
					if (st) {
						if ({1}) {
							st->shouldPlay.store(true);
							st->shouldStop.store(false);
							// Re-push URL to ensure C++ state has it on re-activation
							st->streamUrl = std::string((const char*){2}.__s);
						} else {
							st->shouldStop.store(true);
							st->shouldPlay.store(false);
						}
					}
				', this, newPlay, _lastUrl);

				// Clear outputs on stop
				if (!newPlay)
				{
					setOutput("title", "");
					setOutput("artist", "");
					setOutput("track", "");
					setOutput("raw_metadata", "");
					setOutput("state", false);
					setOutput("error", "");
				}
			}
		}
	}

    // =========================================================================
    // POLL C++ STATE
    // =========================================================================
    private function pollCppState():Void
    {
        var cppTitle:String = "";
        var cppArtist:String = "";
        var cppTrack:String = "";
        var cppRawMeta:String = "";
        var cppError:String = "";
        var cppHasError:Bool = false;
        var cppChanged:Bool = false;
        var cppConnected:Bool = false;

        untyped __cpp__('
            NetRadioState* st = nullptr;
            {
                std::lock_guard<std::mutex> lock(_netradio_map_mutex);
                auto it = _netradio_map.find((void*){0}.mPtr);
                if (it != _netradio_map.end()) st = it->second;
            }
            if (st) {
                std::lock_guard<std::mutex> dataLock(st->mtx);
                if (st->metadataChanged) {
                    {1} = ::String(st->title.c_str());
                    {2} = ::String(st->artist.c_str());
                    {3} = ::String(st->track.c_str());
                    {4} = ::String(st->rawMetadata.c_str());
                    {5} = ::String(st->errorMsg.c_str());
                    {6} = st->hasError;
                    {7} = true;
                    {8} = st->isConnected;
                    st->metadataChanged = false;
                }
            }
        ', this, cppTitle, cppArtist, cppTrack, cppRawMeta,
             cppError, cppHasError, cppChanged, cppConnected);

        if (cppChanged)
        {
            // Update outputs with silent write + single propagate
            if (cppTitle != _lastTitle)
            {
                _lastTitle = cppTitle;
                setOutput("title", cppTitle);
            }
            if (cppArtist != _lastArtist)
            {
                _lastArtist = cppArtist;
                setOutput("artist", cppArtist);
            }
            if (cppTrack != _lastTrack)
            {
                _lastTrack = cppTrack;
                setOutput("track", cppTrack);
            }
            if (cppRawMeta != _lastRawMeta)
            {
                _lastRawMeta = cppRawMeta;
                setOutput("raw_metadata", cppRawMeta);
            }

            // State: true = has error
            if (cppHasError != _lastState)
            {
                _lastState = cppHasError;
                setOutput("state", cppHasError);
            }

            if (cppError != _lastError)
            {
                _lastError = cppError;
                setOutput("error", cppError);
            }

            // Fire "updated" pulse
            var updatedC = getOutput("updated");
            if (updatedC != null)
            {
                updatedC.value = true;
                _updatedTimer = PULSE_DURATION;
            }
        }
    }

    // =========================================================================
    // OUTPUT HELPERS
    // =========================================================================
    private function setOutput(name:String, value:Dynamic):Void
    {
        var c = getOutput(name);
        if (c != null)
        {
            c.setValueSilent(value);
            c.propagateCurrentValue();
        }
    }

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private function updatePulseTimers(dt:Float):Void
    {
        if (_updatedTimer > 0)
        {
            _updatedTimer -= dt;
            if (_updatedTimer <= 0)
            {
                var c = getOutput("updated");
                if (c != null) c.value = false;
            }
        }
    }

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result:Dynamic = {
            streamUrl: _lastUrl,
            pollInterval: _pollInterval
        };
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

        if (state.streamUrl != null)
        {
            _lastUrl = state.streamUrl;
            var urlC = getInput("stream_url");
            if (urlC != null) urlC.value = _lastUrl;
        }
        if (state.pollInterval != null)
        {
            _pollInterval = state.pollInterval;
            var pollC = getInput("poll_interval");
            if (pollC != null) pollC.value = _pollInterval;
        }
    }
}
#end