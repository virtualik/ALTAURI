#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// НЕ включаем windows.h в header!
// Все Windows-типы доступны только в .cpp через @:cppFileCode и __cpp__()
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
// C++ СТРУКТУРА СОСТОЯНИЯ ПОРТА
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
// ФОНОВЫЙ ПОТОК ЧТЕНИЯ (Rx)
// ================================================================
// ИСПРАВЛЕНО: правильная обработка ReadFile при таймауте
//
// Когда COMMTIMEOUTS настроены и данных нет, ReadFile может:
//   а) вернуть FALSE + GetLastError() == ERROR_TIMEOUT  → НЕ ошибка!
//   б) вернуть TRUE  + bytesRead == 0                    → НЕ ошибка!
//   в) вернуть FALSE + GetLastError() == ERROR_OPERATION_ABORTED → порт закрыт
//   г) вернуть TRUE  + bytesRead > 0                     → есть данные!
//   д) вернуть FALSE + другой код ошибки                 → реальная ошибка
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
            // ── СЛУЧАЙ (г): Получены данные ──
            tempBuf[bytesRead] = 0;
            
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            strncpy(st->rxBuffer, tempBuf, sizeof(st->rxBuffer) - 1);
            st->rxBuffer[sizeof(st->rxBuffer) - 1] = 0;
            st->hasRxData = true;
        }
        else if (bResult && bytesRead == 0) {
            // ── СЛУЧАЙ (б): Таймаут, данных нет — продолжаем ──
            continue;
        }
        else {
            // ── ReadFile вернул FALSE ──
            DWORD lastError = GetLastError();
            
            if (lastError == ERROR_TIMEOUT) {
                // ── СЛУЧАЙ (а): Таймаут — НЕ ошибка, продолжаем ──
                continue;
            }
            
            if (lastError == ERROR_OPERATION_ABORTED || !st->isRunning) {
                // ── СЛУЧАЙ (в): Порт закрывается — штатный выход ──
                break;
            }
            
            // ── СЛУЧАЙ (д): Реальная ошибка ──
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
class ComPortAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================
    private static inline var PULSE_DURATION:Float = 0.05;
    
    // =========================================================================
    // ПАРАМЕТРЫ И ВХОДЫ
    // =========================================================================
    private var _lastTxData:String = "";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;

    // =========================================================================
    // PENDING-ПОЛЯ
    // =========================================================================
    @:volatile private var _hasPendingRx:Bool = false;
    @:volatile private var _hasPendingErr:Bool = false;
    
    private var _pendingRxStr:String = "";
    private var _pendingErrStr:String = "";

    // =========================================================================
    // PULSE ТАЙМЕРЫ
    // =========================================================================
    private var _rxTimer:Float = 0.0;
    private var _txTimer:Float = 0.0;
    private var _errTimer:Float = 0.0;

    // =========================================================================
    // КОНСТРУКТОР
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
        // Порт открывается по триггеру "open"
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // 1. ОПРОС C++ БУФЕРА
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

        // 2. ОБРАБОТКА PENDING ДАННЫХ
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

        // 3. ЧТЕНИЕ ВХОДОВ И УПРАВЛЕНИЕ
        readInputs();
        
        // 4. ОБНОВЛЕНИЕ ТАЙМЕРОВ ИМПУЛЬСОВ
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // ЧТЕНИЕ ВХОДОВ
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
    // РАБОТА С УСТРОЙСТВОМ
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
                // Форматируем имя порта (поддержка COM10+)
                // Всегда добавляем dot-slash префикс для любого COM порта
                // charCodeAt ненадёжен в __cpp__, проверяем через C-строку
                char fullPortName[20] = "";
                ::String portStr = {1};
                const char* _cps_rawName = portStr.c_str();
                if (_cps_rawName[0] == (char)92) {
                    // Уже содержит префикс path - используем как есть
                    strncpy(fullPortName, _cps_rawName, sizeof(fullPortName) - 1);
                } else {
                    // Добавляем префикс path
                    fullPortName[0] = (char)92;  // backslash
                    fullPortName[1] = (char)92;  // backslash
                    fullPortName[2] = (char)46;  // dot
                    fullPortName[3] = (char)92;  // backslash
                    strncpy(fullPortName + 4, _cps_rawName, sizeof(fullPortName) - 5);
                }
                fullPortName[sizeof(fullPortName) - 1] = 0;

                // Открываем порт
                st->hComm = CreateFileA(fullPortName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
                if (st->hComm == INVALID_HANDLE_VALUE) {
                    DWORD err = GetLastError();
                    sprintf(st->errBuffer, "Open Failed:%lu", err);
                    st->hasError = true;
                } else {
                    // ── Устанавливаем размеры буферов (уменьшает задержки) ──
                    SetupComm(st->hComm, 4096, 4096);

                    // ── Настраиваем DCB (скорость, 8-N-1) ──
                    DCB dcbSerialParams;
                    memset(&dcbSerialParams, 0, sizeof(DCB));
                    dcbSerialParams.DCBlength = sizeof(DCB);
                    GetCommState(st->hComm, &dcbSerialParams);
                    
                    dcbSerialParams.BaudRate = (DWORD){2};
                    dcbSerialParams.ByteSize = 8;
                    dcbSerialParams.StopBits = ONESTOPBIT;
                    dcbSerialParams.Parity = NOPARITY;
                    // Явно управляем DTR/RTS — не даём драйверу дёргать линии
                    dcbSerialParams.fDtrControl = DTR_CONTROL_ENABLE;
                    dcbSerialParams.fRtsControl = RTS_CONTROL_ENABLE;
                    
                    if (!SetCommState(st->hComm, &dcbSerialParams)) {
                        DWORD err = GetLastError();
                        sprintf(st->errBuffer, "SetCommState:%lu", err);
                        st->hasError = true;
                        CloseHandle(st->hComm);
                        st->hComm = INVALID_HANDLE_VALUE;
                    } else {
                        // ── Настраиваем таймауты ──
                        // ReadIntervalTimeout = MAXDWORD + ReadTotalTimeout = 0
                        // → ReadFile возвращается НЕМЕДЛЕННО с тем что есть в буфере
                        // Это лучший паттерн для неблокирующего чтения
                        COMMTIMEOUTS timeouts;
                        memset(&timeouts, 0, sizeof(COMMTIMEOUTS));
                        timeouts.ReadIntervalTimeout = MAXDWORD;
                        timeouts.ReadTotalTimeoutMultiplier = 0;
                        timeouts.ReadTotalTimeoutConstant = 0;
                        timeouts.WriteTotalTimeoutMultiplier = 10;
                        timeouts.WriteTotalTimeoutConstant = 100;
                        SetCommTimeouts(st->hComm, &timeouts);
                        
                        // ── Очищаем буферы от мусора ──
                        PurgeComm(st->hComm, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);
                        
                        // ── Запускаем фоновый поток чтения ──
                        st->readThread = new std::thread(_altauri_com_reader_loop, (void*){0}.mPtr);
                    }
                }
            #endif

            // Сохраняем указатель в карту и проверяем успешность
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

        // Сначала извлекаем указатель из карты (кратко локаем),
        // потом освобождаем ресурсы БЕЗ удержания мьютекса —
        // чтобы не висеть на join() с замком
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
                    // Сигналим потоку остановиться
                    st->isRunning = false;
                    
                    // Отменяем ожидающий ReadFile
                    if (st->hComm != INVALID_HANDLE_VALUE) {
                        CancelIoEx(st->hComm, NULL);
                    }
                    
                    // Ждём завершения потока (уже без мьютекса!)
                    if (st->readThread && st->readThread->joinable()) {
                        st->readThread->join();
                    }
                    delete st->readThread;
                    
                    // Закрываем порт
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
    // PULSE ТАЙМЕРЫ
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
