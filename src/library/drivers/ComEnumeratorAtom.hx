package library.drivers;
#if cpp

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:headerCode('
// DO NOT include windows.h in header!
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
    volatile bool firstScanDone;  // Flag: first scan complete
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

        // Sleep 2 seconds (in 100ms chunks with isRunning check)
        for (int w = 0; w < 20 && st->isRunning; w++) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    st->isRunning = false;
}
')

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     COM ENUMERATOR ATOM v1.0                              ║
 * ║                     (Windows Registry Scanner)                            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Background scanner for available COM ports via Windows Registry.         ║
 * ║  Polls HARDWARE\DEVICEMAP\SERIALCOMM every 2 seconds.                     ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     ComEnumeratorAtom                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  A) COMPUTE MODULE:                                                 │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     Background Thread (C++):                                        │  ║
 * ║  │       1. Open registry key HARDWARE\DEVICEMAP\SERIALCOMM            │  ║
 * ║  │       2. Enumerate all values                                       │  ║
 * ║  │       3. Extract COM port numbers                                   │  ║
 * ║  │       4. Sort and format as "COM1,COM3,COM5"                        │  ║
 * ║  │       5. Write to currentPorts (thread-safe with mutex)             │  ║
 * ║  │       6. Sleep 2 seconds                                            │  ║
 * ║  │                                                                     │  ║
 * ║  │     update(dt) {                                                    │  ║
 * ║  │       1. Poll C++ buffer every 0.5 seconds                          │  ║
 * ║  │       2. If changed → setValueSilent + propagateCurrentValue        │  ║
 * ║  │     }                                                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  B) DATABANK:                                                       │  ║
 * ║  │     ─────────────                                                   │  ║
 * ║  │     _lastOutputStr:String  - Last reported port list                │  ║
 * ║  │     _pollTimer:Float       - Timer for polling interval             │  ║
 * ║  │     _firstReportDone:Bool  - First result sent flag                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  C) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "ports" - Comma-separated list (String, e.g., "COM1,COM3")      │  ║
 * ║  │                                                                     │  ║
 * ║  │  D) FACE (DeviceView):                                              │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     ComEnumeratorWidget for displaying port list                    │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                      THREAD SAFETY                                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Background Thread (C++) ──► currentPorts ──► Main Thread (Haxe)          ║
 * ║                                                                           ║
 * ║  Pattern:                                                                 ║
 * ║  1. Background thread writes to currentPorts with mutex                   ║
 * ║  2. Main thread polls in update() and copies to _lastOutputStr            ║
 * ║  3. Main thread writes to output contact if changed                       ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    APPLICATION                                            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  • Auto-detection of USB-COM adapters                                     ║
 * ║  • Dynamic port list for ComPortWidget                                    ║
 * ║  • Hot-plug support (plug/unplug detection)                               ║
 * ║  • Debug logging of available serial devices                              ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class ComEnumeratorAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    private static inline var POLL_INTERVAL_CHECK:Float = 0.5;

    // =========================================================================
    // STATE
    // =========================================================================
    private var _lastOutputStr:String = "";
    private var _pollTimer:Float = 0.0;
    private var _firstReportDone:Bool = false;  // First result not yet sent

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [], // No inputs
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

            // FIXED: First result is ALWAYS sent,
            // even if it's an empty string "" (no ports).
            // Subsequent results only on change.
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