package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
 * ============================================================================
 * OSCILLOSCOPE ATOM
 * ============================================================================
 * A specialized Driver acting as a terminal data sink for real-time waveform 
 * visualization. It consumes high-frequency audio/sample buffers from upstream 
 * atoms and bridges the gap between the computational graph and the UI layer.
 *
 * ARCHITECTURAL PRINCIPLES:
 * 1. Zero-GC Data Passing: Receives array references directly from upstream 
 *    drivers without copying data. This prevents Garbage Collection (GC) spikes 
 *    during real-time rendering of high-frequency audio streams.
 * 2. Event-Driven UI Decoupling: Uses the Impulsys event bus to notify the UI 
 *    layer about state changes. This keeps the atom graph clean and avoids 
 *    unnecessary tick recalculations in the reactive graph.
 * 3. Oscillation Bypass: Disables oscillation checks on the high-throughput 
 *    input contact to allow continuous data streaming without triggering 
 *    reactive graph feedback loops or infinite recalculation cycles.
 *
 * DATA & EVENT FLOW:
 * ┌──────────────────┐       ┌─────────────────────┐       ┌───────────────┐
 * │ Upstream Driver  │──────▶│  OscilloscopeAtom   │──────▶│  UI Widget    │
 * │ (e.g., MiniAudio)│  Ref  │    (Data Sink)      │ Event │  (Renderer)   │
 * └──────────────────┘       └─────────────────────┘       └───────────────┘
 *       Contact                     Impulsys
 *       (Array<Float>)      (OSCILOSCOPE_FRAME_READY)
 *                           (OSCILOSCOPE_SHAPE_CHANGED)
 * ============================================================================
 */
class OscilloscopeAtom extends Atom implements Driver
{
    // =========================================================================
    // CONSTANTS: VISUAL SHAPES
    // =========================================================================
    /** Прямоугольная форма отображения (классический осциллограф). */
    public static inline var SHAPE_RECTANGULAR:Int = 0;
    /** Квадратная форма отображения (равные пропорции осей X/Y). */
    public static inline var SHAPE_SQUARE:Int = 1;
    /** Круговая форма отображения (полярные координаты, Lissajous-like). */
    public static inline var SHAPE_CIRCULAR:Int = 2;
    
    // =========================================================================
    // STATE & DATA (ZERO-GC)
    // =========================================================================
    /**
    * Текущий буфер сэмплов для отрисовки.
    * 
    * ВАЖНО: Мы храним именно ссылку на массив из upstream драйвера, 
    * а не копируем его. Это реализует паттерн Zero-GC Data Passing, 
    * критичный для real-time аудио визуализации, так как аллокация 
    * нового массива каждый кадр вызвала бы фатальные фризы из-за GC.
    */
    private var _currentBuffer:Array<Float>;
    
    /**
    * Коэффициент масштабирования амплитуды (Zoom).
    * Определяет, насколько сильно растягивается волна по вертикали.
    */
    private var _zoom:Float = 1.0;
    
    /**
    * Текущая форма визуализации (SHAPE_RECTANGULAR, SHAPE_SQUARE, SHAPE_CIRCULAR).
    */
    private var _displayShape:Int = SHAPE_RECTANGULAR;
    
    /**
    * Коэффициент растяжения времени (Time Scale).
    * Определяет, сколько сэмплов помещается на экране по горизонтали.
    */
    private var _timeScale:Float = 1.0;

	
    // Регулирование частоты смены кадров
	private var _targetFrameRate:Float = 60.0;
	private var _decimation:Int = 1;
	private var _frameAccumulator:Float = 0.0;
	private var _lastEmitTime:Float = 0.0;
	
