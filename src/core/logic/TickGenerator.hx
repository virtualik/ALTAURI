package core.logic;
import core.types.Priority;
import haxe.Timer;
import system.managers.DriverManager;

/**
* TICK GENERATOR v1.4 (Deaf Graph Fix + Depth-Safe Suspend + Traps + Fault Visibility)
*
* The central hub for simulation control.
*
* Responsibilities:
* - Manages the fixed time-step simulation loop
* - Schedules and executes logic tasks (CRITICAL, NORMAL, BACKGROUND)
* - Provides thread-safe task queue for external threads (e.g., Audio)
* - v1.2: TOPOLOGY TRANSACTION GUARD (Reentrancy-Safe Graph Mutation Lock)
*
* Architecture:
* ┌───────────────────────────────────────────────────────────────────────┐
* │ External Threads        Main Loop (Game Loop)                         │
* │                                                                       │
* │ ┌────────────────┐      ┌──────────────────────────┐                  │
* │ │Audio Callback  │      │ onEnterFrame() {         │                  │
* │ │scheduleNextTick│─SPSC─▶ TickGenerator.update(dt);│                  │
* │ └────────────────Queue  │ }                        │                  │
* │                         │                          │                  │
* │ ┌────────────────       │ flushPendingInputs()     │                  │
* │ │UI Input (Main) │─────▶│   ↓                      │                  │
* │ │scheduleNextTick│(safe)│ performStep()            │                  │
* │ └────────────────┘thread│ ├─►DriverManager.update()│                  │
* │                         │ ├─►flushPendingInputs()  │                  │
* │                         │ ├─►process()             │                  │
* │                         │ └─►emitTick()            │                  │
* └───────────────────────────────────────────────────────────────────────┘
*
* ═══════════════════════════════════════════════════════════════════════
* v1.2 REENTRANCY-SAFE TOPOLOGY TRANSACTION GUARD
* ═══════════════════════════════════════════════════════════════════════
*
* PROBLEM:
* When structural changes occur (GroupAtoms, DeletePort, Undo/Redo),
* the reactive graph might attempt to propagate signals through
* contacts that are in the process of being disposed or rewired.
* This causes NullReference crashes, especially with active audio drivers.
*
* SOLUTION:
* lockTopology() / unlockTopology() creates an atomic transaction zone.
* - Uses a depth counter (_topologyLockDepth) to support nested commands.
* - While locked, process() is suspended.
* - Contact propagation is deferred to _deferredTopologyTasks.
* - On final unlock, deferred tasks are flushed safely, and UI is notified.
*
* ┌─────────────────────────────────────────────────────────────────────┐
* │  Transaction Lifecycle:                                             │
* │                                                                     │
* │  1. LOCK (Depth = 1)                                                │
* │     ├── process() becomes NO-OP                                     │
* │     ├── Contact.set_value() defers to _deferredTopologyTasks        │
* │     └── Graph is frozen in time                                     │
* │                                                                     │
* │  2. MUTATE (UI/Undo/Redo actions)                                   │
* │     ├── Atoms disposed, ports removed, wires rewired                │
* │     └── No signal propagation can crash the system                  │
* │                                                                     │
* │  3. UNLOCK (Depth = 0)                                              │
* │     ├── Flush _deferredTopologyTasks (safe propagation)             │
* │     ├── Impulsys.quickEmit(REDRAW_WIRES)                            │
* │     └── Resume normal process() execution                           │
* └─────────────────────────────────────────────────────────────────────┘
*
* v1.1 Changes:
* - Replaced _pendingInputs array with LockFreeQueue<Void->Void>.
*   This eliminates Data Race when calling scheduleNextTick() from
*   external threads (e.g., Audio Thread in MiniAudioAtom).
*/
// ═══════════════════════════════════════════════════════════════════════════
// v1.3 CHANGES (Deaf Graph fix — field evidence 2026-08-25 01:29:16→01:30:07)
// ═══════════════════════════════════════════════════════════════════════════
//
//  EVIDENCE: after a 3-level pop() reconstruction the whole reactive graph
//  went deaf for 51 seconds — button presses wrote values (set_value probes
//  in crash_trap.log) but NOTHING propagated: no deliveries, no COND-OUT,
//  LED frozen on its last received state. The graph revived the moment the
//  NEXT reconstruction ran a constructor → resume().
//
//  ROOT CAUSE — task loss poisons Contact._isScheduled:
//  Contact.set_value latches _isScheduled=true and hands _propagate to
//  schedule(). The latch resets ONLY when _propagate actually RUNS.
//  TickGenerator had TWO silent task-loss paths:
//    (a) process() iteration-guard trip → clearQueues() destroyed all
//        queued tasks;
//    (b) schedule() early-returned on _blockedUntilNextFrame — the task
//        was dropped BEFORE queueing.
//  Either way the latch stayed true forever → the contact never scheduled
//  again → permanently deaf (values go in, nothing comes out).
//
//  FIXES:
//   1. schedule() NEVER drops tasks — queues unconditionally.
//   2. Iteration-guard trip no longer clearQueues() — tasks are deferred
//      to the next frame via the block flag; the guard restarts at zero.
//   3. suspend()/resume() boolean → DEPTH COUNTER: nested Assembly
//      construction/dispose cascades used to cancel each other's suspend
//      state (child resume un-suspended the generator mid-parent-build;
//      an unbalanced interleaving could leave it stuck suspended forever).
//   4. TG-* trap markers: TG-LOCK/TG-UNLOCK, TG-SUSPEND/TG-RESUME (with
//      depth), TG-TRIP, TG-BLOCK, TG-CLEAR — the next hunt sees the shot.
//
//  INVARIANT (do not break): every task passed to schedule() must
//  EVENTUALLY EXECUTE — Contact._isScheduled correctness depends on it.
//
class TickGenerator
{
	private static var _instance: TickGenerator;

// =========================================================================
// CONFIGURATION
// =========================================================================
	/** Simulation frequency in Hertz. */
	public var targetHz(default, set): Int = 60;
	private function set_targetHz(value: Int): Int
	{
		targetHz = Std.int(Math.max(1, value));
		fixedDeltaTime = 1.0 / targetHz;
		return targetHz;
	}
	/** Fixed time step in seconds. */
	public var fixedDeltaTime(default, null): Float = 1.0 / 60.0;
	/** Maximum steps per frame (protection against "death spiral"). */
	public var maxStepsPerFrame: Int = 5;

// =========================================================================
// STATE
// =========================================================================
	/** Global tick counter (impulse count). */
	public var currentTick(default, null): Int = 0;
	/** Start time of current frame (for profiling). */
	public var frameStartTime(default, null): Float = 0.0;
	private var _accumulator: Float = 0.0;
	private var _isPaused: Bool = false;

// =========================================================================
// v1.2: TOPOLOGY TRANSACTION GUARD
// =========================================================================
	/**
	* Reentrancy-safe lock depth counter.
	* Allows nested commands (e.g., MacroCommand) without premature unlocking.
	*/
	private var _topologyLockDepth: Int = 0;

