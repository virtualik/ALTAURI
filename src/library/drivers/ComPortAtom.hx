// FILE: library/drivers/ComPortAtom.hx
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
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT ATOM v2.7.0                                  ║
* ║          (Dual-Platform Serial Driver: C++ WinAPI + HTML5 Web Serial)     ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Active driver atom for serial port communication.                        ║
* ║  At compile time, Haxe selects the appropriate backend:                   ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    COMPILATION FLOW                                 │  ║
* ║  │                                                                     │  ║
* ║  │  haxe -cpp  ──► #if cpp   ──► WinAPI CreateFile + ReadFile thread   │  ║
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
* ║  │  │  WinAPI CreateFileA      │  │  Web Serial API (primary)        │ │  ║
* ║  │  │  SetupComm + DCB         │  │  navigator.serial.requestPort    │ │  ║
* ║  │  │  COMMTIMEOUTS            │  │  port.open(options)              │ │  ║
* ║  │  │  std::thread reader      │  │  readable.getReader()            │ │  ║
* ║  │  │  ReadFile loop           │  │                                  │ │  ║
* ║  │  │  WriteFile               │  │  WebUSB API (fallback)           │ │  ║
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
* ║  │ setDTR         │ false    │ DTR line state (C++ only)                │ ║
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
* ║  │  [C++: ReadFile thread]  OR  [JS: reader.read() / transferIn()]     │  ║
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
* ║  │  [C++: WriteFile(hComm, data)]  OR  [JS: writer.write(encoded)]     │  ║
* ║  │      │                           OR  [JS: transferOut(ep, data)]    │  ║
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
* ║  │    copy rxBuffer → _pendingRxStr        ReadFile(hComm, buf)        │  ║
* ║  │    hasRxData = false                    lock(rxMutex)               │  ║
* ║  │    unlock                               append to rxBuffer          │  ║
* ║  │                                         hasRxData = true            │  ║
* ║  │    emit rxData                          unlock                      │  ║
* ║  │  }                                      }                           │  ║
* ║  │                                         isRunning = false           │  ║
* ║  │  closeDevice() {                      }                             │  ║
* ║  │    isRunning = false                                                │  ║
* ║  │    CancelIoEx(hComm)                  Thread exits cleanly          │  ║
* ║  │    readThread->join()                                               │  ║
* ║  │    CloseHandle(hComm)                                               │  ║
* ║  │  }                                                                  │  ║
* ║  │                                                                     │  ║
* ║  │  Synchronization: std::mutex (rxMutex, errMutex, _com_map_mutex)    │  ║
* ║  │  Lifecycle: ComPortState* stored in _com_states_map keyed by        │  ║
* ║  │             Haxe object pointer (this.mPtr)                         │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     HTML5 BACKEND: USB CHIP INIT                          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  When Web Serial API is unavailable (e.g., Android Chrome), the atom      ║
* ║  falls back to WebUSB with chip-specific initialization sequences:        ║
* ║                                                                           ║
* ║  ┌──────────┬──────────┬──────────────────────────────────────────────┐   ║
* ║  │ Chip     │ VendorID │ Init Sequence                                │   ║
* ║  ├──────────┼──────────┼──────────────────────────────────────────────┤   ║
* ║  │ CP2102   │ 0x10C4   │ 1. Enable UART (req 0x00, val 0x01)          │   ║
* ║  │          │          │ 2. Set line control (req 0x03, val 0x0800)   │   ║
* ║  │          │          │ 3. Set MHS (req 0x07, val 0x0303)            │   ║
* ║  │          │          │ 4. Set baud rate (req 0x1E, 4-byte LE)       │   ║
* ║  ├──────────┼──────────┼──────────────────────────────────────────────┤   ║
* ║  │ FTDI     │ 0x0403   │ 1. Reset (req 0x00)                          │   ║
* ║  │          │          │ 2. Purge RX/TX (req 0x02)                    │   ║
* ║  │          │          │ 3. Set flow control (req 0x04, val 0x0008)   │   ║
* ║  │          │          │ 4. Set baud divisor (req 0x03, encoded)      │   ║
* ║  │          │          │ 5. Set DTR/RTS (req 0x01, val 0x0303)        │   ║
* ║  ├──────────┼──────────┼──────────────────────────────────────────────┤   ║
* ║  │ CH340    │ 0x1A86   │ 1. Read init (req 0xA1)                      │   ║
* ║  │          │          │ 2. Set prescaler (req 0x9A, val 0x1312)      │   ║
* ║  │          │          │ 3. Set divisor (req 0x9A, val 0x0f2c)        │   ║
* ║  │          │          │ 4. Set line control (req 0xA4, bitmask)      │   ║
* ║  ├──────────┼──────────┼──────────────────────────────────────────────┤   ║
* ║  │ CDC/ACM  │ (any)    │ 1. SET_LINE_CODING (req 0x20, 7-byte struct) │   ║
* ║  │ (std)    │          │ 2. SET_CONTROL_LINE (req 0x22, val 0x03)     │   ║
* ║  └──────────┴──────────┴──────────────────────────────────────────────┘   ║
* ║                                                                           ║
* ║  Interface selection algorithm:                                           ║
* ║  1. Find CDC control interface (class 0x02) for ctrlIface                 ║
* ║  2. Score all interfaces with bulk IN + bulk OUT endpoints                ║
* ║  3. Prefer CDC data interface (class 0x0A, score=0) over others           ║
* ║  4. Try claimInterface + selectAlternateInterface in score order          ║
* ║  5. On failure, try next candidate (recursive tryClaim)                   ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     BATCHED DRIVER UPDATE PATTERN                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Per ALTAURI architecture (ARHITECTURE_PATTERNS.md §2):                   ║
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
* ║  v2.7.0 — HTML5 Deprecation Fix + Unused Variable Cleanup                 ║
* ║  ─────────────────────────────────────────────────────────                ║
* ║  - FIXED: Replaced all deprecated __js__() calls with js.Syntax.code()    ║
* ║    for HTML5 target compatibility with Haxe 4.3+.                         ║
* ║  - FIXED: Removed unused import (core.types.ContactType.*) — replaced     ║
* ║    with explicit ContactType.INPUT / ContactType.OUTPUT references.       ║
* ║  - FIXED: Removed unused variable `baudC` in readInputs().                ║
* ║  - FIXED: Removed unused intermediate variable `serial` in openDevice().  ║
* ║  - ADDED: import js.Syntax for HTML5 target.                              ║
* ║                                                                           ║
* ║  v2.6.5 — C++ Bracket Balancing Fix                                       ║
* ║  ─────────────────────────────────                                        ║
* ║  - FIXED: Corrected all C++ bracket balancing in __cpp__ blocks to        ║
* ║    prevent "unmatched '{'" cascade errors in Windows/MSVC compilation.    ║
* ║  - FIXED: Ensured _com_states_map.end() is used instead of                ║
* ║    _com_map_mutex.end().                                                  ║
* ║                                                                           ║
* ║  v2.6.4 — Type Conversion Fix                                             ║
* ║  ─────────────────────────                                                ║
* ║  - Replaced Std.int() with cast Math.floor() for Int conversion.          ║
* ║  - Removed unused js.Syntax import.                                       ║
* ║                                                                           ║
* ║  v2.6.3 — HTML5 Compatibility Fixes                                       ║
* ║  ──────────────────────────────────                                       ║
* ║  - Replaced Math.min() with ternary operator.                             ║
* ║  - Added explicit cast for DataView.setUint32().                          ║
* ║                                                                           ║
* ║  v2.6.2 — TypedArray Migration                                            ║
* ║  ─────────────────────────────                                            ║
* ║  - Migrated all TypedArrays from js.html.* to js.lib.*.                   ║
* ║                                                                           ║
* ║  v2.6.1 — Haxe Parser Conflict Fix                                        ║
* ║  ──────────────────────────────────                                       ║
* ║  - Replaced .catch() with ['catch']() to prevent Haxe parser conflicts.   ║
* ║                                                                           ║
* ║  v2.6 — WebUSB Fallback                                                   ║
* ║  ─────────────────────                                                    ║
* ║  - ADDED: Full WebUSB API fallback for Android devices.                   ║
* ║  - ADDED: Chip-specific initialization for CP2102, FTDI, CH340, CDC/ACM.  ║
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
	* Contact layout:
	* ┌─────────────────────────────────────────────────────────────────┐
	* │  INPUTS (11):  portName, baudRate, bufferSize, chunkSize,       │
	* │                enabled, open, close, send, txData, setDTR,      │
	* │                testRxData                                       │
	* │                                                                 │
	* │  OUTPUTS (6):  isOpen, rxData, rxTick, txTick, error, errorTick │
	* └─────────────────────────────────────────────────────────────────┘
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
	* Called at construction and when bufferSize input changes at runtime.
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
	*
	* Overflow policy: when the buffer is full, the oldest data is
	* overwritten by advancing _readPos. This ensures the most recent
	* data is always preserved at the cost of losing old data.
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
	/**
	* Clear the ring buffer, resetting all positions and counters.
	* Called on port open to discard stale data from previous session.
	*/
	private function clearBuffer():Void { _readPos = 0; _writePos = 0; _overflowCount = 0; }

	/**
	* Emit pending RX data from the ring buffer to the rxData output contact.
	*
	* Reads up to _chunkSize bytes per call, converts them to a String
	* via String.fromCharCode(), and pushes to the output using the
	* batched driver update pattern (setValueSilent + propagateCurrentValue).
	*
	* Also triggers the rxTick pulse to notify downstream atoms of new data.
	*
	* Called from update(dt) on HTML5 target. On C++ target, data is
	* emitted directly from the pending fields (already converted to String
	* by the reader thread copy in update()).
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
	/**
	* Driver initialization hook.
	* Called once when the driver is registered with DriverManager.
	* ComPortAtom requires no special initialization beyond the constructor.
	*/
	override public function init():Void {}

	/**
	* Main driver update loop. Called every simulation tick by DriverManager.
	*
	* Execution order within a single tick:
	* ┌─────────────────────────────────────────────────────────────────┐
	* │  1. Guard: skip if disposed or disabled                         │
	* │  2. readConfiguration(): hot-reload bufferSize/chunkSize/enabled│
	* │  3. Test injection: if testRxData is set, emit it directly      │
	* │  4. Platform poll:                                              │
	* │     C++:   copy rxBuffer/errBuffer from ComPortState via mutex  │
	* │     HTML5: (data arrives via async callbacks, sets _hasPendingRx)│
	* │  5. Emit pending RX data (batched: setValueSilent + propagate)  │
	* │  6. Emit pending error (batched: setValueSilent + propagate)    │
	* │  7. HTML5: emitRxData() from ring buffer                        │
	* │  8. readInputs(): process open/close/send/DTR commands          │
	* │  9. updatePulseTimers(dt): auto-reset tick contacts             │
	* └─────────────────────────────────────────────────────────────────┘
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

		// === Emit pending RX data (common path for both platforms) ===
		if (_hasPendingRx)
		{
			_hasPendingRx = false;
			var rxOut = getOutput("rxData");
			if (rxOut != null) { rxOut.setValueSilent(_pendingRxStr); rxOut.propagateCurrentValue(); }
			var rxTick = getOutput("rxTick");
			if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
		}
		// === Emit pending error (common path for both platforms) ===
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

	/**
	* Dispose the driver and release all resources.
	*
	* Closes the serial port (platform-specific), unregisters from
	* DriverManager, and calls super.dispose() to release contacts
	* and NamingService slot.
	*
	* C++ path: closeDevice() sets isRunning=false, CancelIoEx,
	*           joins reader thread, closes HANDLE.
	* HTML5 path: closeDevice() cancels reader, releases locks,
	*             closes port/device via Promise chain.
	*/
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
	/**
	* Read and apply runtime configuration from input contacts.
	*
	* Supports hot-reload of:
	* - bufferSize: reinitializes ring buffer if changed (256..65536)
	* - chunkSize: updates emit chunk size (1..4096)
	* - enabled: master on/off switch for all I/O processing
	*
	* Called at the beginning of every update(dt) cycle.
	*/
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
	*
	* Pulse-based commands (open, close, send) are auto-reset to false
	* after processing to prevent re-triggering on the next tick.
	*
	* DTR is edge-detected: only acts when the value changes from
	* the last known state (_lastDTR) and the port is open.
	*
	* ┌─────────────────────────────────────────────────────────────────┐
	* │  Command Processing:                                            │
	* │                                                                 │
	* │  open=true  → openDevice()  → open=false                        │
	* │  close=true → closeDevice() → close=false                       │
	* │  send=true  → sendToDevice(txData) → send=false + txTick pulse  │
	* │  setDTR     → edge-detect → setDTRState(newDTR)                 │
	* └─────────────────────────────────────────────────────────────────┘
	*/
	private function readInputs():Void
	{
		var openC  = getInput("open");
		var closeC = getInput("close");
		var sendC  = getInput("send");
		var txC    = getInput("txData");
		var dtrC   = getInput("setDTR");

		if (openC != null && openC.value == true) { openDevice(); openC.value = false; }
		if (closeC != null && closeC.value == true) { closeDevice(); closeC.value = false; }
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
// DEVICE OPERATION (C++ WinAPI)
// =========================================================================
	#if cpp
	/**
	* Open the serial port using WinAPI CreateFileA.
	*
	* Sequence:
	* 1. Close existing port if already open
	* 2. Create ComPortState struct and register in _com_states_map
	* 3. Build \\.\COMx path (handles both "COM1" and "\\.\COM1" input)
	* 4. CreateFileA with GENERIC_READ | GENERIC_WRITE
	* 5. SetupComm(4096, 4096) for internal driver buffers
	* 6. Configure DCB: baud rate, 8N1, DTR/RTS enable
	* 7. Set COMMTIMEOUTS: non-blocking read, 100ms write timeout
	* 8. PurgeComm to clear stale data
	* 9. Spawn std::thread for background ReadFile loop
	*
	* On failure, error is stored in ComPortState.errBuffer and
	* surfaced via the error output contact on the next update(dt).
	*/
	private function openDevice():Void
	{
		if (_isOpenFlag) closeDevice();
		var portNameStr:String = getInput("portName").value;
		var baudRateInt:Int = cast getInput("baudRate").value;
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

	/**
	* Close the serial port and clean up the reader thread.
	*
	* Sequence:
	* 1. Remove ComPortState from _com_states_map (under mutex)
	* 2. Set isRunning = false (signals reader thread to exit)
	* 3. CancelIoEx to unblock any pending ReadFile
	* 4. Join reader thread (waits for clean exit)
	* 5. PurgeComm + CloseHandle
	* 6. Delete ComPortState struct
	* 7. Update isOpen output to false
	*/
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
		#endif
		delete st;
	}
		', this);
		_isOpenFlag = false;
		var outOpen = getOutput("isOpen");
		if (outOpen != null) outOpen.value = false;
	}

	/**
	* Transmit a string to the serial port via WinAPI WriteFile.
	*
	* Looks up ComPortState from _com_states_map, then calls
	* WriteFile with the string's c_str() representation.
	*
	* @param data String data to transmit
	*/
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
		#endif
	}
		', this, data);
	}

	/**
	* Set the DTR (Data Terminal Ready) line state via EscapeCommFunction.
	*
	* @param state true = SETDTR (assert), false = CLRDTR (deassert)
	*/
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
	* Open a serial port via Web Serial API or WebUSB fallback.
	*
	* Detection logic:
	* ┌─────────────────────────────────────────────────────────────────┐
	* │  1. Check navigator.serial → Web Serial API (desktop Chrome)    │
	* │     └─► requestPort() → user picks port from browser dialog     │
	* │                                                                 │
	* │  2. Else check navigator.usb → WebUSB API (Android Chrome)      │
	* │     └─► requestDevice() with vendor ID filters:                 │
	* │         0x303A (Espressif), 0x0403 (FTDI),                      │
	* │         0x1A86 (CH340), 0x10C4 (CP2102), 0x067B (Prolific)     │
	* │                                                                 │
	* │  3. Else → setError("Neither API supported")                    │
	* └─────────────────────────────────────────────────────────────────┘
	*
	* Both paths are async (Promise-based). The port is not considered
	* open until onPortOpened() fires.
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
			untyped js.Syntax.code("navigator.serial").requestPort().then(function(port:Dynamic) { self.onSerialPortRequested(port); })
			['catch'](function(err:Dynamic) { self.onPortRequestError(err); });
		}
		else if (hasUSB)
		{
			_connectionType = "usb";
			var self = this;
			var filters:Array<Dynamic> = [
			{ vendorId: 0x303A }, { vendorId: 0x0403 }, { vendorId: 0x1A86 }, { vendorId: 0x10C4 }, { vendorId: 0x067B }
			];
			untyped js.Syntax.code("navigator.usb").requestDevice({ filters: filters }).then(function(device:Dynamic)
			{
				self.onUsbDeviceRequested(device);
			})['catch'](function(err:Dynamic)
			{
				self.onPortRequestError(err);
			});
		}
		else
		{
			setError("Neither Web Serial API nor WebUSB is supported in this browser.");
		}
	}

