package core.view;

import openfl.display.Sprite;
import openfl.events.Event;
import core.base.Atom;
import core.base.Assembly;
import core.logic.EventType;
import core.logic.Impulse;
import core.logic.Impulsys;
import library.electro.FFTAtom;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     FFT WIDGET v2.2                                       ║
* ║                     (Logarithmic Spectrum Analyzer)                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v2.2 Changes:                                                            ║
* ║  - Added "Brick Mode" (mode=1) with segmented vertical bricks.            ║
* ║  - Brick colors: 0-60% Green, 60-80% Yellow, 80-100% Red.                 ║
* ║  - Added Peak Hold effect for Brick Mode (white brick that falls down).   ║
* ║  - All visualization parameters are now read dynamically from FFTAtom.    ║
* ║                                                                           ║
* ║  v2.0 Changes:                                                            ║
* ║  - Replaced linear bin grouping with LOGARITHMIC frequency mapping.       ║
* ║  - Each bar now represents an equal logarithmic frequency range           ║
* ║    (e.g., 20-40Hz, 40-80Hz, 80-160Hz...), matching human hearing.         ║
* ║  - Added proper background clearing to prevent visual artifacts.          ║
* ║  - Improved bar spacing and color gradient thresholds.                    ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        LOGARITHMIC MAPPING                                ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Frequency Range: 20 Hz ───────────────────────────────► 20,000 Hz        ║
* ║  (Log Scale)      [20-40][40-80][80-160]...[10k-20k]                      ║
* ║                                                                           ║
* ║  For each bar:                                                            ║
* ║    1. Calculate freqStart and freqEnd using log interpolation             ║
* ║    2. Convert frequencies to FFT bin indices                              ║
* ║    3. Find the MAXIMUM dB value within that bin range                     ║
* ║    4. Draw the bar                                                        ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     FFT WIDGET v1.0                                       ║
* ║                     (Real-Time Spectrum Analyzer Visualization)           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Visual component (Face) for the FFTAtom.                                 ║
* ║  Renders a real-time bar-chart spectrum analyzer using dBFS data.         ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        RENDERING PIPELINE                                 ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  [FFTAtom] ──(Impulsys)──► FFT_SPECTRUM_READY                       │  ║
* ║  │         │                                                           │  ║
* ║  │         ▼                                                           │  ║
* ║  │  [FFTWidget.onFrameReady()]                                         │  ║
* ║  │         │                                                           │  ║
* ║  │         ├─► _hasNewFrame = true (Dirty Flag)                        │  ║
* ║  │         │                                                           │  ║
* ║  │         ▼                                                           │  ║
* ║  │  [OpenFL ENTER_FRAME] ──► redrawSpectrum()                          │  ║
* ║  │         │                                                           │  ║
* ║  │         ├─► Read spectrumDB from Atom (Zero-GC reference)           │  ║
* ║  │         ├─► Map dBFS [-120..0] to [0..1.0]                          │  ║
* ║  │         ├─► Draw bars directly to widget.graphics (No Sprite alloc) │  ║
* ║  │         └─► Apply Green -> Yellow -> Red gradient                   │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     dBFS TO VISUAL MAPPING                                ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  dBFS Value   │  Normalized  │  Bar Height  │  Color                      ║
* ║  ─────────────┼──────────────┼──────────────┼────────────────────         ║
* ║  0 dB (Max)   │  1.00        │  100%        │  ██████████ Red             ║
* ║  -6 dB        │  0.95        │  95%         │  █████████░ Red             ║
* ║  -12 dB       │  0.90        │  90%         │  ████████░░ Yellow          ║
* ║  -24 dB       │  0.80        │  80%         │  ██████░░░░ Yellow          ║
* ║  -48 dB       │  0.60        │  60%         │  ████░░░░░░ Green           ║
* ║  -72 dB       │  0.40        │  40%         │  ██░░░░░░░░ Green           ║
* ║  -96 dB       │  0.20        │  20%         │  █░░░░░░░░░ Green           ║
* ║  -120 dB (Min)│  0.00        │  0%          │  ░░░░░░░░░░ Empty           ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class FFTWidget extends DeviceView
{
	// =========================================================================
	// CONFIGURATION (External parameters and colors)
	// =========================================================================
	/** Base widget width. */
	public var widgetWidth:Float = 300;
	/** Base widget height. */
	public var widgetHeight:Float = 150;
	/** Widget background color (dark). */
	private var _colorBg:Int = 0x0a0a12;
	/** Grid color (barely visible). */
	private var _colorGrid:Int = 0x1a2a1a;
	/** Bar gradient colors (Green -> Yellow -> Red). */
	private var _colorGreen:Int = 0x00CC44;
	private var _colorYellow:Int = 0xCCAA00;
	private var _colorRed:Int = 0xCC2222;

	// =========================================================================
	// STATE & DATA (Zero-GC)
	// =========================================================================
	/** Reference to the linked FFT atom for reading data. */
	private var _fftAtom:FFTAtom;
	/** "Dirty" frame flag. Set when an event is received from the atom. */
	private var _hasNewFrame:Bool = false;
	/** Rendering lock flag (protection against recursion). */
	private var _isRendering:Bool = false;
	
	private var _previousBarHeights:Array<Float>;
	private var _peakHeights:Array<Float>;
	private var _smoothingFactor:Float = 0.7; // 0.0 = no smoothing, 1.0 = maximum smoothing
	private var _peakFallSpeed:Float = 0.001;  // 3% of maxHeight per frame

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	/**
	* Creates a spectrum analyzer widget and links it to the atom.
	*
	* @param atom Base atom (must be FFTAtom or Assembly containing it).
	*/
	public function new(atom:Atom)
	{
		super(atom);
		// --- Resolve FFTAtom reference ---
		if (Std.isOfType(atom, FFTAtom))
		{
			_fftAtom = cast(atom, FFTAtom);
		}
		else if (Std.isOfType(atom, Assembly))
		{
			var asm = cast(atom, Assembly);
			for (internalAtom in asm.internalAtoms)
			{
				if (Std.isOfType(internalAtom, FFTAtom))
				{
					_fftAtom = cast(internalAtom, FFTAtom);
					break;
				}
			}
		}
		// --- Initialize UI and subscriptions ---
		buildUI();
		// Subscribe to global Impulsys events
		Impulsys.subscribeToImpulse(EventType.FFT_SPECTRUM_READY, onFrameReady);
		// Synchronize rendering with screen refresh rate (ENTER_FRAME).
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	// =========================================================================
	// WIDGET SIZE
	// =========================================================================
	/**
	* Returns current widget dimensions for the layout manager.
	*/
	override public function getWidgetSize(): {width:Float, height:Float}
	{
		return {width: widgetWidth, height: widgetHeight};
	}

	// =========================================================================
	// UI CONSTRUCTION
	// =========================================================================
	/**
	* Orchestrates creation of all visual components.
	*/
	private function buildUI():Void
	{
		// Draw static background
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();
		// Frame
		graphics.lineStyle(2, 0x333355);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
	}

	// =========================================================================
	// LIFECYCLE & EVENT HANDLERS
	// =========================================================================
	/**
	* FFT_SPECTRUM_READY event handler.
	* Sets the _hasNewFrame flag so rendering happens in the next ENTER_FRAME.
	*/
	private function onFrameReady(impulse:Impulse):Void
	{
		if (isDisposed || impulse == null || impulse.data == null) return;
		if (_fftAtom == null || impulse.data.atomId != _fftAtom.id) return;
		_hasNewFrame = true;
	}

	/**
	* Main rendering loop, tied to screen refresh rate (ENTER_FRAME).
	*/
	private function onEnterFrame(e:Event):Void
	{
		if (_hasNewFrame && !_isRendering)
		{
			_hasNewFrame = false;
			redrawSpectrum();
		}
	}

	// =========================================================================
	// REDRAW LOGIC (Spectrum Redrawing Logic)
	// =========================================================================
	/**
	* Main spectrum drawing function.
	* v2.2: Improved sensitivity, dynamic range mapping, and added Brick Mode with Peak Hold.
	*/
	private function redrawSpectrum():Void
	{
		if (_fftAtom == null) return;
		var spectrumDB:Array<Float> = _fftAtom.getSpectrumDB();
		if (spectrumDB == null || spectrumDB.length == 0) return;
		_isRendering = true;

		var sampleRate = _fftAtom.getSampleRate();
		var fftSize = _fftAtom.getFFTSize();
		var binCount = spectrumDB.length; // Usually fftSize / 2
		var freqResolution = sampleRate / fftSize; // Hz per bin

		// Read parameters dynamically from Atom
		var numBars = _fftAtom.getTargetBars();
		var minFreq = _fftAtom.getMinFreq();
		var maxFreq = _fftAtom.getMaxFreq();
		var minDB = _fftAtom.getMinDB();
		var maxDB = _fftAtom.getMaxDB();
		var compressionExponent = _fftAtom.getCompressionExponent();
		var noiseGate = _fftAtom.getNoiseGate();
		var gain = _fftAtom.getGain();
		var mode = _fftAtom.getMode();

		// Protection against log(0)
		if (minFreq <= 0) minFreq = 1.0;
		if (maxFreq <= minFreq) maxFreq = sampleRate / 2.0;
		
		var barWidth = widgetWidth / numBars;
		var maxHeight = widgetHeight;

		// === SMOOTHING ARRAY INITIALIZATION ===
		if (_previousBarHeights == null || _previousBarHeights.length != numBars)
		{
			_previousBarHeights = [];
			for (i in 0...numBars) _previousBarHeights.push(0);
		}
		
		// === PEAK HOLD ARRAY INITIALIZATION ===
		if (_peakHeights == null || _peakHeights.length != numBars)
		{
			_peakHeights = [];
			for (i in 0...numBars) _peakHeights.push(0);
		}

		// === CLEAR AND BACKGROUND ===
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();

		// Draw grid (horizontal lines)
		graphics.lineStyle(1, _colorGrid, 0.5);
		var gridSteps = 4;
		for (i in 1...gridSteps)
		{
			var y = (maxHeight / gridSteps) * i;
			graphics.moveTo(0, y);
			graphics.lineTo(widgetWidth, y);
		}

		// === LOGARITHMIC DIVISION ===
		var logMin = Math.log(minFreq) / Math.log(10);
		var logMax = Math.log(maxFreq) / Math.log(10);
		var logRange = logMax - logMin;
		var currentBarHeights:Array<Float> = [];

		for (i in 0...numBars)
		{
			// Calculate frequency boundaries for the current bar in logarithmic scale
			var tStart = i / numBars;
			var tEnd = (i + 1) / numBars;
			var freqStart = Math.pow(10, logMin + tStart * logRange);
			var freqEnd = Math.pow(10, logMin + tEnd * logRange);

			// Convert frequencies to FFT bin indices
			var binStart = Std.int(freqStart / freqResolution);
			var binEnd = Std.int(freqEnd / freqResolution);

			// Clamp index range
			if (binStart < 0) binStart = 0;
			if (binEnd >= binCount) binEnd = binCount - 1;
			if (binStart > binEnd) binEnd = binStart; // At high frequencies bins may merge

			// Find the MAXIMUM dB value in this bin range
			var maxDBVal = minDB;
			for (b in binStart...binEnd + 1)
			{
				if (spectrumDB[b] > maxDBVal)
				{
					maxDBVal = spectrumDB[b];
				}
			}
			
			// Apply gain (range -1.0 to 1.0 maps to -20dB to +20dB offset)
			maxDBVal += gain * 20.0;

			// 1. Mapping dBFS [minDB..maxDB] -> Normalized [0.0..1.0]
			var range = maxDB - minDB;
			if (range <= 0) range = 1.0; // Fallback
			var normalized = (maxDBVal - minDB) / range;
			if (normalized < 0) normalized = 0;
			if (normalized > 1) normalized = 1;
/**/
			// 2. === ВИЗУАЛЬНЫЙ ПОДЪЕМ ВЫСОКИХ ЧАСТОТ (Tilt) для утехи глаз ===
			// freqStart - это текущая частота бина. Делим на 1000 (1 кГц) как на опорную точку.
			var tiltMultiplier = Math.pow(freqStart / 1000.0, 0.5);

			// Ограничиваем множитель, чтобы не улететь в бесконечность
			if (tiltMultiplier < 0.5) tiltMultiplier = 0.5;
			if (tiltMultiplier > 1.5) tiltMultiplier = 1.5;

			normalized *= tiltMultiplier;
		
			// Дополнительная защита от выхода за 1.0 после умножения
			if (normalized > 1.0) normalized = 1.0;

			// 3. Power compression (makes mid-level volumes visually taller)
			var compressed = Math.pow(normalized, compressionExponent);

			// 4. Noise gate
			if (compressed < noiseGate) compressed = 0;

			var targetHeight = compressed * maxHeight;

			// === SMOOTHING ===
			var smoothedHeight = _previousBarHeights[i] * _smoothingFactor + targetHeight * (1.0 - _smoothingFactor);
			currentBarHeights.push(smoothedHeight);
			
			// === PEAK HOLD LOGIC ===
			var currentPeak = _peakHeights[i];
			if (smoothedHeight > currentPeak) {
				currentPeak = smoothedHeight;
			} else {
				currentPeak -= _peakFallSpeed * maxHeight;
				if (currentPeak < 0) currentPeak = 0;
			}
			_peakHeights[i] = currentPeak;
			
			var barHeight = smoothedHeight;
			var x = i * barWidth;
			var y = maxHeight - barHeight;

			// Draw bar based on mode
			if (mode == 1) {
				drawBrickBar(x, barWidth, maxHeight, barHeight, currentPeak);
			} else {
				// Standard mode
				if (barHeight > 0.5)
				{
					var color = getColorForLevel(normalized);
					graphics.beginFill(color);
					// Draw with small gap for aesthetics
					graphics.drawRect(x + 1, y, barWidth - 2, barHeight);
					graphics.endFill();
				}
			}
		}

		// Save current heights for the next frame
		_previousBarHeights = currentBarHeights;
		_isRendering = false;
	}

	/**
	* Draws the bar in "Brick Mode" with segmented colors and peak hold.
	* 
	* @param x X position of the bar
	* @param barWidth Total width of the bar
	* @param maxHeight Maximum height of the widget
	* @param height Current smoothed height of the bar
	* @param peakHeight Current height of the peak hold indicator
	*/
	private function drawBrickBar(x:Float, barWidth:Float, maxHeight:Float, height:Float, peakHeight:Float):Void
	{
		var brickHeight = 4.0;
		var gap = 1.0;
		var step = brickHeight + gap;
		var numBricks = Std.int(maxHeight / step);
		
		var targetBricks = Std.int(height / step);
		var peakBrick = Std.int(peakHeight / step);
		
		var bWidth = barWidth - 2;
		if (bWidth <= 0) bWidth = 1;
		var brickX = x + 1;
		
		for (i in 0...numBricks) {
			var brickY = maxHeight - (i + 1) * step;
			
			if (i < targetBricks) {
				// Determine color based on height percentage
				var pct = (i + 1) / numBricks;
				var color:Int;
				if (pct <= 0.60) color = _colorGreen;
				else if (pct <= 0.80) color = _colorYellow;
				else color = _colorRed;
				
				graphics.beginFill(color);
				graphics.drawRect(brickX, brickY, bWidth, brickHeight);
				graphics.endFill();
			} else if (i == peakBrick && peakBrick >= targetBricks) {
				// Draw peak hold brick (white indicator)
				graphics.beginFill(0xFFFFFF);
				graphics.drawRect(brickX, brickY, bWidth, brickHeight);
				graphics.endFill();
			}
		}
	}

	/**
	* Returns color for the bar depending on normalized level (0.0 - 1.0).
	* Implements gradient: Green -> Yellow -> Red.
	*
	* @param level Normalized level (0.0 = silence, 1.0 = 0 dBFS).
	* @return Color in Int format (HEX).
	*/
	private function getColorForLevel(level:Float):Int
	{
		if (level >= 0.85)
		{
			return _colorRed;      // > -18 dBFS (Red)
		}
		else if (level >= 0.60)
		{
			return _colorYellow;   // > -48 dBFS (Yellow)
		}
		else {
			return _colorGreen;    // < -48 dBFS (Green)
		}
	}

	// =========================================================================
	// CLEAR & DISPOSE
	// =========================================================================
	/**
	* Clears the screen of drawn spectrum.
	*/
	public function clearDisplay():Void
	{
		graphics.clear();
		graphics.beginFill(_colorBg);
		graphics.drawRect(0, 0, widgetWidth, widgetHeight);
		graphics.endFill();
	}

	/**
	* Releases widget resources.
	* Unsubscribes from Impulsys events, removes ENTER_FRAME listeners
	* and nullifies references to help Garbage Collector.
	*/
	override public function dispose():Void
	{
		removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		Impulsys.removeImpulse(EventType.FFT_SPECTRUM_READY, onFrameReady);
		_fftAtom = null;
		super.dispose();
	}
}