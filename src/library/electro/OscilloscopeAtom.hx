package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.logic.TickGenerator;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * OSCILLOSCOPE ATOM v4.0 (Time-Based Sampling)
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * АРХИТЕКТУРА: "ATOM IS DATABANK & COMPUTE CORE"
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * OscilloscopeAtom - это активный атом-драйвер с тактированием от TickGenerator.
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OscilloscopeAtom                                                      │
 * │                                                                         │
 * │   А) COMPUTE MODULE:                                                    │
 * │   ─────────────────                                                     │
 * │   update(dt) {                                                          │
 * │       1. Аккумулируем время до следующего сэмпла                        │
 * │       2. Вычисляем интервал: sampleInterval = timeScale / BUFFER_SIZE   │
 * │       3. Если накопилось достаточно времени → takeSample()              │
 * │       4. takeSample() читает текущее значение входа "in"                │
 * │       5. Проверяем триггер и записываем в буфер                         │
 * │   }                                                                     │
 * │                                                                         │
 * │   Б) DATABANK:                                                          │
 * │   ─────────────                                                         │
 * │   private var _buffer:Array<Float>;        // Кольцевой буфер 512       │
 * │   private var _writeIndex:Int = 0;         // Текущая позиция записи    │
 * │   private var _samplesCollected:Int = 0;   // Сколько сэмплов собрано   │
 * │   private var _totalSamples:Int = 0;       // Общий счётчик             │
 * │   private var _sampleAccumulator:Float = 0;// Накопитель времени        │
 * │   private var _timeScale:Float = 1.0;      // секунд на весь экран      │
 * │   private var _triggerLevel:Float = 0.0;   // Уровень триггера          │
 * │   private var _triggerEdge:Int = 0;        // 0=rising, 1=falling       │
 * │   private var _triggerMode:Int = 0;        // 0=auto, 1=normal, 2=single│
 * │   private var _triggerArmed:Bool = true;   // вооружён ли триггер       │
 * │                                                                         │
 * │   public function getBuffer():Array<Float>  // API для DeviceView       │
 * │   public function getWriteIndex():Int                                   │
 * │   public function getSamplesCollected():Int                             │
 * │   public function getSamplingStatus() // Статус сэмплирования           │
 * │                                                                         │
 * │   В) FACE (DeviceView):                                                 │
 * │   ──────────────────                                                    │
 * │   OscilloscopeWidget читает из Databank:                                │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │ var buffer = oscAtom.getBuffer();                               │   │
 * │   │ var idx = oscAtom.getWriteIndex();                              │   │
 * │   │ drawWave(buffer, idx, oscAtom.getSamplesCollected());           │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Headless Mode:                                                        │
 * │   ──────────────                                                        │
 * │   Атом работает автономно - сэмплирует вход по времени.                 │
 * │   DeviceView не нужен для работы.                                       │
 * │   Данные могут быть сохранены через getPersistentState().               │
 * │                                                                         │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │   ТАКТИРОВАНИЕ ОТ TICKGENERATOR                                         │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │                                                                         │
 * │   TickGenerator (60 Hz)                                                 │
 * │        │                                                                │
 * │        ├──► SignalGenerator.update(dt) - генерирует сигнал              │
 * │        │                                                                │
 * │        └──► OscilloscopeAtom.update(dt) - сэмплирует вход               │
 * │                                                                         │
 * │   Оба используют один fixedDeltaTime для консистентного времени!        │
 * │                                                                         │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │   РАСЧЁТ ИНТЕРВАЛОВ                                                     │
 * │   ═══════════════════════════════════════════════════════════════════   │
 * │                                                                         │
 * │   timeScale = 0.01 (10ms на экран)                                      │
 * │   BUFFER_SIZE = 512                                                     │
 * │   sampleInterval = 0.01 / 512 = 19.5μs                                  │
 * │   sampleRate = 512 / 0.01 = 51.2 kHz                                    │
 * │                                                                         │
 * │   Для синусоиды 440 Hz:                                                 │
 * │   - Период = 2.27ms                                                     │
 * │   - Сэмплов на период = 51.2kHz / 440Hz ≈ 116 сэмплов                   │
 * │   - Достаточно для плавной волны!                                       │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * v4.0 Changes:
 * - ARCHITECTURE: Time-based sampling instead of event-driven
 * - Oscilloscope is now an active Driver (isActive = true)
 * - Uses TickGenerator.update(dt) for precise timing
 * - Sample interval calculated from timeScale / BUFFER_SIZE
 * - Trigger logic works with time-based sampling
 * - Input contact ignores oscillation for fast signals
 * - Sampling status API for debugging
 *
 * v3.0 Changes:
 * - REMOVED: Double buffering (Input Buffer). No more waiting for 1024 samples.
 * - ARCHITECTURE: Direct write to ring buffer.
 * - RESULT: Instant visualization. Zero latency.
 * - EFFICIENCY: Single array allocation.
 *
 * v2.3 Changes (Performance & Stability):
 * - FIXED: Reduced INPUT_BUFFER_SIZE to 512 to match display buffer.
 * - FIXED: flushInputBufferToDisplay() loop now correctly copies exactly
 *   BUFFER_SIZE samples, preventing double-overwrite artifacts.
 * - IMPROVED: processInput() is more robust handling mixed data types.
 *
 * v2.2 Changes:
 * - ADDED: Display Shape property (RECTANGULAR, SQUARE, CIRCULAR).
 *
 * v2.1 Changes:
 * - FIXED: addSamples() now increments _totalSamples per sample added.
 * - FIXED: getPersistentState() merges with super result.
 * - FIXED: restoreState() calls super.restoreState() first.
 * - FIXED: processInput() comment clarifies Float/Int order.
 */
