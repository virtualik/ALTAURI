// ============================================================================
//  WebSocketAtom.hx
//  Cross-platform WebSocket client atom for the ALTAURI visual construction
//  system.
//
//  Targets:
//    - HTML5    : Native browser WebSocket API (event-driven)
//    - Windows  : WinHttpWebSocket* API (Win 8+) + background worker thread
//    - Linux    : STUB (placeholder for libwebsockets integration)
//    - Android  : STUB (placeholder for libwebsockets via NDK)
//
//  Conforms to "Atom is Databank & Compute Core" architecture:
//    - Atom holds all state (databank fields, contacts)
//    - update(dt) is the single compute entry point
//    - Platform backends only push data INTO databank flags
//    - Widget reads data from contacts (never from backend directly)
//
//  Contacts (20 total: 10 inputs + 10 outputs)
//  ─────────────────────────────────────────────────────
//  INPUTS:
//    url                    (string,  IMPORTANT) "ws://host:port/path" or "wss://..."
//    subprotocol            (string,  OPTIONAL)  "chat, superchat" — Sec-WebSocket-Protocol
//    binaryMode             (bool,    OPTIONAL)  true → sendData as hex, false → as text
//    connect                (bool,    CRITICAL)  pulse — start connection
//    disconnect             (bool,    CRITICAL)  pulse — close connection
//    send                   (bool,    CRITICAL)  pulse — send sendData
//    sendData               (string,  IMPORTANT) payload to send
//    autoReconnect          (bool,    OPTIONAL)  enable auto-reconnect on drop (default false)
//    reconnectInterval      (float,   OPTIONAL)  base delay between attempts in seconds (default 1.0)
//    maxReconnectAttempts   (int,     OPTIONAL)  0 = unlimited, N = max attempts (default 0)
//
//  OUTPUTS:
//    isConnected           (bool,    CRITICAL)  connection status
//    receivedData          (string,  IMPORTANT) last received payload
//    receivedTick          (bool,    INTERNAL)  pulse on each received message
//    sentTick              (bool,    INTERNAL)  pulse on each successful send
//    error                 (string,  IMPORTANT) last error message
//    errorTick            (bool,    INTERNAL)  pulse on each error
//    closeCode             (int,     OPTIONAL)  RFC 6455 close code (1000/1001/1006/...)
//    bytesReceived         (int,     OPTIONAL)  total bytes received
//    bytesSent             (int,     OPTIONAL)  total bytes sent
//    reconnectAttempts     (int,     OPTIONAL)  current auto-reconnect attempt count
// ============================================================================

package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;

#if html5
import js.html.WebSocket;
import js.html.MessageEvent;
import js.html.CloseEvent;
import js.html.Event;
import js.lib.ArrayBuffer;
import js.lib.Uint8Array;
import haxe.io.Bytes;
#end

// ============================================================================
//  C++ HEADER INJECTION (Windows / Linux / Android)
// ============================================================================
// IMPORTANT: Only STL headers and forward declarations go here.
// Windows-specific headers (windows.h, winhttp.h) MUST NOT be included in
// @:headerCode — that would pollute the global namespace of every other
// .cpp file that includes class headers (like __boot__.cpp), breaking
// lime/OpenFL headers (OpenALAudioContext.h, etc.) with mysterious
// "syntax error: constant" errors caused by Windows macros (ERROR, etc.).
// Windows includes live in @:cppFileCode below.
// ============================================================================
#if cpp
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <atomic>
#include <vector>
#include <queue>
#include <chrono>

// ── Android JNI Helpers (Shared) ──
#ifdef __ANDROID__
#ifndef ALTAURI_JNI_HELPERS_INCLUDED
#define ALTAURI_JNI_HELPERS_INCLUDED

#include <jni.h>
#include <android/log.h>

#ifndef LOGI
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "WsAndroid", __VA_ARGS__)
#endif
#ifndef LOGE
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "WsAndroid", __VA_ARGS__)
#endif

// g_vm is defined in ComPortAtom.cpp
extern JavaVM* g_vm;

static inline JNIEnv* GetJniEnv(bool* outAttached = nullptr) {
    if (!g_vm) {
        if (outAttached) *outAttached = false;
        return nullptr;
    }
    JNIEnv* env = nullptr;
    jint res = g_vm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (res == JNI_EDETACHED) {
        if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            if (outAttached) *outAttached = true;
            return env;
        }
        return nullptr;
    } else if (res == JNI_OK) {
        if (outAttached) *outAttached = false;
        return env;
    }
    return nullptr;
}

static inline jobject GetActivity() {
    JNIEnv* env = GetJniEnv();
    if (env == nullptr) return nullptr;
    jclass activityThreadClass = env->FindClass("android/app/ActivityThread");
    if (activityThreadClass == nullptr) { env->ExceptionClear(); return nullptr; }
    jmethodID currentActivityThreadMethod = env->GetStaticMethodID(activityThreadClass, "currentActivityThread", "()Landroid/app/ActivityThread;");
    if (currentActivityThreadMethod == nullptr) { env->ExceptionClear(); env->DeleteLocalRef(activityThreadClass); return nullptr; }
    jobject activityThreadObj = env->CallStaticObjectMethod(activityThreadClass, currentActivityThreadMethod);
    if (activityThreadObj == nullptr) { env->DeleteLocalRef(activityThreadClass); return nullptr; }
    jmethodID getApplicationMethod = env->GetMethodID(activityThreadClass, "getApplication", "()Landroid/app/Application;");
    jobject context = env->CallObjectMethod(activityThreadObj, getApplicationMethod);
    env->DeleteLocalRef(activityThreadObj);
    env->DeleteLocalRef(activityThreadClass);
    return context;
}

#endif // ALTAURI_JNI_HELPERS_INCLUDED
#endif // __ANDROID__

// ── Linux : libwebsockets (placeholder for future integration) ───
// Forward-declare minimal lws types so the struct compiles even without
// the libwebsockets header installed. The actual lws_context / lws objects
// are only created inside .cpp body when HAS_LIBWEBSOCKETS is defined.
#if defined(__linux__) || defined(__ANDROID__)
struct lws_context;
struct lws;
#endif
')

