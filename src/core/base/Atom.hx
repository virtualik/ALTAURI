package core.base;
import core.logic.EventType;
import core.logic.Impulsys;
import core.logic.TickGenerator;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import system.managers.Driver;

/**
* ATOM BASE CLASS v7.2 (DisplayName Support + Fault Isolation Latch)
* Fundamental unit of logic. Independent of rendering engine.
*
* An Atom is the smallest executable unit in the system.
* It holds inputs, outputs, and a processing function.
*
* Key Responsibilities:
* - Manages contact connections (inputs/outputs)
* - Schedules calculations via TickGenerator
* - Supports Logic Mode (digital) and Analog Mode (immediate)
* - Implements Driver interface for active components
* - v7.1: Supports user-friendly displayName with uniqueness
* - v7.2: Fault isolation latch — markAsFaulted()/clearFault() +
*   ATOM_FAULTED/ATOM_FAULT_CLEARED events; exception containment in
*   _calculate(); runtime-only fault state (never serialized)
*/
class Atom implements IDisposable implements Driver
{
// ========================================================================
// PROPERTIES
// ========================================================================
	public var id(get, never):String;
	private function get_id():String return _id;
	private var _id:String;

	public var type(default, null):String;

	public var name(default, null):String;

	/**
	* v7.1: User-friendly display name (editable, unique within Assembly).
	* Used in UI for node identification.
	* Default value: type (e.g., "Button", "NETRadioPlayer")
	*/
	public var displayName(get, set):String;
	private var _displayName:String;

	// ═══════════════════════════════════════════════════════════════════════
	// v3.9: Visual mode for NodeView (LIGHT, MEDIUM, HEAVY)
	// Persisted in JSON so it survives app restart.
	// ═══════════════════════════════════════════════════════════════════════
	private var _visualMode:String = "LIGHT"; // Default

	public function getVisualMode():String return _visualMode;
	public function setVisualModeState(mode:String):Void 
	{
		_visualMode = mode;
	}

	private function get_displayName():String
	{
		return _displayName != null ? _displayName : type;
	}

	private function set_displayName(value:String):String
	{
		_displayName = value;
		return value;
	}

	/**
	* Determines the timing model for this atom.
	* ┌────────────────┬────────────────────────────────────────────────┐
	* │ Value          │ Behavior                                       │
	* ├────────────────┼────────────────────────────────────────────────┤
	* │ true (Digital) │ Output changes are scheduled for the NEXT tick │
	* │ false (Analog) │ Output changes happen IMMEDIATELY              │
	* └────────────────┴────────────────────────────────────────────────┘
	*/
	public var isLogic(get, set):Bool;
	private var _isLogic:Bool = false;
	private function get_isLogic():Bool return _isLogic;
	private function set_isLogic(value:Bool):Bool
	{
		_isLogic = value;
		return _isLogic;
	}

	private var _inputs:Array<Contact>;
	private var _outputs:Array<Contact>;
	private var _process:Array<Dynamic> -> Array<Dynamic>;
	private var _inputCache:Array<Dynamic>;
	private var _isScheduled:Bool = false;
	private var _isActive:Bool = false;

	/**
	* v7.0: @:volatile forces the processor to always read from RAM,
	* not from the thread register cache.
	*
	* This is critical for drivers (e.g., MiniAudioAtom).
	* The OS audio thread checks _isDisposed in callback. Without @:volatile,
	* the C++ compiler might cache the value in the audio thread's register,
	* and after dispose() is called in the main thread, the audio thread
	* will continue execution with a "stale" (false) flag value.
	*/
	@:volatile private var _isDisposed:Bool = false;
	private var _hasCalculatedOnce:Bool = false;

