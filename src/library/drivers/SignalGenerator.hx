package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;

import system.managers.DriverManager;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     SIGNAL GENERATOR ATOM v1.0                            ║
 * ║                     (Quantized Output System)                             ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Генератор сигналов с квантованием амплитуды.                             ║
 * ║  Выдаёт значение на выходной контакт ТОЛЬКО при смене                     ║
 * ║  квантового значения амплитуды.                                           ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        АРХИТЕКТУРА                                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     SignalGenerator                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  А) COMPUTE MODULE:                                                 │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     update(dt) {                                                    │  ║
 * ║  │         1. Генерация сырого сигнала по формуле                      │  ║
 * ║  │         2. Квантование амплитуды                                    │  ║
 * ║  │         3. Сравнение с предыдущим квантом                           │  ║
 * ║  │         4. Если изменился → output.value = newQuantum               │  ║
 * ║  │     }                                                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  Б) DATABANK:                                                       │  ║
 * ║  │     ─────────────                                                   │  ║
 * ║  │     _frequency:Float     - Частота генерации (Гц)                   │  ║
 * ║  │     _quantumStep:Float   - Шаг квантования амплитуды                │  ║
 * ║  │     _currentPhase:Float  - Текущая фаза сигнала                     │  ║
 * ║  │     _lastQuantum:Float   - Последнее квантованное значение          │  ║
 * ║  │     _mode:Int            - Режим генерации (0=OFF, 1=SQR, 2=SAW...) │  ║
 * ║  │                                                                     │  ║
 * ║  │  В) INPUTS:                                                         │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "freq"    - Частота (Float)                                     │  ║
 * ║  │     "quantum"  - Шаг квантования (Float, 0.01..1.0)                 │  ║
 * ║  │     "mode"     - Режим (Int: 0=OFF, 1=SQR, 2=SAW, 3=SIN, 4=TRI)     │  ║
 * ║  │                                                                     │  ║
 * ║  │  Г) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "out"     - Квантованное значение амплитуды (Float)             │  ║
 * ║  │     "changed"  - Импульс при смене кванта (Bool, кратковременный)   │  ║
 * ║  │                                                                     │  ║
 * ║  │  Д) FACE (DeviceView):                                              │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     TextWidget или OscilloscopeWidget для отображения               │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                      ПРИНЦИП РАБОТЫ                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Пример для синусоиды с quantum = 0.25:                                   ║
 * ║                                                                           ║
 * ║  Amplitude                                                                ║
 * ║    1.0 ┤         ╭──────╮         ╭──────╮                                ║
 * ║    0.75┤        ╭╯      ╰╮       ╭╯      ╰╮    ← Квант = 0.75             ║
 * ║    0.50┤       ╭╯        ╰╮     ╭╯        ╰╮   ← Квант = 0.50             ║
 * ║    0.25┤      ╭╯          ╰╮   ╭╯          ╰╮  ← Квант = 0.25             ║
 * ║    0.00┼──────╯            ╰───╯            ╰─ ← Квант = 0.00             ║
 * ║   -0.25┤                                      ╰╮ ← Квант = -0.25          ║
 * ║   -0.50┤                                        ╰╮← Квант = -0.50         ║
 * ║   -0.75┤                                         ╰                        ║
 * ║   -1.0 ┤                                                                  ║
 * ║        └─────────────────────────────────────────► Time                   ║
 * ║                                                                           ║
 * ║  Выходные импульсы (changed):                                             ║
 * ║         _|  |_|  |_|  |_|  |_|  |_|  |_|  |_|  |_                         ║
 * ║           ↑    ↑    ↑    ↑    ↑    ↑    ↑    ↑                            ║
 * ║         Каждый раз когда сигнал пересекает границу кванта                 ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     РЕЖИМЫ ГЕНЕРАЦИИ                                      ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  MODE 0: OFF        - Генерация отключена, выход = 0                      ║
 * ║  MODE 1: SQUARE     - Меандр (Square Wave)                                ║
 * ║  MODE 2: SAWTOOTH   - Пилообразный (Sawtooth Wave)                        ║
 * ║  MODE 3: SINE       - Синусоида (Sine Wave)                               ║
 * ║  MODE 4: TRIANGLE   - Треугольный (Triangle Wave)                         ║
 * ║  MODE 5: NOISE      - Шум (Random)                                        ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    ПРИМЕНЕНИЕ                                             ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  • Цифро-аналоговые преобразователи (ЦАП)                                 ║
 * ║  • Событийно-ориентированные системы управления                           ║
 * ║  • Оптимизация передачи данных (отправка только изменений)                ║
 * ║  • Синхронизация модулей по изменению уровня сигнала                      ║
 * ║  • Генерация триггерных импульсов                                         ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class SignalGenerator extends Atom implements system.managers.Driver
{
	// =========================================================================
	// КОНСТАНТЫ
	// =========================================================================

	/**
	 * Минимальный шаг квантования.
	 */
	private static inline var MIN_QUANTUM:Float = 0.001;

	/**
	 * Максимальный шаг квантования.
	 */
	private static inline var MAX_QUANTUM:Float = 1.0;

	/**
	 * Минимальная частота (Гц).
	 */
	private static inline var MIN_FREQUENCY:Float = 0.1;

	/**
	 * Максимальная частота (Гц).
	 */
	private static inline var MAX_FREQUENCY:Float = 20000.0;

	/**
	 * Длительность импульса changed (в секундах).
	 */
	private static inline var PULSE_DURATION:Float = 0.05;

	// =========================================================================
	// РЕЖИМЫ ГЕНЕРАЦИИ
	// =========================================================================

	private static inline var MODE_OFF:Int        = 0;
	private static inline var MODE_SQUARE:Int     = 1;
	private static inline var MODE_SAWTOOTH:Int   = 2;
	private static inline var MODE_SINE:Int       = 3;
	private static inline var MODE_TRIANGLE:Int   = 4;
	private static inline var MODE_NOISE:Int      = 5;

	// =========================================================================
	// DATABANK - Параметры
	// =========================================================================

	/**
	 * Частота генерации в Герцах.
	 */
	private var _frequency:Float = 440.0;

	/**
	 * Шаг квантования амплитуды.
	 */
	private var _quantumStep:Float = 0.1;

	/**
	 * Текущий режим генерации.
	 */
	private var _mode:Int = MODE_OFF;

	// =========================================================================
	// DATABANK - Состояние
	// =========================================================================

	/**
	 * Текущая фаза сигнала (радианы).
	 */
	private var _currentPhase:Float = 0.0;

	/**
	 * Последнее квантованное значение.
	 * Используется для обнаружения изменений.
	 */
	private var _lastQuantum:Float = 0.0;

	/**
	 * Флаг первого кадра (для инициализации).
	 */
	private var _isFirstUpdate:Bool = true;

	/**
	 * Время до сброса импульса changed.
	 */
	private var _pulseTimer:Float = 0.0;

	/**
	 * Флаг активного импульса changed.
	 */
	private var _pulseActive:Bool = false;

	/**
	 * Счётчик выходных импульсов (статистика).
	 */
	private var _pulseCount:Int = 0;

	/**
	 * Общее время работы.
	 */
	private var _totalTime:Float = 0.0;

	/**
	 * Счётчик обновлений.
	 */
	private var _updateCount:Int = 0;

	// =========================================================================
	// КОНСТРУКТОР
	// =========================================================================

	public function new(id:String)
	{
		super(
			// === INPUTS ===
			[
				new Contact(440.0, INPUT, "freq"),     // Частота
				new Contact(0.1, INPUT, "quantum"),    // Шаг квантования
				new Contact(0, INPUT, "mode")          // Режим генерации
			],
			// === OUTPUTS ===
			[
				new Contact(0.0, OUTPUT, "out"),       // Квантованное значение
				new Contact(false, OUTPUT, "changed")  // Импульс при смене кванта
			],
			// === PROCESS FUNCTION ===
			null,
			id,
			"SignalGenerator",
			true  // isActive = true (регистрируемся в DriverManager)
		);

		var outContact = getOutput("out");
		if (outContact != null)
		{
			outContact.ignoreOscillation = true;
		}
		trace('SignalGenerator: Created (id: $id)');
	}

	// =========================================================================
	// LIFECYCLE - Driver Interface
	// =========================================================================

	/**
	 * Инициализация драйвера.
	 */
	override public function init():Void
	{
		_currentPhase = 0.0;
		_lastQuantum = 0.0;
		_isFirstUpdate = true;
		_pulseTimer = 0.0;
		_pulseActive = false;
		_pulseCount = 0;
		_totalTime = 0.0;
		_updateCount = 0;

		trace('SignalGenerator: Initialized');
	}

	/**
	 * Обновление каждый кадр - основная логика генерации.
	 * Вызывается из DriverManager.update().
	 *
	 * @param dt Delta time в секундах
	 */
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;

		// Добавим логирование каждые 60 кадров
		if (Std.random(60) == 0)
		{
			trace('SignalGenerator update, freq=$_frequency, mode=$_mode, tick=${TickGenerator.getInstance().currentTick}');
		}

		_updateCount++;
		_totalTime += dt;

		// 1. Считываем входные параметры
		readInputs();

		// 2. Управление импульсом changed
		updatePulse(dt);

		// 3. Если генерация отключена - выходим
		if (_mode == MODE_OFF)
		{
			setOutputQuantized(0.0);
			return;
		}

		// 4. Продвигаем фазу
		advancePhase(dt);

		// 5. Генерируем сырой сигнал
		var rawValue = generateRawSignal();

		// 6. Квантуем значение
		var newQuantum = quantizeValue(rawValue);

		// 7. Проверяем изменение и обновляем выход
		updateOutput(newQuantum);
	}

	/**
	 * Освобождение ресурсов.
	 */
	override public function dispose():Void
	{
		DriverManager.getInstance().unregister(this.id);
		super.dispose();
		trace('SignalGenerator: Disposed (pulses: $_pulseCount)');
	}

	// =========================================================================
	// ЧТЕНИЕ ВХОДОВ
	// =========================================================================

	/**
	 * Считать значения с входных контактов.
	 */
	private function readInputs():Void
	{
		// Частота
		var freqContact = getInput("freq");
		if (freqContact != null && freqContact.value != null)
		{
			var f = parseFloat(freqContact.value, _frequency);
			if (f >= MIN_FREQUENCY && f <= MAX_FREQUENCY)
			{
				_frequency = f;
			}
		}

		// Шаг квантования
		var quantumContact = getInput("quantum");
		if (quantumContact != null && quantumContact.value != null)
		{
			var q = parseFloat(quantumContact.value, _quantumStep);
			if (q >= MIN_QUANTUM && q <= MAX_QUANTUM)
			{
				_quantumStep = q;
			}
		}

		// Режим
		var modeContact = getInput("mode");
		if (modeContact != null && modeContact.value != null)
		{
			_mode = parseInt(modeContact.value, MODE_OFF);
			if (_mode < MODE_OFF || _mode > MODE_NOISE)
			{
				_mode = MODE_OFF;
			}
		}
	}

	// =========================================================================
	// ГЕНЕРАЦИЯ СИГНАЛА
	// =========================================================================

	/**
	 * Продвижение фазы на основе прошедшего времени.
	 *
	 * @param dt Delta time в секундах
	 */
	private function advancePhase(dt:Float):Void
	{
		_currentPhase += _frequency * 2.0 * Math.PI * dt;

		// Нормализация фазы для предотвращения переполнения
		while (_currentPhase > 2.0 * Math.PI)
		{
			_currentPhase -= 2.0 * Math.PI;
		}
	}

	/**
	 * Генерация сырого (неквантованного) сигнала.
	 *
	 * @return Значение в диапазоне [-1.0, 1.0]
	 */
	private function generateRawSignal():Float
	{
		return switch (_mode)
		{
			case MODE_SQUARE:
				generateSquare();

			case MODE_SAWTOOTH:
				generateSawtooth();

			case MODE_SINE:
				generateSine();

			case MODE_TRIANGLE:
				generateTriangle();

			case MODE_NOISE:
				generateNoise();

			default:
				0.0;
		}
	}

	/**
	 * Генерация меандра (Square Wave).
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  1.0 ┤ ┌─────┐     ┌─────┐     ┌─────┐     ┌─────┐
	 *  0.0 ┼─┘     └─────┘     └─────┘     └─────┘     └─────
	 * -1.0 ┤
	 *      └──────────────────────────────────────────► Time
	 * ═══════════════════════════════════════════════════════════════════
	 */
	private function generateSquare():Float
	{
		// Нормализованная фаза [0, 1)
		var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
		if (normalizedPhase < 0) normalizedPhase += 1.0;

		// 50% duty cycle
		return (normalizedPhase < 0.5) ? 1.0 : -1.0;
	}

	/**
	 * Генерация пилообразного сигнала (Sawtooth Wave).
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  1.0 ┤       ╱       ╱       ╱       ╱       ╱
	 *  0.0 ┼──────╱ ──────╱ ──────╱ ──────╱ ──────╱ ─────
	 * -1.0 ┤     ╱       ╱       ╱       ╱       ╱
	 *      └──────────────────────────────────────────► Time
	 * ═══════════════════════════════════════════════════════════════════
	 */
	private function generateSawtooth():Float
	{
		// Нормализованная фаза [0, 1)
		var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
		if (normalizedPhase < 0) normalizedPhase += 1.0;

		// Линейно от -1 до 1
		return 2.0 * normalizedPhase - 1.0;
	}

	/**
	 * Генерация синусоиды (Sine Wave).
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  1.0 ┤    ╭───╮         ╭───╮         ╭───╮
	 *  0.0 ┼──╭─╯   ╰─╮─────╭─╯   ╰─╮─────╭─╯   ╰─╮──
	 * -1.0 ┤ ╰╯       ╰─────╯       ╰─────╯       ╰╯
	 *      └──────────────────────────────────────────► Time
	 * ═══════════════════════════════════════════════════════════════════
	 */
	private function generateSine():Float
	{
		return Math.sin(_currentPhase);
	}

	/**
	 * Генерация треугольного сигнала (Triangle Wave).
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  1.0 ┤     ╱╲       ╱╲       ╱╲       ╱╲       ╱
	 *  0.0 ┼────╱──╲─────╱──╲─────╱──╲─────╱──╲─────╱
	 * -1.0 ┤   ╱    ╲   ╱    ╲   ╱    ╲   ╱    ╲   ╱
	 *       └──────────────────────────────────────────► Time
	 * ═══════════════════════════════════════════════════════════════════
	 */
	private function generateTriangle():Float
	{
		// Нормализованная фаза [0, 1)
		var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
		if (normalizedPhase < 0) normalizedPhase += 1.0;

		// Треугольник: поднимается от -1 до 1 на первой половине,
		// опускается от 1 до -1 на второй
		if (normalizedPhase < 0.5)
		{
			// Восходящая часть
			return -1.0 + 4.0 * normalizedPhase;
		}
		else
		{
			// Нисходящая часть
			return 3.0 - 4.0 * normalizedPhase;
		}
	}

	/**
	 * Генерация шума (Noise).
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  1.0 ┤  │  ││ │ │ │   ││  │ │  │ │ │  │  ││ │ │ │
	 *  0.0 ┼──┼──┼┼─┼─┼─┼───┼┼──┼─┼──┼─┼─┼──┼──┼┼─┼─┼─┼──
	 * -1.0 ┤  ││ │ ││ │││││ │ │││││ ││ │ │ │ │││ │ ││
	 *       └──────────────────────────────────────────► Time
	 * ═══════════════════════════════════════════════════════════════════
	 */
	private function generateNoise():Float
	{
		return (Math.random() * 2.0 - 1.0);
	}

	// =========================================================================
	// КВАНТОВАНИЕ
	// =========================================================================

	/**
	 * Квантование значения амплитуды.
	 *
	 * ═══════════════════════════════════════════════════════════════════
	 *  Amplitude
	 *    1.0 ┼─────────────────────────────●───────────────────────
	 *    0.8 ┼─────────────────────────────│───────────────────────
	 *    0.6 ┼─────────────────────────────│───────────────────────
	 *    0.4 ┼───────────────────●─────────│───────────────────────
	 *    0.2 ┼───────────────────│─────────│───────────────────────
	 *    0.0 ┼─────●─────────────│─────────│───────────────────────
	 *   -0.2 ┼─────│─────────────│─────────│───────────────────────
	 *   -0.4 ┼─────│─────●───────│─────────│───────────────────────
	 *   -0.6 ┼─────│─────│───────│─────────│───────────────────────
	 *   -0.8 ┼─────│─────│───────│─────────│───────────────────────
	 *   -1.0 ┼─────│─────│───────│─────●───│───────────────────────
	 *         └──────────────────────────────────────────────────►
	 *
	 *  quantum = 0.2, значения округляются до ближайшего уровня
	 * ═══════════════════════════════════════════════════════════════════
	 *
	 * @param value Сырое значение [-1.0, 1.0]
	 * @return Квантованное значение
	 */
	private function quantizeValue(value:Float):Float
	{
		// Округляем до ближайшего кванта
		var quantized = Math.round(value / _quantumStep) * _quantumStep;

		// Ограничиваем диапазон
		if (quantized > 1.0) quantized = 1.0;
		if (quantized < -1.0) quantized = -1.0;

		return quantized;
	}

	// =========================================================================
	// УПРАВЛЕНИЕ ВЫХОДОМ
	// =========================================================================

	/**
	 * Обновить выходное значение с проверкой изменения кванта.
	 *
	 * @param newQuantum Новое квантованное значение
	 */
	private function updateOutput(newQuantum:Float):Void
	{
		// Первый кадр - инициализация
		if (_isFirstUpdate)
		{
			_lastQuantum = newQuantum;
			_isFirstUpdate = false;
			setOutputQuantized(newQuantum);
			return;
		}

		// Проверяем изменение
		if (newQuantum != _lastQuantum)
		{
			_lastQuantum = newQuantum;
			setOutputQuantized(newQuantum);
			triggerPulse();
		}
	}

	/**
	 * Установить квантованное значение на выход.
	 *
	 * @param value Квантованное значение
	 */
	private function setOutputQuantized(value:Float):Void
	{
		var outContact = getOutput("out");
		if (outContact != null)
		{
			outContact.value = value;
		}
	}

	/**
	 * Запустить импульс changed.
	 */
	private function triggerPulse():Void
	{
		var changedContact = getOutput("changed");
		if (changedContact != null)
		{
			changedContact.value = true;
			_pulseActive = true;
			_pulseTimer = PULSE_DURATION;
			_pulseCount++;
		}
	}

	/**
	 * Обновить состояние импульса changed.
	 *
	 * @param dt Delta time в секундах
	 */
	private function updatePulse(dt:Float):Void
	{
		if (!_pulseActive) return;

		_pulseTimer -= dt;

		if (_pulseTimer <= 0)
		{
			var changedContact = getOutput("changed");
			if (changedContact != null)
			{
				changedContact.value = false;
			}
			_pulseActive = false;
		}
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================

	/**
	 * Получить частоту генерации.
	 */
	public function getFrequency():Float
	{
		return _frequency;
	}

	/**
	 * Установить частоту генерации.
	 */
	public function setFrequency(freq:Float):Void
	{
		if (freq >= MIN_FREQUENCY && freq <= MAX_FREQUENCY)
		{
			_frequency = freq;
		}
	}

	/**
	 * Получить шаг квантования.
	 */
	public function getQuantumStep():Float
	{
		return _quantumStep;
	}

	/**
	 * Установить шаг квантования.
	 */
	public function setQuantumStep(step:Float):Void
	{
		if (step >= MIN_QUANTUM && step <= MAX_QUANTUM)
		{
			_quantumStep = step;
		}
	}

	/**
	 * Получить режим генерации.
	 */
	public function getMode():Int
	{
		return _mode;
	}

	/**
	 * Установить режим генерации.
	 */
	public function setMode(mode:Int):Void
	{
		if (mode >= MODE_OFF && mode <= MODE_NOISE)
		{
			_mode = mode;
		}
	}

	/**
	 * Получить текущую фазу.
	 */
	public function getPhase():Float
	{
		return _currentPhase;
	}

	/**
	 * Сбросить фазу в ноль.
	 */
	public function resetPhase():Void
	{
		_currentPhase = 0.0;
	}

	/**
	 * Получить последнее квантованное значение.
	 */
	public function getLastQuantum():Float
	{
		return _lastQuantum;
	}

	/**
	 * Получить количество сгенерированных импульсов.
	 */
	public function getPulseCount():Int
	{
		return _pulseCount;
	}

	/**
	 * Получить имя режима генерации.
	 */
	public function getModeName():String
	{
		return switch (_mode)
		{
			case MODE_OFF:      "OFF";
			case MODE_SQUARE:   "SQUARE";
			case MODE_SAWTOOTH: "SAWTOOTH";
			case MODE_SINE:     "SINE";
			case MODE_TRIANGLE: "TRIANGLE";
			case MODE_NOISE:    "NOISE";
			default:            "UNKNOWN";
		}
	}

	/**
	 * Получить все доступные режимы.
	 */
	public static function getAvailableModes():Array< {id:Int, name:String, description:String}>
	{
		return [
		{ id: MODE_OFF,      name: "OFF",      description: "Генерация отключена" },
		{ id: MODE_SQUARE,   name: "SQUARE",   description: "Меандр (квадратная волна)" },
		{ id: MODE_SAWTOOTH, name: "SAWTOOTH", description: "Пилообразная волна" },
		{ id: MODE_SINE,     name: "SINE",     description: "Синусоида" },
		{ id: MODE_TRIANGLE, name: "TRIANGLE", description: "Треугольная волна" },
		{ id: MODE_NOISE,    name: "NOISE",    description: "Случайный шум" }
		];
	}

	// =========================================================================
	// STATE SERIALIZATION
	// =========================================================================

	/**
	 * Сохранить состояние для персистентности.
	 */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();

		var result:Dynamic = {
			frequency: _frequency,
			quantumStep: _quantumStep,
			mode: _mode,
			phase: _currentPhase,
			lastQuantum: _lastQuantum,
			pulseCount: _pulseCount
		};

		// Добавляем поля базового класса
		if (base != null)
		{
			if (Reflect.hasField(base, "isLogic"))
			{
				Reflect.setField(result, "isLogic", Reflect.field(base, "isLogic"));
			}
		}

		return result;
	}

	/**
	 * Восстановить состояние из сохранённых данных.
	 */
	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;

		// Сначала восстанавливаем поля базового класса
		super.restoreState(state);

		if (state.frequency != null)
		{
			var f = parseFloat(state.frequency, _frequency);
			if (f >= MIN_FREQUENCY && f <= MAX_FREQUENCY)
			{
				_frequency = f;
			}
		}

		if (state.quantumStep != null)
		{
			var q = parseFloat(state.quantumStep, _quantumStep);
			if (q >= MIN_QUANTUM && q <= MAX_QUANTUM)
			{
				_quantumStep = q;
			}
		}

		if (state.mode != null)
		{
			_mode = parseInt(state.mode, MODE_OFF);
			if (_mode < MODE_OFF || _mode > MODE_NOISE)
			{
				_mode = MODE_OFF;
			}
		}

		if (state.phase != null)
		{
			_currentPhase = parseFloat(state.phase, _currentPhase);
		}

		if (state.lastQuantum != null)
		{
			_lastQuantum = parseFloat(state.lastQuantum, _lastQuantum);
		}

		if (state.pulseCount != null)
		{
			_pulseCount = parseInt(state.pulseCount, 0);
		}

		trace('SignalGenerator: Restored state (freq: $_frequency, mode: ${getModeName()})');
	}

	// =========================================================================
	// UTILITY
	// =========================================================================

	/**
	 * Безопасный парсинг Float.
	 */
	private function parseFloat(value:Dynamic, defaultValue:Float):Float
	{
		if (value == null) return defaultValue;

		if (Std.isOfType(value, Float))
		{
			return cast(value, Float);
		}

		if (Std.isOfType(value, Int))
		{
			return cast(value, Int) * 1.0;
		}

		if (Std.isOfType(value, String))
		{
			var f = Std.parseFloat(cast(value, String));
			return Math.isNaN(f) ? defaultValue : f;
		}

		return defaultValue;
	}

	/**
	 * Безопасный парсинг Int.
	 */
	private function parseInt(value:Dynamic, defaultValue:Int):Int
	{
		if (value == null) return defaultValue;

		if (Std.isOfType(value, Int))
		{
			return cast(value, Int);
		}

		if (Std.isOfType(value, Float))
		{
			return Std.int(cast(value, Float));
		}

		if (Std.isOfType(value, String))
		{
			var i = Std.parseInt(cast(value, String));
			return i == null ? defaultValue : i;
		}

		return defaultValue;
	}
}