	/**
	* Queue for tasks deferred during topology mutation.
	* Pre-allocated to avoid GC spikes during grouping operations.
	*/
	private var _deferredTopologyTasks: Array<Void -> Void>;

// =========================================================================
// QUEUE SYSTEM
// =========================================================================
	private var _queuesWrite: Map<Priority, Array<Void -> Void>>;
	private var _queuesRead: Map<Priority, Array<Void -> Void>>;
	private var _isProcessing: Bool = false;
	// v1.3: DEPTH COUNTER (was boolean _suspended — see class changelog).
	private var _suspendDepth: Int = 0;
	#if html5
	private var _html5FallbackTimer:Dynamic = null;
	private static inline var HTML5_FALLBACK_INTERVAL:Int = 16; // ~60 FPS
	#end
	/** v1.1: Lock-free queue for cross-thread communication. */
	private var _pendingQueue: LockFreeQueue<Void -> Void>;
	private var _blockedUntilNextFrame: Bool = false;
	private var _iterationGuard: Int = 0;
	private var _maxIterationsPerTick: Int = 5000;

// =========================================================================
// LISTENERS (Tick Event)
// =========================================================================
	private var _tickListeners: Array<Void -> Void> = [];

	public static function getInstance(): TickGenerator
	{
		if (_instance == null) _instance = new TickGenerator();
		return _instance;
	}

