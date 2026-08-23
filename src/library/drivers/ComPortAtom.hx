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
import haxe.io.Bytes;
#end

#if cpp
@:headerCode('
#include <string>
#include <thread>
#include <mutex>
#include <map>
#include <chrono>
#include <stdio.h>

#ifdef __ANDROID__
#ifndef ALTAURI_JNI_HELPERS_INCLUDED
#define ALTAURI_JNI_HELPERS_INCLUDED

#include <jni.h>
#include <android/log.h>

#ifndef LOGI
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "ComPortJNI", __VA_ARGS__)
#endif
#ifndef LOGE
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "ComPortJNI", __VA_ARGS__)
#endif

// g_vm is defined in ComPortAtom.cpp
extern JavaVM* g_vm;

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

#endif // ALTAURI_JNI_HELPERS_INCLUDED
#endif // __ANDROID__
')

@:cppFileCode('
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOGDI
#include <windows.h>
#include <setupapi.h>
#include <devpkey.h>
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "setupapi.lib")
// DEVPKEY_Device_BusReportedDeviceDesc is extern in some SDK versions — define it directly
// GUID {540B947E-8B40-45BC-A8A2-6A0B894CBDA2}, PID 97
static const DEVPROPKEY _myDevPropKey_BusReportedDesc = { { 0x540b947e, 0x8b40, 0x45bc, { 0xa8, 0xa2, 0x6a, 0x0b, 0x89, 0x4c, 0xbd, 0xa2 } }, 97 };
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
	JavaVM* g_vm = nullptr;
    jobject jPort;
    jobject jConnection;
#endif
    std::thread* readThread;
    volatile bool isRunning;
    char rxBuffer[4096];
    int rxLen; // Stores actual length of binary data (independent of null-terminator)
    bool hasRxData;
    std::mutex rxMutex;
    char errBuffer[256];
    bool hasError;
    std::mutex errMutex;
    std::chrono::steady_clock::time_point lastRxTime;
};

static std::map<void*, ComPortState*> _com_states_map;
static std::mutex _com_map_mutex;

#ifdef __ANDROID__
   // Единственное место, где выделяется память под g_vm
   JavaVM* g_vm = nullptr;

   JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
       g_vm = vm; // Сохраняем указатель
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
            if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
            jobject device = env->CallObjectMethod(iterator, next);
            if (env->ExceptionCheck()) { env->ExceptionClear(); if(device) env->DeleteLocalRef(device); continue; }
            if (!device) continue;
            
            jclass deviceClass = env->GetObjectClass(device);
            if (!deviceClass) { // ЗАЩИТА ОТ ZOMBIE-ОБЪЕКТОВ
                if (env->ExceptionCheck()) env->ExceptionClear();
                env->DeleteLocalRef(device);
                continue;
            }
            
            jmethodID getVendorId = env->GetMethodID(deviceClass, "getVendorId", "()I");
            jmethodID getProductId = env->GetMethodID(deviceClass, "getProductId", "()I");
            int vid = env->CallIntMethod(device, getVendorId);
            int pid = env->CallIntMethod(device, getProductId);
            if (env->ExceptionCheck()) env->ExceptionClear();
            
            if ((searchVid == vid && searchPid == pid) || (searchVid == 0 && searchPid == 0 && targetDevice == nullptr)) {
                targetDevice = device;
                env->DeleteLocalRef(deviceClass);
                break;
            }
            env->DeleteLocalRef(deviceClass);
            env->DeleteLocalRef(device);
        }
        if (env->ExceptionCheck()) env->ExceptionClear();
                
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
    
    // 4. Check and request permission
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
    
    // 5. Open device via usb-serial-for-android
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
                                                // Пытаемся установить параметры
                                                env->CallVoidMethod(port, setParams, baudRate, 8, 1, 0);
                                                if (env->ExceptionCheck()) {
                                                    env->ExceptionClear();
                                                    // CDC devices (like Arduino Leonardo) often reject setParameters.
                                                    // We ignore this error and continue, as the port is already open.
                                                    LOGI("Java Exception in setParameters() ignored (CDC device?).");
                                                }
                                                
                                                // === IMPORTANT FOR PL2303: Force DTR and RTS high ===
                                                // Этот блок теперь выполнится ВСЕГДА, даже если setParameters упала
                                                jmethodID setDTRMethod = env->GetMethodID(portClass, "setDTR", "(Z)V");
                                                jmethodID setRTSMethod = env->GetMethodID(portClass, "setRTS", "(Z)V");
                                                if (setDTRMethod != nullptr) env->CallVoidMethod(port, setDTRMethod, JNI_TRUE);
                                                if (setRTSMethod != nullptr) env->CallVoidMethod(port, setRTSMethod, JNI_TRUE);
                                                if (env->ExceptionCheck()) env->ExceptionClear();
                                                // =========================================================

                                                st->jPort = env->NewGlobalRef(port);
                                                st->jConnection = env->NewGlobalRef(connection);
                                                opened = true;
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
    }
    env->DeleteLocalRef(proberClass);
    
    // 6. Final cleanup
    env->DeleteLocalRef(targetDevice);
    env->DeleteLocalRef(mgrClass);
    env->DeleteLocalRef(usbManager);
    env->DeleteLocalRef(ctxClass);
    env->DeleteLocalRef(context);
    return opened;
}
#endif

