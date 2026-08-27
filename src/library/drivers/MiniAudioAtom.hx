package library.drivers;
#if cpp
import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;
// ============================================================================
// C++ HEADER INJECTION
// ============================================================================
// Injecting miniaudio header files and standard C++ libraries
// into the global header of the generated .cpp file.
// This is necessary for defining structures and functions that will be
// used in @:cppFileCode and untyped __cpp__.
@:headerCode('
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>
			 ')
// ============================================================================
// C++ IMPLEMENTATION INJECTION
// ============================================================================
// Injecting the audio engine implementation directly into the .cpp file.
// Here we define data structures for lock-free transfer of audio samples
// from the audio driver thread (Audio Thread) to the main application thread (Main Thread).
@:cppFileCode('
			  // Directive to include miniaudio implementation exactly once in one .cpp file
			  // to avoid linker errors (duplicate symbols).
#define MINIAUDIO_IMPLEMENTATION
#include "../../../../include/miniaudio.h"
#include <math.h>
#include <atomic>
#include <string.h>
			  // ═══════════════════════════════════════════════════════════════════════════
			  // LOCK-FREE DOUBLE BUFFER ARCHITECTURE
			  // ═══════════════════════════════════════════════════════════════════════════
			  //
			  //  ┌─────────────────────────────────────────────────────────────────────┐
			  //  │                    AUDIO THREAD (Producer)                          │
			  //  │                                                                     │
			  //  │  miniaudio callback ──► Writes samples to buffers[writeIndex]       │
			  //  │                           │                                         │
			  //  │                           ▼                                         │
			  //  │                     samplesWritten++                                │
			  //  │                           │                                         │
			  //  │                     (if buffer is full)                             │
			  //  │                           │                                         │
			  //  │                           ▼                                         │
			  //  │                     readyIndex = writeIndex  (memory_order_release) │
			  //  │                     writeIndex = 1 - writeIndex                     │
			  //  │                     samplesWritten = 0                              │
			  //  └─────────────────────────────────────────────────────────────────────┘
			  //                              │
			  //                              ▼ (Atomic flag readyIndex)
			  //  ┌─────────────────────────────────────────────────────────────────────┐
			  //  │                    MAIN THREAD (Consumer)                           │
			  //  │                                                                     │
			  //  │  update(dt) ──► _scope_get_ready_index()                            │
			  //  │                     │                                               │
			  //  │                     ▼                                               │
			  //  │               (if readyIndex >= 0)                                  │
			  //  │                     │                                               │
			  //  │                     ▼                                               │
			  //  │               Copy data from buffers[readyIndex] to Haxe arrays     │
			  //  │                     │                                               │
			  //  │                     ▼                                               │
			  //  │               _scope_clear_ready() (readyIndex = -1)                │
			  //  └─────────────────────────────────────────────────────────────────────┘
			  //
			  // This scheme guarantees:
			  // 1. No locks (mutex-free) — critical for real-time audio.
			  // 2. No memory allocations in the playback/capture thread.
			  // 3. Correct synchronization via std::atomic and memory ordering.
			  // ═══════════════════════════════════════════════════════════════════════════
			  // Double buffer structure for transferring audio data between threads.
			  struct DoubleBuffer {
			  // Two buffers for samples (Ping-Pong).
			  // Format: interleaved stereo (L, R, L, R...).
			  // Size: 512 frames * 2 channels = 1024 floats per buffer.
			  float buffers[2][512 * 2];
			  // Index of the buffer Audio Thread is currently writing to.
			  std::atomic<int> writeIndex;
			  // Index of the buffer that is filled and ready for Main Thread reading.
			  // -1 means no buffers are ready.
			  std::atomic<int> readyIndex;
			  // Counter of samples written to the current buffer (writeIndex).
			  std::atomic<int> samplesWritten;
			  // Target buffer size (number of frames after which buffer is considered full).
			  int targetSize;
			  DoubleBuffer() : writeIndex(0), readyIndex(-1), samplesWritten(0), targetSize(512) {
			  memset(buffers, 0, sizeof(buffers));
			  }
			  };
			  // ═══════════════════════════════════════════════════════════════════════════
			  // AUDIO CALLBACK (PRODUCER THREAD)
			  // ═══════════════════════════════════════════════════════════════════════════
			  // This function is called by the miniaudio library in a separate thread
			  // every time the audio device is ready to accept/provide a portion of data.
			  //
			  // CRITICAL: Memory allocation, mutexes, or blocking system calls are FORBIDDEN here.
			  static void _altauri_audio_cb_double(
			  ma_device*  pDevice,
			  void*       pOutput,
			  const void* pInput,
			  ma_uint32   frameCount)
			  {
			  // Get pointer to the Haxe class instance (MiniAudioAtom).
			  // pUserData was set during device initialization.
			  ::library::drivers::MiniAudioAtom_obj* self =
			  (::library::drivers::MiniAudioAtom_obj*)(pDevice->pUserData);
			  // Dispose check: if object is already destroyed, exit immediately.
			  // _isDisposed is marked as @:volatile in Haxe so C++ compiler
			  // does not cache its value in the thread register.
			  if (!self || (bool)self->_isDisposed) return;
			  DoubleBuffer* db = (DoubleBuffer*)self->_doubleBufferRaw;
			  if (!db) return;
			  const float* samples = (const float*)pInput;
			  if (!samples) return;
			  // Read atom parameters. They can be changed from Main Thread,
			  // but it is acceptable for the audio thread to read them without mutex (tearing allowed),
			  // as these are just gain coefficients.
			  float gain = (float)self->_gain;
			  int channel = (int)self->_channel;
			  float quantum = (float)self->_quantum;
			  // Variables for accumulating RMS (Root Mean Square) and clipping detection.
			  float rmsAccum = 0.0f;
			  bool clip = false;
			  float lastSample = 0.0f;
			  // Load buffer indices.
			  // memory_order_relaxed is sufficient as we read our own local data,
			  // and synchronization between threads happens only when writing to readyIndex.
			  int writeIdx = db->writeIndex.load(std::memory_order_relaxed);
			  float* buffer = db->buffers[writeIdx];
			  int accum = db->samplesWritten.load(std::memory_order_relaxed);
			  int targetSize = db->targetSize;
			  // Main loop for processing audio frames.
			  for (ma_uint32 i = 0; i < frameCount; i++)
			  {
			  // Read stereo pair (interleaved format: L, R, L, R...).
			  // Apply gain coefficient.
			  float left  = samples[i * 2]     * gain;
			  float right = samples[i * 2 + 1] * gain;
			  // Mix to mono depending on selected channel.
			  float mono = 0.0f;
			  if (channel == 0) mono = (left + right) * 0.5f; // Average (Mono)
			  else if (channel == 1) mono = left;             // Left only
			  else if (channel == 2) mono = right;            // Right only
			  // Clipping detection (exceeding [-1.0, 1.0] range).
			  if (mono >  1.0f) { mono =  1.0f; clip = true; }
			  if (mono < -1.0f) { mono = -1.0f; clip = true; }
			  // Accumulate sum of squares for RMS calculation.
			  rmsAccum += mono * mono;
			  lastSample = mono;
			  // Write samples to buffer ONLY if it is not yet overflowed.
			  // This protects against array overflow if frameCount > targetSize.
			  if (accum < targetSize) {
			  int bufIdx = accum * 2;
			  buffer[bufIdx]     = left;
			  buffer[bufIdx + 1] = right;
			  accum++;
			  }
			  }
			  // Save number of written samples.
			  db->samplesWritten.store(accum, std::memory_order_relaxed);
			  // ═══════════════════════════════════════════════════════════════════
			  // SWAP BUFFERS (LOCK-FREE HANDSHAKE)
			  // ═══════════════════════════════════════════════════════════════════
			  // If buffer is filled to target size, we must pass it
			  // to Main Thread and switch to the second buffer.
			  if (accum >= targetSize) {
			  // 1. Publish index of filled buffer.
			  // memory_order_release guarantees that all writes to buffer[]
			  // will be visible to Main Thread BEFORE it reads readyIndex.
			  db->readyIndex.store(writeIdx, std::memory_order_release);
			  // 2. Switch to second buffer (Ping-Pong).
			  int nextIdx = 1 - writeIdx;
			  db->writeIndex.store(nextIdx, std::memory_order_release);
			  // 3. Reset counter for new buffer.
			  db->samplesWritten.store(0, std::memory_order_relaxed);
			  }
			  // ═══════════════════════════════════════════════════════════════════
			  // METADATA CALCULATION
			  // ═══════════════════════════════════════════════════════════════════
			  // Calculate RMS (volume level) and quantized sample.
			  float rms = sqrtf(rmsAccum / (float)frameCount);
			  // Amplitude quantization: round to nearest step (quantum).
			  // This allows generating "changed" impulse only when crossing
			  // threshold values, useful for triggers and events.
			  float quantized = roundf(lastSample / quantum) * quantum;
			  if (quantized >  1.0f) quantized =  1.0f;
			  if (quantized < -1.0f) quantized = -1.0f;
			  // Detect change in quantized value.
			  // Ignore first change (initialization).
			  bool changed = (!(bool)self->_isFirstSample) &&
			  (quantized != (float)self->_lastQuantum);
			  // ═══════════════════════════════════════════════════════════════════
			  // CROSS-THREAD DATA TRANSFER (PRODUCER -> CONSUMER)
			  // ═══════════════════════════════════════════════════════════════════
			  // Write calculated metadata to volatile fields of Haxe object.
			  // Main Thread will read them in update(dt).
			  // @:volatile in Haxe guarantees that C++ will not cache these variables
			  // in registers and will read/write them directly to RAM.
			  self->_pendingSample  = quantized;
			  self->_pendingRms     = rms;
			  self->_pendingClip    = clip;
			  self->_pendingChanged = changed;
			  self->_lastQuantum    = quantized;
			  self->_isFirstSample  = false;
			  self->_hasPending     = true; // Flag: "New data available for processing"
			  }
			  // ═══════════════════════════════════════════════════════════════════════════
			  // C-API FOR HAXE INTEROP
			  // ═══════════════════════════════════════════════════════════════════════════
			  // These functions are called from Haxe via untyped __cpp__.
			  // They provide safe access to the DoubleBuffer structure.
			  // Returns ready buffer index or -1 if none ready.
			  extern "C" int _scope_get_ready_index(void* raw) {
			  if (!raw) return -1;
			  // memory_order_acquire guarantees that we see all writes to buffer[]
			  // made by Audio Thread BEFORE setting readyIndex.
			  return ((DoubleBuffer*)raw)->readyIndex.load(std::memory_order_acquire);
			  }
			  // Returns raw pointer to float array in specified buffer.
			  extern "C" void* _scope_get_buffer_ptr(void* raw, int index) {
			  if (!raw || index < 0 || index > 1) return nullptr;
			  return (void*)((DoubleBuffer*)raw)->buffers[index];
			  }
			  // Resets buffer ready flag (Main Thread signals that data has been copied).
			  extern "C" void _scope_clear_ready(void* raw) {
			  if (!raw) return;
			  ((DoubleBuffer*)raw)->readyIndex.store(-1, std::memory_order_release);
			  }
			  ')
/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     MINI AUDIO ATOM v1.2                                  ║
* ║                     (Zero-GC Real-Time Audio Capture)                     ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Audio capture driver (microphone or system loopback) based on            ║
* ║  miniaudio library. Supports raw sample transfer,                         ║
* ║  RMS calculation, clipping detection and amplitude quantization.          ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │                     MiniAudioAtom                                   │  ║
* ║  │                                                                     │  ║
* ║  │  A) COMPUTE MODULE (Main Thread — update(dt)):                      │  ║
* ║  │     ─────────────────────────────────────────                       │  ║
* ║  │     1. readInputs()                                                 │  ║
* ║  │        - Read parameters from input contacts                        │  ║
* ║  │        - mode, quantum, gain, channel, rate, bufferSize             │  ║
* ║  │                                                                     │  ║
* ║  │     2. checkDoubleBuffer()                                          │  ║
* ║  │        - Poll C++ buffer for ready data                             │  ║
* ║  │        - If readyIndex >= 0:                                        │  ║
* ║  │            propagateScopeBuffer() → copy to Haxe arrays             │  ║
* ║  │            _scope_clear_ready() → release buffer                    │  ║
* ║  │                                                                     │  ║
* ║  │     3. Batched Driver Update Pattern                                │  ║
* ║  │        - setValueSilent() for all output contacts                   │  ║
* ║  │        - propagateCurrentValue() once per contact                   │  ║
* ║  │        - This reduces TickGenerator load                            │  ║
* ║  │                                                                     │  ║
* ║  │  B) DATABANK (Haxe):                                                │  ║
* ║  │     ─────────────────────                                           │  ║
* ║  │     _mode, _quantum, _gain, _channel, _sampleRateIdx                │  ║
* ║  │     _lastQuantum, _isFirstSample                                    │  ║
* ║  │     _bufA, _bufLA, _bufRA (Ping-Pong Buffer A)                      │  ║
* ║  │     _bufB, _bufLB, _bufRB (Ping-Pong Buffer B)                      │  ║
* ║  │                                                                     │  ║
* ║  │  C) CROSS-THREAD STATE (@:volatile):                                │  ║
* ║  │     ─────────────────────────────────                               │  ║
* ║  │     _hasPending, _pendingSample, _pendingRms,                       │  ║
* ║  │     _pendingClip, _pendingChanged                                   │  ║
* ║  │     (Written in Audio Thread, read in Main Thread)                  │  ║
* ║  │                                                                     │  ║
* ║  │  D) INPUTS:                                                         │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "mode"       - 0 = Mic, 1 = Loopback                            │  ║
* ║  │     "quantum"    - Amplitude quantization step (0.001 .. 1.0)       │  ║
* ║  │     "gain"       - Gain coefficient                                 │  ║
* ║  │     "channel"    - 0=Mono, 1=Left, 2=Right                          │  ║
* ║  │     "rate"       - Sample rate index (44100/48000/96000)            │  ║
* ║  │     "bufferSize" - Buffer size (64 .. 512 frames)                   │  ║
* ║  │                                                                     │  ║
* ║  │  E) OUTPUTS:                                                        │  ║
* ║  │     ────────                                                        │  ║
* ║  │     "sample"    - Quantized sample (Float)                          │  ║
* ║  │     "changed"   - Impulse on quantized value change                 │  ║
* ║  │     "rms"       - RMS volume level (Float)                          │  ║
* ║  │     "clip"      - Clipping impulse (Bool)                           │  ║
* ║  │     "tick"      - Impulse on each processed buffer (Bool)           │  ║
* ║  │     "level"     - Level in dBFS (Float)                             │  ║
* ║  │     "device"    - Device name (String)                              │  ║
* ║  │     "buffer"    - Mono buffer (Array<Float>)                        │  ║
* ║  │     "bufferL"   - Left channel (Array<Float>)                       │  ║
* ║  │     "bufferR"   - Right channel (Array<Float>)                      │  ║
* ║  │                                                                     │  ║
* ║  │  F) FACE (DeviceView):                                              │  ║
* ║  │     ─────────────────                                               │  ║
* ║  │     MiniAudioWidget for VU meter visualization and control          │  ║
* ║  │                                                                     │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    ZERO-GC PING-PONG BUFFERS                              ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  In Haxe, runtime array allocation causes garbage collection (GC),        ║
* ║  which leads to micro-freezes in the audio stream.                        ║
* ║                                                                           ║
* ║  Solution:                                                                ║
* ║  ┌──────────────────────────────────────────────────────────────────────┐ ║
* ║  │  init() pre-allocates 6 fixed-size arrays:                           │ ║
* ║  │    _bufA, _bufLA, _bufRA (Buffer A)                                  │ ║
* ║  │    _bufB, _bufLB, _bufRB (Buffer B)                                  │ ║
* ║  │                                                                      │ ║
* ║  │  In propagateScopeBuffer() we simply switch pointers:                │ ║
* ║  │    if (_activeBuf == 0) target = _bufB; else target = _bufA;         │ ║
* ║  │                                                                      │ ║
* ║  │  Result: 0 allocations per processed audio buffer.                   │ ║
* ║  └──────────────────────────────────────────────────────────────────────┘ ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                    VERSION HISTORY                                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v1.1 (Current) — Idempotent Lifecycle (Fix A, Task 96)                   ║
* ║    • FIX: openDevice() resource-liveness guard — the double init()        ║
* ║      opened TWO devices; device #1 leaked with a live audio callback      ║
* ║      (sample race on the shared DoubleBuffer + UAF after dispose/GC       ║
* ║      of the atom — the "rebirth crash" on Back [<]).                      ║
* ║    • FIX: init() memo guard (no double ping-pong buffer allocation).      ║
* ║    • FIX: closeDevice() total-sweep guard (releases ANY live pointer,     ║
* ║      not only when the _deviceReady flag is set).                         ║
* ║    • FIX: OOM path in openDevice() frees the surviving allocation.        ║
* ║                                                                           ║
* ║  v1.0 — Initial Zero-GC real-time audio capture                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class MiniAudioAtom extends Atom implements system.managers.Driver
{
// =========================================================================
// CONSTANTS
// =========================================================================
	/** Minimum amplitude quantization step. */
	private static inline var MIN_QUANTUM:Float    = 0.001;
	/** Maximum amplitude quantization step. */
	private static inline var MAX_QUANTUM:Float    = 1.0;
	/** Duration of impulse (tick, changed, clip) in seconds. */
	private static inline var PULSE_DURATION:Float = 0.05;
	/** Capture mode: Microphone. */
	private static inline var MODE_MIC:Int      = 0;
	/** Capture mode: System Loopback (what is being played). */
	private static inline var MODE_LOOPBACK:Int = 1;
	/** Supported sample rates. */
	private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];