	private function new()
	{
		_queuesWrite = new Map();
		_queuesRead = new Map();
		_queuesWrite.set(CRITICAL, []);
		_queuesWrite.set(NORMAL, []);
		_queuesWrite.set(BACKGROUND, []);
		_queuesRead.set(CRITICAL, []);
		_queuesRead.set(NORMAL, []);
		_queuesRead.set(BACKGROUND, []);

// 4096 tasks capacity - enough for aggressive audio streams
		_pendingQueue = new LockFreeQueue<Void -> Void>(4096);

// v1.2: Initialize deferred tasks queue
		_deferredTopologyTasks = [];
		#if html5
		ensureHTML5FallbackTimer();
		#end
	}

// =========================================================================
// v1.2: TOPOLOGY TRANSACTION API
// =========================================================================
	/**
	* Lock the topology graph.
	* Suspends signal propagation and task processing.
	* Safe for nested calls (uses depth counter).
	*/
	public function lockTopology(): Void
	{
		_topologyLockDepth++;
		utils.Trap.log("TG-LOCK", "depth=" + _topologyLockDepth);
		if (_topologyLockDepth == 1)
		{
// First lock: clear deferred queue to prepare for new transaction
			_deferredTopologyTasks.resize(0);
		}
	}

	/**
	* Unlock the topology graph.
	* When depth reaches 0, flushes deferred tasks and notifies UI.
	*/
	public function unlockTopology(): Void
	{
		if (_topologyLockDepth <= 0) return;
		_topologyLockDepth--;

		if (_topologyLockDepth == 0)
		{
// Final unlock: safe to resume graph execution
			utils.Trap.log("TG-UNLOCK", "depth=0 — flushing deferred tasks");
			var tasksToFlush = _deferredTopologyTasks.copy();
			_deferredTopologyTasks.resize(0);

// Execute deferred propagations safely
			for (task in tasksToFlush)
			{
				try { task(); }
				catch (e: Dynamic)
				{
					// v1.4 FAULT ISOLATION: deferred propagation tasks used to die in
					// TOTAL silence here — the "deaf graph" failure mode (signals
					// vanished between lock/unlock with zero evidence). One black-box
					// line per failure now; the swallow itself stays (a dead deferred
					// target is legal during topology mutations).
					utils.Trap.log("TG-DEFERRED-EX", "deferred topology task threw: " + Std.string(e));
				}
			}

// Notify UI to redraw wires after structural changes
			Impulsys.quickEmit(EventType.REDRAW_WIRES);

// Resume normal processing if there are pending tasks
			if (!_isProcessing && hasPendingTasks()) process();
		}
	}

	/**
	* Check if the topology is currently locked.
	* Used by Contact to decide whether to defer propagation.
	*/
	public function isTopologyLocked(): Bool
	{
		return _topologyLockDepth > 0;
	}

	/**
	* Defer a task until the topology is unlocked.
	* If already unlocked, executes immediately.
	*/
	public function deferTopologyTask(task: Void -> Void): Void
	{
		if (_topologyLockDepth > 0)
		{
			_deferredTopologyTasks.push(task);
		}
		else
		{
			task();
		}
	}

// =========================================================================
// MAIN LOOP
// =========================================================================
	/**
	* Main update method. Called from Main.onMainLoop.
	*
	* @param realDt Real delta time in seconds
	*/
	public function update(realDt: Float): Void
	{
		if (_isPaused) return;
		frameStartTime = Timer.stamp();

// 1. Accumulate time
		_accumulator += realDt;

// 2. Protection against "Death Spiral"
// If accumulator grows too large (lag), clamp it to prevent freezing
		var maxAccum: Float = fixedDeltaTime * maxStepsPerFrame;
		if (_accumulator > maxAccum)
		{
			_accumulator = maxAccum;
		}

// 3. Perform simulation steps
		var stepsPerformed: Int = 0;
		while (_accumulator >= fixedDeltaTime)
		{
			performStep(fixedDeltaTime);
			_accumulator -= fixedDeltaTime;
			stepsPerformed++;
			if (stepsPerformed >= maxStepsPerFrame) break;
		}
	}