#ifdef __ANDROID__
extern "C" bool checkAndroidUsbPermission(int searchVid, int searchPid) {
    JNIEnv* env = GetJniEnv();
    if (!env) return false;
    jobject context = GetActivity();
    if (!context) return false;
    
    jclass ctxClass = env->GetObjectClass(context);
    jmethodID getSysServ = env->GetMethodID(ctxClass, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    jstring usbStr = env->NewStringUTF("usb");
    jobject usbManager = env->CallObjectMethod(context, getSysServ, usbStr);
    env->DeleteLocalRef(usbStr);
    if (!usbManager) { env->DeleteLocalRef(ctxClass); env->DeleteLocalRef(context); return false; }
    
    jclass mgrClass = env->GetObjectClass(usbManager);
    jmethodID getDeviceList = env->GetMethodID(mgrClass, "getDeviceList", "()Ljava/util/HashMap;");
    jobject deviceMap = env->CallObjectMethod(usbManager, getDeviceList);
    if (!deviceMap) { env->DeleteLocalRef(mgrClass); env->DeleteLocalRef(usbManager); env->DeleteLocalRef(ctxClass); env->DeleteLocalRef(context); return false; }
    
    jclass mapClass = env->GetObjectClass(deviceMap);
    jmethodID valuesMethod = env->GetMethodID(mapClass, "values", "()Ljava/util/Collection;");
    jobject values = env->CallObjectMethod(deviceMap, valuesMethod);
    bool hasPermission = false;
    
    if (values != nullptr) {
        jclass collectionClass = env->GetObjectClass(values);
        jmethodID iteratorMethod = env->GetMethodID(collectionClass, "iterator", "()Ljava/util/Iterator;");
        jobject iterator = env->CallObjectMethod(values, iteratorMethod);
        jclass iteratorClass = env->GetObjectClass(iterator);
        jmethodID hasNext = env->GetMethodID(iteratorClass, "hasNext", "()Z");
        jmethodID next = env->GetMethodID(iteratorClass, "next", "()Ljava/lang/Object;");
        
        while (env->CallBooleanMethod(iterator, hasNext)) {
            if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
            jobject device = env->CallObjectMethod(iterator, next);
            if (env->ExceptionCheck()) { env->ExceptionClear(); if(device) env->DeleteLocalRef(device); continue; }
            if (!device) continue;
            
            jclass deviceClass = env->GetObjectClass(device);
            if (!deviceClass) { // ЗАЩИТА ОТ ZOMBIE-ОБЪЕКТОВ
                if (env->ExceptionCheck()) env->ExceptionClear();
                env->DeleteLocalRef(device);
                continue;
            }
            
            jmethodID getVendorId = env->GetMethodID(deviceClass, "getVendorId", "()I");
            jmethodID getProductId = env->GetMethodID(deviceClass, "getProductId", "()I");
            int vid = env->CallIntMethod(device, getVendorId);
            int pid = env->CallIntMethod(device, getProductId);
            if (env->ExceptionCheck()) env->ExceptionClear();
            
            bool match = (searchVid == vid && searchPid == pid) || (searchVid == 0 && searchPid == 0);
            if (match) {
                jmethodID hasPermMethod = env->GetMethodID(mgrClass, "hasPermission", "(Landroid/hardware/usb/UsbDevice;)Z");
                hasPermission = env->CallBooleanMethod(usbManager, hasPermMethod, device);
                if (env->ExceptionCheck()) env->ExceptionClear();
                env->DeleteLocalRef(deviceClass);
                env->DeleteLocalRef(device);
                break;
            } else {
                env->DeleteLocalRef(deviceClass);
                env->DeleteLocalRef(device);
            }
        }
        if (env->ExceptionCheck()) env->ExceptionClear();
                
        env->DeleteLocalRef(iteratorClass); env->DeleteLocalRef(iterator); env->DeleteLocalRef(collectionClass); env->DeleteLocalRef(values);
    }
    env->DeleteLocalRef(mapClass); env->DeleteLocalRef(deviceMap); env->DeleteLocalRef(mgrClass); env->DeleteLocalRef(usbManager); env->DeleteLocalRef(ctxClass); env->DeleteLocalRef(context);
    return hasPermission;
}
#endif

#ifdef __ANDROID__
extern "C" int getUsbDeviceCount() {
    JNIEnv* env = GetJniEnv();
    if (!env) return -1;
    jobject context = GetActivity();
    if (!context) return -1;

    jclass ctxClass = env->GetObjectClass(context);
    jmethodID getSysServ = env->GetMethodID(ctxClass, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    if (env->ExceptionCheck()) env->ExceptionClear();
    
    jstring usbStr = env->NewStringUTF("usb");
    jobject usbManager = env->CallObjectMethod(context, getSysServ, usbStr);
    env->DeleteLocalRef(usbStr);
    if (env->ExceptionCheck()) env->ExceptionClear();
    
    if (!usbManager) { env->DeleteLocalRef(ctxClass); env->DeleteLocalRef(context); return -1; }

    jclass mgrClass = env->GetObjectClass(usbManager);
    jmethodID getDeviceList = env->GetMethodID(mgrClass, "getDeviceList", "()Ljava/util/HashMap;");
    if (env->ExceptionCheck()) env->ExceptionClear();
    
    jobject deviceMap = env->CallObjectMethod(usbManager, getDeviceList);
    if (env->ExceptionCheck()) env->ExceptionClear();
    
    int count = -1;
    if (deviceMap != nullptr) {
        jclass mapClass = env->GetObjectClass(deviceMap);
        jmethodID sizeMethod = env->GetMethodID(mapClass, "size", "()I");
        if (env->ExceptionCheck()) env->ExceptionClear();
        count = env->CallIntMethod(deviceMap, sizeMethod);
        if (env->ExceptionCheck()) env->ExceptionClear();
        env->DeleteLocalRef(mapClass);
        env->DeleteLocalRef(deviceMap);
    }

    env->DeleteLocalRef(mgrClass);
    env->DeleteLocalRef(usbManager);
    env->DeleteLocalRef(ctxClass);
    env->DeleteLocalRef(context);
    return count;
}
#endif

static void _altauri_com_reader_loop(void* haxePtr) {
    ComPortState* st = nullptr;
    { 
        std::lock_guard<std::mutex> mapLock(_com_map_mutex); 
        auto it = _com_states_map.find(haxePtr); 
        if (it == _com_states_map.end()) return; 
        st = it->second; 
    }
    st->isRunning = true;
    st->rxLen = 0;
    st->hasRxData = false;
    st->lastRxTime = std::chrono::steady_clock::now();
    char tempBuf[4096];

#ifdef __ANDROID__
    if (st->jPort != nullptr) {
        bool attached = false;
        JNIEnv* env = GetJniEnv(&attached);
        if (env != nullptr) {
            jclass portClass = env->GetObjectClass(st->jPort);
            if (portClass != nullptr) {
                jmethodID readMethod = env->GetMethodID(portClass, "read", "([BI)I");
                if (readMethod != nullptr) {
                    jbyteArray jbuf = env->NewByteArray(4096);
                    if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
                    if (jbuf != nullptr) {
                        while (st->isRunning) {
                            jint bytesRead = env->CallIntMethod(st->jPort, readMethod, jbuf, 10);
                            if (env->ExceptionCheck()) {
                                env->ExceptionClear(); // Скрываем длинный стектрейс из Logcat
                                LOGE("Android Rx Exception -> Device Disconnected");
                                std::lock_guard<std::mutex> errLock(st->errMutex);
                                sprintf(st->errBuffer, "Device disconnected"); // Дружелюбный текст
                                st->hasError = true;
                                break;
                            }
                            if (bytesRead > 0) {
                                env->GetByteArrayRegion(jbuf, 0, bytesRead, (jbyte*)tempBuf);
                                if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
                                
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
                                st->lastRxTime = std::chrono::steady_clock::now();
                            } else if (bytesRead < 0) {
                                LOGE("Android Rx Err: %d", (int)bytesRead);
                                if (!st->isRunning) break;
                                std::lock_guard<std::mutex> errLock(st->errMutex);
                                sprintf(st->errBuffer, "Android Rx Err:%d", (int)bytesRead);
                                st->hasError = true;
                                break;
                            }
                        }
                        env->DeleteLocalRef(jbuf);
                    } else {
                        LOGE("Android RX: NewByteArray failed");
                        if (env->ExceptionCheck()) env->ExceptionClear();
                        std::lock_guard<std::mutex> errLock(st->errMutex);
                        sprintf(st->errBuffer, "Android RX: NewByteArray failed");
                        st->hasError = true;
                    }
                } else {
                    LOGE("Android RX: read([BI)I method not found!");
                    if (env->ExceptionCheck()) env->ExceptionClear();
                    std::lock_guard<std::mutex> errLock(st->errMutex);
                    sprintf(st->errBuffer, "Android RX: read([BI)I method not found!");
                    st->hasError = true;
                }
                env->DeleteLocalRef(portClass);
            } else {
                if (env->ExceptionCheck()) env->ExceptionClear();
                std::lock_guard<std::mutex> errLock(st->errMutex);
                sprintf(st->errBuffer, "Android RX: portClass is null");
                st->hasError = true;
            }
            if (attached) {
                JavaVM* vm = nullptr;
                if (env->GetJavaVM(&vm) == JNI_OK) {
                    vm->DetachCurrentThread();
                }
            }
        } else {
            std::lock_guard<std::mutex> errLock(st->errMutex);
            sprintf(st->errBuffer, "Android RX: GetJniEnv failed");
            st->hasError = true;
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
            st->lastRxTime = std::chrono::steady_clock::now();
        } else if (bResult && bytesRead == 0) {
            Sleep(1);
            continue;
        } else {
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
                st->lastRxTime = std::chrono::steady_clock::now();
            } else if (bytesRead == 0) {
                usleep(10000);
            } else {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { continue; }
                if (errno == EBADF) { break; }
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

#ifdef __ANDROID__
extern "C" const char* androidScanUSBDevices() {
    static std::string result;
    result.clear();
    JNIEnv* env = GetJniEnv();
    if (!env) return "";
    jobject context = GetActivity();
    if (!context) return "";
    
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
        if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
        jobject device = env->CallObjectMethod(iterator, next);
        if (env->ExceptionCheck()) { env->ExceptionClear(); if(device) env->DeleteLocalRef(device); continue; }
        if (!device) continue;
        
        jclass deviceClass = env->GetObjectClass(device);
        if (!deviceClass) { // ЗАЩИТА ОТ ZOMBIE-ОБЪЕКТОВ
            if (env->ExceptionCheck()) env->ExceptionClear();
            env->DeleteLocalRef(device);
            continue;
        }
        
        jmethodID getVendorId = env->GetMethodID(deviceClass, "getVendorId", "()I");
        jmethodID getProductId = env->GetMethodID(deviceClass, "getProductId", "()I");
        jmethodID getDeviceName = env->GetMethodID(deviceClass, "getDeviceName", "()Ljava/lang/String;");
        
        int vid = env->CallIntMethod(device, getVendorId);
        int pid = env->CallIntMethod(device, getProductId);
        if (env->ExceptionCheck()) env->ExceptionClear();
        
        jstring deviceNameStr = (jstring)env->CallObjectMethod(device, getDeviceName);
        if (env->ExceptionCheck()) env->ExceptionClear();
        
        std::string deviceName = "Unknown";
        if (deviceNameStr != nullptr) {
            const char* deviceNameChars = env->GetStringUTFChars(deviceNameStr, nullptr);
            if (deviceNameChars) {
                deviceName = std::string(deviceNameChars);
                env->ReleaseStringUTFChars(deviceNameStr, deviceNameChars);
            }
            env->DeleteLocalRef(deviceNameStr);
        }

        jmethodID getProductName = env->GetMethodID(deviceClass, "getProductName", "()Ljava/lang/String;");
        if (env->ExceptionCheck()) env->ExceptionClear();
        std::string productName = "USB Device";
        if (getProductName != nullptr) {
            jstring productNameStr = (jstring)env->CallObjectMethod(device, getProductName);
            if (env->ExceptionCheck()) env->ExceptionClear();
            if (productNameStr != nullptr) {
                const char* pnc = env->GetStringUTFChars(productNameStr, nullptr);
                if (pnc) { productName = std::string(pnc); env->ReleaseStringUTFChars(productNameStr, pnc); }
                env->DeleteLocalRef(productNameStr);
            }
        }
        
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "%04X|%04X|%s|", vid, pid, productName.c_str());
        result += buffer;
        result += "\\n";
        
        env->DeleteLocalRef(deviceClass);
        env->DeleteLocalRef(device);
    }
    if (env->ExceptionCheck()) env->ExceptionClear();
        
    env->DeleteLocalRef(iteratorClass);
    env->DeleteLocalRef(iterator);
    env->DeleteLocalRef(collectionClass);
    env->DeleteLocalRef(values);
    env->DeleteLocalRef(mapClass);
    env->DeleteLocalRef(deviceMap);
    env->DeleteLocalRef(mgrClass);
    env->DeleteLocalRef(usbManager);
    env->DeleteLocalRef(ctxClass);
    env->DeleteLocalRef(context);
    return result.c_str();
}
#endif

#ifdef _WIN32
// Helper: find USB device info (VID, PID, friendlyName) for a given COM port name
static void findUsbDeviceInfoForPort(const std::string& portName,
    std::string& outVid, std::string& outPid, std::string& outFriendlyName)
{
    outVid = "0000"; outPid = "0000"; outFriendlyName = "Serial Port";

    HKEY hUsbRoot;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SYSTEM\\\\CurrentControlSet\\\\Enum\\\\USB", 0, KEY_READ | KEY_WOW64_64KEY, &hUsbRoot) != ERROR_SUCCESS) return;

    char vidPidKey[256];
    DWORD vidPidKeySize;
    DWORD idx = 0;
    bool found = false;

    while (!found && RegEnumKeyExA(hUsbRoot, idx++, vidPidKey, &(vidPidKeySize = sizeof(vidPidKey)),
        NULL, NULL, NULL, NULL) == ERROR_SUCCESS)
    {
        // Parse "VID_046D&PID_C52B"
        std::string vk = vidPidKey;
        size_t vidPos = vk.find("VID_");
        size_t pidPos = vk.find("&PID_");
        if (vidPos == std::string::npos || pidPos == std::string::npos) { vidPidKeySize = sizeof(vidPidKey); continue; }
        std::string vid = vk.substr(vidPos + 4, 4);
        std::string pid = vk.substr(pidPos + 5, 4);

        HKEY hVidPid;
        if (RegOpenKeyExA(hUsbRoot, vidPidKey, 0, KEY_READ | KEY_WOW64_64KEY, &hVidPid) != ERROR_SUCCESS) {
            vidPidKeySize = sizeof(vidPidKey); continue;
        }

        char instanceKey[256];
        DWORD instKeySize;
        DWORD instIdx = 0;

        while (!found && RegEnumKeyExA(hVidPid, instIdx++, instanceKey, &(instKeySize = sizeof(instanceKey)),
            NULL, NULL, NULL, NULL) == ERROR_SUCCESS)
        {
            // Check Device Parameters\\PortName for match
            std::string paramPath = "SYSTEM\\\\CurrentControlSet\\\\Enum\\\\USB\\\\" + std::string(vidPidKey)
                + "\\\\" + std::string(instanceKey) + "\\\\Device Parameters";
            HKEY hParam;
            if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, paramPath.c_str(),
                0, KEY_READ | KEY_WOW64_64KEY, &hParam) == ERROR_SUCCESS)
            {
                char pnValue[64]; DWORD pnSize = sizeof(pnValue); DWORD pnType;
                if (RegQueryValueExA(hParam, "PortName", NULL, &pnType,
                    (LPBYTE)pnValue, &pnSize) == ERROR_SUCCESS
                    && std::string(pnValue) == portName)
                {
                    // Match found! Get real device name via SetupAPI.
                    // Registry FriendlyName = Windows-generated localized string (e.g. "Устройство с последовательным интерфейсом USB")
                    // Registry DeviceDesc  = INF reference like "@oem40.inf,%ch340ser.devicedesc%;USB" (unusable)
                    // DEVPKEY_Device_BusReportedDeviceDesc = actual iProduct string from USB descriptor (e.g. "Raspberry Pi Pico")

                    // Build device instance ID: USB\\VID_xxxx&PID_xxxx\\instance
                    std::string instanceId = "USB\\\\" + std::string(vidPidKey) + "\\\\" + std::string(instanceKey);
                    wchar_t wInstanceId[512];
                    MultiByteToWideChar(CP_UTF8, 0, instanceId.c_str(), -1, wInstanceId, 512);

                    HDEVINFO hDevInfo = SetupDiCreateDeviceInfoList(NULL, NULL);
                    if (hDevInfo != INVALID_HANDLE_VALUE) {
                        SP_DEVINFO_DATA devInfoData;
                        memset(&devInfoData, 0, sizeof(devInfoData));
                        devInfoData.cbSize = sizeof(SP_DEVINFO_DATA);

                        if (SetupDiOpenDeviceInfoW(hDevInfo, wInstanceId, NULL, 0, &devInfoData)) {
                            // Priority 1: BusReportedDeviceDesc — real iProduct string from USB descriptor
                            DEVPROPTYPE propType;
                            wchar_t wBuf[256];
                            if (SetupDiGetDevicePropertyW(hDevInfo, &devInfoData,
                                &_myDevPropKey_BusReportedDesc,
                                &propType, (PBYTE)wBuf, sizeof(wBuf), NULL, 0)) {
                                char utf8Buf[512];
                                int utf8Len = WideCharToMultiByte(CP_UTF8, 0, wBuf, -1, utf8Buf, sizeof(utf8Buf), NULL, NULL);
                                if (utf8Len > 1) { utf8Buf[utf8Len - 1] = 0; outFriendlyName = utf8Buf; }
                            }
                            // Priority 2: SPDRP_DEVICEDESC — resolved by SetupAPI (not raw INF ref)
                            if (outFriendlyName == "Serial Port" || outFriendlyName.empty()) {
                                if (SetupDiGetDeviceRegistryPropertyW(hDevInfo, &devInfoData, SPDRP_DEVICEDESC,
                                    NULL, (PBYTE)wBuf, sizeof(wBuf), NULL)) {
                                    char utf8Buf[512];
                                    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, wBuf, -1, utf8Buf, sizeof(utf8Buf), NULL, NULL);
                                    if (utf8Len > 1) { utf8Buf[utf8Len - 1] = 0; outFriendlyName = utf8Buf; }
                                }
                            }
                        }
                        SetupDiDestroyDeviceInfoList(hDevInfo);
                    }

                    // Priority 3: FriendlyName from registry (last resort)
                    if (outFriendlyName == "Serial Port" || outFriendlyName.empty()) {
                        std::string instPath = "SYSTEM\\\\CurrentControlSet\\\\Enum\\\\USB\\\\" + std::string(vidPidKey)
                            + "\\\\" + std::string(instanceKey);
                        HKEY hInst;
                        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, instPath.c_str(),
                            0, KEY_READ | KEY_WOW64_64KEY, &hInst) == ERROR_SUCCESS) {
                            wchar_t wfn[256]; DWORD wfnSize = sizeof(wfn);
                            if (RegQueryValueExW(hInst, L"FriendlyName", NULL, NULL, (LPBYTE)wfn, &wfnSize) == ERROR_SUCCESS) {
                                char utf8Buf[512];
                                int utf8Len = WideCharToMultiByte(CP_UTF8, 0, wfn, -1, utf8Buf, sizeof(utf8Buf), NULL, NULL);
                                if (utf8Len > 0) { utf8Buf[utf8Len - 1] = 0; outFriendlyName = utf8Buf; }
                            }
                            RegCloseKey(hInst);
                        }
                    }
                    outVid = vid; outPid = pid;
                    found = true;
                }
                RegCloseKey(hParam);
            }
            instKeySize = sizeof(instanceKey);
        }
        RegCloseKey(hVidPid);
        vidPidKeySize = sizeof(vidPidKey);
    }
    RegCloseKey(hUsbRoot);
}

