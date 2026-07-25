// FILE: library/drivers/ComPortAtom.hx
package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;
#if html5
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
* COM PORT ATOM v2.6.5 (C++ Bracket Balance Fix)
*
* Serial port driver with platform-specific backends.
* 
* v2.6.5 Changes:
* - FIXED: Corrected all C++ bracket balancing in __cpp__ blocks to prevent 
*   "unmatched '{'" cascade errors in Windows/MSVC compilation.
* - FIXED: Ensured _com_states_map.end() is used instead of _com_map_mutex.end().
*
* v2.6.4 Changes:
* - Replaced Std.int() with cast Math.floor() for Int conversion.
* - Removed unused js.Syntax import.
*
* v2.6.3 Changes:
* - Replaced Math.min() with ternary operator.
* - Added explicit cast for DataView.setUint32().
*
* v2.6.2 Changes:
* - Migrated all TypedArrays from js.html.* to js.lib.*.
*
* v2.6.1 Changes:
* - Replaced .catch() with ['catch']() to prevent Haxe parser conflicts.
*
* v2.6 Changes:
* - ADDED: Full WebUSB API fallback for Android devices.
* - ADDED: Chip-specific initialization for CP2102, FTDI, CH340, and CDC/ACM.
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
/** Native browser SerialPort instance (Web Serial API). */
private var _serialPort:Dynamic = null;
/** Readable stream reader (Web Serial). */
private var _reader:Dynamic = null;
/** Writable stream writer (Web Serial). */
private var _writer:Dynamic = null;

/** Native browser USBDevice instance (WebUSB Fallback). */
private var _usbDevice:Dynamic = null;
private var _usbInterfaceNumber:Int = -1;
private var _usbEndpointIn:Int = -1;
private var _usbEndpointOut:Int = -1;
private var _usbControlInterface:Int = -1;

/** Read loop active flag. */
private var _isReading:Bool = false;
/** Connection type: "serial" or "usb" */
private var _connectionType:String = "none";
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
for (i in 0..._bufferSize) _ringBuffer.push(0);
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
if (_overflowCount % 100 == 0) trace('ComPortAtom: Ring buffer overflow! Lost $_overflowCount bytes total');
}
}
return written;
}
private function getBufferCount():Int { return _writePos - _readPos; }
private function clearBuffer():Void { _readPos = 0; _writePos = 0; _overflowCount = 0; }

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
override public function init():Void {}

override public function update(dt:Float):Void
{
if (_isDisposed) return;
readConfiguration();
if (!_enabled) return;

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

if (_hasPendingRx)
{
_hasPendingRx = false;
var rxOut = getOutput("rxData");
if (rxOut != null) { rxOut.setValueSilent(_pendingRxStr); rxOut.propagateCurrentValue(); }
var rxTick = getOutput("rxTick");
if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
}
if (_hasPendingErr)
{
_hasPendingErr = false;
var errOut = getOutput("error");
if (errOut != null) { errOut.setValueSilent(_pendingErrStr); errOut.propagateCurrentValue(); }
var errTick = getOutput("errorTick");
if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
}

#if html5
emitRxData();
#end
readInputs();
updatePulseTimers(dt);
}

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

