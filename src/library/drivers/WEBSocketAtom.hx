// FILE: library/drivers/WEBSocketAtom.hx
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// HTML5-SPECIFIC IMPORTS
// ============================================================================
#if html5
import js.html.WebSocket;
import js.html.MessageEvent;
import js.html.Event;
#end

// ============================================================================
// C++ HEADER INJECTION
// ============================================================================
#if cpp
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <atomic>
#include <vector>
')

// ============================================================================
// C++ IMPLEMENTATION INJECTION
// ============================================================================
@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOGDI
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

// ================================================================
// WEBSOCKET STATE STRUCTURE (C++ Backend)
// ================================================================
struct WebSocketState {
    std::string url;
    std::string lastReceivedData;
    std::string lastError;
    std::atomic<bool> isConnected;
    std::atomic<bool> hasNewData;
    std::atomic<bool> hasError;
    std::atomic<bool> shouldConnect;
    std::atomic<bool> shouldDisconnect;
    std::string pendingSendData;
    std::atomic<bool> hasPendingSend;
    std::mutex mtx;
    std::thread* worker;
    std::atomic<bool> isRunning;

#ifdef _WIN32
    HINTERNET hSession;
    HINTERNET hConnect;
    HINTERNET hWebSocket;
    std::mutex hWebSocketMtx;
#endif

    WebSocketState()
        : isConnected(false), hasNewData(false), hasError(false),
          shouldConnect(false), shouldDisconnect(false), hasPendingSend(false),
          worker(nullptr), isRunning(false)
#ifdef _WIN32
          , hSession(NULL), hConnect(NULL), hWebSocket(NULL)
#endif
    {}
};

static std::map<void*, WebSocketState*> _ws_map;
static std::mutex _ws_map_mutex;

// ================================================================
// URL PARSER
// ================================================================
struct WsUrl {
    std::string host;
    std::string path;
    uint16_t port;
    bool isSecure;
    bool valid;
    WsUrl() : port(80), isSecure(false), valid(false) {}
};

static WsUrl parse_ws_url(const std::string& url) {
    WsUrl result;
    std::string u = url;
    size_t schemeEnd = u.find("://");
    if (schemeEnd == std::string::npos) return result;
    std::string scheme = u.substr(0, schemeEnd);
    if (scheme == "wss") { result.isSecure = true; result.port = 443; }
    else if (scheme == "ws") { result.isSecure = false; result.port = 80; }
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

// ================================================================
// WEBSOCKET WORKER THREAD
// ================================================================
static void _ws_worker_func(void* haxePtr) {
    WebSocketState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_ws_map_mutex);
        auto it = _ws_map.find(haxePtr);
        if (it != _ws_map.end()) st = it->second;
    }
    st->isRunning.store(true);

