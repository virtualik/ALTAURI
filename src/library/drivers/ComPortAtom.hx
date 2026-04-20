#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// НЕ включаем windows.h в header!
// НЕ определяем Windows-макросы — они конфликтуют с OpenAL/Lime.
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
// ВАЖНО: volatile bool вместо std::atomic<bool> — иначе struct некопируема
struct ComPortState {
    HANDLE hComm;
    std::thread* readThread;
    volatile bool isRunning;  // volatile вместо std::atomic<bool>
    
    char rxBuffer[1024];
    bool hasRxData;
    std::mutex rxMutex;
    
    char errBuffer[256];
    bool hasError;
    std::mutex errMutex;
};

// Хранилище указателей (new/delete) — нет проблем с копированием
static std::map<void*, ComPortState*> _com_states_map;
static std::mutex _com_map_mutex;

// ================================================================
// ФОНОВЫЙ ПОТОК ЧТЕНИЯ (Rx)
// ================================================================
static void _altauri_com_reader_loop(void* haxePtr) {
    // Кратко локаем карту чтобы найти свой указатель
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
        if (ReadFile(st->hComm, tempBuf, sizeof(tempBuf) - 1, &bytesRead, NULL) && bytesRead > 0) {
            tempBuf[bytesRead] = 0;
            
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            strncpy(st->rxBuffer, tempBuf, sizeof(st->rxBuffer) - 1);
            st->rxBuffer[sizeof(st->rxBuffer) - 1] = 0;
            st->hasRxData = true;
        } else if (!st->isRunning) {
            break;
        } else {
            std::lock_guard<std::mutex> errLock(st->errMutex);
            sprintf(st->errBuffer, "Rx Read Error");
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
    // ПАРАМЕТРЫ И ВХОДЫ (Для отслеживания изменений)
    // =========================================================================
    private var _lastTxData:String = "";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;

    // =========================================================================
    // PENDING-ПОЛЯ (Мост между C++ потоком и Haxe потоком)
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
                new Contact("COM1", INPUT, "portName"),  // Имя порта
                new Contact(9600, INPUT, "baudRate"),    // Скорость
                new Contact(false, INPUT, "open"),       // Триггер: открыть
                new Contact(false, INPUT, "close"),      // Триггер: закрыть
                new Contact(false, INPUT, "send"),       // Триггер: отправить
                new Contact("", INPUT, "txData"),        // Строка для отправки (Tx)
                new Contact(false, INPUT, "setDTR")      // Состояние линии DTR
            ],
            [ // OUTPUTS
                new Contact(false, OUTPUT, "isOpen"),    // Порт открыт?
                new Contact("", OUTPUT, "rxData"),       // Принятые данные (Rx)
                new Contact(false, OUTPUT, "rxTick"),    // Импульс при приеме
                new Contact(false, OUTPUT, "txTick"),    // Импульс при отправке
                new Contact("", OUTPUT, "error"),        // Текст ошибки
                new Contact(false, OUTPUT, "errorTick")  // Импульс при ошибке
            ],
            null, // Без стандартной функции process
            id,
            "ComPortAtom",
            true // isActive = true (запускает update цикл)
        );
        
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        // Не открываем порт сразу, ждем пока пользователь подаст "true" на вход "open"
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        // 1. ОПРОС C++ БУФЕРА (Чтение из фонового потока)
        // Сначала получаем указатель, потом работаем с мьютексами данных
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

        // 2. ОБРАБОТКА PENDING ДАННЫХ (Передача в логическую схему)
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
    // ЧТЕНИЕ ВХОДОВ (Триггерная логика)
    // =========================================================================
    private function readInputs():Void
    {
        var openC  = getInput("open");
        var closeC = getInput("close");
        var sendC  = getInput("send");
        var txC    = getInput("txData");
        var dtrC   = getInput("setDTR");

        // --- Управление портом ---
        if (openC != null && openC.value == true) {
            openDevice();
            openC.value = false; // Сбрасываем триггер
        }
        
        if (closeC != null && closeC.value == true) {
            closeDevice();
            closeC.value = false; // Сбрасываем триггер
        }

        // --- Отправка данных (Tx) ---
        if (sendC != null && sendC.value == true && _isOpenFlag) {
            if (txC != null && txC.value != null && txC.value != "") {
                sendToDevice(txC.value);
                var txTick = getOutput("txTick");
                if (txTick != null) { txTick.value = true; _txTimer = PULSE_DURATION; }
            }
            sendC.value = false; // Сбрасываем триггер
        }

        // --- Управление линией DTR ---
        if (dtrC != null && dtrC.value != null) {
            var newDTR:Bool = dtrC.value == true;
            if (newDTR != _lastDTR && _isOpenFlag) {
                _lastDTR = newDTR;
                setDTRState(newDTR);
            }
        }
    }

    // =========================================================================
    // РАБОТА С УСТРОЙСТВОМ (C++ Вызовы)
    // =========================================================================
    private function openDevice():Void
    {
        if (_isOpenFlag) closeDevice(); // Пересоздаем если уже открыт
        
        var portNameStr:String = getInput("portName").value;
        var baudRateInt:Int = Std.int(getInput("baudRate").value);

        // Один __cpp__ блок — всё в одной C++ области видимости
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
                // Форматируем имя порта (поддержка COM10 и выше)
                char fullPortName[20] = "";
                ::String portStr = {1};
                if (portStr.length > 3 && portStr.charCodeAt(0) != 92) {
                    // Строим "\\\\.\\COMx" посимвольно — без escape-кошмара
                    fullPortName[0] = (char)92; // backslash
                    fullPortName[1] = (char)92; // backslash
                    fullPortName[2] = (char)46; // dot
                    fullPortName[3] = (char)92; // backslash
                    strcpy(fullPortName + 4, portStr.c_str());
                } else {
                    strcpy(fullPortName, portStr.c_str());
                }

                // Открываем порт
                st->hComm = CreateFileA(fullPortName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
                if (st->hComm == INVALID_HANDLE_VALUE) {
                    sprintf(st->errBuffer, "Open Failed");
                    st->hasError = true;
                } else {
                    // Настраиваем скорость и формат (8-N-1)
                    DCB dcbSerialParams;
                    memset(&dcbSerialParams, 0, sizeof(DCB));
                    dcbSerialParams.DCBlength = sizeof(DCB);
                    GetCommState(st->hComm, &dcbSerialParams);
                    
                    dcbSerialParams.BaudRate = (DWORD){2};
                    dcbSerialParams.ByteSize = 8;
                    dcbSerialParams.StopBits = ONESTOPBIT;
                    dcbSerialParams.Parity = NOPARITY;
                    
                    if (!SetCommState(st->hComm, &dcbSerialParams)) {
                        sprintf(st->errBuffer, "SetCommState Failed");
                        st->hasError = true;
                        CloseHandle(st->hComm);
                        st->hComm = INVALID_HANDLE_VALUE;
                    } else {
                        // Настраиваем таймауты
                        COMMTIMEOUTS timeouts;
                        memset(&timeouts, 0, sizeof(COMMTIMEOUTS));
                        timeouts.ReadIntervalTimeout = 50;
                        timeouts.ReadTotalTimeoutConstant = 50;
                        timeouts.ReadTotalTimeoutMultiplier = 10;
                        timeouts.WriteTotalTimeoutConstant = 50;
                        timeouts.WriteTotalTimeoutMultiplier = 10;
                        SetCommTimeouts(st->hComm, &timeouts);
                        
                        // Запускаем фоновый поток чтения
                        st->readThread = new std::thread(_altauri_com_reader_loop, (void*){0}.mPtr);
                    }
                }
            #endif

            // Сохраняем указатель в глобальную карту и проверяем успешность
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
            std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
            auto _cps_it = _com_states_map.find((void*){0}.mPtr);
            if (_cps_it != _com_states_map.end()) {
                ComPortState* st = _cps_it->second;
                
                #ifdef _WIN32
                    // Останавливаем поток
                    st->isRunning = false;
                    if (st->hComm != INVALID_HANDLE_VALUE) {
                        CancelIoEx(st->hComm, NULL);
                        CloseHandle(st->hComm);
                    }
                    if (st->readThread && st->readThread->joinable()) {
                        st->readThread->join();
                    }
                    delete st->readThread;
                #endif
                
                delete st;  // Освобождаем память
                _com_states_map.erase(_cps_it);
            }
        ', this);

        _isOpenFlag = false;
        var outOpen = getOutput("isOpen");
        if (outOpen != null) outOpen.value = false;
    }

    private function sendToDevice(data:String):Void
    {
        untyped __cpp__('
            std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
            auto _cps_it = _com_states_map.find((void*){0}.mPtr);
            if (_cps_it != _com_states_map.end()) {
                ComPortState* st = _cps_it->second;
                #ifdef _WIN32
                    if (st->hComm != INVALID_HANDLE_VALUE) {
                        const char* buffer = {1}.c_str();
                        DWORD bytesToWrite = (DWORD)strlen(buffer);
                        DWORD bytesWritten;
                        WriteFile(st->hComm, buffer, bytesToWrite, &bytesWritten, NULL);
                    }
                #endif
            }
        ', this, data);
    }

    private function setDTRState(state:Bool):Void
    {
        untyped __cpp__('
            std::lock_guard<std::mutex> _cps_lock(_com_map_mutex);
            auto _cps_it = _com_states_map.find((void*){0}.mPtr);
            if (_cps_it != _com_states_map.end()) {
                ComPortState* st = _cps_it->second;
                #ifdef _WIN32
                    if (st->hComm != INVALID_HANDLE_VALUE) {
                        if ({1}) {
                            EscapeCommFunction(st->hComm, SETDTR);
                        } else {
                            EscapeCommFunction(st->hComm, CLRDTR);
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