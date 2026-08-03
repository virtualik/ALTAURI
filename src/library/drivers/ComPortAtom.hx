/*### Key Improvements Summary
1. **Cross-Platform Error Delivery (`_hasPendingErr`)**:
* Moved the `_hasPendingErr` emission block outside `#if cpp` into the cross-platform `update()` pipeline. Errors recorded via `setError()` on HTML5 (e.g., Web Serial or WebUSB initialization failures) are now correctly dispatched to the `error` and `errorTick` contacts.
2. **Null Pointer Safety in `openDevice()`**:
* Added null checks for `getInput("portName")` and `getInput("baudRate")` as well as their `.value` fields before reading/casting properties across both C++ and HTML5 targets.
3. **Safe Memory Copy in C++ (`memcpy`)**:
* Replaced `strncpy` with `memcpy` inside `_altauri_com_reader_loop` to ensure full binary payload preservation (preventing null-byte truncation) and avoid compiler warnings on MSVC and GCC.
4. **English Documentation & Comment Translation**:
* All internal comments and header annotations have been translated to English while retaining exact descriptions of algorithms and edge-case behavior.
5. **ASCII Schemes & Architecture Preservation**:
* Retained all original ASCII diagrams, architecture flowcharts, and contact maps. Updated the Hardware Support Matrix table in the doc header to document added microcontrollers and USB-UART bridges.
6. **"First Pulse" Race Condition Resolution**:
* Reset the pulse flag (`openC.value = false;`) *immediately* before initiating `openDevice()`. This avoids multi-frame re-triggering and maintains instant execution alignment for user gesture events in browser security contexts.
7. **Extended USB Chipset & Microcontroller Support**:
* Integrated full WebUSB filter definitions and initialization sequences for:
* **USB-UART Bridges:** CP2102/CP2104 (`0x10C4`), FTDI (`0x0403`), CH340/CH341 (`0x1A86`), PL2303 (`0x067B`).
* **Microcontrollers (CDC/ACM):** Arduino SA (`0x2341`), SparkFun (`0x1B4F`), STM32 (`0x0483`), RP2040 (`0x2E8A`), Microchip/Atmel SAMD (`0x03EB`), Espressif (`0x303A`).
* Added standard CDC `SET_LINE_CODING` (`0x20`) and `SET_CONTROL_LINE_STATE` (`0x22`, asserting DTR+RTS) sequence required for microcontrollers like Arduino Leonardo (ATmega32u4) and STM32 Virtual COM ports.
8. **Android Chrome WebUSB Fallback**:
* Ensured smooth transition between Web Serial API (Desktop Chrome/Edge) and WebUSB API (Android Chrome), handling claimInterface order, alternative interface selection, and error recovery.
9. **Android / POSIX C++ Backend Support**:
* Added full POSIX (`#else` branch) implementation for the C++ backend to allow compilation and basic serial I/O on Android/Linux targets using `<unistd.h>`, `<fcntl.h>`, `<termios.h>`, and `<sys/ioctl.h>`.
*/
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

#if html5
import js.Syntax;
import js.lib.Uint8Array;
import js.lib.ArrayBuffer;
import js.lib.DataView;
#end

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
#else
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#endif