	// ═══════════════════════════════════════════════════════════════════════
	// v7.2: FAULT ISOLATION LATCH (FAULT_ISOLATION WP).
	// A latched atom is NOT broken out of the running graph — it is made
	// VISIBLE: one ATOM_FAULTED event + one ATOM-FAULT black-box line per
	// fault (no per-frame spam), a red frame on its NodeView, and an
	// automatic unlatch on the first healthy pass (successful _calculate,
	// restart, successful resource activation). Fault state is RUNTIME-ONLY
	// — getPersistentState() never serializes it.
	// ═══════════════════════════════════════════════════════════════════════
	private var _isFaulted:Bool = false;
	private var _faultReason:String = null;
	private var _faultMessage:String = null;

	/** True while this atom holds a fault latch (red frame in editor). */
	public var isFaulted(get, never):Bool;
	private function get_isFaulted():Bool return _isFaulted;

	/** Machine-readable fault code of the current latch (null if healthy). */
	public var faultReason(get, never):String;
	private function get_faultReason():String return _faultReason;

	/** Human-readable fault text of the current latch (null if healthy). */
	public var faultMessage(get, never):String;
	private function get_faultMessage():String return _faultMessage;

	/**
	* Latch a fault. Idempotent-quiet: the FIRST fault emits
	* ATOM_FAULTED {atomId, reason, message} and writes one ATOM-FAULT
	* line to the black box; repeated faults while latched are silent
	* (the old failure mode — a fault re-logged every frame/event — is
	* exactly what this latch removes).
	* @return true if the latch was set by THIS call.
	*/
	public function markAsFaulted(reason:String, message:String):Bool
	{
		if (_isDisposed) return false;
		if (_isFaulted) return false;
		_isFaulted = true;
		_faultReason = (reason != null) ? reason : "UNKNOWN";
		_faultMessage = (message != null) ? Std.string(message) : "";
		trace('Atom ${id}: FAULT [${_faultReason}] ${_faultMessage}');
		utils.Trap.log("ATOM-FAULT", id + " [" + _faultReason + "] " + _faultMessage);
		Impulsys.quickEmit(EventType.ATOM_FAULTED, {
			atomId: id, reason: _faultReason, message: _faultMessage
		});
		return true;
	}

	/**
	* Unlatch the fault (manual retry succeeded / resource re-activated /
	* healthy calculation passed). Emits ATOM_FAULT_CLEARED {atomId}
	* exactly once per held latch.
	* @return true if a latch was actually cleared by THIS call.
	*/
	public function clearFault():Bool
	{
		if (!_isFaulted) return false;
		_isFaulted = false;
		_faultReason = null;
		_faultMessage = null;
		utils.Trap.log("ATOM-FAULT", id + " cleared");
		Impulsys.quickEmit(EventType.ATOM_FAULT_CLEARED, { atomId: id });
		return true;
	}

	/**
	* v7.2: RESOURCE CONTRACT — override to declare an exclusive resource
	* key (e.g. ComPortAtom -> "serial:COM3"). Null (default) = this atom
	* claims no exclusive resource; the grab is enforced by
	* system.managers.ResourceRegistry at the atom's REAL activation
	* point (openDevice/openFile/...), not at registration time.
	*/
	public function getResourceKey():String
	{
		return null;
	}

// ========================================================================
// INITIALIZATION v7.0
// ========================================================================
	public var isInitializing(get, set):Bool;
	private var _isInitializing:Bool = false;
	private function get_isInitializing():Bool return _isInitializing;
	private function set_isInitializing(value:Bool):Bool
	{
		_isInitializing = value;
		return _isInitializing;
	}

