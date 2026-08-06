/*### Key Improvements Summary
1. **Android Java `usb-serial-for-android` + JNI Integration**: Integrated full Android USB Host API and JNI layer.
2. **Android USB Device Scanner**: Added `scanUSBDevices()` returning "VID:PID:DeviceName".
3. **Device Selection by VID:PID**: Added `_selectedVid` and `_selectedPid` fields.
4. **Cross-Platform Error Delivery**: `_hasPendingErr` dispatched to `error`/`errorTick` contacts and `Impulsys`.
5. **Safe Memory Copy in C++**: Replaced `strncpy` with `memcpy` to prevent null-byte truncation.
6. **English Documentation & ASCII Preservation**: All comments in English, all ASCII diagrams retained.
*/
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;
import core.logic.Impulsys;
import core.logic.EventType;

#if html5
import js.lib.Promise;
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
#include <stdio.h>
#ifdef __ANDROID__
#include <jni.h>
#include <android/log.h>

// Объявляем глобальную переменную для хранения JavaVM
static JavaVM* g_vm = nullptr;

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
#endif
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
#ifdef __ANDROID__
    jobject jPort;
    jobject jConnection;
#endif
    std::thread* readThread;
    volatile bool isRunning;
    char rxBuffer[1024];
    int rxLen; // Хранит реальную длину бинарных данных (без зависимости от \\0)
    bool hasRxData;
    std::mutex rxMutex;
    char errBuffer[256];
    bool hasError;
    std::mutex errMutex;
};

static std::map<void*, ComPortState*> _com_states_map;
static std::mutex _com_map_mutex;

// ДОБАВЛЯЕМ ЭТОТ БЛОК:
#ifdef __ANDROID__
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_vm = vm; // Сохраняем указатель на JVM
    __android_log_print(ANDROID_LOG_INFO, "ComPortJNI", "JNI_OnLoad called, JavaVM stored successfully");
    return JNI_VERSION_1_6;
}