// =========================================================================
// C++ POINTERS (DATABANK)
// =========================================================================
	/** Pointer to ma_device structure in C++. */
	private var _device:cpp.RawPointer<cpp.Void>  = null;
	/** Pointer to ma_context structure in C++. */
	private var _context:cpp.RawPointer<cpp.Void> = null;
	/** Pointer to DoubleBuffer structure in C++. */
	private var _deviceReady:Bool = false;
// =========================================================================
// PARAMETERS (DATABANK)
// =========================================================================
	/** Current operation mode (Mic or Loopback). */
	private var _mode:Int          = MODE_LOOPBACK;
	/** Amplitude quantization step. */
	private var _quantum:Float     = 0.01;
	/** Signal gain coefficient. */
	private var _gain:Float        = 1.0;
	/** Selected channel (0=Mono, 1=Left, 2=Right). */
	private var _channel:Int       = 0;
	/** Sample rate index in SAMPLE_RATES array. */
	private var _sampleRateIdx:Int = 0;
	/** Last quantized sample (for change detection). */
	private var _lastQuantum:Float  = 0.0;
	/** First sample flag (ignore change on initialization). */
	private var _isFirstSample:Bool = true;
// =========================================================================
// CROSS-THREAD STATE (@:volatile)
// =========================================================================
// These fields are written in Audio Thread (C++ callback)
// and read in Main Thread (Haxe update).
// @:volatile forces C++ compiler to always read/write them to RAM,
// avoiding caching in processor registers.
	/** Raw pointer to DoubleBuffer. */
	@:volatile private var _doubleBufferRaw:cpp.RawPointer<cpp.Void> = null;
	/** Flag: new data available for processing in Main Thread. */
	@:volatile private var _hasPending:Bool     = false;
	/** Last quantized sample (from Audio Thread). */
	@:volatile private var _pendingSample:Float  = 0.0;
	/** Last calculated RMS (from Audio Thread). */
	@:volatile private var _pendingRms:Float     = 0.0;
	/** Clipping flag (from Audio Thread). */
	@:volatile private var _pendingClip:Bool     = false;
	/** Quantized value change flag (from Audio Thread). */
	@:volatile private var _pendingChanged:Bool  = false;