	public function getDecimation():Int return _decimation;
	public function getTargetFrameRate():Float return _targetFrameRate;
	
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    /**
    * Создает новый экземпляр осциллографа.
    * 
    * ОСОБЕННОСТЬ: У этого атома НЕТ выходных контактов (outputs = []).
    * Он является "терминальным узлом" (Data Sink). Его задача — не передавать 
    * данные дальше по графу, а визуализировать их или передавать в UI.
    * 
    * @param id Уникальный идентификатор атома.
    */
    public function new(id:String)
    {
        super(
            // === INPUTS (Параметры и сырые данные) ===
            [
                new Contact(null, INPUT, "in"),            // Сырой массив сэмплов от upstream драйвера
                new Contact(1.0, INPUT, "zoom"),           // Масштаб амплитуды
                new Contact(0, INPUT, "displayShape"),     // Форма виджета (0, 1, 2)
                new Contact(1.0, INPUT, "timeScale"),      // Масштаб времени
                new Contact(512, INPUT, "bufferSize"),     // Ожидаемый размер буфера (информационный)
				new Contact(60.0, INPUT, "frameRate"),	   // Целевая частота отрисовки (FPS)
				new Contact(1.0, INPUT, "decimation")      // Прореживание сэмплов (1 = все, 2 = каждый 2-й)


            ],
            // === OUTPUTS ===
            [], // Пустой массив. Осциллограф не генерирует данные для других атомов.
            null,
            id,
            "Oscilloscope",
            true
        );
        
        // ═══════════════════════════════════════════════════════════════════
        // OSCILLATION BYPASS (HIGH-FREQUENCY DATA PIPE)
        // ═══════════════════════════════════════════════════════════════════
        // Контакт "in" получает данные с частотой аудио-буфера (например, 40 раз в секунду).
        // Если не отключить защиту от осцилляции, реактивный граф может попытаться 
        // пересчитывать downstream атомы или зациклиться.
        // ignoreOscillation = true разрешает бесконечный поток изменений.
        // resetOscillation() сбрасывает счетчик, чтобы избежать ложных срабатываний при старте.
        var samplesContact = getInput("in");
        if (samplesContact != null) {
            samplesContact.ignoreOscillation = true;
            samplesContact.resetOscillation();
        }
    }
    
    // =========================================================================
    // LIFECYCLE
    // =========================================================================
    /**
    * Инициализация драйвера.
    * В данном случае не требуется, так как осциллограф не создает 
    * тяжелых ресурсов (вроде аудио-устройств) при старте.
    */
    override public function init():Void {}
    
    /**
    * Главный цикл обновления драйвера.
    * Вызывается каждый кадр из DriverManager.update(dt).
    * 
    * Здесь реализован паттерн Event-Driven UI Decoupling:
    * 1. Мы забираем ссылку на буфер (Zero-GC).
    * 2. Мы уведомляем UI через Impulsys, а не через propagateCurrentValue().
    * Это разгружает TickGenerator, так как UI обновляется асинхронно через события.
    * 
    * @param dt Delta time (время с прошлого кадра в секундах).
    */
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;
		
		// 1. Читаем параметры (включая frameRate и decimation)
		readParameters();
		
		// 2. Throttling по частоте кадров
		_frameAccumulator += dt;
		var targetInterval = 1.0 / _targetFrameRate;
		
		if (_frameAccumulator < targetInterval) return;  // ← Пропускаем кадр
		
		_frameAccumulator = 0.0;  // ← Сбрасываем accumulator
		