extern "C" const char* scanWindowsCOMPorts() {
    static std::string result;
    result.clear();

    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "HARDWARE\\\\DEVICEMAP\\\\SERIALCOMM", 0, KEY_READ | KEY_WOW64_64KEY, &hKey) != ERROR_SUCCESS) return result.c_str();

    char valueName[256], valueData[256];
    DWORD vnSize, vdSize, vType, index = 0;

    while (true) {
        vnSize = sizeof(valueName); vdSize = sizeof(valueData);
        if (RegEnumValueA(hKey, index++, valueName, &vnSize,
            NULL, &vType, (LPBYTE)valueData, &vdSize) != ERROR_SUCCESS) break;

        std::string portName = valueData;
        std::string vid, pid, friendlyName;
        findUsbDeviceInfoForPort(portName, vid, pid, friendlyName);

        char buffer[512];
        snprintf(buffer, sizeof(buffer), "%s|%s|%s|%s", vid.c_str(), pid.c_str(), friendlyName.c_str(), portName.c_str());
        result += buffer;
        result += "\\n";
    }
    RegCloseKey(hKey);
    return result.c_str();
}
#endif
')
#end

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     COM PORT ATOM v3.3                                    ║
* ║     (Multi-Platform Driver: WinAPI/POSIX/Android JNI + HTML5 Web)         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                    COMPILATION FLOW                                 │  ║
* ║  │  haxe -cpp (Windows) ──► #if cpp ──► RegScanner + WinAPI CreateFile │  ║
* ║  │  haxe -cpp (Linux)   ──► #if cpp ──► POSIX open / termios           │  ║
* ║  │  haxe -cpp (Android) ──► #if cpp ──► Android usb-serial-for-android │  ║
* ║  │  haxe -html5         ──► #if html5─► Web Serial API / WebUSB        │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║         SCANNER DATA FORMAT (unified):VID|PID|friendlyName|portIdentifier ║
* ║    Android: "046D|C52B|Arduino Leonardo|"                                 ║
* ║    Windows: "046D|C52B|Arduino Leonardo (COM3)|COM3"                      ║
* ║    Windows (non-USB): "0000|0000|Serial Port|COM1"                        ║
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
/**
/**
* v3.3 CHANGES (Auto-Reopen — "port closes after grouping/pop"):
* - getPersistentState() now persists wasOpen = _isOpenFlag.
* - restoreState() sets _autoReopenRequested when wasOpen was true.
* - update() performs ONE deferred openDevice() attempt — the port
*   reopens automatically after grouping, pop()-reconstruction and
*   app restart (load-symmetric behavior: the system restores the
*   state as it was). To keep a port closed on next start, close it
*   before saving.
*
* v3.2 CHANGES (Crash Traps + Persistent Configuration — BUG-B):
* - utils.Trap breadcrumbs: openDevice / closeDevice / sendToDevice /
*   rx delivery (marker map: patches/TRAP_PLAN_v1.md).
* - NEW getPersistentState()/restoreState() overrides: portName,
*   baudRate, bufferSize, chunkSize, enabled, appendMode are persisted
*   into atomDef.values — the configuration now survives grouping,
*   pop()-reconstruction and disk save/load. Before this, reconstructed
*   instances fell back to COM1/9600 defaults (field evidence:
*   "Successfully opened COM1" right after grouping a COM17 setup).
*   Action inputs (open/close/send/setDTR/testRxData) are deliberately
*   NOT persisted — restoring them would fire side effects on Hot Start.
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
    /** Append mode for outgoing data: "none" | "CR" | "LF" | "CRLF".
     *  Applied in sendToDevice() BEFORE platform dispatch:
     *  "CR" appends \r, "LF" appends \n, "CRLF" appends \r\n.
     *  Works uniformly on every target (Android JNI / Windows WriteFile /
     *  POSIX write / HTML5 Web Serial / HTML5 WebUSB) because all paths
     *  treat each string char as one byte (charCodeAt & 0xFF). */
    private var _lastAppendMode:String = "none";
    private var _lastDTR:Bool = false;
    private var _isOpenFlag:Bool = false;
    /** v3.3: reopen once after reconstruction when wasOpen was true. */
    private var _autoReopenRequested:Bool = false;

    @:volatile private var _hasPendingRx:Bool = false;
    @:volatile private var _hasPendingErr:Bool = false;
    private var _pendingRxStr:String = "";
    private var _pendingErrStr:String = "";
    private var _rxAccumStr:String = "";

    // === Для авто-открытия после выдачи прав ===
    #if android
    private var _isWaitingForUsbPermission:Bool = false;
    private var _usbPermissionTimeout:Float = 0.0;
    private var _permCheckTimer:Float = 0.0;
    #end

    private var _rxTimer:Float = 0.0;
    private var _rxDebounceTime:Float = 0.0;
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
                new Contact("none", ContactType.INPUT, "appendMode"),
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
        #if html5
        _rxDebounceTime = 0; // Reset debounce — new data arrived, wait before emitting
        #end
        return written;
    }

    private function getBufferCount():Int { return _writePos - _readPos; }
    private function clearBuffer():Void { _readPos = 0; _writePos = 0; _overflowCount = 0; }

    private function emitRxData():Void
    {
        var availableBytes = getBufferCount();
        if (availableBytes == 0) return;
        var bytesToRead:Int = availableBytes < _chunkSize ? availableBytes : _chunkSize;
        #if html5
        var bBuf = new haxe.io.BytesBuffer();
        for (i in 0...bytesToRead)
        {
            var idx = _readPos % _bufferSize;
            bBuf.addByte(_ringBuffer[idx] & 0xFF);
            _readPos++;
        }
        var rxBytes = bBuf.getBytes();
        // Note: rxBytes.getString() is NOT used here — it decodes as UTF-8, corrupting bytes >127
        var rxString = [for (i in 0...rxBytes.length) String.fromCharCode(rxBytes.get(i))].join("");
        #else
        var rxString = "";
        for (i in 0...bytesToRead)
        {
            var idx = _readPos % _bufferSize;
            rxString += String.fromCharCode(_ringBuffer[idx]);
            _readPos++;
        }
        #end
        var rxOut = getOutput("rxData");
        if (rxOut != null) { rxOut.setValueSilent(rxString); rxOut.propagateCurrentValue(); }
        var rxTick = getOutput("rxTick");
        if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
        Impulsys.quickEmit(EventType.COMPORT_RX_DATA, rxString);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        readConfiguration();
        if (!_enabled) return;

        // v3.3: Auto-reopen — wasOpen persisted through reconstruction/save.
        if (_autoReopenRequested)
        {
            _autoReopenRequested = false;
            if (!_isOpenFlag)
            {
                utils.Trap.log("COMPORT", "auto-reopen (wasOpen=true)");
                openDevice();
            }
        }

        #if android

        // === Авто-открытие порта после выдачи прав Android ===
        if (_isWaitingForUsbPermission) {
            // Отнимаем dt, а не 1.0, так как update вызывается каждый кадр
            _usbPermissionTimeout -= dt; 
            _permCheckTimer -= dt;
            if (_usbPermissionTimeout <= 0) {
                _isWaitingForUsbPermission = false;
                setError("USB Permission request timed out or denied.");
            } else if (_permCheckTimer <= 0) {
                _permCheckTimer = 0.5; // Проверяем права раз в 0.5 сек, а не каждый кадр (~60 fps)
                var hasPerm:Bool = untyped __cpp__('(bool)checkAndroidUsbPermission({0}, {1})', _selectedVid, _selectedPid);
                if (hasPerm) {
                    trace("ComPortAtom: USB Permission granted! Auto-opening port...");
                    _isWaitingForUsbPermission = false;
                    openDevice(); // Пробуем открыть еще раз!
                }
            }
        }
        #end

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
                            auto _cps_now = std::chrono::steady_clock::now();
                            auto _cps_elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                _cps_now - _cps_stPtr->lastRxTime).count();
                            // Inter-message timeout: 50ms silence -> message complete
                            // Transport delivers bytes, Protocol decides when message ends
                            if (_cps_elapsed >= 50) {
                                {0}->_pendingRxStr = ::String(_cps_stPtr->rxBuffer, _cps_stPtr->rxLen);
                                {0}->_hasPendingRx = true;
                                _cps_stPtr->hasRxData = false;
                                _cps_stPtr->rxLen = 0;
                            }
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
            utils.Trap.log("COMPORT", "rx: \"" + _pendingRxStr + "\"");
            Impulsys.quickEmit(EventType.COMPORT_RX_DATA, _pendingRxStr);
        }

        if (_hasPendingErr)
        {
            _hasPendingErr = false;
            
            // Если это физическое отключение кабеля - не выводим страшную ошибку, просто закрываем порт
            if (_pendingErrStr.indexOf("disconnected") >= 0) {
                if (_isOpenFlag) {
                    trace('ComPortAtom: USB cable unplugged. Forcing closeDevice()...');
                    closeDevice();
                    _selectedVid = 0;
                    _selectedPid = 0;
                    Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
                }
            } else {
                // Это реальная ошибка (не отключение), выводим её пользователю
                var errOut = getOutput("error");
                if (errOut != null) { errOut.setValueSilent(_pendingErrStr); errOut.propagateCurrentValue(); }
                var errTick = getOutput("errorTick");
                if (errTick != null) { errTick.value = true; _errTimer = PULSE_DURATION; }
                Impulsys.quickEmit(EventType.COMPORT_ERROR, _pendingErrStr);
                
                if (_isOpenFlag) {
                    trace('ComPortAtom: Port error detected. Forcing closeDevice()...');
                    closeDevice();
                    _selectedVid = 0;
                    _selectedPid = 0;
                    Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
                }
            }
        }
        #if html5
        // Debounced RX: only emit when no new data has arrived for ~2 frames (~30ms at 60fps)
        // This prevents partial messages from being output when PL2303 delivers data in small USB chunks
        if (getBufferCount() > 0) {
            _rxDebounceTime += dt;
            if (_rxDebounceTime >= 0.030) {
                emitRxData();
            }
        } else {
            _rxDebounceTime = 0;
        }
        #end
        readInputs();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
		utils.Trap.log("COMPORT", "dispose enter");
		
        #if cpp
        closeDevice();
        #elseif html5
        if (_isOpenFlag) closeDevice();
        #end
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    /**
    * v3.2: Persist the current CONFIGURATION inputs so reconstructed
    * instances keep the user setup (port, baud, buffer, chunk, enabled,
    * append mode). See the class-level v3.2 notes.
    */
    override public function getPersistentState():Dynamic
    {
        var state:Dynamic = super.getPersistentState();
        if (state == null) state = {};

        var c:Contact;
        c = getInput("portName");   if (c != null && c.value != null) state.portName = c.value;
        c = getInput("baudRate");   if (c != null && c.value != null) state.baudRate = c.value;
        c = getInput("bufferSize"); if (c != null && c.value != null) state.bufferSize = c.value;
        c = getInput("chunkSize");  if (c != null && c.value != null) state.chunkSize = c.value;
        c = getInput("enabled");    if (c != null && c.value != null) state.enabled = c.value;
        state.appendMode = _lastAppendMode;
        state.wasOpen = _isOpenFlag;

        return state;
    }

    /**
    * v3.2: Restore configuration written by getPersistentState().
    * Uses Contact.setValueDirect() — restores must never trigger
    * propagation (reconstruction runs inside topology transactions).
    */
    override public function restoreState(state:Dynamic):Void
    {
        super.restoreState(state);
        if (state == null) return;

        var c:Contact;
        if (Reflect.hasField(state, "portName"))   { c = getInput("portName");   if (c != null) c.setValueDirect(Reflect.field(state, "portName")); }
        if (Reflect.hasField(state, "baudRate"))   { c = getInput("baudRate");   if (c != null) c.setValueDirect(Reflect.field(state, "baudRate")); }
        if (Reflect.hasField(state, "bufferSize")) { c = getInput("bufferSize"); if (c != null) c.setValueDirect(Reflect.field(state, "bufferSize")); }
        if (Reflect.hasField(state, "chunkSize"))  { c = getInput("chunkSize");  if (c != null) c.setValueDirect(Reflect.field(state, "chunkSize")); }
        if (Reflect.hasField(state, "enabled"))    { c = getInput("enabled");    if (c != null) c.setValueDirect(Reflect.field(state, "enabled")); }
        if (Reflect.hasField(state, "appendMode")) { _lastAppendMode = Std.string(Reflect.field(state, "appendMode")); }
        if (Reflect.hasField(state, "wasOpen")) { _autoReopenRequested = Reflect.field(state, "wasOpen") == true; }
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
        var appendModeC = getInput("appendMode");
        var dtrC   = getInput("setDTR");

        if (openC != null && openC.value == true) { openC.value = false; openDevice(); }
        if (closeC != null && closeC.value == true) { closeC.value = false; closeDevice(); }

        // ── Append mode change (COMMON) ──
        // Read line-ending append setting: "none" | "CR" | "LF" | "CRLF".
        // Applied in sendToDevice() before platform dispatch.
        if (appendModeC != null && appendModeC.value != null)
        {
            var newAm:String = Std.string(appendModeC.value);
            if (newAm != _lastAppendMode)
            {
                _lastAppendMode = newAm;
            }
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

    #if android
    public function scanUSBDevices(silent:Bool = false):Array<String>
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
            
            // Выводим отладку в RX только если не silent
            if (!silent) {
                var debugMsg = "--- USB SCAN RESULTS ---\n" + devicesStr + "----------------------\nFound: " + result.length + " devices";
                var rxOut = getOutput("rxData");
                if (rxOut != null) { rxOut.setValueSilent(debugMsg); rxOut.propagateCurrentValue(); }
                var rxTick = getOutput("rxTick");
                if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
            }
        }
        return result;
    }
    #end

    #if (cpp && !android)
    private static function extractComNumber(entry:String):Int
    {
        var idx = entry.lastIndexOf("|");
        if (idx >= 0) {
            var port = entry.substr(idx + 1);
            var upper = port.toUpperCase();
            if (upper.indexOf("COM") == 0) {
                var n = Std.parseInt(upper.substr(3));
                return (n != null) ? n : 9999;
            }
        }
        return 9999;
    }

    public function scanCOMPorts(silent:Bool = false):Array<String>
    {
        var result:Array<String> = [];
        var portsStr:String = "";
        untyped __cpp__('
            #ifdef _WIN32
            const char* ports = scanWindowsCOMPorts();
            if (ports != nullptr) { {0} = ::String(ports); }
            #endif
        ', portsStr);

        if (portsStr != null && portsStr.length > 0)
        {
            var lines = portsStr.split("\n");
            for (line in lines) if (line != null && line.length > 0) result.push(line);
            result.sort(function(a:String, b:String):Int {
                var na = extractComNumber(a);
                var nb = extractComNumber(b);
                return (na < nb ? -1 : (na > nb ? 1 : 0));
            });

            if (!silent) {
                var debugMsg = "--- COM PORT SCAN ---\n" + portsStr + "----------------------\nFound: " + result.length + " ports";
                var rxOut = getOutput("rxData");
                if (rxOut != null) { rxOut.setValueSilent(debugMsg); rxOut.propagateCurrentValue(); }
                var rxTick = getOutput("rxTick");
                if (rxTick != null) { rxTick.value = true; _rxTimer = PULSE_DURATION; }
            }
        }
        return result;
    }
    #end

    #if cpp
    public function setSelectedDevice(vid:Int, pid:Int):Void
    {
        _selectedVid = vid;
        _selectedPid = pid;
        trace('ComPortAtom: Selected device VID:PID = ${StringTools.hex(vid, 4)}:${StringTools.hex(pid, 4)}');
    }
    #end

    public function openDevice():Void
    {
        utils.Trap.log("COMPORT", "openDevice enter");
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
                    DCB dcb = {}; dcb.DCBlength = sizeof(DCB);
                    if (GetCommState(hComm, &dcb)) {
                        dcb.BaudRate = {1}; dcb.ByteSize = 8; dcb.StopBits = ONESTOPBIT; dcb.Parity = NOPARITY; dcb.fDtrControl = DTR_CONTROL_ENABLE;
                        SetCommState(hComm, &dcb);
                    }
                    COMMTIMEOUTS timeouts = {};
                    timeouts.ReadIntervalTimeout = 5; timeouts.ReadTotalTimeoutMultiplier = 0; timeouts.ReadTotalTimeoutConstant = 50;
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
                    // POSIX FIX: Reset input flags and set read timeout (VMIN/VTIME)
                    options.c_iflag &= ~(IXON | IXOFF | IXANY | ICRNL | INLCR | IGNCR);
                    options.c_cc[VMIN] = 0;
                    options.c_cc[VTIME] = 1; // Timeout 0.1 sec (returns control to thread)
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
            #if android
            _isWaitingForUsbPermission = false; // Сбрасываем флаг ожидания
            #end
            
            // === ОЧИЩАЕМ ОШИБКУ, так как порт успешно открыт ===
            _pendingErrStr = "";
            _hasPendingErr = false;
            var errOut = getOutput("error");
            if (errOut != null) { errOut.setValueSilent(""); errOut.propagateCurrentValue(); }
            // ==================================================
            
            var openOut = getOutput("isOpen");
            if (openOut != null) { openOut.setValueSilent(true); openOut.propagateCurrentValue(); }
            Impulsys.quickEmit(EventType.COMPORT_STATUS, "Connected to " + portName);
            trace('ComPortAtom: Successfully opened $portName at $baudRate baud');
            utils.Trap.log("COMPORT", "opened: " + portName + " @ " + baudRate);
        }
        else
        {
            utils.Trap.log("COMPORT", "open FAILED: " + (errMessage != "" ? errMessage : portName));
            #if android
            if (errMessage.indexOf("Requesting USB permission") >= 0) {
                _isWaitingForUsbPermission = true;
                _usbPermissionTimeout = 15.0;
                setError("Waiting for USB permission...");
            } else {
                _isWaitingForUsbPermission = false;
                setError(errMessage != "" ? errMessage : 'Failed to open serial port: $portName');
            }
            #else
            setError(errMessage != "" ? errMessage : 'Failed to open serial port: $portName');
            #end
        }
        #elseif html5
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
                                // --- USB-UART Converters ---
                                { vendorId: 0x303A }, // Espressif Systems (ESP32-S2/S3/C3 Native USB)
                                { vendorId: 0x0403 }, // FTDI (FT232R, FT2232, FT4232)
                                { vendorId: 0x1A86 }, // QinHeng Electronics (CH340, CH341, CH9102)
                                { vendorId: 0x10C4 }, // Silicon Labs (CP2102, CP2104, CP2105)
                                { vendorId: 0x067B }, // Prolific Technology (PL2303)
                                
                                // --- Microcontrollers & CDC/ACM Devices ---
                                { vendorId: 0x2341 }, // Arduino SA (Leonardo, Micro, Uno, Mega, Nano)
                                { vendorId: 0x1B4F }, // SparkFun Electronics (Pro Micro 32u4, SAMD21)
                                { vendorId: 0x0483 }, // STMicroelectronics (STM32 USB CDC / Virtual COM)
                                { vendorId: 0x2E8A }, // Raspberry Pi Foundation (RP2040 Pico CDC)
                                { vendorId: 0x03EB }  // Microchip / Atmel (SAMD21 / LUFA CDC)
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
                        setError("Neither Web Serial API nor WebUSB is supported in this browser environment.");
                }
        #end
    }

    public function closeDevice():Void
    {
        utils.Trap.log("COMPORT", "closeDevice enter isOpen=" + _isOpenFlag);
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
                                if (portClose != nullptr) {
                                    env->CallVoidMethod(st->jPort, portClose);
                                    // IMPORTANT: Ignore error if device is already physically disconnected
                                    if (env->ExceptionCheck()) env->ExceptionClear();
                                }
                                env->DeleteGlobalRef(st->jPort);
                                st->jPort = nullptr; // Clear pointer to prevent double close
                                if (st->jConnection != nullptr) {
                                    jclass connClass = env->GetObjectClass(st->jConnection);
                                    if (connClass != nullptr) {
                                        jmethodID connClose = env->GetMethodID(connClass, "close", "()V");
                                        if (connClose != nullptr) {
                                            env->CallVoidMethod(st->jConnection, connClose);
                                            if (env->ExceptionCheck()) env->ExceptionClear();
                                        }
                                        env->DeleteLocalRef(connClass);
                                    }
                                    env->DeleteGlobalRef(st->jConnection);
                                    st->jConnection = nullptr;
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
        _rxAccumStr = "";
        _rxDebounceTime = 0;
        var openOut = getOutput("isOpen");
        if (openOut != null) { openOut.setValueSilent(false); openOut.propagateCurrentValue(); }
        utils.Trap.log("COMPORT", "pre status-emit Disconnected");
        Impulsys.quickEmit(EventType.COMPORT_STATUS, "Disconnected");
        trace('ComPortAtom: Closed serial device');
		utils.Trap.log("COMPORT", "native closed");
		
        #elseif html5
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

                        if (_serialPort != null)
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
        #end
    }

    public function sendToDevice(dataStr:String):Void
    {
        if (!_isOpenFlag)
        {
            utils.Trap.log("COMPORT", "send REFUSED (port closed): \"" + dataStr + "\"");
            return;
        }
        utils.Trap.log("COMPORT", "send: \"" + dataStr + "\" append=" + _lastAppendMode);
        // ── Apply line-ending append based on _lastAppendMode ──
        // "none" → no change, "CR" → \r, "LF" → \n, "CRLF" → \r\n.
        // Applied uniformly on every target: in HTML5 the string is later
        // converted to Uint8Array via charCodeAt(i) & 0xFF (so \r → 0x0D,
        // \n → 0x0A); in C++ the Haxe string's null-terminated UTF-8 buffer
        // is passed straight to WriteFile / JNI write() / posix write(),
        // which also preserves \r and \n as single bytes.
        if (_lastAppendMode == "CR")
        {
            dataStr += "\r";
        }
        else if (_lastAppendMode == "LF")
        {
            dataStr += "\n";
        }
        else if (_lastAppendMode == "CRLF")
        {
            dataStr += "\r\n";
        }
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
                                jmethodID writeMethod = env->GetMethodID(portClass, "write", "([BI)V"); // V instead of I (void not int)
                                if (writeMethod == nullptr) {
                                    if (env->ExceptionCheck()) env->ExceptionClear();
                                    LOGE("Android TX: write method not found");
                                } else {
                                    // SAFE string length retrieval
                                    const char* dataChars = {1}.c_str();
                                    int len = strlen(dataChars);
                                    if (len > 0) {
                                        jbyteArray jbuf = env->NewByteArray(len);
                                        if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
                                        if (jbuf != nullptr) {
                                            env->SetByteArrayRegion(jbuf, 0, len, (const jbyte*)dataChars);
                                            if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
                                            env->CallVoidMethod(st->jPort, writeMethod, jbuf, 1000);
                                            if (env->ExceptionCheck()) {
                                                env->ExceptionDescribe(); // Will print Java stacktrace to Logcat
                                                env->ExceptionClear();
                                                LOGE("Android TX Java Exception in write()");
                                                std::lock_guard<std::mutex> errLock(st->errMutex);
                                                sprintf(st->errBuffer, "Android TX Exception");
                                                st->hasError = true;
                                            } else {
                                                LOGI("TX: Wrote %d bytes", len);
                                            }
                                            env->DeleteLocalRef(jbuf);
                                        } else {
                                            LOGE("Android TX: NewByteArray failed");
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
                    if (st->hComm >= 0) { (void)write(st->hComm, {1}.c_str(), {1}.length); }
                #endif
            }
        ', selfPtr, dataStr);
        #elseif html5
                if (_connectionType == "serial")
                {
                        if (_serialPort == null || !_isOpenFlag) return;
                        var writable:Dynamic = untyped js.Syntax.code("{0}.writable", _serialPort);
                        if (writable == null) { setError("Port has no writable stream"); return; }
                        _writer = untyped js.Syntax.code("{0}.getWriter()", writable);
                        var txLen:Int = dataStr.length;
                        var buf:Uint8Array = new Uint8Array(txLen);
                        for (ti in 0...txLen) buf[ti] = dataStr.charCodeAt(ti) & 0xFF;
                        var self = this;
                        untyped _writer.write(buf).then(function() { self.onWriteSuccess(); })
                        ['catch'](function(err:Dynamic) { self.onWriteError(err); });
                }
                else if (_connectionType == "usb")
                {
                        if (_usbDevice == null || _usbEndpointOut == -1) return;
                        var txLen:Int = dataStr.length;
                        var buf:Uint8Array = new Uint8Array(txLen);
                        for (ti in 0...txLen) buf[ti] = dataStr.charCodeAt(ti) & 0xFF;
                        var self = this;
                        untyped _usbDevice.transferOut(_usbEndpointOut, buf).then(function() { self.onWriteSuccess(); })
                        ['catch'](function(err:Dynamic) { self.onWriteError(err); });
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
        #end
    }

    #if html5
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

        /** Web Serial: port selected by user. */
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
        /** WebUSB: device selected by user. */
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
                                        .then(function() { 
                                                return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0001, index:0x0000}); 
                                        })
                                        .then(function() { 
                                                // Critical command: RX buffer activation
                                                return untyped dev.controlTransferOut({requestType:'vendor', recipient:'device', request:0x01, value:0x0002, index:0x0044}); 
                                        })
                                        .then(function() {
                                                var lineCoding:Uint8Array = new Uint8Array([
                                                        baudRate & 0xFF,
                                                        (baudRate >> 8) & 0xFF,
                                                        (baudRate >> 16) & 0xFF,
                                                        (baudRate >> 24) & 0xFF,
                                                        0x00,  // 1 stop bit
                                                        0x00,  // no parity
                                                        0x08   // 8 data bits
                                                ]);
                                                return untyped dev.controlTransferOut({
                                                        requestType: 'class',
                                                        recipient: 'interface',
                                                        request: 0x20,
                                                        value: 0,
                                                        index: ctrlIface
                                                }, lineCoding);
                                        }).then(function() {
                                                return untyped dev.controlTransferOut({
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
                                        .then(function() {
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
                if (result.done) {
                        _isReading = false;
                        // FIX: Release reader lock to prevent stream leak on next port open
                        if (_reader != null) {
                                var reader = _reader;
                                _reader = null;
                                try { untyped reader.releaseLock(); } catch (e:Dynamic) {}
                        }
                        return;
                }
                var bytes:Array<Int> = [];
                var value:Dynamic = result.value;
                var len:Int = untyped js.Syntax.code("{0}.length", value);
                for (i in 0...len) bytes.push(untyped js.Syntax.code("{0}[{1}]", value, i));
                writeToBuffer(bytes);
                readSerialChunk();
        }

        /** Web Serial read error handler. */
        @:keep public function onReadError(err:Dynamic):Void {
                _isReading = false;
                // FIX: Cancel and release reader lock to prevent stream leak
                if (_reader != null) {
                        var reader = _reader;
                        _reader = null;
                        untyped reader.cancel()['catch'](function(e:Dynamic) { return null; })
                        .then(function() {
                                try { untyped reader.releaseLock(); } catch (e:Dynamic) {}
                        });
                }
                if (!_isDisposed) setError('Read error: $err');
        }

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
                        if (len > 0) {
                                var bytes:Array<Int> = [];
                                for (i in 0...len) {
                                        bytes.push(dataView.getUint8(i));
                                }
                                writeToBuffer(bytes);
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

        #end
}