// --- WEB SERIAL CALLBACKS ---
	/**
	* Web Serial: port selected by user via browser dialog.
	* Opens the port with configured baud rate and standard 8N1 settings.
	*
	* @param port Native SerialPort object from navigator.serial.requestPort()
	*/
	@:keep public function onSerialPortRequested(port:Dynamic):Void
	{
		_serialPort = port;
		var baudRateInt:Int = 9600;
		var baudC = getInput("baudRate");
		if (baudC != null && baudC.value != null) baudRateInt = cast baudC.value;
		var options:Dynamic = { baudRate: baudRateInt, dataBits: 8, stopBits: 1, parity: "none", bufferSize: 4096, flowControl: "none" };
		var self = this;
		untyped _serialPort.open(options).then(function() { self.onPortOpened(); })
		['catch'](function(err:Dynamic) { self.onPortOpenError(err); });
	}

// --- WEB USB CALLBACKS ---
	/**
	* WebUSB: device selected by user via browser dialog.
	* Opens the device, selects configuration 1, then claims interfaces
	* and runs chip-specific initialization.
	*
	* @param device Native USBDevice object from navigator.usb.requestDevice()
	*/
	@:keep public function onUsbDeviceRequested(device:Dynamic):Void
	{
		_usbDevice = device;
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

	/**
	* WebUSB: Claim USB interfaces and run chip-specific baud rate init.
	*
	* Algorithm:
	* 1. Find CDC control interface (class 0x02) for ctrlIface
	* 2. Score all interfaces with bulk IN + bulk OUT endpoints
	*    - CDC data interface (class 0x0A) gets score 0 (preferred)
	*    - All others get score 1
	* 3. Sort candidates by score (ascending)
	* 4. Try claimInterface + selectAlternateInterface in order
	* 5. Run chip-specific init based on vendorId:
	*    - 0x10C4 (CP2102): vendor requests 0x00, 0x03, 0x07, 0x1E
	*    - 0x0403 (FTDI):   vendor requests 0x00, 0x02, 0x04, 0x03, 0x01
	*    - 0x1A86 (CH340):  vendor requests 0xA1, 0x9A, 0x9A, 0xA4
	*    - default (CDC):   class requests 0x20 (SET_LINE_CODING), 0x22
	* 6. On failure, recursively try next candidate
	*
	* @param baudRate Target baud rate for chip initialization
	* @return Promise that resolves when init is complete
	*/
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

				if (vid == 0x10c4)   // CP2102
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
				else if (vid == 0x0403)   // FTDI
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
				else if (vid == 0x1a86)   // CH340
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
				else   // Standard CDC/ACM
				{
					var lineCoding:Uint8Array = new Uint8Array([baudRate & 0xFF, (baudRate >> 8) & 0xFF, (baudRate >> 16) & 0xFF, (baudRate >> 24) & 0xFF, 0x00, 0x00, 0x08]);
					initPromise = untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x20, value:0, index:ctrlIface}, lineCoding)
					.then(function() { return untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:0x03, index:ctrlIface}); });
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
	/**
	* Called when the port is successfully opened (both Serial and USB paths).
	* Sets _isOpenFlag, updates isOpen output, and starts the read loop.
	*/
	@:keep public function onPortOpened():Void
	{
		_isOpenFlag = true;
		var outOpen = getOutput("isOpen");
		if (outOpen != null) outOpen.value = true;

		if (_connectionType == "serial") startSerialReadLoop();
		else if (_connectionType == "usb") startUsbReadLoop();

		trace('ComPortAtom: Port opened via $_connectionType');
	}

	/** Port open failed — surface error to output contact. */
	@:keep public function onPortOpenError(err:Dynamic):Void { setError('Failed to open port: $err'); }
	/** User cancelled the port/device selection dialog. */
	@:keep public function onPortRequestError(err:Dynamic):Void { trace('ComPortAtom: Port request cancelled or failed: $err'); }

	/**
	* Close the serial port (Web Serial or WebUSB).
	*
	* Web Serial close sequence:
	* 1. reader.cancel() → reader.releaseLock()
	* 2. writer.close() → writer.releaseLock()
	* 3. port.close()
	*
	* WebUSB close sequence:
	* 1. releaseInterface(dataInterface)
	* 2. releaseInterface(controlInterface) if different
	* 3. device.close()
	*
	* All steps are chained via Promises to ensure proper ordering.
	* Errors in individual steps are swallowed (port must close regardless).
	*/
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

	/** Port closed successfully — update isOpen output. */
	@:keep public function onPortClosed():Void
	{
		_isOpenFlag = false;
		var outOpen = getOutput("isOpen");
		if (outOpen != null) outOpen.value = false;
		trace('ComPortAtom: Port closed');
	}
	/** Port close failed — surface error. */
	@:keep public function onPortCloseError(err:Dynamic):Void { setError('Failed to close port: $err'); }