	/**
	* Create a new Atom instance.
	*
	* @param inputs      Array of input contacts
	* @param outputs     Array of output contacts
	* @param processFunc Processing function (inputs -> outputs)
	* @param id          Unique instance ID
	* @param type        Atom type name
	* @param isActive    If true, registers with DriverManager for updates
	* @param displayName Optional user-friendly name (default: type)
	*/
	public function new(
		inputs:Array<Contact>,
		outputs:Array<Contact>,
		processFunc:Array<Dynamic> -> Array<Dynamic>,
		?id:String,
		?type:String = "Generic",
		?isActive:Bool = false,
		?displayName:String = null
	)
	{
		this._id = (id != null) ? id : "atom_" + Std.random(100000);
		this.type = type;
		this.name = type;
		this._displayName = (displayName != null) ? displayName : type;
		this._isActive = isActive;
		this._inputs = (inputs != null) ? inputs : [];
		this._outputs = (outputs != null) ? outputs : [];
		this._process = processFunc;
		_inputCache = [];
		for (i in 0..._inputs.length) _inputCache.push(null);
		_bind();
		var tg = TickGenerator.getInstance();
		var isAssemblyWithInternal = Std.isOfType(this, Assembly) &&
									 cast(this, Assembly).blueprint != null &&
									 cast(this, Assembly).blueprint.internalAtoms != null &&
									 cast(this, Assembly).blueprint.internalAtoms.length > 0;
		// Schedule initial calculation if not an assembly with internal atoms
		// and TickGenerator is not suspended.
		if (_process != null && !isAssemblyWithInternal && !tg.isSuspended())
		{
			_isScheduled = true;
			TickGenerator.getInstance().scheduleNextTick(function()
			{
				if (!_isDisposed) _calculate();
			});
		}
		// Register as active driver if flag is set
		if (_isActive)
		{
			DriverManager.getInstance().register(this);
		}
	}

	/**
	* Bind contacts to this atom as owner.
	*/
	private function _bind():Void
	{
		for (input in _inputs)
		{
			if (input != null) input.owner = this;
		}
		for (output in _outputs)
		{
			if (output != null) output.owner = this;
		}
	}

// ========================================================================
// LIFECYCLE
// ========================================================================
	public function init():Void { }

	/**
	* Update loop for active drivers.
	* Called by DriverManager every frame.
	*/
	public function update(dt:Float):Void
	{
		_onUpdate(dt);
	}

	private function _onUpdate(dt:Float):Void { }

	/**
	* Called when a contact value changes.
	* Schedules calculation if not already scheduled.
	*/
	public function onContactChanged(c:Contact):Void
	{
		if (_isScheduled || _isDisposed) return;
		if (isInitializing) return;
		// Ignore changes from our own outputs (prevents feedback loops)
		if (c.type == OUTPUT && c.owner == this) return;
		if (_process != null)
		{
			_isScheduled = true;
			TickGenerator.getInstance().schedule(_calculate, NORMAL);
		}
	}

	/**
	* Main calculation step.
	* Reads inputs, runs process function, writes outputs.
	*/
	private function _calculate():Void
	{
		_isScheduled = false;
		_hasCalculatedOnce = true;
		if (_isDisposed || _process == null || _inputs == null) return;
		// Cache input values
		for (i in 0..._inputs.length) _inputCache[i] = _inputs[i].value;
		// Process — v7.2 FAULT ISOLATION: a throwing _process() latches the
		// fault (ONE event + ONE black-box line; repeated faults stay silent)
		// and aborts THIS calculation without writing garbage outputs. The
		// atom stays in the graph: the next user-driven value change re-runs
		// _calculate, and a healthy pass clears the latch below —
		// reconfiguration IS the retry (no autopilot).
		var results:Array<Dynamic>;
		try
		{
			results = _process(_inputCache);
		}
		catch (e:Dynamic)
		{
			markAsFaulted("EXCEPTION", Std.string(e));
			return;
		}
		// Healthy pass — unlatch (no-op when not faulted).
		if (_isFaulted) clearFault();
		// Write outputs
		if (results != null && results.length == _outputs.length)
		{
			if (isLogic)
			{
				// Logic Mode: Schedule output update for next tick (unit delay)
				var outs = _outputs;
				var vals = results;
				TickGenerator.getInstance().scheduleNextTick(function()
				{
					if (_isDisposed) return;
					for (i in 0...outs.length)
					{
						if (outs[i] != null) outs[i].value = vals[i];
					}
				});
			}
			else
			{
				// Analog Mode: Immediate update
				for (i in 0..._outputs.length)
				{
					if (_outputs[i] != null) _outputs[i].value = results[i];
				}
			}
		}
	}

