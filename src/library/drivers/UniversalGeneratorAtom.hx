package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

/**
 * UNIVERSAL GENERATOR ATOM v3.0 (Time-Based Smooth Generation)
 * 
 * ИСПРАВЛЕНИЯ v3.0:
 * - Полностью переписана математика генерации.
 * - Использует реальное время и фазу для непрерывности волны.
 * - Буфер теперь представляет окно времени (Time Window), а не фиксированное количество периодов.
 * - Устранена зависимость от FPS.
 * - Устранен алиасинг (рывки) за счет правильного масштабирования.
 */
class UniversalGeneratorAtom extends Atom implements system.managers.Driver {

    // === Configuration ===
    // Размер буфера. Должен совпадать с ожиданиями осциллографа.
    private static inline var BUFFER_SIZE:Int = 512;

    // Временное окно в секундах.
    // 0.01 сек = 10 мс. При 440 Гц это ~4.4 периода. Идеально для визуализации.
    // Для низких частот (1 Гц) будет видно 0.01 периода (кусочек).
    // Можно сделать динамическим, но для генератора это хорошее значение по умолчанию.
    private static inline var TIME_WINDOW:Float = 0.01; 

    // === Mode Selection Inputs ===
    private var _modeSquare:Bool = false;
    private var _modeSaw:Bool = false;
    private var _modeSine:Bool = false;

    // === Frequency ===
    private var _frequency:Float = 440.0;

    // === Phase Tracking (Непрерывная фаза) ===
    private var _currentPhase:Float = 0.0;

    // === Output Buffer ===
    private var _buffer:Array<Float>;

    public function new(id:String) {
        super(
            [
                new Contact(false, INPUT, "square"),
                new Contact(false, INPUT, "saw"),
                new Contact(false, INPUT, "sine"),
                new Contact(440.0, INPUT, "freq")
            ],
            [
                new Contact(null, OUTPUT, "out")
            ],
            null,
            id,
            "UniversalGen",
            false
        );

        _buffer = new Array<Float>();
        for (i in 0...BUFFER_SIZE) _buffer.push(0.0);

        DriverManager.getInstance().register(this);
    }

    // =========================================================================
    // Driver Interface
    // =========================================================================

    override public function init():Void {
        _currentPhase = 0.0;
    }

    override public function update(dt:Float):Void {
        generateBuffer(dt);
    }

    override public function dispose():Void {
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // =========================================================================
    // Core Generation Logic
    // =========================================================================

    private function generateBuffer(dt:Float):Void {
        // 1. Read inputs
        if (_inputs != null && _inputs.length >= 4) {
            _modeSquare = _inputs[0].value == true;
            _modeSaw = _inputs[1].value == true;
            _modeSine = _inputs[2].value == true;

            var f = _inputs[3].value;
            if (f != null) {
                if (Std.isOfType(f, Float)) _frequency = cast(f, Float);
                else if (Std.isOfType(f, Int)) _frequency = cast(f, Float);
                
                // Защита от некорректных значений
                if (_frequency < 0.1) _frequency = 0.1;
                if (_frequency > 20000) _frequency = 20000;
            }
        }

        // 2. Validate mode
        var activeModes = 0;
        if (_modeSquare) activeModes++;
        if (_modeSaw) activeModes++;
        if (_modeSine) activeModes++;

        // Если режим не выбран или выбрано несколько - тишина
        if (activeModes != 1) {
            // Можно оставить старые данные или обнулить.
            // Для "стабильности" картинки при переключении - лучше не трогать буфер или выводить 0.
            if (_outputs != null && _outputs.length > 0) _outputs[0].value = null;
            return;
        }

        // 3. Продвигаем фазу вперед на время, прошедшее с прошлого кадра (dt)
        // Это обеспечивает непрерывность волны независимо от FPS
        _currentPhase += _frequency * 2.0 * Math.PI * dt;
        
        // Нормализация фазы (не обязательно, но полезно для больших времен работы)
        // Используем while на случай огромных dt (лаги системы)
        while (_currentPhase > 2.0 * Math.PI) {
            _currentPhase -= 2.0 * Math.PI;
        }

        // 4. Generate buffer (Снимок волны в текущий момент)
        // Мы рисуем буфер, который показывает "срез" времени TIME_WINDOW.
        // Точка i в буфере соответствует времени t = i * (TIME_WINDOW / BUFFER_SIZE)
        
        var sampleInterval = TIME_WINDOW / BUFFER_SIZE;

        for (i in 0...BUFFER_SIZE) {
            // Время для данного сэмпла относительно начала окна
            var t = i * sampleInterval;
            
            // Полная фаза для этого сэмпла = текущая фаза + смещение по времени
            var phase = _currentPhase + (_frequency * 2.0 * Math.PI * t);
            
            // Нормализуем для пилы (нужна фаза 0..1)
            var normalizedPhase = (phase / (2.0 * Math.PI)) % 1.0;
            if (normalizedPhase < 0) normalizedPhase += 1.0;

            if (_modeSquare) {
                // Меандр (50% duty cycle)
                _buffer[i] = (normalizedPhase < 0.5) ? 1.0 : -1.0;
            } 
            else if (_modeSaw) {
                // Пила: от -1 до 1
                _buffer[i] = 2.0 * normalizedPhase - 1.0;
            } 
            else if (_modeSine) {
                // Синус
                _buffer[i] = Math.sin(phase);
            }
        }

        // 5. Output buffer
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = _buffer.copy();
        }
    }

    // =========================================================================
    // State Serialization
    // =========================================================================

    override public function getPersistentState():Dynamic {
        return {
            frequency: _frequency,
            phase: _currentPhase,
            modeSquare: _modeSquare,
            modeSaw: _modeSaw,
            modeSine: _modeSine
        };
    }

    override public function restoreState(state:Dynamic):Void {
        if (state != null) {
            if (state.frequency != null) _frequency = state.frequency;
            if (state.phase != null) _currentPhase = state.phase;
            if (state.modeSquare != null) _modeSquare = state.modeSquare;
            if (state.modeSaw != null) _modeSaw = state.modeSaw;
            if (state.modeSine != null) _modeSine = state.modeSine;
        }
    }
}