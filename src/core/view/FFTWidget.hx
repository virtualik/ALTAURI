package core.view;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import library.electro.FFTAtom;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     FFT WIDGET v2.0                                       ║
 * ║                     (Logarithmic Spectrum Analyzer)                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  v2.0 Changes:                                                            ║
 * ║  - Replaced linear bin grouping with LOGARITHMIC frequency mapping.       ║
 * ║  - Each bar now represents an equal logarithmic frequency range           ║
 * ║    (e.g., 20-40Hz, 40-80Hz, 80-160Hz...), matching human hearing.         ║
 * ║  - Added proper background clearing to prevent visual artifacts.          ║
 * ║  - Improved bar spacing and color gradient thresholds.                    ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        LOGARITHMIC MAPPING                                ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Frequency Range: 20 Hz ───────────────────────────────► 20,000 Hz        ║
 * ║  (Log Scale)      [20-40][40-80][80-160]...[10k-20k]                      ║
 * ║                                                                           ║
 * ║  For each bar:                                                            ║
 * ║    1. Calculate freqStart and freqEnd using log interpolation             ║
 * ║    2. Convert frequencies to FFT bin indices                              ║
 * ║    3. Find the MAXIMUM dB value within that bin range                     ║
 * ║    4. Draw the bar                                                        ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     FFT WIDGET v1.0                                       ║
 * ║                     (Real-Time Spectrum Analyzer Visualization)           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Visual component (Face) for the FFTAtom.                                 ║
 * ║  Renders a real-time bar-chart spectrum analyzer using dBFS data.         ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        RENDERING PIPELINE                                 ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  [FFTAtom] ──(Impulsys)──► FFT_SPECTRUM_READY                       │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ▼                                                           │  ║
 * ║  │  [FFTWidget.onFrameReady()]                                         │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ├─► _hasNewFrame = true (Dirty Flag)                        │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ▼                                                           │  ║
 * ║  │  [OpenFL ENTER_FRAME] ──► redrawSpectrum()                          │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ├─► Read spectrumDB from Atom (Zero-GC reference)           │  ║
 * ║  │         ├─► Map dBFS [-120..0] to [0..1.0]                          │  ║
 * ║  │         ├─► Draw bars directly to widget.graphics (No Sprite alloc) │  ║
 * ║  │         └─► Apply Green -> Yellow -> Red gradient                   │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     dBFS TO VISUAL MAPPING                                ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  dBFS Value   │  Normalized  │  Bar Height  │  Color                      ║
 * ║  ─────────────┼──────────────┼──────────────┼────────────────────         ║
 * ║  0 dB (Max)   │  1.00        │  100%        │  ██████████ Red             ║
 * ║  -6 dB        │  0.95        │  95%         │  █████████░ Red             ║
 * ║  -12 dB       │  0.90        │  90%         │  ████████░░ Yellow          ║
 * ║  -24 dB       │  0.80        │  80%         │  ██████░░░░ Yellow          ║
 * ║  -48 dB       │  0.60        │  60%         │  ████░░░░░░ Green           ║
 * ║  -72 dB       │  0.40        │  40%         │  ██░░░░░░░░ Green           ║
 * ║  -96 dB       │  0.20        │  20%         │  █░░░░░░░░░ Green           ║
 * ║  -120 dB (Min)│  0.00        │  0%          │  ░░░░░░░░░░ Empty           ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class FFTWidget extends DeviceView
{
	// =========================================================================
	// CONFIGURATION (Внешние параметры и цвета)
	// =========================================================================
	/** Базовая ширина виджета. */
	public var widgetWidth:Float = 300;
	/** Базовая высота виджета. */
	public var widgetHeight:Float = 150;
	
	/** Цвет фона виджета (темный). */
	private var _colorBg:Int = 0x0a0a12;
	/** Цвет сетки (едва заметный). */
	private var _colorGrid:Int = 0x1a2a1a;
	
	/** Цвета градиента для столбиков (Зеленый -> Желтый -> Красный). */
	private var _colorGreen:Int = 0x00CC44;
	private var _colorYellow:Int = 0xCCAA00;
	private var _colorRed:Int = 0xCC2222;
	
	/** Целевое количество столбиков для визуализации (логарифмических полос). */
	private var _targetBars:Int = 32;
	
	// =========================================================================
	// STATE & DATA (Zero-GC)
	// =========================================================================
	/** Ссылка на связанный атом FFT для чтения данных. */
	private var _fftAtom:FFTAtom;
	
	/** Флаг "грязного" кадра. Устанавливается при получении события от атома. */
	private var _hasNewFrame:Bool = false;
	
	/** Флаг блокировки рендеринга (защита от рекурсии). */
	private var _isRendering:Bool = false;

	private var _previousBarHeights:Array<Float>;
	private var _smoothingFactor:Float = 0.7; // 0.0 = нет сглаживания, 1.0 = максимальное сглаживание

	// =========================================================================
	// CONSTRUCTOR (Конструктор)
	// =========================================================================
	/**
	 * Создает виджет спектрального анализатора и связывает его с атомом.
	 * 
	 * @param atom Базовый атом (должен быть FFTAtom или Assembly, содержащий его).
	 */
	public function new(atom:Atom)
	{
		super(atom);
		
		// --- Разрешение ссылки на FFTAtom ---
		if (Std.isOfType(atom, FFTAtom)) {
			_fftAtom = cast(atom, FFTAtom);
		}
		else if (Std.isOfType(atom, Assembly)) {
			var asm = cast(atom, Assembly);
			for (internalAtom in asm.internalAtoms) {
				if (Std.isOfType(internalAtom, FFTAtom)) {
					_fftAtom = cast(internalAtom, FFTAtom);
					break;
				}
			}
		}
		
		// --- Инициализация UI и подписок ---
		buildUI();
		
		// Подписываемся на глобальные события Impulsys
		Impulsys.subscribeToImpulse(EventType.FFT_SPECTRUM_READY, onFrameReady);
		
		// Синхронизируем отрисовку с частотой обновления экрана (ENTER_FRAME).
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}
	
	// =========================================================================
	// WIDGET SIZE (Размеры виджета)
	// =========================================================================
	/**
	 * Возвращает текущие габариты виджета для системы компоновки (Layout Manager).
	 */
	override public function getWidgetSize():{width:Float, height:Float} {
		return {width: widgetWidth, height: widgetHeight};
	}
	
	// =========================================================================
	// UI CONSTRUCTION (Построение интерфейса)
	// =========================================================================
	/**
	 * Оркестрирует создание всех визуальных компонентов.
	 */
	private function buildUI():Void
	{
		// Рисуем статический фон
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();
		
		// Рамка
		graphics.lineStyle(2, 0x333355);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
	}
	
	// =========================================================================
	// LIFECYCLE & EVENT HANDLERS (Жизненный цикл и обработчики событий)
	// =========================================================================
	/**
	 * Обработчик события FFT_SPECTRUM_READY.
	 * Устанавливает флаг _hasNewFrame, чтобы отрисовка произошла в следующем ENTER_FRAME.
	 */
	private function onFrameReady(impulse:Impulse):Void
	{
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_fftAtom == null || impulse.data.atomId != _fftAtom.id) return;
		
		_hasNewFrame = true;
	}
	
	/**
	 * Главный цикл рендеринга, привязанный к частоте обновления экрана (ENTER_FRAME).
	 */
	private function onEnterFrame(e:Event):Void
	{
		if (_hasNewFrame && !_isRendering) {
			_hasNewFrame = false;
			redrawSpectrum();
		}
	}
	
	// =========================================================================
	// REDRAW LOGIC (Логика перерисовки спектра)
	// =========================================================================
	/**
	 * Основная функция отрисовки спектра.
	 * v2.0: Использует ЛОГАРИФМИЧЕСКОЕ разбиение частотного диапазона.
	 * 
	 * Вместо равномерного распределения бинов, мы делим диапазон от minFreq 
	 * до maxFreq на равные логарифмические интервалы. Для каждого интервала 
	 * находим максимальное значение dB и рисуем столбик.
	 */
	private function redrawSpectrum():Void
	{
		if (_fftAtom == null) return;
		
		var spectrumDB:Array<Float> = _fftAtom.getSpectrumDB();
		if (spectrumDB == null || spectrumDB.length == 0) return;
		
		_isRendering = true;
		
		var sampleRate = _fftAtom.getSampleRate();
		var fftSize = _fftAtom.getFFTSize();
		var binCount = spectrumDB.length; // Обычно fftSize / 2
		var freqResolution = sampleRate / fftSize; // Гц на бин
		
		// Диапазон частот для отображения (20 Гц - 20 кГц)
		var minFreq = 18.0;
		var maxFreq = sampleRate / 2.0; // Частота Найквиста
		
		// Защита от log(0)
		if (minFreq <= 0) minFreq = 1.0;
		
		var numBars = _targetBars;
		var barWidth = widgetWidth / numBars;
		var maxHeight = widgetHeight;
		
		// === ИНИЦИАЛИЗАЦИЯ МАССИВА СГЛАЖИВАНИЯ ===
		if (_previousBarHeights == null || _previousBarHeights.length != numBars)
		{
			_previousBarHeights = [];
			for (i in 0...numBars) _previousBarHeights.push(0);
		}
		
		// === ОЧИСТКА И ФОН ===
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();
		
		// Рисуем сетку (горизонтальные линии)
		graphics.lineStyle(1, _colorGrid, 0.5);
		var gridSteps = 4;
		for (i in 1...gridSteps) {
			var y = (maxHeight / gridSteps) * i;
			graphics.moveTo(0, y);
			graphics.lineTo(widgetWidth, y);
		}
		
		// === ЛОГАРИФМИЧЕСКОЕ РАЗБИЕНИЕ ===
		var logMin = Math.log(minFreq) / Math.log(10);
		var logMax = Math.log(maxFreq) / Math.log(10);
		var logRange = logMax - logMin;
		
		var currentBarHeights:Array<Float> = [];
		
		for (i in 0...numBars)
		{
			// Вычисляем границы частот для текущего столбика в логарифмической шкале
			var tStart = i / numBars;
			var tEnd = (i + 1) / numBars;
			
			var freqStart = Math.pow(10, logMin + tStart * logRange);
			var freqEnd = Math.pow(10, logMin + tEnd * logRange);
			
			// Переводим частоты в индексы бинов FFT
			var binStart = Std.int(freqStart / freqResolution);
			var binEnd = Std.int(freqEnd / freqResolution);
			
			// Ограничиваем диапазон индексов
			if (binStart < 0) binStart = 0;
			if (binEnd >= binCount) binEnd = binCount - 1;
			if (binStart > binEnd) binEnd = binStart; // На высоких частотах бины могут сливаться
			
			// Находим МАКСИМАЛЬНОЕ значение dB в этом диапазоне бинов
			var maxDB = -50.0;
			for (b in binStart...binEnd + 1)
			{
				if (spectrumDB[b] > maxDB) {
					maxDB = spectrumDB[b];
				}
			}
			
			// Маппинг dBFS [-120..0] -> Normalized [0.0..1.0]
			// диапазон -120..0 dBFS):
			// 1. Сжатый диапазон (-120..0 dBFS)
			var minDB:Float = -10.0;
			var normalized = (maxDB - minDB) / (0.0 - minDB);
			if (normalized < 0) normalized = 0;
			if (normalized > 1) normalized = 1;

			// 2. Степенное сжатие
			var compressed = Math.pow(normalized, 0.9);

			// 3. Noise gate
			var noiseGate:Float = 0.03;
			if (compressed < noiseGate) compressed = 0;

			var targetHeight = compressed * maxHeight;
			
			// === СГЛАЖИВАНИЕ ===
			var smoothedHeight = _previousBarHeights[i] * _smoothingFactor + targetHeight * (1.0 - _smoothingFactor);
			currentBarHeights.push(smoothedHeight);
			
			var barHeight = smoothedHeight;
			var x = i * barWidth;
			var y = maxHeight - barHeight;
			
			// Рисуем столбик (если он виден)
			if (barHeight > 0.5) {
				var color = getColorForLevel(normalized);
				graphics.beginFill(color);
				// Рисуем с небольшим отступом (gap) для красоты
				graphics.drawRect(x + 1, y, barWidth - 2, barHeight);
				graphics.endFill();
			}
		}
		
		// Сохраняем текущие высоты для следующего кадра
		_previousBarHeights = currentBarHeights;
		
		_isRendering = false;
	}
	
	/**
	 * Возвращает цвет для столбика в зависимости от нормализованного уровня (0.0 - 1.0).
	 * Реализует градиент: Зеленый -> Желтый -> Красный.
	 * 
	 * @param level Нормализованный уровень (0.0 = тишина, 1.0 = 0 dBFS).
	 * @return Цвет в формате Int (HEX).
	 */
	private function getColorForLevel(level:Float):Int
	{
		if (level >= 0.85) {
			return _colorRed;      // > -18 dBFS (Красный)
		} else if (level >= 0.60) {
			return _colorYellow;   // > -48 dBFS (Желтый)
		} else {
			return _colorGreen;    // < -48 dBFS (Зеленый)
		}
	}
	
	// =========================================================================
	// CLEAR & DISPOSE (Очистка и освобождение ресурсов)
	// =========================================================================
	/**
	 * Очищает экран от нарисованного спектра.
	 */
	public function clearDisplay():Void
	{
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();
	}
	
	/**
	 * Освобождение ресурсов виджета.
	 * Отписывается от событий Impulsys, удаляет слушатели ENTER_FRAME
	 * и обнуляет ссылки для помощи Garbage Collector'у.
	 */
	override public function dispose():Void
	{
		removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		Impulsys.removeImpulse(EventType.FFT_SPECTRUM_READY, onFrameReady);
		
		_fftAtom = null;
		
		super.dispose();
	}
}