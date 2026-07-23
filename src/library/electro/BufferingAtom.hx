package library.electro;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;
import core.types.ContactType.*;
import system.managers.DriverManager;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     BUFFERING ATOM v1.0                                   ║
* ║                     (Batch Mode + Zero-GC)                                ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Accumulates incoming samples into a fixed-size buffer.                   ║
* ║  When buffer is full, emits it on "buffer" output with "changed" pulse.   ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     BufferingAtom                                   │  ║
* ║  │                                                                     │  ║
* ║  │  A) COMPUTE MODULE:                                                 │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     onContactChanged("in") → _buffer.push(sample)                   │  ║
* ║  │                              _count++                               │  ║
* ║  │                              if (_count >= _size) → flush()         │  ║
* ║  │                                                                     │  ║
* ║  │     flush() {                                                       │  ║
* ║  │       1. setValueSilent(buffer)  ← Batch write                      │  ║
* ║  │       2. setValueSilent(changed=true)                               │  ║
* ║  │       3. setValueSilent(count=0)                                    │  ║
* ║  │       4. propagateCurrentValue() × 3  ← Single propagation          │  ║
* ║  │       5. Reset buffer                                               │  ║
* ║  │     }                                                               │  ║
* ║  │                                                                     │  ║
* ║  │     update(dt) → manage "changed" pulse timer                       │  ║
* ║  │                                                                     │  ║
* ║  │  B) DATABANK:                                                       │  ║
* ║  │     ─────────────                                                   │  ║
* ║  │     _buffer: Array<Float>  - Accumulator (Zero-GC, pre-allocated)   │  ║
* ║  │     _count: Int            - Current fill level                     │  ║
* ║  │     _size: Int             - Target buffer size (default: 512)      │  ║
* ║  │     _pulseTimer: Float     - Timer for "changed" pulse reset        │  ║
* ║  │                                                                     │  ║
* ║  │  C) INPUTS:                                                         │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "in"   - Float  - Incoming sample                               │  ║
* ║  │     "size" - Int    - Buffer size (1..8192)                         │  ║
* ║  │                                                                     │  ║
* ║  │  D) OUTPUTS:                                                        │  ║
* ║  │     ───────                                                         │  ║
* ║  │     "buffer"  - Array<Float>  - Full buffer (Zero-GC reference)     │  ║
* ║  │     "changed" - Bool          - Pulse when buffer ready (50ms)      │  ║
* ║  │     "count"   - Int           - Current fill level                  │  ║
* ║  │                                                                     │  ║
* ║  │  E) FACE (DeviceView):                                              │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     BufferingWidget (optional) - shows fill level                   │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     BATCH MODE PATTERN                                    ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  flush() {                                                          │  ║
* ║  │                                                                     │  ║
* ║  │    // 1. Silent writes — no propagation triggered                   │  ║
* ║  │    bufferOut.setValueSilent(_buffer);                               │  ║
* ║  │    changedOut.setValueSilent(true);                                 │  ║
* ║  │    countOut.setValueSilent(0);                                      │  ║
* ║  │                                                                     │  ║
* ║  │    // 2. Single propagation per output                              │  ║
* ║  │    bufferOut.propagateCurrentValue();                               │  ║
* ║  │    changedOut.propagateCurrentValue();                              │  ║
* ║  │    countOut.propagateCurrentValue();                                │  ║
* ║  │                                                                     │  ║
* ║  │    // Result: 3 writes + 3 propagations (not 3 × 3 = 9)             │  ║
* ║  │  }                                                                  │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    ZERO-GC BUFFER MANAGEMENT                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Problem: Creating new Array<Float>() on every flush() causes GC spikes.  ║
* ║                                                                           ║
* ║  Solution: Pre-allocate buffer in init() and reuse it.                    ║
* ║ On flush(), we pass the SAME array reference to downstream atoms.         ║
* ║ They must copy it if they need to store it long-term.                     ║
* ║                                                                           ║
* ║  Trade-off:                                                               ║
* ║ - Pro: Zero allocations during runtime                                    ║
* ║ - Con: Downstream atoms see the same array object (must copy if needed)   ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    APPLICATION                                            ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  • Audio sample accumulation (512 frames for FFT)                         ║
* ║  • Sensor data batching                                                   ║
* ║  • Network packet assembly                                                ║
* ║  • Any scenario where you need to collect N samples before processing     ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class BufferingAtom extends Atom implements system.managers.Driver
{
	// =========================================================================
	// CONSTANTS
	// =========================================================================
	/** Default buffer size */
	private static inline var DEFAULT_BUFFER_SIZE:Int = 512;
	/** Minimum allowed buffer size */
	private static inline var MIN_BUFFER_SIZE:Int = 1;
	/** Maximum allowed buffer size */
	private static inline var MAX_BUFFER_SIZE:Int = 8192;
	/** Duration of "changed" pulse in seconds */
	private static inline var PULSE_DURATION:Float = 0.05;

	// =========================================================================
	// DATABANK — Parameters
	// =========================================================================
	/** Target buffer size */
	private var _size:Int = DEFAULT_BUFFER_SIZE;

	// =========================================================================
	// DATABANK — State (Zero-GC)
	// =========================================================================
	/** 
	* Pre-allocated accumulator buffer.
	* Reused on every flush() to avoid GC allocations.
	*/
	private var _buffer:Array<Float>;
	/** Current fill level */
	private var _count:Int = 0;
	/** "changed" pulse timer */
	private var _pulseTimer:Float = 0.0;
	/** Flag: pulse is active */
	private var _pulseActive:Bool = false;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	public function new(id:String)
	{
		super(
			// === INPUTS ===
			[
				new Contact(null, INPUT, "in"),      // Incoming sample (Float)
				new Contact(DEFAULT_BUFFER_SIZE, INPUT, "size")  // Buffer size (Int)
			],
			// === OUTPUTS ===
			[
				new Contact(null, OUTPUT, "buffer"),   // Full buffer (Array<Float>)
				new Contact(false, OUTPUT, "changed"), // Pulse when buffer ready
				new Contact(0, OUTPUT, "count")        // Current fill level
			],
			null,
			id,
			"BufferingAtom",
			true  // isActive = true → register in DriverManager
		);

		// Disable oscillation protection for "buffer" output
		// (large arrays change frequently)
		var bufferOut = getOutput("buffer");
		if (bufferOut != null)
		{
			bufferOut.ignoreOscillation = true;
		}

		// Pre-allocate buffer (Zero-GC)
		_buffer = new Array<Float>();
		for (i in 0...MAX_BUFFER_SIZE)
		{
			_buffer.push(0.0);
		}

		trace('BufferingAtom: Created (id: $id, default size: $_size)');
	}

	// =========================================================================
	// DRIVER INTERFACE
	// =========================================================================
	/**
	* Driver initialization.
	* Called once when registered in DriverManager.
	*/
	override public function init():Void
	{
		_count = 0;
		_pulseTimer = 0.0;
		_pulseActive = false;
		trace('BufferingAtom: Initialized');
	}

	/**
	* Update loop for active drivers.
	* Called by DriverManager every frame.
	*
	* Manages "changed" pulse timer.
	*
	* @param dt Delta time in seconds
	*/
	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;

		// Update pulse timer
		if (_pulseActive)
		{
			_pulseTimer -= dt;
			if (_pulseTimer <= 0)
			{
				var changedOut = getOutput("changed");
				if (changedOut != null)
				{
					changedOut.value = false;
				}
				_pulseActive = false;
			}
		}
	}

	/**
	* Free resources.
	*/
	override public function dispose():Void
	{
		DriverManager.getInstance().unregister(this.id);
		_buffer = null;
		super.dispose();
		trace('BufferingAtom: Disposed');
	}

	// =========================================================================
	// COMPUTE MODULE
	// =========================================================================
	/**
	* Called when any contact value changes.
	* Handles sample accumulation and buffer size changes.
	*/
	override public function onContactChanged(c:Contact):Void
	{
		if (_isDisposed) return;

		// Handle "size" parameter change
		if (c.name == "size" && c.value != null)
		{
			var newSize = Std.int(c.value);
			if (newSize >= MIN_BUFFER_SIZE && newSize <= MAX_BUFFER_SIZE)
			{
				if (newSize != _size)
				{
					_size = newSize;
					// If new size is smaller than current count, flush immediately
					if (_count >= _size)
					{
						flush();
					}
					trace('BufferingAtom: Buffer size changed to $_size');
				}
			}
			return;
		}

		// Handle "in" sample
		if (c.name == "in" && c.value != null)
		{
			var sample:Float = 0.0;

			// Type coercion
			if (Std.isOfType(c.value, Float))
			{
				sample = cast(c.value, Float);
			}
			else if (Std.isOfType(c.value, Int))
			{
				sample = cast(c.value, Int) * 1.0;
			}
			else if (Std.isOfType(c.value, String))
			{
				var parsed = Std.parseFloat(cast(c.value, String));
				if (!Math.isNaN(parsed))
				{
					sample = parsed;
				}
			}

			// Add to buffer (Zero-GC: reuse pre-allocated array)
			_buffer[_count] = sample;
			_count++;

			// Update count output (silent write)
			var countOut = getOutput("count");
			if (countOut != null)
			{
				countOut.setValueSilent(_count);
				countOut.propagateCurrentValue();
			}

			// Check if buffer is full
			if (_count >= _size)
			{
				flush();
			}
		}

		// Pass to base class for scheduling (if needed)
		super.onContactChanged(c);
	}

	/**
	* Flush the buffer: emit on outputs and reset.
	*
	* ═══════════════════════════════════════════════════════════════════
	* BATCH MODE PATTERN
	* ═══════════════════════════════════════════════════════════════════
	*
	* 1. Silent writes (no propagation)
	* 2. Single propagation per output
	*
	* This reduces TickGenerator load from 3 × 3 = 9 to 3 + 3 = 6 operations.
	*/
	private function flush():Void
	{
		var bufferOut = getOutput("buffer");
		var changedOut = getOutput("changed");
		var countOut = getOutput("count");

		// === BATCH WRITE (Silent) ===
		// 1. Pass buffer reference (Zero-GC: same array object)
		if (bufferOut != null)
		{
			// Create a copy for downstream atoms (they need their own reference)
			// This is the ONLY allocation in the entire pipeline
			var bufferCopy = _buffer.slice(0, _count);
			bufferOut.setValueSilent(bufferCopy);
		}

		// 2. Trigger "changed" pulse
		if (changedOut != null)
		{
			changedOut.setValueSilent(true);
		}

		// 3. Reset count
		if (countOut != null)
		{
			countOut.setValueSilent(0);
		}

		// === SINGLE PROPAGATION PER OUTPUT ===
		if (bufferOut != null) bufferOut.propagateCurrentValue();
		if (changedOut != null) changedOut.propagateCurrentValue();
		if (countOut != null) countOut.propagateCurrentValue();

		// Start pulse timer
		_pulseActive = true;
		_pulseTimer = PULSE_DURATION;

		// Reset accumulator (Zero-GC: just reset counter, array is reused)
		_count = 0;

		trace('BufferingAtom: Flushed $_size samples');
	}

	// =========================================================================
	// PUBLIC API
	// =========================================================================
	/**
	* Get current buffer size.
	*/
	public function getBufferSize():Int
	{
		return _size;
	}

	/**
	* Get current fill level.
	*/
	public function getFillLevel():Int
	{
		return _count;
	}

	/**
	* Manually flush the buffer (even if not full).
	* Useful for force-extracting partial data.
	*/
	public function forceFlush():Void
	{
		if (_count > 0)
		{
			flush();
		}
	}

	/**
	* Reset the buffer without emitting.
	*/
	public function reset():Void
	{
		_count = 0;

		var countOut = getOutput("count");
		if (countOut != null)
		{
			countOut.setValueSilent(0);
			countOut.propagateCurrentValue();
		}
	}

	// =========================================================================
	// STATE SERIALIZATION
	// =========================================================================
	override public function getPersistentState():Dynamic
	{
		var base = super.getPersistentState();
		var result:Dynamic = {
			bufferSize: _size
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

	override public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;
		super.restoreState(state);

		if (state.bufferSize != null)
		{
			var newSize = Std.int(state.bufferSize);
			if (newSize >= MIN_BUFFER_SIZE && newSize <= MAX_BUFFER_SIZE)
			{
				_size = newSize;
				var sizeContact = getInput("size");
				if (sizeContact != null)
				{
					sizeContact.value = _size;
				}
			}
		}
	}
}
