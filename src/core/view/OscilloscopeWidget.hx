package core.view;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import core.base.Atom;
import core.base.Contact;
import core.base.Assembly;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import library.electro.OscilloscopeAtom;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     OSCILLOSCOPE WIDGET v2.5                              ║
 * ║                     (Real-Time Waveform Visualization)                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Визуальный компонент (Face) для атома OscilloscopeAtom.                  ║
 * ║  Отвечает за отрисовку волновых форм в реальном времени, поддержку        ║
 * ║  различных геометрий (линейная, квадратная, полярная) и режима            ║
 * ║  "Истории" (Ring Buffer) для создания эффекта послесвечения люминофора.   ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        RENDERING PIPELINE                                 ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  [Upstream Driver] ──(Array Ref)──► [OscilloscopeAtom]              │  ║
 * ║  │         │                               │                           │  ║
 * ║  │         │                               ▼                           │  ║
 * ║  │         │                  Impulsys: FRAME_READY                    │  ║
 * ║  │         │                               │                           │  ║
 * ║  │         ▼                               ▼                           │  ║
 * ║  │  [OscilloscopeWidget] ◄───────── onFrameReady()                     │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ├─► _hasNewFrame = true (Dirty Flag)                        │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ▼                                                           │  ║
 * ║  │  [OpenFL ENTER_FRAME] ──► redrawFromAtom()                          │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ├─► Atomic Snapshot (Copy Array to _renderBuffer)           │  ║
 * ║  │         │                                                           │  ║
 * ║  │         ├─► [History Mode?] ──Yes──► Ring Buffer Layer (Sprite)     │  ║
 * ║  │         │               │                                           │  ║
 * ║  │         │               No                                          │  ║
 * ║  │         │               ▼                                           │  ║
 * ║  │         └────────► [Normal Mode] ──► Canvas (Sprite)                │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     HISTORY MODE RING BUFFER                              ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  Layer 0: [ Wave N-4 ]  ◄── Oldest (будет перезаписан следующим)    │  ║
 * ║  │  Layer 1: [ Wave N-3 ]                                              │  ║
 * ║  │  Layer 2: [ Wave N-2 ]                                              │  ║
 * ║  │  Layer 3: [ Wave N-1 ]                                              │  ║
 * ║  │  Layer 4: [ Wave N   ]  ◄── Newest (Текущий индекс записи)          │  ║
 * ║  │                                                                     │  ║
 * ║  │  _currentLayer указывает на СЛЕДУЮЩИЙ слой для перезаписи.          │  ║
 * ║  │  Это создает визуальный эффект "затухания люминофора" без           │  ║
 * ║  │  необходимости вручную менять альфа-канал или использовать шейдеры. │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class OscilloscopeWidget extends DeviceView
{
	// =========================================================================
	// CONFIGURATION (Внешние параметры и цвета)
	// =========================================================================
	/** Базовая ширина виджета (для прямоугольной формы). */
	public var widgetWidth:Float = 300;
	/** Базовая высота виджета (для прямоугольной формы). */
	public var widgetHeight:Float = 150;
	/** Цвет линии осциллограммы (белый). */
	public var colorLine:Int = 0xFFFFFF;
	/** Цвет фона виджета (темно-синий/черный). */
	public var colorBg:Int = 0x0a0a12;
	/** Цвет сетки (темно-зеленый, полупрозрачный). */
	public var colorGrid:Int = 0x1a2a1a;

	// =========================================================================
	// HISTORY MODE (Режим истории / Кольцевой буфер)
	// =========================================================================
	/** Количество слоев в кольцевом буфере (глубина истории). */
	private static inline var HISTORY_LAYERS:Int = 5;
	
	/** Флаг включения режима истории. По умолчанию выключен, но может быть активирован. */
	private var _historyMode:Bool = false;
	
	/** Контейнер (Sprite), содержащий все слои истории. Позволяет перемещать их вместе. */
	private var _historyContainer:Sprite;
	
	/** Массив спрайтов, каждый из которых представляет один кадр истории. */
	private var _historyLayers:Array<Sprite>;
	
	/** Текущая позиция записи в кольцевом буфере (индекс от 0 до HISTORY_LAYERS-1). */
	private var _currentLayer:Int = 0;
	
	/** Счетчик обработанных кадров в режиме истории (используется для отладки и логирования). */
	private var _historyFrameCount:Int = 0;

	// =========================================================================
	// NORMAL MODE COMPONENTS (Компоненты обычного режима)
	// =========================================================================
	/** Основной холст для отрисовки волны в обычном режиме (один кадр). */
	private var _canvas:Sprite;
	
	/** Спрайт для отрисовки координатной сетки. */
	private var _grid:Sprite;
	
	/** Маска (Shape), которая обрезает отрисовку по границам виджета или форме круга. */
	private var _mask:Shape;
	
	/** Ссылка на связанный атом осциллографа для чтения данных и параметров. */
	private var _oscAtom:OscilloscopeAtom;

	// =========================================================================
	// FRAME SYNCHRONIZATION (Синхронизация кадров)
	// =========================================================================
	/** 
	 * Флаг "грязного" кадра (Dirty Flag). 
	 * Устанавливается в true при получении события OSCILLOSCOPE_FRAME_READY.
	 * Сбрасывается в false после отрисовки в onEnterFrame.
	 */
	private var _hasNewFrame:Bool = false;
	
	/** Флаг блокировки рендеринга (защита от рекурсивных вызовов или гонок). */
	private var _isRendering:Bool = false;
	
	/** 
	 * Локальный буфер для атомарного снимка данных (Atomic Snapshot).
	 * Копирует данные из атома, чтобы избежать "разрывов" (tearing), 
	 * если upstream драйвер обновит массив прямо во время отрисовки.
	 */
	private var _renderBuffer:Array<Float>;

	// =========================================================================
	// CONSTRUCTOR (Конструктор)
	// =========================================================================
	/**
	 * Создает виджет осциллографа и связывает его с атомом.
	 * 
	 * @param atom Базовый атом (может быть OscilloscopeAtom или Assembly, содержащий его).
	 * @param contactName Имя входного контакта (по умолчанию "in").
	 */
	public function new(atom:Atom, contactName:String = "in")
	{
		super(atom);
		
		// --- Разрешение ссылки на OscilloscopeAtom ---
		// Если передан сам осциллограф, берем его.
		if (Std.isOfType(atom, OscilloscopeAtom)) {
			_oscAtom = cast(atom, OscilloscopeAtom);
		}
		// Если передана Assembly (сборка), ищем осциллограф среди её внутренних атомов.
		else if (Std.isOfType(atom, Assembly)) {
			var asm = cast(atom, Assembly);
			for (internalAtom in asm.internalAtoms) {
				if (Std.isOfType(internalAtom, OscilloscopeAtom)) {
					_oscAtom = cast(internalAtom, OscilloscopeAtom);
					break;
				}
			}
		}
		
		// --- Инициализация UI и подписок ---
		buildUI();
		
		// Подписываемся на глобальные события Impulsys для мгновенного реагирования
		// на изменения формы и поступления новых данных, минуя стандартный цикл propagate.
		Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
		Impulsys.subscribeToImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
		
		// Синхронизируем отрисовку с частотой обновления экрана (ENTER_FRAME).
		addEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
	}

	// =========================================================================
	// WIDGET SIZE (Размеры виджета)
	// =========================================================================
	/**
	 * Возвращает текущие габариты виджета для системы компоновки (Layout Manager).
	 * В режиме истории высота умножается на количество слоев.
	 */
	override public function getWidgetSize():{width:Float, height:Float} {
		if (_historyMode) {
			return {width: widgetWidth, height: widgetHeight * HISTORY_LAYERS};
		}
		return {width: widgetWidth, height: widgetHeight};
	}

	// =========================================================================
	// UI CONSTRUCTION (Построение интерфейса)
	// =========================================================================
	/**
	 * Оркестрирует создание всех визуальных компонентов: фона, сетки, маски и холста.
	 */
	private function buildUI():Void
	{
		updateDimensions();
		drawBackground();
		
		// Создаем и добавляем сетку
		_grid = new Sprite();
		addChild(_grid);
		
		// Создаем маску и применяем её к сетке, чтобы линии сетки не выходили за границы
		_mask = new Shape();
		addChild(_mask);
		_grid.mask = _mask;
		
		drawGrid();
		drawMask();
		
		// Инициализируем холст в зависимости от выбранного режима
		if (_historyMode) {
			initHistoryLayers();
		} else {
			_canvas = new Sprite();
			addChild(_canvas);
			_canvas.mask = _mask; // Маска также применяется к холсту с волной
		}
	}

	/**
	 * Инициализирует кольцевой буфер спрайтов для режима истории.
	 * Каждый слой смещен по оси Y, чтобы они не перекрывались визуально 
	 * (хотя в текущей реализации они рисуются в одном месте, просто перезаписываются).
	 * Примечание: В v2.5 слои рисуются друг поверх друга в одном месте, 
	 * создавая эффект наложения, но y = i * widgetHeight используется для 
	 * потенциального вертикального стека, если это потребуется в будущем.
	 */
	private function initHistoryLayers():Void
	{
		_historyContainer = new Sprite();
		addChild(_historyContainer);
		_historyLayers = [];
		
		for (i in 0...HISTORY_LAYERS) {
			var layer = new Sprite();
			layer.y = i * widgetHeight; // Смещение (в текущей логике отрисовки они накладываются)
			_historyContainer.addChild(layer);
			_historyLayers.push(layer);
		}
		
		_currentLayer = 0;
		_historyFrameCount = 0;
	}

	/**
	 * Обновляет базовые размеры виджета в зависимости от выбранной геометрии (Shape).
	 * Квадрат и Круг требуют равных пропорций (200x200).
	 */
	private function updateDimensions():Void {
		if (_oscAtom == null) return;
		var shape = _oscAtom.getDisplayShape();
		switch (shape) {
			case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR:
				widgetWidth = 200;
				widgetHeight = 200;
			default:
				widgetWidth = 300;
				widgetHeight = 150;
		}
	}

	/**
	 * Отрисовывает фон и рамку виджета.
	 * Для круглой формы использует drawCircle, для остальных — drawRoundRect.
	 */
	private function drawBackground():Void {
		var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
		graphics.clear();
		graphics.beginFill(colorBg);
		
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
			graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
		else
			graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
			
		graphics.endFill();
		
		// Рамка
		graphics.lineStyle(3, 0x333355);
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR)
			graphics.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2);
		else
			graphics.drawRoundRect(0, 0, widgetWidth, widgetHeight, 5, 5);
	}

	/**
	 * Отрисовывает координатную сетку.
	 * Для круга: концентрические окружности и перекрестие.
	 * Для прямоугольника: вертикальные и горизонтальные линии с выделением центральной оси.
	 */
	private function drawGrid():Void {
		var g = _grid.graphics;
		g.clear();
		g.lineStyle(1, colorGrid, 0.7);
		var shape = (_oscAtom != null) ? _oscAtom.getDisplayShape() : OscilloscopeAtom.SHAPE_RECTANGULAR;
		
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
			var cx = widgetWidth / 2;
			var cy = widgetHeight / 2;
			var radius = widgetWidth / 2;
			// Рисуем 5 концентрических кругов
			for (i in 1...6) g.drawCircle(cx, cy, radius * (i / 5.0));
			// Рисуем перекрестие (оси X и Y)
			g.moveTo(cx - radius, cy); g.lineTo(cx + radius, cy);
			g.moveTo(cx, cy - radius); g.lineTo(cx, cy + radius);
		} else {
			// Вертикальные линии (10 делений)
			var stepX = widgetWidth / 10;
			for (i in 0...11) {
				g.moveTo(i * stepX, 0);
				g.lineTo(i * stepX, widgetHeight);
			}
			// Горизонтальные линии (6 делений)
			var stepY = widgetHeight / 6;
			for (i in 0...7) {
				g.moveTo(0, i * stepY);
				g.lineTo(widgetWidth, i * stepY);
			}
			// Центральная горизонтальная ось (нулевая линия) — делаем её ярче
			g.lineStyle(1, colorGrid, 1.0);
			g.moveTo(0, widgetHeight / 2);
			g.lineTo(widgetWidth, widgetHeight / 2);
		}
	}

    /**
     * Создает векторную маску для обрезки холста.
     * Это предотвращает выход линии осциллограммы за пределы виджета 
     * или за пределы круга при полярной развертке.
     */
    private function drawMask():Void {
        var g = _mask.graphics;
        g.clear();
        g.beginFill(0xFFFFFF); // Цвет не важен, важна альфа (непрозрачность)
        
        if ((_oscAtom != null) && (_oscAtom.getDisplayShape() == OscilloscopeAtom.SHAPE_CIRCULAR)) {
            // Радиус маски чуть меньше фона, чтобы скрыть артефакты на границе
            g.drawCircle(widgetWidth / 2, widgetHeight / 2, widgetWidth / 2 - 2);
        } else {
            // ИСПРАВЛЕНО: Добавили +1 к ширине, чтобы крайний правый пиксель волны 
            // (при x = widgetWidth) не был обрезан из-за особенностей растеризации OpenFL.
            g.drawRect(0, 0, widgetWidth + 1, widgetHeight); 
        }
        g.endFill();
    }

	// =========================================================================
	// HISTORY MODE API (Публичный API для управления режимом истории)
	// =========================================================================
	/**
	 * Включает или выключает режим истории.
	 * При изменении режима полностью перестраивает UI.
	 * 
	 * @param enabled Флаг включения.
	 */
	public function setHistoryMode(enabled:Bool):Void
	{
		if (_historyMode == enabled) return;
		_historyMode = enabled;
		
		// Полная пересборка UI для корректного переключения между Canvas и HistoryLayers
		removeChildren();
		buildUI();
		if (_oscAtom != null) syncFromAtom();
	}

	/** Возвращает текущий статус режима истории. */
	public function isHistoryMode():Bool return _historyMode;
	
	/** Возвращает индекс текущего активного слоя в кольцевом буфере. */
	public function getCurrentLayer():Int return _currentLayer;
	
	/** Возвращает общее количество отрисованных кадров в режиме истории. */
	public function getHistoryFrameCount():Int return _historyFrameCount;

	// =========================================================================
	// LIFECYCLE & EVENT HANDLERS (Жизненный цикл и обработчики событий)
	// =========================================================================
	/**
	 * Вызывается при активации виджета. Синхронизирует начальное состояние.
	 */
	override private function onActivate():Void {
		syncFromAtom();
	}

	/**
	 * Принудительная синхронизация визуала с текущим состоянием атома.
	 * Перерисовывает фон, сетку и саму волну.
	 */
	override private function syncFromAtom():Void {
		if (_oscAtom == null) return;
		updateDimensions();
		drawBackground();
		drawGrid();
		drawMask();
		
		if (_historyMode) {
			// В режиме истории ждем прихода новых кадров через onFrameReady
		} else {
			// В обычном режиме рисуем сразу, если есть данные
			redrawFromAtom();
		}
	}

	/**
	 * Реакция на изменение входных контактов (например, zoom, timeScale).
	 * Игнорирует контакт "in" (сырые данные), так как он обрабатывается через Impulsys.
	 */
	override private function onContactChanged(contact:Contact, newValue:Dynamic):Void {
		if (isDisposed || _oscAtom == null) return;
		if (contact.name == "in") return; // Данные обрабатываются в onFrameReady
		
		// При изменении параметров перерисовываем сетку и волну
		drawGrid();
		redrawFromAtom();
	}

	/**
	 * Обработчик события OSCILLOSCOPE_FRAME_READY.
	 * Устанавливает флаг _hasNewFrame, чтобы отрисовка произошла в следующем ENTER_FRAME.
	 * Это критически важно для синхронизации с частотой монитора и предотвращения tearing.
	 */
	private function onFrameReady(impulse:Impulse):Void {
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
		
		_hasNewFrame = true;
	}

	/**
	 * Обработчик события OSCILLOSCOPE_SHAPE_CHANGED.
	 * Мгновенно перестраивает UI при смене формы (например, с прямоугольника на круг) 
	 * из окна Properties, без необходимости переключать вкладки.
	 */
	private function onShapeChanged(impulse:Impulse):Void {
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_oscAtom == null || impulse.data.atomId != _oscAtom.id) return;
		
		var newShape:Int = impulse.data.shape;
		switch (newShape) {
			case OscilloscopeAtom.SHAPE_SQUARE, OscilloscopeAtom.SHAPE_CIRCULAR:
				widgetWidth = 200;
				widgetHeight = 200;
			default:
				widgetWidth = 300;
				widgetHeight = 150;
		}
		
		// Полная пересборка UI под новую геометрию
		removeChildren();
		buildUI();
	}

	/**
	 * Главный цикл рендеринга, привязанный к частоте обновления экрана (ENTER_FRAME).
	 * Проверяет флаг _hasNewFrame и запускает отрисовку, если есть новые данные.
	 */
	private function onEnterFrame(e:openfl.events.Event):Void {
		if (_hasNewFrame && !_isRendering) {
			_hasNewFrame = false;
			redrawFromAtom();
		}
	}

	// =========================================================================
	// REDRAW LOGIC (Логика перерисовки)
	// =========================================================================
	/**
	 * Основная функция отрисовки.
	 * Реализует паттерн "Atomic Snapshot": копирует массив данных из атома 
	 * в локальный _renderBuffer перед началом отрисовки.
	 * Это гарантирует, что даже если upstream драйвер изменит массив 
	 * прямо в середине цикла отрисовки, мы будем работать с консистентным снимком.
	 */
	private function redrawFromAtom():Void {
		if (_oscAtom == null) return;
		var buffer = _oscAtom.getBuffer();
		if (buffer == null || buffer.length == 0) return;
		
		_isRendering = true;
		
		// --- Atomic Snapshot ---
		var count = buffer.length;
		
		// Переаллоцируем локальный буфер только если изменился размер
		if (_renderBuffer == null || _renderBuffer.length != count) {
			_renderBuffer = new Array<Float>();
			for (i in 0...count) _renderBuffer.push(0.0);
		}
		
		// Быстрое копирование данных
		for (i in 0...count) {
			_renderBuffer[i] = buffer[i];
		}
		
		// Маршрутизация в нужный режим отрисовки
		if (_historyMode) {
			redrawHistory(_renderBuffer);
		} else {
			redrawNormal(_renderBuffer);
		}
		
		_isRendering = false;
	}

	/**
	 * Отрисовка в обычном режиме (один холст).
	 * Маршрутизирует вызов к линейному или круговому алгоритму.
	 */
	private function redrawNormal(buffer:Array<Float>):Void {
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
			drawWaveCircular(buffer);
		} else {
			drawWaveLinear(buffer);
		}
	}

	/**
	 * Отрисовка в режиме истории (Ring Buffer).
	 * Очищает самый старый слой и рисует на нем новую волну, 
	 * затем сдвигает указатель _currentLayer.
	 */
	private function redrawHistory(buffer:Array<Float>):Void {
		var layer = _historyLayers[_currentLayer];
		var g = layer.graphics;
		
		// Очищаем текущий слой (который является самым старым в кольцевом буфере)
		g.clear();
		
		// Рисуем новую волну на этом слое
		var shape = _oscAtom.getDisplayShape();
		if (shape == OscilloscopeAtom.SHAPE_CIRCULAR) {
			drawWaveCircular(buffer, g);
		} else {
			drawWaveLinear(buffer, g);
		}
		
		// Сдвигаем указатель кольцевого буфера
		_currentLayer = (_currentLayer + 1) % HISTORY_LAYERS;
		_historyFrameCount++;
		
		// Отладочный вывод каждые 10 кадров
		if (_historyFrameCount % 10 == 0) {
			trace('OscilloscopeWidget: History frame $_historyFrameCount, next layer to clear: $_currentLayer');
		}
	}

	// =========================================================================
	// WAVE DRAWING (Алгоритмы отрисовки волн)
	// =========================================================================
	/**
	 * Отрисовка линейной (декартовой) волны.
	 * 
	 * ИСПРАВЛЕНО: Шаг по X (stepX) рассчитывается как `widgetWidth / (count - 1)`.
	 * Это гарантирует, что последняя точка волны будет иметь координату X = widgetWidth,
	 * и волна физически растянется на всю ширину виджета без отступов по краям.
	 * 
	 * @param buffer Массив сэмплов (снимок).
	 * @param targetGraphics Целевой контекст графики (если null, используется _canvas).
	 */
	private function drawWaveLinear(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void {
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
		
		// === КРИТИЧЕСКИЙ FIX: Всегда очищаем холст перед отрисовкой ===
		g.clear();
		
		if (targetGraphics == null) {
			_canvas.mask = _mask;
		}
		
		var count = buffer.length;
		if (count == 0) return;
		
		// === Decimation: прореживание сэмплов ===
		var decimation = (_oscAtom != null) ? _oscAtom.getDecimation() : 1;
		if (decimation < 1) decimation = 1;
		
		var effectiveCount = Math.ceil(count / decimation);
		if (effectiveCount < 2) effectiveCount = 2;
		
		var zoom = _oscAtom.getZoom();
		var centerY = widgetHeight / 2.0;
		var scale = (widgetHeight / 2.0) * 0.9 * zoom;
		
		// === FIX: Рассчитываем шаг для эффективного количества точек ===
		var stepX = widgetWidth / (effectiveCount - 1);
		
		g.lineStyle(3.0, colorLine, 1.0);
		
		// Первая точка
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 1.0) sample = 1.0;
		if (sample < -1.5) sample = -1.5;
		
		g.moveTo(0, centerY - sample * scale);
		
		// Отрисовка с прореживанием
		var drawIndex = 0;
		for (i in 1...count) {
			if (i % decimation != 0 && i != count - 1) continue;  // ← Пропускаем сэмплы
			
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 10) sample = 10;
			if (sample < -1.5) sample = -1.5;
			
			drawIndex++;
			g.lineTo(drawIndex * stepX, centerY - sample * scale);
		}
	}

	/**
	 * Отрисовка круговой (полярной) волны.
	 * Амплитуда сэмпла маппится на радиус. 
	 * Угол равномерно распределяется по длине буфера (от 0 до 2*PI).
	 * 
	 * @param buffer Массив сэмплов.
	 * @param targetGraphics Целевой контекст графики.
	 */
	private function drawWaveCircular(buffer:Array<Float>, ?targetGraphics:openfl.display.Graphics = null):Void {
		var g = targetGraphics != null ? targetGraphics : _canvas.graphics;
		
		// === КРИТИЧЕСКИЙ FIX: Всегда очищаем холст ===
		g.clear();
		
		var count = buffer.length;
		var decimation = (_oscAtom != null) ? _oscAtom.getDecimation() : 1;
		if (decimation < 1) decimation = 1;
		
		var effectiveCount = Math.ceil(count / decimation);
		if (effectiveCount < 2) effectiveCount = 2;
		
		var zoom = _oscAtom.getZoom();
		var cx = widgetWidth / 2;
		var cy = widgetHeight / 2;
		var maxRadius = (widgetWidth / 2) * 0.9 * zoom;
		
		g.lineStyle(1.0, colorLine, 1.0);
		
		var sample = buffer[0];
		if (!Math.isFinite(sample)) sample = 0.0;
		if (sample > 1.0) sample = 1.0;
		if (sample < -1.0) sample = -1.0;
		
		var angle:Float = 0.0;
		var r = ((sample + 1.0) / 2.0) * maxRadius;
		g.moveTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		
		var drawIndex = 0;
		for (i in 1...count) {
			if (i % decimation != 0 && i != count - 1) continue;
			
			sample = buffer[i];
			if (!Math.isFinite(sample)) sample = 0.0;
			if (sample > 1.0) sample = 1.0;
			if (sample < -1.0) sample = -1.0;
			
			drawIndex++;
			angle = (drawIndex / effectiveCount) * Math.PI * 2;
			r = ((sample + 1.0) / 2.0) * maxRadius;
			g.lineTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
		}
	}

	// =========================================================================
	// CLEAR & DISPOSE (Очистка и освобождение ресурсов)
	// =========================================================================
	/**
	 * Очищает экран от нарисованных волн.
	 * В режиме истории очищает все слои кольцевого буфера и сбрасывает указатели.
	 */
	public function clearDisplay():Void {
		if (_historyMode) {
			for (layer in _historyLayers) {
				if (layer != null) layer.graphics.clear();
			}
			_currentLayer = 0;
			_historyFrameCount = 0;
		} else if (_canvas != null) {
			_canvas.graphics.clear();
		}
	}

	/** Алиас для полной очистки (совместимость). */
	public function clearAll():Void {
		clearDisplay();
	}

	/**
	 * Освобождение ресурсов виджета.
	 * Отписывается от событий Impulsys, удаляет слушатели ENTER_FRAME 
	 * и обнуляет ссылки для помощи Garbage Collector'у.
	 */
	override public function dispose():Void {
		removeEventListener(openfl.events.Event.ENTER_FRAME, onEnterFrame);
		Impulsys.removeImpulse(EventType.OSCILLOSCOPE_SHAPE_CHANGED, onShapeChanged);
		Impulsys.removeImpulse(EventType.OSCILLOSCOPE_FRAME_READY, onFrameReady);
		
		_canvas = null;
		_grid = null;
		_mask = null;
		_oscAtom = null;
		_renderBuffer = null;
		_historyLayers = null;
		_historyContainer = null;
		
		super.dispose();
	}
}