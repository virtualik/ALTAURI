package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * SIGNAL GENERATOR ATOM v1.3 (State Serialization)
 * Генерирует синусоиду заданной частоты.
 * 
 * v1.2: Создает новый массив каждый кадр.
 * ПРИЧИНА: Contact проверяет равенство ссылок. Если массив тот же,
 * сигнал не передается. Для потока данных нужен новый объект.
 * 
 * v1.3 Changes:
 * - Added getPersistentState() for saving frequency and phase
 * - Added restoreState() for restoring generator settings on load
 */
class SignalGeneratorAtom extends Atom {

    // Настройки генерации
    private var _frequency:Float = 440.0;
    private var _sampleRate:Float = 44100.0;

    // Внутреннее состояние
    private var _phase:Float = 0.0;
    private var _samplesPerFrame:Int = 512;

    public function new(id:String) {
        super(
            [
                new Contact(440.0, INPUT, "freq")
            ],
            [
                new Contact(null, OUTPUT, "out")
            ],
            null,
            id,
            "SignalGen",
            true // ACTIVE!
        );
    }

    override private function _onUpdate(dt:Float):Void {
        generateSamples();
    }

    private function generateSamples():Void {
        if (_inputs != null && _inputs.length > 0 && _inputs[0].value != null) {
            var f = _inputs[0].value;
            if (Std.isOfType(f, Float)) {
                _frequency = cast(f, Float);
            }
        }

        var phaseStep = (_frequency * 2 * Math.PI) / _sampleRate;

        // ИСПРАВЛЕНИЕ: Создаем НОВЫЙ массив каждый кадр.
        // Это необходимо, чтобы Contact увидел изменение и передал сигнал дальше.
        var buffer:Array<Float> = new Array<Float>();

        for (i in 0..._samplesPerFrame) {
            var sample = Math.sin(_phase);
            buffer.push(sample);

            _phase += phaseStep;
            if (_phase > 2 * Math.PI) {
                _phase -= 2 * Math.PI;
            }
        }

        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = buffer;
        }
    }

    // =========================================================================
    // STATE SERIALIZATION v1.3
    // =========================================================================

    /**
     * Save generator state for persistence.
     * Returns current frequency and phase so generation can continue from where it left off.
     */
    override public function getPersistentState():Dynamic {
        return { 
            frequency: _frequency,
            phase: _phase,
            sampleRate: _sampleRate
        };
    }

    /**
     * Restore generator state from saved data.
     * Called when loading a project to restore the generator's frequency and phase.
     */
    override public function restoreState(state:Dynamic):Void {
        if (state != null) {
            if (state.frequency != null) {
                _frequency = state.frequency;
                // Also update the input contact if it has default value
                if (_inputs != null && _inputs.length > 0 && _inputs[0].value == 440.0) {
                    _inputs[0].value = _frequency;
                }
            }
            if (state.phase != null) {
                _phase = state.phase;
            }
            if (state.sampleRate != null) {
                _sampleRate = state.sampleRate;
            }
        }
    }

    /**
     * Get current frequency (for UI display).
     */
    public function getFrequency():Float {
        return _frequency;
    }

    /**
     * Set frequency directly (for UI control).
     */
    public function setFrequency(value:Float):Void {
        _frequency = value;
    }
}