// =========================================================================
// PULSE TIMERS (MAIN THREAD STATE)
// =========================================================================
	/** Timer for resetting "changed" impulse. */
	private var _changedTimer:Float = 0.0;
	/** Timer for resetting "tick" impulse. */
	private var _tickTimer:Float    = 0.0;
	/** Timer for resetting "clip" impulse. */
	private var _clipTimer:Float    = 0.0;
	/** Target buffer size in frames. */
	private var _bufferSize:Int = 512;
// =========================================================================
// ZERO-GC PING-PONG BUFFERS
// =========================================================================
// Pre-allocated arrays for copying data from C++ without allocations.
// We use two sets of buffers (A and B) to copy data
// from C++ into one set while the other set is passed to downstream atoms.
	/** Buffer A: Mono mix. */
	private var _bufA:Array<Float>;
	/** Buffer A: Left channel. */
	private var _bufLA:Array<Float>;
	/** Buffer A: Right channel. */
	private var _bufRA:Array<Float>;
	/** Buffer B: Mono mix. */
	private var _bufB:Array<Float>;
	/** Buffer B: Left channel. */
	private var _bufLB:Array<Float>;
	/** Buffer B: Right channel. */
	private var _bufRB:Array<Float>;
	/** Active buffer index (0 = A, 1 = B). */
	private var _activeBuf:Int = 0;