class OscilloscopeAtom extends Atom implements Driver
{
    // =========================================================================
    // CONFIGURATION
    // =========================================================================
    // Размер буфера = ширина экрана осциллографа в пикселях.
    // 512 точек достаточно для плавной линии.
    private static inline var BUFFER_SIZE:Int = 512;
    
    // Минимальный интервал сэмпла (защита от слишком высокой частоты)
    private static inline var MIN_SAMPLE_INTERVAL:Float = 0.00001; // 10μs
    
    // =========================================================================
    // DISPLAY SHAPE ENUM
    // =========================================================================
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    public static inline var SHAPE_SQUARE:Int = 1;
    public static inline var SHAPE_CIRCULAR:Int = 2;
    
    // =========================================================================
    // DATABANK
    // =========================================================================
    private var _buffer:Array<Float>;
    // Индекс записи в кольцевом буфере
    private var _writeIndex:Int = 0;
    // Счетчик собранных сэмплов (для логики "ожидание сигнала")
    private var _samplesCollected:Int = 0;
    private var _totalSamples:Int = 0;
    private var _lastValue:Float = 0.0;
    private var _displayShape:Int = SHAPE_RECTANGULAR;
    
    // =========================================================================
    // TIME BASE & TRIGGER
    // =========================================================================
    private var _timeScale:Float = 1.0;      // секунд на весь экран (ширина буфера)
    private var _triggerLevel:Float = 0.0;
    private var _triggerEdge:Int = 0;        // 0=rising, 1=falling
    private var _triggerMode:Int = 0;        // 0=auto, 1=normal, 2=single
    private var _triggerArmed:Bool = true;   // вооружён ли триггер (для single/normal)
    
