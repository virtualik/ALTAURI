// FILE: library/drivers/ComPortAtom.hx
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

#if cpp
@:headerCode('
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
            tempBuf[bytesRead] = 0;
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            
            // === FIX: Safe concatenation with overflow protection ===
            size_t currentLen = strlen(st->rxBuffer);
            size_t newLen = currentLen + bytesRead;
            
            if (newLen >= sizeof(st->rxBuffer)) {
                size_t overflow = newLen - (sizeof(st->rxBuffer) - 1);
                memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                st->rxBuffer[currentLen - overflow] = 0;
                currentLen = currentLen - overflow;
            }
            
            strncpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
            st->rxBuffer[currentLen + bytesRead] = 0;
            st->hasRxData = true;
        }
        else if (bResult && bytesRead == 0) {
            continue;
        }
        else {
            DWORD lastError = GetLastError();
            if (lastError == ERROR_TIMEOUT) { continue; }
            if (lastError == ERROR_OPERATION_ABORTED || !st->isRunning) { break; }
            
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
#end

/**
 * COM PORT ATOM v2.3 (Dual-Platform + Zero-GC Batching + Test Bypass)
 *
 * Serial port driver with platform-specific backends.
 * At compile time, Haxe selects the appropriate backend.
 *
 * ─────────────────────────────────────────────────────────────────────
 * │                    COMPILATION FLOW                                 │
 * │                                                                     │
 * │  haxe -cpp  ──► #if cpp   ──► WinAPI + Background Thread          │
 * │  haxe -html5──► #if html5 ──► Browser Web Serial API              │
 * │                                                                     │
 * │  Common code (contacts, update logic, ring buffer) is shared.       │
 * │  Platform-specific code is isolated in #if blocks.                  │
 * └─────────────────────────────────────────────────────────────────────┘
 *
 * v2.3 Changes:
 * - ADDED: "testRxData" INPUT contact to bypass C++ backend for UI pipeline testing.
 * - OPTIMIZED: Batched Driver Update Pattern (setValueSilent + propagateCurrentValue)
 *   to prevent TickGenerator overload and UI freezes during large data bursts.
 * - FIXED: C++ rxBuffer explicitly cleared after reading to prevent stale data races.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │                     ComPortAtom                                     │
 * │                                                                     │
 * │  COMMON LAYER (all targets):                                        │
 * │  • Contacts: portName, baudRate, open, close, send, txData, setDTR │
 * │  • Outputs: isOpen, rxData, rxTick, txTick, error, errorTick       │
 * │  • Ring buffer for sequential Rx emission                          │
 * │  • update(dt): propagation + pulse timers                          │
 * │                                                                     │
 * │  #if cpp:                                                           │
 * │  • ComPortState* (C++)                                              │
 * │  • Background thread with ReadFile()                                │
 * │  • Mutex/Atomic sync                                                │
 * │                                                                     │
 * │  #if html5:                                                         │
 * │  • Dynamic _serialPort (Web Serial API)                            │
 * │  • Async read loop via navigator.serial                            │
 * │  • Single-threaded (browser event loop)                            │
 * └─────────────────────────────────────────────────────────────────────┘
 */
class ComPortAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var PULSE_DURATION:Float = 0.05;
    private static inline var DEFAULT_BUFFER_SIZE:Int = 4096;
    private static inline var DEFAULT_CHUNK_SIZE:Int = 256;
    private static inline var MIN_BUFFER_SIZE:Int = 256;
    private static inline var MAX_BUFFER_SIZE:Int = 65536;
    private static inline var MIN_CHUNK_SIZE:Int = 1;
    private static inline var MAX_CHUNK_SIZE:Int = 4096;

    // =========================================================================
    // RING BUFFER (COMMON)
    // =========================================================================
    private var _ringBuffer:Array<Int>;
    private var _readPos:Int = 0;
    private var _writePos:Int = 0;
    private var _overflowCount:Int = 0;
    private var _bufferSize:Int = DEFAULT_BUFFER_SIZE;
    private var _chunkSize:Int = DEFAULT_CHUNK_SIZE;
    private var _enabled:Bool = true;

    // =========================================================================
    // PARAMETERS AND INPUTS (COMMON)
    // =========================================================================
    private var _lastTxData:String = "";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;

    // =========================================================================
    // PENDING FIELDS (COMMON)
    // =========================================================================
    @:volatile private var _hasPendingRx:Bool = false;
    @:volatile private var _hasPendingErr:Bool = false;
    private var _pendingRxStr:String = "";
    private var _pendingErrStr:String = "";

    // =========================================================================
    // PULSE TIMERS (COMMON)
    // =========================================================================
    private var _rxTimer:Float = 0.0;
    private var _txTimer:Float = 0.0;
    private var _errTimer:Float = 0.0;

    // =========================================================================
    // PLATFORM-SPECIFIC FIELDS
    // =========================================================================
    #if cpp
    // C++ fields are managed via __cpp__() — no Haxe fields needed
    #elseif html5
    /** Native browser SerialPort instance (Dynamic — Web Serial API not in Haxe externs). */
    private var _serialPort:Dynamic = null;
    /** Readable stream reader. */
    private var _reader:Dynamic = null;
    /** Writable stream writer. */
    private var _writer:Dynamic = null;
    /** Read loop active flag. */
    private var _isReading:Bool = false;
    #end

    // =========================================================================
    // CONSTRUCTOR (COMMON)
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact("COM1", INPUT, "portName"),
                new Contact(9600, INPUT, "baudRate"),
                new Contact(DEFAULT_BUFFER_SIZE, INPUT, "bufferSize"),
                new Contact(DEFAULT_CHUNK_SIZE, INPUT, "chunkSize"),
                new Contact(true, INPUT, "enabled"),
                new Contact(false, INPUT, "open"),
                new Contact(false, INPUT, "close"),
                new Contact(false, INPUT, "send"),
                new Contact("", INPUT, "txData"),
                new Contact(false, INPUT, "setDTR"),
                // FIX: Added as INPUT to allow injecting test data to bypass C++ backend
                new Contact("", INPUT, "testRxData") 
            ],
            [
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
        initRingBuffer(DEFAULT_BUFFER_SIZE);
        init();
    }

    // =========================================================================
    // RING BUFFER MANAGEMENT (COMMON)
    // =========================================================================
    private function initRingBuffer(size:Int):Void
    {
        _bufferSize = size;
        _ringBuffer = new Array<Int>();
        for (i in 0..._bufferSize)
        {
            _ringBuffer.push(0);
        }
        _readPos = 0;
        _writePos = 0;
        _overflowCount = 0;
    }

    private function writeToBuffer(data:Array<Int>):Int
    {
        var written = 0;
        for (byte in data)
        {
            var idx = _writePos % _bufferSize;
            _ringBuffer[idx] = byte;
            _writePos++;
            written++;
            if (getBufferCount() > _bufferSize)
            {
                _readPos = _writePos - _bufferSize;
                _overflowCount++;
                if (_overflowCount % 100 == 0)
                {
                    trace('ComPortAtom: Ring buffer overflow! Lost $_overflowCount bytes total');
                }
            }
        }
        return written;
    }

    private function getBufferCount():Int
    {
        return _writePos - _readPos;
    }

    private function clearBuffer():Void
    {
        _readPos = 0;
        _writePos = 0;
        _overflowCount = 0;
    }

    /**
     * Read data from ring buffer and emit via rxData output.
     *
     * Emits up to _chunkSize bytes per call to prevent blocking.
     * Data is emitted sequentially in the order it was received.
     */
    private function emitRxData():Void
    {
        var availableBytes = getBufferCount();
        if (availableBytes == 0) return;

        // Limit chunk size to prevent blocking
        var bytesToRead:Int = Std.int(Math.min(availableBytes, _chunkSize));

        // Build string from ring buffer character by character
        var rxString = "";
        for (i in 0...bytesToRead)
        {
            var idx = _readPos % _bufferSize;
            rxString += String.fromCharCode(_ringBuffer[idx]);
            _readPos++;
        }

        // Emit via output using Batched Driver Update Pattern
        var rxOut = getOutput("rxData");
        if (rxOut != null)
        {
            rxOut.setValueSilent(rxString);
            rxOut.propagateCurrentValue();
        }

        // Pulse
        var rxTick = getOutput("rxTick");
        if (rxTick != null)
        {
            rxTick.value = true;
            _rxTimer = PULSE_DURATION;
        }
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

        // Read configuration inputs
        readConfiguration();

        if (!_enabled) return;

        // === FIX: Test RX data bypass (Direct passthrough to rxData output) ===
        var testRxC = getInput("testRxData");
        if (testRxC != null && testRxC.value != null && testRxC.value != "")
        {
            var testData:String = Std.string(testRxC.value);
            var rxOut = getOutput("rxData");
            if (rxOut != null)
            {
                rxOut.setValueSilent(testData);
                rxOut.propagateCurrentValue();
            }
            var rxTick = getOutput("rxTick");
            if (rxTick != null)
            {
                rxTick.value = true;
                _rxTimer = PULSE_DURATION;
            }
            // Clear the test input to prevent continuous firing
            testRxC.value = "";
            // Skip C++ polling if we are in test mode to ensure clean isolation
        }
        else 
        {
            // Poll platform backend
            #if cpp
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
                        _cps_stPtr->rxBuffer[0] = 0; // FIX: Explicitly clear buffer after reading
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
            #end
        }

        // HTML5: _hasPendingRx is set by WebSocket callbacks
        // Process pending received data using Batched Driver Update Pattern
        if (_hasPendingRx)
        {
            _hasPendingRx = false;
            var rxOut = getOutput("rxData");
            if (rxOut != null)
            {
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
            if (errOut != null)
            {
                errOut.setValueSilent(_pendingErrStr);
                errOut.propagateCurrentValue();
            }
            var errTick = getOutput("errorTick");
            if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
        }

        // Emit from ring buffer (HTML5 sequential emission)
        #if html5
        emitRxData();
        #end

        // Read inputs and control
        readInputs();

        // Update pulse timers
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        #if cpp
        closeDevice();
        #elseif html5
        if (_isOpenFlag)
        {
            closeDevice();
        }
        #end
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // CONFIGURATION READING (COMMON)
    // =========================================================================
    private function readConfiguration():Void
    {
        var bufSizeC = getInput("bufferSize");
        if (bufSizeC != null && bufSizeC.value != null)
        {
            var newSize = Std.int(bufSizeC.value);
            if (newSize >= MIN_BUFFER_SIZE && newSize <= MAX_BUFFER_SIZE && newSize != _bufferSize)
            {
                trace('ComPortAtom: Buffer size changed from $_bufferSize to $newSize');
                initRingBuffer(newSize);
            }
        }

        var chunkC = getInput("chunkSize");
        if (chunkC != null && chunkC.value != null)
        {
            var newChunk = Std.int(chunkC.value);
            if (newChunk >= MIN_CHUNK_SIZE && newChunk <= MAX_CHUNK_SIZE)
            {
                _chunkSize = newChunk;
            }
        }

        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null)
        {
            _enabled = (enabledC.value == true);
        }
    }

    // =========================================================================
    // INPUT READING (COMMON)
    // =========================================================================
    private function readInputs():Void
    {
        var openC  = getInput("open");
        var closeC = getInput("close");
        var sendC  = getInput("send");
        var txC    = getInput("txData");
        var dtrC   = getInput("setDTR");
        var baudC = getInput("baudRate");

        if (baudC != null && baudC.value != null)
        {
            var newBaud = Std.int(baudC.value);
            if (newBaud > 0 && newBaud != 9600)
            {
                if (_isOpenFlag)
                {
                    closeDevice();
                    openDevice();
                }
            }
        }

        if (openC != null && openC.value == true)
        {
            openDevice();
            openC.value = false;
        }

        if (closeC != null && closeC.value == true)
        {
            closeDevice();
            closeC.value = false;
        }

        if (sendC != null && sendC.value == true && _isOpenFlag)
        {
            if (txC != null && txC.value != null && txC.value != "")
            {
                sendToDevice(txC.value);
                var txTick = getOutput("txTick");
                if (txTick != null) { txTick.value = true; _txTimer = PULSE_DURATION; }
            }
            sendC.value = false;
        }

        if (dtrC != null && dtrC.value != null)
        {
            var newDTR:Bool = dtrC.value == true;
            if (newDTR != _lastDTR && _isOpenFlag)
            {
                _lastDTR = newDTR;
                setDTRState(newDTR);
            }
        }
    }

    // =========================================================================
    // DEVICE OPERATION (C++ WinAPI)
    // =========================================================================
    #if cpp
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
        char fullPortName[20] = "";
        ::String portStr = {1};
        const char* _cps_rawName = portStr.c_str();
        if (_cps_rawName[0] == (char)92) {
            strncpy(fullPortName, _cps_rawName, sizeof(fullPortName) - 1);
        } else {
            fullPortName[0] = (char)92;
            fullPortName[1] = (char)92;
            fullPortName[2] = (char)46;
            fullPortName[3] = (char)92;
            strncpy(fullPortName + 4, _cps_rawName, sizeof(fullPortName) - 5);
        }
        fullPortName[sizeof(fullPortName) - 1] = 0;
        st->hComm = CreateFileA(fullPortName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (st->hComm == INVALID_HANDLE_VALUE) {
            DWORD err = GetLastError();
            sprintf(st->errBuffer, "Open Failed:%lu", err);
            st->hasError = true;
        } else {
            SetupComm(st->hComm, 4096, 4096);
            DCB dcbSerialParams;
            memset(&dcbSerialParams, 0, sizeof(DCB));
            dcbSerialParams.DCBlength = sizeof(DCB);
            GetCommState(st->hComm, &dcbSerialParams);
            dcbSerialParams.BaudRate = (DWORD){2};
            dcbSerialParams.ByteSize = 8;
            dcbSerialParams.StopBits = ONESTOPBIT;
            dcbSerialParams.Parity = NOPARITY;
            dcbSerialParams.fDtrControl = DTR_CONTROL_ENABLE;
            dcbSerialParams.fRtsControl = RTS_CONTROL_ENABLE;
            if (!SetCommState(st->hComm, &dcbSerialParams)) {
                DWORD err = GetLastError();
                sprintf(st->errBuffer, "SetCommState:%lu", err);
                st->hasError = true;
                CloseHandle(st->hComm);
                st->hComm = INVALID_HANDLE_VALUE;
            } else {
                COMMTIMEOUTS timeouts;
                memset(&timeouts, 0, sizeof(COMMTIMEOUTS));
                timeouts.ReadIntervalTimeout = MAXDWORD;
                timeouts.ReadTotalTimeoutMultiplier = 0;
                timeouts.ReadTotalTimeoutConstant = 0;
                timeouts.WriteTotalTimeoutMultiplier = 10;
                timeouts.WriteTotalTimeoutConstant = 100;
                SetCommTimeouts(st->hComm, &timeouts);
                PurgeComm(st->hComm, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);
                st->readThread = new std::thread(_altauri_com_reader_loop, (void*){0}.mPtr);
            }
        }
        #endif
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
            st->isRunning = false;
            if (st->hComm != INVALID_HANDLE_VALUE) {
                CancelIoEx(st->hComm, NULL);
            }
            if (st->readThread && st->readThread->joinable()) {
                st->readThread->join();
            }
            delete st->readThread;
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
    #end

    // =========================================================================
    // DEVICE OPERATION (HTML5 Web Serial API)
    // =========================================================================
    #if html5
    /**
     * Open serial port using Web Serial API.
     *
     * NOTE: Web Serial API requires user gesture to request port.
     * The first open() call will show a browser dialog to select port.
     * Subsequent calls will reuse the granted permission.
     *
     * IMPORTANT: This method MUST be called from a user gesture context
     * (e.g., button click in ComPortWidget). If called from update(),
     * the browser will block the request.
     *
     * v2.1 FIX: All Promise callbacks now use arrow functions (x) => {}
     * to preserve lexical `this` binding. Previously, regular function(x) {}
     * created its own `this` (undefined in strict mode), causing
     * "Cannot read properties of undefined (reading 'onPortRequested')".
     */
    private function openDevice():Void
    {
        if (_isOpenFlag) closeDevice();
        clearBuffer();

        // Get navigator.serial
        var serial:Dynamic = untyped __js__("navigator.serial");
        if (serial == null)
        {
            setError("Web Serial API not supported in this browser");
            return;
        }

        // v2.1 FIX: Arrow functions preserve lexical `this`
        untyped __js__("{0}.requestPort().then((port) => { {1}.onPortRequested(port); }, (err) => { {1}.onPortRequestError(err); })",
        serial, this);
    }

    /**
     * Callback: port selected by user.
     */
    public function onPortRequested(port:Dynamic):Void
    {
        _serialPort = port;

        var baudRateInt:Int = 9600;
        var baudC = getInput("baudRate");
        if (baudC != null && baudC.value != null) baudRateInt = Std.int(baudC.value);

        var options:Dynamic = {
            baudRate: baudRateInt,
            dataBits: 8,
            stopBits: 1,
            parity: "none",
            bufferSize: 4096,
            flowControl: "none"
        };

        // v2.1 FIX: Arrow functions preserve lexical `this`
        untyped __js__("{0}.open({1}).then(() => { {2}.onPortOpened(); }, (err) => { {2}.onPortOpenError(err); })",
                       _serialPort, options, this);
    }

    /**
     * Callback: port opened successfully.
     */
    public function onPortOpened():Void
    {
        _isOpenFlag = true;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = true;
        startReadLoop();
        trace('ComPortAtom: Port opened');
    }

    /**
     * Callback: port open failed.
     */
    public function onPortOpenError(err:Dynamic):Void
    {
        setError('Failed to open port: $err');
    }

    /**
     * Callback: port request failed (user cancelled or API error).
     */
    public function onPortRequestError(err:Dynamic):Void
    {
        setError('Failed to request port: $err');
    }

    /**
     * Close serial port and release all streams.
     */
    private function closeDevice():Void
    {
        if (!_isOpenFlag) return;

        _isReading = false;

        // Close reader
        if (_reader != null)
        {
            untyped __js__("{0}.cancel().catch((err) => {}); {0}.releaseLock();", _reader);
            _reader = null;
        }

        // Close writer
        if (_writer != null)
        {
            untyped __js__("{0}.close().catch((err) => {}); {0}.releaseLock();", _writer);
            _writer = null;
        }

        // Close port
        if (_serialPort != null)
        {
            // v2.1 FIX: Arrow functions preserve lexical `this`
            untyped __js__("{0}.close().then(() => { {1}.onPortClosed(); }, (err) => { {1}.onPortCloseError(err); })",
            _serialPort, this);
            _serialPort = null;
        }
    }

    /**
     * Callback: port closed successfully.
     */
    public function onPortClosed():Void
    {
        _isOpenFlag = false;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = false;
        trace('ComPortAtom: Port closed');
    }

    /**
     * Callback: port close failed.
     */
    public function onPortCloseError(err:Dynamic):Void
    {
        setError('Failed to close port: $err');
    }

    /**
     * Start asynchronous read loop.
     *
     * Reads chunks from serial port and writes to ring buffer.
     * Runs continuously until _isReading is set to false.
     */
    private function startReadLoop():Void
    {
        _isReading = true;
        if (_serialPort == null) return;

        var readable:Dynamic = untyped __js__("{0}.readable", _serialPort);
        if (readable == null)
        {
            setError("Port has no readable stream");
            return;
        }

        _reader = untyped __js__("{0}.getReader()", readable);
        readChunk();
    }

    /**
     * Recursive read loop.
     */
    private function readChunk():Void
    {
        if (!_isReading || _isDisposed) return;

        // v2.1 FIX: Arrow functions preserve lexical `this`
        untyped __js__("{0}.read().then((result) => { {1}.onReadResult(result); }, (err) => { {1}.onReadError(err); })",
        _reader, this);
    }

    /**
     * Callback: read result received.
     */
    public function onReadResult(result:Dynamic):Void
    {
        if (result.done)
        {
            _isReading = false;
            return;
        }

        // Convert Uint8Array to Array<Int>
        var bytes:Array<Int> = [];
        var value:Dynamic = result.value;
        var len:Int = untyped __js__("{0}.length", value);
        for (i in 0...len)
        {
            bytes.push(untyped __js__("{0}[{1}]", value, i));
        }

        writeToBuffer(bytes);
        _hasPendingRx = true;

        // Continue reading
        readChunk();
    }

    /**
     * Callback: read error.
     */
    public function onReadError(err:Dynamic):Void
    {
        if (_isReading && !_isDisposed)
        {
            setError('Read error: $err');
        }
    }

    /**
     * Send data to serial port.
     *
     * @param data String data to send (will be encoded as UTF-8)
     */
    private function sendToDevice(data:String):Void
    {
        if (_serialPort == null || !_isOpenFlag) return;

        var writable:Dynamic = untyped __js__("{0}.writable", _serialPort);
        if (writable == null)
        {
            setError("Port has no writable stream");
            return;
        }

        _writer = untyped __js__("{0}.getWriter()", writable);
        var encoder:Dynamic = untyped __js__("new TextEncoder()");
        var encoded:Dynamic = untyped __js__("{0}.encode({1})", encoder, data);

        // v2.1 FIX: Arrow functions preserve lexical `this`
        untyped __js__("{0}.write({1}).then(() => { {2}.onWriteSuccess(); }, (err) => { {2}.onWriteError(err); })",
        _writer, encoded, this);
    }

    /**
     * Callback: write successful.
     */
    public function onWriteSuccess():Void
    {
        if (_writer != null)
        {
            untyped __js__("{0}.releaseLock()", _writer);
            _writer = null;
        }
    }

    /**
     * Callback: write error.
     */
    public function onWriteError(err:Dynamic):Void
    {
        setError('Write error: $err');
        if (_writer != null)
        {
            untyped __js__("{0}.releaseLock()", _writer);
            _writer = null;
        }
    }

    /**
     * Set DTR state.
     *
     * NOTE: Web Serial API does not directly support DTR control.
     * This is a placeholder for future implementation if needed.
     *
     * @param state true = DTR high, false = DTR low
     */
    private function setDTRState(state:Bool):Void
    {
        trace('ComPortAtom: DTR control not supported in Web Serial API');
    }

    /**
     * Set error state.
     *
     * @param msg Error message
     */
    private function setError(msg:String):Void
    {
        _pendingErrStr = msg;
        _hasPendingErr = true;
    }
    #end

    // =========================================================================
    // PULSE TIMERS (COMMON)
    // =========================================================================
    private function updatePulseTimers(dt:Float):Void
    {
        if (_rxTimer > 0)
        {
            _rxTimer -= dt;
            if (_rxTimer <= 0) { var c = getOutput("rxTick"); if (c != null) c.value = false; }
        }
        if (_txTimer > 0)
        {
            _txTimer -= dt;
            if (_txTimer <= 0) { var c = getOutput("txTick"); if (c != null) c.value = false; }
        }
        if (_errTimer > 0)
        {
            _errTimer -= dt;
            if (_errTimer <= 0) { var c = getOutput("errorTick"); if (c != null) c.value = false; }
        }
    }
}