// =========================================================================
// CONSTRUCTOR
// =========================================================================
	/**
	* Creates a new MiniAudioAtom instance.
	* Initializes input/output contacts, registers driver.
	*
	* @param id Unique atom identifier.
	*/
	public function new(id:String)
	{
		super(
// === INPUTS (Control parameters) ===
			[
				new Contact(MODE_LOOPBACK, INPUT, "mode"),       // 0 = Mic, 1 = Loopback
				new Contact(0.01, INPUT, "quantum"),             // Quantization step
				new Contact(50.0, INPUT, "gain"),                // Gain
				new Contact(0, INPUT, "channel"),                // 0=Mono, 1=Left, 2=Right
				new Contact(0, INPUT, "rate"),                   // Rate index
				new Contact(512, INPUT, "bufferSize")            // Buffer size
			],
// === OUTPUTS (Data and metadata) ===
			[
				new Contact(0.0, OUTPUT, "sample"),              // Quantized sample
				new Contact(false, OUTPUT, "changed"),           // Change impulse
				new Contact(0.0, OUTPUT, "rms"),                 // RMS level
				new Contact(false, OUTPUT, "clip"),              // Clipping impulse
				new Contact(false, OUTPUT, "tick"),              // Buffer processed impulse
				new Contact(0.0, OUTPUT, "level"),               // Level in dBFS
				new Contact("", OUTPUT, "device"),               // Device name
				new Contact(null, OUTPUT, "buffer"),             // Mono buffer (Array)
				new Contact(null, OUTPUT, "bufferL"),            // Left channel (Array)
				new Contact(null, OUTPUT, "bufferR")             // Right channel (Array)
			],
			null,          // No standard process function (we are Driver)
			id,
			"MiniAudioAtom",
			true           // isActive = true -> registered in DriverManager
		);
// Disable oscillation protection for "sample" output,
// as we expect frequent value changes.
		var sampleOut = getOutput("sample");
		if (sampleOut != null) sampleOut.ignoreOscillation = true;
// Initialize driver (open audio device).
		init();
	}