	/**
	* One discrete simulation step.
	*
	* Order of execution is critical:
	* 1. Drivers (Analog/Generators) produce data FIRST
	* 2. Logic (Digital) propagates data SECOND
	*/
	private function performStep(dt: Float): Void
	{
// 1. Advance global tick counter (Timebase)
		currentTick++;

// 2. Update DRIVERS (Analog/Generators) - FIRST!
// Generators create data in their output contacts
		DriverManager.getInstance().update(dt);

// 3. Run LOGIC TICK (Digital) - SECOND!
// SignalQueue propagates data from generators to oscilloscopes
		tick();
	}

// =========================================================================
// TICK LOGIC
// =========================================================================
	/**
	* SIMULATION TICK
	*
	* Processes pending tasks and notifies listeners.
	*/
	public function tick(): Void
	{
// Reset new frame locks
		if (_blockedUntilNextFrame)
		{
			utils.Trap.log("TG-BLOCK", "block flag reset at tick");
		}
		_blockedUntilNextFrame = false;

// Inject pending inputs (buttons, inputs, audio data)
		flushPendingInputs();

// Launch signal propagation
		process();

// Notify listeners about tick completion (for UI sync, etc.)
		emitTick();
	}

	/**
	* Subscribe to tick event.
	*/
	public function addTickListener(listener: Void -> Void): Void
	{
		if (listener != null && _tickListeners.indexOf(listener) == -1)
		{
			_tickListeners.push(listener);
		}
	}

	public function removeTickListener(listener: Void -> Void): Void
	{
		_tickListeners.remove(listener);
	}

	private function emitTick(): Void
	{
// Copy array for safe iteration (listener may unsubscribe)
		var listeners = _tickListeners.copy();
		for (l in listeners)
		{
			if (l != null) l();
		}
	}

// =========================================================================
// SCHEDULING API
// =========================================================================
	/**
	* Schedule a task for immediate execution within current or next tick.
	*
	* @param task     Task to execute
	* @param priority Task priority (CRITICAL, NORMAL, BACKGROUND)
	*/
	public function schedule(task: Void -> Void, priority: Priority = NORMAL): Void
	{
// v1.3: NEVER drop a task. The old early-return on _blockedUntilNextFrame
// discarded the task while Contact._isScheduled stayed latched true — the
// contact went permanently deaf (field-proven, 2026-08-25). Queue
// unconditionally; process() is entry-guarded by the block flag and will
// run the task on the next frame.
		var queue = _queuesWrite.get(priority);
		if (queue != null)
		{
			queue.push(task);
		}

// If not processing and not suspended, run immediately
// (usually called from update -> tick -> process)
		if (!_isProcessing && _suspendDepth == 0 && !_blockedUntilNextFrame)
		{
			process();
		}
	}

	/**
	* Schedule a task for execution at the START of the next tick.
	*
	* v1.1: THREAD-SAFE. Can be called from Audio Thread.
	*
	* @param task Task to execute
	*/
	public function scheduleNextTick(task: Void -> Void): Void
	{
		if (task != null)
		{
			if (!_pendingQueue.push(task))
			{
				trace('TickGenerator: pending queue overflow! Task dropped.');
			}
		}
	}

	public function suspend(): Void
	{
		_suspendDepth++;
		utils.Trap.log("TG-SUSPEND", "depth=" + _suspendDepth);
	}

	public function resume(): Void
	{
// v1.3: depth-aware — only the OUTERMOST resume re-enables processing.
// A spurious resume() at depth 0 (unbalanced pair) is now VISIBLE via
// the TG-RESUME trap and still safely flushes pending work.
		if (_suspendDepth > 0) _suspendDepth--;
		utils.Trap.log("TG-RESUME", "depth=" + _suspendDepth);
		if (_suspendDepth > 0) return;
		_blockedUntilNextFrame = false;
		flushPendingInputs();
		if (!_isProcessing && hasPendingTasks()) process();
	}
	
	#if html5
	/**
	 * HTML5 fallback timer.
	 * Browsers can throttle requestAnimationFrame, causing ENTER_FRAME
	 * to stop firing. This timer ensures update() is called regularly.
	 */
	private function ensureHTML5FallbackTimer():Void {
		#if html5
		if (_html5FallbackTimer == null) {
			_html5FallbackTimer = js.Browser.window.setInterval(function() {
				// Only update if not paused
				if (!_isPaused) {
					update(1.0 / 60.0);
				}
			}, HTML5_FALLBACK_INTERVAL);
		}
		#end
	}
	#end

	public function isSuspended(): Bool return _suspendDepth > 0;

	public function hasPendingTasks(): Bool
	{
		for (q in _queuesWrite) if (q != null && q.length > 0) return true;
		for (q in _queuesRead) if (q != null && q.length > 0) return true;
// v1.1: Check LockFreeQueue
		var test = _pendingQueue.pop();
		if (test != null)
		{
// If something exists, put it back (via push, safe from main thread)
// Ideally SPSC needs peek(), but this works for overflow check
			_queuesWrite.get(NORMAL).push(test);
			return true;
		}
		return false;
	}

