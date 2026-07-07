package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;
import system.managers.DriverManager;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     SIGNAL GENERATOR ATOM v1.0                            ║
 * ║                     (Quantized Output System)                             ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Signal generator with amplitude quantization.                            ║
 * ║  Outputs value to output contact ONLY when quantum                        ║
 * ║  amplitude value changes.                                                 ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                        ARCHITECTURE                                       ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     SignalGenerator                                 │  ║
 * ║  │                                                                     │  ║
 * ║  │  A) COMPUTE MODULE:                                                 │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     update(dt) {                                                    │  ║
 * ║  │         1. Generate raw signal by formula                           │  ║
 * ║  │         2. Quantize amplitude                                       │  ║
 * ║  │         3. Compare with previous quantum                            │  ║
 * ║  │         4. If changed → output.value = newQuantum                   │  ║
 * ║  │     }                                                               │  ║
 * ║  │                                                                     │  ║
 * ║  │  B) DATABANK:                                                       │  ║
 * ║  │     ─────────────                                                   │  ║
 * ║  │     _frequency:Float     - Generation frequency (Hz)                │  ║
 * ║  │     _quantumStep:Float   - Amplitude quantization step              │  ║
 * ║  │     _currentPhase:Float  - Current signal phase                     │  ║
 * ║  │     _lastQuantum:Float   - Last quantized value                     │  ║
 * ║  │     _mode:Int            - Generation mode (0=OFF, 1=SQR, 2=SAW...) │  ║
 * ║  │                                                                     │  ║
 * ║  │  C) INPUTS:                                                         │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "freq"    - Frequency (Float)                                   │  ║
 * ║  │     "quantum"  - Quantization step (Float, 0.01..1.0)               │  ║
 * ║  │     "mode"     - Mode (Int: 0=OFF, 1=SQR, 2=SAW, 3=SIN, 4=TRI)      │  ║
 * ║  │                                                                     │  ║
 * ║  │  D) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     "out"     - Quantized amplitude value (Float)                   │  ║
 * ║  │     "changed"  - Pulse on quantum change (Bool, short-lived)        │  ║
 * ║  │                                                                     │  ║
 * ║  │  E) FACE (DeviceView):                                              │  ║
 * ║  │     ─────────────────                                               │  ║
 * ║  │     TextWidget or OscilloscopeWidget for display                    │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                      WORKING PRINCIPLE                                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Example for sine wave with quantum = 0.25:                               ║
 * ║                                                                           ║
 * ║  Amplitude                                                                ║
 * ║    1.0 ┤         ╭──────╮         ╭──────╮                                ║
 * ║    0.75┤        ╭╯      ╰╮       ╭╯      ╰╮    ← Quantum = 0.75           ║
 * ║    0.50┤       ╭╯        ╰╮     ╭╯        ╰╮   ← Quantum = 0.50           ║
 * ║    0.25┤      ╭╯          ╰╮   ╭╯          ╰╮  ← Quantum = 0.25           ║
 * ║    0.00┼──────╯            ╰───╯            ╰─ ← Quantum = 0.00           ║
 * ║   -0.25┤                                      ╰╮ ← Quantum = -0.25        ║
 * ║   -0.50┤                                        ╰╮← Quantum = -0.50       ║
 * ║   -0.75┤                                         ╰                        ║
 * ║   -1.0 ┤                                                                  ║
 * ║        └─────────────────────────────────────────► Time                   ║
 * ║                                                                           ║
 * ║  Output pulses (changed):                                                 ║
 * ║         _|  |_|  |_|  |_|  |_|  |_|  |_|  |_|  |_                         ║
 * ║           ↑    ↑    ↑    ↑    ↑    ↑    ↑    ↑                            ║
 * ║         Each time signal crosses quantum boundary                         ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     GENERATION MODES                                      ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  MODE 0: OFF        - Generation disabled, output = 0                     ║
 * ║  MODE 1: SQUARE     - Square Wave                                         ║
 * ║  MODE 2: SAWTOOTH   - Sawtooth Wave                                       ║
 * ║  MODE 3: SINE       - Sine Wave                                           ║
 * ║  MODE 4: TRIANGLE   - Triangle Wave                                       ║
 * ║  MODE 5: NOISE      - Noise (Random)                                      ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                    APPLICATION                                            ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  • Digital-to-analog converters (DAC)                                     ║
 * ║  • Event-driven control systems                                           ║
 * ║  • Data transmission optimization (send only changes)                     ║
 * ║  • Module synchronization by signal level change                          ║
 * ║  • Trigger pulse generation                                               ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class SignalGenerator extends Atom implements system.managers.Driver
{
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    /**
     * Minimum quantization step.
     */
    private static inline var MIN_QUANTUM:Float = 0.001;
    
    /**
     * Maximum quantization step.
     */
    private static inline var MAX_QUANTUM:Float = 1.0;
    
    /**
     * Minimum frequency (Hz).
     */
    private static inline var MIN_FREQUENCY:Float = 0.1;
    
    /**
     * Maximum frequency (Hz).
     */
    private static inline var MAX_FREQUENCY:Float = 20000.0;
    
    /**
     * Duration of 'changed' pulse (in seconds).
     */
    private static inline var PULSE_DURATION:Float = 0.05;

    // =========================================================================
    // GENERATION MODES
    // =========================================================================
    private static inline var MODE_OFF:Int        = 0;
    private static inline var MODE_SQUARE:Int     = 1;
    private static inline var MODE_SAWTOOTH:Int   = 2;
    private static inline var MODE_SINE:Int       = 3;
    private static inline var MODE_TRIANGLE:Int   = 4;
    private static inline var MODE_NOISE:Int      = 5;

    // =========================================================================
    // DATABANK - Parameters
    // =========================================================================
    /**
     * Generation frequency in Hertz.
     */
    private var _frequency:Float = 440.0;
    
    /**
     * Amplitude quantization step.
     */
    private var _quantumStep:Float = 0.1;
    
    /**
     * Current generation mode.
     */
    private var _mode:Int = MODE_OFF;

    // =========================================================================
    // DATABANK - State
    // =========================================================================
    /**
     * Current signal phase (radians).
     */
    private var _currentPhase:Float = 0.0;
    
    /**
     * Last quantized value.
     * Used for change detection.
     */
    private var _lastQuantum:Float = 0.0;
    
    /**
     * First frame flag (for initialization).
     */
    private var _isFirstUpdate:Bool = true;
    
    /**
     * Time until 'changed' pulse reset.
     */
    private var _pulseTimer:Float = 0.0;
    
    /**
     * Active 'changed' pulse flag.
     */
    private var _pulseActive:Bool = false;
    
    /**
     * Output pulse counter (statistics).
     */
    private var _pulseCount:Int = 0;
    
    /**
     * Total runtime.
     */
    private var _totalTime:Float = 0.0;
    
    /**
     * Update counter.
     */
    private var _updateCount:Int = 0;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new(id:String)
    {
        super(
            // === INPUTS ===
            [
                new Contact(440.0, INPUT, "freq"),     // Frequency
                new Contact(0.1, INPUT, "quantum"),    // Quantization step
                new Contact(0, INPUT, "mode")          // Generation mode
            ],
            // === OUTPUTS ===
            [
                new Contact(0.0, OUTPUT, "out"),       // Quantized value
                new Contact(false, OUTPUT, "changed")  // Pulse on quantum change
            ],
            // === PROCESS FUNCTION ===
            null,
            id,
            "SignalGenerator",
            true  // isActive = true (register in DriverManager)
        );
        
        var outContact = getOutput("out");
        if (outContact != null)
        {
            outContact.ignoreOscillation = true;
        }
        
        trace('SignalGenerator: Created (id: $id)');
    }

    // =========================================================================
    // LIFECYCLE - Driver Interface
    // =========================================================================
    /**
     * Driver initialization.
     */
    override public function init():Void
    {
        _currentPhase = 0.0;
        _lastQuantum = 0.0;
        _isFirstUpdate = true;
        _pulseTimer = 0.0;
        _pulseActive = false;
        _pulseCount = 0;
        _totalTime = 0.0;
        _updateCount = 0;
        
        trace('SignalGenerator: Initialized');
    }

    /**
     * Update every frame - main generation logic.
     * Called from DriverManager.update().
     *
     * @param dt Delta time in seconds
     */
    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        
        _updateCount++;
        _totalTime += dt;
        
        // 1. Read input parameters
        readInputs();
        
        // 2. Manage 'changed' pulse
        updatePulse(dt);
        
        // 3. If generation disabled - exit
        if (_mode == MODE_OFF)
        {
            setOutputQuantized(0.0);
            return;
        }
        
        // 4. Advance phase
        advancePhase(dt);
        
        // 5. Generate raw signal
        var rawValue = generateRawSignal();
        
        // 6. Quantize value
        var newQuantum = quantizeValue(rawValue);
        
        // 7. Check change and update output
        updateOutput(newQuantum);
    }

    /**
     * Free resources.
     */
    override public function dispose():Void
    {
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
        
        trace('SignalGenerator: Disposed (pulses: $_pulseCount)');
    }

    // =========================================================================
    // INPUT READING
    // =========================================================================
    /**
     * Read values from input contacts.
     */
    private function readInputs():Void
    {
        // Frequency
        var freqContact = getInput("freq");
        if (freqContact != null && freqContact.value != null)
        {
            var f = parseFloat(freqContact.value, _frequency);
            if (f >= MIN_FREQUENCY && f <= MAX_FREQUENCY)
            {
                _frequency = f;
            }
        }
        
        // Quantization step
        var quantumContact = getInput("quantum");
        if (quantumContact != null && quantumContact.value != null)
        {
            var q = parseFloat(quantumContact.value, _quantumStep);
            if (q >= MIN_QUANTUM && q <= MAX_QUANTUM)
            {
                _quantumStep = q;
            }
        }
        
        // Mode
        var modeContact = getInput("mode");
        if (modeContact != null && modeContact.value != null)
        {
            _mode = parseInt(modeContact.value, MODE_OFF);
            if (_mode < MODE_OFF || _mode > MODE_NOISE)
            {
                _mode = MODE_OFF;
            }
        }
    }

    // =========================================================================
    // SIGNAL GENERATION
    // =========================================================================
    /**
     * Advance phase based on elapsed time.
     *
     * @param dt Delta time in seconds
     */
    private function advancePhase(dt:Float):Void
    {
        _currentPhase += _frequency * 2.0 * Math.PI * dt;
        
        // Normalize phase to prevent overflow
        while (_currentPhase > 2.0 * Math.PI)
        {
            _currentPhase -= 2.0 * Math.PI;
        }
    }

    /**
     * Generate raw (unquantized) signal.
     *
     * @return Value in range [-1.0, 1.0]
     */
    private function generateRawSignal():Float
    {
        return switch (_mode)
        {
            case MODE_SQUARE:
                generateSquare();
            case MODE_SAWTOOTH:
                generateSawtooth();
            case MODE_SINE:
                generateSine();
            case MODE_TRIANGLE:
                generateTriangle();
            case MODE_NOISE:
                generateNoise();
            default:
                0.0;
        }
    }

    /**
     * Generate square wave.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  1.0 ┤ ┌─────┐     ┌─────┐     ┌─────┐     ┌─────┐
     *  0.0 ┼─┘     └─────┘     └─────┘     └─────┘     └─────
     * -1.0 ┤
     *      └──────────────────────────────────────────► Time
     * ═══════════════════════════════════════════════════════════════════
     */
    private function generateSquare():Float
    {
        // Normalized phase [0, 1)
        var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
        if (normalizedPhase < 0) normalizedPhase += 1.0;
        
        // 50% duty cycle
        return (normalizedPhase < 0.5) ? 1.0 : -1.0;
    }

    /**
     * Generate sawtooth wave.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  1.0 ┤       ╱       ╱       ╱       ╱       ╱
     *  0.0 ┼──────╱ ──────╱ ──────╱ ──────╱ ──────╱ ─────
     * -1.0 ┤     ╱       ╱       ╱       ╱       ╱
     *      └──────────────────────────────────────────► Time
     * ═══════════════════════════════════════════════════════════════════
     */
    private function generateSawtooth():Float
    {
        // Normalized phase [0, 1)
        var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
        if (normalizedPhase < 0) normalizedPhase += 1.0;
        
        // Linear from -1 to 1
        return 2.0 * normalizedPhase - 1.0;
    }

    /**
     * Generate sine wave.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  1.0 ┤    ╭───╮         ╭───╮         ╭───╮
     *  0.0 ┼──╭─╯   ╰─╮─────╭─╯   ╰─╮─────╭─╯   ╰─╮──
     * -1.0 ┤ ╰╯       ╰─────╯       ╰─────╯       ╰╯
     *      └──────────────────────────────────────────► Time
     * ═══════════════════════════════════════════════════════════════════
     */
    private function generateSine():Float
    {
        return Math.sin(_currentPhase);
    }

    /**
     * Generate triangle wave.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  1.0 ┤     ╱╲       ╱╲       ╱╲       ╱╲       ╱
     *  0.0 ┼────╱──╲─────╱──╲─────╱──╲─────╱──╲─────╱
     * -1.0 ┤   ╱    ╲   ╱    ╲   ╱    ╲   ╱    ╲   ╱
     *       └──────────────────────────────────────────► Time
     * ═══════════════════════════════════════════════════════════════════
     */
    private function generateTriangle():Float
    {
        // Normalized phase [0, 1)
        var normalizedPhase = (_currentPhase / (2.0 * Math.PI)) % 1.0;
        if (normalizedPhase < 0) normalizedPhase += 1.0;
        
        // Triangle: rises from -1 to 1 in first half,
        // falls from 1 to -1 in second half
        if (normalizedPhase < 0.5)
        {
            // Rising part
            return -1.0 + 4.0 * normalizedPhase;
        }
        else
        {
            // Falling part
            return 3.0 - 4.0 * normalizedPhase;
        }
    }

    /**
     * Generate noise.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  1.0 ┤  │  ││ │ │ │   ││  │ │  │ │ │  │  ││ │ │ │
     *  0.0 ┼──┼──┼┼─┼─┼─┼───┼┼──┼─┼──┼─┼─┼──┼──┼┼─┼─┼─┼──
     * -1.0 ┤  ││ │ ││ │││││ │ │││││ ││ │ │ │ │││ │ ││
     *       └──────────────────────────────────────────► Time
     * ═══════════════════════════════════════════════════════════════════
     */
    private function generateNoise():Float
    {
        return (Math.random() * 2.0 - 1.0);
    }

    // =========================================================================
    // QUANTIZATION
    // =========================================================================
    /**
     * Quantize amplitude value.
     *
     * ═══════════════════════════════════════════════════════════════════
     *  Amplitude
     *    1.0 ┼─────────────────────────────●───────────────────────
     *    0.8 ┼─────────────────────────────│───────────────────────
     *    0.6 ┼─────────────────────────────│───────────────────────
     *    0.4 ┼───────────────────●─────────│───────────────────────
     *    0.2 ┼───────────────────│─────────│───────────────────────
     *    0.0 ┼─────●─────────────│─────────│───────────────────────
     *   -0.2 ┼─────│─────────────│─────────│───────────────────────
     *   -0.4 ┼─────│─────●───────│─────────│───────────────────────
     *   -0.6 ┼─────│─────│───────│─────────│───────────────────────
     *   -0.8 ┼─────│─────│───────│─────────│───────────────────────
     *   -1.0 ┼─────│─────│───────│─────●───│───────────────────────
     *         └──────────────────────────────────────────────────►
     *
     *  quantum = 0.2, values rounded to nearest level
     * ═══════════════════════════════════════════════════════════════════
     *
     * @param value Raw value [-1.0, 1.0]
     * @return Quantized value
     */
    private function quantizeValue(value:Float):Float
    {
        // Round to nearest quantum
        var quantized = Math.round(value / _quantumStep) * _quantumStep;
        
        // Clamp range
        if (quantized > 1.0) quantized = 1.0;
        if (quantized < -1.0) quantized = -1.0;
        
        return quantized;
    }

    // =========================================================================
    // OUTPUT CONTROL
    // =========================================================================
    /**
     * Update output value with quantum change check.
     *
     * @param newQuantum New quantized value
     */
    private function updateOutput(newQuantum:Float):Void
    {
        // First frame - initialization
        if (_isFirstUpdate)
        {
            _lastQuantum = newQuantum;
            _isFirstUpdate = false;
            setOutputQuantized(newQuantum);
            return;
        }
        
        // Check change
        if (newQuantum != _lastQuantum)
        {
            _lastQuantum = newQuantum;
            setOutputQuantized(newQuantum);
            triggerPulse();
        }
    }

    /**
     * Set quantized value to output.
     *
     * @param value Quantized value
     */
    private function setOutputQuantized(value:Float):Void
    {
        var outContact = getOutput("out");
        if (outContact != null)
        {
            outContact.value = value;
        }
    }

    /**
     * Trigger 'changed' pulse.
     */
    private function triggerPulse():Void
    {
        var changedContact = getOutput("changed");
        if (changedContact != null)
        {
            changedContact.value = true;
            _pulseActive = true;
            _pulseTimer = PULSE_DURATION;
            _pulseCount++;
        }
    }

    /**
     * Update 'changed' pulse state.
     *
     * @param dt Delta time in seconds
     */
    private function updatePulse(dt:Float):Void
    {
        if (!_pulseActive) return;
        
        _pulseTimer -= dt;
        if (_pulseTimer <= 0)
        {
            var changedContact = getOutput("changed");
            if (changedContact != null)
            {
                changedContact.value = false;
            }
            _pulseActive = false;
        }
    }

    // =========================================================================
    // PUBLIC API
    // =========================================================================
    /**
     * Get generation frequency.
     */
    public function getFrequency():Float
    {
        return _frequency;
    }

    /**
     * Set generation frequency.
     */
    public function setFrequency(freq:Float):Void
    {
        if (freq >= MIN_FREQUENCY && freq <= MAX_FREQUENCY)
        {
            _frequency = freq;
        }
    }

    /**
     * Get quantization step.
     */
    public function getQuantumStep():Float
    {
        return _quantumStep;
    }

    /**
     * Set quantization step.
     */
    public function setQuantumStep(step:Float):Void
    {
        if (step >= MIN_QUANTUM && step <= MAX_QUANTUM)
        {
            _quantumStep = step;
        }
    }

    /**
     * Get generation mode.
     */
    public function getMode():Int
    {
        return _mode;
    }

    /**
     * Set generation mode.
     */
    public function setMode(mode:Int):Void
    {
        if (mode >= MODE_OFF && mode <= MODE_NOISE)
        {
            _mode = mode;
        }
    }

    /**
     * Get current phase.
     */
    public function getPhase():Float
    {
        return _currentPhase;
    }

    /**
     * Reset phase to zero.
     */
    public function resetPhase():Void
    {
        _currentPhase = 0.0;
    }

    /**
     * Get last quantized value.
     */
    public function getLastQuantum():Float
    {
        return _lastQuantum;
    }

    /**
     * Get number of generated pulses.
     */
    public function getPulseCount():Int
    {
        return _pulseCount;
    }

    /**
     * Get generation mode name.
     */
    public function getModeName():String
    {
        return switch (_mode)
        {
            case MODE_OFF:      "OFF";
            case MODE_SQUARE:   "SQUARE";
            case MODE_SAWTOOTH: "SAWTOOTH";
            case MODE_SINE:     "SINE";
            case MODE_TRIANGLE: "TRIANGLE";
            case MODE_NOISE:    "NOISE";
            default:            "UNKNOWN";
        }
    }

    /**
     * Get all available modes.
     */
    public static function getAvailableModes():Array<{id:Int, name:String, description:String}>
    {
        return [
            { id: MODE_OFF,      name: "OFF",      description: "Generation disabled" },
            { id: MODE_SQUARE,   name: "SQUARE",   description: "Square wave" },
            { id: MODE_SAWTOOTH, name: "SAWTOOTH", description: "Sawtooth wave" },
            { id: MODE_SINE,     name: "SINE",     description: "Sine wave" },
            { id: MODE_TRIANGLE, name: "TRIANGLE", description: "Triangle wave" },
            { id: MODE_NOISE,    name: "NOISE",    description: "Random noise" }
        ];
    }

    // =========================================================================
    // STATE SERIALIZATION
    // =========================================================================
    /**
     * Save state for persistence.
     */
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();
		var result:Dynamic = {
			frequency: _frequency,
			quantumStep: _quantumStep,
			mode: _mode,
			phase: _currentPhase,
			lastQuantum: _lastQuantum,
			pulseCount: _pulseCount
		};
		if (base != null)
		{
			for (field in Reflect.fields(base))
			{
				Reflect.setField(result, field, Reflect.field(base, field));
			}
		}
		return result;
	}

    /**
     * Restore state from saved data.
     */
    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        // First restore base class fields
        super.restoreState(state);
        
        if (state.frequency != null)
        {
            var f = parseFloat(state.frequency, _frequency);
            if (f >= MIN_FREQUENCY && f <= MAX_FREQUENCY)
            {
                _frequency = f;
            }
        }
        
        if (state.quantumStep != null)
        {
            var q = parseFloat(state.quantumStep, _quantumStep);
            if (q >= MIN_QUANTUM && q <= MAX_QUANTUM)
            {
                _quantumStep = q;
            }
        }
        
        if (state.mode != null)
        {
            _mode = parseInt(state.mode, MODE_OFF);
            if (_mode < MODE_OFF || _mode > MODE_NOISE)
            {
                _mode = MODE_OFF;
            }
        }
        
        if (state.phase != null)
        {
            _currentPhase = parseFloat(state.phase, _currentPhase);
        }
        
        if (state.lastQuantum != null)
        {
            _lastQuantum = parseFloat(state.lastQuantum, _lastQuantum);
        }
        
        if (state.pulseCount != null)
        {
            _pulseCount = parseInt(state.pulseCount, 0);
        }
        
        trace('SignalGenerator: Restored state (freq: $_frequency, mode: ${getModeName()})');
    }

    // =========================================================================
    // UTILITY
    // =========================================================================
    /**
     * Safe Float parsing.
     */
    private function parseFloat(value:Dynamic, defaultValue:Float):Float
    {
        if (value == null) return defaultValue;
        if (Std.isOfType(value, Float))
        {
            return cast(value, Float);
        }
        if (Std.isOfType(value, Int))
        {
            return cast(value, Int) * 1.0;
        }
        if (Std.isOfType(value, String))
        {
            var f = Std.parseFloat(cast(value, String));
            return Math.isNaN(f) ? defaultValue : f;
        }
        return defaultValue;
    }

    /**
     * Safe Int parsing.
     */
    private function parseInt(value:Dynamic, defaultValue:Int):Int
    {
        if (value == null) return defaultValue;
        if (Std.isOfType(value, Int))
        {
            return cast(value, Int);
        }
        if (Std.isOfType(value, Float))
        {
            return Std.int(cast(value, Float));
        }
        if (Std.isOfType(value, String))
        {
            var i = Std.parseInt(cast(value, String));
            return i == null ? defaultValue : i;
        }
        return defaultValue;
    }
}