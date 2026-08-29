package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     FFT ATOM v1.1                                         ║
* ║                     (Real-Time Spectrum Analyzer)                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Драйвер спектрального анализа на базе алгоритма Cooley-Tukey Radix-2.    ║
* ║  Принимает буфер сэмплов от MiniAudioAtom, выполняет FFT, и выдаёт        ║
* ║  спектральные данные (амплитуды, dB, bass/mid/treble).                    ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     FFTAtom                                         │  ║
* ║  │                                                                     │  ║
* ║  │  A) COMPUTE MODULE (Main Thread — update(dt)):                      │  ║
* ║  │     ─────────────────────────────────────────                       │  ║
* ║  │     1. readInputs()                                                 │  ║
* ║  │        - buffer, windowSize, windowType, sampleRate                 │  ║
* ║  │        - targetBars, minFreq, maxFreq, minDB, maxDB                 │  ║
* ║  │        - compressionExponent, noiseGate, gain, mode                 │  ║
* ║  │                                                                     │  ║
* ║  │     2. processFFT()                                                 │  ║
* ║  │        - Apply window function (Hann/Hamming)                       │  ║
* ║  │        - Execute Cooley-Tukey FFT                                   │  ║
* ║  │        - Extract magnitudes                                         │  ║
* ║  │        - Convert to dBFS                                            │  ║
* ║  │        - Calculate bass/mid/treble energy                           │  ║
* ║  │                                                                     │  ║
* ║  │     3. Batched Driver Update Pattern                                │  ║
* ║  │        - setValueSilent() для всех выходов                          │  ║
* ║  │        - propagateCurrentValue() один раз на выход                  │  ║
* ║  │        - Impulsys.quickEmit(FFT_SPECTRUM_READY)                     │  ║
* ║  │                                                                     │  ║
* ║  │  B) DATABANK (Haxe):                                                │  ║
* ║  │     ─────────────────────                                           │  ║
* ║  │     _inputBuffer: Array<Float>     - Копия входного буфера          │  ║
* ║  │     _windowFunc: Array<Float>      - Оконная функция                │  ║
* ║  │     _spectrum: Array<Float>        - Амплитуды (N/2 бинов)          │  ║
* ║  │     _spectrumDB: Array<Float>      - Амплитуды в dBFS               │  ║
* ║  │     _re: Array<Float>              - Real part (FFT workspace)      │  ║
* ║  │     _im: Array<Float>              - Imaginary part (FFT workspace) │  ║
* ║  │                                                                     │  ║
* ║  │  C) INPUTS:                                                         │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "buffer"      - Array<Float> (от MiniAudioAtom)                 │  ║
* ║  │     "windowSize"  - Int (512, 1024, 2048)                           │  ║
* ║  │     "windowType"  - Int (0=None, 1=Hann, 2=Hamming)                 │  ║
* ║  │     "sampleRate"  - Int (44100, 48000, 96000)                       │  ║
* ║  │     "targetBars"  - Int (количество столбиков, по умолч. 16)        │  ║
* ║  │     "minFreq"     - Float (мин. частота, по умолч. 20.0)            │  ║
* ║  │     "maxFreq"     - Float (макс. частота, по умолч. 20000.0)        │  ║
* ║  │     "minDB"       - Float (мин. уровень dBFS, по умолч. -90.0)      │  ║
* ║  │     "maxDB"       - Float (макс. уровень dBFS, по умолч. 0.0)       │  ║
* ║  │     "compExp"     - Float (степень компрессии, по умолч. 0.6)       │  ║
* ║  │     "noiseGate"   - Float (порог шума, по умолч. 0.01)              │  ║
* ║  │     "gain"        - Float (усиление -1.0..1.0, по умолч. 0.0)       │  ║
* ║  │     "mode"        - Int (0 = стандарт, 1 = кирпичики с пиком)       │  ║
* ║  │                                                                     │  ║
* ║  │  D) OUTPUTS:                                                        │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "spectrum"    - Array<Float> (амплитуды, N/2 бинов)             │  ║
* ║  │     "spectrumDB"  - Array<Float> (амплитуды в dBFS)                 │  ║
* ║  │     "peak"        - Float (пиковая частота, Hz)                     │  ║
* ║  │     "peakAmp"     - Float (амплитуда пика)                          │  ║
* ║  │     "bass"        - Float (энергия 20-250 Hz)                       │  ║
* ║  │     "mid"         - Float (энергия 250-4000 Hz)                     │  ║
* ║  │     "treble"      - Float (энергия 4000-20000 Hz)                   │  ║
* ║  │     "changed"     - Bool (импульс при обновлении)                   │  ║
* ║  │                                                                     │  ║
* ║  │  E) FACE (DeviceView):                                              │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     FFTWidget для визуализации спектра                              │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     FFT ALGORITHM                                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Cooley-Tukey Radix-2 Decimation-In-Time (DIT):                           ║
* ║                                                                           ║
* ║  1. Bit-reversal permutation входных данных                               ║
* ║  2. Butterfly operations:                                                 ║
* ║     ┌──────┐                                                              ║
* ║     │  a   │──────┐                                                       ║
* ║     └──────┘      │  ┌──────┐                                             ║
* ║                   ├─►│ a + t│                                             ║
* ║     ┌──────┐      │  └──────┘                                             ║
* ║     │  b   │──────┘                                                       ║
* ║     └──────┘      │  ┌──────┐                                             ║
* ║                   └─►│ a - t│                                             ║
* ║                      └──────┘                                             ║
* ║                                                                           ║
* ║     где t = b * W_N^k (twiddle factor)                                    ║
* ║     W_N^k = e^(-2πi*k/N)                                                  ║
* ║                                                                           ║
* ║  Сложность: O(N log N) вместо O(N²)                                       ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                   WINDOW FUNCTIONS                                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Hann:  w(n) = 0.5 * (1 - cos(2π * n / (N-1)))                            ║
* ║  Hamming: w(n) = 0.54 - 0.46 * cos(2π * n / (N-1))                        ║
* ║                                                                           ║
* ║  Оконные функции уменьшают спектральную утечку (spectral leakage),        ║
* ║  вызванную резкими краями буфера.                                         ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class FFTAtom extends Atom implements Driver
{
	// =========================================================================
	// CONSTANTS
	// =========================================================================
	/** Минимальный размер FFT (степень 2) */
	private static inline var MIN_FFT_SIZE:Int = 256;
	/** Максимальный размер FFT */
	private static inline var MAX_FFT_SIZE:Int = 4096;
	/** Длительность импульса "changed" */
	private static inline var PULSE_DURATION:Float = 0.05;
	
	/** Оконная функция: None */
	private static inline var WINDOW_NONE:Int = 0;
	/** Оконная функция: Hann */
	private static inline var WINDOW_HANN:Int = 1;
	/** Оконная функция: Hamming */
	private static inline var WINDOW_HAMMING:Int = 2;
	
	// =========================================================================
	// DATABANK — Parameters
	// =========================================================================
	/** Размер FFT (количество точек) */
	private var _fftSize:Int = 512;
	/** Тип оконной функции */
	private var _windowType:Int = WINDOW_HANN;
	/** Частота дискретизации (для расчёта частотных бинов) */
	private var _sampleRate:Int = 48000;
	
	// === Новые параметры визуализации и настройки ===
	private var _targetBars:Int = 16;
	private var _minFreq:Float = 20.0;
	private var _maxFreq:Float = 20000.0;
	private var _minDB:Float = -90.0;
	private var _maxDB:Float = 0.0;
	private var _compressionExponent:Float = 0.8;
	private var _noiseGate:Float = 0.01;
	private var _gain:Float = 0.0;
	private var _mode:Int = 0; // 0 = стандарт, 1 = кирпичики с peak hold
	
	// =========================================================================
	// DATABANK — Zero-GC Buffers (предвыделенные)
	// =========================================================================
	/** Входной буфер (копия от MiniAudioAtom) */
	private var _inputBuffer:Array<Float>;
	/** Оконная функция (предвычисленная) */
	private var _windowFunc:Array<Float>;
	/** Real part (рабочий буфер FFT) */
	private var _re:Array<Float>;
	/** Imaginary part (рабочий буфер FFT) */
	private var _im:Array<Float>;
	/** Спектр (амплитуды, N/2 бинов) */
	private var _spectrum:Array<Float>;
	/** Спектр в dBFS */
	private var _spectrumDB:Array<Float>;
	
	// =========================================================================
	// DATABANK — State
	// =========================================================================
	/** Флаг: есть новые данные для обработки */
	private var _hasNewData:Bool = false;
	/** Пиковая частота (Hz) */
	private var _peakFreq:Float = 0.0;
	/** Амплитуда пика */
	private var _peakAmp:Float = 0.0;
	/** Энергия bass (20-250 Hz) */
	private var _bassEnergy:Float = 0.0;
	/** Энергия mid (250-4000 Hz) */
	private var _midEnergy:Float = 0.0;
	/** Энергия treble (4000-20000 Hz) */
	private var _trebleEnergy:Float = 0.0;
	
	/** Таймер импульса "changed" */
	private var _pulseTimer:Float = 0.0;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	/**
	* Создаёт новый экземпляр FFTAtom.
	* 
	* @param id Уникальный идентификатор атома
	*/
	public function new(id:String)
	{
		super(
			// === INPUTS ===
			[
				new Contact(null, INPUT, "buffer"),          // Array<Float> от MiniAudioAtom
				new Contact(512, INPUT, "windowSize"),       // Размер FFT (512, 1024, 2048)
				new Contact(WINDOW_HANN, INPUT, "windowType"), // Тип окна (0=None, 1=Hann, 2=Hamming)
				new Contact(48000, INPUT, "sampleRate"),     // Частота дискретизации
				new Contact(16, INPUT, "targetBars"),        // Количество баров
				new Contact(20.0, INPUT, "minFreq"),         // Минимальная частота (Hz)
				new Contact(20000.0, INPUT, "maxFreq"),      // Максимальная частота (Hz)
				new Contact(-90.0, INPUT, "minDB"),          // Минимальный уровень dBFS
				new Contact(0.0, INPUT, "maxDB"),            // Максимальный уровень dBFS
				new Contact(0.6, INPUT, "compressionExponent"), // Степень компрессии
				new Contact(0.01, INPUT, "noiseGate"),       // Порог шумоподавления
				new Contact(0.0, INPUT, "gain"),             // Усиление (-1.0 до +1.0, маппится на ±20dB)
				new Contact(0, INPUT, "mode")                // Режим визуализации (0 = стандарт, 1 = кирпичики)
			],
			// === OUTPUTS ===
			[
				new Contact(null, OUTPUT, "spectrum"),       // Array<Float> (амплитуды)
				new Contact(null, OUTPUT, "spectrumDB"),     // Array<Float> (dBFS)
				new Contact(0.0, OUTPUT, "peak"),            // Float (пиковая частота, Hz)
				new Contact(0.0, OUTPUT, "peakAmp"),         // Float (амплитуда пика)
				new Contact(0.0, OUTPUT, "bass"),            // Float (энергия 20-250 Hz)
				new Contact(0.0, OUTPUT, "mid"),             // Float (энергия 250-4000 Hz)
				new Contact(0.0, OUTPUT, "treble"),          // Float (энергия 4000-20000 Hz)
				new Contact(false, OUTPUT, "changed")        // Bool (импульс)
			],
			null,
			id,
			"FFTAtom",
			true // isActive = true → регистрируется в DriverManager
		);
		
		// Отключаем защиту от осцилляции для выхода "spectrum"
		var spectrumOut = getOutput("spectrum");
		if (spectrumOut != null) spectrumOut.ignoreOscillation = true;
		
		init();
	}
	
	// =========================================================================
	// LIFECYCLE
	// =========================================================================
	/**
	* Инициализация драйвера.
	* Предвыделяет Zero-GC буферы и вычисляет оконную функцию.
	*/
	override public function init():Void
	{
		// Предвыделение буферов (Zero-GC)
		_inputBuffer = new Array<Float>();
		_windowFunc = new Array<Float>();
		_re = new Array<Float>();
		_im = new Array<Float>();
		_spectrum = new Array<Float>();
		_spectrumDB = new Array<Float>();
		
		// Инициализация нулями
		for (i in 0...MAX_FFT_SIZE) {
			_inputBuffer.push(0.0);
			_windowFunc.push(0.0);
			_re.push(0.0);
			_im.push(0.0);
		}
		for (i in 0...(MAX_FFT_SIZE >> 1)) {
			_spectrum.push(0.0);
			_spectrumDB.push(-120.0);
		}
		
		// Чтение начальных параметров
		readInputs();
		
		// Вычисление оконной функции
		computeWindowFunction();
	}
	
	/**
	* Главный цикл обновления драйвера.
	* Вызывается каждый кадр из DriverManager.update(dt).
	* 
	* @param dt Delta time (время с прошлого кадра в секундах)
	*/
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;
		
		// 1. Чтение входных параметров
		readInputs();
		
		// 2. Обработка FFT (если есть новые данные)
		if (_hasNewData) {
			processFFT();
			_hasNewData = false;
		}
		
		// 3. Обновление таймера импульса
		if (_pulseTimer > 0) {
			_pulseTimer -= dt;
			if (_pulseTimer <= 0) {
				var c = getOutput("changed");
				if (c != null) c.value = false;
			}
		}
	}
	
	/**
	* Освобождение ресурсов.
	*/
	override public function dispose():Void
	{
		DriverManager.getInstance().unregister(this.id);
		_inputBuffer = null;
		_windowFunc = null;
		_re = null;
		_im = null;
		_spectrum = null;
		_spectrumDB = null;
		super.dispose();
	}
	
	// =========================================================================
	// INPUT READING
	// =========================================================================
	/**
	* Читает значения входных контактов и обновляет параметры атома.
	*/
	private function readInputs():Void
	{
		// Чтение буфера сэмплов
		var bufferC = getInput("buffer");
		if (bufferC != null && bufferC.value != null) {
			if (Std.isOfType(bufferC.value, Array)) {
				var samples:Array<Float> = bufferC.value;
				if (samples != null && samples.length > 0) {
					// Копируем данные во входной буфер (Zero-GC)
					var count = Std.int(Math.min(samples.length, _fftSize));
					for (i in 0...count) {
						_inputBuffer[i] = samples[i];
					}
					_hasNewData = true;
				}
			}
		}
		
		// Чтение размера FFT
		var sizeC = getInput("windowSize");
		if (sizeC != null && sizeC.value != null) {
			var newSize = Std.int(sizeC.value);
			// Проверяем, что размер — степень 2
			if (newSize >= MIN_FFT_SIZE && newSize <= MAX_FFT_SIZE && isPowerOfTwo(newSize)) {
				if (newSize != _fftSize) {
					_fftSize = newSize;
					computeWindowFunction(); // Перевычисляем окно
				}
			}
		}
		
		// Чтение типа окна
		var typeC = getInput("windowType");
		if (typeC != null && typeC.value != null) {
			var newType = Std.int(typeC.value);
			if (newType >= WINDOW_NONE && newType <= WINDOW_HAMMING) {
				if (newType != _windowType) {
					_windowType = newType;
					computeWindowFunction();
				}
			}
		}
		
		// Чтение частоты дискретизации
		var rateC = getInput("sampleRate");
		if (rateC != null && rateC.value != null) {
			_sampleRate = Std.int(rateC.value);
		}
		
		// === Чтение новых параметров визуализации ===
		var barsC = getInput("targetBars");
		if (barsC != null && barsC.value != null) {
			var v = Std.int(barsC.value);
			if (v >= 1 && v <= 128) _targetBars = v;
		}
		
		var minFC = getInput("minFreq");
		if (minFC != null && minFC.value != null) {
			var v = Std.parseFloat(Std.string(minFC.value));
			if (v >= 1.0) _minFreq = v;
		}
		
		var maxFC = getInput("maxFreq");
		if (maxFC != null && maxFC.value != null) {
			var v = Std.parseFloat(Std.string(maxFC.value));
			if (v >= 20.0) _maxFreq = v;
		}
		
		var minDBC = getInput("minDB");
		if (minDBC != null && minDBC.value != null) {
			_minDB = Std.parseFloat(Std.string(minDBC.value));
		}
		
		var maxDBC = getInput("maxDB");
		if (maxDBC != null && maxDBC.value != null) {
			_maxDB = Std.parseFloat(Std.string(maxDBC.value));
		}
		
		var compC = getInput("compressionExponent");
		if (compC != null && compC.value != null) {
			var v = Std.parseFloat(Std.string(compC.value));
			if (v > 0.1 && v <= 2.0) _compressionExponent = v;
		}
		
		var gateC = getInput("noiseGate");
		if (gateC != null && gateC.value != null) {
			var v = Std.parseFloat(Std.string(gateC.value));
			if (v >= 0.0 && v <= 1.0) _noiseGate = v;
		}
		
		var gainC = getInput("gain");
		if (gainC != null && gainC.value != null) {
			var v = Std.parseFloat(Std.string(gainC.value));
			if (v >= -1.0 && v <= 1.0) _gain = v;
		}
		
		var modeC = getInput("mode");
		if (modeC != null && modeC.value != null) {
			var v = Std.int(modeC.value);
			if (v >= 0 && v <= 1) _mode = v;
		}
	}
	
	// =========================================================================
	// FFT PROCESSING
	// =========================================================================
	/**
	* Основная функция обработки FFT.
	* 1. Применяет оконную функцию
	* 2. Выполняет Cooley-Tukey FFT
	* 3. Извлекает магнитуды
	* 4. Конвертирует в dBFS
	* 5. Вычисляет bass/mid/treble
	*/
	private function processFFT():Void
	{
		// 1. Применение оконной функции
		for (i in 0..._fftSize) {
			_re[i] = _inputBuffer[i] * _windowFunc[i];
			_im[i] = 0.0; // Imaginary part = 0 для реального сигнала
		}
		
		// 2. Выполнение FFT (Cooley-Tukey Radix-2 DIT)
		fft(_re, _im, _fftSize);
		
		// 3. Извлечение магнитуд и конвертация в dBFS
		var halfSize = _fftSize >> 1;
		var peakBin = 0;
		var peakMag = 0.0;
		
		for (i in 0...halfSize) {
			// Магнитуда = sqrt(re² + im²)
			var mag = Math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]);
			_spectrum[i] = mag;
			
			// Конвертация в dBFS: 20 * log10(mag)
			var db = (mag > 0.0001) ? 20.0 * Math.log(mag) / Math.log(10) : -120.0;
			_spectrumDB[i] = db;
			
			// Поиск пика
			if (mag > peakMag) {
				peakMag = mag;
				peakBin = i;
			}
		}
		
		// 4. Вычисление пиковой частоты
		// Частота бина = bin * (sampleRate / fftSize)
		var freqResolution = _sampleRate / _fftSize;
		_peakFreq = peakBin * freqResolution;
		_peakAmp = peakMag;
		
		// 5. Вычисление bass/mid/treble энергии
		computeBandEnergies(freqResolution);
		
		// 6. Batched propagation (паттерн из MiniAudioAtom)
		var spectrumOut = getOutput("spectrum");
		var spectrumDBOut = getOutput("spectrumDB");
		var peakOut = getOutput("peak");
		var peakAmpOut = getOutput("peakAmp");
		var bassOut = getOutput("bass");
		var midOut = getOutput("mid");
		var trebleOut = getOutput("treble");
		var changedOut = getOutput("changed");
		
		// Silent writes
		if (spectrumOut != null) spectrumOut.setValueSilent(_spectrum);
		if (spectrumDBOut != null) spectrumDBOut.setValueSilent(_spectrumDB);
		if (peakOut != null) peakOut.setValueSilent(_peakFreq);
		if (peakAmpOut != null) peakAmpOut.setValueSilent(_peakAmp);
		if (bassOut != null) bassOut.setValueSilent(_bassEnergy);
		if (midOut != null) midOut.setValueSilent(_midEnergy);
		if (trebleOut != null) trebleOut.setValueSilent(_trebleEnergy);
		
		// Single propagation per output
		if (spectrumOut != null) spectrumOut.propagateCurrentValue();
		if (spectrumDBOut != null) spectrumDBOut.propagateCurrentValue();
		if (peakOut != null) peakOut.propagateCurrentValue();
		if (peakAmpOut != null) peakAmpOut.propagateCurrentValue();
		if (bassOut != null) bassOut.propagateCurrentValue();
		if (midOut != null) midOut.propagateCurrentValue();
		if (trebleOut != null) trebleOut.propagateCurrentValue();
		
		// Импульс "changed"
		if (changedOut != null) {
			changedOut.value = true;
			_pulseTimer = PULSE_DURATION;
		}
		
		// Уведомление UI через Impulsys
		Impulsys.quickEmit(EventType.FFT_SPECTRUM_READY, { atomId: this.id });
	}
	
	/**
	* Алгоритм Cooley-Tukey Radix-2 DIT FFT (in-place).
	* 
	* @param re Real part (массив размера N)
	* @param im Imaginary part (массив размера N)
	* @param n Размер FFT (степень 2)
	*/
	private function fft(re:Array<Float>, im:Array<Float>, n:Int):Void
	{
		// 1. Bit-reversal permutation
		var j = 0;
		for (i in 0...(n - 1)) {
			if (i < j) {
				// Swap re[i] and re[j]
				var tempRe = re[i];
				re[i] = re[j];
				re[j] = tempRe;
				// Swap im[i] and im[j]
				var tempIm = im[i];
				im[i] = im[j];
				im[j] = tempIm;
			}
			var k = n >> 1;
			while (k <= j) {
				j -= k;
				k >>= 1;
			}
			j += k;
		}
		
		// 2. Cooley-Tukey butterfly operations
		var step = 2;
		while (step <= n) {
			var halfStep = step >> 1;
			var angleStep = -2.0 * Math.PI / step;
			
			for (i in 0...halfStep) {
				var angle = i * angleStep;
				var wRe = Math.cos(angle);
				var wIm = Math.sin(angle);
				
				var k = i;
				while (k < n) {
					var idx1 = k;
					var idx2 = k + halfStep;
					
					// Butterfly: t = w * (re[idx2] + i*im[idx2])
					var tRe = wRe * re[idx2] - wIm * im[idx2];
					var tIm = wRe * im[idx2] + wIm * re[idx2];
					
					// re[idx2] = re[idx1] - t
					re[idx2] = re[idx1] - tRe;
					im[idx2] = im[idx1] - tIm;
					
					// re[idx1] = re[idx1] + t
					re[idx1] = re[idx1] + tRe;
					im[idx1] = im[idx1] + tIm;
					
					k += step;
				}
			}
			
			step <<= 1;
		}
	}
	
	/**
	* Вычисляет энергию в частотных диапазонах bass/mid/treble.
	* 
	* @param freqResolution Частотное разрешение (Hz на бин)
	*/
	private function computeBandEnergies(freqResolution:Float):Void
	{
		var halfSize = _fftSize >> 1;
		
		// Bass: 20-250 Hz
		var bassStart = Std.int(20.0 / freqResolution);
		var bassEnd = Std.int(250.0 / freqResolution);
		_bassEnergy = 0.0;
		for (i in bassStart...bassEnd) {
			if (i < halfSize) _bassEnergy += _spectrum[i];
		}
		
		// Mid: 250-4000 Hz
		var midStart = bassEnd;
		var midEnd = Std.int(4000.0 / freqResolution);
		_midEnergy = 0.0;
		for (i in midStart...midEnd) {
			if (i < halfSize) _midEnergy += _spectrum[i];
		}
		
		// Treble: 4000-20000 Hz
		var trebleStart = midEnd;
		var trebleEnd = Std.int(20000.0 / freqResolution);
		_trebleEnergy = 0.0;
		for (i in trebleStart...trebleEnd) {
			if (i < halfSize) _trebleEnergy += _spectrum[i];
		}
	}
	
	// =========================================================================
	// WINDOW FUNCTION
	// =========================================================================
	/**
	* Вычисляет оконную функцию для текущего размера FFT и типа окна.
	*/
	private function computeWindowFunction():Void
	{
		var N = _fftSize;
		for (n in 0...N) {
			var w = 1.0;
			switch (_windowType) {
				case WINDOW_HANN:
					w = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * n / (N - 1)));
				case WINDOW_HAMMING:
					w = 0.54 - 0.46 * Math.cos(2.0 * Math.PI * n / (N - 1));
				case WINDOW_NONE:
					w = 1.0;
			}
			_windowFunc[n] = w;
		}
	}
	
	// =========================================================================
	// UTILITY
	// =========================================================================
	/**
	* Проверяет, является ли число степенью 2.
	* 
	* @param n Число для проверки
	* @return true если степень 2
	*/
	private function isPowerOfTwo(n:Int):Bool
	{
		return n > 0 && (n & (n - 1)) == 0;
	}
	
	// =========================================================================
	// PUBLIC API (для виджета)
	// =========================================================================
	public function getSpectrum():Array<Float> return _spectrum;
	public function getSpectrumDB():Array<Float> return _spectrumDB;
	public function getFFTSize():Int return _fftSize;
	public function getSampleRate():Int return _sampleRate;
	public function getPeakFreq():Float return _peakFreq;
	public function getBassEnergy():Float return _bassEnergy;
	public function getMidEnergy():Float return _midEnergy;
	public function getTrebleEnergy():Float return _trebleEnergy;
	
	// === Геттеры для новых параметров визуализации ===
	public function getTargetBars():Int return _targetBars;
	public function getMinFreq():Float return _minFreq;
	public function getMaxFreq():Float return _maxFreq;
	public function getMinDB():Float return _minDB;
	public function getMaxDB():Float return _maxDB;
	public function getCompressionExponent():Float return _compressionExponent;
	public function getNoiseGate():Float return _noiseGate;
	public function getGain():Float return _gain;
	public function getMode():Int return _mode;
}