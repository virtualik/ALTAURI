package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;

// Импорты только для платформ, поддерживающих Microphone
#if (flash || html5)
import openfl.media.Microphone;
import openfl.events.SampleDataEvent;
import openfl.utils.ByteArray;
#end

/**
 * AUDIO INPUT ATOM v1.1 (Cross-Platform Fix)
 * Захватывает аудио с микрофона.
 * Внимание: Работает только на Flash и HTML5.
 * На HL (Native) заглушка - атом создается, но не передает данные.
 */
class AudioInputAtom extends Atom {

    #if (flash || html5)
    private var _mic:Microphone;
    #end
    
    private var _buffer:Array<Float>;
    private static inline var BUFFER_SIZE:Int = 1024;

    public function new(id:String) {
        super(
            [], // Нет входов
            [
                new Contact(null, OUTPUT, "samples"),
                new Contact(0.0, OUTPUT, "level")
            ],
            null,
            id,
            "AudioIn",
            true // ACTIVE Driver
        );

        _buffer = new Array<Float>();
        
        #if (flash || html5)
        initMicrophone();
        #else
        // На HL/Native микрофон не поддерживается "из коробки"
        trace("AudioInputAtom: Microphone API not available on this target.");
        #end
    }

    #if (flash || html5)
    private function initMicrophone():Void {
        _mic = Microphone.getMicrophone();
        if (_mic != null) {
            _mic.rate = 44; // 44100 Hz
            _mic.setSilenceLevel(0);
            _mic.setUseEchoSuppression(false);
            _mic.addEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);
        } else {
            trace("AudioInputAtom: Microphone not found");
        }
    }

    private function onSampleData(e:SampleDataEvent):Void {
        var data:ByteArray = e.data;
        while (data.bytesAvailable >= 4) {
            var sample:Float = data.readFloat();
            _buffer.push(sample);
        }
        if (_buffer.length >= BUFFER_SIZE) {
            flushBuffer();
        }
    }
    #end

    private function flushBuffer():Void {
        if (_buffer.length == 0) return;
        
        var outputData = _buffer.splice(0, BUFFER_SIZE);

        if (_outputs[0] != null) {
            _outputs[0].value = outputData;
        }

        var sum:Float = 0;
        for (s in outputData) {
            sum += s * s;
        }
        var rms = Math.sqrt(sum / outputData.length);

        if (_outputs[1] != null) {
            _outputs[1].value = rms;
        }
    }

    override public function dispose():Void {
        #if (flash || html5)
        if (_mic != null) {
            _mic.removeEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);
        }
        #end
        super.dispose();
    }
}