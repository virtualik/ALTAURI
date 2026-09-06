package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.EventType;
import core.logic.Impulsys;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     FFT ATOM v1.1                                         ║
* ║                     (Real-Time Spectrum Analyzer)                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* A spectral analysis driver based on the Cooley-Tukey Radix-2 algorithm.
* Accepts a sample buffer from MiniAudioAtom, performs the FFT, and outputs
* spectral data (amplitudes, dB, bass/mid/treble).
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     FFTAtom                                         │  ║
* ║  │                                                                     │  ║
* ║  │  A) COMPUTE MODULE (Main Thread — update(dt)):                      │  ║
* ║  │     ─────────────────────────────────────────                       │  ║
* ║  │     1. readInputs()                                                 │  ║
* ║  │        - buffer, windowSize, windowType, sampleRate                 │  ║
* ║  │        - targetBars, minFreq, maxFreq, minDB, maxDB                 │  ║
* ║  │        - compressionExponent, noiseGate, gain, mode                 │  ║
* ║  │                                                                     │  ║
* ║  │     2. processFFT()                                                 │  ║
* ║  │        - Apply window function (Hann/Hamming)                       │  ║
* ║  │        - Execute Cooley-Tukey FFT                                   │  ║
* ║  │        - Extract magnitudes                                         │  ║
* ║  │        - Convert to dBFS                                            │  ║
* ║  │        - Calculate bass/mid/treble energy                           │  ║
* ║  │                                                                     │  ║
* ║  │     3. Batched Driver Update Pattern                                │  ║
* ║  │        - setValueSilent() for all outputs                          │  ║
* ║  │        - propagateCurrentValue() once per output                    │  ║
* ║  │        - Impulsys.quickEmit(FFT_SPECTRUM_READY)                     │  ║
* ║  │                                                                     │  ║
* ║  │  B) DATABANK (Haxe):                                                │  ║
* ║  │     ─────────────────────                                           │  ║
* ║  │     _inputBuffer: Array<Float>     - A copy of the input buffer     │  ║
* ║  │     _windowFunc: Array<Float>      - The window function             │  ║
* ║  │     _spectrum: Array<Float>        - Amplitudes (N/2 bins)           │  ║
* ║  │     _spectrumDB: Array<Float>      - Amplitudes in dBFS              │  ║
* ║  │     _re: Array<Float>              - Real part (FFT workspace)      │  ║
* ║  │     _im: Array<Float>              - Imaginary part (FFT workspace) │  ║
* ║  │                                                                     │  ║
* ║  │  C) INPUTS:                                                         │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "buffer"      - Array<Float> (from MiniAudioAtom)               │  ║
* ║  │     "windowSize"  - Int (512, 1024, 2048)                           │  ║
* ║  │     "windowType"  - Int (0=None, 1=Hann, 2=Hamming)                 │  ║
* ║  │     "sampleRate"  - Int (44100, 48000, 96000)                       │  ║
* ║  │     "targetBars"  - Int (the number of bars, default 16)            │  ║
* ║  │     "minFreq"     - Float (min frequency, default 20.0)             │  ║
* ║  │     "maxFreq"     - Float (max frequency, default 20000.0)          │  ║
* ║  │     "minDB"       - Float (min dBFS level, default -90.0)           │  ║
* ║  │     "maxDB"       - Float (max dBFS level, default 0.0)             │  ║
* ║  │     "compExp"     - Float (compression exponent, default 0.6)       │  ║
* ║  │     "noiseGate"   - Float (noise gate, default 0.01)                │  ║
* ║  │     "gain"        - Float (gain -1.0..1.0, default 0.0)             │  ║
* ║  │     "mode"        - Int (0 = standard, 1 = bars with peak)           │  ║
* ║  │                                                                     │  ║
* ║  │  D) OUTPUTS:                                                        │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "spectrum"    - Array<Float> (amplitudes, N/2 bins)             │  ║
* ║  │     "spectrumDB"  - Array<Float> (amplitudes in dBFS)               │  ║
* ║  │     "peak"        - Float (peak frequency, Hz)                      │  ║
* ║  │     "peakAmp"     - Float (peak amplitude)                          │  ║
* ║  │     "bass"        - Float (20-250 Hz energy)                        │  ║
* ║  │     "mid"         - Float (250-4000 Hz energy)                      │  ║
* ║  │     "treble"      - Float (4000-20000 Hz energy)                    │  ║
* ║  │     "changed"     - Bool (an impulse on update)                     │  ║
* ║  │                                                                     │  ║
* ║  │  E) FACE (DeviceView):                                              │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     FFTWidget for spectrum visualization                            │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     FFT ALGORITHM                                         ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Cooley-Tukey Radix-2 Decimation-In-Time (DIT):                           ║
* ║                                                                           ║
* ║  1. Bit-reversal permutation of the input data                           ║
* ║  2. Butterfly operations:                                                 ║
* ║     ┌──────┐                                                              ║
* ║     │  a   │──────┐                                                       ║
* ║     └──────┘      │  ┌──────┐                                             ║
* ║                   ├─►│ a + t│                                             ║
* ║     ┌──────┐      │  └──────┘                                             ║
* ║     │  b   │──────┘                                                       ║
* ║     └──────┘      │  ┌──────┐                                             ║
* ║                   └─►│ a - t│                                             ║
* ║                      └──────┘                                             ║
* ║                                                                           ║
* ║     where t = b * W_N^k (the twiddle factor)                             ║
* ║     W_N^k = e^(-2πi*k/N)                                                  ║
* ║                                                                           ║
* ║  Complexity: O(N log N) instead of O(N²)                                 ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                   WINDOW FUNCTIONS                                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Hann:  w(n) = 0.5 * (1 - cos(2π * n / (N-1)))                            ║
* ║  Hamming: w(n) = 0.54 - 0.46 * cos(2π * n / (N-1))                        ║
* ║                                                                           ║
* ║  Window functions reduce the spectral leakage caused by the sharp        ║
* ║  edges of the buffer.                                                    ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class FFTAtom extends Atom implements Driver
{
	// =========================================================================
	// CONSTANTS
	// =========================================================================
	/** Minimal FFT size (a power of 2) */
	private static inline var MIN_FFT_SIZE:Int = 256;
	/** Maximum FFT size */
	private static inline var MAX_FFT_SIZE:Int = 4096;
	/** The duration of the "changed" impulse */
	private static inline var PULSE_DURATION:Float = 0.05;
	
	/** Window function: None */
	private static inline var WINDOW_NONE:Int = 0;
	/** Window function: Hann */
	private static inline var WINDOW_HANN:Int = 1;
	/** Window function: Hamming */
	private static inline var WINDOW_HAMMING:Int = 2;
	
	// =========================================================================
	// DATABANK — Parameters
	// =========================================================================
	/** FFT size (the number of points) */
	private var _fftSize:Int = 512;
	/** The window function type */
	private var _windowType:Int = WINDOW_HANN;
	/** The sample rate (for computing the frequency bins) */
	private var _sampleRate:Int = 48000;
	
	// === New visualization and tuning parameters ===
	private var _targetBars:Int = 16;
	private var _minFreq:Float = 20.0;
	private var _maxFreq:Float = 20000.0;
	private var _minDB:Float = -90.0;
	private var _maxDB:Float = 0.0;
	private var _compressionExponent:Float = 0.8;
	private var _noiseGate:Float = 0.01;
	private var _gain:Float = 0.0;
	private var _mode:Int = 0; // 0 = standard, 1 = bars with peak hold
	
	// =========================================================================
	// DATABANK - Zero-GC buffers (pre-allocated)
	// =========================================================================
	/** The input buffer (a copy from MiniAudioAtom) */
	private var _inputBuffer:Array<Float>;
	/** The window function (precomputed) */
	private var _windowFunc:Array<Float>;
	/** Real part (the FFT working buffer) */
	private var _re:Array<Float>;
	/** Imaginary part (the FFT working buffer) */
	private var _im:Array<Float>;
	/** The spectrum (amplitudes, N/2 bins) */
	private var _spectrum:Array<Float>;
	/** The spectrum in dBFS */
	private var _spectrumDB:Array<Float>;
	
	// =========================================================================
	// DATABANK — State
	// =========================================================================
	/** Flag: new data is ready for processing */
	private var _hasNewData:Bool = false;
	/** The peak frequency (Hz) */
	private var _peakFreq:Float = 0.0;
	/** The peak amplitude */
	private var _peakAmp:Float = 0.0;
	/** Bass energy (20-250 Hz) */
	private var _bassEnergy:Float = 0.0;
	/** Mid energy (250-4000 Hz) */
	private var _midEnergy:Float = 0.0;
	/** Treble energy (4000-20000 Hz) */
	private var _trebleEnergy:Float = 0.0;
	
	/** The timer of the "changed" impulse */
	private var _pulseTimer:Float = 0.0;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	/**
	* Creates a new FFTAtom instance.
	* 
	* @param id The unique identifier of the atom
	*/
	public function new(id:String)
	{
		super(
			// === INPUTS ===
			[
				new Contact(null, INPUT, "buffer"),          // Array<Float> from MiniAudioAtom
				new Contact(512, INPUT, "windowSize"),       // FFT size (512, 1024, 2048)
				new Contact(WINDOW_HANN, INPUT, "windowType"), // The window type (0=None, 1=Hann, 2=Hamming)
				new Contact(48000, INPUT, "sampleRate"),     // The sample rate
				new Contact(16, INPUT, "targetBars"),        // The number of bars
				new Contact(20.0, INPUT, "minFreq"),         // The minimum frequency (Hz)
				new Contact(20000.0, INPUT, "maxFreq"),      // The maximum frequency (Hz)
				new Contact(-90.0, INPUT, "minDB"),          // The minimum dBFS level
				new Contact(0.0, INPUT, "maxDB"),            // The maximum dBFS level
				new Contact(0.6, INPUT, "compressionExponent"), // The compression exponent
				new Contact(0.01, INPUT, "noiseGate"),       // The noise gate threshold
				new Contact(0.0, INPUT, "gain"),             // The gain (-1.0 to +1.0, mapped to ±20dB)
				new Contact(0, INPUT, "mode")                // The visualization mode (0 = standard, 1 = bars)
			],
			// === OUTPUTS ===
			[
				new Contact(null, OUTPUT, "spectrum"),       // Array<Float> (amplitudes)
				new Contact(null, OUTPUT, "spectrumDB"),     // Array<Float> (dBFS)
				new Contact(0.0, OUTPUT, "peak"),            // Float (the peak frequency, Hz)
				new Contact(0.0, OUTPUT, "peakAmp"),         // Float (the peak amplitude)
				new Contact(0.0, OUTPUT, "bass"),            // Float (the 20-250 Hz energy)
				new Contact(0.0, OUTPUT, "mid"),             // Float (the 250-4000 Hz energy)
				new Contact(0.0, OUTPUT, "treble"),          // Float (the 4000-20000 Hz energy)
				new Contact(false, OUTPUT, "changed")        // Bool (an impulse)
			],
			null,
			id,
			"FFTAtom",
			true // isActive = true -> registered in DriverManager
		);
		
		// Disable the oscillation protection for the "spectrum" output
		var spectrumOut = getOutput("spectrum");
		if (spectrumOut != null) spectrumOut.ignoreOscillation = true;
		
		init();
	}
	
	// =========================================================================
	// LIFECYCLE
	// =========================================================================
	/**
	* Driver initialization.
	* Pre-allocates the Zero-GC buffers and computes the window function.
	*/
	override public function init():Void
	{
		// Pre-allocating the buffers (Zero-GC)
		_inputBuffer = new Array<Float>();
		_windowFunc = new Array<Float>();
		_re = new Array<Float>();
		_im = new Array<Float>();
		_spectrum = new Array<Float>();
		_spectrumDB = new Array<Float>();
		
		// Initializing with zeros
		for (i in 0...MAX_FFT_SIZE) {
			_inputBuffer.push(0.0);
			_windowFunc.push(0.0);
			_re.push(0.0);
			_im.push(0.0);
		}
		for (i in 0...(MAX_FFT_SIZE >> 1)) {
			_spectrum.push(0.0);
			_spectrumDB.push(-120.0);
		}
		
		// Reading the initial parameters
		readInputs();
		
		// Computing the window function
		computeWindowFunction();
	}
	
	/**
	* The main update loop of the driver.
	* Called every frame from DriverManager.update(dt).
	* 
	* @param dt Delta time (the time since the last frame, in seconds)
	*/
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;
		
		// 1. Reading the input parameters
		readInputs();
		
		// 2. FFT processing (if new data has arrived)
		if (_hasNewData) {
			processFFT();
			_hasNewData = false;
		}
		
		// 3. Updating the impulse timer
		if (_pulseTimer > 0) {
			_pulseTimer -= dt;
			if (_pulseTimer <= 0) {
				var c = getOutput("changed");
				if (c != null) c.value = false;
			}
		}
	}
	
	/**
	* Releasing the resources.
	*/
	override public function dispose():Void
	{
		DriverManager.getInstance().unregister(this.id);
		_inputBuffer = null;
		_windowFunc = null;
		_re = null;
		_im = null;
		_spectrum = null;
		_spectrumDB = null;
		super.dispose();
	}
	
	// =========================================================================
	// INPUT READING
	// =========================================================================
	/**
	* Reads the values of the input contacts and updates the atom parameters.
	*/
	private function readInputs():Void
	{
		// Reading the sample buffer
		var bufferC = getInput("buffer");
		if (bufferC != null && bufferC.value != null) {
			if (Std.isOfType(bufferC.value, Array)) {
				var samples:Array<Float> = bufferC.value;
				if (samples != null && samples.length > 0) {
					// Copy the data into the input buffer (Zero-GC)
					var count = Std.int(Math.min(samples.length, _fftSize));
					for (i in 0...count) {
						_inputBuffer[i] = samples[i];
					}
					_hasNewData = true;
				}
			}
		}
		
		// Reading the FFT size
		var sizeC = getInput("windowSize");
		if (sizeC != null && sizeC.value != null) {
			var newSize = Std.int(sizeC.value);
			// Verify that the size is a power of 2
			if (newSize >= MIN_FFT_SIZE && newSize <= MAX_FFT_SIZE && isPowerOfTwo(newSize)) {
				if (newSize != _fftSize) {
					_fftSize = newSize;
					computeWindowFunction(); // Recompute the window
				}
			}
		}
		
		// Reading the window type
		var typeC = getInput("windowType");
		if (typeC != null && typeC.value != null) {
			var newType = Std.int(typeC.value);
			if (newType >= WINDOW_NONE && newType <= WINDOW_HAMMING) {
				if (newType != _windowType) {
					_windowType = newType;
					computeWindowFunction();
				}
			}
		}
		
		// Reading the sample rate
		var rateC = getInput("sampleRate");
		if (rateC != null && rateC.value != null) {
			_sampleRate = Std.int(rateC.value);
		}
		
		// === Reading the new visualization parameters ===
		var barsC = getInput("targetBars");
		if (barsC != null && barsC.value != null) {
			var v = Std.int(barsC.value);
			if (v >= 1 && v <= 128) _targetBars = v;
		}
		
		var minFC = getInput("minFreq");
		if (minFC != null && minFC.value != null) {
			var v = Std.parseFloat(Std.string(minFC.value));
			if (v >= 1.0) _minFreq = v;
		}
		
		var maxFC = getInput("maxFreq");
		if (maxFC != null && maxFC.value != null) {
			var v = Std.parseFloat(Std.string(maxFC.value));
			if (v >= 20.0) _maxFreq = v;
		}
		
		var minDBC = getInput("minDB");
		if (minDBC != null && minDBC.value != null) {
			_minDB = Std.parseFloat(Std.string(minDBC.value));
		}
		
		var maxDBC = getInput("maxDB");
		if (maxDBC != null && maxDBC.value != null) {
			_maxDB = Std.parseFloat(Std.string(maxDBC.value));
		}
		
		var compC = getInput("compressionExponent");
		if (compC != null && compC.value != null) {
			var v = Std.parseFloat(Std.string(compC.value));
			if (v > 0.1 && v <= 2.0) _compressionExponent = v;
		}
		
		var gateC = getInput("noiseGate");
		if (gateC != null && gateC.value != null) {
			var v = Std.parseFloat(Std.string(gateC.value));
			if (v >= 0.0 && v <= 1.0) _noiseGate = v;
		}
		
		var gainC = getInput("gain");
		if (gainC != null && gainC.value != null) {
			var v = Std.parseFloat(Std.string(gainC.value));
			if (v >= -1.0 && v <= 1.0) _gain = v;
		}
		
		var modeC = getInput("mode");
		if (modeC != null && modeC.value != null) {
			var v = Std.int(modeC.value);
			if (v >= 0 && v <= 1) _mode = v;
		}
	}
	
	// =========================================================================
	// FFT PROCESSING
	// =========================================================================
	/**
	* The main FFT processing function.
	* 1. Applies the window function
	* 2. Runs the Cooley-Tukey FFT
	* 3. Extracts the magnitudes
	* 4. Converts to dBFS
	* 5. Computes the bass/mid/treble energy
	*/
	private function processFFT():Void
	{
		// 1. Applying the window function
		for (i in 0..._fftSize) {
			_re[i] = _inputBuffer[i] * _windowFunc[i];
			_im[i] = 0.0; // Imaginary part = 0 for a real signal
		}
		
		// 2. Running the FFT (Cooley-Tukey Radix-2 DIT)
		fft(_re, _im, _fftSize);
		
		// 3. Extracting the magnitudes and converting to dBFS
		var halfSize = _fftSize >> 1;
		var peakBin = 0;
		var peakMag = 0.0;
		
		for (i in 0...halfSize) {
			// Magnitude = sqrt(re^2 + im^2)
			var mag = Math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]);
			_spectrum[i] = mag;
			
			// Converting to dBFS: 20 * log10(mag)
			var db = (mag > 0.0001) ? 20.0 * Math.log(mag) / Math.log(10) : -120.0;
			_spectrumDB[i] = db;
			
			// Finding the peak
			if (mag > peakMag) {
				peakMag = mag;
				peakBin = i;
			}
		}
		
		// 4. Computing the peak frequency
		// The bin frequency = bin * (sampleRate / fftSize)
		var freqResolution = _sampleRate / _fftSize;
		_peakFreq = peakBin * freqResolution;
		_peakAmp = peakMag;
		
		// 5. Computing the bass/mid/treble energy
		computeBandEnergies(freqResolution);
		
		// 6. Batched propagation (the pattern from MiniAudioAtom)
		var spectrumOut = getOutput("spectrum");
		var spectrumDBOut = getOutput("spectrumDB");
		var peakOut = getOutput("peak");
		var peakAmpOut = getOutput("peakAmp");
		var bassOut = getOutput("bass");
		var midOut = getOutput("mid");
		var trebleOut = getOutput("treble");
		var changedOut = getOutput("changed");
		
		// Silent writes
		if (spectrumOut != null) spectrumOut.setValueSilent(_spectrum);
		if (spectrumDBOut != null) spectrumDBOut.setValueSilent(_spectrumDB);
		if (peakOut != null) peakOut.setValueSilent(_peakFreq);
		if (peakAmpOut != null) peakAmpOut.setValueSilent(_peakAmp);
		if (bassOut != null) bassOut.setValueSilent(_bassEnergy);
		if (midOut != null) midOut.setValueSilent(_midEnergy);
		if (trebleOut != null) trebleOut.setValueSilent(_trebleEnergy);
		
		// Single propagation per output
		if (spectrumOut != null) spectrumOut.propagateCurrentValue();
		if (spectrumDBOut != null) spectrumDBOut.propagateCurrentValue();
		if (peakOut != null) peakOut.propagateCurrentValue();
		if (peakAmpOut != null) peakAmpOut.propagateCurrentValue();
		if (bassOut != null) bassOut.propagateCurrentValue();
		if (midOut != null) midOut.propagateCurrentValue();
		if (trebleOut != null) trebleOut.propagateCurrentValue();
		
		// The "changed" impulse
		if (changedOut != null) {
			changedOut.value = true;
			_pulseTimer = PULSE_DURATION;
		}
		
		// Notifying the UI via Impulsys
		Impulsys.quickEmit(EventType.FFT_SPECTRUM_READY, { atomId: this.id });
	}
	
	/**
	* The Cooley-Tukey Radix-2 DIT FFT algorithm (in-place).
	* 
	* @param re Real part (an array of size N)
	* @param im Imaginary part (an array of size N)
	* @param n The FFT size (a power of 2)
	*/
	private function fft(re:Array<Float>, im:Array<Float>, n:Int):Void
	{
		// 1. Bit-reversal permutation
		var j = 0;
		for (i in 0...(n - 1)) {
			if (i < j) {
				// Swap re[i] and re[j]
				var tempRe = re[i];
				re[i] = re[j];
				re[j] = tempRe;
				// Swap im[i] and im[j]
				var tempIm = im[i];
				im[i] = im[j];
				im[j] = tempIm;
			}
			var k = n >> 1;
			while (k <= j) {
				j -= k;
				k >>= 1;
			}
			j += k;
		}
		
		// 2. Cooley-Tukey butterfly operations
		var step = 2;
		while (step <= n) {
			var halfStep = step >> 1;
			var angleStep = -2.0 * Math.PI / step;
			
			for (i in 0...halfStep) {
				var angle = i * angleStep;
				var wRe = Math.cos(angle);
				var wIm = Math.sin(angle);
				
				var k = i;
				while (k < n) {
					var idx1 = k;
					var idx2 = k + halfStep;
					
					// Butterfly: t = w * (re[idx2] + i*im[idx2])
					var tRe = wRe * re[idx2] - wIm * im[idx2];
					var tIm = wRe * im[idx2] + wIm * re[idx2];
					
					// re[idx2] = re[idx1] - t
					re[idx2] = re[idx1] - tRe;
					im[idx2] = im[idx1] - tIm;
					
					// re[idx1] = re[idx1] + t
					re[idx1] = re[idx1] + tRe;
					im[idx1] = im[idx1] + tIm;
					
					k += step;
				}
			}
			
			step <<= 1;
		}
	}
	
	/**
	* Computes the energy in the bass/mid/treble frequency ranges.
	* 
	* @param freqResolution The frequency resolution (Hz per bin)
	*/
	private function computeBandEnergies(freqResolution:Float):Void
	{
		var halfSize = _fftSize >> 1;
		
		// Bass: 20-250 Hz
		var bassStart = Std.int(20.0 / freqResolution);
		var bassEnd = Std.int(250.0 / freqResolution);
		_bassEnergy = 0.0;
		for (i in bassStart...bassEnd) {
			if (i < halfSize) _bassEnergy += _spectrum[i];
		}
		
		// Mid: 250-4000 Hz
		var midStart = bassEnd;
		var midEnd = Std.int(4000.0 / freqResolution);
		_midEnergy = 0.0;
		for (i in midStart...midEnd) {
			if (i < halfSize) _midEnergy += _spectrum[i];
		}
		
		// Treble: 4000-20000 Hz
		var trebleStart = midEnd;
		var trebleEnd = Std.int(20000.0 / freqResolution);
		_trebleEnergy = 0.0;
		for (i in trebleStart...trebleEnd) {
			if (i < halfSize) _trebleEnergy += _spectrum[i];
		}
	}
	
	// =========================================================================
	// WINDOW FUNCTION
	// =========================================================================
	/**
	* Computes the window function for the current FFT size and window type.
	*/
	private function computeWindowFunction():Void
	{
		var N = _fftSize;
		for (n in 0...N) {
			var w = 1.0;
			switch (_windowType) {
				case WINDOW_HANN:
					w = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * n / (N - 1)));
				case WINDOW_HAMMING:
					w = 0.54 - 0.46 * Math.cos(2.0 * Math.PI * n / (N - 1));
				case WINDOW_NONE:
					w = 1.0;
			}
			_windowFunc[n] = w;
		}
	}
	
	// =========================================================================
	// UTILITY
	// =========================================================================
	/**
	* Checks whether a number is a power of 2.
	* 
	* @param n The number to check
	* @return true if it is a power of 2
	*/
	private function isPowerOfTwo(n:Int):Bool
	{
		return n > 0 && (n & (n - 1)) == 0;
	}
	
	// =========================================================================
	// PUBLIC API (for the widget)
	// =========================================================================
	public function getSpectrum():Array<Float> return _spectrum;
	public function getSpectrumDB():Array<Float> return _spectrumDB;
	public function getFFTSize():Int return _fftSize;
	public function getSampleRate():Int return _sampleRate;
	public function getPeakFreq():Float return _peakFreq;
	public function getBassEnergy():Float return _bassEnergy;
	public function getMidEnergy():Float return _midEnergy;
	public function getTrebleEnergy():Float return _trebleEnergy;
	
	// === Getters for the new visualization parameters ===
	public function getTargetBars():Int return _targetBars;
	public function getMinFreq():Float return _minFreq;
	public function getMaxFreq():Float return _maxFreq;
	public function getMinDB():Float return _minDB;
	public function getMaxDB():Float return _maxDB;
	public function getCompressionExponent():Float return _compressionExponent;
	public function getNoiseGate():Float return _noiseGate;
	public function getGain():Float return _gain;
	public function getMode():Int return _mode;
}