private function readInputs():Void
{
var openC  = getInput("open");
var closeC = getInput("close");
var sendC  = getInput("send");
var txC    = getInput("txData");
var dtrC   = getInput("setDTR");
var baudC  = getInput("baudRate");

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

private function openDevice():Void
{
if (_isOpenFlag) closeDevice();
clearBuffer();

var hasSerial:Bool = untyped __js__("typeof navigator !== 'undefined' && 'serial' in navigator");
var hasUSB:Bool = untyped __js__("typeof navigator !== 'undefined' && 'usb' in navigator");

if (hasSerial)
{
_connectionType = "serial";
var serial:Dynamic = untyped __js__("navigator.serial");
var self = this;
untyped serial.requestPort().then(function(port:Dynamic) { self.onSerialPortRequested(port); })
['catch'](function(err:Dynamic) { self.onPortRequestError(err); });
}
else if (hasUSB)
{
_connectionType = "usb";
var self = this;
var filters:Array<Dynamic> = [
{ vendorId: 0x303A }, { vendorId: 0x0403 }, { vendorId: 0x1A86 }, { vendorId: 0x10C4 }, { vendorId: 0x067B }
];
untyped navigator.usb.requestDevice({ filters: filters }).then(function(device:Dynamic) { 
self.onUsbDeviceRequested(device); 
})['catch'](function(err:Dynamic) { 
self.onPortRequestError(err); 
});
}
else
{
setError("Neither Web Serial API nor WebUSB is supported in this browser.");
}
}

// --- WEB SERIAL CALLBACKS ---
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
@:keep public function onUsbDeviceRequested(device:Dynamic):Void
{
_usbDevice = device;
var baudRateInt:Int = 9600;
var baudC = getInput("baudRate");
if (baudC != null && baudC.value != null) baudRateInt = cast baudC.value;

var self = this;
untyped _usbDevice.open().then(function() {
return untyped _usbDevice.selectConfiguration(1);
}).then(function() {
return self.claimUsbInterfaces(baudRateInt);
}).then(function() {
self.onPortOpened();
})['catch'](function(err:Dynamic) {
self.onPortOpenError(err);
});
}

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

return untyped dev.claimInterface(cand.iface.interfaceNumber).then(function() {
return untyped dev.selectAlternateInterface(cand.iface.interfaceNumber, cand.altIndex)['catch'](function(e:Dynamic) { return null; });
}).then(function() {
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

if (vid == 0x10c4) { // CP2102
initPromise = untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x00, value:0x01, index:0x00})
.then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x03, value:0x0800, index:0x00}); })
.then(function() { return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x07, value:0x0303, index:0x00}); })
.then(function() { 
var buf:ArrayBuffer = new ArrayBuffer(4); 
var view:DataView = new DataView(buf); 
view.setUint32(0, baudRate, true);
return untyped dev.controlTransferOut({requestType:'vendor', recipient:'interface', request:0x1E, value:0, index:0}, buf);
});
} 
else if (vid == 0x0403) { // FTDI
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
else if (vid == 0x1a86) { // CH340
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
else { // Standard CDC/ACM
var lineCoding:Uint8Array = new Uint8Array([baudRate & 0xFF, (baudRate >> 8) & 0xFF, (baudRate >> 16) & 0xFF, (baudRate >> 24) & 0xFF, 0x00, 0x00, 0x08]);
initPromise = untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x20, value:0, index:ctrlIface}, lineCoding)
.then(function() { return untyped dev.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:0x03, index:ctrlIface}); });
}

return initPromise;
}).then(function() {
self._usbInterfaceNumber = ifaceNum;
self._usbControlInterface = ctrlIface;
self._usbEndpointIn = epIn;
self._usbEndpointOut = epOut;
return untyped Promise.resolve();
})['catch'](function(err:Dynamic) {
return untyped tryClaim(idx + 1);
});
};

return untyped tryClaim(0);
}

// --- COMMON CALLBACKS ---
@:keep public function onPortOpened():Void
{
_isOpenFlag = true;
var outOpen = getOutput("isOpen");
if (outOpen != null) outOpen.value = true;

if (_connectionType == "serial") startSerialReadLoop();
else if (_connectionType == "usb") startUsbReadLoop();

trace('ComPortAtom: Port opened via $_connectionType');
}

@:keep public function onPortOpenError(err:Dynamic):Void { setError('Failed to open port: $err'); }
@:keep public function onPortRequestError(err:Dynamic):Void { trace('ComPortAtom: Port request cancelled or failed: $err'); }

private function closeDevice():Void
{
if (!_isOpenFlag) return;
_isReading = false;

if (_connectionType == "serial")
{
if (_reader != null) {
var self = this;
untyped _reader.cancel()['catch'](function(err:Dynamic) { return null; }).then(function() { 
untyped _reader.releaseLock(); 
_reader = null; 
});
}
if (_writer != null) {
var self = this;
untyped _writer.close()['catch'](function(err:Dynamic) { return null; }).then(function() { 
untyped _writer.releaseLock(); 
_writer = null; 
});
}
if (_serialPort != null) {
var self = this;
untyped _serialPort.close().then(function() { 
self.onPortClosed(); 
})['catch'](function(err:Dynamic) { 
self.onPortCloseError(err); 
});
_serialPort = null;
}
}
else if (_connectionType == "usb")
{
var self = this;
var dev:Dynamic = _usbDevice;
var p:Dynamic = untyped Promise.resolve();

if (_usbInterfaceNumber != -1)
{
p = p.then(function() {
return untyped dev.releaseInterface(_usbInterfaceNumber)['catch'](function(e:Dynamic) { return null; });
});
}
if (_usbControlInterface != -1 && _usbControlInterface != _usbInterfaceNumber)
{
p = p.then(function() {
return untyped dev.releaseInterface(_usbControlInterface)['catch'](function(e:Dynamic) { return null; });
});
}

p = p.then(function() {
return untyped dev.close()['catch'](function(e:Dynamic) { return null; });
}).then(function() {
self.onPortClosed();
});

_usbDevice = null;
}
}

@:keep public function onPortClosed():Void
{
_isOpenFlag = false;
var outOpen = getOutput("isOpen");
if (outOpen != null) outOpen.value = false;
trace('ComPortAtom: Port closed');
}
@:keep public function onPortCloseError(err:Dynamic):Void { setError('Failed to close port: $err'); }