    // =========================================================================
    // SAMPLING STATE (v4.0)
    // =========================================================================
    private var _sampleAccumulator:Float = 0.0;  // Накопитель времени для сэмплов
    private var _lastInputValue:Float = 0.0;     // Последнее прочитанное значение входа
    private var _isSampling:Bool = false;        // Флаг активного сэмплирования
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            [
                new Contact(null, INPUT, "in"),
                new Contact(1.0, INPUT, "timeScale"),
                new Contact(0.0, INPUT, "triggerLevel"),
                new Contact(0, INPUT, "triggerEdge"),
                new Contact(0, INPUT, "triggerMode")
            ],
            [], // нет выходов
            null,
            id,
            "Oscilloscope",
            true  // v4.0: isActive = true (регистрируемся в DriverManager)
        );
        
        var inContact = getInput("in");
        if (inContact != null) {
            inContact.ignoreOscillation = true;  // v4.0: Игнорируем осцилляцию для быстрых сигналов
            inContact.resetOscillation();
        }
        
        // Инициализация буфера нулями
        _buffer = [];
        for (i in 0...BUFFER_SIZE) {
            _buffer.push(0.0);
        }
        
        trace('OscilloscopeAtom: Created (id: $id, bufferSize: $BUFFER_SIZE, active: true)');
    }
    
    // =========================================================================
    // LIFECYCLE - Driver Interface
    // =========================================================================
    /**
     * Инициализация драйвера.
     */
    override public function init():Void
    {
        _sampleAccumulator = 0.0;
        _lastInputValue = 0.0;
        _isSampling = true;
        _triggerArmed = true;
        trace('OscilloscopeAtom: Initialized (sampling active)');
    }
    
    /**
     * Обновление каждый кадр - основная логика сэмплирования.
     * Вызывается из DriverManager.update().
     * 
     * v4.0: Time-based sampling вместо event-driven
     * 
     * @param dt Delta time в секундах
     */
    override public function update(dt:Float):Void
    {
        if (_isDisposed || !_isSampling) return;
        
        // 1. Считываем параметры (timeScale, trigger и т.д.)
        readParameters();
        
        // 2. Вычисляем интервал сэмпла
        var sampleInterval = _timeScale / BUFFER_SIZE;
        if (sampleInterval < MIN_SAMPLE_INTERVAL) {
            sampleInterval = MIN_SAMPLE_INTERVAL;
        }
        
        // 3. Аккумулируем время
        _sampleAccumulator += dt;
        
        // 4. Если накопилось достаточно времени - берём сэмпл(ы)
        while (_sampleAccumulator >= sampleInterval) {
            takeSample();
            _sampleAccumulator -= sampleInterval;
        }
        
        // 5. Авто-вооружение триггера в auto mode
        if (_triggerMode == 0 && !_triggerArmed && _samplesCollected >= BUFFER_SIZE) {
            _triggerArmed = true;
        }
    }
    
    /**
     * Освобождение ресурсов.
     */
    override public function dispose():Void
    {
        DriverManager.getInstance().unregister(this.id);
        _buffer = null;
        super.dispose();
        trace('OscilloscopeAtom: Disposed (total samples: $_totalSamples)');
    }
    
    // =========================================================================
    // PARAMETER READING
    // =========================================================================
    /**
     * Считать значения с входных контактов параметров.
     */
    private function readParameters():Void
    {
        // timeScale
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null) {
            var ts = _safeFloat(timeScaleContact.value, _timeScale);
            if (ts >= 0.001 && ts <= 10.0) {
                _timeScale = ts;
            }
        }
        
        // triggerLevel
        var triggerLevelContact = getInput("triggerLevel");
        if (triggerLevelContact != null && triggerLevelContact.value != null) {
            _triggerLevel = _safeFloat(triggerLevelContact.value, 0.0);
            if (_triggerLevel < -1.0) _triggerLevel = -1.0;
            if (_triggerLevel > 1.0) _triggerLevel = 1.0;
        }
        
        // triggerEdge
        var triggerEdgeContact = getInput("triggerEdge");
        if (triggerEdgeContact != null && triggerEdgeContact.value != null) {
            _triggerEdge = _safeInt(triggerEdgeContact.value, 0);
        }
        
        // triggerMode
        var triggerModeContact = getInput("triggerMode");
        if (triggerModeContact != null && triggerModeContact.value != null) {
            _triggerMode = _safeInt(triggerModeContact.value, 0);
            if (_triggerMode == 2) _triggerArmed = true; // single mode: re-arm
        }
    }
    
    // =========================================================================
    // EVENT HANDLING (for parameter changes only)
    // =========================================================================
    /**
     * Обработка изменений контактов.
     * v4.0: Только для параметров, не для сэмплирования!
     */
    override public function onContactChanged(c:Contact):Void
    {
        if (_isDisposed) return;
        
        // v4.0: Игнорируем "in" для сэмплирования - оно происходит в update()
        // Но обрабатываем изменения параметров
        switch (c.name) {
            case "timeScale":
                _timeScale = _safeFloat(c.value, 1.0);
                if (_timeScale < 0.001) _timeScale = 0.001;
            case "triggerLevel":
                _triggerLevel = _safeFloat(c.value, 0.0);
                if (_triggerLevel < -1.0) _triggerLevel = -1.0;
                if (_triggerLevel > 1.0) _triggerLevel = 1.0;
            case "triggerEdge":
                _triggerEdge = _safeInt(c.value, 0);
            case "triggerMode":
                _triggerMode = _safeInt(c.value, 0);
                if (_triggerMode == 2) _triggerArmed = true; // single mode: re-arm
            case "in":
                // v4.0: Игнорируем для сэмплирования, но сохраняем последнее значение
                // на случай если update() не успевает прочитать
                if (c.value != null) {
                    _lastInputValue = _toFloat(c.value, 0.0);
                }
        }
    }
    
    // =========================================================================
    // SAMPLING LOGIC (v4.0)
    // =========================================================================
    /**
     * Взять один сэмпл с входа.
     * Вызывается из update() когда накопилось достаточно времени.
     */
    private function takeSample():Void
    {
        // 1. Читаем текущее значение входа
        var inContact = getInput("in");
        var currentValue:Float = 0.0;
        
        if (inContact != null && inContact.value != null) {
            currentValue = _toFloat(inContact.value, _lastInputValue);
        } else {
            currentValue = _lastInputValue;
        }
        
        // Обновляем последнее значение
        _lastInputValue = currentValue;
        
        // 2. Логика триггера
        if (_triggerMode != 0 && !_triggerArmed) {
            // Не вооружены — игнорируем сэмплы (ждём вооружения)
            return;
        }
        
        // Проверка на запуск по фронту
        if (_triggerMode != 0 && _triggerArmed) {
            var triggered = false;
            
            if (_triggerEdge == 0) { // rising
                if (_lastValue < _triggerLevel && currentValue >= _triggerLevel) {
                    triggered = true;
                }
            } else { // falling
                if (_lastValue > _triggerLevel && currentValue <= _triggerLevel) {
                    triggered = true;
                }
            }
            
            if (triggered) {
                _triggerArmed = false;
                // Очищаем буфер и начинаем запись с текущего сэмпла
                clearBuffer();
                _buffer[0] = currentValue;
                _writeIndex = 1;
                _samplesCollected = 1;
                _lastValue = currentValue;
                _totalSamples++;
                return;
            }
        }
        
        // 3. Запись в буфер (auto mode или когда триггер не сработал)
        _buffer[_writeIndex] = currentValue;
        _writeIndex = (_writeIndex + 1) % BUFFER_SIZE;
        if (_samplesCollected < BUFFER_SIZE) {
            _samplesCollected++;
        }
        _lastValue = currentValue;
        _totalSamples++;
    }
    
    // =========================================================================
    // PUBLIC API
    // =========================================================================
    public function getBuffer():Array<Float> return _buffer;
    public function getWriteIndex():Int return _writeIndex;
    public function getSamplesCollected():Int return _samplesCollected;
    public function getTotalSamples():Int return _totalSamples;
    public function getLastValue():Float return _lastValue;
    public function getBufferSize():Int return BUFFER_SIZE;
    public function getDisplayShape():Int return _displayShape;
    
    public function setDisplayShape(shape:Int):Void
    {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR) {
            _displayShape = shape;
        }
    }
    
    /**
     * v4.0: Статус сэмплирования для отладки
     */
    public function getSamplingStatus():{
        sampleRate:Float,
        timePerSample:Float,
        isTriggered:Bool,
        accumulator:Float
    } {
        var sampleInterval = _timeScale / BUFFER_SIZE;
        return {
            sampleRate: 1.0 / sampleInterval,
            timePerSample: sampleInterval,
            isTriggered: !_triggerArmed,
            accumulator: _sampleAccumulator
        };
    }
    
    /**
     * v4.0: Включить/выключить сэмплирование
     */
    public function setSampling(active:Bool):Void
    {
        _isSampling = active;
        if (active) {
            _sampleAccumulator = 0.0;
            _triggerArmed = true;
        }
    }
    
    public function clearBuffer():Void
    {
        _writeIndex = 0;
        _samplesCollected = 0;
        // _totalSamples не сбрасываем - это общая статистика
        _lastValue = 0.0;
        for (i in 0...BUFFER_SIZE) {
            _buffer[i] = 0.0;
        }
    }
    
    // =========================================================================
    // TIME SCALE & TRIGGER API
    // =========================================================================
    public function getTimeScale():Float return _timeScale;
    public function setTimeScale(scale:Float):Void { 
        _timeScale = Math.max(0.001, scale); 
    }
    
    public function getTriggerLevel():Float return _triggerLevel;
    public function setTriggerLevel(level:Float):Void { 
        _triggerLevel = Math.max(-1.0, Math.min(1.0, level)); 
    }
    
    public function getTriggerEdge():Int return _triggerEdge;
    public function setTriggerEdge(edge:Int):Void { 
        _triggerEdge = edge; 
    }
    
    public function getTriggerMode():Int return _triggerMode;
    public function setTriggerMode(mode:Int):Void {
        _triggerMode = mode;
        if (mode == 2) _triggerArmed = true;
    }
    
    public function rearm():Void { 
        _triggerArmed = true; 
    }
    
    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
    override public function getPersistentState():Dynamic
    {
        var base = super.getPersistentState();
        var result = {
            displayShape: _displayShape,
            timeScale: _timeScale,
            triggerLevel: _triggerLevel,
            triggerEdge: _triggerEdge,
            triggerMode: _triggerMode,
            totalSamples: _totalSamples
        };
        if (base != null && Reflect.hasField(base, "isLogic")) {
            Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
        }
        return result;
    }
    
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        super.restoreState(state);
        
        if (state.timeScale != null) _timeScale = state.timeScale;
        if (state.triggerLevel != null) _triggerLevel = state.triggerLevel;
        if (state.triggerEdge != null) _triggerEdge = state.triggerEdge;
        if (state.triggerMode != null) {
            _triggerMode = state.triggerMode;
            if (_triggerMode == 2) _triggerArmed = true;
        }
        if (state.displayShape != null) _displayShape = state.displayShape;
        if (state.totalSamples != null) _totalSamples = state.totalSamples;
        
        // Повторно настраиваем контакт
        var inContact = getInput("in");
        if (inContact != null) {
            inContact.ignoreOscillation = true;
            inContact.resetOscillation();
        }
        
        trace('OscilloscopeAtom: Restored state (timeScale: $_timeScale, totalSamples: $_totalSamples)');
    }
    
    // =========================================================================
    // UTILITY FUNCTIONS
    // =========================================================================
    private function _safeFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, String)) {
            var f = Std.parseFloat(cast value);
            return Math.isNaN(f) ? defaultVal : f;
        }
        return defaultVal;
    }
    
    private function _safeInt(value:Dynamic, defaultVal:Int):Int {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Int)) return cast value;
        if (Std.isOfType(value, Float)) return Std.int(cast(value, Float));
        if (Std.isOfType(value, String)) {
            var i = Std.parseInt(cast value);
            return i == null ? defaultVal : i;
        }
        return defaultVal;
    }
    
    private function _toFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, Bool)) return cast(value, Bool) ? 1.0 : 0.0;
        if (Std.isOfType(value, String)) {
            var f = Std.parseFloat(cast value);
            return Math.isNaN(f) ? defaultVal : f;
        }
        return defaultVal;
    }
}