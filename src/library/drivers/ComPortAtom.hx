package library.drivers;
#if cpp

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// DO NOT include windows.h in header!
// All Windows types are available only in .cpp via @:cppFileCode and __cpp__()
#include <string>
#include <thread>
#include <mutex>
#include <map>
')

@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOGDI
#include <windows.h>
#pragma comment(lib, "advapi32.lib")
#endif

// ================================================================
// C++ PORT STATE STRUCTURE
// ================================================================
struct ComPortState {
    HANDLE hComm;
    std::thread* readThread;
    volatile bool isRunning;
    char rxBuffer[1024];
    bool hasRxData;
    std::mutex rxMutex;
    char errBuffer[256];
    bool hasError;
    std::mutex errMutex;
};

static std::map<void*, ComPortState*> _com_states_map;
static std::mutex _com_map_mutex;

// ================================================================
// BACKGROUND READ THREAD (Rx)
// ================================================================
// FIXED: Proper ReadFile handling on timeout
//
// When COMMTIMEOUTS are configured and no data is available, ReadFile can:
//   a) return FALSE + GetLastError() == ERROR_TIMEOUT  → NOT an error!
//   b) return TRUE  + bytesRead == 0                    → NOT an error!
//   c) return FALSE + GetLastError() == ERROR_OPERATION_ABORTED → port closed
//   d) return TRUE  + bytesRead > 0                     → data available!
//   e) return FALSE + other error code                  → real error
//
static void _altauri_com_reader_loop(void* haxePtr) {
    ComPortState* st = nullptr;
    {
        std::lock_guard<std::mutex> mapLock(_com_map_mutex);
        auto it = _com_states_map.find(haxePtr);
        if (it == _com_states_map.end()) return;
        st = it->second;
    }

    st->isRunning = true;

    char tempBuf[1024];
    DWORD bytesRead;

    while (st->isRunning) {
#ifdef _WIN32
        bytesRead = 0;
        BOOL bResult = ReadFile(st->hComm, tempBuf, sizeof(tempBuf) - 1, &bytesRead, NULL);

        if (bResult && bytesRead > 0) {
            // ── CASE (d): Data received ──
            tempBuf[bytesRead] = 0;
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            strncpy(st->rxBuffer, tempBuf, sizeof(st->rxBuffer) - 1);
            st->rxBuffer[sizeof(st->rxBuffer) - 1] = 0;
            st->hasRxData = true;
        }
        else if (bResult && bytesRead == 0) {
            // ── CASE (b): Timeout, no data — continue ──
            continue;
        }
        else {
            // ── ReadFile returned FALSE ──
            DWORD lastError = GetLastError();

            if (lastError == ERROR_TIMEOUT) {
                // ── CASE (a): Timeout — NOT an error, continue ──
                continue;
            }

            if (lastError == ERROR_OPERATION_ABORTED || !st->isRunning) {
                // ── CASE (c): Port closing — normal exit ──
                break;
            }

            // ── CASE (e): Real error ──
            std::lock_guard<std::mutex> errLock(st->errMutex);
            sprintf(st->errBuffer, "Rx Err:%lu", lastError);
            st->hasError = true;
            break;
        }
#endif
    }

    st->isRunning = false;
}
')

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     COM PORT ATOM v1.0                                    ║
 * ║                     (Serial Communication Driver)                         ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Serial port driver with background read thread.                          ║
 * ║  Supports COM1-COM256, configurable baud rate, DTR control.               ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     ComPortAtom                                     │  ║
 * ║  │                                                                     │  ║
 * ║  │  A) COMPUTE MODULE:                                                 │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     Background Thread (C++):                                        │  ║
 * ║  │       1. ReadFile() from COM port                                   │  ║
 * ║  │       2. Handle timeouts and errors                                 │  ║
 * ║  │       3. Write to rxBuffer (thread-safe with mutex)                 │  ║
 * ║  │                                                                     │  ║
 * ║  │     update(dt) {                                                    │  ║
 * ║  │       1. Poll C++ buffer for new data                               │  ║
 * ║  │       2. Write to output contacts (silent + propagate)              │  ║
 * ║  │       3. Read inputs and control port                               │  ║
 * ║  │       4. Update pulse timers                                        │  ║
 * ║  │     }                                                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  B) DATABANK:                                                       │  ║
 * ║  │     ─────────────                                                   │  ║
 * ║  │     _lastTxData:String   - Last transmitted data                    │  ║
 * ║  │     _lastDTR:Bool        - Last DTR state                           │  ║
 * ║  │     _isOpenFlag:Bool     - Port open status                         │  ║
 * ║  │                                                                     │  ║
 * ║  │  C) INPUTS:                                                         │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "portName"  - Port name (String, e.g., "COM1")                  │  ║
 * ║  │     "baudRate"  - Baud rate (Int, e.g., 9600)                       │  ║
 * ║  │     "open"      - Open trigger (Bool)                               │  ║
 * ║  │     "close"     - Close trigger (Bool)                              │  ║
 * ║  │     "send"      - Send trigger (Bool)                               │  ║
 * ║  │     "txData"    - Data to transmit (String)                         │  ║
 * ║  │     "setDTR"    - DTR control (Bool)                                │  ║
 * ║  │                                                                     │  ║
 * ║  │  D) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "isOpen"    - Port open status (Bool)                           │  ║
 * ║  │     "rxData"    - Received data (String)                            │  ║
 * ║  │     "rxTick"    - Receive pulse (Bool, short-lived)                 │  ║
 * ║  │     "txTick"    - Transmit pulse (Bool, short-lived)                │  ║
 * ║  │     "error"     - Error message (String)                            │  ║
 * ║  │     "errorTick" - Error pulse (Bool, short-lived)                   │  ║
 * ║  │                                                                     │  ║
 * ║  │  E) FACE (DeviceView):                                              │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     ComPortWidget for interactive control                           │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                      THREAD SAFETY                                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Background Thread (C++) ──► Pending Fields ──► Main Thread (Haxe)        ║
 * ║                                                                           ║
 * ║  Pattern:                                                                 ║
 * ║  1. Background thread writes to rxBuffer/errBuffer with mutex             ║
 * ║  2. Main thread polls in update() and copies to pending fields            ║
 * ║  3. Main thread writes to output contacts                                 ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    APPLICATION                                            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  • Serial communication with microcontrollers (Arduino, ESP32)            ║
 * ║  • Industrial equipment control (PLC, CNC)                                ║
 * ║  • Modem/AT command interface                                             ║
 * ║  • GPS receiver data acquisition                                          ║
 * ║  • Custom protocol communication                                          ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class ComPortAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var PULSE_DURATION:Float = 0.05;

    // =========================================================================
    // PARAMETERS AND INPUTS
    // =========================================================================
    private var _lastTxData:String = "";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;

    // =========================================================================
    // PENDING FIELDS
    // =========================================================================
    @:volatile private var _hasPendingRx:Bool = false;
    @:volatile private var _hasPendingErr:Bool = false;
    private var _pendingRxStr:String = "";
    private var _pendingErrStr:String = "";

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private var _rxTimer:Float = 0.0;
    private var _txTimer:Float = 0.0;
    private var _errTimer:Float = 0.0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [ // INPUTS
                new Contact("COM1", INPUT, "portName"),
                new Contact(9600, INPUT, "baudRate"),
                new Contact(false, INPUT, "open"),
                new Contact(false, INPUT, "close"),
                new Contact(false, INPUT, "send"),
                new Contact("", INPUT, "txData"),
                new Contact(false, INPUT, "setDTR")
            ],
            [ // OUTPUTS
                new Contact(false, OUTPUT, "isOpen"),
                new Contact("", OUTPUT, "rxData"),
                new Contact(false, OUTPUT, "rxTick"),
                new Contact(false, OUTPUT, "txTick"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "ComPortAtom",
            true
        );
        
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        // Port opens on "open" trigger
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // 1. POLL C++ BUFFER
        untyped __cpp__('
            ComPortState* _cps_stPtr = nullptr;
            {
                std::lock_guard<std::mutex> _cps_mapLock(_com_map_mutex);
                auto _cps_it = _com_states_map.find((void*){0}.mPtr);
                if (_cps_it != _com_states_map.end()) {
                    _cps_stPtr = _cps_it->second;
                }
            }
            if (_cps_stPtr) {
                {
                    std::lock_guard<std::mutex> _cps_rxLock(_cps_stPtr->rxMutex);
                    if (_cps_stPtr->hasRxData) {
                        {0}->_pendingRxStr = ::String(_cps_stPtr->rxBuffer);
                        {0}->_hasPendingRx = true;
                        _cps_stPtr->hasRxData = false;
                    }
                }
                {
                    std::lock_guard<std::mutex> _cps_errLock(_cps_stPtr->errMutex);
                    if (_cps_stPtr->hasError) {
                        {0}->_pendingErrStr = ::String(_cps_stPtr->errBuffer);
                        {0}->_hasPendingErr = true;
                        _cps_stPtr->hasError = false;
                    }
                }
            }
        ', this);

        // 2. PROCESS PENDING DATA
        if (_hasPendingRx)
        {
            _hasPendingRx = false;
            var rxOut = getOutput("rxData");
            if (rxOut != null) {
                rxOut.setValueSilent(_pendingRxStr);
                rxOut.propagateCurrentValue();
            }
            var rxTick = getOutput("rxTick");
            if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
        }

        if (_hasPendingErr)
        {
            _hasPendingErr = false;
            var errOut = getOutput("error");
            if (errOut != null) {
                errOut.setValueSilent(_pendingErrStr);
                errOut.propagateCurrentValue();
            }
            var errTick = getOutput("errorTick");
            if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
        }

        // 3. READ INPUTS AND CONTROL
        readInputs();

        // 4. UPDATE PULSE TIMERS
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // INPUT READING
    // =========================================================================
    private function readInputs():Void
    {
        var openC  = getInput("open");
        var closeC = getInput("close");
        var sendC  = getInput("send");
        var txC    = getInput("txData");
        var dtrC   = getInput("setDTR");

        if (openC != null && openC.value == true) {
            openDevice();
            openC.value = false;
        }

        if (closeC != null && closeC.value == true) {
            closeDevice();
            closeC.value = false;
        }

        if (sendC != null && sendC.value == true && _isOpenFlag) {
            if (txC != null && txC.value != null && txC.value != "") {
                sendToDevice(txC.value);
                var txTick = getOutput("txTick");
                if (txTick != null) { txTick.value = true; _txTimer = PULSE_DURATION; }
            }
            sendC.value = false;
        }

        if (dtrC != null && dtrC.value != null) {
            var newDTR:Bool = dtrC.value == true;
            if (newDTR != _lastDTR && _isOpenFlag) {
                _lastDTR = newDTR;
                setDTRState(newDTR);
            }
        }
    }

    // =========================================================================
    // DEVICE OPERATION
    // =========================================================================
    private function openDevice():Void
    {
        if (_isOpenFlag) closeDevice();

        var portNameStr:String = getInput("portName").value;
        var baudRateInt:Int = Std.int(getInput("baudRate").value);

        untyped __cpp__('
            ComPortState* st = new ComPortState();
            st->hComm = INVALID_HANDLE_VALUE;
            st->readThread = nullptr;
            st->isRunning = false;
            st->hasRxData = false;
            st->hasError = false;
            st->rxBuffer[0] = 0;
            st->errBuffer[0] = 0;

#ifdef _WIN32
            // Format port name (support for COM10+)
            // Always add dot-slash prefix for any COM port
            // charCodeAt is unreliable in __cpp__, check via C-string
            char fullPortName[20] = "";
            ::String portStr = {1};
            const char* _cps_rawName = portStr.c_str();

            if (_cps_rawName[0] == (char)92) {
                // Already contains path prefix - use as is
                strncpy(fullPortName, _cps_rawName, sizeof(fullPortName) - 1);
            } else {
                // Add path prefix
                fullPortName[0] = (char)92;  // backslash
                fullPortName[1] = (char)92;  // backslash
                fullPortName[2] = (char)46;  // dot
                fullPortName[3] = (char)92;  // backslash
                strncpy(fullPortName + 4, _cps_rawName, sizeof(fullPortName) - 5);
            }
            fullPortName[sizeof(fullPortName) - 1] = 0;

            // Open port
            st->hComm = CreateFileA(fullPortName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);

            if (st->hComm == INVALID_HANDLE_VALUE) {
                DWORD err = GetLastError();
                sprintf(st->errBuffer, "Open Failed:%lu", err);
                st->hasError = true;
            } else {
                // ── Set buffer sizes (reduces latency) ──
                SetupComm(st->hComm, 4096, 4096);

                // ── Configure DCB (speed, 8-N-1) ──
                DCB dcbSerialParams;
                memset(&dcbSerialParams, 0, sizeof(DCB));
                dcbSerialParams.DCBlength = sizeof(DCB);
                GetCommState(st->hComm, &dcbSerialParams);

                dcbSerialParams.BaudRate = (DWORD){2};
                dcbSerialParams.ByteSize = 8;
                dcbSerialParams.StopBits = ONESTOPBIT;
                dcbSerialParams.Parity = NOPARITY;

                // Explicitly control DTR/RTS — prevent driver from toggling lines
                dcbSerialParams.fDtrControl = DTR_CONTROL_ENABLE;
                dcbSerialParams.fRtsControl = RTS_CONTROL_ENABLE;

                if (!SetCommState(st->hComm, &dcbSerialParams)) {
                    DWORD err = GetLastError();
                    sprintf(st->errBuffer, "SetCommState:%lu", err);
                    st->hasError = true;
                    CloseHandle(st->hComm);
                    st->hComm = INVALID_HANDLE_VALUE;
                } else {
                    // ── Configure timeouts ──
                    // ReadIntervalTimeout = MAXDWORD + ReadTotalTimeout = 0
                    // → ReadFile returns IMMEDIATELY with whatever is in the buffer
                    // This is the best pattern for non-blocking reads
                    COMMTIMEOUTS timeouts;
                    memset(&timeouts, 0, sizeof(COMMTIMEOUTS));
                    timeouts.ReadIntervalTimeout = MAXDWORD;
                    timeouts.ReadTotalTimeoutMultiplier = 0;
                    timeouts.ReadTotalTimeoutConstant = 0;
                    timeouts.WriteTotalTimeoutMultiplier = 10;
                    timeouts.WriteTotalTimeoutConstant = 100;
                    SetCommTimeouts(st->hComm, &timeouts);

                    // ── Clear buffers from garbage ──
                    PurgeComm(st->hComm, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);

                    // ── Start background read thread ──
                    st->readThread = new std::thread(_altauri_com_reader_loop, (void*){0}.mPtr);
                }
            }
#endif

            // Save pointer to map and check success
            {
                std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
                _com_states_map[(void*){0}.mPtr] = st;
                {0}->_isOpenFlag = (st->hComm != INVALID_HANDLE_VALUE);
            }
        ', this, portNameStr, baudRateInt);

        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = _isOpenFlag;
    }

    private function closeDevice():Void
    {
        if (!_isOpenFlag) return;

        // First extract pointer from map (brief lock),
        // then free resources WITHOUT holding the mutex —
        // to avoid hanging on join() with lock held
        untyped __cpp__('
            ComPortState* st = nullptr;
            {
                std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
                auto _cps_it = _com_states_map.find((void*){0}.mPtr);
                if (_cps_it != _com_states_map.end()) {
                    st = _cps_it->second;
                    _com_states_map.erase(_cps_it);
                }
            }

            if (st) {
#ifdef _WIN32
                // Signal thread to stop
                st->isRunning = false;

                // Cancel pending ReadFile
                if (st->hComm != INVALID_HANDLE_VALUE) {
                    CancelIoEx(st->hComm, NULL);
                }

                // Wait for thread completion (already without mutex!)
                if (st->readThread && st->readThread->joinable()) {
                    st->readThread->join();
                }
                delete st->readThread;

                // Close port
                if (st->hComm != INVALID_HANDLE_VALUE) {
                    PurgeComm(st->hComm, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);
                    CloseHandle(st->hComm);
                }
#endif
                delete st;
            }
        ', this);

        _isOpenFlag = false;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = false;
    }

    private function sendToDevice(data:String):Void
    {
        untyped __cpp__('
            ComPortState* _cps_stPtr = nullptr;
            {
                std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
                auto _cps_it = _com_states_map.find((void*){0}.mPtr);
                if (_cps_it != _com_states_map.end()) {
                    _cps_stPtr = _cps_it->second;
                }
            }

            if (_cps_stPtr) {
#ifdef _WIN32
                if (_cps_stPtr->hComm != INVALID_HANDLE_VALUE) {
                    const char* buffer = {1}.c_str();
                    DWORD bytesToWrite = (DWORD)strlen(buffer);
                    DWORD bytesWritten;
                    WriteFile(_cps_stPtr->hComm, buffer, bytesToWrite, &bytesWritten, NULL);
                }
#endif
            }
        ', this, data);
    }

    private function setDTRState(state:Bool):Void
    {
        untyped __cpp__('
            ComPortState* _cps_stPtr = nullptr;
            {
                std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
                auto _cps_it = _com_states_map.find((void*){0}.mPtr);
                if (_cps_it != _com_states_map.end()) {
                    _cps_stPtr = _cps_it->second;
                }
            }

            if (_cps_stPtr) {
#ifdef _WIN32
                if (_cps_stPtr->hComm != INVALID_HANDLE_VALUE) {
                    if ({1}) {
                        EscapeCommFunction(_cps_stPtr->hComm, SETDTR);
                    } else {
                        EscapeCommFunction(_cps_stPtr->hComm, CLRDTR);
                    }
                }
#endif
            }
        ', this, state);
    }

    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    private function updatePulseTimers(dt:Float):Void
    {
        if (_rxTimer > 0) {
            _rxTimer -= dt;
            if (_rxTimer <= 0) { var c = getOutput("rxTick"); if (c != null) c.value = false; }
        }
        if (_txTimer > 0) {
            _txTimer -= dt;
            if (_txTimer <= 0) { var c = getOutput("txTick"); if (c != null) c.value = false; }
        }
        if (_errTimer > 0) {
            _errTimer -= dt;
            if (_errTimer <= 0) { var c = getOutput("errorTick"); if (c != null) c.value = false; }
        }
    }
}
#end