#ifdef _WIN32
    while (st->isRunning.load()) {
        if (st->shouldConnect.load()) {
            st->shouldConnect.store(false);
            std::string url;
            { std::lock_guard<std::mutex> lock(st->mtx); url = st->url; }
            if (url.empty()) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "Empty URL";
                st->hasError.store(true);
                continue;
            }
            WsUrl parsed = parse_ws_url(url);
            if (!parsed.valid) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "Invalid WebSocket URL: " + url;
                st->hasError.store(true);
                continue;
            }
            st->hSession = WinHttpOpen(L"ALTAURI-WebSocket/1.0",
                WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
            if (!st->hSession) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WinHttpOpen failed";
                st->hasError.store(true);
                continue;
            }
            std::wstring wHost(parsed.host.begin(), parsed.host.end());
            st->hConnect = WinHttpConnect(st->hSession, wHost.c_str(), parsed.port, 0);
            if (!st->hConnect) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WinHttpConnect failed";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            std::wstring wPath(parsed.path.begin(), parsed.path.end());
            DWORD flags = parsed.isSecure ? WINHTTP_FLAG_SECURE : 0;
            st->hWebSocket = WinHttpOpenRequest(st->hConnect, L"GET", wPath.c_str(),
                NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
            if (!st->hWebSocket) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WinHttpOpenRequest failed";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            WinHttpAddRequestHeaders(st->hWebSocket,
                L"Upgrade: websocket\\r\\nConnection: Upgrade\\r\\n",
                (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD);
            if (!WinHttpSendRequest(st->hWebSocket, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WinHttpSendRequest failed";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            if (!WinHttpReceiveResponse(st->hWebSocket, NULL)) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WinHttpReceiveResponse failed";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            DWORD statusCode = 0;
            DWORD dwSize = sizeof(statusCode);
            WinHttpQueryHeaders(st->hWebSocket,
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &dwSize,
                WINHTTP_NO_HEADER_INDEX);
            if (statusCode != 101) {
                std::lock_guard<std::mutex> lock(st->mtx);
                st->lastError = "WebSocket handshake failed (status " + std::to_string(statusCode) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            st->isConnected.store(true);
            { std::lock_guard<std::mutex> lock(st->mtx); st->lastError = ""; }

            // Main WebSocket I/O loop
            while (st->isRunning.load() && st->isConnected.load()) {
                if (st->shouldDisconnect.load()) { st->shouldDisconnect.store(false); break; }
                if (st->hasPendingSend.load()) {
                    st->hasPendingSend.store(false);
                    std::string sendData;
                    { std::lock_guard<std::mutex> lock(st->mtx); sendData = st->pendingSendData; }
                    if (!sendData.empty() && st->hWebSocket) {
                        std::vector<BYTE> frame;
                        frame.push_back(0x81);
                        if (sendData.length() < 126) {
                            frame.push_back(0x80 | (BYTE)sendData.length());
                        } else if (sendData.length() < 65536) {
                            frame.push_back(0x80 | 126);
                            frame.push_back((BYTE)((sendData.length() >> 8) & 0xFF));
                            frame.push_back((BYTE)(sendData.length() & 0xFF));
                        } else {
                            frame.push_back(0x80 | 127);
                            for (int i = 7; i >= 0; i--)
                                frame.push_back((BYTE)((sendData.length() >> (i * 8)) & 0xFF));
                        }
                        BYTE mask[4] = {0x12, 0x34, 0x56, 0x78};
                        for (int i = 0; i < 4; i++) frame.push_back(mask[i]);
                        for (size_t i = 0; i < sendData.length(); i++)
                            frame.push_back(sendData[i] ^ mask[i % 4]);
                        DWORD bytesWritten;
                        WinHttpWriteData(st->hWebSocket, frame.data(), (DWORD)frame.size(), &bytesWritten);
                    }
                }
                DWORD bytesAvailable = 0;
                if (WinHttpQueryDataAvailable(st->hWebSocket, &bytesAvailable) && bytesAvailable > 0) {
                    std::vector<BYTE> buffer(bytesAvailable);
                    DWORD bytesRead;
                    if (WinHttpReadData(st->hWebSocket, buffer.data(), bytesAvailable, &bytesRead) && bytesRead > 0) {
                        if (bytesRead >= 2) {
                            BYTE opcode = buffer[0] & 0x0F;
                            bool masked = (buffer[1] & 0x80) != 0;
                            uint64_t payloadLen = buffer[1] & 0x7F;
                            size_t offset = 2;
                            if (payloadLen == 126) {
                                if (bytesRead >= 4) { payloadLen = (buffer[2] << 8) | buffer[3]; offset = 4; }
                            } else if (payloadLen == 127) {
                                if (bytesRead >= 10) {
                                    payloadLen = 0;
                                    for (int i = 0; i < 8; i++) payloadLen = (payloadLen << 8) | buffer[2 + i];
                                    offset = 10;
                                }
                            }
                            if (masked && bytesRead >= offset + 4) {
                                BYTE maskKey[4];
                                memcpy(maskKey, &buffer[offset], 4);
                                offset += 4;
                                std::string payload;
                                for (uint64_t i = 0; i < payloadLen && offset + i < bytesRead; i++)
                                    payload += (char)(buffer[offset + i] ^ maskKey[i % 4]);
                                if (opcode == 0x1 || opcode == 0x2) {
                                    std::lock_guard<std::mutex> lock(st->mtx);
                                    st->lastReceivedData = payload;
                                    st->hasNewData.store(true);
                                }
                            }
                        }
                    }
                } else {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
            }
            st->isConnected.store(false);
            if (st->hWebSocket) { WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL; }
            if (st->hConnect) { WinHttpCloseHandle(st->hConnect); st->hConnect = NULL; }
            if (st->hSession) { WinHttpCloseHandle(st->hSession); st->hSession = NULL; }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
#else
    while (st->isRunning.load()) { std::this_thread::sleep_for(std::chrono::milliseconds(100)); }
#endif
    st->isRunning.store(false);
}
')
#end

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     WEBSOCKET ATOM v2.0                                   ║
 * ║              (Cross-Platform: C++ WinHTTP + HTML5 Native)                 ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  WebSocket client with dual-platform support.                             ║
 * ║  At compile time, Haxe selects the appropriate backend:                   ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                    COMPILATION FLOW                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  haxe -cpp  ──► #if cpp   ──► WinHTTP + Background Thread          │  ║
 * ║  │  haxe -js   ──► #if html5 ──► Browser WebSocket API                │  ║
 * ║  │                                                                     │  ║
 * ║  │  Common code (contacts, update logic, propagation) is shared.       │  ║
 * ║  │  Platform-specific code is isolated in #if blocks.                  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     WEBSocketAtom                                   │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  COMMON LAYER (all targets)                                   │  │  ║
 * ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
 * ║  │  │  • Contacts: url, connect, disconnect, send, sendData        │  │  ║
 * ║  │  │  • Outputs: isConnected, receivedData, receivedTick,         │  │  ║
 * ║  │  │            sentTick, error, errorTick                         │  │  ║
 * ║  │  │  • update(dt): propagation + pulse timers                    │  │  ║
 * ║  │  │  • readInputs(): input reading + dispatch                    │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌──────────────────────────┐  ┌────────────────────────────────┐  │  ║
 * ║  │  │  #if cpp                 │  │  #if html5                     │  │  ║
 * ║  │  │  ─────────               │  │  ──────────                    │  │  ║
 * ║  │  │  WebSocketState* (C++)   │  │  _webSocket:WebSocket (JS)     │  │  ║
 * ║  │  │  Background thread       │  │  onopen/onmessage/onerror      │  │  ║
 * ║  │  │  WinHTTP API             │  │  .send() / .close()            │  │  ║
 * ║  │  │  Mutex/Atomic sync       │  │  Single-threaded (event loop)  │  │  ║
 * ║  │  └──────────────────────────┘  └────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  DATABANK (Haxe fields, shared)                               │  │  ║
 * ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
 * ║  │  │  _lastUrl, _lastReceivedData, _lastError                      │  │  ║
 * ║  │  │  _isConnectedFlag, _hasPendingReceived, _hasPendingError      │  │  ║
 * ║  │  │  _receivedTimer, _sentTimer, _errorTimer                      │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     DATA FLOW COMPARISON                                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  C++ Target:                                                              ║
 * ║  ──────────                                                               ║
 * ║  Background Thread ──► WebSocketState (mutex) ──► update(dt) polling     ║
 * ║                        ──► _hasPendingReceived ──► propagateCurrentValue  ║
 * ║                                                                           ║
 * ║  HTML5 Target:                                                            ║
 * ║  ────────────                                                             ║
 * ║  WebSocket.onmessage ──► _pendingReceivedStr ──► update(dt) propagation  ║
 * ║                          ──► _hasPendingReceived ──► propagateCurrentValue║
 * ║                                                                           ║
 * ║  Both targets converge at the propagation step — identical output         ║
 * ║  behavior regardless of platform.                                         ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class WEBSocketAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS (COMMON)
    // =========================================================================
    private static inline var PULSE_DURATION:Float = 0.05;

    // =========================================================================
    // DATABANK — COMMON FIELDS
    // =========================================================================
    private var _lastUrl:String = "";
    private var _lastReceivedData:String = "";
    private var _lastError:String = "";
    private var _isConnectedFlag:Bool = false;

    @:volatile private var _hasPendingReceived:Bool = false;
    @:volatile private var _hasPendingError:Bool = false;
    private var _pendingReceivedStr:String = "";
    private var _pendingErrStr:String = "";

    private var _receivedTimer:Float = 0.0;
    private var _sentTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    // =========================================================================
    // PLATFORM-SPECIFIC FIELDS
    // =========================================================================
    #if html5
    /** Native browser WebSocket instance. Null when disconnected. */
    private var _webSocket:WebSocket = null;
    #end

    // =========================================================================
    // CONSTRUCTOR (COMMON)
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact("", INPUT, "url"),
                new Contact(false, INPUT, "connect"),
                new Contact(false, INPUT, "disconnect"),
                new Contact(false, INPUT, "send"),
                new Contact("", INPUT, "sendData")
            ],
            [
                new Contact(false, OUTPUT, "isConnected"),
                new Contact("", OUTPUT, "receivedData"),
                new Contact(false, OUTPUT, "receivedTick"),
                new Contact(false, OUTPUT, "sentTick"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "WEBSocketAtom",
            true
        );
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================

    /**
     * Platform-specific initialization.
     *
     * C++:    Allocates WebSocketState, spawns background thread.
     * HTML5:  No-op (WebSocket created lazily on connect).
     */
    override public function init():Void
    {
        #if cpp
        untyped __cpp__('
            WebSocketState* st = new WebSocketState();
            st->isRunning.store(false);
            {
                std::lock_guard<std::mutex> lock(_ws_map_mutex);
                _ws_map[(void*){0}.mPtr] = st;
            }
            st->worker = new std::thread(_ws_worker_func, (void*){0}.mPtr);
        ', this);
        #elseif html5
        trace('WEBSocketAtom: HTML5 mode initialized (native WebSocket API)');
        #end
    }

    /**
     * Main update loop. Called every frame by DriverManager.
     *
     * ═══════════════════════════════════════════════════════════════════
     * FLOW:
     * ═══════════════════════════════════════════════════════════════════
     *
     *  ┌─────────────────────────────────────────────────────────────┐
     *  │  1. Poll platform backend for new data                      │
     *  │     C++:    Read from WebSocketState (mutex-protected)      │
     *  │     HTML5:  Check _hasPendingReceived (set by callbacks)    │
     *  │                                                             │
     *  │  2. Process pending received data → propagateCurrentValue   │
     *  │  3. Process pending errors → propagateCurrentValue          │
     *  │  4. Update connection status output                         │
     *  │  5. readInputs() — read user commands                       │
     *  │  6. updatePulseTimers() — reset tick pulses                 │
     *  └─────────────────────────────────────────────────────────────┘
     *
     * @param dt Delta time in seconds
     */
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // ── STEP 1: Poll platform backend ──
        #if cpp
        untyped __cpp__('
            WebSocketState* _ws_stPtr = nullptr;
            {
                std::lock_guard<std::mutex> _ws_mapLock(_ws_map_mutex);
                auto _ws_it = _ws_map.find((void*){0}.mPtr);
                if (_ws_it != _ws_map.end()) {
                    _ws_stPtr = _ws_it->second;
                }
            }
            if (_ws_stPtr) {
                {
                    std::lock_guard<std::mutex> _ws_dataLock(_ws_stPtr->mtx);
                    if (_ws_stPtr->hasNewData.load()) {
                        {0}->_pendingReceivedStr = ::String(_ws_stPtr->lastReceivedData.c_str());
                        {0}->_hasPendingReceived = true;
                        _ws_stPtr->hasNewData.store(false);
                    }
                }
                {
                    std::lock_guard<std::mutex> _ws_errLock(_ws_stPtr->mtx);
                    if (_ws_stPtr->hasError.load()) {
                        {0}->_pendingErrStr = ::String(_ws_stPtr->lastError.c_str());
                        {0}->_hasPendingError = true;
                        _ws_stPtr->hasError.store(false);
                    }
                }
                {0}->_isConnectedFlag = _ws_stPtr->isConnected.load();
            }
        ', this);
        #end
        // HTML5: _hasPendingReceived is set directly by WebSocket callbacks
        // No polling needed — event-driven architecture

        // ── STEP 2: Process pending received data (COMMON) ──
        if (_hasPendingReceived)
        {
            _hasPendingReceived = false;
            var rxOut = getOutput("receivedData");
            if (rxOut != null)
            {
                rxOut.setValueSilent(_pendingReceivedStr);
                rxOut.propagateCurrentValue();
            }
            var rxTick = getOutput("receivedTick");
            if (rxTick != null)
            {
                rxTick.value = true;
                _receivedTimer = PULSE_DURATION;
            }
        }

        // ── STEP 3: Process pending errors (COMMON) ──
        if (_hasPendingError)
        {
            _hasPendingError = false;
            var errOut = getOutput("error");
            if (errOut != null)
            {
                errOut.setValueSilent(_pendingErrStr);
                errOut.propagateCurrentValue();
            }
            var errTick = getOutput("errorTick");
            if (errTick != null)
            {
                errTick.value = true;
                _errorTimer = PULSE_DURATION;
            }
        }

        // ── STEP 4: Update connection status (COMMON) ──
        var connOut = getOutput("isConnected");
        if (connOut != null && connOut.value != _isConnectedFlag)
        {
            connOut.value = _isConnectedFlag;
        }

        // ── STEP 5: Read inputs and control ──
        readInputs();

        // ── STEP 6: Update pulse timers ──
        updatePulseTimers(dt);
    }

    /**
     * Safe disposal pattern.
     *
     * C++:    Signals thread to stop, joins, frees WebSocketState.
     * HTML5:  Closes native WebSocket, nullifies reference.
     */
    override public function dispose():Void
    {
        #if cpp
        untyped __cpp__('
            WebSocketState* st = nullptr;
            {
                std::lock_guard<std::mutex> _ws_lock(_ws_map_mutex);
                auto _ws_it = _ws_map.find((void*){0}.mPtr);
                if (_ws_it != _ws_map.end()) {
                    st = _ws_it->second;
                    _ws_map.erase(_ws_it);
                }
            }
            if (st) {
                st->shouldDisconnect.store(true);
                st->isRunning.store(false);
                if (st->worker && st->worker->joinable()) {
                    st->worker->join();
                }
                delete st->worker;
                delete st;
            }
        ', this);
        #elseif html5
        if (_webSocket != null)
        {
            _webSocket.close();
            _webSocket = null;
        }
        _isConnectedFlag = false;
        #end

        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // INPUT READING (COMMON + PLATFORM DISPATCH)
    // =========================================================================

    /**
     * Reads input contacts and dispatches platform-specific actions.
     *
     * Common logic: read contact values, detect edges.
     * Platform dispatch: connect/disconnect/send implementation.
     */
    private function readInputs():Void
    {
        var urlC = getInput("url");
        var connectC = getInput("connect");
        var disconnectC = getInput("disconnect");
        var sendC = getInput("send");
        var sendDataC = getInput("sendData");

        // ── URL change (COMMON) ──
        if (urlC != null && urlC.value != null)
        {
            var newUrl:String = Std.string(urlC.value);
            if (newUrl != _lastUrl)
            {
                _lastUrl = newUrl;
                #if cpp
                untyped __cpp__('
                    WebSocketState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                        auto it = _ws_map.find((void*){0}.mPtr);
                        if (it != _ws_map.end()) st = it->second;
                    }
                    if (st) {
                        std::lock_guard<std::mutex> dataLock(st->mtx);
                        st->url = std::string((const char*){1}.__s);
                    }
                ', this, newUrl);
                #end
                // HTML5: URL stored in _lastUrl, used on next connect
            }
        }

        // ── Connect trigger ──
        if (connectC != null && connectC.value == true)
        {
            connectC.value = false;
            #if cpp
            untyped __cpp__('
                WebSocketState* st = nullptr;
                {
                    std::lock_guard<std::mutex> lock(_ws_map_mutex);
                    auto it = _ws_map.find((void*){0}.mPtr);
                    if (it != _ws_map.end()) st = it->second;
                }
                if (st) { st->shouldConnect.store(true); }
            ', this);
            #elseif html5
            connectWebSocket();
            #end
        }

        // ── Disconnect trigger ──
        if (disconnectC != null && disconnectC.value == true)
        {
            disconnectC.value = false;
            #if cpp
            untyped __cpp__('
                WebSocketState* st = nullptr;
                {
                    std::lock_guard<std::mutex> lock(_ws_map_mutex);
                    auto it = _ws_map.find((void*){0}.mPtr);
                    if (it != _ws_map.end()) st = it->second;
                }
                if (st) { st->shouldDisconnect.store(true); }
            ', this);
            #elseif html5
            disconnectWebSocket();
            #end
        }

        // ── Send trigger ──
        if (sendC != null && sendC.value == true && _isConnectedFlag)
        {
            sendC.value = false;
            if (sendDataC != null && sendDataC.value != null)
            {
                var data:String = Std.string(sendDataC.value);
                #if cpp
                untyped __cpp__('
                    WebSocketState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                        auto it = _ws_map.find((void*){0}.mPtr);
                        if (it != _ws_map.end()) st = it->second;
                    }
                    if (st) {
                        std::lock_guard<std::mutex> dataLock(st->mtx);
                        st->pendingSendData = std::string((const char*){1}.__s);
                        st->hasPendingSend.store(true);
                    }
                ', this, data);
                #elseif html5
                sendWebSocketData(data);
                #end

                var sentTick = getOutput("sentTick");
                if (sentTick != null)
                {
                    sentTick.value = true;
                    _sentTimer = PULSE_DURATION;
                }
            }
        }
    }

    // =========================================================================
    // HTML5-SPECIFIC IMPLEMENTATION
    // =========================================================================
    #if html5

    /**
     * Create and configure native browser WebSocket.
     *
     * Event handlers set pending flags that update() will process
     * on the next frame — this is the bridge between the browser's
     * event loop and ALTAURI's TickGenerator-driven update cycle.
     *
     * ┌─────────────────────────────────────────────────────────────┐
     * │  Browser Event Loop          ALTAURI Update Loop            │
     * │  ──────────────────          ───────────────────            │
     * │  WebSocket.onmessage  ──►   _hasPendingReceived = true     │
     * │                              _pendingReceivedStr = data     │
     * │                                     │                       │
     * │                                     ▼                       │
     * │                              update(dt) polls flag          │
     * │                                     │                       │
     * │                                     ▼                       │
     * │                              propagateCurrentValue()        │
     * └─────────────────────────────────────────────────────────────┘
     */
    private function connectWebSocket():Void
    {
        // Close existing connection if any
        if (_webSocket != null)
        {
            disconnectWebSocket();
        }

        if (_lastUrl == null || _lastUrl == "")
        {
            setError("Empty URL");
            return;
        }

        try
        {
            _webSocket = new WebSocket(_lastUrl);

            _webSocket.onopen = function(e:Event) {
                _isConnectedFlag = true;
                _lastError = "";
                trace('WEBSocketAtom: Connected to $_lastUrl');
            };

            _webSocket.onmessage = function(e:MessageEvent) {
                var data:String = Std.string(e.data);
                _pendingReceivedStr = data;
                _hasPendingReceived = true;
            };

            _webSocket.onerror = function(e:Event) {
                setError("WebSocket error");
            };

            _webSocket.onclose = function(e:Event) {
                _isConnectedFlag = false;
                trace('WEBSocketAtom: Connection closed');
            };

        } catch (e:Dynamic) {
            setError('Failed to create WebSocket: $e');
        }
    }

    /**
     * Close native WebSocket connection.
     */
    private function disconnectWebSocket():Void
    {
        if (_webSocket != null)
        {
            _webSocket.close();
            _webSocket = null;
            _isConnectedFlag = false;
        }
    }

    /**
     * Send data through native WebSocket.
     *
     * @param data String data to send
     */
    private function sendWebSocketData(data:String):Void
    {
        if (_webSocket != null && _isConnectedFlag)
        {
            try
            {
                _webSocket.send(data);
            } catch (e:Dynamic) {
                setError('Send failed: $e');
            }
        }
    }

    /**
     * Set error state (HTML5 helper).
     *
     * @param msg Error message
     */
    private function setError(msg:String):Void
    {
        _pendingErrStr = msg;
        _hasPendingError = true;
        _lastError = msg;
    }

    #end

    // =========================================================================
    // PULSE TIMERS (COMMON)
    // =========================================================================

    /**
     * Countdown pulse timers for tick outputs.
     *
     * Tick outputs (receivedTick, sentTick, errorTick) are short-lived
     * Bool pulses that fire for PULSE_DURATION seconds and then reset.
     *
     * @param dt Delta time in seconds
     */
    private function updatePulseTimers(dt:Float):Void
    {
        if (_receivedTimer > 0)
        {
            _receivedTimer -= dt;
            if (_receivedTimer <= 0)
            {
                var c = getOutput("receivedTick");
                if (c != null) c.value = false;
            }
        }
        if (_sentTimer > 0)
        {
            _sentTimer -= dt;
            if (_sentTimer <= 0)
            {
                var c = getOutput("sentTick");
                if (c != null) c.value = false;
            }
        }
        if (_errorTimer > 0)
        {
            _errorTimer -= dt;
            if (_errorTimer <= 0)
            {
                var c = getOutput("errorTick");
                if (c != null) c.value = false;
            }
        }
    }
}