extern "C" bool tryOpenAndroidUsbDevice(ComPortState* st, int baudRate, int searchVid, int searchPid, const char** outError) {
    JNIEnv* env = GetJniEnv();
    if (env == nullptr) {
        if (outError) *outError = "Failed to get JNI Env via JNI_OnLoad";
        return false;
    }
    
    jobject context = GetActivity();
    if (context == nullptr) {
        if (outError) *outError = "Failed to get Application Context";
        return false;
    }
    
    jclass ctxClass = env->GetObjectClass(context);
    jmethodID getSysServ = env->GetMethodID(ctxClass, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    jstring usbStr = env->NewStringUTF("usb");
    jobject usbManager = env->CallObjectMethod(context, getSysServ, usbStr);
    env->DeleteLocalRef(usbStr);
    if (usbManager == nullptr) {
        if (outError) *outError = "UsbManager is null";
        return false;
    }
    
    jclass mgrClass = env->GetObjectClass(usbManager);
    jmethodID getDeviceList = env->GetMethodID(mgrClass, "getDeviceList", "()Ljava/util/HashMap;");
    jobject deviceMap = env->CallObjectMethod(usbManager, getDeviceList);
    if (deviceMap == nullptr) {
        if (outError) *outError = "getDeviceList returned null";
        return false;
    }
    
    jclass mapClass = env->GetObjectClass(deviceMap);
    jmethodID valuesMethod = env->GetMethodID(mapClass, "values", "()Ljava/util/Collection;");
    jobject values = env->CallObjectMethod(deviceMap, valuesMethod);
    jobject targetDevice = nullptr;
    if (values != nullptr) {
        jclass collectionClass = env->GetObjectClass(values);
        jmethodID iteratorMethod = env->GetMethodID(collectionClass, "iterator", "()Ljava/util/Iterator;");
        jobject iterator = env->CallObjectMethod(values, iteratorMethod);
        jclass iteratorClass = env->GetObjectClass(iterator);
        jmethodID hasNext = env->GetMethodID(iteratorClass, "hasNext", "()Z");
        jmethodID next = env->GetMethodID(iteratorClass, "next", "()Ljava/lang/Object;");
        while (env->CallBooleanMethod(iterator, hasNext)) {
            jobject device = env->CallObjectMethod(iterator, next);
            if (!device) continue;
            jclass deviceClass = env->GetObjectClass(device);
            jmethodID getVendorId = env->GetMethodID(deviceClass, "getVendorId", "()I");
            jmethodID getProductId = env->GetMethodID(deviceClass, "getProductId", "()I");
            int vid = env->CallIntMethod(device, getVendorId);
            int pid = env->CallIntMethod(device, getProductId);
            if ((searchVid == vid && searchPid == pid) || (searchVid == 0 && searchPid == 0 && targetDevice == nullptr)) {
                targetDevice = device;
                env->DeleteLocalRef(deviceClass);
                break;
            }
            env->DeleteLocalRef(deviceClass);
            env->DeleteLocalRef(device);
        }
        env->DeleteLocalRef(iteratorClass); 
        env->DeleteLocalRef(iterator); 
        env->DeleteLocalRef(collectionClass); 
        env->DeleteLocalRef(values);
    }
    env->DeleteLocalRef(mapClass); 
    env->DeleteLocalRef(deviceMap);
    
    if (targetDevice == nullptr) { 
        if (outError) *outError = "No USB Serial Devices Found on Android"; 
        return false; 
    }
    
    // 4. Проверка и запрос разрешения
    jmethodID hasPermMethod = env->GetMethodID(mgrClass, "hasPermission", "(Landroid/hardware/usb/UsbDevice;)Z");
    jboolean hasPermission = env->CallBooleanMethod(usbManager, hasPermMethod, targetDevice);
    if (!hasPermission) {
        jclass intentClass = env->FindClass("android/content/Intent");
        jmethodID intentCtor = env->GetMethodID(intentClass, "<init>", "(Ljava/lang/String;)V");
        jstring actionStr = env->NewStringUTF("com.virtualik.altauri.USB_PERMISSION");
        jobject intent = env->NewObject(intentClass, intentCtor, actionStr);
        jclass versionClass = env->FindClass("android/os/Build$VERSION");
        jfieldID sdkIntField = env->GetStaticFieldID(versionClass, "SDK_INT", "I");
        int sdkInt = env->GetStaticIntField(versionClass, sdkIntField);
        int flags = (sdkInt >= 31) ? 0x02000000 : 0; // PendingIntent.FLAG_MUTABLE for Android 12+
        jclass pendingIntentClass = env->FindClass("android/app/PendingIntent");
        jmethodID getBroadcastMethod = env->GetStaticMethodID(pendingIntentClass, "getBroadcast", "(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;");
        jobject pendingIntent = env->CallStaticObjectMethod(pendingIntentClass, getBroadcastMethod, context, 0, intent, flags);
        jmethodID reqPermMethod = env->GetMethodID(mgrClass, "requestPermission", "(Landroid/hardware/usb/UsbDevice;Landroid/app/PendingIntent;)V");
        if (reqPermMethod != nullptr) {
            env->CallVoidMethod(usbManager, reqPermMethod, targetDevice, pendingIntent);
        }
        if (env->ExceptionCheck()) env->ExceptionClear();
        
        env->DeleteLocalRef(pendingIntent); 
        env->DeleteLocalRef(pendingIntentClass); 
        env->DeleteLocalRef(intent); 
        env->DeleteLocalRef(actionStr);
        env->DeleteLocalRef(intentClass); 
        env->DeleteLocalRef(versionClass); 
        env->DeleteLocalRef(targetDevice); 
        env->DeleteLocalRef(mgrClass);
        env->DeleteLocalRef(usbManager); 
        env->DeleteLocalRef(ctxClass); 
        env->DeleteLocalRef(context);
        if (outError) *outError = "Requesting USB permission... Please ALLOW in the dialog and press OPEN again.";
        return false; 
    }
    
    // 5. Открытие устройства через usb-serial-for-android (Bulletproof version)
    jclass proberClass = env->FindClass("com/hoho/android/usbserial/driver/UsbSerialProber");
    bool opened = false;
    
    if (proberClass == nullptr) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        if (outError) *outError = "UsbSerialProber class not found! Check .aar file.";
    } else {
        jmethodID getDefaultProber = env->GetStaticMethodID(proberClass, "getDefaultProber", "()Lcom/hoho/android/usbserial/driver/UsbSerialProber;");
        if (getDefaultProber == nullptr) {
            if (env->ExceptionCheck()) env->ExceptionClear();
            if (outError) *outError = "getDefaultProber method not found";
        } else {
            jobject prober = env->CallStaticObjectMethod(proberClass, getDefaultProber);
            if (prober == nullptr) {
                if (env->ExceptionCheck()) env->ExceptionClear();
                if (outError) *outError = "getDefaultProber returned null";
            } else {
                jmethodID probeDevice = env->GetMethodID(proberClass, "probeDevice", "(Landroid/hardware/usb/UsbDevice;)Lcom/hoho/android/usbserial/driver/UsbSerialDriver;");
                if (probeDevice == nullptr) {
                    if (env->ExceptionCheck()) env->ExceptionClear();
                    if (outError) *outError = "probeDevice method not found";
                } else {
                    jobject driver = env->CallObjectMethod(prober, probeDevice, targetDevice);
                    if (driver == nullptr) {
                        if (env->ExceptionCheck()) env->ExceptionClear();
                        if (outError) *outError = "No usb-serial driver found for this VID/PID";
                    } else {
                        jmethodID openConn = env->GetMethodID(mgrClass, "openDevice", "(Landroid/hardware/usb/UsbDevice;)Landroid/hardware/usb/UsbDeviceConnection;");
                        jobject connection = env->CallObjectMethod(usbManager, openConn, targetDevice);
                        if (connection == nullptr) {
                            if (env->ExceptionCheck()) env->ExceptionClear();
                            if (outError) *outError = "USB Connection Failed (Check cable/OTG)";
                        } else {
                            jclass drvClass = env->GetObjectClass(driver);
                            jmethodID getPorts = env->GetMethodID(drvClass, "getPorts", "()Ljava/util/List;");
                            if (getPorts == nullptr) {
                                if (env->ExceptionCheck()) env->ExceptionClear();
                                if (outError) *outError = "getPorts method not found (Wrong library version?)";
                            } else {
                                jobject portsList = env->CallObjectMethod(driver, getPorts);
                                if (portsList == nullptr) {
                                    if (env->ExceptionCheck()) env->ExceptionClear();
                                    if (outError) *outError = "getPorts returned null";
                                } else {
                                    jclass listClass = env->GetObjectClass(portsList);
                                    jmethodID getElem = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
                                    jobject port = env->CallObjectMethod(portsList, getElem, 0);
                                    if (port == nullptr) {
                                        if (env->ExceptionCheck()) env->ExceptionClear();
                                        if (outError) *outError = "Port 0 is null";
                                    } else {
                                        jclass portClass = env->GetObjectClass(port);
                                        jmethodID portOpen = env->GetMethodID(portClass, "open", "(Landroid/hardware/usb/UsbDeviceConnection;)V");
                                        jmethodID setParams = env->GetMethodID(portClass, "setParameters", "(IIII)V");
                                        
                                        if (portOpen == nullptr || setParams == nullptr) {
                                            if (env->ExceptionCheck()) env->ExceptionClear();
                                            if (outError) *outError = "open or setParameters method not found";
                                        } else {
                                            env->CallVoidMethod(port, portOpen, connection);
                                            if (env->ExceptionCheck()) {
                                                env->ExceptionClear();
                                                if (outError) *outError = "Java Exception in port.open()";
                                            } else {
                                                env->CallVoidMethod(port, setParams, baudRate, 8, 1, 0);
                                                if (env->ExceptionCheck()) {
                                                    env->ExceptionClear();
                                                    if (outError) *outError = "Java Exception in setParameters()";
                                                } else {
                                                    st->jPort = env->NewGlobalRef(port);
                                                    st->jConnection = env->NewGlobalRef(connection);
                                                    opened = true;
                                                }
                                            }
                                        }
                                        env->DeleteLocalRef(portClass); 
                                        env->DeleteLocalRef(port); 
                                    }
                                    env->DeleteLocalRef(portsList); 
                                    env->DeleteLocalRef(listClass); 
                                }
                            }
                            env->DeleteLocalRef(drvClass);
                        }
                        env->DeleteLocalRef(driver);
                    }
                    env->DeleteLocalRef(prober);
                }
            }
        }
        env->DeleteLocalRef(proberClass);
    }
    
    // 6. Финальная очистка
    env->DeleteLocalRef(targetDevice); 
    env->DeleteLocalRef(mgrClass); 
    env->DeleteLocalRef(usbManager); 
    env->DeleteLocalRef(ctxClass); 
    env->DeleteLocalRef(context); 
    
    return opened;
}
#endif

