package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

/**
* UNIVERSAL GENERATOR ATOM v2.0 (Buffered Output)
* Генерирует波形ы в буфер (массив), а не по одному семплу.
*
* v2.0 Changes:
* - FIXED: Now outputs an array of samples (buffer) per frame.
* - This matches OscilloscopeAtom expectations and makes waves visible.
* - Square/Saw/Sine modes are now rendered correctly with proper resolution.
* 
* Modes:
* - Square: Rectangular wave (50% duty cycle)
* - Saw: Sawtooth wave (linear rise/fall)
* - Sine: Sinusoidal wave
* 
* Mode Selection Logic:
* - Exactly ONE mode input must be TRUE for generation
* - If 0, 2, or 3 modes are TRUE → output = 0 (generator disabled)
*/
class UniversalGeneratorAtom extends Atom implements system.managers.Driver {

    // === Configuration ===
    // Размер буфера. Должен совпадать с ожиданиями осциллографа (обычно 512)
    private static inline var BUFFER_SIZE:Int = 512;

    // === Mode Selection Inputs ===
    private var _modeSquare:Bool = false;
    private var _modeSaw:Bool = false;
    private var _modeSine:Bool = false;

    // === Frequency ===
    private var _frequency:Float = 440.0;

    // === Phase Tracking ===
    private var _phase:Float = 0.0;

    // === Output Buffer ===
    private var _buffer:Array<Float>;

    public function new(id:String) {
        super(
            [
                // Mode Selection Inputs (Boolean)
                new Contact(false, INPUT, "square"),
                new Contact(false, INPUT, "saw"),
                new Contact(false, INPUT, "sine"),
                // Frequency Input (Float)
                new Contact(440.0, INPUT, "freq")
            ],
            [
                // Output: Array<Float>
                new Contact(null, OUTPUT, "out")
            ],
            null,
            id,
            "UniversalGen",
            false // Register manually
        );

        // Pre-allocate buffer
        _buffer = new Array<Float>();
        for (i in 0...BUFFER_SIZE) _buffer.push(0.0);

        DriverManager.getInstance().register(this);
    }

    // =========================================================================
    // Driver Interface
    // =========================================================================

    override public function init():Void {
        _phase = 0.0;
        _frequency = 440.0;
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
                if (_frequency < 0) _frequency = 0;
                if (_frequency > 20000) _frequency = 20000;
            }
        }

        // 2. Validate mode selection
        var activeModes = 0;
        if (_modeSquare) activeModes++;
        if (_modeSaw) activeModes++;
        if (_modeSine) activeModes++;

        if (activeModes != 1) {
            // Disable output (null or empty)
            if (_outputs != null && _outputs.length > 0) _outputs[0].value = null;
            return;
        }

        // 3. Generate buffer
        // Мы моделируем "виртуальное время" для заполнения буфера, чтобы волна выглядела непрерывной.
        // step = виртуальный шаг времени между семплами в буфере.
        // Можно привязать к dt, но для осциллографа важнее частота.
        // Используем фазовый прирост на семпл.

        var phaseStep = _frequency / BUFFER_SIZE; // Нормализованная фаза

        for (i in 0...BUFFER_SIZE) {
            if (_modeSquare) {
                _buffer[i] = (_phase < 0.5) ? 1.0 : -1.0;
            } else if (_modeSaw) {
                _buffer[i] = (_phase * 2.0) - 1.0;
            } else if (_modeSine) {
                _buffer[i] = Math.sin(_phase * 2.0 * Math.PI);
            }

            _phase += phaseStep;
            if (_phase >= 1.0) _phase -= 1.0;
        }

        // 4. Output buffer
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = _buffer.copy(); // Отправляем копию массива
        }
    }

    // =========================================================================
    // State Serialization
    // =========================================================================
    
    override public function getPersistentState():Dynamic {
        return {
            frequency: _frequency,
            phase: _phase,
            modeSquare: _modeSquare,
            modeSaw: _modeSaw,
            modeSine: _modeSine
        };
    }

    override public function restoreState(state:Dynamic):Void {
        if (state != null) {
            if (state.frequency != null) _frequency = state.frequency;
            if (state.phase != null) _phase = state.phase;
            if (state.modeSquare != null) _modeSquare = state.modeSquare;
            if (state.modeSaw != null) _modeSaw = state.modeSaw;
            if (state.modeSine != null) _modeSine = state.modeSine;
        }
    }
}