// --- READ LOOPS ---
private function startSerialReadLoop():Void
{
_isReading = true;
if (_serialPort == null) return;
var readable:Dynamic = untyped __js__("{0}.readable", _serialPort);
if (readable == null) { setError("Port has no readable stream"); return; }
_reader = untyped __js__("{0}.getReader()", readable);
readSerialChunk();
}

private function readSerialChunk():Void
{
if (!_isReading || _isDisposed) return;
var self = this;
untyped _reader.read().then(function(result:Dynamic) { self.onReadResult(result); })
['catch'](function(err:Dynamic) { self.onReadError(err); });
}

private function startUsbReadLoop():Void
{
_isReading = true;
if (_usbDevice == null || _usbEndpointIn == -1) return;
readUsbChunk();
}

private function readUsbChunk():Void
{
if (!_isReading || _isDisposed) return;
var self = this;
untyped _usbDevice.transferIn(_usbEndpointIn, 64).then(function(result:Dynamic) { self.onUsbReadResult(result); })
['catch'](function(err:Dynamic) { self.onUsbReadError(err); });
}

// --- READ RESULTS ---
@:keep public function onReadResult(result:Dynamic):Void
{
if (result.done) { _isReading = false; return; }
var bytes:Array<Int> = [];
var value:Dynamic = result.value;
var len:Int = untyped __js__("{0}.length", value);
for (i in 0...len) bytes.push(untyped __js__("{0}[{1}]", value, i));
writeToBuffer(bytes);
_hasPendingRx = true;
readSerialChunk();
}
@:keep public function onReadError(err:Dynamic):Void { if (_isReading && !_isDisposed) setError('Read error: $err'); }

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
@:keep public function onUsbReadError(err:Dynamic):Void 
{ 
if (_isReading && !_isDisposed) 
{
var errMsg = Std.string(err);
if (errMsg.indexOf('device unavailable') == -1 && errMsg.indexOf('disconnected') == -1) {
setError('USB Read error: $err');
} else {
_isReading = false;
}
} 
}

// --- WRITE OPERATIONS ---
private function sendToDevice(data:String):Void
{
if (_connectionType == "serial")
{
if (_serialPort == null || !_isOpenFlag) return;
var writable:Dynamic = untyped __js__("{0}.writable", _serialPort);
if (writable == null) { setError("Port has no writable stream"); return; }
_writer = untyped __js__("{0}.getWriter()", writable);
var encoder:Dynamic = untyped __js__("new TextEncoder()");
var encoded:Dynamic = untyped __js__("{0}.encode({1})", encoder, data);
var self = this;
untyped _writer.write(encoded).then(function() { self.onWriteSuccess(); })
['catch'](function(err:Dynamic) { self.onWriteError(err); });
}
else if (_connectionType == "usb")
{
if (_usbDevice == null || _usbEndpointOut == -1) return;
var encoder:Dynamic = untyped __js__("new TextEncoder()");
var encoded:Uint8Array = untyped encoder.encode(data);
var self = this;
untyped _usbDevice.transferOut(_usbEndpointOut, encoded).then(function() { self.onWriteSuccess(); })
['catch'](function(err:Dynamic) { self.onWriteError(err); });
}
}

@:keep public function onWriteSuccess():Void
{
if (_connectionType == "serial" && _writer != null) { untyped __js__("{0}.releaseLock()", _writer); _writer = null; }
}
@:keep public function onWriteError(err:Dynamic):Void
{
setError('Write error: $err');
if (_connectionType == "serial" && _writer != null) { untyped __js__("{0}.releaseLock()", _writer); _writer = null; }
}

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

if (vid == 0x10c4) { // CP2102
var maskVal:Int = (state ? 1 : 0) | 0x100 | (state ? 2 : 0) | 0x200;
untyped _usbDevice.controlTransferOut({requestType:'vendor', recipient:'device', request:0x07, value:maskVal, index:0x00});
} else if (vid == 0x1a86) { // CH340
var ch340Val:Int = (~((state ? 1<<5 : 0) | (state ? 1<<6 : 0))) & 0xffff;
untyped _usbDevice.controlTransferOut({requestType:'vendor', recipient:'device', request:0xA4, value:ch340Val, index:0x00});
} else { // CDC
untyped _usbDevice.controlTransferOut({requestType:'class', recipient:'interface', request:0x22, value:val, index:_usbControlInterface});
}
}
}

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
if (_rxTimer > 0) { _rxTimer -= dt; if (_rxTimer <= 0) { var c = getOutput("rxTick"); if (c != null) c.value = false; } }
if (_txTimer > 0) { _txTimer -= dt; if (_txTimer <= 0) { var c = getOutput("txTick"); if (c != null) c.value = false; } }
if (_errTimer > 0) { _errTimer -= dt; if (_errTimer <= 0) { var c = getOutput("errorTick"); if (c != null) c.value = false; } }
}
}