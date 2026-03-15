package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * SIGNAL GENERATOR ATOM v1.2 (Streaming Fix)
 * Генерирует синусоиду заданной частоты.
 * v1.2: Создает новый массив каждый кадр.
 * ПРИЧИНА: Contact проверяет равенство ссылок. Если массив тот же,
 * сигнал не передается. Для потока данных нужен новый объект.
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
}