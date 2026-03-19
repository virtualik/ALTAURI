package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

#if (flash || html5)
import openfl.media.Microphone;
import openfl.events.SampleDataEvent;
import openfl.utils.ByteArray;
#end

/**
* AUDIO INPUT ATOM v2.2 (Fixed Data Flow & Overrides)
* Captures audio from microphone. Active Driver.
*/
class AudioInputAtom extends Atom implements system.managers.Driver {
	// Ring Buffer Implementation
	private static inline var BUFFER_SIZE:Int = 2048; // Увеличили буфер
	private static inline var BUFFER_MASK:Int = 2047; 
	private static inline var FLUSH_THRESHOLD:Int = 256; // Отправляем данные каждые 256 сэмплов
	
	private var _buffer:Array<Float>;
	private var _writeIndex:Int = 0;
	private var _available:Int = 0;
	
	#if (flash || html5)
	private var _mic:Microphone;
	#end

	public function new(id:String) {
		super(
			[], 
			[
				new Contact(null, OUTPUT, "samples"),
				new Contact(0.0, OUTPUT, "level")
			],
			null,
			id,
			"AudioIn",
			false // Регистрируем вручную
		);

		// Initialize ring buffer
		_buffer = [];
		for (i in 0...BUFFER_SIZE) {
			_buffer.push(0.0);
		}

		#if (flash || html5)
		initMicrophone();
		#else
		trace("AudioInputAtom: Microphone API not available on this target.");
		#end
		
		// Force registration
		DriverManager.getInstance().register(this);
	}

	// Driver Interface
	override public function init():Void { }
	
	override public function update(dt:Float):Void {
		// Если микрофон работает через события (SampleDataEvent), то данные уже в буфере.
		// Этот метод нужен, чтобы принудительно слить остатки буфера, если событий давно не было.
		if (_available > 0) {
			flushBuffer();
		}
	}

	override public function dispose():Void {
		DriverManager.getInstance().unregister(this.id);
		#if (flash || html5)
		if (_mic != null) {
			_mic.removeEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);
			_mic = null;
		}
		#end
		super.dispose();
	}

	#if (flash || html5)
	private function initMicrophone():Void {
		_mic = Microphone.getMicrophone();
		if (_mic != null) {
			_mic.rate = 44; // 44.1 kHz
			_mic.setSilenceLevel(0); // Отключаем подавление тишины! Важно для синтеза
			_mic.setUseEchoSuppression(false);
			_mic.gain = 50; // Усиливаем сигнал
			_mic.addEventListener(SampleDataEvent.SAMPLE_DATA, onSampleData);
			trace("AudioInputAtom: Microphone initialized");
		} else {
			trace("AudioInputAtom: Microphone access denied or not found");
		}
	}

	private function onSampleData(e:SampleDataEvent):Void {
		var ByteArray = e.data;
		
		// Читаем все доступные сэмплы из события
		while (data.bytesAvailable >= 4) {
			var sample:Float = data.readFloat();
			
			// Пишем в кольцевой буфер
			_buffer[_writeIndex] = sample;
			_writeIndex = (_writeIndex + 1) & BUFFER_MASK;
			_available++;
			
			// Защита от переполнения (если читатель не успевает)
			if (_available > BUFFER_SIZE) {
				_available = BUFFER_SIZE;
			}
		}
		
		// ВАЖНОЕ ИСПРАВЛЕНИЕ: Не ждем полного буфера!
		// Сливаем данные порциями, как только набралось достаточно
		if (_available >= FLUSH_THRESHOLD) {
			flushBuffer();
		}
	}
	#end

	private function flushBuffer():Void {
		if (_available == 0) return;

		// Создаем массив для передачи наружу
		var outputData = new Array<Float>();
		
		// Вычисляем позицию начала чтения
		var readPos = (_writeIndex - _available + BUFFER_SIZE) & BUFFER_MASK;
		
		// Копируем доступные сэмплы
		var toRead = _available;
		if (toRead > BUFFER_SIZE) toRead = BUFFER_SIZE;

		for (i in 0...toRead) {
			outputData.push(_buffer[readPos]);
			readPos = (readPos + 1) & BUFFER_MASK;
		}

		// Отправка на выход "samples"
		if (_outputs != null && _outputs.length > 0) {
			_outputs[0].value = outputData;
		}

		// Расчет уровня (RMS) для выхода "level"
		var sum:Float = 0.0;
		for (s in outputData) {
			sum += s * s;
		}
		var rms = 0.0;
		if (outputData.length > 0) {
			rms = Math.sqrt(sum / outputData.length);
		}
		
		if (_outputs != null && _outputs.length > 1) {
			_outputs[1].value = rms;
		}

		// Сбрасываем счетчик доступных данных (они были прочитаны/отправлены)
		_available = 0;
	}
}