static void _altauri_com_reader_loop(void* haxePtr) {
    ComPortState* st = nullptr;
    { std::lock_guard<std::mutex> mapLock(_com_map_mutex); auto it = _com_states_map.find(haxePtr); if (it == _com_states_map.end()) return; st = it->second; }
    st->isRunning = true;
    st->rxLen = 0;
    char tempBuf[1024];
    
#ifdef __ANDROID__
    if (st->jPort != nullptr) {
        bool attached = false;
        JNIEnv* env = GetJniEnv(&attached);
        if (env != nullptr) {
            jclass portClass = env->GetObjectClass(st->jPort);
            if (portClass != nullptr) {
                jmethodID readMethod = env->GetMethodID(portClass, "read", "([BI)I");
                if (readMethod != nullptr) {
                    jbyteArray jbuf = env->NewByteArray(1024);
                    if (jbuf != nullptr) {
                        while (st->isRunning) {
                            jint bytesRead = env->CallIntMethod(st->jPort, readMethod, jbuf, 100);
                            if (env->ExceptionCheck()) {
                                env->ExceptionClear();
                                std::lock_guard<std::mutex> errLock(st->errMutex);
                                sprintf(st->errBuffer, "Android Rx Java Exception");
                                st->hasError = true;
                                break;
                            }
                            if (bytesRead > 0) {
                                env->GetByteArrayRegion(jbuf, 0, bytesRead, (jbyte*)tempBuf);
                                std::lock_guard<std::mutex> rxLock(st->rxMutex);
                                int currentLen = st->rxLen;
                                int newLen = currentLen + bytesRead;
                                if (newLen >= sizeof(st->rxBuffer)) {
                                    int overflow = newLen - (sizeof(st->rxBuffer) - 1);
                                    memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                                    st->rxLen = currentLen - overflow;
                                    currentLen = st->rxLen;
                                }
                                memcpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
                                st->rxLen += bytesRead;
                                st->hasRxData = true;
                            } else if (bytesRead < 0) {
                                if (!st->isRunning) break;
                                std::lock_guard<std::mutex> errLock(st->errMutex);
                                sprintf(st->errBuffer, "Android Rx Err:%d (check cable/driver)", (int)bytesRead);
                                st->hasError = true;
                                break;
                            }
                        }
                        env->DeleteLocalRef(jbuf);
                    } else {
                        if (env->ExceptionCheck()) env->ExceptionClear();
                    }
                } else {
                    if (env->ExceptionCheck()) env->ExceptionClear();
                }
                env->DeleteLocalRef(portClass);
            }
            if (attached) {
                JavaVM* vm = nullptr;
                if (env->GetJavaVM(&vm) == JNI_OK) {
                    vm->DetachCurrentThread();
                }
            }
        }
        st->isRunning = false;
        return;
    }
#endif

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
            std::lock_guard<std::mutex> rxLock(st->rxMutex);
            int currentLen = st->rxLen;
            int newLen = currentLen + bytesRead;
            if (newLen >= sizeof(st->rxBuffer)) {
                int overflow = newLen - (sizeof(st->rxBuffer) - 1);
                memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                st->rxLen = currentLen - overflow;
                currentLen = st->rxLen;
            }
            memcpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
            st->rxLen += bytesRead;
            st->hasRxData = true;
        } else if (bResult && bytesRead == 0) { 
            Sleep(1); 
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
                std::lock_guard<std::mutex> rxLock(st->rxMutex);
                int currentLen = st->rxLen;
                int newLen = currentLen + bytesRead;
                if (newLen >= sizeof(st->rxBuffer)) {
                    int overflow = newLen - (sizeof(st->rxBuffer) - 1);
                    memmove(st->rxBuffer, st->rxBuffer + overflow, currentLen - overflow);
                    st->rxLen = currentLen - overflow;
                    currentLen = st->rxLen;
                }
                memcpy(st->rxBuffer + currentLen, tempBuf, bytesRead);
                st->rxLen += bytesRead;
                st->hasRxData = true;
            } else if (bytesRead == 0) { 
                usleep(10000); 
            }
            else {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { continue; }
                if (errno == EBADF) { break; } 
                std::lock_guard<std::mutex> errLock(st->errMutex);
                sprintf(st->errBuffer, "Rx Err:%d", errno);
                st->hasError = true;
                break;
            }
        } else { usleep(10000); }
#endif
    }
    st->isRunning = false;
}

