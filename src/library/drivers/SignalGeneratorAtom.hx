package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

/**
 * SIGNAL GENERATOR ATOM v1.0
 * Генерирует синусоиду заданной частоты.
 * Работает как Driver, обновляя буфер каждый кадр.
 */
class SignalGeneratorAtom extends Atom {

    // Настройки генерации
    private var _frequency:Float = 440.0; // Частота (Гц), 440 - Ля
    private var _sampleRate:Float = 44100.0; // Качество звука
    
    // Внутреннее состояние
    private var _phase:Float = 0.0;
    private var _samplesPerFrame:Int = 512; // Размер буфера на кадр

    public function new(id:String) {
        super(
            [
                // Вход: Частота (можно менять в рантайме)
                new Contact(440.0, INPUT, "freq") 
            ],
            [
                // Выход: Массив сэмплов (буфер)
                new Contact(null, OUTPUT, "out") 
            ],
            null,
            id,
            "SignalGen",
            true // ACTIVE!
        );
    }

    // Вызывается каждый кадр (Driver)
    override private function _onUpdate(dt:Float):Void {
        generateSamples();
    }

    private function generateSamples():Void {
        // Если на входе есть частота, берем её
        if (_inputs != null && _inputs.length > 0 && _inputs[0].value != null) {
            var f = _inputs[0].value;
            if (Std.isOfType(f, Float)) {
                _frequency = cast(f, Float);
            }
        }

        var buffer:Array<Float> = new Array<Float>();
        
        var phaseStep = (_frequency * 2 * Math.PI) / _sampleRate;

        for (i in 0..._samplesPerFrame) {
            // Генерируем синусоиду от -1.0 до 1.0
            var sample = Math.sin(_phase);
            buffer.push(sample);

            _phase += phaseStep;
            
            // Зацикливаем фазу, чтобы не переполнить Float
            if (_phase > 2 * Math.PI) {
                _phase -= 2 * Math.PI;
            }
        }

        // Отправляем готовый буфер на выход
        if (_outputs != null && _outputs.length > 0) {
            _outputs[0].value = buffer;
        }
    }
}