// =========================================================================
// LIFECYCLE
// =========================================================================
	/**
	* Driver initialization.
	* Called once upon registration in DriverManager.
	* Pre-allocates Zero-GC buffers and opens audio device.
	*/
	override public function init():Void
	{
// ═══════════════════════════════════════════════════════════════════
// IDEMPOTENCY GUARD (v1.1, Fix A — Task 96).
// init() is invoked TWICE in the constructor flow: once implicitly via
// DriverManager.register() — the Atom base constructor (isActive=true)
// registers this driver and register() calls driver.init(), a VIRTUAL
// call that lands in THIS override before the derived constructor body
// has run — and once explicitly at the end of the constructor body.
// Without a guard every MiniAudioAtom allocation built TWO sets of
// ping-pong buffers (6 wasted arrays per atom per "rebirth") and fed
// openDevice() twice (see the guard there for the fatal consequences).
// Memo guard: _bufA != null means the allocation phase already ran.
		if (_bufA != null) return;
// 1. Pre-allocation of Zero-GC Ping-Pong Buffers.
// We create fixed-size arrays once to avoid
// runtime allocations (which would trigger GC).
		_bufA = new Array<Float>(); _bufLA = new Array<Float>(); _bufRA = new Array<Float>();
		_bufB = new Array<Float>(); _bufLB = new Array<Float>(); _bufRB = new Array<Float>();
// Fill with zeros (512 frames).
		for (i in 0...512)
		{
			_bufA.push(0.0); _bufLA.push(0.0); _bufRA.push(0.0);
			_bufB.push(0.0); _bufLB.push(0.0); _bufRB.push(0.0);
		}
// 2. Read initial parameters from contacts.
		readInputs();
// 3. Open audio device (start capture).
		openDevice();
	}
	/**
	* Main driver update loop.
	* Called every frame from DriverManager.update(dt).
	*
	* ═══════════════════════════════════════════════════════════════════
	* BATCHED DRIVER UPDATE PATTERN
	* ═══════════════════════════════════════════════════════════════════
	*
	*  ┌─────────────────────────────────────────────────────────────────┐
	*  │  1. setValueSilent(value) for all outputs                      │
	*  │     → Write value to _value, NOT triggering propagation.       │
	*  │                                                                 │
	*  │  2. propagateCurrentValue() once per output                    │
	*  │     → Notify subscribers (widgets, downstream atoms).          │
	*  │                                                                 │
	*  │  Result: Reduced TickGenerator load,                           │
	*  │  as propagation happens not on every write,                    │
	*  │  but only once per frame per contact.                          │
	*  └─────────────────────────────────────────────────────────────────┘
	*
	* @param dt Delta time (time since last frame in seconds).
	*/
	override public function update(dt:Float):Void
	{
// Dispose check: if object is destroyed, exit.
		if (_isDisposed) return;
// 1. Check if there is ready data in Double Buffer.
		checkDoubleBuffer();
// 2. If Audio Thread passed new data (_hasPending == true)...
		if (_hasPending)
		{
// Reset flag to prevent re-processing data.
			_hasPending = false;
// Save data snapshot to local variables.
// This guarantees we work with consistent data,
// even if Audio Thread has already started writing new data.
			var snapSample  = _pendingSample;
			var snapRms     = _pendingRms;
			var snapClip    = _pendingClip;
			var snapChanged = _pendingChanged;
// Get references to output contacts.
			var sampleOut = getOutput("sample");
			var rmsOut    = getOutput("rms");
			var levelOut  = getOutput("level");
// === BATCHED WRITE (Silent) ===
// Write values without triggering propagation.
			if (sampleOut != null) sampleOut.setValueSilent(snapSample);
			if (rmsOut    != null) rmsOut.setValueSilent(snapRms);
// Convert RMS to dBFS (decibels relative to Full Scale).
// Formula: 20 * log10(rms). If rms is close to 0, return -120 dB.
			if (levelOut != null)
			{
				var db = snapRms > 0.0001 ? 20.0 * Math.log(snapRms) / Math.log(10) : -120.0;
				levelOut.setValueSilent(db);
			}
// === PULSE GENERATION (Tick, Changed, Clip) ===
// Generate short impulses (PULSE_DURATION seconds).
			var tickOut = getOutput("tick");
			if (tickOut != null) { tickOut.value = true; _tickTimer = PULSE_DURATION; }
			if (snapChanged)
			{
				var c = getOutput("changed");
				if (c != null) { c.value = true; _changedTimer = PULSE_DURATION; }
			}
			if (snapClip)
			{
				var c = getOutput("clip");
				if (c != null) { c.value = true; _clipTimer = PULSE_DURATION; }
			}
// === PROPAGATION (One-shot) ===
// Notify subscribers that data has updated.
// This triggers recalculation of downstream atoms and widget updates.
			if (sampleOut != null) sampleOut.propagateCurrentValue();
			if (rmsOut    != null) rmsOut.propagateCurrentValue();
			if (levelOut  != null) levelOut.propagateCurrentValue();
		}
// 3. Update impulse timers (reset them to false after time expires).
		updatePulseTimers(dt);
// 4. Read input parameters (user may have changed settings).
		readInputs();
	}
	/**
	* Release resources.
	* Called when atom is removed from scene.
	* Closes audio device and unregisters from DriverManager.
	*/
	override public function dispose():Void
	{
		closeDevice();
		DriverManager.getInstance().unregister(this.id);
		super.dispose();
	}
