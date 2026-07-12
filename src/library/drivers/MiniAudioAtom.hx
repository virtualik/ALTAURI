#if cpp
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

// ============================================================================
// C++ HEADER INJECTION
// ============================================================================
// Встраиваем заголовочные файлы miniaudio и стандартные библиотеки C++ 
// в глобальный заголовок сгенерированного .cpp файла.
// Это необходимо для определения структур и функций, которые будут 
// использоваться в @:cppFileCode и untyped __cpp__.
@:headerCode('
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>
')

// ============================================================================
// C++ IMPLEMENTATION INJECTION
// ============================================================================
// Встраиваем реализацию аудио-движка непосредственно в .cpp файл.
// Здесь определяются структуры данных для lock-free передачи аудио-сэмплов
// из потока аудио-драйвера (Audio Thread) в главный поток приложения (Main Thread).
@:cppFileCode('
// Директива для включения реализации miniaudio ровно в одном .cpp файле,
// чтобы избежать ошибок линковщика (duplicate symbols).
#define MINIAUDIO_IMPLEMENTATION
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>

// ═══════════════════════════════════════════════════════════════════════════
// LOCK-FREE DOUBLE BUFFER ARCHITECTURE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │                    AUDIO THREAD (Producer)                          │
//  │                                                                     │
//  │  miniaudio callback ──► Записывает сэмплы в buffers[writeIndex]     │
//  │                           │                                         │
//  │                           ▼                                         │
//  │                     samplesWritten++                                │
//  │                           │                                         │
//  │                     (если буфер полон)                              │
//  │                           │                                         │
//  │                           ▼                                         │
//  │                     readyIndex = writeIndex  (memory_order_release) │
//  │                     writeIndex = 1 - writeIndex                     │
//  │                     samplesWritten = 0                              │
//  └─────────────────────────────────────────────────────────────────────┘
//                              │
//                              ▼ (Атомарный флаг readyIndex)
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │                    MAIN THREAD (Consumer)                           │
//  │                                                                     │
//  │  update(dt) ──► _scope_get_ready_index()                            │
//  │                     │                                               │
//  │                     ▼                                               │
//  │               (если readyIndex >= 0)                                │
//  │                     │                                               │
//  │                     ▼                                               │
//  │               Копируем данные из buffers[readyIndex] в Haxe массивы │
//  │                     │                                               │
//  │                     ▼                                               │
//  │               _scope_clear_ready() (readyIndex = -1)                │
//  └─────────────────────────────────────────────────────────────────────┘
//
// Эта схема гарантирует:
// 1. Отсутствие блокировок (mutex-free) — критично для real-time аудио.
// 2. Отсутствие аллокаций памяти в потоке воспроизведения/записи.
// 3. Корректную синхронизацию через std::atomic и memory ordering.
// ═══════════════════════════════════════════════════════════════════════════

// Структура двойного буфера для передачи аудио-данных между потоками.
struct DoubleBuffer {
    // Два буфера для сэмплов (Ping-Pong). 
    // Формат: interleaved stereo (L, R, L, R...).
    // Размер: 512 фреймов * 2 канала = 1024 float-ов на буфер.
    float buffers[2][512 * 2];  
    
    // Индекс буфера, в который Audio Thread прямо сейчас пишет данные.
    std::atomic<int> writeIndex;  
    
    // Индекс буфера, который заполнен и готов к чтению Main Thread-ом.
    // -1 означает, что готовых буферов нет.
    std::atomic<int> readyIndex;  
    
    // Счетчик сэмплов, записанных в текущий буфер (writeIndex).
    std::atomic<int> samplesWritten;  
    
    // Целевой размер буфера (количество фреймов, после которого буфер считается полным).
    int targetSize;  
    
    DoubleBuffer() : writeIndex(0), readyIndex(-1), samplesWritten(0), targetSize(512) {
        memset(buffers, 0, sizeof(buffers));
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO CALLBACK (PRODUCER THREAD)
// ═══════════════════════════════════════════════════════════════════════════
// Эта функция вызывается библиотекой miniaudio в отдельном потоке 
// каждый раз, когда аудио-устройство готово принять/отдать порцию данных.
// 
// КРИТИЧНО: Здесь ЗАПРЕЩЕНО аллоцировать память, использовать мьютексы 
// или вызывать блокирующие системные функции.
static void _altauri_audio_cb_double(
    ma_device*  pDevice,
    void*       pOutput,
    const void* pInput,
    ma_uint32   frameCount)
{
    // Получаем указатель на экземпляр Haxe-класса (MiniAudioAtom).
    // pUserData был установлен при инициализации устройства.
    ::library::drivers::MiniAudioAtom_obj* self =
        (::library::drivers::MiniAudioAtom_obj*)(pDevice->pUserData);
    
    // Проверка на dispose: если объект уже уничтожен, немедленно выходим.
    // _isDisposed помечен как @:volatile в Haxe, чтобы компилятор C++ 
    // не кешировал его значение в регистре потока.
    if (!self || (bool)self->_isDisposed) return;
    
    DoubleBuffer* db = (DoubleBuffer*)self->_doubleBufferRaw;
    if (!db) return;
    
    const float* samples = (const float*)pInput;
    if (!samples) return;
    
    // Читаем параметры атома. Они могут быть изменены из Main Thread,
    // но для аудио-потока допустимо читать их без мьютекса (допустим tearing),
    // так как это просто коэффициенты усиления.
    float gain = (float)self->_gain;
    int channel = (int)self->_channel;
    float quantum = (float)self->_quantum;
    
    // Переменные для накопления RMS (Root Mean Square) и детекции клиппинга.
    float rmsAccum = 0.0f;
    bool clip = false;
    float lastSample = 0.0f;
    
    // Загружаем индексы буферов. 
    // memory_order_relaxed достаточно, так как мы читаем свои же локальные данные,
    // а синхронизация между потоками происходит только при записи в readyIndex.
    int writeIdx = db->writeIndex.load(std::memory_order_relaxed);
    float* buffer = db->buffers[writeIdx];
    int accum = db->samplesWritten.load(std::memory_order_relaxed);
    int targetSize = db->targetSize;
    
    // Основной цикл обработки аудио-фреймов.
    for (ma_uint32 i = 0; i < frameCount; i++)
    {
        // Читаем стерео-пару (interleaved format: L, R, L, R...).
        // Применяем коэффициент усиления (gain).
        float left  = samples[i * 2]     * gain;
        float right = samples[i * 2 + 1] * gain;
        
        // Микширование в моно в зависимости от выбранного канала.
        float mono = 0.0f;
        if (channel == 0) mono = (left + right) * 0.5f; // Среднее (Mono)
        else if (channel == 1) mono = left;             // Только левый
        else if (channel == 2) mono = right;            // Только правый
        
        // Детекция клиппинга (превышение диапазона [-1.0, 1.0]).
        if (mono >  1.0f) { mono =  1.0f; clip = true; }
        if (mono < -1.0f) { mono = -1.0f; clip = true; }
        
        // Накопление суммы квадратов для расчета RMS.
        rmsAccum += mono * mono;
        lastSample = mono;
        
        // Записываем сэмплы в буфер ТОЛЬКО если он еще не переполнен.
        // Это защищает от переполнения массива, если frameCount > targetSize.
        if (accum < targetSize) {
            int bufIdx = accum * 2;
            buffer[bufIdx]     = left;
            buffer[bufIdx + 1] = right;
            accum++;
        }
    }
    
    // Сохраняем количество записанных сэмплов.
    db->samplesWritten.store(accum, std::memory_order_relaxed);
    
    // ═══════════════════════════════════════════════════════════════════
    // SWAP BUFFERS (LOCK-FREE HANDSHAKE)
    // ═══════════════════════════════════════════════════════════════════
    // Если буфер заполнен до целевого размера, мы должны передать его 
    // Main Thread-у и переключиться на второй буфер.
    if (accum >= targetSize) {
        // 1. Публикуем индекс заполненного буфера.
        // memory_order_release гарантирует, что все записи в buffer[] 
        // будут видны Main Thread-у ДО того, как он прочитает readyIndex.
        db->readyIndex.store(writeIdx, std::memory_order_release);
        
        // 2. Переключаемся на второй буфер (Ping-Pong).
        int nextIdx = 1 - writeIdx;
        db->writeIndex.store(nextIdx, std::memory_order_release);
        
        // 3. Сбрасываем счетчик для нового буфера.
        db->samplesWritten.store(0, std::memory_order_relaxed);
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // METADATA CALCULATION
    // ═══════════════════════════════════════════════════════════════════
    // Вычисляем RMS (уровень громкости) и квантованный сэмпл.
    float rms = sqrtf(rmsAccum / (float)frameCount);
    
    // Квантование амплитуды: округляем до ближайшего шага (quantum).
    // Это позволяет генерировать импульс "changed" только при пересечении 
    // пороговых значений, что полезно для триггеров и событий.
    float quantized = roundf(lastSample / quantum) * quantum;
    if (quantized >  1.0f) quantized =  1.0f;
    if (quantized < -1.0f) quantized = -1.0f;
    
    // Детекция изменения квантованного значения.
    // Игнорируем первое изменение (инициализация).
    bool changed = (!(bool)self->_isFirstSample) &&
                   (quantized != (float)self->_lastQuantum);
    
    // ═══════════════════════════════════════════════════════════════════
    // CROSS-THREAD DATA TRANSFER (PRODUCER -> CONSUMER)
    // ═══════════════════════════════════════════════════════════════════
    // Записываем вычисленные метаданные в volatile-поля Haxe-объекта.
    // Main Thread прочитает их в update(dt).
    // @:volatile в Haxe гарантирует, что C++ не закеширует эти переменные 
    // в регистрах и будет читать/писать их напрямую в RAM.
    self->_pendingSample  = quantized;
    self->_pendingRms     = rms;
    self->_pendingClip    = clip;
    self->_pendingChanged = changed;
    self->_lastQuantum    = quantized;
    self->_isFirstSample  = false;
    self->_hasPending     = true; // Флаг: "Есть новые данные для обработки"
}

// ═══════════════════════════════════════════════════════════════════════════
// C-API FOR HAXE INTEROP
// ═══════════════════════════════════════════════════════════════════════════
// Эти функции вызываются из Haxe через untyped __cpp__.
// Они обеспечивают безопасный доступ к структуре DoubleBuffer.

// Возвращает индекс готового буфера или -1, если готовых нет.
extern "C" int _scope_get_ready_index(void* raw) {
    if (!raw) return -1;
    // memory_order_acquire гарантирует, что мы увидим все записи в buffer[],
    // которые были сделаны Audio Thread-ом ДО установки readyIndex.
    return ((DoubleBuffer*)raw)->readyIndex.load(std::memory_order_acquire);
}

// Возвращает сырой указатель на массив float-ов в указанном буфере.
extern "C" void* _scope_get_buffer_ptr(void* raw, int index) {
    if (!raw || index < 0 || index > 1) return nullptr;
    return (void*)((DoubleBuffer*)raw)->buffers[index];
}

// Сбрасывает флаг готовности буфера (Main Thread сообщает, что скопировал данные).
extern "C" void _scope_clear_ready(void* raw) {
    if (!raw) return;
    ((DoubleBuffer*)raw)->readyIndex.store(-1, std::memory_order_release);
}
')

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     MINI AUDIO ATOM v1.0                                  ║
* ║                     (Zero-GC Real-Time Audio Capture)                     ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Драйвер захвата аудио (микрофон или системный loopback) на базе          ║
* ║  библиотеки miniaudio. Поддерживает передачу сырых сэмплов,               ║
* ║  расчет RMS, детекцию клиппинга и квантование амплитуды.                  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     MiniAudioAtom                                   │  ║
* ║  │                                                                     │  ║
* ║  │  A) COMPUTE MODULE (Main Thread — update(dt)):                      │  ║
* ║  │     ─────────────────────────────────────────                       │  ║
* ║  │     1. readInputs()                                                 │  ║
* ║  │        - Чтение параметров из входных контактов                     │  ║
* ║  │        - mode, quantum, gain, channel, rate, bufferSize             │  ║
* ║  │                                                                     │  ║
* ║  │     2. checkDoubleBuffer()                                          │  ║
* ║  │        - Опрос C++ буфера на наличие готовых данных                 │  ║
* ║  │        - Если readyIndex >= 0:                                      │  ║
* ║  │            propagateScopeBuffer() → копирование в Haxe массивы      │  ║
* ║  │            _scope_clear_ready() → освобождение буфера               │  ║
* ║  │                                                                     │  ║
* ║  │     3. Batched Driver Update Pattern                                │  ║
* ║  │        - setValueSilent() для всех выходных контактов               │  ║
* ║  │        - propagateCurrentValue() один раз на контакт                │  ║
* ║  │        - Это снижает нагрузку на TickGenerator                      │  ║
* ║  │                                                                     │  ║
* ║  │  B) DATABANK (Haxe):                                                │  ║
* ║  │     ─────────────────────                                           │  ║
* ║  │     _mode, _quantum, _gain, _channel, _sampleRateIdx                │  ║
* ║  │     _lastQuantum, _isFirstSample                                    │  ║
* ║  │     _bufA, _bufLA, _bufRA (Ping-Pong Buffer A)                      │  ║
* ║  │     _bufB, _bufLB, _bufRB (Ping-Pong Buffer B)                      │  ║
* ║  │                                                                     │  ║
* ║  │  C) CROSS-THREAD STATE (@:volatile):                                │  ║
* ║  │     ─────────────────────────────────                               │  ║
* ║  │     _hasPending, _pendingSample, _pendingRms,                       │  ║
* ║  │     _pendingClip, _pendingChanged                                   │  ║
* ║  │     (Записываются в Audio Thread, читаются в Main Thread)           │  ║
* ║  │                                                                     │  ║
* ║  │  D) INPUTS:                                                         │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "mode"       - 0 = Mic, 1 = Loopback                            │  ║
* ║  │     "quantum"    - Шаг квантования амплитуды (0.001 .. 1.0)         │  ║
* ║  │     "gain"       - Коэффициент усиления                             │  ║
* ║  │     "channel"    - 0=Mono, 1=Left, 2=Right                          │  ║
* ║  │     "rate"       - Индекс частоты дискретизации (44100/48000/96000) │  ║
* ║  │     "bufferSize" - Размер буфера (64 .. 512 фреймов)                │  ║
* ║  │                                                                     │  ║
* ║  │  E) OUTPUTS:                                                        │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "sample"    - Квантованный сэмпл (Float)                        │  ║
* ║  │     "changed"   - Импульс при изменении квантованного значения      │  ║
* ║  │     "rms"       - Уровень громкости RMS (Float)                     │  ║
* ║  │     "clip"      - Импульс при клиппинге (Bool)                      │  ║
* ║  │     "tick"      - Импульс на каждый обработанный буфер (Bool)       │  ║
* ║  │     "level"     - Уровень в dBFS (Float)                            │  ║
* ║  │     "device"    - Название устройства (String)                      │  ║
* ║  │     "buffer"    - Моно буфер (Array<Float>)                         │  ║
* ║  │     "bufferL"   - Левый канал (Array<Float>)                        │  ║
* ║  │     "bufferR"   - Правый канал (Array<Float>)                       │  ║
* ║  │                                                                     │  ║
* ║  │  F) FACE (DeviceView):                                              │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     MiniAudioWidget для визуализации VU-метра и управления          │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    ZERO-GC PING-PONG BUFFERS                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  В Haxe аллокация массивов в рантайме вызывает сборку мусора (GC),        ║
* ║  что приводит к микро-фризам в аудио-потоке.                              ║
* ║                                                                           ║
* ║  Решение:                                                                 ║
* ║  ┌──────────────────────────────────────────────────────────────────────┐ ║
* ║  │  В init() предвыделяются 6 массивов фиксированного размера:          │ ║
* ║  │    _bufA, _bufLA, _bufRA (Буфер A)                                   │ ║
* ║  │    _bufB, _bufLB, _bufRB (Буфер B)                                   │ ║
* ║  │                                                                      │ ║
* ║  │  В propagateScopeBuffer() мы просто переключаем указатели:           │ ║
* ║  │    if (_activeBuf == 0) target = _bufB; else target = _bufA;         │ ║
* ║  │                                                                      │ ║
* ║  │  Результат: 0 аллокаций на каждый обработанный аудио-буфер.          │ ║
* ║  └──────────────────────────────────────────────────────────────────────┘ ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class MiniAudioAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    /** Минимальный шаг квантования амплитуды. */
    private static inline var MIN_QUANTUM:Float    = 0.001;
    /** Максимальный шаг квантования амплитуды. */
    private static inline var MAX_QUANTUM:Float    = 1.0;
    /** Длительность импульса (tick, changed, clip) в секундах. */
    private static inline var PULSE_DURATION:Float = 0.05;
    
    /** Режим захвата: Микрофон. */
    private static inline var MODE_MIC:Int      = 0;
    /** Режим захвата: Системный Loopback (то, что воспроизводится). */
    private static inline var MODE_LOOPBACK:Int = 1;
    
    /** Поддерживаемые частоты дискретизации. */
    private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];
    
    // =========================================================================
    // C++ POINTERS (DATABANK)
    // =========================================================================
    /** Указатель на структуру ma_device в C++. */
    private var _device:cpp.RawPointer<cpp.Void>  = null;
    /** Указатель на структуру ma_context в C++. */
    private var _context:cpp.RawPointer<cpp.Void> = null;
    /** Указатель на структуру DoubleBuffer в C++. */
    private var _deviceReady:Bool = false;
    
    // =========================================================================
    // PARAMETERS (DATABANK)
    // =========================================================================
    /** Текущий режим работы (Mic или Loopback). */
    private var _mode:Int          = MODE_LOOPBACK;
    /** Шаг квантования амплитуды. */
    private var _quantum:Float     = 0.01;
    /** Коэффициент усиления сигнала. */
    private var _gain:Float        = 1.0;
    /** Выбранный канал (0=Mono, 1=Left, 2=Right). */
    private var _channel:Int       = 0;
    /** Индекс частоты дискретизации в массиве SAMPLE_RATES. */
    private var _sampleRateIdx:Int = 0;
    
    /** Последний квантованный сэмпл (для детекции изменений). */
    private var _lastQuantum:Float  = 0.0;
    /** Флаг первого сэмпла (игнорируем изменение при инициализации). */
    private var _isFirstSample:Bool = true;
    
    // =========================================================================
    // CROSS-THREAD STATE (@:volatile)
    // =========================================================================
    // Эти поля записываются в Audio Thread (C++ callback) 
    // и читаются в Main Thread (Haxe update).
    // @:volatile заставляет C++ компилятор всегда читать/писать их в RAM,
    // избегая кеширования в регистрах процессора.
    
    /** Сырой указатель на DoubleBuffer. */
    @:volatile private var _doubleBufferRaw:cpp.RawPointer<cpp.Void> = null;
    
    /** Флаг: есть новые данные для обработки в Main Thread. */
    @:volatile private var _hasPending:Bool     = false;
    /** Последний квантованный сэмпл (из Audio Thread). */
    @:volatile private var _pendingSample:Float  = 0.0;
    /** Последний расчет RMS (из Audio Thread). */
    @:volatile private var _pendingRms:Float     = 0.0;
    /** Флаг клиппинга (из Audio Thread). */
    @:volatile private var _pendingClip:Bool     = false;
    /** Флаг изменения квантованного значения (из Audio Thread). */
    @:volatile private var _pendingChanged:Bool  = false;
    
    // =========================================================================
    // PULSE TIMERS (MAIN THREAD STATE)
    // =========================================================================
    /** Таймер для сброса импульса "changed". */
    private var _changedTimer:Float = 0.0;
    /** Таймер для сброса импульса "tick". */
    private var _tickTimer:Float    = 0.0;
    /** Таймер для сброса импульса "clip". */
    private var _clipTimer:Float    = 0.0;
    
    /** Целевой размер буфера в фреймах. */
    private var _bufferSize:Int = 512;
    
    // =========================================================================
    // ZERO-GC PING-PONG BUFFERS
    // =========================================================================
    // Предвыделенные массивы для копирования данных из C++ без аллокаций.
    // Мы используем два набора буферов (A и B), чтобы копировать данные 
    // из C++ в один набор, пока другой набор передается в下游 (downstream) атомы.
    
    /** Буфер A: Моно микс. */
    private var _bufA:Array<Float>;
    /** Буфер A: Левый канал. */
    private var _bufLA:Array<Float>;
    /** Буфер A: Правый канал. */
    private var _bufRA:Array<Float>;
    
    /** Буфер B: Моно микс. */
    private var _bufB:Array<Float>;
    /** Буфер B: Левый канал. */
    private var _bufLB:Array<Float>;
    /** Буфер B: Правый канал. */
    private var _bufRB:Array<Float>;
    
    /** Индекс активного буфера (0 = A, 1 = B). */
    private var _activeBuf:Int = 0;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
    * Создает новый экземпляр MiniAudioAtom.
    * Инициализирует входные и выходные контакты, регистрирует драйвер.
    * 
    * @param id Уникальный идентификатор атома.
    */
    public function new(id:String)
    {
        super(
            // === INPUTS (Параметры управления) ===
            [
                new Contact(MODE_LOOPBACK, INPUT, "mode"),       // 0 = Mic, 1 = Loopback
                new Contact(0.01, INPUT, "quantum"),             // Шаг квантования
                new Contact(50.0, INPUT, "gain"),                // Усиление
                new Contact(0, INPUT, "channel"),                // 0=Mono, 1=Left, 2=Right
                new Contact(0, INPUT, "rate"),                   // Индекс частоты
                new Contact(512, INPUT, "bufferSize")            // Размер буфера
            ],
            // === OUTPUTS (Данные и метаданные) ===
            [
                new Contact(0.0, OUTPUT, "sample"),              // Квантованный сэмпл
                new Contact(false, OUTPUT, "changed"),           // Импульс изменения
                new Contact(0.0, OUTPUT, "rms"),                 // Уровень RMS
                new Contact(false, OUTPUT, "clip"),              // Импульс клиппинга
                new Contact(false, OUTPUT, "tick"),              // Импульс обработки буфера
                new Contact(0.0, OUTPUT, "level"),               // Уровень в dBFS
                new Contact("", OUTPUT, "device"),               // Название устройства
                new Contact(null, OUTPUT, "buffer"),             // Моно буфер (Array)
                new Contact(null, OUTPUT, "bufferL"),            // Левый канал (Array)
                new Contact(null, OUTPUT, "bufferR")             // Правый канал (Array)
            ],
            null,          // Нет стандартной функции process (мы Driver)
            id,
            "MiniAudioAtom",
            true           // isActive = true -> регистрируется в DriverManager
        );
        
        // Отключаем защиту от осцилляции для выхода "sample",
        // так как мы ожидаем частых изменений значения.
        var sampleOut = getOutput("sample");
        if (sampleOut != null) sampleOut.ignoreOscillation = true;
        
        // Инициализация драйвера (открытие аудио-устройства).
        init();
    }
    
    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    /**
    * Инициализация драйвера.
    * Вызывается один раз при регистрации в DriverManager.
    * Предвыделяет Zero-GC буферы и открывает аудио-устройство.
    */
    override public function init():Void
    {
        // 1. Предвыделение Zero-GC Ping-Pong Buffers.
        // Мы создаем массивы фиксированного размера один раз, чтобы избежать 
        // аллокаций в рантайме (которые вызывали бы GC).
        _bufA = new Array<Float>(); _bufLA = new Array<Float>(); _bufRA = new Array<Float>();
        _bufB = new Array<Float>(); _bufLB = new Array<Float>(); _bufRB = new Array<Float>();
        
        // Заполняем нулями (512 фреймов).
        for (i in 0...512) {
            _bufA.push(0.0); _bufLA.push(0.0); _bufRA.push(0.0);
            _bufB.push(0.0); _bufLB.push(0.0); _bufRB.push(0.0);
        }
        
        // 2. Чтение начальных параметров из контактов.
        readInputs();
        
        // 3. Открытие аудио-устройства (запуск захвата).
        openDevice();
    }
    
    /**
    * Главный цикл обновления драйвера.
    * Вызывается каждый кадр из DriverManager.update(dt).
    * 
    * ═══════════════════════════════════════════════════════════════════
    * BATCHED DRIVER UPDATE PATTERN
    * ═══════════════════════════════════════════════════════════════════
    * 
    *  ┌─────────────────────────────────────────────────────────────────┐
    *  │  1. setValueSilent(value) для всех выходов                      │
    *  │     → Записываем значение в _value, НЕ триггеря propagation.    │
    *  │                                                                 │
    *  │  2. propagateCurrentValue() один раз на выход                   │
    *  │     → Уведомляем подписчиков (виджеты, downstream атомы).       │
    *  │                                                                 │
    *  │  Результат: Снижение нагрузки на TickGenerator,                 │
    *  │  так как propagation происходит не на каждую запись,            │
    *  │  а только один раз за кадр на каждый контакт.                   │
    *  └─────────────────────────────────────────────────────────────────┘
    * 
    * @param dt Delta time (время с прошлого кадра в секундах).
    */
    override public function update(dt:Float):Void
    {
        // Проверка на dispose: если объект уничтожен, выходим.
        if (_isDisposed) return;
        
        // 1. Проверяем, есть ли готовые данные в Double Buffer.
        checkDoubleBuffer();
        
        // 2. Если Audio Thread передал новые данные (_hasPending == true)...
        if (_hasPending)
        {
            // Сбрасываем флаг, чтобы не обрабатывать данные повторно.
            _hasPending = false;
            
            // Сохраняем снимок данных (snapshot) в локальные переменные.
            // Это гарантирует, что мы работаем с консистентными данными,
            // даже если Audio Thread уже начал писать новые.
            var snapSample  = _pendingSample;
            var snapRms     = _pendingRms;
            var snapClip    = _pendingClip;
            var snapChanged = _pendingChanged;
            
            // Получаем ссылки на выходные контакты.
            var sampleOut = getOutput("sample");
            var rmsOut    = getOutput("rms");
            var levelOut  = getOutput("level");
            
            // === BATCHED WRITE (Silent) ===
            // Записываем значения без триггера propagation.
            if (sampleOut != null) sampleOut.setValueSilent(snapSample);
            if (rmsOut    != null) rmsOut.setValueSilent(snapRms);
            
            // Конвертируем RMS в dBFS (децибелы относительно Full Scale).
            // Формула: 20 * log10(rms). Если rms близок к 0, возвращаем -120 dB.
            if (levelOut != null)
            {
                var db = snapRms > 0.0001 ? 20.0 * Math.log(snapRms) / Math.log(10) : -120.0;
                levelOut.setValueSilent(db);
            }
            
            // === PULSE GENERATION (Tick, Changed, Clip) ===
            // Генерируем короткие импульсы (PULSE_DURATION секунд).
            var tickOut = getOutput("tick");
            if (tickOut != null) { tickOut.value = true; _tickTimer = PULSE_DURATION; }
            
            if (snapChanged)
            {
                var c = getOutput("changed");
                if (c != null) { c.value = true; _changedTimer = PULSE_DURATION; }
            }
            
            if (snapClip)
            {
                var c = getOutput("clip");
                if (c != null) { c.value = true; _clipTimer = PULSE_DURATION; }
            }
            
            // === PROPAGATION (One-shot) ===
            // Уведомляем подписчиков о том, что данные обновились.
            // Это триггерит пересчет downstream атомов и обновление виджетов.
            if (sampleOut != null) sampleOut.propagateCurrentValue();
            if (rmsOut    != null) rmsOut.propagateCurrentValue();
            if (levelOut  != null) levelOut.propagateCurrentValue();
        }
        
        // 3. Обновляем таймеры импульсов (сбрасываем их в false по истечении времени).
        updatePulseTimers(dt);
        
        // 4. Читаем входные параметры (возможно, пользователь изменил настройки).
        readInputs();
    }
    
    /**
    * Освобождение ресурсов.
    * Вызывается при удалении атома из сцены.
    * Закрывает аудио-устройство и отменяет регистрацию в DriverManager.
    */
    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }
    
    // =========================================================================
    // DOUBLE BUFFER CHECK (MAIN THREAD)
    // =========================================================================
    /**
    * Проверяет наличие готовых данных в C++ Double Buffer.
    * Если буфер готов, копирует данные в Haxe массивы и распространяет их.
    */
    private function checkDoubleBuffer():Void
    {
        if (_doubleBufferRaw == null) return;
        
        var readyIndex:Int = -1;
        // Вызываем C++ функцию для получения индекса готового буфера.
        untyped __cpp__('{0} = ::_scope_get_ready_index({1});', readyIndex, _doubleBufferRaw);
        
        // Если readyIndex >= 0, значит Audio Thread заполнил буфер.
        if (readyIndex >= 0)
        {
            // Копируем данные из C++ в Haxe массивы (Ping-Pong).
            propagateScopeBuffer(readyIndex);
            
            // Сообщаем C++, что мы скопировали данные и буфер можно переиспользовать.
            untyped __cpp__('::_scope_clear_ready({0});', _doubleBufferRaw);
        }
    }
    
    // =========================================================================
    // DEVICE MANAGEMENT
    // =========================================================================
    /**
    * Открывает аудио-устройство (микрофон или loopback).
    * Инициализирует miniaudio context и device, запускает захват.
    */
    private function openDevice():Void
    {
        // Определяем частоту дискретизации и тип устройства.
        var sampleRate : Int = SAMPLE_RATES[_sampleRateIdx];
        var deviceType : Int = (_mode == MODE_LOOPBACK) ? 2 : 1; // 2 = loopback, 1 = capture
        
        // ═══════════════════════════════════════════════════════════════════
        // C++ INITIALIZATION BLOCK
        // ═══════════════════════════════════════════════════════════════════
        // Здесь происходит вся магия инициализации miniaudio.
        // Мы используем untyped __cpp__ для прямого вызова C++ API.
        untyped __cpp__('
            // 1. Создаем Double Buffer в куче (heap).
            DoubleBuffer* db = new DoubleBuffer();
            db->targetSize = {2}; // Устанавливаем целевой размер буфера.
            {0}->_doubleBufferRaw = (void*)db; // Сохраняем указатель в Haxe-объект.
            
            // 2. Выделяем память под context и device.
            ma_context* ctx = (ma_context*)malloc(sizeof(ma_context));
            ma_device*  dev = (ma_device*)malloc(sizeof(ma_device));
            
            if (!ctx || !dev) {
                delete db;
                {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            // 3. Инициализируем контекст miniaudio.
            ma_result result = ma_context_init(NULL, 0, NULL, ctx);
            if (result != MA_SUCCESS) { 
                free(ctx); free(dev); delete db;
                {0}->_doubleBufferRaw = nullptr;
                return; 
            }
            
            {0}->_context = ctx;
            
            // 4. Настраиваем конфигурацию устройства.
            ma_device_config cfg = ma_device_config_init(
                {1} == 2 ? ma_device_type_loopback : ma_device_type_capture
            );
            cfg.sampleRate         = (ma_uint32){3}; // Частота дискретизации.
            cfg.periodSizeInFrames = 512;            // Размер фрейма (latency).
            cfg.capture.format     = ma_format_f32;  // Формат: 32-bit float.
            cfg.capture.channels   = 2;              // Каналы: Stereo.
            
            // Указываем callback-функцию, которая будет вызываться при каждом фрейме.
            cfg.dataCallback       = _altauri_audio_cb_double;
            
            // Передаем указатель на Haxe-объект в callback (pUserData).
            cfg.pUserData          = (void*)({0}.mPtr);
            
            // 5. Инициализируем устройство.
            result = ma_device_init(ctx, &cfg, dev);
            if (result != MA_SUCCESS) {
                ma_context_uninit(ctx);
                free(ctx); free(dev); delete db;
                {0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            {0}->_device = dev;
            
            // 6. Запускаем захват/воспроизведение.
            result = ma_device_start(dev);
            if (result != MA_SUCCESS) {
                ma_device_uninit(dev); ma_context_uninit(ctx);
                free(dev); free(ctx); delete db;
                {0}->_device = NULL; {0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
                return;
            }
            
            // Если всё прошло успешно, устанавливаем флаг готовности.
            {0}->_deviceReady = true;
        ', this, deviceType, _bufferSize, sampleRate);
        
        // Обновляем выходной контакт с названием устройства.
        if (_deviceReady) 
            setDeviceNameOutput((_mode == MODE_LOOPBACK) ? "Loopback @" + sampleRate + "Hz" : "Capture @" + sampleRate + "Hz");
        else 
            setDeviceNameOutput("ERROR: device init failed");
    }
    
    /**
    * Закрывает аудио-устройство и освобождает ресурсы.
    */
    private function closeDevice():Void
    {
        if (!_deviceReady) return;
        _deviceReady = false;
        
        // ═══════════════════════════════════════════════════════════════════
        // C++ CLEANUP BLOCK
        // ═══════════════════════════════════════════════════════════════════
        untyped __cpp__('
            ma_device*  dev = (ma_device*) {0}->_device;
            ma_context* ctx = (ma_context*){0}->_context;
            DoubleBuffer* db = (DoubleBuffer*){0}->_doubleBufferRaw;
            
            // Останавливаем и уничтожаем устройство.
            if (dev) { ma_device_stop(dev); ma_device_uninit(dev); free(dev); }
            // Уничтожаем контекст.
            if (ctx) { ma_context_uninit(ctx); free(ctx); }
            // Освобождаем Double Buffer.
            if (db)  { delete db; }
            
            // Обнуляем указатели в Haxe-объекте.
            {0}->_device = nullptr;
            {0}->_context = nullptr;
            {0}->_doubleBufferRaw = nullptr;
        ', this);
    }
    
    // =========================================================================
    // BUFFER PROPAGATION (ZERO-GC)
    // =========================================================================
    /**
    * Копирует данные из C++ буфера в Haxe массивы (Ping-Pong).
    * Использует предвыделенные массивы для избежания аллокаций (Zero-GC).
    * 
    * @param readyIndex Индекс готового буфера в C++ (0 или 1).
    */
    private function propagateScopeBuffer(readyIndex:Int):Void
    {
        if (_doubleBufferRaw == null) return;
        
        // ═══════════════════════════════════════════════════════════════════
        // PING-PONG BUFFER SELECTION
        // ═══════════════════════════════════════════════════════════════════
        // Выбираем неактивный набор буферов для записи.
        // Пока мы копируем в _bufB, downstream атомы могут читать из _bufA.
        var targetBuf:Array<Float>;
        var targetBufL:Array<Float>;
        var targetBufR:Array<Float>;
        
        if (_activeBuf == 0) {
            targetBuf = _bufB; targetBufL = _bufLB; targetBufR = _bufRB;
            _activeBuf = 1; // Следующий раз будем писать в A.
        } else {
            targetBuf = _bufA; targetBufL = _bufLA; targetBufR = _bufRA;
            _activeBuf = 0; // Следующий раз будем писать в B.
        }
        
        // Получаем сырой указатель на массив float'ов в C++ буфере.
        var rawPtr:cpp.RawPointer<cpp.Void> = untyped __cpp__('(void*)::_scope_get_buffer_ptr({0}, {1})', _doubleBufferRaw, readyIndex);
        var ptr:cpp.Pointer<cpp.Float32> = untyped __cpp__('(cpp::Float32*){0}', rawPtr);
        
        // ═══════════════════════════════════════════════════════════════════
        // DATA COPY (INTERLEAVED -> PLANAR)
        // ═══════════════════════════════════════════════════════════════════
        // Копируем данные из C++ (interleaved: L, R, L, R...) 
        // в Haxe массивы (planar: Mono, Left, Right).
        if (ptr != null) {
            var count = _bufferSize;
            for (i in 0...count) {
                var idx = i * 2;
                var l:Float = ptr[idx];
                var r:Float = ptr[idx + 1];
                
                // Моно микс: среднее значение левого и правого каналов.
                targetBuf[i] = (l + r) * 0.5;
                targetBufL[i] = l;
                targetBufR[i] = r;
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROPAGATION (BATCHED)
        // ═══════════════════════════════════════════════════════════════════
        // Передаем заполненные массивы в выходные контакты.
        var bufOut  = getOutput("buffer");
        var bufLOut = getOutput("bufferL");
        var bufROut = getOutput("bufferR");
        
        // Используем паттерн Batched Driver Update:
        // 1. setValueSilent (запись без тригера)
        // 2. propagateCurrentValue (уведомление подписчиков)
        if (bufOut  != null) { bufOut.setValueSilent(targetBuf);  bufOut.propagateCurrentValue(); }
        if (bufLOut != null) { bufLOut.setValueSilent(targetBufL); bufLOut.propagateCurrentValue(); }
        if (bufROut != null) { bufROut.setValueSilent(targetBufR); bufROut.propagateCurrentValue(); }
    }
    
    // =========================================================================
    // PULSE TIMERS
    // =========================================================================
    /**
    * Обновляет таймеры импульсов (tick, changed, clip).
    * Сбрасывает значения выходов в false по истечении PULSE_DURATION.
    * 
    * @param dt Delta time (время с прошлого кадра в секундах).
    */
    private function updatePulseTimers(dt:Float):Void
    {
        // Таймер "tick"
        if (_tickTimer > 0) { 
            _tickTimer -= dt; 
            if (_tickTimer <= 0) { 
                var c = getOutput("tick"); 
                if (c != null) c.value = false; 
            } 
        }
        // Таймер "changed"
        if (_changedTimer > 0) { 
            _changedTimer -= dt; 
            if (_changedTimer <= 0) { 
                var c = getOutput("changed"); 
                if (c != null) c.value = false; 
            } 
        }
        // Таймер "clip"
        if (_clipTimer > 0) { 
            _clipTimer -= dt; 
            if (_clipTimer <= 0) { 
                var c = getOutput("clip"); 
                if (c != null) c.value = false; 
            } 
        }
    }
    
    // =========================================================================
    // INPUT READING
    // =========================================================================
    /**
    * Читает значения входных контактов и обновляет параметры атома.
    * Вызывается в каждом кадре в update(dt).
    */
    private function readInputs():Void
    {
        var modeC    = getInput("mode");
        var quantumC = getInput("quantum");
        var gainC    = getInput("gain");
        var channelC = getInput("channel");
        var rateC    = getInput("rate");
        var bufSizeC = getInput("bufferSize");
        
        // Чтение режима (Mic / Loopback).
        if (modeC    != null && modeC.value    != null) _mode    = Std.int(modeC.value);
        // Чтение усиления.
        if (gainC    != null && gainC.value    != null) _gain    = gainC.value;
        // Чтение канала.
        if (channelC != null && channelC.value != null) _channel = Std.int(channelC.value);
        
        // Чтение частоты дискретизации (индекс в массиве SAMPLE_RATES).
        if (rateC != null && rateC.value != null)
        {
            var idx = Std.int(rateC.value);
            if (idx >= 0 && idx < SAMPLE_RATES.length) _sampleRateIdx = idx;
        }
        
        // Чтение шага квантования (с проверкой диапазона).
        if (quantumC != null && quantumC.value != null)
        {
            var q:Float = quantumC.value;
            if (q >= MIN_QUANTUM && q <= MAX_QUANTUM) _quantum = q;
        }
        
        // Чтение размера буфера (с проверкой диапазона 64..512).
        if (bufSizeC != null && bufSizeC.value != null)
        {
            var bs = Std.int(bufSizeC.value);
            if (bs >= 64 && bs <= 512 && bs != _bufferSize) _bufferSize = bs;
        }
    }
    
    // =========================================================================
    // UTILITY
    // =========================================================================
    /**
    * Обновляет выходной контакт "device" с названием устройства.
    * 
    * @param name Название устройства (например, "Loopback @48000Hz").
    */
    private function setDeviceNameOutput(name:String):Void
    {
        var c = getOutput("device");
        if (c != null) c.value = name;
    }
    
    /**
    * Перезапускает аудио-устройство.
    * Полезно при изменении параметров, требующих переинициализации 
    * (например, смена частоты дискретизации или режима).
    */
    public function restart():Void
    {
        closeDevice();
        _isFirstSample = true;
        _lastQuantum   = 0.0;
        _hasPending    = false;
        readInputs();
        openDevice();
    }
}
#end