// ============================================================================
//  C++ IMPLEMENTATION INJECTION
// ============================================================================
@:cppFileCode('
// ================================================================
//  PLATFORM-SPECIFIC INCLUDES (kept OUT of header on purpose)
// ================================================================
// These includes pollute the global namespace with Windows macros
// (ERROR, min, max, etc.) and MUST stay in the .cpp file only.
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOGDI
// Prevent min/max macros from breaking std::min/std::max and OpenFL code.
#define NOMINMAX
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

// WinHttpWebSocket functions are available on Windows 8+ (NTDDI_WIN8).
// Ensure SDK exposes them. If your SDK is older, install Windows 8+ SDK.
#if !defined(NTDDI_WIN8)
#error "WinHttpWebSocket API requires Windows 8 SDK or later. Install Windows 8+ SDK."
#endif
#endif // _WIN32

// ================================================================
//  WEBSOCKET STATE STRUCTURE (C++ Backend, all platforms)
// ================================================================
struct WebSocketState {
    // ── Configuration (written from Haxe side) ──
    std::string url;
    std::string subprotocol;

    // ── Received data / errors (read by Haxe update loop) ──
    std::string lastReceivedData;
    std::string lastError;
    int lastCloseCode;

    // ── Atomic flags (cross-thread signaling) ──
    std::atomic<bool> isConnected;
    std::atomic<bool> hasNewData;
    std::atomic<bool> hasError;
    std::atomic<bool> hasCloseEvent;
    std::atomic<bool> shouldConnect;
    std::atomic<bool> shouldDisconnect;
    std::atomic<bool> isRunning;

    // ── Send queue (instead of single pendingSendData) ──
    std::queue<std::string> sendQueue;
    std::mutex sendQueueMtx;
    std::atomic<bool> hasPendingSend;

    // ── Byte counters (read by Haxe update loop) ──
    std::atomic<uint64_t> bytesReceived;
    std::atomic<uint64_t> bytesSent;

    // ── Worker threads ──
    // Control thread: handles connect/disconnect, drains send queue, calls
    //                 WinHttpWebSocketSend.
    // Receive thread:  blocks in WinHttpWebSocketReceive, processes incoming
    //                 frames. Runs ONLY while connected.
    //
    // WinHTTP WebSocket API supports concurrent send (from control thread)
    // and receive (from receive thread) on the same handle — this is
    // documented behavior. Splitting them avoids the conflict where
    // WinHttpWebSocketSend cancels a pending WinHttpWebSocketReceive
    // (returning ERROR_WINHTTP_OPERATION_CANCELLED), which previously
    // caused false "connection closed" detection.
    std::thread* worker;            // control thread
    std::thread* receiveThread;     // receive thread (Win only, null when disconnected)

    // ── Platform-specific handles ──
#ifdef _WIN32
    HINTERNET hSession;
    HINTERNET hConnect;
    HINTERNET hWebSocket;        // WinHttpWebSocket handle
    std::mutex hWebSocketMtx;    // guards hWebSocket during close/cleanup
#elif defined(__ANDROID__)
    // Java WebSocket client instance (managed via JNI)
    jobject javaWsInstance;
    std::mutex javaWsMtx;
#elif defined(__linux__)
    // libwebsockets context is shared across all WS client instances of
    // the application — initialized lazily in the worker thread.
    // Per-instance: just store the wsi pointer (set when connected, cleared
    // when closed). The placeholder fields below keep the struct layout
    // stable so future lws integration is a localized change.
    void* lwsContext;            // actually struct lws_context* (typed as void* to avoid header dep)
    void* lwsWsi;                // actually struct lws*
    bool lwsExitRequested;
#endif

    WebSocketState()
    : lastCloseCode(0),
      isConnected(false), hasNewData(false), hasError(false), hasCloseEvent(false),
      shouldConnect(false), shouldDisconnect(false), isRunning(false),
      hasPendingSend(false),
      bytesReceived(0), bytesSent(0),
      worker(nullptr),
      receiveThread(nullptr)
#ifdef _WIN32
    , hSession(NULL), hConnect(NULL), hWebSocket(NULL)
#elif defined(__ANDROID__)
    , javaWsInstance(nullptr)
#elif defined(__linux__)
    , lwsContext(nullptr), lwsWsi(nullptr), lwsExitRequested(false)
#endif
    {}
};

// ── Instance map: Haxe object pointer → C++ state ──
static std::map<void*, WebSocketState*> _ws_map;
static std::mutex _ws_map_mutex;

// ================================================================
//  URL PARSER (host / port / path / secure)
// ================================================================
struct WsUrl {
    std::string host;
    std::string path;
    uint16_t port;
    bool isSecure;
    bool valid;
    WsUrl() : port(80), isSecure(false), valid(false) {}
};

static WsUrl _ws_parse_url(const std::string& url) {
    WsUrl r;
    size_t schemeEnd = url.find("://");
    if (schemeEnd == std::string::npos) return r;
    std::string scheme = url.substr(0, schemeEnd);
    if (scheme == "wss") { r.isSecure = true; r.port = 443; }
    else if (scheme == "ws") { r.isSecure = false; r.port = 80; }
    else return r;
    size_t hostStart = schemeEnd + 3;
    size_t pathStart = url.find("/", hostStart);
    size_t portStart = url.find(":", hostStart);
    if (pathStart == std::string::npos) {
        r.path = "/";
        if (portStart != std::string::npos) {
            r.host = url.substr(hostStart, portStart - hostStart);
            try { r.port = (uint16_t)std::stoi(url.substr(portStart + 1)); } catch (...) {}
        } else {
            r.host = url.substr(hostStart);
        }
    } else {
        r.path = url.substr(pathStart);
        if (portStart != std::string::npos && portStart < pathStart) {
            r.host = url.substr(hostStart, portStart - hostStart);
            try { r.port = (uint16_t)std::stoi(url.substr(portStart + 1, pathStart - portStart - 1)); } catch (...) {}
        } else {
            r.host = url.substr(hostStart, pathStart - hostStart);
        }
    }
    r.valid = !r.host.empty();
    return r;
}

// ================================================================
//  UTF-8 ↔ WIDESTRING helper (Windows needs wchar_t for WinHTTP)
// ================================================================
#ifdef _WIN32
static std::wstring _ws_utf8_to_wstring(const std::string& s) {
    if (s.empty()) return std::wstring();
    int wlen = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), NULL, 0);
    std::wstring ws(wlen, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &ws[0], wlen);
    return ws;
}
#endif