// =========================================================================
// DOUBLE BUFFER CHECK (MAIN THREAD)
// =========================================================================
	/**
	* Checks for ready data in C++ Double Buffer.
	* If buffer is ready, copies data to Haxe arrays and propagates.
	*/
	private function checkDoubleBuffer():Void
	{
		if (_doubleBufferRaw == null) return;
		var readyIndex:Int = -1;
// Call C++ function to get ready buffer index.
		untyped __cpp__('{0} = ::_scope_get_ready_index({1});', readyIndex, _doubleBufferRaw);
// If readyIndex >= 0, Audio Thread has filled the buffer.
		if (readyIndex >= 0)
		{
// Copy data from C++ to Haxe arrays (Ping-Pong).
			propagateScopeBuffer(readyIndex);
// Notify C++ that we copied data and buffer can be reused.
			untyped __cpp__('::_scope_clear_ready({0});', _doubleBufferRaw);
		}
	}
// =========================================================================
// DEVICE MANAGEMENT
// =========================================================================
	/**
	* Opens audio device (microphone or loopback).
	* Initializes miniaudio context and device, starts capture.
	*/
	private function openDevice():Void
	{
// ═══════════════════════════════════════════════════════════════════
// RESOURCE-LIVENESS GUARD (v1.1, Fix A — Task 96) — ROOT FIX of the
// "rebirth crash" (app exit on Back [<] with a reborn MiniAudioAtom).
//
// HISTORY: openDevice() had NO guard. The double init() in the
// constructor flow (DriverManager.register callback + explicit call)
// therefore opened TWO miniaudio devices: device #1 kept RUNNING while
// its _context/_device/_doubleBufferRaw pointers were OVERWRITTEN by
// the second open. Consequences:
//   1) device #1 leaked and its audio callback kept firing every
//      ~11.6 ms with pUserData pointing at this Haxe object;
//   2) BOTH callbacks raced on the same DoubleBuffer (the "sample
//      data race");
//   3) after dispose() + GC of the atom, pUserData dangled →
//      use-after-free → heap corruption (crash exactly at "rebirth").
//
// GUARD: refuse to open while ANY native resource of this atom is
// live. Every failure path of the C++ block below nulls all pointers,
// so a failed open leaves all four conditions false → retry via
// restart() remains fully allowed. restart() itself is unaffected:
// closeDevice() nulls every pointer before openDevice() re-enters.
		if (_deviceReady || _device != null || _context != null || _doubleBufferRaw != null) return;
// Determine sample rate and device type.
		var sampleRate : Int = SAMPLE_RATES[_sampleRateIdx];
		var deviceType : Int = (_mode == MODE_LOOPBACK) ? 2 : 1; // 2 = loopback, 1 = capture
// ═══════════════════════════════════════════════════════════════════
// C++ INITIALIZATION BLOCK
// ═══════════════════════════════════════════════════════════════════
// Here happens all the miniaudio initialization magic.
// We use untyped __cpp__ for direct C++ API calls.
		untyped __cpp__('
		// 1. Create Double Buffer in heap.
		DoubleBuffer* db = new DoubleBuffer();
		db->targetSize = {2}; // Set target buffer size.
		{0}->_doubleBufferRaw = (void*)db; // Save pointer to Haxe object.
		// 2. Allocate memory for context and device.
		ma_context* ctx = (ma_context*)malloc(sizeof(ma_context));
		ma_device*  dev = (ma_device*)malloc(sizeof(ma_device));
		if (!ctx || !dev) {
		// v1.1 (Task 96): free whichever allocation succeeded (OOM hygiene).
		if (ctx) free(ctx);
		if (dev) free(dev);
		delete db;
		{0}->_doubleBufferRaw = nullptr;
		return;
	}
		// 3. Initialize miniaudio context.
		ma_result result = ma_context_init(NULL, 0, NULL, ctx);
		if (result != MA_SUCCESS) {
		free(ctx); free(dev); delete db;
		{0}->_doubleBufferRaw = nullptr;
		return;
	}
		{0}->_context = ctx;
		// 4. Configure device.
		ma_device_config cfg = ma_device_config_init(
		{1} == 2 ? ma_device_type_loopback : ma_device_type_capture
		);
		cfg.sampleRate         = (ma_uint32){3}; // Sample rate.
		cfg.periodSizeInFrames = 512;            // Frame size (latency).
		cfg.capture.format     = ma_format_f32;  // Format: 32-bit float.
		cfg.capture.channels   = 2;              // Channels: Stereo.
		// Specify callback function to be called for each frame.
		cfg.dataCallback       = _altauri_audio_cb_double;
		// Pass pointer to Haxe object to callback (pUserData).
		cfg.pUserData          = (void*)({0}.mPtr);
		// 5. Initialize device.
		result = ma_device_init(ctx, &cfg, dev);
		if (result != MA_SUCCESS) {
		ma_context_uninit(ctx);
		free(ctx); free(dev); delete db;
		{0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
		return;
	}
		{0}->_device = dev;
		// 6. Start capture/playback.
		result = ma_device_start(dev);
		if (result != MA_SUCCESS) {
		ma_device_uninit(dev); ma_context_uninit(ctx);
		free(dev); free(ctx); delete db;
		{0}->_device = NULL; {0}->_context = NULL; {0}->_doubleBufferRaw = nullptr;
		return;
	}
		// If everything succeeded, set ready flag.
		{0}->_deviceReady = true;
		', this, deviceType, _bufferSize, sampleRate);
// Update output contact with device name.
		if (_deviceReady)
		{
			setDeviceNameOutput((_mode == MODE_LOOPBACK) ? "Loopback @" + sampleRate + "Hz" : "Capture @" + sampleRate + "Hz");
			// v1.2 FAULT ISOLATION: a healthy (re)activation unlatches any
			// previous fault — Restart button, rebirth and parameter change
			// are the manual retry paths by design (no autopilot).
			clearFault();
		}
		else
		{
			setDeviceNameOutput("ERROR: device init failed");
			// v1.2 FAULT ISOLATION: latch the failure — red frame + one
			// black-box line instead of an error string buried in the
			// "device" contact output.
			markAsFaulted("AUDIO_INIT_FAILED", "miniaudio init/start failed (mode=" + _mode + ", rate idx=" + _sampleRateIdx + ")");
		}
	}
	/**
	* Closes audio device and releases resources.
	*/
	private function closeDevice():Void
	{
// ═══════════════════════════════════════════════════════════════════
// TOTAL-SWEEP GUARD (v1.1, Fix A — Task 96).
// Mirror of the openDevice() liveness guard: release if ANY native
// resource pointer is live — not only when the _deviceReady flag is
// set. The C++ block below already null-checks dev/ctx/db individually,
// so sweeping with partially-live state is safe. The old guard trusted
// a single flag; a stuck flag would have leaked a RUNNING device (the
// exact bug class Fix A eliminates at the source).
		if (!_deviceReady && _device == null && _context == null && _doubleBufferRaw == null) return;
		_deviceReady = false;
// ═══════════════════════════════════════════════════════════════════
// C++ CLEANUP BLOCK
// ═══════════════════════════════════════════════════════════════════
		untyped __cpp__('
		ma_device*  dev = (ma_device*) {0}->_device;
		ma_context* ctx = (ma_context*){0}->_context;
		DoubleBuffer* db = (DoubleBuffer*){0}->_doubleBufferRaw;
		// Stop and destroy device.
		if (dev) { ma_device_stop(dev); ma_device_uninit(dev); free(dev); }
		// Destroy context.
		if (ctx) { ma_context_uninit(ctx); free(ctx); }
		// Free Double Buffer.
		if (db)  { delete db; }
		// Nullify pointers in Haxe object.
		{0}->_device = nullptr;
		{0}->_context = nullptr;
		{0}->_doubleBufferRaw = nullptr;
		', this);
	}
// =========================================================================
// BUFFER PROPAGATION (ZERO-GC)
// =========================================================================
	/**
	* Copies data from C++ buffer to Haxe arrays (Ping-Pong).
	* Uses pre-allocated arrays to avoid allocations (Zero-GC).
	*
	* @param readyIndex Index of ready buffer in C++ (0 or 1).
	*/
	private function propagateScopeBuffer(readyIndex:Int):Void
	{
		if (_doubleBufferRaw == null) return;
// ═══════════════════════════════════════════════════════════════════
// PING-PONG BUFFER SELECTION
// ═══════════════════════════════════════════════════════════════════
// Select inactive buffer set for writing.
// While we copy to _bufB, downstream atoms can read from _bufA.
		var targetBuf:Array<Float>;
		var targetBufL:Array<Float>;
		var targetBufR:Array<Float>;
		if (_activeBuf == 0)
		{
			targetBuf = _bufB; targetBufL = _bufLB; targetBufR = _bufRB;
			_activeBuf = 1; // Next time we will write to A.
		}
		else {
			targetBuf = _bufA; targetBufL = _bufLA; targetBufR = _bufRA;
			_activeBuf = 0; // Next time we will write to B.
		}
// Get raw pointer to float array in C++ buffer.
		var rawPtr:cpp.RawPointer<cpp.Void> = untyped __cpp__('(void*)::_scope_get_buffer_ptr({0}, {1})', _doubleBufferRaw, readyIndex);
		var ptr:cpp.Pointer<cpp.Float32> = untyped __cpp__('(cpp::Float32*){0}', rawPtr);
// ═══════════════════════════════════════════════════════════════════
// DATA COPY (INTERLEAVED -> PLANAR)
// ═══════════════════════════════════════════════════════════════════
// Copy data from C++ (interleaved: L, R, L, R...)
// to Haxe arrays (planar: Mono, Left, Right).
		if (ptr != null)
		{
			var count = _bufferSize;
			for (i in 0...count)
			{
				var idx = i * 2;
				var l:Float = ptr[idx];
				var r:Float = ptr[idx + 1];
// Mono mix: average of left and right channels.
				targetBuf[i] = (l + r) * 0.5;
				targetBufL[i] = l;
				targetBufR[i] = r;
			}
		}
// ═══════════════════════════════════════════════════════════════════
// PROPAGATION (BATCHED)
// ═══════════════════════════════════════════════════════════════════
// Pass filled arrays to output contacts.
		var bufOut  = getOutput("buffer");
		var bufLOut = getOutput("bufferL");
		var bufROut = getOutput("bufferR");
// Use Batched Driver Update pattern:
// 1. setValueSilent (write without trigger)
// 2. propagateCurrentValue (notify subscribers)
		if (bufOut  != null) { bufOut.setValueSilent(targetBuf);  bufOut.propagateCurrentValue(); }
		if (bufLOut != null) { bufLOut.setValueSilent(targetBufL); bufLOut.propagateCurrentValue(); }
		if (bufROut != null) { bufROut.setValueSilent(targetBufR); bufROut.propagateCurrentValue(); }
	}
// =========================================================================
// PULSE TIMERS
// =========================================================================
	/**
	* Updates impulse timers (tick, changed, clip).
	* Resets output values to false after PULSE_DURATION expires.
	*
	* @param dt Delta time (time since last frame in seconds).
	*/
	private function updatePulseTimers(dt:Float):Void
	{
// "tick" timer
		if (_tickTimer > 0)
		{
			_tickTimer -= dt;
			if (_tickTimer <= 0)
			{
				var c = getOutput("tick");
				if (c != null) c.value = false;
			}
		}
// "changed" timer
		if (_changedTimer > 0)
		{
			_changedTimer -= dt;
			if (_changedTimer <= 0)
			{
				var c = getOutput("changed");
				if (c != null) c.value = false;
			}
		}
// "clip" timer
		if (_clipTimer > 0)
		{
			_clipTimer -= dt;
			if (_clipTimer <= 0)
			{
				var c = getOutput("clip");
				if (c != null) c.value = false;
			}
		}
	}
// =========================================================================
// INPUT READING
// =========================================================================
	/**
	* Reads input contact values and updates atom parameters.
	* Called every frame in update(dt).
	*/
	private function readInputs():Void
	{
		var modeC    = getInput("mode");
		var quantumC = getInput("quantum");
		var gainC    = getInput("gain");
		var channelC = getInput("channel");
		var rateC    = getInput("rate");
		var bufSizeC = getInput("bufferSize");
// Read mode (Mic / Loopback).
		if (modeC    != null && modeC.value    != null) _mode    = Std.int(modeC.value);
// Read gain.
		if (gainC    != null && gainC.value    != null) _gain    = gainC.value;
// Read channel.
		if (channelC != null && channelC.value != null) _channel = Std.int(channelC.value);
// Read sample rate (index in SAMPLE_RATES array).
		if (rateC != null && rateC.value != null)
		{
			var idx = Std.int(rateC.value);
			if (idx >= 0 && idx < SAMPLE_RATES.length) _sampleRateIdx = idx;
		}
// Read quantization step (with range check).
		if (quantumC != null && quantumC.value != null)
		{
			var q:Float = quantumC.value;
			if (q >= MIN_QUANTUM && q <= MAX_QUANTUM) _quantum = q;
		}
// Read buffer size (with range check 64..512).
		if (bufSizeC != null && bufSizeC.value != null)
		{
			var bs = Std.int(bufSizeC.value);
			if (bs >= 64 && bs <= 512 && bs != _bufferSize) _bufferSize = bs;
		}
	}
// =========================================================================
// UTILITY
// =========================================================================
	/**
	* Updates "device" output contact with device name.
	*
	* @param name Device name (e.g., "Loopback @48000Hz").
	*/
	private function setDeviceNameOutput(name:String):Void
	{
		var c = getOutput("device");
		if (c != null) c.value = name;
	}
	/**
	* Restarts audio device.
	* Useful when changing parameters requiring re-initialization
	* (e.g., sample rate or mode change).
	*/
	public function restart():Void
	{
		closeDevice();
		_isFirstSample = true;
		_lastQuantum   = 0.0;
		_hasPending    = false;
		readInputs();
		openDevice();
	}
}
#end