		// 3. Обработка входного потока данных (Zero-GC)
		var samplesContact = getInput("in");
		if (samplesContact != null && samplesContact.value != null)
		{
			if (Std.isOfType(samplesContact.value, Array)) {
				var samplesBuffer:Array<Float> = samplesContact.value;
				if (samplesBuffer != null && samplesBuffer.length > 0) {
					_currentBuffer = samplesBuffer;
					Impulsys.quickEmit(EventType.OSCILLOSCOPE_FRAME_READY, { atomId: this.id });
				}
			}
		}
	}
    
    // =========================================================================
    // PARAMETER READING & EDGE DETECTION
    // =========================================================================
    /**
    * Читает значения входных контактов, валидирует их и применяет.
    * Реализует паттерн Edge Detection (детекция фронта) для параметра displayShape:
    * событие генерируется ТОЛЬКО в момент изменения значения, а не каждый кадр.
    */
    private function readParameters():Void
    {
        // --- Чтение и климппинг Zoom ---
        var zoomContact = getInput("zoom");
        if (zoomContact != null && zoomContact.value != null) {
            _zoom = safeFloat(zoomContact.value, 1.0);
            // Ограничиваем диапазон, чтобы пользователь не мог "сломать" рендерер.
            if (_zoom < 0.1) _zoom = 0.1;
            if (_zoom > 1.5) _zoom = 1.5;
        }
        
        // --- Чтение Display Shape (с Edge Detection) ---
        var shapeContact = getInput("displayShape");
        if (shapeContact != null && shapeContact.value != null) {
            var newShape = safeInt(shapeContact.value, _displayShape);
            
            // Генерируем событие ТОЛЬКО если значение реально изменилось.
            // Это предотвращает лишние перерисовки UI и пересоздания шейдеров/геометрии.
            if (newShape != _displayShape) {
                _displayShape = newShape;
                Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
            }
        }
        
        // --- Чтение и климппинг Time Scale ---
        var timeScaleContact = getInput("timeScale");
        if (timeScaleContact != null && timeScaleContact.value != null) {
            _timeScale = safeFloat(timeScaleContact.value, 1.0);
            if (_timeScale < 0.1) _timeScale = 0.1;
            if (_timeScale > 1.5) _timeScale = 1.5;
        }
	    // --- Чтение frameRate ---
		var frameRateContact = getInput("frameRate");
		if (frameRateContact != null && frameRateContact.value != null) {
			var fr = safeFloat(frameRateContact.value, 60.0);
			if (fr >= 10.0 && fr <= 120.0) _targetFrameRate = fr;
		}
		
		// --- Чтение decimation ---
		var decimationContact = getInput("decimation");
		if (decimationContact != null && decimationContact.value != null) {
			var dec = safeInt(decimationContact.value, 1);
			if (dec >= 1 && dec <= 16) _decimation = dec;
		}
    }
    
    // =========================================================================
    // PUBLIC API (FOR UI WIDGETS)
    // =========================================================================
    // Эти методы используются виджетом (DeviceView) для получения состояния атома.
    // Виджет опрашивает их в своем цикле рендеринга.
    
    /** Возвращает ссылку на текущий буфер сэмплов (Zero-GC). */
    public function getBuffer():Array<Float> return _currentBuffer;
    
    /** Возвращает текущий коэффициент масштабирования амплитуды. */
    public function getZoom():Float return _zoom;
    
    /** Возвращает текущий тип отображаемой формы. */
    public function getDisplayShape():Int return _displayShape;
    
    /** Возвращает текущий коэффициент масштабирования времени. */
    public function getTimeScale():Float return _timeScale;
    
    /**
    * Программное изменение формы отображения.
    * Также триггерит событие для UI, чтобы виджет перестроил геометрию.
    * 
    * @param shape Новая форма (должна быть в диапазоне 0..2).
    */
    public function setDisplayShape(shape:Int):Void {
        if (shape >= SHAPE_RECTANGULAR && shape <= SHAPE_CIRCULAR) {
            _displayShape = shape;
            Impulsys.quickEmit(EventType.OSCILLOSCOPE_SHAPE_CHANGED, { atomId: this.id, shape: _displayShape });
        }
    }
    
    // =========================================================================
    // ROBUST TYPE COERCION (DEFENSIVE PROGRAMMING)
    // =========================================================================
    // Контакты в Haxe могут принимать значения типа Dynamic.
    // Значение может прийти из UI (где оно может быть String или Int), 
    // или из другого атома (где оно Float). Эти методы гарантируют 
    // безопасное приведение типов без падения приложения.
    
    /**
    * Безопасное преобразование Dynamic в Float.
    * Поддерживает Float, Int и String. Возвращает defaultVal при ошибке.
    * 
    * @param value Сырое значение из контакта.
    * @param defaultVal Значение по умолчанию.
    * @return Безопасно сконвертированное Float значение.
    */
    private function safeFloat(value:Dynamic, defaultVal:Float):Float {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Float)) return cast value;
        if (Std.isOfType(value, Int)) return cast(value, Int) * 1.0;
        if (Std.isOfType(value, String)) { 
            var f = Std.parseFloat(cast value); 
            return Math.isNaN(f) ? defaultVal : f; 
        }
        return defaultVal;
    }
    
    /**
    * Безопасное преобразование Dynamic в Int.
    * Поддерживает Int, Float и String. Возвращает defaultVal при ошибке.
    * 
    * @param value Сырое значение из контакта.
    * @param defaultVal Значение по умолчанию.
    * @return Безопасно сконвертированное Int значение.
    */
    private function safeInt(value:Dynamic, defaultVal:Int):Int {
        if (value == null) return defaultVal;
        if (Std.isOfType(value, Int)) return cast value;
        if (Std.isOfType(value, Float)) return Std.int(cast(value, Float));
        if (Std.isOfType(value, String)) { 
            var i = Std.parseInt(cast value); 
            return i == null ? defaultVal : i; 
        }
        return defaultVal;
    }
    
    // =========================================================================
    // CLEANUP
    // =========================================================================
    /**
    * Освобождение ресурсов и отмена регистрации.
    * Обнуляем ссылку на буфер, чтобы GC мог собрать его, если upstream драйвер 
    * уже не держит на него ссылку (хотя обычно upstream драйвер управляет буфером сам).
    */
    override public function dispose():Void {
        DriverManager.getInstance().unregister(this.id);
        _currentBuffer = null;
        super.dispose();
    }
}