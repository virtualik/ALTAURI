package core.base;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ConnectionPoint; // Импортируем тип из Blueprint
import core.base.Contact;
import core.base.IDisposable;
import core.types.ContactType;
import utils.UID;
import library.AtomRegistry;
import system.managers.DriverManager;
import core.logic.TickGenerator;
import core.logic.Impulsys;
import core.logic.EventType;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     ASSEMBLY v1.2 (Signal Flow Fix)                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Universal base class for ALL nodes in the system.                        ║
* ║                                                                           ║
* ║  An Assembly is a composite Atom that can contain internal atoms          ║
* ║  and expose them through gateway ports (inputs/outputs).                  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        KEY RESPONSIBILITIES                               ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  - Manages internal atom instances                                        ║
* ║  - Routes signals between internal atoms and external ports               ║
* ║  - Supports Logic Mode (digital, tick-delayed) and Analog Mode (immediate)║
* ║  - Handles hot-start initialization without signal oscillation            ║
* ║  - v1.1: Provides atom name uniqueness checking within scope              ║
* ║  - v1.2: FIXED signal flow through Assembly ports                         ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v1.2 CHANGES (Signal Flow Fix)                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  PROBLEM:                                                           │  ║
* ║  │  Signal doesn't pass through Assembly:                              │  ║
* ║  │  PushButton → Assembly.IN → Assembly.OUT → LED                      │  ║
* ║  │                                                                     │  ║
* ║  │  Root cause: Internal atom (Button.out) is NOT linked to port.internal│  ║
* ║  │  for OUTPUT ports. Connection exists between port.internal and      │  ║
* ║  │  LED.in, but Button.out → port.internal link is missing.            │  ║
* ║  │                                                                     │  ║
* ║  │  SOLUTION:                                                          │  ║
* ║  │  Added _ensureInternalAtomConnectedToPort() method that creates     │  ║
* ║  │  explicit link between internal atom and port.internal for OUTPUT   │  ║
* ║  │  ports.                                                             │  ║
* ║  │                                                                     │  ║
* ║  │  Flow after fix:                                                    │  ║
* ║  │  ┌──────────────────────────────────────────────────────────────┐   │  ║
* ║  │  │  Button.out ──link──► port.internal ──subscribe──► callback  │   │  ║
* ║  │  │                                    │                         │   │  ║
* ║  │  │                                    ▼                         │   │  ║
* ║  │  │                              port.external ──link──► LED.in  │   │  ║
* ║  │  └──────────────────────────────────────────────────────────────┘   │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class Assembly extends Atom
{
    // ========================================================================
    // CONFIGURATION
    // ========================================================================
    /** Maximum number of input ports allowed. */
    public static inline var MAX_INPUT_PORTS:Int = 20;
    /** Maximum number of output ports allowed. */
    public static inline var MAX_OUTPUT_PORTS:Int = 20;

    // ========================================================================
    // PROPERTIES
    // ========================================================================
    /** Blueprint definition for this assembly. */
    public var blueprint:Blueprint;
    
    /** Map of port name to ConductorPort instance. */
    public var ports(default, null):Map<String, ConductorPort>;
    
    /** Map of runtime ID to internal atom instance. */
    public var internalAtoms(default, null):Map<String, Dynamic>;
    
    /** Getter for external input contacts (convenience). */
    public var inputs(get, null):Map<String, Contact>;
    
    /** Getter for external output contacts (convenience). */
    public var outputs(get, null):Map<String, Contact>;
    
    /** Map from template ID (Blueprint) to runtime ID (instance). */
    private var _idMap:Map<String, String>;
    
    /** Public getter for ID map (read-only). */
    public var idMap(get, never):Map<String, String>;
    private function get_idMap():Map<String, String> return _idMap;

    /**
    * Get template ID from runtime ID.
    * Used to resolve Blueprint definitions from live instances.
    */
    public function getTemplateId(runtimeId:String):String
    {
        for (templateId => rId in _idMap)
        {
            if (rId == runtimeId) return templateId;
        }
        return runtimeId;
    }

    private function get_inputs():Map<String, Contact>
    {
        var map = new Map<String, Contact>();
        for (p in ports)
        {
            if (p != null && p.type != null && p.type == INPUT)
            {
                map.set(p.name, p.external);
            }
        }
        return map;
    }

    private function get_outputs():Map<String, Contact>
    {
        var map = new Map<String, Contact>();
        for (p in ports)
        {
            if (p != null && p.type != null && p.type == OUTPUT)
            {
                map.set(p.name, p.external);
            }
        }
        return map;
    }

    // ========================================================================
    // LOGIC MODE SWITCH
    // ========================================================================
    /** Map of port name to callback function for logic mode. */
    private var _portCallbacks:Map<String, Dynamic -> Void>;

    override private function set_isLogic(value:Bool):Bool
    {
        if (_isLogic != value)
        {
            _isLogic = value;
            _updatePortLinks();
        }
        return _isLogic;
    }

    // ========================================================================
    // QUARANTINE SYSTEM
    // ========================================================================
    /** Reason for quarantine (if any). */
    private var _quarantineReason:String = null;
    /** Is this assembly in quarantine state? */
    private var _isInQuarantine:Bool = false;

    /**
    * Put this assembly into quarantine.
    *
    * Quarantine isolates the assembly:
    * - Unlinks all port connections
    * - Unsubscribes all port callbacks
    * - Emits ATOM_DELETED event
    *
    * Used when assembly is corrupted or needs to be safely removed.
    */
    public function quarantine(reason:String):Void
    {
        if (_isInQuarantine) return;
        _isInQuarantine = true;
        _quarantineReason = reason;
        trace('🚨 ASSEMBLY QUARANTINE: ${this.id} - ${reason}');
        
        // Unlink all port connections
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null)
            {
                if (port.external.hasLink(port.internal))
                {
                    port.external.unlink(port.internal);
                }
                if (port.internal.hasLink(port.external))
                {
                    port.internal.unlink(port.external);
                }
            }
        }
        
        // Unsubscribe all callbacks
        for (name in _portCallbacks.keys())
        {
            var port = ports.get(name);
            if (port != null)
            {
                port.internal.unsubscribe(_portCallbacks.get(name));
            }
        }
        _portCallbacks.clear();
        
        // Notify system
        Impulsys.quickEmit(EventType.ATOM_DELETED, {
            assemblyId: this.id,
            id: this.id,
            reason: reason
        });
    }

    public function isInQuarantine():Bool return _isInQuarantine;
    public function getQuarantineReason():String return _quarantineReason;

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    /**
    * Create a new Assembly instance.
    *
    * @param id        Runtime instance ID
    * @param blueprint Blueprint definition
    */
    public function new(id:String, blueprint:Blueprint)
    {
        this.blueprint = blueprint;
        this.ports = new Map();
        this.internalAtoms = new Map();
        _idMap = new Map();
        _portCallbacks = new Map();
        
        // Set initialization flag FIRST to prevent premature signal propagation
        isInitializing = true;
        
        // Create gateway ports from blueprint
        _createInterface();
        
        // Collect external contacts for parent Atom constructor
        var inputsArr:Array<Contact> = [];
        var outputsArr:Array<Contact> = [];
        var ordered = _getOrderedPortDefs();
        for (pinDef in ordered)
        {
            var p = ports.get(pinDef.name);
            if (p != null)
            {
                if (p.type != null && p.type == INPUT) inputsArr.push(p.external);
                else if (p.type != null) outputsArr.push(p.external);
            }
        }
        
        var typeName = blueprint != null ? blueprint.name : "Assembly";
        super(inputsArr, outputsArr, blueprint.logic, id, typeName, false);
        
        // Force logic mode if assembly has internal atoms
        if (blueprint != null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            if (!_isLogic)
            {
                _isLogic = true;
            }
        }
        
        // Initialize internal structure
        if (blueprint.logic == null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            // Suspend tick generator during initialization
            TickGenerator.getInstance().suspend();
            try
            {
                _createInternalInstances();
                _createInternalConnections();
                _initializeLogicState();
                _updatePortLinks();
            }
            catch (e:Dynamic)
            {
                trace('ERROR during Assembly($id) initialization: $e');
                trace('  Stack: ${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}');
            }
            
            // Unfreeze this assembly (internal atoms remain frozen until _processPendingSignals)
            isInitializing = false;
            TickGenerator.getInstance().resume();
            _processPendingSignals();
        }
        else
        {
            isInitializing = false;
        }
    }

    // ========================================================================
    // NAME UNIQUENESS API (v1.1)
    // ========================================================================
    /**
    * Check if any internal atom has the specified displayName.
    *
    * Used by NodeView inline editor to validate rename operations.
    * Iterates through all internal atoms and compares their displayName
    * field (from Atom.hx v7.1).
    *
    * @param name       The displayName to check for uniqueness
    * @param excludeId  Optional atom ID to exclude from check
    *                   (used when renaming - atom shouldn't conflict with itself)
    * @return true if name is already taken by another atom, false if available
    *
    * Example:
    * ┌─────────────────────────────────────────────────────────────────┐
    * │ // Check if "MyButton" is available                             │
    * │ if (!assembly.hasAtomWithName("MyButton")) {                    │
    * │     atom.displayName = "MyButton";  // Safe to rename           │
    * │ }                                                               │
    * │                                                                 │
    * │ // Rename with self-exclusion                                   │
    * │ if (!assembly.hasAtomWithName("NewName", atom.id)) {            │
    * │     atom.displayName = "NewName";  // Won't conflict with self  │
    * │ }                                                               │
    * └─────────────────────────────────────────────────────────────────┘
    */
    public function hasAtomWithName(name:String, ?excludeId:String):Bool
    {
        if (name == null || internalAtoms == null) return false;
        for (id in internalAtoms.keys())
        {
            // Skip excluded atom (for rename operations)
            if (excludeId != null && id == excludeId) continue;
            var atom:Atom = cast internalAtoms.get(id);
            if (atom != null && atom.displayName == name)
            {
                return true;  // Name is taken
            }
        }
        return false;  // Name is available
    }

    /**
    * Get array of all internal atom displayNames.
    *
    * Useful for:
    * - Autocomplete in UI
    * - Debugging and logging
    * - Building lists of available atoms
    * - Validating against reserved names
    *
    * @return Array of displayName strings (may contain duplicates if not validated)
    *
    * Example:
    * ┌─────────────────────────────────────────────────────────────────┐
    * │ var names = assembly.getAllAtomNames();                         │
    * │ // ["Button_1", "LED_2", "Toggle_3", "SignalGenerator_1"]       │
    * └─────────────────────────────────────────────────────────────────┘
    */
    public function getAllAtomNames():Array<String>
    {
        var names:Array<String> = [];
        if (internalAtoms == null) return names;
        for (id in internalAtoms.keys())
        {
            var atom:Atom = cast internalAtoms.get(id);
            if (atom != null && atom.displayName != null)
            {
                names.push(atom.displayName);
            }
        }
        return names;
    }

    /**
    * Find an atom by its displayName.
    *
    * Useful for programmatic access using human-readable names
    * instead of internal IDs.
    *
    * @param name The displayName to search for
    * @return Atom instance if found, null otherwise
    *
    * Example:
    * ──────────────────────────────────────────────────────────────────┐
    * │ var button = assembly.getAtomByDisplayName("StartButton");      │
    * │ if (button != null) {                                           │
    * │     // Found it! Do something...                                │
    * │ }                                                               │
    * └─────────────────────────────────────────────────────────────────┘
    */
    public function getAtomByDisplayName(name:String):Atom
    {
        if (name == null || internalAtoms == null) return null;
        for (id in internalAtoms.keys())
        {
            var atom:Atom = cast internalAtoms.get(id);
            if (atom != null && atom.displayName == name)
            {
                return atom;
            }
        }
        return null;
    }

    /**
    * Get count of internal atoms.
    *
    * @return Number of atoms currently in this assembly
    */
    public function getAtomCount():Int
    {
        if (internalAtoms == null) return 0;
        var count:Int = 0;
        for (_ in internalAtoms.keys()) count++;
        return count;
    }

    // ========================================================================
    // LOGIC STATE INITIALIZATION
    // ========================================================================
    /**
    * Initialize logic state for all contacts and internal atoms.
    *
    * Sets default values:
    * - Inputs: true (high by default)
    * - Outputs: false (low by default)
    */
    /**
    * Initialize logic state for all contacts and internal atoms.
    *
    * v1.4 FIX: НЕ устанавливает true/false принудительно.
    * Значения приходят ТОЛЬКО от:
    * 1. defaultValue из Blueprint.PinDef
    * 2. Внешних подключенных атомов (через link)
    * 3. Внутренних атомов (через _performInitialCalculation)
    *
    * Это предотвращает перезапись String/Int значений булевыми.
    */
    private function _initializeLogicState():Void
    {
        // ═══════════════════════════════════════════════════════════════
        // v1.4: Устанавливаем значения ТОЛЬКО из defaultValue Blueprint
        // НЕ ставим true/false принудительно!
        // ═══════════════════════════════════════════════════════════════
        if (blueprint != null && blueprint.pins != null)
        {
            for (pinDef in blueprint.pins)
            {
                if (pinDef == null || pinDef.name == null) continue;
                
                var port = ports.get(pinDef.name);
                if (port == null) continue;
                
                // Устанавливаем defaultValue ТОЛЬКО если значение ещё null
                // и defaultValue определён в Blueprint
                if (pinDef.defaultValue != null)
                {
                    if (port.external != null && port.external.value == null)
                    {
                        port.external.value = pinDef.defaultValue;
                    }
                    if (port.internal != null && port.internal.value == null)
                    {
                        port.internal.value = pinDef.defaultValue;
                    }
                }
            }
        }
        
        // Recursively initialize nested assemblies
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                if (Std.isOfType(atom, Assembly))
                {
                    var asm = cast(atom, Assembly);
                    asm._initializeLogicState();
                }
            }
        }
        
        // Perform initial calculation
        _performInitialCalculation();
    }

    /**
    * Perform initial calculation for all internal atoms.
    */
    private function _performInitialCalculation():Void
    {
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                if (Std.isOfType(atom, Assembly))
                {
                    var asm = cast(atom, Assembly);
                    asm._performInitialCalculation();
                }
                else
                {
                    atom._calculate();
                }
            }
        }
        _syncExternalOutputs();
    }

    /**
    * Sync internal output values to external ports.
    */
    private function _syncExternalOutputs():Void
    {
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null && port.type == OUTPUT)
            {
                if (port.internal != null && port.external != null)
                {
                    port.external.value = port.internal.value;
                }
            }
        }
    }

    /**
    * Process pending signals after initialization.
    *
    * This method:
    * 1. Forces memory atoms (Toggle, etc.) to propagate their current state
    * 2. Syncs assembly output ports
    * 3. Unfreezes all internal atoms
    * 4. v1.3 FIX: Schedules FINAL sync wave after all atoms are unfrozen
    *
    * This prevents "cold start" issues where atoms start with null values.
    */
    private function _processPendingSignals():Void
    {
        // ═══════════════════════════════════════════════════════════════
        // FIX v1.3: ПЕРЕДАЧА ВНЕШНИХ ЗНАЧЕНИЙ ВНУТРЬ СБОРКИ
        // ═══════════════════════════════════════════════════════════════
        // Внешние атомы могли передать значения ДО инициализации Assembly.
        // Принудительно синхронизируем external → internal для INPUT портов.
        // ═══════════════════════════════════════════════════════════════
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port != null && port.type == INPUT)
            {
                if (port.external != null && port.internal != null)
                {
                    // Если external имеет значение, а internal — нет или отличается
                    if (port.external.value != null && port.external.value != port.internal.value)
                    {
                        port.internal.value = port.external.value;
                        port.internal.propagateCurrentValue();
                    }
                }
            }
        }
        
        // 1. Force propagate current values from memory atoms
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                for (output in atom.getOutputs())
                {
                    if (output != null && output.value != null)
                    {
                        output.propagateCurrentValue();
                    }
                }
            }
        }
        
        // Sync assembly outputs
        _syncExternalOutputs();
        
        // 2. UNFREEZE ALL ATOMS
        for (runtimeId in internalAtoms.keys())
        {
            var obj = internalAtoms.get(runtimeId);
            if (obj != null)
            {
                var atom:Atom = cast obj;
                atom.isInitializing = false;
                if (Std.isOfType(atom, Assembly))
                {
                    cast(atom, Assembly)._processPendingSignals();
                }
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // FIX v1.3: FINAL SYNC WAVE (deferred via scheduleNextTick)
        // ═══════════════════════════════════════════════════════════════
        TickGenerator.getInstance().scheduleNextTick(function()
        {
            if (_isDisposed) return;
            
            // Повторная передача внешних значений внутрь
            for (name in ports.keys())
            {
                var port = ports.get(name);
                if (port != null && port.type == INPUT)
                {
                    if (port.external != null && port.internal != null)
                    {
                        if (port.external.value != null && port.external.value != port.internal.value)
                        {
                            port.internal.value = port.external.value;
                            port.internal.propagateCurrentValue();
                        }
                    }
                }
            }
            
            // Повторная синхронизация OUTPUT портов
            for (name in ports.keys())
            {
                var port = ports.get(name);
                if (port != null && port.type == OUTPUT)
                {
                    if (port.internal != null && port.external != null)
                    {
                        if (port.internal.value != null)
                        {
                            port.external.value = port.internal.value;
                        }
                        port.external.propagateCurrentValue();
                    }
                }
            }
            
            trace('Assembly($id): Final sync wave complete.');
        });
        
        trace('Assembly($id): Hot Start complete. Signals propagated, atoms unfrozen.');
    }

    // ========================================================================
    // PORT LINKING LOGIC
    // ========================================================================
    /**
    * Update port links based on logic mode.
    *
    * Logic Mode (isLogic = true):
    * - Input ports: external → internal (direct link)
    * - Output ports: internal subscribes → callback schedules on next tick
    *
    * Analog Mode (isLogic = false):
    * - Input ports: external → internal (direct link)
    * - Output ports: internal → external (direct link)
    */
    private function _updatePortLinks():Void
    {
        for (name in ports.keys())
        {
            var port = ports.get(name);
            if (port == null) continue;
            if (port.type == null) continue;
            if (port.external == null) continue;
            if (port.internal == null) continue;
            
            // Remove existing links
            if (port.external.hasLink(port.internal)) port.external.unlink(port.internal);
            if (port.internal.hasLink(port.external)) port.internal.unlink(port.external);
            
            // Remove existing callbacks
            if (_portCallbacks.exists(name))
            {
                port.internal.unsubscribe(_portCallbacks.get(name));
                _portCallbacks.remove(name);
            }
            
            if (this.isLogic)
			{
				if (port.type == INPUT)
				{
					// Input: direct link (всегда работает)
					port.external.link(port.internal);
				}
				else
				{
					// ═══════════════════════════════════════════════════════════════
					// FIX v1.3: Output — двойная гарантия доставки значения
					// ═══════════════════════════════════════════════════════════════
					
					// 1. Подписка на будущие изменения (через tick для unit delay)
					var callback = function(v:Dynamic)
					{
						var targetPort = port;
						TickGenerator.getInstance().scheduleNextTick(function()
						{
							if (!_isDisposed && targetPort != null && !isInitializing)
							{
								targetPort.external.value = v;
								targetPort.external.propagateCurrentValue();
							}
						});
					};
					port.internal.subscribe(callback);
					_portCallbacks.set(name, callback);
					
					// 2. МГНОВЕННАЯ доставка текущего значения (если оно уже есть)
					// Это решает проблему, когда TextInput установил значение
					// ДО создания подписки
					if (port.internal.value != null)
					{
						port.external.value = port.internal.value;
						// Не используем propagateCurrentValue здесь, чтобы избежать
						// осцилляции во время инициализации.
						// Propagation произойдёт в _processPendingSignals()
					}
				}
			}
        }
    }

    // ========================================================================
    // HOT RELOAD SUPPORT
    // ========================================================================
    /**
    * Update assembly from new blueprint (hot reload).
    *
    * - Removes ports that no longer exist
    * - Adds new ports from blueprint
    * - Preserves existing connections where possible
    */
    public function updateFromBlueprint(newBp:Blueprint):Void
    {
        if (newBp.id != this.blueprint.id) return;
        this.name = newBp.name;
        
        // Find ports to remove
        var currentPortNames = [for (name in ports.keys()) name];
        var targetPinNames = new Map<String, Bool>();
        for (pin in newBp.pins)
        {
            targetPinNames.set(pin.name, true);
        }
        
        // Remove obsolete ports
        for (name in currentPortNames)
        {
            if (!targetPinNames.exists(name))
            {
                var port = ports.get(name);
                if (port != null)
                {
                    if (port.type == INPUT)
                    {
                        _inputs.remove(port.external);
                        if (_inputCache.length > _inputs.length) _inputCache.pop();
                    }
                    else
                    {
                        _outputs.remove(port.external);
                    }
                    port.dispose();
                    ports.remove(name);
                }
            }
        }
        
        // Add new ports
        for (pin in newBp.pins)
        {
            var port = ports.get(pin.name);
            if (port == null)
            {
                var currentCount = 0;
                for (p in ports) if (p != null && p.type != null && p.type == pin.type) currentCount++;
                var max = (pin.type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;
                if (currentCount < max)
                {
                    var newPort = new ConductorPort(pin.name, pin.type, pin.defaultValue);
                    ports.set(pin.name, newPort);
                    if (pin.type == INPUT)
                    {
                        _inputs.push(newPort.external);
                        newPort.external.owner = this;
                        while (_inputCache.length < _inputs.length) _inputCache.push(null);
                    }
                    else
                    {
                        _outputs.push(newPort.external);
                        newPort.external.owner = this;
                    }
                }
            }
        }
        
        this.blueprint = newBp;
        _updatePortLinks();
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
    }

    // ========================================================================
    // INTERFACE CREATION
    // ========================================================================
    /**
    * Create gateway ports from blueprint pin definitions.
    *
    * Handles type conversion from String to ContactType for compatibility.
    */
    private function _createInterface():Void
    {
        if (blueprint == null || blueprint.pins == null) return;
        for (pinDef in blueprint.pins)
        {
            if (pinDef == null)
            {
                trace('ERROR: PinDef is null in Blueprint(${blueprint.id})');
                continue;
            }
            if (pinDef.name == null)
            {
                trace('ERROR: PinDef.name is null in Blueprint(${blueprint.id})');
                continue;
            }
            
            // Convert type if needed (String → ContactType)
            var portType:ContactType = pinDef.type;
            if (pinDef.type == null)
            {
                trace('WARN: PinDef "${pinDef.name}" has null.type, using UNDEFINED');
                portType = ContactType.UNDEFINED;
            }
            else if (Std.isOfType(pinDef.type, String))
            {
                var typeStr:String = cast pinDef.type;
                trace('DEBUG: Converting String type "${typeStr}" to ContactType for pin "${pinDef.name}"');
                switch (typeStr)
                {
                    case "INPUT": portType = ContactType.INPUT;
                    case "OUTPUT": portType = ContactType.OUTPUT;
                    case "BIDIRECTIONAL": portType = ContactType.BIDIRECTIONAL;
                    default:
                        trace('WARN: Unknown type "${typeStr}", using UNDEFINED');
                        portType = ContactType.UNDEFINED;
                }
            }
            else if (!Std.isOfType(pinDef.type, ContactType))
            {
                trace('ERROR: PinDef "${pinDef.name}" has invalid type: ${pinDef.type}');
                portType = ContactType.UNDEFINED;
            }
            
            var port = new ConductorPort(pinDef.name, portType, pinDef.defaultValue);
            ports.set(pinDef.name, port);
        }
        _updatePortLinks();
    }

    // ========================================================================
    // INTERNAL ATOM INSTANTIATION
    // ========================================================================
    /**
    * Create internal atom instances from blueprint.
    *
    * Atoms are created in frozen state (isInitializing = true)
    * and unfrozen later by _processPendingSignals().
    */
    private function _createInternalInstances():Void
    {
        if (blueprint == null || blueprint.internalAtoms == null) return;
        for (atomDef in blueprint.internalAtoms)
        {
            // Prevent recursive instantiation
            if (atomDef.typeId == this.blueprint.id)
            {
                trace('WARN: Skipped recursive instantiation of ${atomDef.typeId} inside itself.');
                continue;
            }
            
            var newInstanceID = UID.generate();
            _idMap.set(atomDef.instanceId, newInstanceID);
            
            var instance = AssemblyFactory.createAtom(atomDef.typeId, newInstanceID);
            if (instance != null)
            {
                // Freeze atom during creation
                instance.isInitializing = true;
                internalAtoms.set(newInstanceID, instance);
                
                // Restore saved state
                if (atomDef.values != null)
                {
                    instance.restoreState(atomDef.values);
                }
                
                // Register active drivers
                var bpDef = AtomRegistry.get(atomDef.typeId);
                if (bpDef != null && bpDef.isActive && !bpDef.isNative)
                {
                    DriverManager.getInstance().register(instance);
                }
            }
        }
    }

    // ========================================================================
    // INTERNAL CONNECTIONS
    // ========================================================================
    /**
    * Create internal connections between atoms.
    *
    * v1.2 FIX: Added _ensureInternalAtomConnectedToPort() to create explicit
    * link between internal atom and port.internal for OUTPUT ports.
    *
    * Uses suppressPropagation=true to prevent oscillation during initialization.
    * Connections are later activated by _processPendingSignals().
    */
    private function _createInternalConnections():Void
    {
        if (blueprint == null || blueprint.internalConnections == null) return;
        for (conn in blueprint.internalConnections)
        {
            var fromContact = resolveContact(conn.from);
            var toContact = resolveContact(conn.to);
            
            if (fromContact == null)
            {
                trace('ERROR: Assembly(${this.id}): fromContact NULL for ${conn.from.atomId}.${conn.from.contactName}');
                continue;
            }
            if (toContact == null)
            {
                trace('ERROR: Assembly(${this.id}): toContact NULL for ${conn.to.atomId}.${conn.to.contactName}');
                continue;
            }
            if (fromContact.type == null)
            {
                trace('ERROR: Assembly(${this.id}): fromContact.type is NULL for ${conn.from.atomId}.${conn.from.contactName}');
                trace('  Contact ID: ${fromContact.id}');
                trace('  Contact name: ${fromContact.name}');
                trace('  Contact owner: ${fromContact.owner != null ? fromContact.owner.id : "null"}');
                continue;
            }
            if (toContact.type == null)
            {
                trace('ERROR: Assembly(${this.id}): toContact.type is NULL for ${conn.to.atomId}.${conn.to.contactName}');
                trace('  Contact ID: ${toContact.id}');
                trace('  Contact name: ${toContact.name}');
                trace('  Contact owner: ${toContact.owner != null ? toContact.owner.id : "null"}');
                continue;
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // v1.2 FIX: Ensure internal atom is connected to port for OUTPUT ports
            // ═══════════════════════════════════════════════════════════════════
            // If conn.from.atomId == "SELF", then fromContact is port.internal.
            // We need to find the internal atom that is the source and link it
            // to port.internal.
            if (conn.from.atomId == "SELF")
            {
                _ensureInternalAtomConnectedToPort(conn.from.contactName, OUTPUT);
            }
            
            // If conn.to.atomId == "SELF", then toContact is port.internal.
            // We need to find the internal atom that is the target and link
            // port.internal to it.
            if (conn.to.atomId == "SELF")
            {
                _ensureInternalAtomConnectedToPort(conn.to.contactName, INPUT);
            }
            
            // Link with suppressed propagation (prevents oscillation during init)
            fromContact.link(toContact, true);
        }
    }

    /**
    * v1.2 FIX: Ensure internal atom is connected to assembly port.
    *
    * For OUTPUT ports: Find internal atom with output contact matching portName,
    * then link atom.output → port.internal.
    *
    * For INPUT ports: Find internal atom with input contact matching portName,
    * then link port.internal → atom.input.
    *
    * This fixes the signal flow issue where internal atoms were not connected
    * to assembly ports, causing signals to not pass through the Assembly.
    *
    * @param portName Name of the assembly port
    * @param portType Type of the port (INPUT or OUTPUT)
    */
    /**
    * v1.4 FIX: Ensure internal atom is connected to assembly port.
    *
    * Для INPUT портов: Создаём ПРЯМУЮ связь port.external → atom.input
    * (минуя port.internal, чтобы избежать проблем с типами и осцилляцией).
    * Это точно повторяет поведение прямого провода Port In → Atom.
    *
    * Для OUTPUT портов: Связываем atom.output → port.internal (как раньше).
    *
    * @param portName Name of the assembly port
    * @param portType Type of the port (INPUT or OUTPUT)
    */
    private function _ensureInternalAtomConnectedToPort(portName:String, portType:ContactType):Void
    {
        if (internalAtoms == null) return;
        var port = ports.get(portName);
        if (port == null) return;
        
        for (id in internalAtoms.keys())
        {
            var atom:Atom = cast internalAtoms.get(id);
            if (atom == null) continue;
            
            if (portType == OUTPUT)
            {
                // OUTPUT: atom.output → port.internal (стандартная связь)
                var atomOutput = atom.getOutput(portName);
                if (atomOutput != null)
                {
                    if (!atomOutput.hasLink(port.internal))
                    {
                        atomOutput.link(port.internal, true);
                    }
                    break;
                }
            }
            else // INPUT
            {
                // ═══════════════════════════════════════════════════════
                // v1.4 FIX: INPUT — ПРЯМАЯ связь external → atom.input
                // Минуем port.internal, чтобы избежать проблем с типами
                // Это идентично прямому проводу Port In → Atom
                // ═══════════════════════════════════════════════════════
                var atomInput = atom.getInput(portName);
                if (atomInput != null)
                {
                    // Прямая связь: port.external → atom.input
                    if (!port.external.hasLink(atomInput))
                    {
                        port.external.link(atomInput, true);
                    }
                    
                    // ТАКЖЕ сохраняем связь port.external → port.internal
                    // для совместимости с другими системами
                    if (!port.external.hasLink(port.internal))
                    {
                        port.external.link(port.internal, true);
                    }
                    break;
                }
            }
        }
    }

    // ========================================================================
    // CONTACT RESOLUTION
    // ========================================================================
    /**
    * Resolve a ConnectionPoint to a Contact instance.
    *
    * Handles three cases:
    * 1. SELF → returns assembly port's internal contact
    * 2. Nested Assembly → returns external contact (parent connects to child's outside)
    * 3. Simple Atom → returns getInput/getOutput
    *
    * @param point Connection point definition
    * @return Contact instance or null if not found
    */
    private function resolveContact(point:ConnectionPoint):Contact
    {
        if (point == null)
        {
            trace('ERROR: resolveContact received null point');
            return null;
        }
        
        if (point.atomId == "SELF")
        {
            var port = ports.get(point.contactName);
            if (port == null)
            {
                trace('WARN: Port "${point.contactName}" not found in Assembly(${this.id})');
                return null;
            }
            
            // For SELF, return internal contact (internal atoms connect to inside)
            var contact = port.internal;
            if (contact == null)
            {
                trace('ERROR: Port "${point.contactName}" internal contact is null!');
                return null;
            }
            return contact;
        }
        else
        {
            var realAtomId = _idMap.get(point.atomId);
            if (realAtomId == null)
            {
                if (internalAtoms.exists(point.atomId))
                {
                    realAtomId = point.atomId;
                }
                else
                {
                    trace('WARN: Atom "${point.atomId}" not found in Assembly(${this.id})');
                    trace('  Available keys: ${[for(k in internalAtoms.keys()) k]}');
                    return null;
                }
            }
            
            var obj = internalAtoms.get(realAtomId);
            if (obj == null)
            {
                trace('WARN: Instance "${realAtomId}" is null in Assembly(${this.id})');
                return null;
            }
            
            var atom:Atom = cast obj;
            if (Std.isOfType(atom, Assembly))
            {
                var asm = cast(atom, Assembly);
                var port = asm.ports.get(point.contactName);
                if (port == null)
                {
                    trace('ERROR: Port "${point.contactName}" NOT FOUND on Assembly ${atom.name}(${realAtomId})');
                    trace('  Available ports: ${[for(k in asm.ports.keys()) k]}');
                    return null;
                }
                
                // For nested assemblies, use EXTERNAL contact (parent connects to outside)
                var contact:Contact = port.external;
                if (contact == null)
                {
                    trace('ERROR: External contact from port "${point.contactName}" is null!');
                    return null;
                }
                if (contact.type == null)
                {
                    trace('ERROR: Contact "${point.contactName}" has NULL type!');
                    trace('  Port type: ${port.type}');
                    trace('  Atom: ${atom.name} (${atom.id})');
                    return null;
                }
                return contact;
            }
            else
            {
                // Simple atom - use getInput/getOutput
                var c = atom.getInput(point.contactName);
                if (c == null) c = atom.getOutput(point.contactName);
                if (c == null)
                {
                    trace('WARN: Contact "${point.contactName}" not found on atom ${atom.name}(${realAtomId})');
                    return null;
                }
                if (c.type == null)
                {
                    trace('ERROR: Contact "${point.contactName}" on ${atom.name} has null.type!');
                    return null;
                }
                return c;
            }
        }
    }

    // ========================================================================
    // PORT HELPERS
    // ========================================================================
    private function _getOrderedPortDefs():Array<PinDef>
    {
        if (blueprint == null || blueprint.pins == null) return [];
        return blueprint.pins.copy();
    }

    public function getOrderedPorts(type:ContactType):Array<ConductorPort>
    {
        var result:Array<ConductorPort> = [];
        var defs = _getOrderedPortDefs();
        for (pin in defs)
        {
            if (pin.type == type)
            {
                var p = ports.get(pin.name);
                if (p != null) result.push(p);
            }
        }
        return result;
    }

    public function addPort(name:String, type:ContactType, defaultValue:Dynamic = null):ConductorPort
    {
        var currentCount = 0;
        for (p in ports) if (p != null && p.type != null && p.type == type) currentCount++;
        var max = (type == INPUT) ? MAX_INPUT_PORTS : MAX_OUTPUT_PORTS;
        if (currentCount >= max)
        {
            trace('ERROR: Max ports limit reached for type $type');
            return null;
        }
        if (ports.exists(name))
        {
            trace('ERROR: Port name "$name" already exists');
            return null;
        }
        
        var pinDef:PinDef = { name: name, type: type, defaultValue: defaultValue };
        if (blueprint.pins != null) blueprint.pins.push(pinDef);
        
        var port = new ConductorPort(name, type, defaultValue);
        ports.set(name, port);
        
        if (type == INPUT)
        {
            _inputs.push(port.external);
            port.external.owner = this;
            while (_inputCache.length < _inputs.length) _inputCache.push(null);
        }
        else
        {
            _outputs.push(port.external);
            port.external.owner = this;
        }
        
        _updatePortLinks();
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
        return port;
    }

    public function removePort(name:String):Void
    {
        var port = ports.get(name);
        if (port == null) return;
        
        var pinToRemove:PinDef = null;
        if (blueprint.pins != null)
        {
            for (i in 0...blueprint.pins.length)
            {
                var p = blueprint.pins[i];
                if (p != null && p.name == name)
                {
                    pinToRemove = p;
                    break;
                }
            }
            if (pinToRemove != null)
            {
                blueprint.pins.remove(pinToRemove);
            }
        }
        
        if (port.type == INPUT)
        {
            _inputs.remove(port.external);
            if (_inputCache.length > _inputs.length) _inputCache.pop();
        }
        else
        {
            _outputs.remove(port.external);
        }
        
        port.dispose();
        ports.remove(name);
        Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
    }

    // ========================================================================
    // STATE SERIALIZATION
    // ========================================================================
    override public function getPersistentState():Dynamic
    {
        var states:Dynamic = {};
        if (internalAtoms != null)
        {
            for (runtimeId in internalAtoms.keys())
            {
                var atom:Atom = cast internalAtoms.get(runtimeId);
                if (atom != null)
                {
                    var state = atom.getPersistentState();
                    if (state != null)
                    {
                        Reflect.setField(states, runtimeId, state);
                    }
                }
            }
        }
        
        var hasStates = false;
        for (field in Reflect.fields(states))
        {
            hasStates = true;
            break;
        }
        
        var baseState = super.getPersistentState();
        if (hasStates || (baseState != null && baseState.isLogic == true))
        {
            return
            {
                isLogic: baseState != null ? baseState.isLogic : false,
                internalStates: hasStates ? states : null
            };
        }
        return null;
    }

    override public function restoreState(state:Dynamic):Void
    {
        if (state == null) return;
        
        if (blueprint != null && blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0)
        {
            var wasLogic = _isLogic;
            _isLogic = true;
            if (wasLogic != _isLogic)
            {
                _updatePortLinks();
            }
        }
        else if (Reflect.hasField(state, "isLogic"))
        {
            var wasLogic = _isLogic;
            _isLogic = state.isLogic;
            if (wasLogic != _isLogic)
            {
                _updatePortLinks();
            }
        }
        
        if (internalAtoms != null && Reflect.hasField(state, "internalStates"))
        {
            var states = Reflect.field(state, "internalStates");
            for (runtimeId in internalAtoms.keys())
            {
                if (Reflect.hasField(states, runtimeId))
                {
                    var atom:Atom = cast internalAtoms.get(runtimeId);
                    if (atom != null)
                    {
                        var atomState = Reflect.field(states, runtimeId);
                        atom.restoreState(atomState);
                    }
                }
            }
        }
    }

    // ========================================================================
    // DISPOSE
    // ========================================================================
    override public function dispose():Void
    {
        // Dispose internal atoms
        var keys = [for (k in internalAtoms.keys()) k];
        for (key in keys)
        {
            var obj = internalAtoms.get(key);
            if (obj != null)
            {
                if (Std.isOfType(obj, IDisposable))
                {
                    try { cast(obj, IDisposable).dispose(); }
                    catch (e:Dynamic) { trace('Error: $e'); }
                }
            }
        }
        internalAtoms.clear();
        internalAtoms = null;
        
        // Dispose ports
        var portKeys = [for (k in ports.keys()) k];
        for (key in portKeys)
        {
            var port = ports.get(key);
            if (port != null) port.dispose();
        }
        ports.clear();
        ports = null;
        
        super.dispose();
    }
}