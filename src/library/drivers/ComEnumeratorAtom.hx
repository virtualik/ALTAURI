#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// НЕ включаем windows.h в header!
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <map>
#include <algorithm>
')

@:cppFileCode('
#ifdef _WIN32
    #define WIN32_LEAN_AND_MEAN
    #define NOGDI
    #include <windows.h>
    #pragma comment(lib, "advapi32.lib")
#endif

struct EnumState {
    std::string currentPorts;
    std::mutex mtx;
    volatile bool isRunning;
    std::thread* worker;
    volatile bool firstScanDone;  // Флаг: первый скан завершён
};

static std::map<void*, EnumState*> _enum_map;
static std::mutex _enum_map_mutex;

static void _altauri_enum_worker(void* haxePtr) {
    EnumState* st = nullptr;
    {
        std::lock_guard<std::mutex> mapLock(_enum_map_mutex);
        auto it = _enum_map.find(haxePtr);
        if (it == _enum_map.end()) return;
        st = it->second;
    }

    st->isRunning = true;
    st->firstScanDone = false;
    std::vector<int> ports;

    while (st->isRunning) {
        ports.clear();
        
        #ifdef _WIN32
        HKEY hKey = NULL;
        LONG regResult = RegOpenKeyExA(
            HKEY_LOCAL_MACHINE,
            "HARDWARE\\DEVICEMAP\\SERIALCOMM",
            0,
            KEY_READ,
            &hKey
        );
        
        if (regResult == ERROR_SUCCESS && hKey != NULL) {
            char valueName[256];
            char valueData[256];
            DWORD valueNameSize, valueDataSize, valueType;
            
            for (DWORD i = 0; ; i++) {
                valueNameSize = sizeof(valueName);
                valueDataSize = sizeof(valueData);
                
                if (RegEnumValueA(hKey, i, valueName, &valueNameSize, NULL, &valueType, (LPBYTE)valueData, &valueDataSize) == ERROR_SUCCESS) {
                    std::string dataStr(valueData);
                    size_t pos = dataStr.find("COM");
                    if (pos != std::string::npos) {
                        int num = atoi(dataStr.substr(pos + 3).c_str());
                        if (num > 0) ports.push_back(num);
                    }
                } else {
                    break;
                }
            }
            RegCloseKey(hKey);
        }
        #endif

        std::sort(ports.begin(), ports.end());
        
        std::string result = "";
        for (int p : ports) {
            if (!result.empty()) result += ",";
            result += "COM" + std::to_string(p);
        }

        {
            std::lock_guard<std::mutex> lock(st->mtx);
            st->currentPorts = result;
        }
        st->firstScanDone = true;

        // Спим 2 секунды (по 100мс с проверкой isRunning)
        for (int w = 0; w < 20 && st->isRunning; w++) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
    st->isRunning = false;
}
')

class ComEnumeratorAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================
    private static inline var POLL_INTERVAL_CHECK:Float = 0.5;

    // =========================================================================
    // СОСТОЯНИЕ
    // =========================================================================
    private var _lastOutputStr:String = "";
    private var _pollTimer:Float = 0.0;
    private var _firstReportDone:Bool = false;  // Первый результат ещё не отправлен

    // =========================================================================
    // КОНСТРУКТОР
    // =========================================================================
    public function new(id:String)
    {
        super(
            [], // Нет входов
            [
                new Contact("", OUTPUT, "ports") // "COM1,COM3,COM5"
            ],
            null, 
            id, 
            "ComEnumeratorAtom", 
            true
        );
        
        init();
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================
    override public function init():Void
    {
        untyped __cpp__('
            EnumState* st = new EnumState();
            st->currentPorts = "";
            st->isRunning = false;
            st->worker = nullptr;
            st->firstScanDone = false;

            {
                std::lock_guard<std::mutex> _ce_lock(_enum_map_mutex);
                _enum_map[(void*){0}.mPtr] = st;
            }

            st->worker = new std::thread(_altauri_enum_worker, (void*){0}.mPtr);
        ', this);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        _pollTimer += dt;
        if (_pollTimer >= POLL_INTERVAL_CHECK)
        {
            _pollTimer = 0.0;

            var cppStr:String = "";
            var scanReady:Bool = false;

            untyped __cpp__('
                EnumState* _ce_stPtr = nullptr;
                {
                    std::lock_guard<std::mutex> _ce_mapLock(_enum_map_mutex);
                    auto _ce_it = _enum_map.find((void*){0}.mPtr);
                    if (_ce_it != _enum_map.end()) {
                        _ce_stPtr = _ce_it->second;
                    }
                }
                if (_ce_stPtr) {
                    std::lock_guard<std::mutex> _ce_dataLock(_ce_stPtr->mtx);
                    cppStr = ::String(_ce_stPtr->currentPorts.c_str());
                    scanReady = _ce_stPtr->firstScanDone;
                }
            ', this);

            // ИСПРАВЛЕНО: Первый результат отправляем ВСЕГДА,
            // даже если это пустая строка "" (нет портов).
            // Последующие — только при изменении.
            if (scanReady && !_firstReportDone)
            {
                _firstReportDone = true;
                _lastOutputStr = cppStr;
                var outPort = getOutput("ports");
                if (outPort != null)
                {
                    outPort.setValueSilent(_lastOutputStr);
                    outPort.propagateCurrentValue();
                }
            }
            else if (scanReady && cppStr != _lastOutputStr)
            {
                _lastOutputStr = cppStr;
                var outPort = getOutput("ports");
                if (outPort != null)
                {
                    outPort.setValueSilent(_lastOutputStr);
                    outPort.propagateCurrentValue();
                }
            }
        }
    }

    override public function dispose():Void
    {
        untyped __cpp__('
            EnumState* st = nullptr;
            {
                std::lock_guard<std::mutex> _ce_lock(_enum_map_mutex);
                auto _ce_it = _enum_map.find((void*){0}.mPtr);
                if (_ce_it != _enum_map.end()) {
                    st = _ce_it->second;
                    _enum_map.erase(_ce_it);
                }
            }
            
            if (st) {
                st->isRunning = false;
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
}
#end