// ================================================================
//  RECEIVE THREAD — WINDOWS (WinHttpWebSocket API)
// ================================================================
//  Runs ONLY while connected. Blocks in WinHttpWebSocketReceive, processes
//  incoming frames, exits when:
//    - Peer sends CLOSE frame (hasCloseEvent set, lastCloseCode captured)
//    - WinHttpWebSocketReceive returns error (hasError set)
//    - Control thread calls WinHttpWebSocketClose (ERROR_WINHTTP_OPERATION_CANCELLED)
//    - isRunning becomes false (dispose)
//
//  This thread NEVER calls WinHttpWebSocketSend — sends happen in the
//  control thread. WinHTTP WebSocket API supports concurrent send/receive
//  on the same handle from different threads.
// ================================================================
#ifdef _WIN32
static void _ws_receive_thread_win(WebSocketState* st) {
    BYTE rxBuffer[8192];

    while (st->isRunning.load() && st->isConnected.load()) {
        DWORD rxBytesRead = 0;
        WINHTTP_WEB_SOCKET_BUFFER_TYPE rxBufType;
        DWORD rxErr = WinHttpWebSocketReceive(st->hWebSocket,
            rxBuffer, sizeof(rxBuffer), &rxBytesRead, &rxBufType);

        if (!st->isRunning.load() || !st->isConnected.load()) {
            // State changed during the blocking receive — exit cleanly.
            break;
        }

        if (rxErr == ERROR_WINHTTP_OPERATION_CANCELLED) {
            // Operation cancelled by control thread (WinHttpWebSocketClose
            // or WinHttpCloseHandle during disconnect/dispose). Exit cleanly.
            break;
        } else if (rxErr == ERROR_WINHTTP_TIMEOUT) {
            // Should not happen — we do not set a short receive timeout.
            // Treat as "no data yet, keep waiting".
            continue;
        } else if (rxErr != ERROR_SUCCESS) {
            // Genuine receive error. Surface to Haxe side and exit.
            {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpWebSocketReceive failed (err "
                                + std::to_string(rxErr) + ")";
                st->hasError.store(true);
            }
            // Signal control thread that connection is dead.
            st->isConnected.store(false);
            break;
        }

        // Dispatch by buffer type
        if (rxBufType == WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE ||
            rxBufType == WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE) {
            // Partial fragment — accumulate; do not signal hasNewData yet.
            std::lock_guard<std::mutex> lk(st->sendQueueMtx);
            st->lastReceivedData.append((const char*)rxBuffer, rxBytesRead);
        }
        else if (rxBufType == WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE ||
                 rxBufType == WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE) {
            // Final (possibly only) message chunk. Accumulate and signal.
            size_t totalLen = 0;
            {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastReceivedData.append((const char*)rxBuffer, rxBytesRead);
                totalLen = st->lastReceivedData.size();
                st->bytesReceived.fetch_add(totalLen);
                st->hasNewData.store(true);
            }
            // NOTE: update() on Haxe side will copy lastReceivedData out and
            // clear it. The accumulator semantics are correct because we
            // append-then-signal; once Haxe clears it, the next message
            // starts fresh.
        }
        else if (rxBufType == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) {
            // Peer sent a close frame. Read RFC 6455 close status code.
            USHORT closeStatus = 0;
            DWORD closeReasonLen = 0;
            WinHttpWebSocketQueryCloseStatus(st->hWebSocket,
                &closeStatus, NULL, 0, &closeReasonLen);
            st->lastCloseCode = (int)closeStatus;
            st->hasCloseEvent.store(true);
            // Signal control thread to clean up.
            st->isConnected.store(false);
            break;
        }
        // PING/PONG are handled automatically by WinHttpWebSocket API —
        // we never see them at the application layer.
    }
}
#endif // _WIN32

// ================================================================
//  CONTROL THREAD — WINDOWS (WinHttpWebSocket API)
// ================================================================
//  Responsibilities:
//    - Handle shouldConnect: full WinHTTP handshake sequence
//    - Spawn receive thread after successful connect
//    - Drain send queue (WinHttpWebSocketSend) — concurrent with receive
//    - Handle shouldDisconnect: graceful close, join receive thread
//    - Cleanup handles after disconnect
//
//  This thread NEVER calls WinHttpWebSocketReceive — receives happen in
//  the receive thread.
// ================================================================
#ifdef _WIN32
static void _ws_control_thread_win(WebSocketState* st) {
    st->isRunning.store(true);

    while (st->isRunning.load()) {
        // ── Handle connect request ──
        if (st->shouldConnect.load()) {
            st->shouldConnect.store(false);

            // Read URL + subprotocol (already written by Haxe side).
            std::string urlCopy;
            std::string subprotoCopy;
            {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                urlCopy = st->url;
                subprotoCopy = st->subprotocol;
            }

            if (urlCopy.empty()) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "Empty URL";
                st->hasError.store(true);
                continue;
            }
            WsUrl parsed = _ws_parse_url(urlCopy);
            if (!parsed.valid) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "Invalid WebSocket URL: " + urlCopy;
                st->hasError.store(true);
                continue;
            }

            // ── Step 1: WinHttpOpen ──
            st->hSession = WinHttpOpen(L"ALTAURI-WebSocket/2.0",
                WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
            if (!st->hSession) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpOpen failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                continue;
            }

            // ── Step 2: WinHttpConnect ──
            std::wstring wHost = _ws_utf8_to_wstring(parsed.host);
            st->hConnect = WinHttpConnect(st->hSession, wHost.c_str(), parsed.port, 0);
            if (!st->hConnect) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpConnect failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }

            // ── Step 3: WinHttpOpenRequest (WINHTTP_FLAG_SECURE for wss://) ──
            std::wstring wPath = _ws_utf8_to_wstring(parsed.path);
            DWORD flags = parsed.isSecure ? WINHTTP_FLAG_SECURE : 0;
            st->hWebSocket = WinHttpOpenRequest(st->hConnect, L"GET", wPath.c_str(),
                NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
            if (!st->hWebSocket) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpOpenRequest failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }

            // ── Step 4: Enable WebSocket upgrade BEFORE WinHttpSendRequest ──
            // WinHttpSetOption(UPGRADE_TO_WEB_SOCKET) tells WinHTTP to auto-add
            // all four mandatory RFC 6455 handshake headers during WinHttpSendRequest:
            //   Upgrade: websocket, Connection: Upgrade,
            //   Sec-WebSocket-Key: <random>, Sec-WebSocket-Version: 13
            if (!WinHttpSetOption(st->hWebSocket,
                    WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0)) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpSetOption(UPGRADE_TO_WEB_SOCKET) failed (err "
                                + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect);   st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession);   st->hSession = NULL;
                continue;
            }

            // ── Step 5: Send the request ──
            // Only add Sec-WebSocket-Protocol if user requested a subprotocol.
            // NOTE on escape sequences in Haxe @:cppFileCode: Haxe parses
            // backslash escapes itself before emitting the C++ source. So in
            // a string literal we must write backslash-backslash-r-backslash-
            // backslash-n (four backslashes total for CR+LF) to produce the
            // two-character C escape sequence that C++ then turns into real
            // CR+LF bytes at compile time. A single backslash-r or backslash-n
            // would be turned into a real newline by Haxe and break the C++
            // string literal with C2001 "newline in constant".
            LPCWSTR pAdditionalHeaders = WINHTTP_NO_ADDITIONAL_HEADERS;
            DWORD additionalHeadersLen = 0;
            std::wstring additionalHeaders;
            if (!subprotoCopy.empty()) {
                additionalHeaders = L"Sec-WebSocket-Protocol: "
                                    + _ws_utf8_to_wstring(subprotoCopy)
                                    + L"\\r\\n";
                pAdditionalHeaders = additionalHeaders.c_str();
                additionalHeadersLen = (DWORD)-1;
            }
            if (!WinHttpSendRequest(st->hWebSocket,
                    pAdditionalHeaders, additionalHeadersLen,
                    WINHTTP_NO_REQUEST_DATA, 0, 0, NULL)) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpSendRequest failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            if (!WinHttpReceiveResponse(st->hWebSocket, NULL)) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpReceiveResponse failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }

            // ── Step 6: Verify 101 Switching Protocols ──
            DWORD statusCode = 0;
            DWORD sz = sizeof(statusCode);
            WinHttpQueryHeaders(st->hWebSocket,
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &sz,
                WINHTTP_NO_HEADER_INDEX);
            if (statusCode != 101) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WebSocket handshake failed (HTTP " + std::to_string(statusCode) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }

            // ── Step 7: Complete WebSocket upgrade ──
            HINTERNET hUpgraded = WinHttpWebSocketCompleteUpgrade(st->hWebSocket, NULL);
            if (!hUpgraded) {
                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                st->lastError = "WinHttpWebSocketCompleteUpgrade failed (err " + std::to_string(GetLastError()) + ")";
                st->hasError.store(true);
                WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL;
                WinHttpCloseHandle(st->hConnect); st->hConnect = NULL;
                WinHttpCloseHandle(st->hSession); st->hSession = NULL;
                continue;
            }
            WinHttpCloseHandle(st->hWebSocket);
            st->hWebSocket = hUpgraded;

            // NOTE: No receive timeout configured — receive thread blocks
            // indefinitely until a frame arrives or the connection is closed.
            // Send operations happen in THIS thread, concurrently and safely.

            // ── Step 8: Connection established — launch receive thread ──
            st->isConnected.store(true);
            st->lastError.clear();
            st->lastCloseCode = 0;
            st->bytesReceived.store(0);
            st->bytesSent.store(0);
            st->receiveThread = new std::thread(_ws_receive_thread_win, st);

            // ── Step 9: Control loop — drain send queue, watch disconnect ──
            while (st->isRunning.load() && st->isConnected.load()) {
                // Handle disconnect request
                if (st->shouldDisconnect.load()) {
                    st->shouldDisconnect.store(false);
                    // Send graceful close frame (code 1000 "Normal Closure").
                    // This will also cause the receive thread pending
                    // WinHttpWebSocketReceive to return ERROR_WINHTTP_OPERATION_CANCELLED
                    // or a CLOSE_BUFFER_TYPE, allowing it to exit cleanly.
                    {
                        std::lock_guard<std::mutex> hLock(st->hWebSocketMtx);
                        if (st->hWebSocket) {
                            WinHttpWebSocketClose(st->hWebSocket,
                                WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, NULL, 0);
                        }
                    }
                    st->isConnected.store(false);
                    break;
                }

                // Drain send queue
                if (st->hasPendingSend.load()) {
                    std::string payload;
                    bool hasPayload = false;
                    {
                        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                        if (!st->sendQueue.empty()) {
                            payload = st->sendQueue.front();
                            st->sendQueue.pop();
                            hasPayload = true;
                        } else {
                            st->hasPendingSend.store(false);
                        }
                    }
                    if (hasPayload) {
                        // Send as UTF-8 text message. WinHTTP handles masking
                        // (random key per RFC 6455 §5.3) automatically.
                        WINHTTP_WEB_SOCKET_BUFFER_TYPE bufType =
                            WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE;
                        DWORD winErr = WinHttpWebSocketSend(st->hWebSocket,
                            bufType, (PVOID)payload.data(), (DWORD)payload.size());
                        if (winErr == ERROR_SUCCESS) {
                            st->bytesSent.fetch_add(payload.size());
                        } else {
                            // Send failed — surface error but keep connection.
                            // (Server may still be alive; one bad payload
                            // should not kill the whole session.)
                            std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                            st->lastError = "WinHttpWebSocketSend failed (err "
                                            + std::to_string(winErr) + ")";
                            st->hasError.store(true);
                        }
                    }
                }

                // Small idle wait — let receive thread breathe.
                // 5ms gives responsive send/disconnect without burning CPU.
                Sleep(5);
            }

            // ── Step 10: Wait for receive thread to exit, then cleanup ──
            st->isConnected.store(false);
            // Give receive thread a moment to exit on its own (close frame
            // or OPERATION_CANCELLED). If it does not exit in 2 seconds, we
            // force-close the handle to unblock it.
            if (st->receiveThread && st->receiveThread->joinable()) {
                // Try a graceful join with timeout via a helper thread.
                bool joined = false;
                std::thread joinHelper([&]() {
                    st->receiveThread->join();
                    joined = true;
                });
                joinHelper.detach();
                // Wait up to 2 seconds for graceful exit.
                for (int i = 0; i < 200 && !joined; i++) {
                    Sleep(10);
                }
                if (!joined) {
                    // Force-close the handle to unblock WinHttpWebSocketReceive.
                    std::lock_guard<std::mutex> hLock(st->hWebSocketMtx);
                    if (st->hWebSocket) {
                        WinHttpCloseHandle(st->hWebSocket);
                        st->hWebSocket = NULL;
                    }
                }
                // Wait a bit more for the join to complete.
                for (int i = 0; i < 50 && !joined; i++) {
                    Sleep(10);
                }
                // Delete the thread object. If still not joined (should not
                // happen), we leak the std::thread rather than crash.
                if (joined) {
                    delete st->receiveThread;
                    st->receiveThread = nullptr;
                }
            }

            // Cleanup WinHTTP handles.
            {
                std::lock_guard<std::mutex> lk(st->hWebSocketMtx);
                if (st->hWebSocket) { WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL; }
                if (st->hConnect)   { WinHttpCloseHandle(st->hConnect);   st->hConnect = NULL; }
                if (st->hSession)   { WinHttpCloseHandle(st->hSession);   st->hSession = NULL; }
            }
        }

        // Idle wait — poll flags at 50ms interval when not in connect flow.
        Sleep(50);
    }
    st->isRunning.store(false);
}
#endif // _WIN32

