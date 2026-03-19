package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

/**
* SIGNAL GENERATOR ATOM v3.0 (Time-Accurate)
* Generates sine wave with accurate time scaling.
* Output buffer always represents exactly 1 second of signal.
*/
class SignalGeneratorAtom extends Atom implements system.managers.Driver {
	// === CONFIGURATION ===
	// Сколько времени (в секундах) охватывает выходной буфер
	// Осциллограф будет показывать ровно этот отрезок времени
	private static inline var TIME_WINDOW_SECONDS:Float = 1.0;
	
	// Количество точек для отрисовки (разрешение графика)
	// Должно совпадать с тем, что ожидает осциллограф для красивой картинки
	private static inline var DISPLAY_SAMPLES:Int = 512;

	// === STATE ===
	private var _frequency:Float = 440.0;
	private var _phase:Float = 0.0;
	private var _buffer:Array<Float>;

	public function new(id:String) {
		super(
			[ new Contact(440.0, INPUT, "freq") ],
			[ new Contact(null, OUTPUT, "out") ],
			null,
			id,
			"SignalGen",
			false // Регистрируем вручную
		);

		// Pre-allocate buffer
		_buffer = new Array<Float>();
		for (i in 0...DISPLAY_SAMPLES) {
			_buffer.push(0.0);
		}

		// Register with DriverManager
		DriverManager.getInstance().register(this);
	}

	// --- Driver Interface ---
	override public function init():Void { }

	override public function update(dt:Float):Void {
		generateTimeWindow(dt);
	}

	override public function dispose():Void {
		DriverManager.getInstance().unregister(this.id);
		super.dispose();
	}

	// --- Core Logic ---
	private function generateTimeWindow(dt:Float):Void {
		// 1. Update frequency from input
		if (_inputs != null && _inputs.length > 0 && _inputs[0].value != null) {
			var f = _inputs[0].value;
			if (Std.isOfType(f, Float)) _frequency = cast(f, Float);
			else if (Std.isOfType(f, Int)) _frequency = cast(f, Float);
		}

		// Clamp frequency to valid range
		if (_frequency < 0.0) _frequency = 0.0;
		if (_frequency > 20000.0) _frequency = 20000.0; // Nyquist limit for 44.1kHz

		// 2. Generate samples for the time window
		// We generate samples representing [now, now + TIME_WINDOW_SECONDS]
		// This ensures the oscilloscope always shows exactly TIME_WINDOW_SECONDS of signal
		
		var sampleInterval = TIME_WINDOW_SECONDS / DISPLAY_SAMPLES;
		
		for (i in 0...DISPLAY_SAMPLES) {
			// Time offset for this sample relative to "now"
			var t = i * sampleInterval;
			
			// Calculate phase at this specific time
			// phase(t) = current_phase + 2*PI*freq*t
			var samplePhase = _phase + (_frequency * 2.0 * Math.PI * t);
			
			_buffer[i] = Math.sin(samplePhase);
		}

		// 3. Advance the "current" phase for the next frame
		// This keeps the waveform continuous between updates
		_phase += _frequency * 2.0 * Math.PI * dt;
		
		// Keep phase bounded to avoid floating point drift
		if (_phase > 2.0 * Math.PI) {
			_phase -= 2.0 * Math.PI;
		}

		// 4. Send data to output
		if (_outputs != null && _outputs.length > 0) {
			// Send a copy to ensure change detection in the contact system
			_outputs[0].value = _buffer.copy();
		}
	}

	// --- State Serialization ---
	override public function getPersistentState():Dynamic {
		return { frequency: _frequency, phase: _phase };
	}

	override public function restoreState(state:Dynamic):Void {
		if (state != null) {
			if (state.frequency != null) _frequency = state.frequency;
			if (state.phase != null) _phase = state.phase;
		}
	}
}