	/**
	* Flush tasks from lock-free queue to main queue.
	* Called at start of each tick.
	*/
	public function flushPendingInputs(): Void
	{
		var queue = _queuesWrite.get(NORMAL);
		if (queue == null) return;

// v1.1: Extract tasks from lock-free queue without allocations
		var task = _pendingQueue.pop();
		while (task != null)
		{
			queue.push(task);
			task = _pendingQueue.pop();
		}
	}

// =========================================================================
// CORE EXECUTION
// =========================================================================
	private function process(): Void
	{
// v1.2: TOPOLOGY GUARD - Freeze graph execution during mutations
		if (_suspendDepth > 0 || _blockedUntilNextFrame || _topologyLockDepth > 0) return;
		if (_isProcessing) return;

		_isProcessing = true;
		_iterationGuard = 0;

		do {
// Swap buffers
			var temp = _queuesRead;
			_queuesRead = _queuesWrite;
			_queuesWrite = temp;

// Clear Write buffers
			var clearQ = _queuesWrite.get(CRITICAL); if (clearQ != null) clearQ.resize(0);
			clearQ = _queuesWrite.get(NORMAL); if (clearQ != null) clearQ.resize(0);
			clearQ = _queuesWrite.get(BACKGROUND); if (clearQ != null) clearQ.resize(0);

// Execute tasks in priority order
			var order: Array<Priority> = [CRITICAL, NORMAL, BACKGROUND];
			for (p in order)
			{
				var q = _queuesRead.get(p);
				if (q != null && q.length > 0)
				{
					for (i in 0...q.length)
					{
						_iterationGuard++;
						if (_iterationGuard > _maxIterationsPerTick)
						{
							_blockedUntilNextFrame = true;
// v1.3: DO NOT clearQueues() here. Destroying queued tasks left their
// contacts' Contact._isScheduled one-shot latches stuck true — those
// contacts went PERMANENTLY deaf (values written, never propagated;
// field-proven 2026-08-25: 51 s of silence, LED frozen mid-state).
// Tasks now survive; the block flag defers them to the next frame,
// where the iteration guard restarts from zero.
							utils.Trap.log("TG-TRIP", "iteration guard (>5000) — deferring queued tasks to next frame");
							_isProcessing = false;
							return;
						}

						var task = q[i];
						if (task != null)
						{
							try { task(); }
							catch (e: Dynamic)
							{
								// v1.4 FAULT ISOLATION: mirror the task exception into the black
								// box (the stdout trace is lost in the "lime run" pipe). Bare
								// task closures carry no owner — owner-scoped faults are latched
								// in Atom._calculate / Contact.set_value instead.
								trace('TickGenerator: Error in task: $e');
								utils.Trap.log("TG-TASK-EX", Std.string(e));
							}
						}
					}
					q.resize(0);
				}
			}

// Hard timeout protection
			if (haxe.Timer.stamp() - frameStartTime > 0.1) break;
		}
		while (hasPendingTasks() && !_blockedUntilNextFrame);

		_isProcessing = false;
	}

	private function clearQueues(): Void
	{
		for (q in _queuesWrite) if (q != null) q.resize(0);
		for (q in _queuesRead) if (q != null) q.resize(0);
	}

	public function clear(): Void
	{
		clearQueues();
		_isProcessing = false;
		_suspendDepth = 0;
		utils.Trap.log("TG-CLEAR", "state wiped (project reload boundary)");
		_blockedUntilNextFrame = false;
		_topologyLockDepth = 0;
		_deferredTopologyTasks.resize(0);
	}

	public static function reset():Void {
		if (_instance != null) {
			#if html5
			if (_instance._html5FallbackTimer != null) {
				js.Browser.window.clearInterval(_instance._html5FallbackTimer);
				_instance._html5FallbackTimer = null;
			}
			#end
			_instance.clear();
			if (_instance._pendingQueue != null) _instance._pendingQueue.dispose();
			_instance = null;
		}
	}

// =========================================================================
// PAUSE / CONTROL
// =========================================================================
	public function pause(): Void
	{
		_isPaused = true;
	}

	public function resumeSimulation(): Void
	{
		_isPaused = false;
		_accumulator = 0.0;
	}
}