// ================================================================
//  WORKER THREAD — LINUX (PLACEHOLDER)
// ================================================================
#if defined(__linux__)
static void _ws_worker_posix_stub(WebSocketState* st) {
    st->isRunning.store(true);
    while (st->isRunning.load()) {
        if (st->shouldConnect.load()) {
            st->shouldConnect.store(false);
            std::lock_guard<std::mutex> lk(st->sendQueueMtx);
            st->lastError = "WebSocketAtom: Linux backend not yet "
                            "implemented. Build with HAS_LIBWEBSOCKETS defined and "
                            "link libwebsockets to enable. See README.";
            st->hasError.store(true);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    st->isRunning.store(false);
}
#endif
// ================================================================
//  ANDROID JNI IMPLEMENTATION
// ================================================================
#ifdef __ANDROID__

// JNI callbacks from Java -> C++
extern "C" JNIEXPORT void JNICALL Java_com_virtualik_altauri_AltauriWebSocketClient_nativeOnOpen(JNIEnv* env, jobject thiz, jlong haxePtr) {
    std::lock_guard<std::mutex> mapLock(_ws_map_mutex);
    auto it = _ws_map.find((void*)haxePtr);
    if (it != _ws_map.end()) {
        WebSocketState* st = it->second;
        st->isConnected.store(true);
        st->lastError.clear();
        st->hasError.store(false);
    }
}

extern "C" JNIEXPORT void JNICALL Java_com_virtualik_altauri_AltauriWebSocketClient_nativeOnMessage(JNIEnv* env, jobject thiz, jlong haxePtr, jbyteArray data, jint length) {
    std::lock_guard<std::mutex> mapLock(_ws_map_mutex);
    auto it = _ws_map.find((void*)haxePtr);
    if (it != _ws_map.end()) {
        WebSocketState* st = it->second;
        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
        jbyte* bytes = env->GetByteArrayElements(data, NULL);
        st->lastReceivedData.append((const char*)bytes, length);
        env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
        st->bytesReceived.fetch_add(length);
        st->hasNewData.store(true);
    }
}

extern "C" JNIEXPORT void JNICALL Java_com_virtualik_altauri_AltauriWebSocketClient_nativeOnClose(JNIEnv* env, jobject thiz, jlong haxePtr, jint code, jstring reason) {
    std::lock_guard<std::mutex> mapLock(_ws_map_mutex);
    auto it = _ws_map.find((void*)haxePtr);
    if (it != _ws_map.end()) {
        WebSocketState* st = it->second;
        st->lastCloseCode = code;
        st->hasCloseEvent.store(true);
        st->isConnected.store(false);
    }
}

extern "C" JNIEXPORT void JNICALL Java_com_virtualik_altauri_AltauriWebSocketClient_nativeOnError(JNIEnv* env, jobject thiz, jlong haxePtr, jstring error) {
    std::lock_guard<std::mutex> mapLock(_ws_map_mutex);
    auto it = _ws_map.find((void*)haxePtr);
    if (it != _ws_map.end()) {
        WebSocketState* st = it->second;
        const char* errStr = env->GetStringUTFChars(error, NULL);
        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
        st->lastError = errStr;
        env->ReleaseStringUTFChars(error, errStr);
        st->hasError.store(true);
    }
}

// Functions called from Haxe -> Java
extern "C" void android_ws_connect(void* haxePtr, const char* url, const char* subprotocol) {
    LOGI(">>> [JNI] android_ws_connect CALLED! URL: %s, Sub: %s", url ? url : "null", subprotocol ? subprotocol : "null");
    
    WebSocketState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_ws_map_mutex);
        auto it = _ws_map.find(haxePtr);
        if (it != _ws_map.end()) st = it->second;
    }
    
    if (!st) {
        LOGE(">>> [JNI] ERROR: WebSocketState not found for haxePtr!");
        return;
    }

    JNIEnv* env = GetJniEnv();
    if (!env) {
        LOGE(">>> [JNI] ERROR: Failed to get JNIEnv!");
        return;
    }

    jobject activity = GetActivity();
    if (!activity) {
        LOGE(">>> [JNI] ERROR: Failed to get Activity context!");
        return;
    }

    jclass wsClass = env->FindClass("com/virtualik/altauri/AltauriWebSocketClient");
    if (!wsClass) {
        LOGE(">>> [JNI] ERROR: FindClass failed for AltauriWebSocketClient. Check package path!");
        env->ExceptionClear();
        env->DeleteLocalRef(activity);
        return;
    }
    LOGI(">>> [JNI] SUCCESS: Found AltauriWebSocketClient class");

    jmethodID ctor = env->GetMethodID(wsClass, "<init>", "(Landroid/content/Context;J)V");
    if (!ctor) {
        LOGE(">>> [JNI] ERROR: Failed to find constructor <init>");
        env->ExceptionClear();
        env->DeleteLocalRef(wsClass);
        env->DeleteLocalRef(activity);
        return;
    }

    jobject wsInstance = env->NewObject(wsClass, ctor, activity, (jlong)haxePtr);
    if (!wsInstance) {
        LOGE(">>> [JNI] ERROR: Failed to create Java WebSocket instance");
        env->ExceptionClear();
        env->DeleteLocalRef(wsClass);
        env->DeleteLocalRef(activity);
        return;
    }

    {
        std::lock_guard<std::mutex> lk(st->javaWsMtx);
        if (st->javaWsInstance) {
            // Корректно закрыть старый Java-инстанс перед заменой.
            // Java-WebSocket держит внутренний worker-поток, который
            // продолжает попытки соединения. Если просто заменить
            // глобальный референс, старый поток продолжит работать и
            // его onError/onClose колбэки всё ещё могут прилететь в
            // наш WebSocketState, вызывая фантомные ошибки.
            jclass oldClass = env->GetObjectClass(st->javaWsInstance);
            if (oldClass) {
                jmethodID oldDisconnect = env->GetMethodID(oldClass, "disconnect", "()V");
                if (oldDisconnect) {
                    env->CallVoidMethod(st->javaWsInstance, oldDisconnect);
                    if (env->ExceptionCheck()) {
                        env->ExceptionClear();
                    }
                }
                env->DeleteLocalRef(oldClass);
            }
            env->DeleteGlobalRef(st->javaWsInstance);
            st->javaWsInstance = nullptr;
        }
        st->javaWsInstance = env->NewGlobalRef(wsInstance);
    }
    LOGI(">>> [JNI] Java instance created and stored globally");

    jmethodID connectMethod = env->GetMethodID(wsClass, "connect", "(Ljava/lang/String;Ljava/lang/String;)V");
    if (!connectMethod) {
        LOGE(">>> [JNI] ERROR: Failed to find connect method with signature (Ljava/lang/String;Ljava/lang/String;)V");
        env->ExceptionClear();
        env->DeleteLocalRef(wsInstance);
        env->DeleteLocalRef(wsClass);
        env->DeleteLocalRef(activity);
        return;
    }
    LOGI(">>> [JNI] Found connect method, preparing to call...");

    jstring jUrl = env->NewStringUTF(url);
    jstring jSubproto = subprotocol ? env->NewStringUTF(subprotocol) : nullptr;

    LOGI(">>> [JNI] Calling Java connect()...");
    env->CallVoidMethod(wsInstance, connectMethod, jUrl, jSubproto);

    // САМОЕ ВАЖНОЕ: Проверка на Java-исключения сразу после вызова
    if (env->ExceptionCheck()) {
        LOGE(">>> [JNI] JAVA EXCEPTION during connect()!");
        env->ExceptionDescribe(); // <-- ЭТО ВЫВЕДЕТ ПОЛНЫЙ СТЕКТРЕЙС ОШИБКИ В LOGCAT!
        env->ExceptionClear();
        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
        st->lastError = "Java connect() threw exception";
        st->hasError.store(true);
    } else {
        LOGI(">>> [JNI] Java connect() called successfully (no immediate exception)");
    }

    env->DeleteLocalRef(jUrl);
    if (jSubproto) env->DeleteLocalRef(jSubproto);
    env->DeleteLocalRef(wsInstance);
    env->DeleteLocalRef(wsClass);
    env->DeleteLocalRef(activity);
}

extern "C" void android_ws_send(void* haxePtr, const char* data, int len) {
    LOGI(">>> [JNI] android_ws_send CALLED! Length: %d", len);
        WebSocketState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_ws_map_mutex);
        auto it = _ws_map.find(haxePtr);
        if (it != _ws_map.end()) st = it->second;
    }
    if (!st) return;

    JNIEnv* env = GetJniEnv();
    if (!env) return;

    jobject wsInstance = nullptr;
    {
        std::lock_guard<std::mutex> lk(st->javaWsMtx);
        wsInstance = st->javaWsInstance;
    }
    if (!wsInstance) return;

    jclass wsClass = env->GetObjectClass(wsInstance);
    jmethodID sendMethod = env->GetMethodID(wsClass, "send", "([BI)V");
    
    jbyteArray jData = env->NewByteArray(len);
    env->SetByteArrayRegion(jData, 0, len, (const jbyte*)data);
    
    env->CallVoidMethod(wsInstance, sendMethod, jData, len);
    
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
        st->lastError = "Java send() threw exception";
        st->hasError.store(true);
    } else {
        st->bytesSent.fetch_add(len);
    }
    
    env->DeleteLocalRef(jData);
    env->DeleteLocalRef(wsClass);
}

extern "C" void android_ws_disconnect(void* haxePtr) {
    WebSocketState* st = nullptr;
    {
        std::lock_guard<std::mutex> lock(_ws_map_mutex);
        auto it = _ws_map.find(haxePtr);
        if (it != _ws_map.end()) st = it->second;
    }
    if (!st) return;

    JNIEnv* env = GetJniEnv();
    if (!env) return;

    jobject wsInstance = nullptr;
    {
        std::lock_guard<std::mutex> lk(st->javaWsMtx);
        wsInstance = st->javaWsInstance;
    }
    if (!wsInstance) return;

    jclass wsClass = env->GetObjectClass(wsInstance);
    jmethodID disconnectMethod = env->GetMethodID(wsClass, "disconnect", "()V");
    env->CallVoidMethod(wsInstance, disconnectMethod);
    
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(wsClass);
}
#endif // __ANDROID__
')
#end