// --- READ LOOPS ---
	/**
	* Start the Web Serial read loop.
	* Acquires a reader from port.readable and begins recursive read chain.
	*/
	private function startSerialReadLoop():Void
	{
		_isReading = true;
		if (_serialPort == null) return;
		var readable:Dynamic = untyped js.Syntax.code("{0}.readable", _serialPort);
		if (readable == null) { setError("Port has no readable stream"); return; }
		_reader = untyped js.Syntax.code("{0}.getReader()", readable);
		readSerialChunk();
	}

	/**
	* Read one chunk from the Web Serial reader (recursive Promise chain).
	* Each call reads one chunk, processes it, then schedules the next read.
	* Stops when _isReading is false or the stream is done.
	*/
	private function readSerialChunk():Void
	{
		if (!_isReading || _isDisposed) return;
		var self = this;
		untyped _reader.read().then(function(result:Dynamic) { self.onReadResult(result); })
		['catch'](function(err:Dynamic) { self.onReadError(err); });
	}

	/**
	* Start the WebUSB read loop.
	* Begins recursive transferIn chain on the bulk IN endpoint.
	*/
	private function startUsbReadLoop():Void
	{
		_isReading = true;
		if (_usbDevice == null || _usbEndpointIn == -1) return;
		readUsbChunk();
	}

	/**
	* Read one chunk via WebUSB transferIn (recursive Promise chain).
	* Reads 64 bytes per transfer from the bulk IN endpoint.
	*/
	private function readUsbChunk():Void
	{
		if (!_isReading || _isDisposed) return;
		var self = this;
		untyped _usbDevice.transferIn(_usbEndpointIn, 64).then(function(result:Dynamic) { self.onUsbReadResult(result); })
		['catch'](function(err:Dynamic) { self.onUsbReadError(err); });
	}

