package library.drivers;
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import system.managers.DriverManager;

/**
* UNIVERSAL GENERATOR ATOM v1.0 (Real-Time Single Sample)
* Generates waveforms in real-time, outputting one sample per update.
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
	// === Mode Selection Inputs ===
	private var _modeSquare:Bool = false;
	private var _modeSaw:Bool = false;
	private var _modeSine:Bool = false;
	
	// === Frequency ===
	private var _frequency:Float = 440.0;
	
	// === Phase Tracking (0.0 to 1.0 represents one full cycle) ===
	private var _phase:Float = 0.0;
	
	// === Output Contact Reference ===
	private var _outputContact:Contact;

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
				// Single Sample Output (Float)
				new Contact(0.0, OUTPUT, "out")
			],
			null,
			id,
			"UniversalGen",
			false // Register manually in constructor
		);
		
		_outputContact = _outputs[0];
		
		// Register with DriverManager
		DriverManager.getInstance().register(this);
	}

	// =========================================================================
	// Driver Interface
	// =========================================================================
	override public function init():Void {
		_phase = 0.0;
		_frequency = 440.0;
		_modeSquare = false;
		_modeSaw = false;
		_modeSine = false;
		if (_outputContact != null) {
			_outputContact.value = 0.0;
		}
	}

	override public function update(dt:Float):Void {
		generateSample(dt);
	}

	override public function dispose():Void {
		DriverManager.getInstance().unregister(this.id);
		super.dispose();
	}

	// =========================================================================
	// Core Generation Logic
	// =========================================================================
	private function generateSample(dt:Float):Void {
		// 1. Read mode selection inputs
		if (_inputs != null && _inputs.length >= 4) {
			// Read boolean mode inputs
			var sq = _inputs[0].value;
			var sw = _inputs[1].value;
			var sn = _inputs[2].value;
			
			_modeSquare = (sq == true);
			_modeSaw = (sw == true);
			_modeSine = (sn == true);
			
			// Read frequency
			var f = _inputs[3].value;
			if (f != null) {
				if (Std.isOfType(f, Float)) _frequency = cast(f, Float);
				else if (Std.isOfType(f, Int)) _frequency = cast(f, Float);
			}
		}
		
		// 2. Validate mode selection (EXACTLY ONE must be true)
		var activeModes = 0;
		if (_modeSquare) activeModes++;
		if (_modeSaw) activeModes++;
		if (_modeSine) activeModes++;
		
		// If 0, 2, or 3 modes active → disable output
		if (activeModes != 1) {
			if (_outputContact != null) {
				_outputContact.value = 0.0;
			}
			// Don't advance phase when disabled (keeps waveform continuous on re-enable)
			return;
		}
		
		// 3. Clamp frequency to valid range
		if (_frequency < 0.0) _frequency = 0.0;
		if (_frequency > 20000.0) _frequency = 20000.0;
		
		// 4. Generate waveform based on active mode
		var sample:Float = 0.0;
		
		if (_modeSquare) {
			sample = generateSquare();
		} else if (_modeSaw) {
			sample = generateSaw();
		} else if (_modeSine) {
			sample = generateSine();
		}
		
		// 5. Output single sample value (real-time, no batching)
		if (_outputContact != null) {
			_outputContact.value = sample;
		}
		
		// 6. Advance phase for next sample
		// phase increment = frequency * dt (fraction of cycle per frame)
		_phase += _frequency * dt;
		if (_phase >= 1.0) {
			_phase -= 1.0; // Keep phase in [0, 1) range
		}
	}
	
	// =========================================================================
	// Waveform Generators
	// All return values in range [-1.0, 1.0]
	// =========================================================================
	
	/**
	* Square wave: +1 for first half of cycle, -1 for second half
	* 50% duty cycle (equal rise/fall time)
	*/
	private function generateSquare():Float {
		return (_phase < 0.5) ? 1.0 : -1.0;
	}
	
	/**
	* Sawtooth wave: linear rise from -1 to +1 over one cycle
	* Equal rise/fall portions (symmetric)
	*/
	private function generateSaw():Float {
		// Map phase [0, 1) to output [-1, 1]
		return (_phase * 2.0) - 1.0;
	}
	
	/**
	* Sine wave: standard sinusoidal
	*/
	private function generateSine():Float {
		// phase is [0, 1), convert to radians [0, 2*PI)
		return Math.sin(_phase * 2.0 * Math.PI);
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