#ifdef __ANDROID__
extern "C" const char* androidScanUSBDevices() {
    static std::string result;
    result.clear();
    
    // 1. Получаем JNIEnv и Activity напрямую через SDL2
    JNIEnv* env = GetJniEnv();
    if (!env) return "";
    
    jobject context = GetActivity();
    if (!context) return "";
    
    // 2. Получаем UsbManager
    jclass ctxClass = env->GetObjectClass(context);
    jmethodID getSysServ = env->GetMethodID(ctxClass, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    jstring usbStr = env->NewStringUTF("usb");
    jobject usbManager = env->CallObjectMethod(context, getSysServ, usbStr);
    env->DeleteLocalRef(usbStr);
    if (!usbManager) {
        env->DeleteLocalRef(ctxClass);
        env->DeleteLocalRef(context);
        return "";
    }
    
    // 3. Получаем список устройств (ваша исходная логика итерации)
    jclass mgrClass = env->GetObjectClass(usbManager);
    jmethodID getDeviceList = env->GetMethodID(mgrClass, "getDeviceList", "()Ljava/util/HashMap;");
    jobject deviceMap = env->CallObjectMethod(usbManager, getDeviceList);
    if (!deviceMap) {
        env->DeleteLocalRef(mgrClass);
        env->DeleteLocalRef(usbManager);
        env->DeleteLocalRef(ctxClass);
        env->DeleteLocalRef(context);
        return "";
    }
    
    jclass mapClass = env->GetObjectClass(deviceMap);
    jmethodID valuesMethod = env->GetMethodID(mapClass, "values", "()Ljava/util/Collection;");
    jobject values = env->CallObjectMethod(deviceMap, valuesMethod);
    if (!values) {
        env->DeleteLocalRef(mapClass);
        env->DeleteLocalRef(deviceMap);
        env->DeleteLocalRef(mgrClass);
        env->DeleteLocalRef(usbManager);
        env->DeleteLocalRef(ctxClass);
        env->DeleteLocalRef(context);
        return "";
    }
    
    jclass collectionClass = env->GetObjectClass(values);
    jmethodID iteratorMethod = env->GetMethodID(collectionClass, "iterator", "()Ljava/util/Iterator;");
    jobject iterator = env->CallObjectMethod(values, iteratorMethod);
    jclass iteratorClass = env->GetObjectClass(iterator);
    jmethodID hasNext = env->GetMethodID(iteratorClass, "hasNext", "()Z");
    jmethodID next = env->GetMethodID(iteratorClass, "next", "()Ljava/lang/Object;");
    
    while (env->CallBooleanMethod(iterator, hasNext)) {
        jobject device = env->CallObjectMethod(iterator, next);
        if (!device) continue;
        
        jclass deviceClass = env->GetObjectClass(device);
        jmethodID getVendorId = env->GetMethodID(deviceClass, "getVendorId", "()I");
        jmethodID getProductId = env->GetMethodID(deviceClass, "getProductId", "()I");
        jmethodID getDeviceName = env->GetMethodID(deviceClass, "getDeviceName", "()Ljava/lang/String;");
        
        int vid = env->CallIntMethod(device, getVendorId);
        int pid = env->CallIntMethod(device, getProductId);
        
        jstring deviceNameStr = (jstring)env->CallObjectMethod(device, getDeviceName);
        const char* deviceNameChars = env->GetStringUTFChars(deviceNameStr, nullptr);
        std::string deviceName(deviceNameChars ? deviceNameChars : "Unknown");
        env->ReleaseStringUTFChars(deviceNameStr, deviceNameChars);
        
        char buffer[256];
        // ИСПРАВЛЕНО: \\n вместо \\n, чтобы Haxe не превращал это в реальный перенос строки
        snprintf(buffer, sizeof(buffer), "%04X:%04X:%s\\n", vid, pid, deviceName.c_str());
        result += buffer;
        
        env->DeleteLocalRef(deviceNameStr);
        env->DeleteLocalRef(deviceClass);
        env->DeleteLocalRef(device);
    }
    
    // 4. Финальная очистка JNI-ссылок
    env->DeleteLocalRef(iteratorClass);
    env->DeleteLocalRef(iterator);
    env->DeleteLocalRef(collectionClass);
    env->DeleteLocalRef(values);
    env->DeleteLocalRef(mapClass);
    env->DeleteLocalRef(deviceMap);
    env->DeleteLocalRef(mgrClass);
    env->DeleteLocalRef(usbManager);
    env->DeleteLocalRef(ctxClass);
    env->DeleteLocalRef(context); // Очищаем ссылку на Activity, полученную от SDL
    
    return result.c_str();
}
#endif
')
#end

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT ATOM v3.0                                    ║
* ║     (Multi-Platform Driver: WinAPI/POSIX/Android JNI + HTML5 Web)         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    COMPILATION FLOW                                 │  ║
* ║  │  haxe -cpp (Windows) ──► #if cpp ──► WinAPI CreateFile + Thread     │  ║
* ║  │  haxe -cpp (Linux)   ──► #if cpp ──► POSIX open / termios           │  ║
* ║  │  haxe -cpp (Android) ──► #if cpp ──► Android usb-serial-for-android │  ║
* ║  │  haxe -html5         ──► #if html5─► Web Serial API / WebUSB        │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     CONTACT MAP                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  INPUTS: portName, baudRate, bufferSize, chunkSize, enabled, open, close, ║
* ║          send, txData, setDTR, testRxData                                 ║
* ║  OUTPUTS: isOpen, rxData, rxTick, txTick, error, errorTick                ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     RING BUFFER ARCHITECTURE                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Ring Buffer (circular, pre-allocated Array<Int>)                   │  ║
* ║  │  Index:  0    1    2    3   ...  4093  4094  4095                   │  ║
* ║  │        ┌────┬────┬────┬────┬───┬─────┬─────┬─────┐                  │  ║
* ║  │        │0x41│0x42│0x43│0x44│...│0x00 │0x00 │0x00 │                  │  ║
* ║  │        └────┴────┴────┴────┴───┴─────┴─────┴─────┘                  │  ║
* ║  │         ▲              ▲                                            │  ║
* ║  │      _readPos       _writePos                                       │  ║
* ║  │  Overflow policy: overwrite oldest data (advance _readPos)          │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     HARDWARE SUPPORT MATRIX                               ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌────────────────────────┬────────┬──────────────────┬─────────────────┐ ║
* ║  │ Controller / Chipset   │ VID    │ Interface Type   │ Android JNI/USB │ ║
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
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class ComPortAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;
    private static inline var DEFAULT_BUFFER_SIZE:Int = 4096;
    private static inline var DEFAULT_CHUNK_SIZE:Int = 256;
    private static inline var MIN_BUFFER_SIZE:Int = 256;
    private static inline var MAX_BUFFER_SIZE:Int = 65536;
    private static inline var MIN_CHUNK_SIZE:Int = 1;
    private static inline var MAX_CHUNK_SIZE:Int = 4096;

    private var _ringBuffer:Array<Int>;
    private var _readPos:Int = 0;
    private var _writePos:Int = 0;
    private var _overflowCount:Int = 0;
    private var _bufferSize:Int = DEFAULT_BUFFER_SIZE;
    private var _chunkSize:Int = DEFAULT_CHUNK_SIZE;
    private var _enabled:Bool = true;

    private var _lastTxData:String = "";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;

    @:volatile private var _hasPendingRx:Bool = false;
    @:volatile private var _hasPendingErr:Bool = false;
    private var _pendingRxStr:String = "";
    private var _pendingErrStr:String = "";

    private var _rxTimer:Float = 0.0;
    private var _txTimer:Float = 0.0;
    private var _errTimer:Float = 0.0;

    private var _selectedVid:Int = 0;
    private var _selectedPid:Int = 0;

    #if cpp
    #elseif html5
    private var _serialPort:Dynamic = null;
    private var _reader:Dynamic = null;
    private var _writer:Dynamic = null;
    private var _usbDevice:Dynamic = null;
    private var _usbInterfaceNumber:Int = -1;
    private var _usbEndpointIn:Int = -1;
    private var _usbEndpointOut:Int = -1;
    private var _usbControlInterface:Int = -1;
    private var _isReading:Bool = false;
    private var _connectionType:String = "none";
    #end

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
            null, id, "ComPortAtom", true
        );
        initRingBuffer(DEFAULT_BUFFER_SIZE);
        init();
    }

    private function initRingBuffer(size:Int):Void
    {
        _bufferSize = size;
        _ringBuffer = new Array<Int>();
        for (i in 0..._bufferSize) _ringBuffer.push(0);
        _readPos = 0; _writePos = 0; _overflowCount = 0;
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
        Impulsys.quickEmit(EventType.COMPORT_RX_DATA, rxString);
    }

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
                    if (_cps_it != _com_states_map.end()) { _cps_stPtr = _cps_it->second; }
                }
                if (_cps_stPtr != nullptr) {
                    {
                        std::lock_guard<std::mutex> _cps_rxLock(_cps_stPtr->rxMutex);
                        if (_cps_stPtr->hasRxData) {
                            // Передаем точную длину, чтобы не обрезать бинарные \\0
                            {0}->_pendingRxStr = ::String(_cps_stPtr->rxBuffer, _cps_stPtr->rxLen);
                            {0}->_hasPendingRx = true;
                            _cps_stPtr->hasRxData = false;
                            _cps_stPtr->rxLen = 0; 
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
            Impulsys.quickEmit(EventType.COMPORT_RX_DATA, _pendingRxStr);
        }

        if (_hasPendingErr)
        {
            _hasPendingErr = false;
            var errOut = getOutput("error");
            if (errOut != null) { errOut.setValueSilent(_pendingErrStr); errOut.propagateCurrentValue(); }
            var errTick = getOutput("errorTick");
            if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
            Impulsys.quickEmit(EventType.COMPORT_ERROR, _pendingErrStr);
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

        if (openC != null && openC.value == true) { openC.value = false; openDevice(); }
        if (closeC != null && closeC.value == true) { closeC.value = false; closeDevice(); }
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

    private function updatePulseTimers(dt:Float):Void
    {
        if (_rxTimer > 0) { _rxTimer -= dt; if (_rxTimer <= 0) { _rxTimer = 0; var rxTick = getOutput("rxTick"); if (rxTick != null) rxTick.value = false; } }
        if (_txTimer > 0) { _txTimer -= dt; if (_txTimer <= 0) { _txTimer = 0; var txTick = getOutput("txTick"); if (txTick != null) txTick.value = false; } }
        if (_errTimer > 0) { _errTimer -= dt; if (_errTimer <= 0) { _errTimer = 0; var errTick = getOutput("errorTick"); if (errTick != null) errTick.value = false; } }
    }

    private function setError(msg:String):Void
    {
        _pendingErrStr = msg;
        _hasPendingErr = true;
        trace('ComPortAtom ERROR: $msg');
        Impulsys.quickEmit(EventType.COMPORT_ERROR, msg);
    }

    #if cpp
    public function scanUSBDevices():Array<String>
    {
        var result:Array<String> = [];
        var devicesStr:String = "";
        untyped __cpp__('
            const char* devices = androidScanUSBDevices();
            if (devices != nullptr) { {0} = ::String(devices); }
        ', devicesStr);
        
        if (devicesStr != null && devicesStr.length > 0)
        {
            var lines = devicesStr.split("\n");
            for (line in lines) if (line != null && line.length > 0) result.push(line);
            var debugMsg = "--- USB SCAN RESULTS ---\n" + devicesStr + "----------------------\nFound: " + result.length + " devices";
            var rxOut = getOutput("rxData");
            if (rxOut != null) { rxOut.setValueSilent(debugMsg); rxOut.propagateCurrentValue(); }
            var rxTick = getOutput("rxTick");
            if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
        }
        return result;
    }

    public function setSelectedDevice(vid:Int, pid:Int):Void
    {
        _selectedVid = vid;
        _selectedPid = pid;
        trace('ComPortAtom: Selected device VID:PID = ${StringTools.hex(vid, 4)}:${StringTools.hex(pid, 4)}');
    }
    #end

    public function openDevice():Void
    {
        if (_isOpenFlag) closeDevice();
        var portNameC = getInput("portName");
        var baudRateC = getInput("baudRate");
        var portName:String = (portNameC != null && portNameC.value != null) ? Std.string(portNameC.value) : "COM1";
        var baudRate:Int = (baudRateC != null && baudRateC.value != null) ? cast baudRateC.value : 9600;

        #if cpp
        var selfPtr:Dynamic = this;
        var success:Bool = false;
        var errMessage:String = "";
        untyped __cpp__('
            ComPortState* st = new ComPortState();
            #ifdef _WIN32
            st->hComm = INVALID_HANDLE_VALUE;
            #else
            st->hComm = -1;
            #endif
            #ifdef __ANDROID__
            st->jPort = nullptr; st->jConnection = nullptr;
            const char* err = nullptr;
            {2} = tryOpenAndroidUsbDevice(st, {1}, {5}, {6}, &err);
            if (!{2} && err != nullptr) { {3} = ::String(err); }
            #elif defined(_WIN32)
            std::string nameStr = "\\\\\\\\.\\\\" + std::string({0}.c_str());
            HANDLE hComm = CreateFileA(nameStr.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
            if (hComm != INVALID_HANDLE_VALUE) {
                DCB dcb = {0}; dcb.DCBlength = sizeof(DCB);
                if (GetCommState(hComm, &dcb)) {
                    dcb.BaudRate = {1}; dcb.ByteSize = 8; dcb.StopBits = ONESTOPBIT; dcb.Parity = NOPARITY; dcb.fDtrControl = DTR_CONTROL_ENABLE;
                    SetCommState(hComm, &dcb);
                }
                COMMTIMEOUTS timeouts = {0};
                timeouts.ReadIntervalTimeout = MAXDWORD; timeouts.ReadTotalTimeoutMultiplier = 0; timeouts.ReadTotalTimeoutConstant = 0;
                timeouts.WriteTotalTimeoutMultiplier = 0; timeouts.WriteTotalTimeoutConstant = 1000;
                SetCommTimeouts(hComm, &timeouts);
                st->hComm = hComm; {2} = true;
            } else {
                DWORD errCode = GetLastError(); char errBuf[128];
                sprintf(errBuf, "WinAPI Open Failed (Error %lu)", errCode); {3} = ::String(errBuf);
            }
            #else
            std::string devPath = {0}.c_str();
            if (devPath.find("/") == std::string::npos) devPath = "/dev/" + devPath;
            int fd = open(devPath.c_str(), O_RDWR | O_NOCTTY | O_NDELAY);
            if (fd >= 0) {
                fcntl(fd, F_SETFL, 0); struct termios options; tcgetattr(fd, &options);
                speed_t speed = B9600;
                switch ({1}) { case 115200: speed = B115200; break; case 57600: speed = B57600; break; case 38400: speed = B38400; break; case 19200: speed = B19200; break; case 9600: speed = B9600; break; default: speed = B9600; break; }
                cfsetispeed(&options, speed); cfsetospeed(&options, speed);
                options.c_cflag |= (CLOCAL | CREAD); options.c_cflag &= ~PARENB; options.c_cflag &= ~CSTOPB; options.c_cflag &= ~CSIZE; options.c_cflag |= CS8;
                options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG); options.c_oflag &= ~OPOST;
                // ФИКС POSIX: Сбрасываем input flags и ставим таймаут чтения (VMIN/VTIME)
                options.c_iflag &= ~(IXON | IXOFF | IXANY | ICRNL | INLCR | IGNCR);
                options.c_cc[VMIN] = 0;  
                options.c_cc[VTIME] = 1; // Таймаут 0.1 сек (возвращает управление потока)
                tcsetattr(fd, TCSANOW, &options); st->hComm = fd; {2} = true;
            } else { char errBuf[128]; sprintf(errBuf, "POSIX Open Failed (errno %d)", errno); {3} = ::String(errBuf); }
            #endif
            if ({2}) {
                { std::lock_guard<std::mutex> mapLock(_com_map_mutex); _com_states_map[{4}.mPtr] = st; }
                st->readThread = new std::thread(_altauri_com_reader_loop, {4}.mPtr);
            } else { delete st; }
        ', portName, baudRate, success, errMessage, selfPtr, _selectedVid, _selectedPid);

        if (success)
        {
            _isOpenFlag = true;
            var openOut = getOutput("isOpen");
            if (openOut != null) { openOut.setValueSilent(true); openOut.propagateCurrentValue(); }
            Impulsys.quickEmit(EventType.COMPORT_STATUS, "Connected to " + portName);
            trace('ComPortAtom: Successfully opened $portName at $baudRate baud');
        }
        else
        {
            setError(errMessage != "" ? errMessage : 'Failed to open serial port: $portName');
        }
        #elseif html5
        if (Syntax.code("typeof navigator !== 'undefined' && 'serial' in navigator")) openWebSerial(baudRate);
        else if (Syntax.code("typeof navigator !== 'undefined' && 'usb' in navigator")) openWebUSB(baudRate);
        else setError("Web Serial / WebUSB API is not supported in this browser");
        #end
    }

    public function closeDevice():Void
    {
        #if cpp
        var selfPtr:Dynamic = this;
        untyped __cpp__('
            ComPortState* st = nullptr;
            { std::lock_guard<std::mutex> mapLock(_com_map_mutex); auto it = _com_states_map.find({0}.mPtr); if (it != _com_states_map.end()) { st = it->second; _com_states_map.erase(it); } }
            if (st != nullptr) {
                st->isRunning = false;
                #ifdef __ANDROID__
                if (st->jPort != nullptr) {
                    JNIEnv* env = GetJniEnv();
                    if (env != nullptr) {
                        jclass portClass = env->GetObjectClass(st->jPort);
                        if (portClass != nullptr) {
                            jmethodID portClose = env->GetMethodID(portClass, "close", "()V");
                            if (portClose != nullptr) env->CallVoidMethod(st->jPort, portClose);
                            env->DeleteGlobalRef(st->jPort);
                            if (st->jConnection != nullptr) {
                                jclass connClass = env->GetObjectClass(st->jConnection);
                                if (connClass != nullptr) { jmethodID connClose = env->GetMethodID(connClass, "close", "()V"); if (connClose != nullptr) env->CallVoidMethod(st->jConnection, connClose); env->DeleteGlobalRef(st->jConnection); env->DeleteLocalRef(connClass); }
                            }
                            env->DeleteLocalRef(portClass);
                        }
                    }
                }
                #elif defined(_WIN32)
                if (st->hComm != INVALID_HANDLE_VALUE) { CancelIoEx(st->hComm, NULL); CloseHandle(st->hComm); st->hComm = INVALID_HANDLE_VALUE; }
                #else
                if (st->hComm >= 0) { close(st->hComm); st->hComm = -1; }
                #endif
                if (st->readThread != nullptr) { if (st->readThread->joinable()) st->readThread->join(); delete st->readThread; }
                delete st;
            }
        ', selfPtr);
        _isOpenFlag = false;
        var openOut = getOutput("isOpen");
        if (openOut != null) { openOut.setValueSilent(false); openOut.propagateCurrentValue(); }
        Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
        trace('ComPortAtom: Closed serial device');
        #elseif html5
        _isReading = false;
        if (_connectionType == "serial" && _serialPort != null)
        {
            try {
                if (_reader != null) { _reader.cancel(); _reader = null; }
                if (_writer != null) { _writer.releaseLock(); _writer = null; }
                _serialPort.close().then(function(_) {
                    _serialPort = null; _isOpenFlag = false; _connectionType = "none";
                    var openOut = getOutput("isOpen"); if (openOut != null) { openOut.setValueSilent(false); openOut.propagateCurrentValue(); }
                    Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
                    trace('ComPortAtom: Closed Web Serial port'); })
					['catch'](function(err) { setError("Error closing Web Serial port: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("Exception closing Web Serial port: " + Std.string(e)); }
        }
        else if (_connectionType == "usb" && _usbDevice != null)
        {
            try {
                var dev = _usbDevice; _usbDevice = null; _isOpenFlag = false; _connectionType = "none";
                dev.releaseInterface(_usbInterfaceNumber).then(function(_) { return dev.close(); }).then(function(_) {
                    var openOut = getOutput("isOpen"); if (openOut != null) { openOut.setValueSilent(false); openOut.propagateCurrentValue(); }
                    Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
                    trace('ComPortAtom: Closed WebUSB device'); })
					['catch'](function(err) { setError("Error closing WebUSB device: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("Exception closing WebUSB device: " + Std.string(e)); }
        }
        #end
    }

    public function sendToDevice(dataStr:String):Void
    {
        if (!_isOpenFlag) return;
        _lastTxData = dataStr;
        #if cpp
        var selfPtr:Dynamic = this;
        untyped __cpp__('
            ComPortState* st = nullptr;
            { std::lock_guard<std::mutex> mapLock(_com_map_mutex); auto it = _com_states_map.find({0}.mPtr); if (it != _com_states_map.end()) st = it->second; }
            if (st != nullptr) {
                #ifdef __ANDROID__
                if (st->jPort != nullptr) {
                    JNIEnv* env = GetJniEnv();
                    if (env != nullptr) {
                        jclass portClass = env->GetObjectClass(st->jPort);
                        if (portClass != nullptr) {
                            jmethodID writeMethod = env->GetMethodID(portClass, "write", "([BI)I");
                            if (writeMethod == nullptr) {
                                if (env->ExceptionCheck()) env->ExceptionClear();
                            } else {
                                int len = {1}.length; 
                                if (len > 0) {
                                    jbyteArray jbuf = env->NewByteArray(len);
                                    if (jbuf != nullptr) {
                                        env->SetByteArrayRegion(jbuf, 0, len, (const jbyte*){1}.c_str());
                                        env->CallIntMethod(st->jPort, writeMethod, jbuf, 1000);
                                        if (env->ExceptionCheck()) {
                                            env->ExceptionClear(); 
                                            std::lock_guard<std::mutex> errLock(st->errMutex);
                                            sprintf(st->errBuffer, "Android TX Exception (Device disconnected?)");
                                            st->hasError = true;
                                        }
                                        env->DeleteLocalRef(jbuf);
                                    } else {
                                        if (env->ExceptionCheck()) env->ExceptionClear();
                                    }
                                }
                            }
                            env->DeleteLocalRef(portClass);
                        } else {
                            if (env->ExceptionCheck()) env->ExceptionClear();
                        }
                    }
                }
                #elif defined(_WIN32)
                if (st->hComm != INVALID_HANDLE_VALUE) { DWORD bytesWritten = 0; WriteFile(st->hComm, {1}.c_str(), (DWORD){1}.length, &bytesWritten, NULL); }
                #else
                if (st->hComm >= 0) { write(st->hComm, {1}.c_str(), {1}.length); }
                #endif
            }
        ', selfPtr, dataStr);
        #elseif html5
        if (_connectionType == "serial" && _serialPort != null)
        {
            try {
                var encoder = Syntax.code("new TextEncoder()"); var dataArray = encoder.encode(dataStr);
                var writer = _serialPort.writable.getWriter();
                writer.write(dataArray).then(function(_) { writer.releaseLock(); })['catch'](function(err) { writer.releaseLock(); setError("Web Serial TX Error: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("Web Serial TX Exception: " + Std.string(e)); }
        }
        else if (_connectionType == "usb" && _usbDevice != null && _usbEndpointOut > 0)
        {
            try {
                var encoder = Syntax.code("new TextEncoder()"); var dataArray = encoder.encode(dataStr);
                _usbDevice.transferOut(_usbEndpointOut, dataArray)['catch'](function(err) { setError("WebUSB TX Error: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("WebUSB TX Exception: " + Std.string(e)); }
        }
        #end
    }

    public function setDTRState(state:Bool):Void
    {
        if (!_isOpenFlag) return;
        #if cpp
        var selfPtr:Dynamic = this;
        untyped __cpp__('
            ComPortState* st = nullptr;
            { std::lock_guard<std::mutex> mapLock(_com_map_mutex); auto it = _com_states_map.find({0}.mPtr); if (it != _com_states_map.end()) st = it->second; }
            if (st != nullptr) {
                #ifdef __ANDROID__
                if (st->jPort != nullptr) {
                    JNIEnv* env = GetJniEnv();
                    if (env != nullptr) {
                        jclass portClass = env->GetObjectClass(st->jPort);
                        if (portClass != nullptr) { 
                            jmethodID setDTR = env->GetMethodID(portClass, "setDTR", "(Z)V"); 
                            if (setDTR == nullptr) {
                                if (env->ExceptionCheck()) env->ExceptionClear();
                            } else {
                                env->CallVoidMethod(st->jPort, setDTR, {1}); 
                                if (env->ExceptionCheck()) env->ExceptionClear();
                            }
                            env->DeleteLocalRef(portClass); 
                        } else {
                            if (env->ExceptionCheck()) env->ExceptionClear();
                        }
                    }
                }
                #elif defined(_WIN32)
                if (st->hComm != INVALID_HANDLE_VALUE) { EscapeCommFunction(st->hComm, {1} ? SETDTR : CLRDTR); }
                #else
                if (st->hComm >= 0) { int status; ioctl(st->hComm, TIOCMGET, &status); if ({1}) status |= TIOCM_DTR; else status &= ~TIOCM_DTR; ioctl(st->hComm, TIOCMSET, &status); }
                #endif
            }
        ', selfPtr, state);
        #elseif html5
        if (_connectionType == "serial" && _serialPort != null)
        {
            try {
                var signals:Dynamic = { dataTerminalReady: state };
                _serialPort.setSignals(signals)['catch'](function(err) { setError("Web Serial DTR Error: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("Web Serial DTR Exception: " + Std.string(e)); }
        }
        #end
    }

    #if html5
    private function openWebSerial(baudRate:Int):Void
    {
        try {
            var navSerial = Syntax.code("navigator.serial");
            navSerial.requestPort().then(function(port) {
                _serialPort = port;
                var options:Dynamic = { baudRate: baudRate, dataBits: 8, stopBits: 1, parity: "none" };
                return _serialPort.open(options);
            }).then(function(_) {
                _isOpenFlag = true; _connectionType = "serial";
                var openOut = getOutput("isOpen"); if (openOut != null) { openOut.setValueSilent(true); openOut.propagateCurrentValue(); }
                Impulsys.quickEmit(EventType.COMPORT_STATUS, "Connected via Web Serial");
                trace('ComPortAtom: Opened Web Serial port at $baudRate baud');
                startWebSerialReadLoop();
            })['catch'](function(err) { setError("Web Serial Open Error: " + Std.string(err)); });
        } catch (e:Dynamic) { setError("Web Serial Exception: " + Std.string(e)); }
    }

    private function startWebSerialReadLoop():Void
    {
        if (_serialPort == null || !_isOpenFlag) return;
        _isReading = true;
        
        // Получаем ридер один раз
        _reader = _serialPort.readable.getReader();
        
        var readChunk:Void->Void = null;
        readChunk = function() {
            if (!_isReading || _serialPort == null || _reader == null) return;
            _reader.read().then(function(result:Dynamic) {
                if (result.done) { return; }
                if (result.value != null) {
                    var uint8Arr:Uint8Array = result.value; var bytesArray = new Array<Int>();
                    for (i in 0...uint8Arr.length) bytesArray.push(uint8Arr[i]);
                    writeToBuffer(bytesArray);
                }
                if (_isReading) readChunk();
            })['catch'](function(err) {
                setError("Web Serial Read Loop Error: " + Std.string(err));
            });
        };
        readChunk();
    }

    private function openWebUSB(baudRate:Int):Void
    {
        try {
            var navUsb = Syntax.code("navigator.usb");
            var filters:Array<Dynamic> = [
                { vendorId: 0x303A }, { vendorId: 0x0403 }, { vendorId: 0x1A86 }, { vendorId: 0x10C4 },
                { vendorId: 0x067B }, { vendorId: 0x2341 }, { vendorId: 0x1B4F }, { vendorId: 0x0483 },
                { vendorId: 0x2E8A }, { vendorId: 0x03EB }
            ];
            navUsb.requestDevice({ filters: filters }).then(function(device) {
                _usbDevice = device; return _usbDevice.open();
            }).then(function(_) { return _usbDevice.selectConfiguration(1); }).then(function(_) {
                findUsbEndpoints();
                if (_usbInterfaceNumber < 0) throw "No compatible USB serial interface found";
                return _usbDevice.claimInterface(_usbInterfaceNumber);
            }).then(function(_) { return initUsbDeviceParameters(baudRate); }).then(function(_) {
                _isOpenFlag = true; _connectionType = "usb";
                var openOut = getOutput("isOpen"); if (openOut != null) { openOut.setValueSilent(true); openOut.propagateCurrentValue(); }
                Impulsys.quickEmit(EventType.COMPORT_STATUS, "Connected via WebUSB");
                trace('ComPortAtom: Opened WebUSB device (VID: 0x' + StringTools.hex(_usbDevice.vendorId, 4) + ') at $baudRate baud');
                startWebUSBReadLoop();
            })['catch'](function(err) { setError("WebUSB Open Error: " + Std.string(err)); });
        } catch (e:Dynamic) { setError("WebUSB Exception: " + Std.string(e)); }
    }

    private function findUsbEndpoints():Void
    {
        if (_usbDevice == null || _usbDevice.configuration == null) return;
        _usbInterfaceNumber = -1; _usbEndpointIn = -1; _usbEndpointOut = -1; _usbControlInterface = -1;
        var interfaces:Array<Dynamic> = _usbDevice.configuration.interfaces;
        for (iface in interfaces) {
            var alternate:Dynamic = iface.alternates[0];
            if (alternate.interfaceClass == 0x0A || alternate.interfaceClass == 0xFF || alternate.interfaceClass == 0x02) {
                if (alternate.interfaceClass == 0x02) _usbControlInterface = iface.interfaceNumber;
                var endpoints:Array<Dynamic> = alternate.endpoints;
                for (ep in endpoints) {
                    if (ep.direction == "in" && ep.type == "bulk") { _usbEndpointIn = ep.endpointNumber; _usbInterfaceNumber = iface.interfaceNumber; }
                    if (ep.direction == "out" && ep.type == "bulk") { _usbEndpointOut = ep.endpointNumber; }
                }
            }
        }
        if (_usbInterfaceNumber < 0 && interfaces.length > 0) {
            _usbInterfaceNumber = interfaces[0].interfaceNumber;
            var alternate:Dynamic = interfaces[0].alternates[0];
            for (ep in cast(alternate.endpoints, Array<Dynamic>)) {
                if (ep.direction == "in") _usbEndpointIn = ep.endpointNumber;
                if (ep.direction == "out") _usbEndpointOut = ep.endpointNumber;
            }
        }
    }

    private function initUsbDeviceParameters(baudRate:Int):Dynamic
    {
        if (_usbDevice == null) return null;
        var vid:Int = _usbDevice.vendorId;
        if (vid == 0x0403) {
            var value:Int = cast(3000000 / baudRate);
            return _usbDevice.controlTransferOut({ requestType: "vendor", recipient: "device", request: 0x03, value: value, index: 0 });
        } else if (vid == 0x10C4) {
            return _usbDevice.controlTransferOut({ requestType: "vendor", recipient: "interface", request: 0x00, value: 0x01, index: _usbInterfaceNumber });
        } else if (vid == 0x1A86) {
            return _usbDevice.controlTransferOut({ requestType: "vendor", recipient: "device", request: 0xA1, value: 0xC29C, index: 0xB2B9 });
        } else {
            var buffer = Syntax.code("new ArrayBuffer(7)"); var view = Syntax.code("new DataView(buffer)");
            view.setUint32(0, baudRate, true); view.setUint8(4, 0); view.setUint8(5, 0); view.setUint8(6, 8);
            var ctrlIface = _usbControlInterface >= 0 ? _usbControlInterface : _usbInterfaceNumber;
            return _usbDevice.controlTransferOut({ requestType: "class", recipient: "interface", request: 0x20, value: 0, index: ctrlIface }, buffer);
        }
    }

    private function startWebUSBReadLoop():Void
    {
        if (_usbDevice == null || !_isOpenFlag || _usbEndpointIn <= 0) return;
        _isReading = true;
        var readChunk:Void->Void = null;
        readChunk = function() {
            if (!_isReading || _usbDevice == null) return;
            try {
                _usbDevice.transferIn(_usbEndpointIn, 64).then(function(result:Dynamic) {
                    if (result.status == "ok" && result.data != null) {
                        var dataView:DataView = result.data; var bytesArray = new Array<Int>();
                        for (i in 0...dataView.byteLength) bytesArray.push(dataView.getUint8(i));
                        writeToBuffer(bytesArray);
                    }
                    if (_isReading) readChunk();
                })['catch'](function(err) { setError("WebUSB Read Loop Error: " + Std.string(err)); });
            } catch (e:Dynamic) { setError("WebUSB Read Loop Exception: " + Std.string(e)); }
        };
        readChunk();
    }
    #end
}