	/**
	* Force calculation immediately (bypass scheduler).
	* Use with caution.
	*/
	public function forceCalculate():Void
	{
		if (_isDisposed || _process == null || _inputs == null) return;
		_calculate();
	}

// ========================================================================
// STATE SERIALIZATION v7.1
// ========================================================================
	/**
	* Save state for persistence.
	* v7.1: Includes displayName
	* v3.9 FIX: visualMode removed — now stored in Blueprint.AtomDef, not atom state
	*/
	public function getPersistentState():Dynamic
	{
		var hasLogic = _isLogic;
		var hasDisplayName = (_displayName != null && _displayName != type);
		
		if (hasLogic || hasDisplayName)
		{
			var state:Dynamic = {};
			if (hasLogic) state.isLogic = _isLogic;
			if (hasDisplayName) state.displayName = _displayName;
			return state;
		}
		return null;
	}
	
	/**
	* Restore state from saved data.
	* v7.1: Restores displayName
	* v3.9 FIX: visualMode removed — now restored from Blueprint.AtomDef via createViewForAtom()
	*/
	public function restoreState(state:Dynamic):Void
	{
		if (state == null) return;
		
		if (Reflect.hasField(state, "isLogic"))
		{
			this.isLogic = state.isLogic;
		}
		
		if (Reflect.hasField(state, "displayName"))
		{
			_displayName = state.displayName;
			trace('Atom ${id}: Restored displayName = "${_displayName}"');
		}
	}

// ========================================================================
// CONTACT ACCESS
// ========================================================================
	public function getInputs():Array<Contact> return _inputs;
	public function getOutputs():Array<Contact> return _outputs;

	public function getInput(name:String):Contact
	{
		if (_inputs == null) return null;
		for (c in _inputs) if (c != null && c.name == name) return c;
		return null;
	}

	public function getOutput(name:String):Contact
	{
		if (_outputs == null) return null;
		for (c in _outputs) if (c != null && c.name == name) return c;
		return null;
	}

	public function getInputNames():Array<String>
	{
		var names:Array<String> = [];
		for (c in _inputs) if (c != null && c.name != null) names.push(c.name);
		return names;
	}

	public function getOutputNames():Array<String>
	{
		var names:Array<String> = [];
		for (c in _outputs) if (c != null && c.name != null) names.push(c.name);
		return names;
	}

// ========================================================================
// DISPOSE
// ========================================================================
	public function dispose():Void
	{
		// v7.0: @:volatile guarantees visibility in Audio Thread
		_isDisposed = true;
		
		// v8.0: Release globally-registered displayName so the slot becomes
		// available again for future atoms. Safe to call multiple times —
		// NamingService.unregisterInstanceName() is idempotent.
		if (_displayName != null)
		{
			core.logic.NamingService.unregisterInstanceName(_displayName);
		}
		
		// v3.9: Clear visualMode (не обязательно, но чисто)
		_visualMode = null;
	
// old record:
	//	if (_isActive) DriverManager.getInstance().unregister(this.id);
	// ═══════════════════════════════════════════════════════════════════

// new record:
// v4.4: DRIVER ZOMBIE GUARD — safety net at the base class level.
// ═══════════════════════════════════════════════════════════════════
// DriverManager.unregister() intentionally does not call dispose()
// (caller-is-responsible contract). Active drivers DO unregister in
// their own dispose overrides (MiniAudioAtom), but the contract is a
// trap for future drivers: one forgotten unregister leaves a zombie
// entry that gets update(dt) called on a disposed atom every frame.
// This guard makes the base class responsible: if THIS atom was
// registered as a driver, unregister it NOW (idempotent — double
// unregister with the driver's own call is harmless: the second call
// is a no-op because the map entry is already gone).
        if (_isActive)
        {
            system.managers.DriverManager.getInstance().unregister(this.id);
        }
		
		if (_inputs != null) { for (c in _inputs) { if (c != null) c.dispose(); } }
		if (_outputs != null) { for (c in _outputs) { if (c != null) c.dispose(); } }
		_inputs = null;
		_outputs = null;
		_process = null;
		_inputCache = null;
	}
}