// ============================================================================
//  CLASS DEFINITION
// ============================================================================

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                WEBSOCKET CLIENT ATOM v1.1                                 ║
 * ║        (Cross-Platform: HTML5 Browser + Windows WinHTTP)                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  WebSocket client conforming to RFC 6455.                                 ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                    COMPILATION FLOW                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  haxe -js   ──► #if html5       ──► Browser WebSocket API           │  ║
 * ║  │  haxe -cpp  ──► #if cpp         ──► Windows: WinHttpWebSocket*      │  ║
 * ║  │                                  Linux/Android: STUB (TODO: lws)    │  ║
 * ║  │                                                                     │  ║
 * ║  │  Common code (contacts, update logic, propagation) is shared.       │  ║
 * ║  │  Platform-specific code is isolated in #if blocks.                  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     ARCHITECTURE                                    │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  COMMON LAYER (all targets)                                   │  │  ║
 * ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
 * ║  │  │  • Contacts: url, subprotocol, binaryMode, connect,           │  │  ║
 * ║  │  │              disconnect, send, sendData                       │  │  ║
 * ║  │  │  • Outputs: isConnected, receivedData, receivedTick,          │  │  ║
 * ║  │  │            sentTick, error, errorTick, closeCode,             │  │  ║
 * ║  │  │            bytesReceived, bytesSent                           │  │  ║
 * ║  │  │  • update(dt): propagation + pulse timers                     │  │  ║
 * ║  │  │  • readInputs(): input reading + dispatch                     │  │  ║
 * ║  │  │  • setError(msg), updatePulseTimers(dt)                       │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌──────────────────────────┐   ┌────────────────────────────────┐  │  ║
 * ║  │  │  #if cpp (Windows)       │   │  #if html5                     │  │  ║
 * ║  │  │  ─────────               │   │  ──────────                    │  │  ║
 * ║  │  │  WebSocketState* (C++)   │   │  _webSocket:WebSocket (JS)     │  │  ║
 * ║  │  │  Background thread       │   │  onopen/onmessage/onerror      │  │  ║
 * ║  │  │  WinHttpWebSocket* API   │   │  .send() / .close()            │  │  ║
 * ║  │  │  Mutex/Atomic sync       │   │  Single-threaded (event loop)  │  │  ║
 * ║  │  │  Send queue (no drops)   │   │  binaryType = arraybuffer      │  │  ║
 * ║  │  └──────────────────────────┘   └────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌──────────────────────────┐   ┌────────────────────────────────┐  │  ║
 * ║  │  │  #if cpp (Linux)         │   │  #if cpp (Android)             │  │  ║
 * ║  │  │  STUB                    │   │  STUB                          │  │  ║
 * ║  │  │  Returns error:          │   │  Returns error:                │  │  ║
 * ║  │  │  "Not yet implemented.   │   │  "Not yet implemented.         │  │  ║
 * ║  │  │   Build with             │   │   Build with                   │  │  ║
 * ║  │  │   HAS_LIBWEBSOCKETS"     │   │   HAS_LIBWEBSOCKETS"           │  │  ║
 * ║  │  └──────────────────────────┘   └────────────────────────────────┘  │  ║
 * ║  │                                                                     │  ║
 * ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
 * ║  │  │  DATABANK (Haxe fields, shared)                               │  │  ║
 * ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
 * ║  │  │  _lastUrl, _lastSubprotocol, _lastReceivedData, _lastError    │  │  ║
 * ║  │  │  _isConnectedFlag, _hasPendingReceived, _hasPendingError      │  │  ║
 * ║  │  │  _hasPendingClose, _lastCloseCode                             │  │  ║
 * ║  │  │  _bytesReceived, _bytesSent                                   │  │  ║
 * ║  │  │  _receivedTimer, _sentTimer, _errorTimer                      │  │  ║
 * ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class WebSocketAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS (COMMON)
    // =========================================================================
    /** Pulse duration (seconds) for tick outputs (receivedTick, sentTick, errorTick). */
    private static inline var PULSE_DURATION:Float = 0.05;

    // =========================================================================
    // DATABANK — COMMON FIELDS (all targets)
    // =========================================================================
    /** Last requested URL (cached to detect changes). */
    private var _lastUrl:String = "";
    /** Last requested subprotocol (cached). */
    private var _lastSubprotocol:String = "";
    /** Binary mode flag (true → send as binary, false → send as text). */
    private var _lastBinaryMode:Bool = false;
    /** Append mode for outgoing data: "none" | "CR" | "LF" | "CRLF".
     *  Applied to every send: "CR" appends \r, "LF" appends \n, "CRLF" appends \r\n.
     *  Works for both text and binary modes (in binary mode the appended
     *  bytes are 0x0D / 0x0A respectively). */
    private var _lastAppendMode:String = "none";

    /** Last received data string (UTF-8). For binary payloads, contains raw chars. */
    private var _lastReceivedData:String = "";
    /** Last error message. */
    private var _lastError:String = "";
    /** Last RFC 6455 close code (1000/1001/1006/...). 0 = no close event yet. */
    private var _lastCloseCode:Int = 0;

    /** Connection status flag (mirrors backend). */
    private var _isConnectedFlag:Bool = false;

    /** Pending-received flag (set by backend, cleared by update). */
    @:volatile private var _hasPendingReceived:Bool = false;
    /** Pending-error flag (set by backend, cleared by update). */
    @:volatile private var _hasPendingError:Bool = false;
    /** Pending-close-event flag (set by backend, cleared by update). */
    @:volatile private var _hasPendingClose:Bool = false;

    /** String staged for next update() to propagate to receivedData output. */
    private var _pendingReceivedStr:String = "";
    /** String staged for next update() to propagate to error output. */
    private var _pendingErrStr:String = "";

    /** Byte counters (mirrored from backend). */
    private var _bytesReceived:Int = 0;
    private var _bytesSent:Int = 0;

    // Pulse timers for tick outputs
    private var _receivedTimer:Float = 0.0;
    private var _sentTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    // =========================================================================
    // DATABANK — AUTO-RECONNECT FIELDS (COMMON)
    // =========================================================================
    /**
     * Auto-reconnect configuration. Read from input contacts in readInputs().
     * When the connection drops unexpectedly (NOT via explicit disconnect
     * pulse), the atom waits for reconnectInterval seconds, then triggers
     * shouldConnect again, up to maxReconnectAttempts times.
     *
     * Reset conditions:
     *   - Explicit connect pulse → resets counter, clears user-requested disconnect
     *   - Explicit disconnect pulse → sets _userRequestedDisconnect = true
     *     (prevents auto-reconnect until next explicit connect)
     *   - Successful connection → resets counter to 0
     */
    private var _autoReconnect:Bool = false;
    private var _reconnectInterval:Float = 1.0;
    private var _maxReconnectAttempts:Int = 0;   // 0 = unlimited
    private var _reconnectAttempts:Int = 0;
    private var _reconnectTimer:Float = 0.0;
        
        /**
         * True while we are in an auto-reconnect cycle (between unexpected
         * disconnect and either successful reconnect, explicit disconnect,
         * or max attempts exhausted).
         *
         * Without this flag, the old logic used _wasConnected for edge
         * detection — which only fires on the SINGLE transition frame.
         * If the first reconnect attempt failed, no further attempts were
         * ever made. This flag keeps the cycle alive across frames.
         */
        private var _reconnectActive:Bool = false;

    /**
     * Edge-detection flag: was the atom connected on previous update()?
     * Used to detect the connected-to-disconnected transition that
     * triggers auto-reconnect logic.
     */
    private var _wasConnected:Bool = false;

    /**
     * True when the user explicitly pressed Disconnect. While this is true,
     * auto-reconnect is suppressed (the user wanted to disconnect).
     * Cleared on next explicit Connect pulse.
     */
    private var _userRequestedDisconnect:Bool = false;

    // =========================================================================
    // PLATFORM-SPECIFIC FIELDS
    // =========================================================================
    #if html5
    /** Native browser WebSocket instance. Null when disconnected. */
    private var _webSocket:WebSocket = null;
    /** Saved subprotocols array for next connect. */
    private var _pendingSubprotocols:Array<String> = null;
    #end

    // =========================================================================
    // CONSTRUCTOR (COMMON)
    // =========================================================================
    /**
     * Create a new WebSocketAtom instance.
     *
     * @param id Unique instance ID (typically a UID generated by AssemblyFactory)
     */
    public function new(id:String)
    {
        super(
            [
                // ── INPUTS ──
                new Contact("ws://localhost:8080", INPUT, "url"),
                new Contact("",                   INPUT, "subprotocol"),
                new Contact(false,                INPUT, "binaryMode"),
                new Contact("none",              INPUT, "appendMode"),
                new Contact(false,                INPUT, "connect"),
                new Contact(false,                INPUT, "disconnect"),
                new Contact("",                   INPUT, "sendData"),
				new Contact(false,                INPUT, "send"),
 
                // ── AUTO-RECONNECT INPUTS ──
                new Contact(false,                INPUT, "autoReconnect"),
                new Contact(1.0,                  INPUT, "reconnectInterval"),
                new Contact(0,                   INPUT, "maxReconnectAttempts")
            ],
            [
                // ── OUTPUTS ──
                new Contact(false, OUTPUT, "isConnected"),
                new Contact("",    OUTPUT, "receivedData"),
                new Contact(false, OUTPUT, "receivedTick"),
                new Contact(false, OUTPUT, "sentTick"),
                new Contact("",    OUTPUT, "error"),
                new Contact(false, OUTPUT, "errorTick"),
                new Contact(0,     OUTPUT, "closeCode"),
                new Contact(0,     OUTPUT, "bytesReceived"),
                new Contact(0,     OUTPUT, "bytesSent"),
                // ── AUTO-RECONNECT OUTPUT ──
                new Contact(0,     OUTPUT, "reconnectAttempts")
            ],
            null,
            id,
            "WebSocketAtom",
            true    // isActive → registers with DriverManager
        );
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE — init()
    // =========================================================================

    /**
     * Platform-specific initialization.
     *
     * C++ (Windows): Allocates WebSocketState, spawns background worker thread,
     *                configures WinHTTP timeouts (200ms receive timeout so the
     *                worker can react to shouldDisconnect within ~200ms).
     * C++ (Linux/Android): Allocates state, spawns stub worker (returns
     *                "not implemented" error on connect).
     * HTML5: No-op — WebSocket instance is created lazily on connect.
     *
     * IDEMPOTENT (v1.1, Task 96): called twice in the constructor flow
     * (DriverManager.register() + explicit init()); the second call is a
     * no-op via a map-keyed guard.
     */
    override public function init():Void
    {
        #if cpp
        untyped __cpp__('
            // FIX C (v1.1, Task 96) — IDEMPOTENCY GUARD.
            // init() runs TWICE in the constructor flow: once via
            // DriverManager.register() (the Atom base constructor,
            // isActive=true, calls driver.init() — a VIRTUAL call that
            // lands here before the derived constructor body runs) and
            // once explicitly from the constructor body. The second
            // call used to allocate a SECOND WebSocketState + worker
            // thread and OVERWRITE the map entry — orphaning state #1
            // and its thread for the lifetime of the process (idle
            // loop on atomics: a silent leak, no crash). Map-keyed
            // guard: if this atom instance (mPtr) already owns a
            // state, init() is a no-op.
            {
                std::lock_guard<std::mutex> lock(_ws_map_mutex);
                if (_ws_map.find((void*){0}.mPtr) != _ws_map.end()) {
                    return; // Already initialized — idempotent no-op.
                }
            }
            // Allocate state
            WebSocketState* st = new WebSocketState();
            {
                std::lock_guard<std::mutex> lock(_ws_map_mutex);
                _ws_map[(void*){0}.mPtr] = st;
            }
            // Spawn worker thread (platform-specific function).
            #ifdef _WIN32
                // On Windows, this is the CONTROL thread — it handles
                // connect/disconnect/send and spawns a separate RECEIVE
                // thread after successful connect.
                st->worker = new std::thread(_ws_control_thread_win, st);
            #elif defined(__ANDROID__)
                                // Android uses Java WebSocket client via JNI. No C++ worker thread needed.
                                #elif defined(__linux__)
                                st->worker = new std::thread(_ws_worker_posix_stub, st);
            #endif
        ', this);
        #elseif html5
        trace('WebSocketAtom: HTML5 mode initialized (native WebSocket API)');
        #end
    }

    // =========================================================================
    // DRIVER INTERFACE — update(dt)
    // =========================================================================

    /**
     * Main update loop. Called every frame by DriverManager.
     *
     * Flow:
     *   1. Poll platform backend for new data / errors / close events
     *      C++:    Read from WebSocketState (mutex-protected)
     *      HTML5:  Check _hasPendingReceived (set by callbacks)
     *   2. Process pending received data → propagateCurrentValue
     *   3. Process pending errors → propagateCurrentValue
     *   4. Process pending close events → propagate closeCode
     *   5. Update connection status output
     *   6. Update byte counters
     *   7. readInputs() — read user commands (connect/disconnect/send)
     *   8. updatePulseTimers() — reset tick pulses
     *   9. auto-reconnect logic (COMMON) 
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
                // ── Poll received data ──
                {
                    std::lock_guard<std::mutex> _ws_dataLock(_ws_stPtr->sendQueueMtx);
                    if (_ws_stPtr->hasNewData.load()) {
                        {0}->_pendingReceivedStr = ::String(_ws_stPtr->lastReceivedData.c_str());
                        {0}->_hasPendingReceived = true;
                        _ws_stPtr->lastReceivedData.clear();
                        _ws_stPtr->hasNewData.store(false);
                    }
                }
                // ── Poll errors ──
                {
                    std::lock_guard<std::mutex> _ws_errLock(_ws_stPtr->sendQueueMtx);
                    if (_ws_stPtr->hasError.load()) {
                        {0}->_pendingErrStr = ::String(_ws_stPtr->lastError.c_str());
                        {0}->_hasPendingError = true;
                        _ws_stPtr->hasError.store(false);
                    }
                }
                // ── Poll close events ──
                if (_ws_stPtr->hasCloseEvent.load()) {
                    {0}->_lastCloseCode = _ws_stPtr->lastCloseCode;
                    {0}->_hasPendingClose = true;
                    _ws_stPtr->hasCloseEvent.store(false);
                }
                // ── Sync connection status + byte counters ──
                {0}->_isConnectedFlag = _ws_stPtr->isConnected.load();
                {0}->_bytesReceived = (int)_ws_stPtr->bytesReceived.load();
                {0}->_bytesSent = (int)_ws_stPtr->bytesSent.load();
            }
        ', this);
        #end
        // HTML5: _hasPendingReceived is set directly by WebSocket callbacks.
        // No polling needed — event-driven architecture.

        // ── STEP 2: Process pending received data (COMMON) ──
        if (_hasPendingReceived)
        {
            _hasPendingReceived = false;
            _lastReceivedData = _pendingReceivedStr;

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
            _lastError = _pendingErrStr;

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

        // ── STEP 4: Process pending close events (COMMON) ──
        if (_hasPendingClose)
        {
            _hasPendingClose = false;
            var ccOut = getOutput("closeCode");
            if (ccOut != null)
            {
                ccOut.setValueSilent(_lastCloseCode);
                ccOut.propagateCurrentValue();
            }
        }

        // ── STEP 5: Update connection status output (COMMON) ──
        var connOut = getOutput("isConnected");
        if (connOut != null && connOut.value != _isConnectedFlag)
        {
            connOut.setValueSilent(_isConnectedFlag);
            connOut.propagateCurrentValue();
        }

        // ── STEP 6: Update byte counters (COMMON) ──
        var brOut = getOutput("bytesReceived");
        if (brOut != null && brOut.value != _bytesReceived)
        {
            brOut.setValueSilent(_bytesReceived);
            brOut.propagateCurrentValue();
        }
        var bsOut = getOutput("bytesSent");
        if (bsOut != null && bsOut.value != _bytesSent)
        {
            bsOut.setValueSilent(_bytesSent);
            bsOut.propagateCurrentValue();
        }

        // ── STEP 7: Read inputs and dispatch platform actions ──
        readInputs();

        // ── STEP 8: Update pulse timers ──
        updatePulseTimers(dt);

                // ── STEP 9: Auto-reconnect logic (COMMON) ──
                // State machine:
                //   _reconnectActive = true  → we are counting down to next attempt
                //   _reconnectActive = false → idle (connected, or not in auto cycle)
                //
                // Transitions to TRUE:
                //   - Unexpected disconnect (was connected, now not, auto enabled,
                //     not user-requested)
                // Transitions to FALSE:
                //   - Successful connection (isConnected becomes true)
                //   - Explicit user disconnect pulse
                //   - autoReconnect turned off via input
                //   - maxReconnectAttempts exhausted
                //
                // The timer counts down EVERY frame while _reconnectActive && !connected.
                // This fixes the previous bug where the timer only ticked on the single
                // transition frame, causing exactly one reconnect attempt and then silence.

                // ── Detect unexpected disconnect transition → start cycle ──
                if (_wasConnected && !_isConnectedFlag
                        && _autoReconnect && !_userRequestedDisconnect)
                {
                        if (!_reconnectActive)
                        {
                                _reconnectActive = true;
                                _reconnectTimer = _reconnectInterval;
                                _reconnectAttempts = 0;  // fresh cycle
                        }
                }

                // ── Detect successful connection → stop cycle, reset counter ──
                if (_isConnectedFlag)
                {
                        _reconnectActive = false;
                        _reconnectAttempts = 0;
                        _reconnectTimer = 0;
                }

                // ── Abort cycle if user requested disconnect or auto disabled ──
                if (_userRequestedDisconnect || !_autoReconnect)
                {
                        _reconnectActive = false;
                }

                // ── Run timer every frame while cycle is active and still down ──
                if (_reconnectActive && !_isConnectedFlag)
                {
                        var canRetry:Bool = (_maxReconnectAttempts == 0)
                                                                || (_reconnectAttempts < _maxReconnectAttempts);
                        if (canRetry)
                        {
                                _reconnectTimer -= dt;
                                if (_reconnectTimer <= 0)
                                {
                                        _reconnectAttempts++;
                                        _reconnectTimer = _reconnectInterval;  // reset for next attempt
                                        // Trigger connect — same path as explicit connect pulse
                                        #if cpp
                                                #if android
                                                untyped __cpp__('
                                                {
                                                        std::string urlCopy;
                                                        std::string subprotoCopy;
                                                        WebSocketState* st = nullptr;
                                                        {
                                                                std::lock_guard<std::mutex> lock(_ws_map_mutex);
                                                                auto it = _ws_map.find((void*){0}.mPtr);
                                                                if (it != _ws_map.end()) st = it->second;
                                                        }
                                                        if (st) {
                                                                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                                                                urlCopy = st->url;
                                                                subprotoCopy = st->subprotocol;
                                                                android_ws_connect((void*){0}.mPtr, urlCopy.c_str(), subprotoCopy.c_str());
                                                        }
                                                }
                                                ', this);
                                                #else
                                                untyped __cpp__('
                                                        WebSocketState* _ws_stRc = nullptr;
                                                        {
                                                                std::lock_guard<std::mutex> _ws_rcLock(_ws_map_mutex);
                                                                auto _ws_rcIt = _ws_map.find((void*){0}.mPtr);
                                                                if (_ws_rcIt != _ws_map.end()) {
                                                                        _ws_stRc = _ws_rcIt->second;
                                                                }
                                                        }
                                                        if (_ws_stRc) { _ws_stRc->shouldConnect.store(true); }
                                                ', this);
                                                #end
                                        #elseif html5
                                        connectWebSocket();
                                        #end
                                }
                        }
                        else
                        {
                                // Exhausted all attempts — give up
                                _reconnectActive = false;
                        }
                }

                // Update edge-detection state for next frame
                _wasConnected = _isConnectedFlag;

        // Propagate reconnectAttempts output (only when changed)
        var raOut = getOutput("reconnectAttempts");
        if (raOut != null && raOut.value != _reconnectAttempts)
        {
            raOut.setValueSilent(_reconnectAttempts);
            raOut.propagateCurrentValue();
        }
    }

    // =========================================================================
    // DRIVER INTERFACE — dispose()
    // =========================================================================

    /**
     * Safe disposal pattern.
     *
     * C++:    Signals worker thread to stop, joins, frees WebSocketState.
     * HTML5:  Closes native WebSocket (if any), nullifies reference.
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
                // Signal both threads to stop.
                st->shouldDisconnect.store(true);
                st->isRunning.store(false);

                // Cancel any pending WinHTTP receive so the receive thread
                // can exit promptly.
                #ifdef _WIN32
                {
                    std::lock_guard<std::mutex> hLock(st->hWebSocketMtx);
                    if (st->hWebSocket) {
                        // WinHttpWebSocketClose sends a close frame to the
                        // server AND cancels any pending WinHttpWebSocketReceive
                        // (returns ERROR_WINHTTP_OPERATION_CANCELLED in the
                        // receive thread, allowing it to exit).
                        WinHttpWebSocketClose(st->hWebSocket,
                            WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, NULL, 0);
                    }
                }
                #endif

                // Wait for control thread (it will join the receive thread
                // internally as part of its cleanup sequence).
                if (st->worker && st->worker->joinable()) {
                    st->worker->join();
                }
                delete st->worker;

                // Defensive: if receive thread is somehow still running (e.g.,
                // control thread was in idle wait between connections and
                // exited without cleaning up), join it here too.
                #ifdef _WIN32
                if (st->receiveThread && st->receiveThread->joinable()) {
                    // Force-close handle to unblock any pending receive.
                    {
                        std::lock_guard<std::mutex> hLock(st->hWebSocketMtx);
                        if (st->hWebSocket) {
                            WinHttpCloseHandle(st->hWebSocket);
                            st->hWebSocket = NULL;
                        }
                    }
                    st->receiveThread->join();
                    delete st->receiveThread;
                    st->receiveThread = nullptr;
                }
                // Final handle cleanup (in case control thread did not get to it).
                {
                    std::lock_guard<std::mutex> hLock(st->hWebSocketMtx);
                    if (st->hWebSocket) { WinHttpCloseHandle(st->hWebSocket); st->hWebSocket = NULL; }
                    if (st->hConnect)   { WinHttpCloseHandle(st->hConnect);   st->hConnect = NULL; }
                    if (st->hSession)   { WinHttpCloseHandle(st->hSession);   st->hSession = NULL; }
                }
                delete st;
                                    #elif defined(__ANDROID__)
                                        android_ws_disconnect((void*){0}.mPtr);
                                        JNIEnv* env = GetJniEnv();
                                        if (env && st->javaWsInstance) {
                                                env->DeleteGlobalRef(st->javaWsInstance);
                                                st->javaWsInstance = nullptr;
                                        }
                                        delete st;
                #endif
                        }
        ', this);
        #elseif html5
        if (_webSocket != null)
        {
            try
            {
                // Use 1000 "Normal Closure" per RFC 6455 §7.4
                _webSocket.close(1000, "Atom disposed");
            }
            catch (e:Dynamic) { /* ignore */ }
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
        var urlC          = getInput("url");
        var subprotoC     = getInput("subprotocol");
        var binaryModeC   = getInput("binaryMode");
        var appendModeC   = getInput("appendMode");
        var connectC      = getInput("connect");
        var disconnectC   = getInput("disconnect");
        var sendC         = getInput("send");
        var sendDataC     = getInput("sendData");
        var autoReconnectC       = getInput("autoReconnect");
        var reconnectIntervalC   = getInput("reconnectInterval");
        var maxReconnectAttemptsC = getInput("maxReconnectAttempts");

        // ── Auto-reconnect config (COMMON) ──
        if (autoReconnectC != null && autoReconnectC.value != null)
        {
            _autoReconnect = (autoReconnectC.value == true);
        }
        if (reconnectIntervalC != null && reconnectIntervalC.value != null)
        {
            var newInterval:Float = cast(reconnectIntervalC.value, Float);
            // Clamp to reasonable range: 100ms .. 60s
            if (newInterval < 0.1) newInterval = 0.1;
            if (newInterval > 60.0) newInterval = 60.0;
            _reconnectInterval = newInterval;
        }
        if (maxReconnectAttemptsC != null && maxReconnectAttemptsC.value != null)
        {
            var n:Int = cast(maxReconnectAttemptsC.value, Int);
            if (n < 0) n = 0;  // negative is meaningless, treat as 0 (unlimited)
            _maxReconnectAttempts = n;
        }

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
                        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                        st->url = std::string((const char*){1}.__s);
                    }
                ', this, newUrl);
                #end
                // HTML5: URL stored in _lastUrl, used on next connect.
            }
        }

        // ── Subprotocol change (COMMON) ──
        if (subprotoC != null && subprotoC.value != null)
        {
            var newSp:String = Std.string(subprotoC.value);
            if (newSp != _lastSubprotocol)
            {
                _lastSubprotocol = newSp;
                #if cpp
                untyped __cpp__('
                    WebSocketState* st = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                        auto it = _ws_map.find((void*){0}.mPtr);
                        if (it != _ws_map.end()) st = it->second;
                    }
                    if (st) {
                        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                        st->subprotocol = std::string((const char*){1}.__s);
                    }
                ', this, newSp);
                #elseif html5
                // Parse comma-separated subprotocols for HTML5 WebSocket ctor.
                if (newSp == null || newSp == "")
                {
                    _pendingSubprotocols = null;
                }
                else
                {
                    _pendingSubprotocols = newSp.split(",").map(function(s:String):String {
                        return StringTools.trim(s);
                    }).filter(function(s:String):Bool { return s != ""; });
                }
                #end
            }
        }

        // ── Binary mode change (COMMON) ──
        if (binaryModeC != null && binaryModeC.value != null)
        {
            _lastBinaryMode = (binaryModeC.value == true);
        }

        // ── Append mode change (COMMON) ──
        // Read line-ending append setting: "none" | "CR" | "LF" | "CRLF".
        // Applied in the Send trigger below before platform dispatch.
        if (appendModeC != null && appendModeC.value != null)
        {
            var newAm:String = Std.string(appendModeC.value);
            if (newAm != _lastAppendMode)
            {
                _lastAppendMode = newAm;
            }
        }

        // ── Connect trigger ──
        if (connectC != null && connectC.value == true)
        {
            connectC.value = false;
            // Reset auto-reconnect state — explicit connect clears any
            // previous "user requested disconnect" flag and counter.
            _userRequestedDisconnect = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;  // immediate attempt (will be the explicit one)
                        #if cpp
                                #if android
                                untyped __cpp__('
                                {
                                        std::string urlCopy;
                                        std::string subprotoCopy;
                                        WebSocketState* st = nullptr;
                                        {
                                                std::lock_guard<std::mutex> lock(_ws_map_mutex);
                                                auto it = _ws_map.find((void*){0}.mPtr);
                                                if (it != _ws_map.end()) st = it->second;
                                        }
                                        if (st) {
                                                std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                                                urlCopy = st->url;
                                                subprotoCopy = st->subprotocol;
                                                android_ws_connect((void*){0}.mPtr, urlCopy.c_str(), subprotoCopy.c_str());
                                        }
                                }
                                ', this);
                                #else
                                untyped __cpp__('
                                WebSocketState* st = nullptr;
                                {
                                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                                        auto it = _ws_map.find((void*){0}.mPtr);
                                        if (it != _ws_map.end()) st = it->second;
                                }
                                if (st) { st->shouldConnect.store(true); }
                                ', this);
                                #end
                        #elseif html5
                        connectWebSocket();
            #end
        }

        // ── Disconnect trigger ──
        if (disconnectC != null && disconnectC.value == true)
        {
            disconnectC.value = false;
            // Mark as user-requested — auto-reconnect will be suppressed
            // until next explicit connect pulse.
            _userRequestedDisconnect = true;
                        #if cpp
                                #if android
                                untyped __cpp__('android_ws_disconnect((void*){0}.mPtr);', this);
                                #else
                                untyped __cpp__('
                                WebSocketState* st = nullptr;
                                {
                                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                                        auto it = _ws_map.find((void*){0}.mPtr);
                                        if (it != _ws_map.end()) st = it->second;
                                }
                                if (st) { st->shouldDisconnect.store(true); }
                                ', this);
                                #end
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
                // ── Apply line-ending append based on _lastAppendMode ──
                // "none" → no change, "CR" → \r, "LF" → \n, "CRLF" → \r\n.
                // Applied uniformly to text AND binary modes. In binary mode
                // the appended chars become bytes 0x0D / 0x0A respectively,
                // since sendWebSocketData() encodes each char as a single byte.
                if (_lastAppendMode == "CR")
                {
                    data += "\r";
                }
                else if (_lastAppendMode == "LF")
                {
                    data += "\n";
                }
                else if (_lastAppendMode == "CRLF")
                {
                    data += "\r\n";
                }
                                #if cpp
                                                #if android
                                                untyped __cpp__('
                                                {
                                                        const char* dataChars = (const char*){1}.__s;
                                                        int dataLen = {1}.length;
                                                        android_ws_send((void*){0}.mPtr, dataChars, dataLen);
                                                }
                                                ', this, data);
                                                #else
                                                untyped __cpp__('
                                                WebSocketState* st = nullptr;
                                                {
                                                        std::lock_guard<std::mutex> lock(_ws_map_mutex);
                                                        auto it = _ws_map.find((void*){0}.mPtr);
                                                        if (it != _ws_map.end()) st = it->second;
                                                }
                                                if (st) {
                                                        std::lock_guard<std::mutex> lk(st->sendQueueMtx);
                                                        st->sendQueue.push(std::string((const char*){1}.__s));
                                                        st->hasPendingSend.store(true);
                                                }
                                                ', this, data);
                                                #end
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
     * │  WebSocket.onopen    ──►    _isConnectedFlag = true         │
     * │                                                              │
     * │  WebSocket.onmessage ──►   _hasPendingReceived = true       │
     * │                            _pendingReceivedStr = data       │
     * │                                  │                          │
     * │                                  ▼                          │
     * │                            update(dt) polls flag            │
     * │                                  │                          │
     * │                                  ▼                          │
     * │                            propagateCurrentValue()          │
     * │                                                              │
     * │  WebSocket.onclose   ──►    _lastCloseCode = e.code         │
     * │                            _hasPendingClose = true          │
     * │                            _isConnectedFlag = false         │
     * │                                                              │
     * │  WebSocket.onerror   ──►    _pendingErrStr = "..."          │
     * │                            _hasPendingError = true          │
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
            // Create WebSocket with optional subprotocols.
            // Per HTML5 WebSocket spec, the second argument is an array of
            // subprotocol strings — the browser handles Sec-WebSocket-Protocol
            // negotiation automatically.
            if (_pendingSubprotocols != null && _pendingSubprotocols.length > 0)
            {
                _webSocket = new WebSocket(_lastUrl, _pendingSubprotocols);
            }
            else
            {
                _webSocket = new WebSocket(_lastUrl);
            }

            // Configure binary mode for incoming data.
            // 'arraybuffer' gives us ArrayBuffer (clean for binary),
            // 'blob' would give Blob (asynchronous to read).
            _webSocket.binaryType = ARRAYBUFFER;

            _webSocket.onopen = function(e:Event) {
                _isConnectedFlag = true;
                _lastError = "";
                trace('WebSocketAtom: Connected to $_lastUrl');
            };

            _webSocket.onmessage = function(e:MessageEvent) {
                if (e.data == null) return;

                if (Std.isOfType(e.data, ArrayBuffer))
                {
                    // Binary frame — convert to string preserving raw bytes.
                    var ab:ArrayBuffer = cast e.data;
                    var u8:Uint8Array = new Uint8Array(ab);
                    var sb = new StringBuf();
                    for (i in 0...u8.length)
                    {
                        sb.addChar(u8[i]);
                    }
                    _pendingReceivedStr = sb.toString();
                    _bytesReceived += u8.length;
                }
                else if (Std.isOfType(e.data, String))
                {
                    _pendingReceivedStr = cast e.data;
                    _bytesReceived += _pendingReceivedStr.length;
                }
                else
                {
                    // Blob or other — fall back to string repr.
                    _pendingReceivedStr = Std.string(e.data);
                    _bytesReceived += _pendingReceivedStr.length;
                }
                _hasPendingReceived = true;
            };

            _webSocket.onerror = function(e:Event) {
                // Browsers don't expose error details for security reasons.
                // The onclose handler will fire next with code 1006 typically.
                setError("WebSocket error (browser does not expose details)");
            };

            _webSocket.onclose = function(e:CloseEvent) {
                _isConnectedFlag = false;
                _lastCloseCode = e.code;
                _hasPendingClose = true;
                if (e.code != 1000 && e.code != 1001)
                {
                    // Non-normal close — surface as error too.
                    setError('WebSocket closed (code ${e.code}${e.reason != "" ? ": " + e.reason : ""})');
                }
                trace('WebSocketAtom: Connection closed (code ${e.code})');
            };
        }
        catch (e:Dynamic) {
            setError('Failed to create WebSocket: $e');
        }
    }

    /**
     * Close native WebSocket connection gracefully.
     * Uses code 1000 "Normal Closure" per RFC 6455 §7.4.
     */
    private function disconnectWebSocket():Void
    {
        if (_webSocket != null)
        {
            try
            {
                // Check readyState: 0=CONNECTING, 1=OPEN, 2=CLOSING, 3=CLOSED
                if (_webSocket.readyState == 1) // OPEN
                {
                    _webSocket.close(1000, "Client disconnect");
                }
            }
            catch (e:Dynamic) { /* ignore */ }
            _webSocket = null;
            _isConnectedFlag = false;
        }
    }

    /**
     * Send data through native WebSocket.
     *
     * Per RFC 6455, clients MUST NOT mask — browsers handle masking internally.
     * For binary mode, the string is interpreted as a sequence of UTF-16 code
     * units (Haxe String) — we encode each char as a byte (0x00-0xFF). For
     * proper binary data, use hex-decoded bytes.
     *
     * @param data String data to send
     */
    private function sendWebSocketData(data:String):Void
    {
        if (_webSocket == null || !_isConnectedFlag) return;

        try
        {
            if (_lastBinaryMode)
            {
                // Binary mode: convert string chars to bytes.
                // Haxe String is UTF-16 internally; for binary payloads we
                // treat each char's code as a single byte (0x00-0xFF).
                var len:Int = data.length;
                var ab:ArrayBuffer = new ArrayBuffer(len);
                var u8:Uint8Array = new Uint8Array(ab);
                for (i in 0...len)
                {
                    u8[i] = data.charCodeAt(i) & 0xFF;
                }
                _webSocket.send(ab);
                _bytesSent += len;
            }
            else
            {
                // Text mode: send as plain UTF-8 string.
                _webSocket.send(data);
                _bytesSent += data.length;
            }
        }
        catch (e:Dynamic) {
            setError('Send failed: $e');
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
        trace('WebSocketAtom ERROR: $msg');
    }

    #end // #if html5

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
                _receivedTimer = 0;
                var c = getOutput("receivedTick");
                if (c != null) c.value = false;
            }
        }
        if (_sentTimer > 0)
        {
            _sentTimer -= dt;
            if (_sentTimer <= 0)
            {
                _sentTimer = 0;
                var c = getOutput("sentTick");
                if (c != null) c.value = false;
            }
        }
        if (_errorTimer > 0)
        {
            _errorTimer -= dt;
            if (_errorTimer <= 0)
            {
                _errorTimer = 0;
                var c = getOutput("errorTick");
                if (c != null) c.value = false;
            }
        }
    }
}