// --- READ RESULTS ---
	/**
	* Web Serial: process a read result chunk.
	* Converts Uint8Array to byte array, writes to ring buffer,
	* sets _hasPendingRx flag, and schedules next read.
	*
	* @param result {done: Bool, value: Uint8Array}
	*/
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
	/** Web Serial: read error handler. */
	@:keep public function onReadError(err:Dynamic):Void { if (_isReading && !_isDisposed) setError('Read error: $err'); }

	/**
	* WebUSB: process a transferIn result.
	* Handles 'stall' status by clearing halt and retrying.
	* On 'ok' status, extracts bytes from DataView and writes to ring buffer.
	*
	* @param result {status: String, data: DataView}
	*/
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
			var bytes:Array<Int> = [];
			var view:Uint8Array = untyped result.data;
			for (i in 0...view.length) bytes.push(view[i]);
			writeToBuffer(bytes);
			_hasPendingRx = true;
		}
		readUsbChunk();
	}
	/**
	* WebUSB: read error handler.
	* Ignores "device unavailable" and "disconnected" errors (normal on unplug).
	* All other errors are surfaced via the error output contact.
	*/
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
	/**
	* Transmit a string to the serial port.
	*
	* Web Serial: acquires a writer from port.writable, encodes via
	* TextEncoder, writes, then releases the writer lock.
	*
	* WebUSB: encodes via TextEncoder, calls transferOut on bulk OUT endpoint.
	*
	* @param data String data to transmit
	*/
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

	/** Write completed successfully — release writer lock (Web Serial only). */
	@:keep public function onWriteSuccess():Void
	{
		if (_connectionType == "serial" && _writer != null) { untyped js.Syntax.code("{0}.releaseLock()", _writer); _writer = null; }
	}
	/** Write failed — surface error and release writer lock. */
	@:keep public function onWriteError(err:Dynamic):Void
	{
		setError('Write error: $err');
		if (_connectionType == "serial" && _writer != null) { untyped js.Syntax.code("{0}.releaseLock()", _writer); _writer = null; }
	}

	/**
	* Set DTR line state (HTML5 implementation).
	*
	* Web Serial: DTR control is not directly supported in the standard
	* Web Serial API without vendor-specific extensions. Logs a warning.
	*
	* WebUSB: sends chip-specific control transfer:
	* ┌──────────┬──────────────────────────────────────────────────────┐
	* │ Chip     │ DTR Control Transfer                                 │
	* ├──────────┼──────────────────────────────────────────────────────┤
	* │ CP2102   │ vendor req 0x07, value = MHS bitmask                 │
	* │ CH340    │ vendor req 0xA4, value = ~((DTR<<5)|(RTS<<6))       │
	* │ CDC/ACM  │ class req 0x22, value = 0x03 (DTR+RTS) or 0x00     │
	* └──────────┴──────────────────────────────────────────────────────┘
	*
	* @param state true = assert DTR, false = deassert DTR
	*/
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
			else     // CDC
			{
				untyped _usbDevice.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:val, index:_usbControlInterface});
			}
		}
	}

	/**
	* Set a pending error message to be emitted on the next update(dt).
	* Uses the same pending mechanism as RX data for thread safety.
	*
	* @param msg Error message string
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
	/**
	* Update pulse timers and auto-reset tick contacts.
	*
	* Each tick contact (rxTick, txTick, errorTick) is set to true when
	* an event occurs, then auto-resets to false after PULSE_DURATION
	* seconds. This method decrements the timers each frame and resets
	* the contact when the timer expires.
	*
	* ┌─────────────────────────────────────────────────────────────────┐
	* │  Timer Lifecycle:                                               │
	* │                                                                 │
	* │  Event occurs → tick.value = true, timer = PULSE_DURATION       │
	* │                                                                 │
	* │  update(dt):  timer -= dt                                       │
	* │               if timer <= 0: tick.value = false                 │
	* │                                                                 │
	* │  Result: downstream atoms see a brief TRUE pulse (50ms)         │
	* │  that can trigger one-shot actions (LED blink, counter incr.)   │
	* └─────────────────────────────────────────────────────────────────┘
	*
	* @param dt Delta time in seconds since last tick
	*/
	private function updatePulseTimers(dt:Float):Void
	{
		if (_rxTimer > 0) { _rxTimer -= dt; if (_rxTimer <= 0) { var c = getOutput("rxTick"); if (c != null) c.value = false; } }
		if (_txTimer > 0) { _txTimer -= dt; if (_txTimer <= 0) { var c = getOutput("txTick"); if (c != null) c.value = false; } }
		if (_errTimer > 0) { _errTimer -= dt; if (_errTimer <= 0) { var c = getOutput("errorTick"); if (c != null) c.value = false; } }
	}
}