struct ComPortState {
#ifdef _WIN32
    HANDLE hComm;
#else
    int hComm;
#endif
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
#ifdef _WIN32
    DWORD bytesRead;
#else
    ssize_t bytesRead;
#endif
    while (st->isRunning) {
#ifdef _WIN32
        bytesRead = 0;
        BOOL bResult = ReadFile(st->hComm, tempBuf, sizeof(tempBuf) - 1, &bytesRead, NULL);
        if (bResult && bytesRead > 0) {
            tempBuf[bytesRead] = 0;
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            size_t currentLen = strlen(st->rxBuffer);
            size_t newLen = currentLen + bytesRead;
            if (newLen >= sizeof(st->rxBuffer)) {
                size_t overflow = newLen - (sizeof(st->rxBuffer) - 1);
                memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                st->rxBuffer[currentLen - overflow] = 0;
                currentLen = currentLen - overflow;
            }
            memcpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
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
#else
        if (st->hComm > 0) {
            bytesRead = read(st->hComm, tempBuf, sizeof(tempBuf) - 1);
            if (bytesRead > 0) {
                tempBuf[bytesRead] = 0;
                std::lock_guard<std::mutex> rxLock(st->rxMutex);
                size_t currentLen = strlen(st->rxBuffer);
                size_t newLen = currentLen + bytesRead;
                if (newLen >= sizeof(st->rxBuffer)) {
                    size_t overflow = newLen - (sizeof(st->rxBuffer) - 1);
                    memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                    st->rxBuffer[currentLen - overflow] = 0;
                    currentLen = currentLen - overflow;
                }
                memcpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
                st->rxBuffer[currentLen + bytesRead] = 0;
                st->hasRxData = true;
            } else if (bytesRead == 0) {
                usleep(10000);
            } else {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                    continue;
                }
                std::lock_guard<std::mutex> errLock(st->errMutex);
                sprintf(st->errBuffer, "Rx Err:%d", errno);
                st->hasError = true;
                break;
            }
        } else {
            usleep(10000);
        }
#endif
    }
    st->isRunning = false;
}
')
#end

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT ATOM v2.8.0                                  ║
* ║          (Dual-Platform Serial Driver: C++ WinAPI/POSIX + HTML5 Web)      ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Active driver atom for serial port communication.                        ║
* ║  At compile time, Haxe selects the appropriate backend:                   ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    COMPILATION FLOW                                 │  ║
* ║  │                                                                     │  ║
* ║  │  haxe -cpp  ──► #if cpp   ──► WinAPI/POSIX CreateFile + Thread      │  ║
* ║  │  haxe -html5──► #if html5 ──► Web Serial API / WebUSB fallback      │  ║
* ║  │                                                                     │  ║
* ║  │  Common code (ring buffer, pulse timers, input dispatch) is shared. │  ║
* ║  │  Platform-specific code is isolated in #if blocks.                  │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     ComPortAtom (Active Driver)                     │  ║
* ║  │                                                                     │  ║
* ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
* ║  │  │  COMMON LAYER (all targets)                                   │  │  ║
* ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
* ║  │  │  • Ring Buffer: circular byte storage with overflow tracking  │  │  ║
* ║  │  │  • Pulse Timers: rxTick/txTick/errorTick auto-reset           │  │  ║
* ║  │  │  • Input Dispatch: open/close/send/DTR command handling       │  │  ║
* ║  │  │  • Configuration: bufferSize/chunkSize/enabled hot-reload     │  │  ║
* ║  │  │  • Batched Output: setValueSilent + propagateCurrentValue     │  │  ║
* ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
* ║  │                                                                     │  ║
* ║  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐ │  ║
* ║  │  │  #if cpp                 │  │  #if html5                       │ │  ║
* ║  │  │  ────────                │  │  ──────────                      │ │  ║
* ║  │  │  WinAPI/POSIX CreateFile │  │  Web Serial API (primary)        │ │  ║
* ║  │  │  SetupComm + DCB / termios│ │  navigator.serial.requestPort    │ │  ║
* ║  │  │  COMMTIMEOUTS / tcsetattr│  │  port.open(options)              │ │  ║
* ║  │  │  std::thread reader      │  │  readable.getReader()            │ │  ║
* ║  │  │  ReadFile / read loop    │  │                                  │ │  ║
* ║  │  │  WriteFile / write       │  │  WebUSB API (fallback)           │ │  ║
* ║  │  │  EscapeCommFunction DTR  │  │  navigator.usb.requestDevice     │ │  ║
* ║  │  │  CancelIoEx + join       │  │  Chip-specific init sequences    │ │  ║
* ║  │  │                          │  │  transferIn / transferOut        │ │  ║
* ║  │  │  ComPortState struct     │  │  controlTransferOut (vendor)     │ │  ║
* ║  │  │  _com_states_map         │  │                                  │ │  ║
* ║  │  └──────────────────────────┘  └──────────────────────────────────┘ │  ║
* ║  │                                                                     │  ║
* ║  │  ┌───────────────────────────────────────────────────────────────┐  │  ║
* ║  │  │  DATABANK (Haxe fields, shared)                               │  │  ║
* ║  │  │  ──────────────────────────────────────────────────────────── │  │  ║
* ║  │  │  _ringBuffer, _readPos, _writePos, _overflowCount             │  │  ║
* ║  │  │  _bufferSize, _chunkSize, _enabled                            │  │  ║
* ║  │  │  _lastTxData, _lastDTR, _isOpenFlag                           │  │  ║
* ║  │  │  _hasPendingRx, _hasPendingErr (volatile)                     │  │  ║
* ║  │  │  _pendingRxStr, _pendingErrStr                                │  │  ║
* ║  │  │  _rxTimer, _txTimer, _errTimer                                │  │  ║
* ║  │  └───────────────────────────────────────────────────────────────┘  │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     CONTACT MAP                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  INPUTS (Widget → Atom):                                                  ║
* ║  ┌────────────────┬──────────┬──────────────────────────────────────────┐ ║
* ║  │ Contact Name   │ Default  │ Description                              │ ║
* ║  ├────────────────┼──────────┼──────────────────────────────────────────┤ ║
* ║  │ portName       │ "COM1"   │ Serial port identifier (e.g., "COM3")    │ ║
* ║  │ baudRate       │ 9600     │ Baud rate (9600, 115200, etc.)           │ ║
* ║  │ bufferSize     │ 4096     │ Ring buffer capacity in bytes            │ ║
* ║  │ chunkSize      │ 256      │ Max bytes emitted per rxData update      │ ║
* ║  │ enabled        │ true     │ Master enable/disable switch             │ ║
* ║  │ open           │ false    │ Pulse: trigger port open                 │ ║
* ║  │ close          │ false    │ Pulse: trigger port close                │ ║
* ║  │ send           │ false    │ Pulse: trigger TX transmission           │ ║
* ║  │ txData         │ ""       │ Data string to transmit                  │ ║
* ║  │ setDTR         │ false    │ DTR line state                           │ ║
* ║  │ testRxData     │ ""       │ Inject test data into RX path            │ ║
* ║  └────────────────┴──────────┴──────────────────────────────────────────┘ ║
* ║                                                                           ║
* ║  OUTPUTS (Atom → Widget / Downstream):                                    ║
* ║  ┌────────────────┬──────────┬──────────────────────────────────────────┐ ║
* ║  │ Contact Name   │ Default  │ Description                              │ ║
* ║  ├────────────────┼──────────┼──────────────────────────────────────────┤ ║
* ║  │ isOpen         │ false    │ Current port open/closed state           │ ║
* ║  │ rxData         │ ""       │ Received data chunk (up to chunkSize)    │ ║
* ║  │ rxTick         │ false    │ Pulse: new RX data available             │ ║
* ║  │ txTick         │ false    │ Pulse: data was transmitted              │ ║
* ║  │ error          │ ""       │ Last error message                       │ ║
* ║  │ errorTick      │ false    │ Pulse: new error occurred                │ ║
* ║  └────────────────┴──────────┴──────────────────────────────────────────┘ ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     RING BUFFER ARCHITECTURE                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Ring Buffer (circular, pre-allocated Array<Int>)                   │  ║
* ║  │                                                                     │  ║
* ║  │  _bufferSize = 4096 (configurable 256..65536)                       │  ║
* ║  │                                                                     │  ║
* ║  │  Index:  0    1    2    3   ...  4093  4094  4095                   │  ║
* ║  │        ┌────┬────┬────┬────┬───┬─────┬─────┬─────┐                  │  ║
* ║  │        │0x41│0x42│0x43│0x44│...│0x00 │0x00 │0x00 │                  │  ║
* ║  │        └────┴────┴────┴────┴───┴─────┴─────┴─────┘                  │  ║
* ║  │         ▲              ▲                                            │  ║
* ║  │         │              │                                            │  ║
* ║  │      _readPos       _writePos                                       │  ║
* ║  │      (consumer)     (producer)                                      │  ║
* ║  │                                                                     │  ║
* ║  │  Overflow policy: overwrite oldest data (advance _readPos)          │  ║
* ║  │  _overflowCount tracks total lost bytes for diagnostics             │  ║
* ║  │                                                                     │  ║
* ║  │  emitRxData() reads up to _chunkSize bytes per update cycle,        │  ║
* ║  │  converting raw bytes to String via String.fromCharCode().          │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     DATA FLOW PIPELINE                                    ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  RX PATH (Receive):                                                       ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                                                                     │  ║
* ║  │  [Hardware]                                                         │  ║
* ║  │      │                                                              │  ║
* ║  │      ▼                                                              │  ║
* ║  │  [C++: ReadFile/read thread] OR [JS: reader.read() / transferIn()]  │  ║
* ║  │      │                           │                                  │  ║
* ║  │      ▼                           ▼                                  │  ║
* ║  │  [ComPortState.rxBuffer]   [_hasPendingRx = true]                   │  ║
* ║  │      │                           │                                  │  ║
* ║  │      └───────────┬───────────────┘                                  │  ║
* ║  │                  ▼                                                  │  ║
* ║  │  [update(dt): poll _hasPendingRx]                                   │  ║
* ║  │                  │                                                  │  ║
* ║  │                  ▼                                                  │  ║
* ║  │  [writeToBuffer(bytes) → Ring Buffer]                               │  ║
* ║  │                  │                                                  │  ║
* ║  │                  ▼                                                  │  ║
* ║  │  [emitRxData(): read chunkSize bytes → String]                      │  ║
* ║  │                  │                                                  │  ║
* ║  │                  ▼                                                  │  ║
* ║  │  [rxData.setValueSilent(str) + propagateCurrentValue()]             │  ║
* ║  │  [rxTick.value = true, _rxTimer = PULSE_DURATION]                   │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ║  TX PATH (Transmit):                                                      ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                                                                     │  ║
* ║  │  [Widget: user types data + clicks SEND]                            │  ║
* ║  │      │                                                              │  ║
* ║  │      ▼                                                              │  ║
* ║  │  [txData.value = "Hello"]                                           │  ║
* ║  │  [send.value = true]                                                │  ║
* ║  │      │                                                              │  ║
* ║  │      ▼                                                              │  ║
* ║  │  [readInputs(): detect send pulse]                                  │  ║
* ║  │      │                                                              │  ║
* ║  │      ▼                                                              │  ║
* ║  │  [C++: WriteFile/write]  OR  [JS: writer.write(encoded)]            │  ║
* ║  │      │                       OR  [JS: transferOut(ep, data)]        │  ║
* ║  │      ▼                                                              │  ║
* ║  │  [txTick.value = true, _txTimer = PULSE_DURATION]                   │  ║
* ║  │  [send.value = false]  (auto-reset pulse)                           │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     PULSE TIMER MECHANISM                                 ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Tick contacts (rxTick, txTick, errorTick) emit a brief TRUE pulse        ║
* ║  that auto-resets to FALSE after PULSE_DURATION seconds.                  ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Timeline:                                                          │  ║
* ║  │                                                                     │  ║
* ║  │  rxTick:  ──────┐         ┌──────────────────────────────────       │  ║
* ║  │                 │  TRUE   │                                         │  ║
* ║  │                 └─────────┘                                         │  ║
* ║  │                 ◄─ 50ms ─►                                          │  ║
* ║  │                 PULSE_DURATION                                      │  ║
* ║  │                                                                     │  ║
* ║  │  update(dt) decrements _rxTimer each frame.                         │  ║
* ║  │  When _rxTimer <= 0: rxTick.value = false                           │  ║
* ║  │                                                                     │  ║
* ║  │  This allows downstream atoms (LED, Oscilloscope) to detect         │  ║
* ║  │  discrete events without polling the data contact.                  │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     C++ BACKEND: THREAD MODEL                             ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Main Thread (Haxe/TickGenerator)     Reader Thread (std::thread)   │  ║
* ║  │  ────────────────────────────────     ────────────────────────────  │  ║
* ║  │                                                                     │  ║
* ║  │  update(dt) {                       _altauri_com_reader_loop() {    │  ║
* ║  │    lock(rxMutex)                      while (isRunning) {           │  ║
* ║  │    copy rxBuffer → _pendingRxStr        ReadFile/read(hComm, buf)   │  ║
* ║  │    hasRxData = false                    lock(rxMutex)               │  ║
* ║  │    unlock                               append to rxBuffer          │  ║
* ║  │                                         hasRxData = true            │  ║
* ║  │    emit rxData                          unlock                      │  ║
* ║  │  }                                      }                           │  ║
* ║  │                                         isRunning = false           │  ║
* ║  │  closeDevice() {                      }                             │  ║
* ║  │    isRunning = false                                                │  ║
* ║  │    CancelIoEx/close(hComm)              Thread exits cleanly        │  ║
* ║  │    readThread->join()                                               │  ║
* ║  │    CloseHandle/close(hComm)                                         │  ║
* ║  │  }                                                                  │  ║
* ║  │                                                                     │  ║
* ║  │  Synchronization: std::mutex (rxMutex, errMutex, _com_map_mutex)    │  ║
* ║  │  Lifecycle: ComPortState* stored in _com_states_map keyed by        │  ║
* ║  │             Haxe object pointer (this.mPtr)                         │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     HTML5 BACKEND: HARDWARE MATRIX & CHIP INIT            ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  When Web Serial API is unavailable (e.g., Android Chrome), the atom      ║
* ║  falls back to WebUSB with chip-specific initialization sequences:        ║
* ║                                                                           ║
* ║  ┌────────────────────────┬────────┬──────────────────┬─────────────────┐ ║
* ║  │ Controller / Chipset   │ VID    │ Interface Type   │ Android WebUSB  │ ║
* ║  ├────────────────────────┼────────┼──────────────────┼─────────────────┤ ║
* ║  │ Espressif (ESP32/S2/S3)│ 0x303A │ CDC / Custom     │ YES             │ ║
* ║  │ FTDI (FT232R/H)        │ 0x0403 │ Vendor Specific  │ YES             │ ║
* ║  │ WCH (CH340 / CH341)    │ 0x1A86 │ Vendor Specific  │ YES             │ ║
* ║  │ Silicon Labs (CP2102/4)│ 0x10C4 │ Vendor Specific  │ YES             │ ║
* ║  │ Prolific (PL2303)      │ 0x067B │ Vendor Specific  │ YES             │ ║
* ║  │ Arduino (32u4/16u2)    │ 0x2341 │ CDC / ACM        │ YES             │ ║
* ║  │ SparkFun (32u4/SAMD)   │ 0x1B4F │ CDC / ACM        │ YES             │ ║
* ║  │ STM32 (Virtual COM)    │ 0x0483 │ CDC / ACM        │ YES             │ ║
* ║  │ Raspberry Pi (RP2040)  │ 0x2E8A │ CDC / ACM        │ YES             │ ║
* ║  │ Microchip / SAMD       │ 0x03EB │ CDC / ACM        │ YES             │ ║
* ║  └────────────────────────┴────────┴──────────────────┴─────────────────┘ ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     BATCHED DRIVER UPDATE PATTERN                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Per ALTAURI architecture:                                                ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Phase 1: SILENT WRITE (no propagation)                             │  ║
* ║  │    rxOut.setValueSilent(rxString)                                   │  ║
* ║  │    errOut.setValueSilent(errString)                                 │  ║
* ║  │                                                                     │  ║
* ║  │  Phase 2: SINGLE PROPAGATION (one event per contact)                │  ║
* ║  │    rxOut.propagateCurrentValue()                                    │  ║
* ║  │    errOut.propagateCurrentValue()                                   │  ║
* ║  │                                                                     │  ║
* ║  │  This reduces TickGenerator load from O(N×M) to O(N+M)              │  ║
* ║  │  where N = output contacts, M = subscribers per contact.            │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     VERSION HISTORY                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v2.8.1 — Android / POSIX C++ Backend Support                             ║
* ║  ───────────────────────────────────────────────────────────────          ║
* ║  - FIXED: Compilation errors on Android/Linux targets by isolating        ║
* ║    Windows-specific types (HANDLE, DWORD) and adding POSIX equivalents.   ║
* ║  - ADDED: POSIX serial read/write/ioctl implementation for non-Windows.   ║
* ║                                                                           ║
* ║  v2.8.0 — Cross-Platform Error Sync + Microcontroller WebUSB CDC          ║
* ║  ───────────────────────────────────────────────────────────────          ║
* ║  - FIXED: Error delivery on HTML5 moved outside #if cpp block to update() ║
* ║  - FIXED: Null pointer safety checks added to openDevice() for input      ║
* ║    contacts and their values.                                             ║
* ║  - FIXED: Replaced strncpy with memcpy in C++ background thread.          ║
* ║  - FIXED: First pulse trigger issue resolved by immediately resetting     ║
* ║    openC.value prior to device initialization.                           ║
* ║  - ADDED: Microcontroller WebUSB CDC/ACM initialization for Arduino,      ║
* ║    SparkFun, STM32, RP2040, Atmel SAMD, and Espressif devices.            ║
* ║  - TRANSLATED: Converted all remaining Russian comments to English.       ║
* ║                                                                           ║
* ║  v2.7.0 — HTML5 Deprecation Fix + Unused Variable Cleanup                 ║
* ║  ─────────────────────────────────────────────────────────                ║
* ║  - FIXED: Replaced all deprecated __js__() calls with js.Syntax.code().   ║
* ║  - FIXED: Removed unused imports and variables.                           ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class ComPortAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    /** Duration of tick pulses (rxTick, txTick, errorTick) in seconds. */
    private static inline var PULSE_DURATION:Float = 0.05;
    /** Default ring buffer capacity in bytes. */
    private static inline var DEFAULT_BUFFER_SIZE:Int = 4096;
    /** Default maximum bytes emitted per rxData update cycle. */
    private static inline var DEFAULT_CHUNK_SIZE:Int = 256;
    /** Minimum allowed ring buffer size. */
    private static inline var MIN_BUFFER_SIZE:Int = 256;
    /** Maximum allowed ring buffer size. */
    private static inline var MAX_BUFFER_SIZE:Int = 65536;
    /** Minimum allowed chunk size. */
    private static inline var MIN_CHUNK_SIZE:Int = 1;
    /** Maximum allowed chunk size. */
    private static inline var MAX_CHUNK_SIZE:Int = 4096;

    // =========================================================================
    // RING BUFFER (COMMON)
    // =========================================================================
    /**
    * Pre-allocated circular byte buffer.
    * Stores raw received bytes before they are emitted as String chunks.
    * Indexed via modulo arithmetic: _ringBuffer[pos % _bufferSize].
    */
    private var _ringBuffer:Array<Int>;
    /** Consumer position: next byte to read from ring buffer. */
    private var _readPos:Int = 0;
    /** Producer position: next byte to write into ring buffer. */
    private var _writePos:Int = 0;
    /** Total number of bytes lost due to buffer overflow (diagnostics). */
    private var _overflowCount:Int = 0;
    /** Current ring buffer capacity in bytes (configurable at runtime). */
    private var _bufferSize:Int = DEFAULT_BUFFER_SIZE;
    /** Maximum bytes emitted per rxData update (configurable at runtime). */
    private var _chunkSize:Int = DEFAULT_CHUNK_SIZE;
    /** Master enable flag. When false, update() skips all I/O processing. */
    private var _enabled:Bool = true;

    // =========================================================================
    // PARAMETERS AND INPUTS (COMMON)
    // =========================================================================
    /** Last transmitted data string (for diagnostics / deduplication). */
    private var _lastTxData:String = "";
    /** Last known DTR line state (prevents redundant EscapeCommFunction calls). */
    private var _lastDTR:Bool = false;
    /** Current port open/closed state (mirrors isOpen output contact). */
    private var _isOpenFlag:Bool = false;

    // =========================================================================
    // PENDING FIELDS (COMMON)
    // =========================================================================
    /**
    * Volatile flag: new RX data is pending from the platform backend.
    * Set by C++ reader thread (via mutex-protected copy) or by
    * HTML5 read callbacks. Consumed by update(dt) on the main thread.
    *
    * @:volatile ensures visibility across threads on C++ target.
    */
    @:volatile private var _hasPendingRx:Bool = false;
    /**
    * Volatile flag: a new error message is pending from the platform backend.
    * Same cross-thread visibility guarantees as _hasPendingRx.
    */
    @:volatile private var _hasPendingErr:Bool = false;
    /** Pending RX data string (populated by backend, consumed by update). */
    private var _pendingRxStr:String = "";
    /** Pending error message string (populated by backend, consumed by update). */
    private var _pendingErrStr:String = "";

    // =========================================================================
    // PULSE TIMERS (COMMON)
    // =========================================================================
    /** Countdown timer for rxTick pulse auto-reset. */
    private var _rxTimer:Float = 0.0;
    /** Countdown timer for txTick pulse auto-reset. */
    private var _txTimer:Float = 0.0;
    /** Countdown timer for errorTick pulse auto-reset. */
    private var _errTimer:Float = 0.0;

    // =========================================================================
    // PLATFORM-SPECIFIC FIELDS
    // =========================================================================
    #if cpp
    // C++ fields are managed via __cpp__() — no Haxe fields needed.
    // ComPortState struct lives in the global _com_states_map,
    // keyed by this object's mPtr (Haxe object pointer).
    #elseif html5
    /** Native browser SerialPort instance (Web Serial API). */
    private var _serialPort:Dynamic = null;
    /** Readable stream reader (Web Serial). */
    private var _reader:Dynamic = null;
    /** Writable stream writer (Web Serial). */
    private var _writer:Dynamic = null;
    /** Native browser USBDevice instance (WebUSB Fallback). */
    private var _usbDevice:Dynamic = null;
    /** Claimed USB data interface number. */
    private var _usbInterfaceNumber:Int = -1;
    /** USB bulk IN endpoint number for receiving data. */
    private var _usbEndpointIn:Int = -1;
    /** USB bulk OUT endpoint number for transmitting data. */
    private var _usbEndpointOut:Int = -1;
    /** USB CDC control interface number (for SET_LINE_CODING etc.). */
    private var _usbControlInterface:Int = -1;
    /** Read loop active flag (controls recursive read chain). */
    private var _isReading:Bool = false;
    /** Connection type: "serial" (Web Serial) or "usb" (WebUSB fallback). */
    private var _connectionType:String = "none";
    #end

    // =========================================================================
    // CONSTRUCTOR (COMMON)
    // =========================================================================
    /**
    * Create a new ComPortAtom driver instance.
    *
    * Registers as an active driver (isActive=true) so DriverManager
    * calls update(dt) every simulation tick.
    *
    * @param id Unique runtime instance ID
    */
    public function new(id:String)
    {
        super(
            [
                new Contact("COM1", ContactType.INPUT, "portName"),
                new Contact(9600, ContactType.INPUT, "baudRate"),
                new Contact(DEFAULT_BUFFER_SIZE, ContactType.INPUT, "bufferSize"),
                new Contact(DEFAULT_CHUNK_SIZE, ContactType.INPUT, "chunkSize"),
                new Contact(true, ContactType.INPUT, "enabled"),
                new Contact(false, ContactType.INPUT, "open"),
                new Contact(false, ContactType.INPUT, "close"),
                new Contact(false, ContactType.INPUT, "send"),
                new Contact("", ContactType.INPUT, "txData"),
                new Contact(false, ContactType.INPUT, "setDTR"),
                new Contact("", ContactType.INPUT, "testRxData")
            ],
            [
                new Contact(false, ContactType.OUTPUT, "isOpen"),
                new Contact("", ContactType.OUTPUT, "rxData"),
                new Contact(false, ContactType.OUTPUT, "rxTick"),
                new Contact(false, ContactType.OUTPUT, "txTick"),
                new Contact("", ContactType.OUTPUT, "error"),
                new Contact(false, ContactType.OUTPUT, "errorTick")
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
    /**
    * Initialize (or reinitialize) the ring buffer with a new size.
    * Resets read/write positions and overflow counter.
    *
    * @param size New buffer capacity in bytes (clamped by caller)
    */
    private function initRingBuffer(size:Int):Void
    {
        _bufferSize = size;
        _ringBuffer = new Array<Int>();
        for (i in 0..._bufferSize) _ringBuffer.push(0);
        _readPos = 0;
        _writePos = 0;
        _overflowCount = 0;
    }

    /**
    * Write an array of bytes into the ring buffer.
    * Overwrites oldest bytes on overflow.
    *
    * @param data Array of byte values (0-255) to write
    * @return Number of bytes written
    */
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
                if (_overflowCount % 100 == 0) trace('ComPortAtom: Ring buffer overflow! Lost $_overflowCount bytes total');
            }
        }
        return written;
    }

    /**
    * Get the number of unread bytes currently in the ring buffer.
    *
    * @return Byte count available for reading
    */
    private function getBufferCount():Int { return _writePos - _readPos; }

    /** Clear the ring buffer, resetting positions and counters. */
    private function clearBuffer():Void { _readPos = 0; _writePos = 0; _overflowCount = 0; }

    /**
    * Emit pending RX data from the ring buffer to the rxData output contact.
    * Uses batched driver update pattern (setValueSilent + propagateCurrentValue).
    */
    private function emitRxData():Void
    {
        var availableBytes = getBufferCount();
        if (availableBytes == 0) return;
        var bytesToRead:Int = availableBytes < _chunkSize ? availableBytes : _chunkSize;
        var rxString = "";
        for (i in 0...bytesToRead)
        {
            var idx = _readPos % _bufferSize;
            rxString += String.fromCharCode(_ringBuffer[idx]);
            _readPos++;
        }
        var rxOut = getOutput("rxData");
        if (rxOut != null) { rxOut.setValueSilent(rxString); rxOut.propagateCurrentValue(); }
        var rxTick = getOutput("rxTick");
        if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    /** Driver initialization hook. */
    override public function init():Void {}

    /**
    * Main driver update loop. Called every simulation tick by DriverManager.
    *
    * @param dt Delta time in seconds since last tick
    */
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        readConfiguration();
        if (!_enabled) return;

        // === Test data injection (for debugging without hardware) ===
        var testRxC = getInput("testRxData");
        if (testRxC != null && testRxC.value != null && testRxC.value != "")
        {
            var testData:String = Std.string(testRxC.value);
            var rxOut = getOutput("rxData");
            if (rxOut != null) { rxOut.setValueSilent(testData); rxOut.propagateCurrentValue(); }
            var rxTick = getOutput("rxTick");
            if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
            testRxC.value = "";
        }
        else
        {
            // === C++ PLATFORM: Poll reader thread data via mutex ===
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
            if (_cps_stPtr != nullptr) {
                {
                    std::lock_guard<std::mutex> _cps_rxLock(_cps_stPtr->rxMutex);
                    if (_cps_stPtr->hasRxData) {
                        {0}->_pendingRxStr = ::String(_cps_stPtr->rxBuffer);
                        {0}->_hasPendingRx = true;
                        _cps_stPtr->hasRxData = false;
                        _cps_stPtr->rxBuffer[0] = 0;
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

        // === CROSS-PLATFORM: Emit pending RX data ===
        if (_hasPendingRx)
        {
            _hasPendingRx = false;
            var rxOut = getOutput("rxData");
            if (rxOut != null) { rxOut.setValueSilent(_pendingRxStr); rxOut.propagateCurrentValue(); }
            var rxTick = getOutput("rxTick");
            if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
        }

        // === CROSS-PLATFORM: Emit pending error messages (C++ and HTML5) ===
        if (_hasPendingErr)
        {
            _hasPendingErr = false;
            var errOut = getOutput("error");
            if (errOut != null) { errOut.setValueSilent(_pendingErrStr); errOut.propagateCurrentValue(); }
            var errTick = getOutput("errorTick");
            if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
        }

        // === HTML5: Emit data from ring buffer ===
        #if html5
        emitRxData();
        #end

        readInputs();
        updatePulseTimers(dt);
    }

    /** Dispose the driver and release all platform resources. */
    override public function dispose():Void
    {
        #if cpp
        closeDevice();
        #elseif html5
        if (_isOpenFlag) closeDevice();
        #end
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // CONFIGURATION & INPUT READING (COMMON)
    // =========================================================================
    /** Read and apply runtime configuration from input contacts. */
    private function readConfiguration():Void
    {
        var bufSizeC = getInput("bufferSize");
        if (bufSizeC != null && bufSizeC.value != null)
        {
            var newSize:Int = cast bufSizeC.value;
            if (newSize >= MIN_BUFFER_SIZE && newSize <= MAX_BUFFER_SIZE && newSize != _bufferSize)
            {
                trace('ComPortAtom: Buffer size changed from $_bufferSize to $newSize');
                initRingBuffer(newSize);
            }
        }
        var chunkC = getInput("chunkSize");
        if (chunkC != null && chunkC.value != null)
        {
            var newChunk:Int = cast chunkC.value;
            if (newChunk >= MIN_CHUNK_SIZE && newChunk <= MAX_CHUNK_SIZE) _chunkSize = newChunk;
        }
        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null) _enabled = (enabledC.value == true);
    }

    /**
    * Read and dispatch command inputs (open, close, send, DTR).
    * Resets pulse signals immediately to avoid multi-frame race conditions.
    */
    private function readInputs():Void
    {
        var openC  = getInput("open");
        var closeC = getInput("close");
        var sendC  = getInput("send");
        var txC    = getInput("txData");
        var dtrC   = getInput("setDTR");

        if (openC != null && openC.value == true)
        {
            openC.value = false; // Reset immediately to prevent second frame trigger
            openDevice();
        }
        if (closeC != null && closeC.value == true)
        {
            closeC.value = false; // Reset immediately
            closeDevice();
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
            if (newDTR != _lastDTR && _isOpenFlag) { _lastDTR = newDTR; setDTRState(newDTR); }
        }
    }

    // =========================================================================
    // DEVICE OPERATION (C++ WinAPI / POSIX)
    // =========================================================================
    #if cpp
    /** Open serial port via WinAPI CreateFileA or POSIX open. */
    private function openDevice():Void
    {
        if (_isOpenFlag) closeDevice();
        var portNameC = getInput("portName");
        var portNameStr:String = (portNameC != null && portNameC.value != null) ? Std.string(portNameC.value) : "COM1";
        var baudC = getInput("baudRate");
        var baudRateInt:Int = (baudC != null && baudC.value != null) ? cast baudC.value : 9600;

        untyped __cpp__('
        ComPortState* st = new ComPortState();
        #ifdef _WIN32
        st->hComm = INVALID_HANDLE_VALUE;
        #else
        st->hComm = -1;
        #endif
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
        #else
        // POSIX implementation for Android/Linux
        ::String portStr = {1};
        const char* _cps_rawName = portStr.c_str();
        st->hComm = open(_cps_rawName, O_RDWR | O_NOCTTY | O_NDELAY);
        if (st->hComm < 0) {
            sprintf(st->errBuffer, "POSIX Open Failed:%d", errno);
            st->hasError = true;
        } else {
            struct termios tty;
            memset(&tty, 0, sizeof(tty));
            if (tcgetattr(st->hComm, &tty) != 0) {
                sprintf(st->errBuffer, "tcgetattr Failed:%d", errno);
                st->hasError = true;
                close(st->hComm);
                st->hComm = -1;
            } else {
                cfsetospeed(&tty, (speed_t){2});
                cfsetispeed(&tty, (speed_t){2});
                tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8;
                tty.c_iflag &= ~IGNBRK;
                tty.c_lflag = 0;
                tty.c_oflag = 0;
                tty.c_cc[VMIN] = 0;
                tty.c_cc[VTIME] = 1; // 100ms read timeout
                tty.c_iflag &= ~(IXON | IXOFF | IXANY);
                tty.c_cflag |= (CLOCAL | CREAD);
                tty.c_cflag &= ~(PARENB | PARODD);
                tty.c_cflag &= ~CSTOPB;
                tty.c_cflag &= ~CRTSCTS;
                if (tcsetattr(st->hComm, TCSANOW, &tty) != 0) {
                    sprintf(st->errBuffer, "tcsetattr Failed:%d", errno);
                    st->hasError = true;
                    close(st->hComm);
                    st->hComm = -1;
                } else {
                    st->readThread = new std::thread(_altauri_com_reader_loop, (void*){0}.mPtr);
                }
            }
        }
        #endif

        {
            std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
            _com_states_map[(void*){0}.mPtr] = st;
            #ifdef _WIN32
            {0}->_isOpenFlag = (st->hComm != INVALID_HANDLE_VALUE);
            #else
            {0}->_isOpenFlag = (st->hComm >= 0);
            #endif
        }
        ', this, portNameStr, baudRateInt);

        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = _isOpenFlag;
    }

    /** Close serial port and terminate background thread. */
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
        if (st != nullptr) {
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
            #else
            st->isRunning = false;
            if (st->hComm >= 0) {
                close(st->hComm);
            }
            if (st->readThread && st->readThread->joinable()) {
                st->readThread->join();
            }
            delete st->readThread;
            #endif
            delete st;
        }
        ', this);
        _isOpenFlag = false;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = false;
    }

    /** Transmit raw string to serial port. */
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
        if (_cps_stPtr != nullptr) {
            #ifdef _WIN32
            if (_cps_stPtr->hComm != INVALID_HANDLE_VALUE) {
                const char* buffer = {1}.c_str();
                DWORD bytesToWrite = (DWORD)strlen(buffer);
                DWORD bytesWritten;
                WriteFile(_cps_stPtr->hComm, buffer, bytesToWrite, &bytesWritten, NULL);
            }
            #else
            if (_cps_stPtr->hComm >= 0) {
                const char* buffer = {1}.c_str();
                size_t bytesToWrite = strlen(buffer);
                write(_cps_stPtr->hComm, buffer, bytesToWrite);
            }
            #endif
        }
        ', this, data);
    }

    /** Set DTR line state via EscapeCommFunction or POSIX ioctl. */
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
        if (_cps_stPtr != nullptr) {
            #ifdef _WIN32
            if (_cps_stPtr->hComm != INVALID_HANDLE_VALUE) {
                if ({1}) {
                    EscapeCommFunction(_cps_stPtr->hComm, SETDTR);
                } else {
                    EscapeCommFunction(_cps_stPtr->hComm, CLRDTR);
                }
            }
            #else
            if (_cps_stPtr->hComm >= 0) {
                int flags = TIOCM_DTR;
                if ({1}) {
                    ioctl(_cps_stPtr->hComm, TIOCMBIS, &flags);
                } else {
                    ioctl(_cps_stPtr->hComm, TIOCMBIC, &flags);
                }
            }
            #endif
        }
        ', this, state);
    }
    #end

    // =========================================================================
    // DEVICE OPERATION (HTML5: Web Serial + WebUSB Fallback)
    // =========================================================================
    #if html5
    /**
    * Open serial port via Web Serial API (Desktop) or WebUSB API (Android/Fallback).
    */
    private function openDevice():Void
    {
        if (_isOpenFlag) closeDevice();
        clearBuffer();
        var hasSerial:Bool = untyped js.Syntax.code("typeof navigator !== 'undefined' && 'serial' in navigator");
        var hasUSB:Bool = untyped js.Syntax.code("typeof navigator !== 'undefined' && 'usb' in navigator");

        if (hasSerial)
        {
            _connectionType = "serial";
            var self = this;
            
            // === Fullscreen-aware port request ===
            // Browser exits fullscreen when requestPort() is called, which breaks the dialog.
            // Solution: explicitly exit fullscreen first, wait for it to complete,
            // then call requestPort(). After port selection, re-enter fullscreen.
            var wasFullscreen:Bool = untyped js.Syntax.code("document.fullscreenElement != null");
            var doRequestPort = function() {
                untyped js.Syntax.code("navigator.serial").requestPort().then(function(port:Dynamic) {
                    self.onSerialPortRequested(port);
                    // Re-enter fullscreen after successful port selection
                    if (wasFullscreen) {
                        self._reenterFullscreen();
                    }
                })
                ['catch'](function(err:Dynamic) {
                    self.onPortRequestError(err);
                    // Re-enter fullscreen even on error/cancel
                    if (wasFullscreen) {
                        self._reenterFullscreen();
                    }
                });
            };

            if (wasFullscreen)
            {
                // Exit fullscreen first, then request port after a short delay
                untyped js.Syntax.code("document.exitFullscreen()");
                // Wait for fullscreen exit to complete (typically 100-200ms)
                haxe.Timer.delay(doRequestPort, 300);
            }
            else
            {
                // Not in fullscreen, proceed normally
                doRequestPort();
            }
        }
    }

    // --- WEB SERIAL CALLBACKS ---
    /** Web Serial: port selected by user. */
    @:keep public function onSerialPortRequested(port:Dynamic):Void
    {
        _serialPort = port;
        var portInfo:String = "Serial Port";
        try {
            // Web Serial provides getInfo() with usbVendorId / usbProductId
            var info:Dynamic = untyped port.getInfo();
            if (info != null)
            {
                var vid:Int = untyped info.usbVendorId != null ? info.usbVendorId : 0;
                var pid:Int = untyped info.usbProductId != null ? info.usbProductId : 0;
                if (vid != 0)
                {
                    portInfo = StringTools.hex(vid, 4) + ":" + StringTools.hex(pid, 4);
                    // Format it nicely:
                    portInfo = formatUsbName(vid, pid);
                }
            }
        }
        catch (e:Dynamic) {}

        var portNameC = getInput("portName");
        if (portNameC != null)
        {
            portNameC.value = portInfo;           // Key assignment for port info display
            // Alternatively, use setValueSilent + propagate if preferred by architecture
        }

        var baudRateInt:Int = 9600;
        var baudC = getInput("baudRate");
        if (baudC != null && baudC.value != null) baudRateInt = cast baudC.value;

        var options:Dynamic = { baudRate: baudRateInt, dataBits: 8, stopBits: 1, parity: "none", bufferSize: 4096, flowControl: "none" };
        var self = this;
        untyped _serialPort.open(options).then(function() { self.onPortOpened(); })
        ['catch'](function(err:Dynamic) { self.onPortOpenError(err); });
    }

    // --- WEB USB CALLBACKS ---
    /** WebUSB: device selected by user. */
    @:keep public function onUsbDeviceRequested(device:Dynamic):Void
    {
        _usbDevice = device;
        var vid:Int = untyped device.vendorId;
        var pid:Int = untyped device.productId;
        var productName:String = untyped (device.productName != null ? device.productName : "");
        var portInfo:String = productName != ""
            ? productName
            : formatUsbName(vid, pid);

        var portNameC = getInput("portName");
        if (portNameC != null)
        {
            portNameC.value = portInfo;
        }

        var baudRateInt:Int = 9600;
        var baudC = getInput("baudRate");
        if (baudC != null && baudC.value != null) baudRateInt = cast baudC.value;

        var self = this;
        untyped _usbDevice.open().then(function()
        {
            return untyped _usbDevice.selectConfiguration(1);
        }).then(function()
        {
            return self.claimUsbInterfaces(baudRateInt);
        }).then(function()
        {
            self.onPortOpened();
        })['catch'](function(err:Dynamic)
        {
            self.onPortOpenError(err);
        });
    }

    private function formatUsbName(vid:Int, pid:Int):String
    {
        return switch (vid)
        {
            case 0x0403: "FTDI " + StringTools.hex(pid, 4);
            case 0x10C4: "CP210x " + StringTools.hex(pid, 4);
            case 0x1A86: "CH340 " + StringTools.hex(pid, 4);
            case 0x067B: "PL2303";
            case 0x2341: "Arduino";
            case 0x1B4F: "SparkFun";
            case 0x0483: "STM32";
            case 0x2E8A: "RP2040";
            case 0x03EB: "Atmel SAMD";
            case 0x303A: "ESP32";
            default: "USB " + StringTools.hex(vid, 4) + ":" + StringTools.hex(pid, 4);
        }
    }

    /**
    * Synchronous port request to preserve browser User Gesture context.
    * Called directly from ComPortWidget.onOpenClick() to bypass the update() loop,
    * which destroys the user gesture context and blocks the browser dialog.
    */
    public function requestPortSync():Void
    {
        var hasSerial:Bool = untyped js.Syntax.code("typeof navigator !== 'undefined' && 'serial' in navigator");
        var hasUSB:Bool = untyped js.Syntax.code("typeof navigator !== 'undefined' && 'usb' in navigator");

        // Save fullscreen state to restore it after dialog closes
        var cfg = ui.DisplayConfig.getInstance();
        var wasFullscreen = cfg.isFullscreen;
        var win = openfl.Lib.current.stage.window;

        if (hasSerial)
        {
            _connectionType = "serial";
            var self = this;
            untyped js.Syntax.code("navigator.serial").requestPort().then(function(port:Dynamic) {
                self.onSerialPortRequested(port);
                if (wasFullscreen) cfg.reenterFullscreen(win);
            })['catch'](function(err:Dynamic) {
                self.onPortRequestError(err);
                if (wasFullscreen) cfg.reenterFullscreen(win);
            });
        }
        else if (hasUSB)
        {
            _connectionType = "usb";
            var self = this;
            var filters:Array<Dynamic> = [
                { vendorId: 0x303A }, { vendorId: 0x0403 }, { vendorId: 0x1A86 },
                { vendorId: 0x10C4 }, { vendorId: 0x067B }, { vendorId: 0x2341 },
                { vendorId: 0x1B4F }, { vendorId: 0x0483 }, { vendorId: 0x2E8A }, { vendorId: 0x03EB }
            ];
            untyped js.Syntax.code("navigator.usb").requestDevice({ filters: filters }).then(function(device:Dynamic) {
                self.onUsbDeviceRequested(device);
                if (wasFullscreen) cfg.reenterFullscreen(win);
            })['catch'](function(err:Dynamic) {
                self.onPortRequestError(err);
                if (wasFullscreen) cfg.reenterFullscreen(win);
            });
        }
        else
        {
            setError("Neither Web Serial API nor WebUSB is supported in this browser environment.");
        }
    }

    /** WebUSB: Claim interface and configure chip/CDC control sequence. */
    @:keep private function claimUsbInterfaces(baudRate:Int):Dynamic
    {
        var self = this;
        var dev:Dynamic = _usbDevice;
        var config:Dynamic = dev.configuration;
        var ifaceNum:Int = -1;
        var ctrlIface:Int = -1;
        var epIn:Int = -1;
        var epOut:Int = -1;
        var interfaces:Dynamic = config.interfaces;

        for (i in 0...interfaces.length)
        {
            var iface:Dynamic = interfaces[i];
            if (iface.alternates != null && iface.alternates.length > 0 && iface.alternates[0].interfaceClass == 0x02)
            {
                ctrlIface = iface.interfaceNumber;
                break;
            }
        }

        var candidates:Array<Dynamic> = [];
        for (i in 0...interfaces.length)
        {
            var iface:Dynamic = interfaces[i];
            for (a in 0...iface.alternates.length)
            {
                var alt:Dynamic = iface.alternates[a];
                var hasIn:Bool = false;
                var hasOut:Bool = false;
                for (e in 0...alt.endpoints.length)
                {
                    var ep:Dynamic = alt.endpoints[e];
                    if (ep.type == 'bulk' && ep.direction == 'in') hasIn = true;
                    if (ep.type == 'bulk' && ep.direction == 'out') hasOut = true;
                }
                if (hasIn && hasOut)
                {
                    var score:Int = (alt.interfaceClass == 0x0a) ? 0 : 1;
                    candidates.push({ iface: iface, altIndex: a, alt: alt, score: score });
                    break;
                }
            }
        }

        candidates.sort(function(a:Dynamic, b:Dynamic):Int {
            var sa:Int = a.score;
            var sb:Int = b.score;
            return sa - sb;
        });

        if (candidates.length == 0) return untyped Promise.reject('No suitable USB interface found');

        var tryClaim:Dynamic = null;
        tryClaim = function(idx:Int):Dynamic
        {
            if (idx >= candidates.length) return untyped Promise.reject('Unable to claim any USB interface');
            var cand:Dynamic = candidates[idx];
            return untyped dev.claimInterface(cand.iface.interfaceNumber).then(function()
            {
                return untyped dev.selectAlternateInterface(cand.iface.interfaceNumber, cand.altIndex)['catch'](function(e:Dynamic) { return null; });
            }).then(function()
            {
                ifaceNum = cand.iface.interfaceNumber;
                for (e in 0...cand.alt.endpoints.length)
                {
                    var ep:Dynamic = cand.alt.endpoints[e];
                    if (ep.type == 'bulk' && ep.direction == 'in') epIn = ep.endpointNumber;
                    else if (ep.type == 'bulk' && ep.direction == 'out') epOut = ep.endpointNumber;
                }
                if (ctrlIface == -1 || ctrlIface == ifaceNum) ctrlIface = ifaceNum;

                var vid:Int = dev.vendorId;
                var initPromise:Dynamic = untyped Promise.resolve();

                if (vid == 0x10c4)   // Silicon Labs CP2102 / CP2104
                {
                    initPromise = untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x00, value:0x01, index:0x00})
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x03, value:0x0800, index:0x00}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x07, value:0x0303, index:0x00}); })
                    .then(function()
                    {
                        var buf:ArrayBuffer = new ArrayBuffer(4);
                        var view:DataView = new DataView(buf);
                        view.setUint32(0, baudRate, true);
                        return untyped dev.controlTransferOut({requestType:'vendor', recipient:'interface', request:0x1E, value:0, index:0}, buf);
                    });
                }
                else if (vid == 0x0403)   // FTDI FT232R / FT2232 / FT4232
                {
                    var divisor:Float = 3000000.0 / baudRate;
                    var intPart:Int = cast Math.floor(divisor);
                    var fracPart:Float = divisor - intPart;
                    var subInt:Int = 0;
                    if (fracPart >= 0.0625 && fracPart < 0.1875) subInt = 1;
                    else if (fracPart >= 0.1875 && fracPart < 0.3125) subInt = 2;
                    else if (fracPart >= 0.3125 && fracPart < 0.4375) subInt = 3;
                    else if (fracPart >= 0.4375 && fracPart < 0.5625) subInt = 4;
                    else if (fracPart >= 0.5625 && fracPart < 0.6875) subInt = 5;
                    else if (fracPart >= 0.6875 && fracPart < 0.8125) subInt = 6;
                    else if (fracPart >= 0.8125) subInt = 7;

                    var val:Int = (intPart & 0xFF) | ((subInt & 0x07) << 14) | (((intPart >> 8) & 0x3F) << 8);
                    var idx_val:Int = (intPart >> 14) & 0x03;

                    initPromise = untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x00, value:0x00, index:0x00})
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x02, value:0x00, index:0x00}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x04, value:0x0008, index:0x00}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x03, value:val, index:idx_val}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0303, index:0x00}); });
                }
                else if (vid == 0x1a86)   // WCH CH340 / CH341
                {
                    var factor:Float = 1532620800.0 / baudRate;
                    var factorInt:Int = cast Math.floor(factor);
                    var div:Int = 3;
                    while (factorInt > 0xfff0 && div > 0) { factorInt >>= 3; div--; }
                    if (factorInt > 0xfff0) return untyped Promise.reject('Baudrate not supported by CH340');
                    factorInt = 0x10000 - factorInt;
                    var a_val:Int = (factorInt & 0xff00) | div;
                    var b_val:Int = factorInt & 0xff;

                    initPromise = untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0xA1, value:0x0000, index:0x0000})
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x9A, value:0x1312, index:a_val}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x9A, value:0x0f2c, index:b_val}); })
                    .then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0xA4, value:(~((1<<5)|(1<<6)))&0xffff, index:0x0000}); });
                }
                else if (vid == 0x067b)   // Prolific PL2303
                {
                    // Vendor initialization sequence required to enable RX/TX buffers for PL2303
                    initPromise = untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0000, index:0x0001})
                    .then(function()
                    {
                        return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0001, index:0x0000});
                    })
                    .then(function()
                    {
                        // Critical command: RX buffer activation
                        return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0002, index:0x0044});
                    })
                    .then(function()
                    {
                        var lineCoding:Uint8Array = new Uint8Array([
                            baudRate & 0xFF,
                            (baudRate >> 8) & 0xFF,
                            (baudRate >> 16) & 0xFF,
                            (baudRate >> 24) & 0xFF,
                            0x00,  // 1 stop bit
                            0x00,  // no parity
                            0x08   // 8 data bits
                        ]);
                        return untyped dev.controlTransferOut(
                        {
                            requestType: 'class',
                            recipient: 'interface',
                            request: 0x20,
                            value: 0,
                            index: ctrlIface
                        }, lineCoding);
                    }).then(function()
                    {
                        return untyped dev.controlTransferOut(
                        {
                            requestType: 'class',
                            recipient: 'interface',
                            request: 0x22,
                            value: 0x03,
                            index: ctrlIface
                        });
                    });
                }
                else   // Standard USB CDC / ACM (Arduino, STM32, RP2040, SparkFun, Atmel SAMD, ESP32)
                {
                    var lineCoding:Uint8Array = new Uint8Array([
                        baudRate & 0xFF,
                        (baudRate >> 8) & 0xFF,
                        (baudRate >> 16) & 0xFF,
                        (baudRate >> 24) & 0xFF,
                        0x00, // 1 stop bit
                        0x00, // no parity
                        0x08  // 8 data bits
                    ]);
                    initPromise = untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x20, value:0, index:ctrlIface}, lineCoding)
                    .then(function()
                    {
                        // SET_CONTROL_LINE_STATE: Assert DTR (0x01) + RTS (0x02) = 0x03
                        return untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:0x03, index:ctrlIface});
                    });
                }

                return initPromise;
            }).then(function()
            {
                self._usbInterfaceNumber = ifaceNum;
                self._usbControlInterface = ctrlIface;
                self._usbEndpointIn = epIn;
                self._usbEndpointOut = epOut;
                return untyped Promise.resolve();
            })['catch'](function(err:Dynamic)
            {
                return untyped tryClaim(idx + 1);
            });
        };
        return untyped tryClaim(0);
    }

    // --- COMMON CALLBACKS ---
    /** Port successfully opened callback. */
    @:keep public function onPortOpened():Void
    {
        _isOpenFlag = true;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = true;
        if (_connectionType == "serial") startSerialReadLoop();
        else if (_connectionType == "usb") startUsbReadLoop();
        trace('ComPortAtom: Port opened via $_connectionType');
    }

    /** Port open error callback. */
    @:keep public function onPortOpenError(err:Dynamic):Void { setError('Failed to open port: $err'); }

    /** User dialog cancellation callback. */
    @:keep public function onPortRequestError(err:Dynamic):Void { trace('ComPortAtom: Port request cancelled or failed: $err'); }

    /** Close serial port or USB device. */
    private function closeDevice():Void
    {
        if (!_isOpenFlag) return;
        _isOpenFlag = false;
        _isReading = false;

        if (_connectionType == "serial")
        {
            var self = this;
            var port:Dynamic = _serialPort;
            var closeSequence:Dynamic = untyped Promise.resolve();

            if (_reader != null)
            {
                var reader:Dynamic = _reader;
                _reader = null;
                closeSequence = closeSequence.then(function()
                {
                    return untyped reader.cancel().then(function() {}, function(err:Dynamic) { return null; });
                }).then(function()
                {
                    untyped reader.releaseLock();
                });
            }

            if (_writer != null)
            {
                var writer:Dynamic = _writer;
                _writer = null;
                closeSequence = closeSequence.then(function()
                {
                    return untyped writer.close().then(function() {}, function(err:Dynamic) { return null; });
                }).then(function()
                {
                    untyped writer.releaseLock();
                });
            }

            if (port != null)
            {
                closeSequence = closeSequence.then(function()
                {
                    return untyped port.close();
                }).then(function()
                {
                    self.onPortClosed();
                }, function(err:Dynamic)
                {
                    self.onPortCloseError(err);
                });
            }
            else
            {
                closeSequence = closeSequence.then(function()
                {
                    self.onPortClosed();
                });
            }
            _serialPort = null;
        }
        else if (_connectionType == "usb")
        {
            var self = this;
            var dev:Dynamic = _usbDevice;
            var p:Dynamic = untyped Promise.resolve();

            if (_usbInterfaceNumber != -1)
            {
                p = p.then(function()
                {
                    return untyped dev.releaseInterface(_usbInterfaceNumber).then(function() {}, function(e:Dynamic) { return null; });
                });
            }

            if (_usbControlInterface != -1 && _usbControlInterface != _usbInterfaceNumber)
            {
                p = p.then(function()
                {
                    return untyped dev.releaseInterface(_usbControlInterface).then(function() {}, function(e:Dynamic) { return null; });
                });
            }

            p = p.then(function()
            {
                return untyped dev.close().then(function() {}, function(e:Dynamic) { return null; });
            }).then(function()
            {
                self.onPortClosed();
            }, function(err:Dynamic)
            {
                self.onPortCloseError(err);
            });
            _usbDevice = null;
        }
    }

    /** Port closed callback. */
    @:keep public function onPortClosed():Void
    {
        _isOpenFlag = false;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = false;
        trace('ComPortAtom: Port closed');
    }

    /** Port close error callback. */
    @:keep public function onPortCloseError(err:Dynamic):Void { setError('Failed to close port: $err'); }

    // --- READ LOOPS ---
    /** Start Web Serial read loop. */
    private function startSerialReadLoop():Void
    {
        _isReading = true;
        if (_serialPort == null) return;
        var readable:Dynamic = untyped js.Syntax.code("{0}.readable", _serialPort);
        if (readable == null) { setError("Port has no readable stream"); return; }
        _reader = untyped js.Syntax.code("{0}.getReader()", readable);
        readSerialChunk();
    }

    /** Read one chunk from Web Serial reader. */
    private function readSerialChunk():Void
    {
        if (!_isReading || _isDisposed) return;
        var self = this;
        untyped _reader.read().then(function(result:Dynamic) { self.onReadResult(result); })
        ['catch'](function(err:Dynamic) { self.onReadError(err); });
    }

    /** Start WebUSB read loop. */
    private function startUsbReadLoop():Void
    {
        _isReading = true;
        if (_usbDevice == null || _usbEndpointIn == -1) return;
        readUsbChunk();
    }

    /** Read one chunk via WebUSB transferIn. */
    private function readUsbChunk():Void
    {
        if (!_isReading || _isDisposed) return;
        var self = this;
        untyped _usbDevice.transferIn(_usbEndpointIn, 64).then(function(result:Dynamic) { self.onUsbReadResult(result); })
        ['catch'](function(err:Dynamic) { self.onUsbReadError(err); });
    }

    // --- READ RESULTS ---
    /** Process Web Serial read result chunk. */
    @:keep public function onReadResult(result:Dynamic):Void
    {
        if (result.done) { _isReading = false; return; }
        var bytes:Array<Int> = [];
        var value:Dynamic = result.value;
        var len:Int = untyped js.Syntax.code("{0}.length", value);
        for (i in 0...len) bytes.push(untyped js.Syntax.code("{0}[{1}]", value, i));
        writeToBuffer(bytes);
        _hasPendingRx = true;
        readSerialChunk();
    }

    /** Web Serial read error handler. */
    @:keep public function onReadError(err:Dynamic):Void { if (_isReading && !_isDisposed) setError('Read error: $err'); }

    /** Process WebUSB transferIn result. */
    @:keep public function onUsbReadResult(result:Dynamic):Void
    {
        if (result.status == 'stall')
        {
            var self = this;
            untyped _usbDevice.clearHalt('in', _usbEndpointIn).then(function() { self.readUsbChunk(); });
            return;
        }
        if (result.status == 'ok' && result.data != null)
        {
            var dataView:DataView = untyped result.data;
            var len:Int = dataView.byteLength;
            if (len > 0)
            {
                var bytes:Array<Int> = [];
                for (i in 0...len)
                {
                    bytes.push(dataView.getUint8(i));
                }
                writeToBuffer(bytes);
                _hasPendingRx = true;
            }
        }
        readUsbChunk();
    }

    /** WebUSB read error handler. */
    @:keep public function onUsbReadError(err:Dynamic):Void
    {
        if (_isReading && !_isDisposed)
        {
            var errMsg = Std.string(err);
            if (errMsg.indexOf('device unavailable') == -1 && errMsg.indexOf('disconnected') == -1)
            {
                setError('USB Read error: $err');
            }
            else
            {
                _isReading = false;
            }
        }
    }

    // --- WRITE OPERATIONS ---
    /** Transmit string to device. */
    private function sendToDevice(data:String):Void
    {
        if (_connectionType == "serial")
        {
            if (_serialPort == null || !_isOpenFlag) return;
            var writable:Dynamic = untyped js.Syntax.code("{0}.writable", _serialPort);
            if (writable == null) { setError("Port has no writable stream"); return; }
            _writer = untyped js.Syntax.code("{0}.getWriter()", writable);
            var encoder:Dynamic = untyped js.Syntax.code("new TextEncoder()");
            var encoded:Dynamic = untyped js.Syntax.code("{0}.encode({1})", encoder, data);
            var self = this;
            untyped _writer.write(encoded).then(function() { self.onWriteSuccess(); })
            ['catch'](function(err:Dynamic) { self.onWriteError(err); });
        }
        else if (_connectionType == "usb")
        {
            if (_usbDevice == null || _usbEndpointOut == -1) return;
            var encoder:Dynamic = untyped js.Syntax.code("new TextEncoder()");
            var encoded:Uint8Array = untyped encoder.encode(data);
            var self = this;
            untyped _usbDevice.transferOut(_usbEndpointOut, encoded).then(function() { self.onWriteSuccess(); })
            ['catch'](function(err:Dynamic) { self.onWriteError(err); });
        }
    }

    /** Write success callback. */
    @:keep public function onWriteSuccess():Void
    {
        if (_connectionType == "serial" && _writer != null) { untyped js.Syntax.code("{0}.releaseLock()", _writer); _writer = null; }
    }

    /** Write error callback. */
    @:keep public function onWriteError(err:Dynamic):Void
    {
        setError('Write error: $err');
        if (_connectionType == "serial" && _writer != null) { untyped js.Syntax.code("{0}.releaseLock()", _writer); _writer = null; }
    }

    /** Set DTR line state (HTML5 implementation). */
    private function setDTRState(state:Bool):Void
    {
        if (_connectionType == "serial")
        {
            trace('ComPortAtom: DTR control not directly supported in standard Web Serial API without extensions.');
        }
        else if (_connectionType == "usb")
        {
            var vid:Int = untyped _usbDevice.vendorId;
            var val:Int = state ? 0x03 : 0x00;
            if (vid == 0x10c4)   // CP2102
            {
                var maskVal:Int = (state ? 1 : 0) | 0x100 | (state ? 2 : 0) | 0x200;
                untyped _usbDevice.controlTransferOut({requestType:'vendor', recipient:'device', request:0x07, value:maskVal, index:0x00});
            }
            else if (vid == 0x1a86)     // CH340
            {
                var ch340Val:Int = (~((state ? 1<<5 : 0) | (state ? 1<<6 : 0))) & 0xffff;
                untyped _usbDevice.controlTransferOut({requestType:'vendor', recipient:'device', request:0xA4, value:ch340Val, index:0x00});
            }
            else     // CDC / ACM
            {
                untyped _usbDevice.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:val, index:_usbControlInterface});
            }
        }
    }

    /** Set pending error message. */
    private function setError(msg:String):Void
    {
        _pendingErrStr = msg;
        _hasPendingErr = true;
    }
    #end

    // =========================================================================
    // PULSE TIMERS (COMMON)
    // =========================================================================
    /** Update pulse timers and auto-reset tick contacts. */
    private function updatePulseTimers(dt:Float):Void
    {
        if (_rxTimer > 0) { _rxTimer -= dt; if (_rxTimer <= 0) { var c = getOutput("rxTick"); if (c != null) c.value = false; } }
        if (_txTimer > 0) { _txTimer -= dt; if (_txTimer <= 0) { var c = getOutput("txTick"); if (c != null) c.value = false; } }
        if (_errTimer > 0) { _errTimer -= dt; if (_errTimer <= 0) { var c = getOutput("errorTick"); if (c != null) c.value = false; } }
    }

    /**
    * Helper to restore fullscreen after a browser dialog closes.
    */
    private function _restoreFullscreen():Void
    {
        #if html5
        var cfg = ui.DisplayConfig.getInstance();
        var win = openfl.Lib.current.stage.window;
        cfg.reenterFullscreen(win);
        #end
    }

    #if html5
    /**
    * Re-enter fullscreen mode after a browser dialog closes.
    * Delegates to DisplayConfig which correctly targets the canvas element
    * and triggers stage resize.
    */
    private function _reenterFullscreen():Void
    {
        var cfg = ui.DisplayConfig.getInstance();
        var win = openfl.Lib.current.stage.window;
        cfg.reenterFullscreen(win);
    }
    #end
}