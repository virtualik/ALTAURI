package core.base;

import core.data.Blueprint;
import core.data.Blueprint.PinDef;
import core.data.Blueprint.ConnectionPoint;
import core.data.Blueprint.ConnectionDef;
import core.base.Contact;
import core.base.IDisposable;
import core.types.ContactType;
import utils.UID;
import library.AtomRegistry;
import system.managers.DriverManager;
import core.logic.TickGenerator;
import core.logic.Impulsys;
import core.logic.EventType;
using StringTools;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                     ASSEMBLY v2.10                                        ║
* ║  (Full Integrity + Template ID Serialization + Clean Gateway Topology     ║
* ║   + Load-Symmetric Blueprint Sync + Atom Mapping Registration             ║
* ║   + Inline Value Persistence + Crash Traps + Conn Traps                    ║
* ║   + Ghost AtomDef Self-Heal on Load)                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v2.10 CHANGES (Ghost AtomDef Self-Heal — Wide View v1.1):                ║
* ║   _createInternalInstances(): an AtomDef whose typeId cannot be            ║
* ║   resolved (blueprint absent from AtomRegistry — e.g. an assembly          ║
* ║   deleted by an undone grouping in a pre-v3.18 build, or a missing         ║
* ║   library file) is now DROPPED from the blueprint at load time,           ║
* ║   together with its dangling _idMap entry. Before, the dead entry          ║
* ║   produced "ERROR: Blueprint not found" on every load and was             ║
* ║   re-serialized by every save, polluting the project file forever.        ║
* ║   Self-heals saves already carrying such ghosts (field case: the           ║
* ║   CustomAssembly_e5a3 entry left in Selfrun.atom by final test T5).       ║
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
* ║ - v1.1: Provides atom name uniqueness checking within scope               ║
* ║  - v1.2: FIXED signal flow through Assembly ports                         ║
* ║  - v1.4: DIRECT link port.external → atom.input for INPUT ports           ║
* ║  - v1.5: ADDED Ghost Connection Safety Net (defensive sanitization)       ║
* ║  - v1.8: FIXED _restoreInternalPortLinks() contact name resolution        ║
* ║  - v1.9: FIXED async NullRef crash in OUTPUT port callback                ║
* ║  - v1.10: FIXED direct port-to-port connections (SELF→SELF)               ║
* ║           even when no internal atoms exist.                              ║
* ║  - v1.11: FIXED external wires not removed when port is deleted.          ║
* ║           Added PORT_REMOVED event notification.                          ║
* ║  - v2.0: FIXED Template ID serialization for nested state persistence.    ║
* ║  - v2.8: FIXED position scramble in _recreatePortWithNewExternalName()    ║
* ║         (renamed ports jumped to END of _inputs/_outputs via remove+push; ║
* ║          now replaced IN-PLACE at the captured index so external contact  ║
* ║          order stays locked to the internal wall order)                   ║
* ║  - v2.9: STABLE WALL-PORT NAMING v3.0 (Inlet/Arrival/Departure/           ║
* ║         Outlet): legacy pins migrate in place (PortNaming); stable        ║
* ║         ports NEVER rename; beneficiary tooltips (getPortBeneficiary);    ║
* ║         legacy aliases bridge pre-migration parent references and         ║
* ║         heal them in place (resolveContact / getPortByAnyName)            ║
* ║                                                                           ║
* ║  - v2.0: FIXED Delta Topology infinite loops in port linking.             ║
* ║  - v2.1: ADDED syncConnectionsToTemplateIds() — converts runtime IDs in   ║
* ║         blueprint.internalConnections to template IDs before              ║
* ║         reconstruction. Prevents ghost connections after exit.            ║
* ║  - v2.1: ADDED refreshExternalPortNames() — updates port.externalName     ║
* ║         based on currently connected internal atom. Prevents              ║
* ║         "incoming_N" labels surviving after user connects atoms.          ║
* ║  - v2.1: ADDED syncDisplayNamesToBlueprint() — persists user-renamed      ║
* ║         atom displayNames into atomDef.values for restoreState().         ║
* ║  - v2.1: FIXED addPort() — now accepts externalName parameter and         ║
* ║         propagates it to PinDef + ConductorPort dual naming.              ║
* ║  - v2.2: ADDED registerAtomMapping(templateId, runtimeId) — public API    ║
* ║         for GroupAtomsCommand / CreateAtomCommand to register atoms       ║
* ║         added at runtime. Without this, resolveContact cannot find        ║
* ║         the atom by its template ID in blueprint.internalConnections.     ║
* ║  - v2.3: ADDED syncAtomValuesToBlueprint() — merges LIVE persistent       ║
* ║         state of internal atoms into atomDef.values so that               ║
* ║         pop()-reconstruction restores current inline values               ║
* ║         instead of the last-saved ones (BUG-B, load-symmetric).           ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     VERSION HISTORY                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  v2.5 — Connection Table Traps (gateway-link forensics)                   ║
* ║  ──────────────────────────────────────────────                           ║
* ║  Field evidence: after pop()-reconstruction the gateway INPUT             ║
* ║  link for "open" (incoming_2) works while "send" (incoming_3)             ║
* ║  is dead. Whether the SELF-connection lives in the blueprint or           ║
* ║  dies in resolveContact is currently invisible. _createInternal           ║
* ║  Connections() now dumps the bp connection table (ASM-CONN) and           ║
* ║  logs every physical link it creates (ASM-LINK).                          ║
* ║                                                                           ║
* ║  v2.4 — Crash Traps + mergeLiveStateInto                                  ║
* ║  ──────────────────────────────────────────────                           ║
* ║  - dispose(): Trap.log breadcrumbs at every teardown stage                ║
* ║    (entry, per-atom, cleared, super, resume, catch) written to            ║
* ║    crash_trap.log with flush-per-line — survives hard crashes             ║
* ║    (stdout buffering eats the tail on c0000005).                          ║
* ║  - _updatePortLinks(): OUTPUT delivery callback logs the value            ║
* ║    handoff to the external side (condution probe, logic mode).            ║
* ║  - + mergeLiveStateInto(atomDef, atom): static helper for commands        ║
* ║    that rebuild atoms (GroupAtoms) — fixes the grouping-path              ║
* ║    variant of BUG-B (live driver settings lost on grouping:               ║
* ║    ComPort reopened COM1 instead of the configured COM17).                ║
* ║                                                                           ║
* ║  v2.3 — Inline Value Persistence (BUG-B)                                  ║
* ║  ──────────────────────────────────────────────                           ║
* ║  PROBLEM:                                                                 ║
* ║  User-edited inline values (TextInput gain 50 → 3) lived only in          ║
* ║  runtime instances. atomDef.values received them only when                ║
* ║  ProjectManager wrote to disk, so pop()-reconstruction restored           ║
* ║  the LAST SAVED value — edits survived save/load but NOT the              ║
* ║  exit/re-enter cycle (violation of Load-Symmetric Reconstruction).        ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  syncAtomValuesToBlueprint() — for every internal atom (leaf AND          ║
* ║  nested Assembly): getPersistentState() is merged into                    ║
* ║  atomDef.values (matched by instanceId). Called from                      ║
* ║  EditorContext.pop() and prepareCurrentAssemblyForSave().                 ║
* ║  EditorContext v2.8 additionally syncs the exited child state             ║
* ║  into the PARENT atomDef.values — the parent-side restoreState()          ║
* ║  overwrite must see FRESH data, not the last disk-save snapshot.          ║
* ║                                                                           ║
* ║  v2.2 — Atom Mapping Registration                                         ║
* ║  ─────────────────────────────────────────────────                        ║
* ║  PROBLEM:                                                                 ║
* ║  GroupAtomsCommand and CreateAtomCommand add atoms to a live assembly     ║
* ║  at runtime. They write the new atom's instanceId into bp.internalAtoms   ║
* ║  and add the runtime instance to internalAtoms map. But they did NOT      ║
* ║  register the template→runtime mapping in _idMap.                         ║
* ║                                                                           ║
* ║  This caused resolveContact() to fail when looking up the atom by its     ║
* ║  template ID in blueprint.internalConnections — because _idMap didn't     ║
* ║  have the entry.                                                          ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  Added public registerAtomMapping(templateId, runtimeId) method.          ║
* ║  Commands that add atoms at runtime MUST call this after creating the     ║
* ║  instance, so that resolveContact can find it.                            ║
* ║                                                                           ║
* ║  v2.1 — Load-Symmetric Blueprint Sync                                     ║
* ║  ─────────────────────────────────────────────────                        ║
* ║  PROBLEM:                                                                 ║
* ║  After "enter assembly → add wires → exit", the reconstructed assembly    ║
* ║  lost all wires because blueprint.internalConnections still held RUNTIME  ║
* ║  IDs of the old internal atoms. _createInternalInstances() generates new  ║
* ║  runtime IDs via UID.generate(), so the SAFETY NET in                     ║
* ║  _createInternalConnections() removed every connection as a ghost.        ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  Added three sync methods that bring the in-memory blueprint into the     ║
* ║  SAME state as a freshly-loaded-from-disk blueprint:                      ║
* ║    - refreshExternalPortNames()     — update PinDef.externalName          ║
* ║    - syncDisplayNamesToBlueprint()  — write displayName into values       ║
* ║    - syncConnectionsToTemplateIds() — translate runtime→template IDs      ║
* ║  Called in EditorContext.pop() + EditorContext.prepareCurrentAssemblyForSave()
* ║  ─────────────────────────────────────────────────                        ║
* ║  - getPersistentState() / restoreState() now use getTemplateId() for      ║
* ║    JSON keys. This guarantees nested states survive app reloads, as       ║
* ║    Runtime IDs change on every instantiation, but Template IDs are stable.║
* ║  - _ensureInternalAtomConnectedToPort() no longer creates direct          ║
* ║    port.external → atom.input links. This prevented "Delta Topology"      ║
* ║    signal duplication (infinite loops) that caused app freezes.           ║
* ║    Gateway flow (external → internal → atom) is now strictly enforced.    ║
* ║                                                                           ║
* ║  v1.11 — Fix external wire cleanup on port deletion                       ║
* ║  ─────────────────────────────────────────────────                        ║
* ║  - removePort() now emits PORT_REMOVED event with assemblyId and portName ║
* ║  - Parent assembly (Main) listens to this event and removes wires         ║
* ║    that reference SELF.portName from the parent blueprint.                ║
* ║  - Prevents "ghost" wires that point to (0,0) after port deletion.        ║
* ║                                                                           ║
* ║  v1.10 — Fix direct port-to-port connections (SELF→SELF)                  ║
* ║  ────────────────────────────────────────────────────                     ║
* ║  - Changed constructor to call _createInternalConnections()               ║
* ║    even when blueprint.internalAtoms is empty.                            ║
* ║  - Added rebuildInternalConnections() method to refresh all               ║
* ║    internal port links after blueprint changes.                           ║
* ║  - rebuildInternalConnections() now removes old port-to-port links        ║
* ║    using only public Contact API (hasLink / unlink) — no private access.  ║
* ║  - Call rebuildInternalConnections() in updateFromBlueprint(),            ║
* ║    addPort(), removePort() to keep links in sync.                         ║
* ║  - Now a simple SELF.incoming_1 → SELF.outgoing_1 wire works              ║
* ║    immediately without needing an internal atom.                          ║
* ║                                                                           ║
* ║  v1.9 — Async NullReference Protection                                    ║
* ║  ─────────────────────────────────────                                    ║
* ║  Output port callback in _updatePortLinks() now checks:                   ║
* ║    • !_isDisposed (assembly alive)                                        ║
* ║    • !targetPort.isDisposed (port not disposed via ConductorPort flag)    ║
* ║    • targetPort.external != null (contact still exists)                   ║
* ║  Prevents crash when port is disposed between callback scheduling         ║
* ║  and execution (enter/exit editor race condition).                        ║
* ║                                                                           ║
* ║  v1.8 — Hot-Reload Port Link Restore Fix                                  ║
* ║  ─────────────────────────────────────────                                ║
* ║  _restoreInternalPortLinks() now correctly resolves contact names         ║
* ║  from connection definitions instead of using port names:                 ║
* ║                                                                           ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  SELF.pin_X → atom.contact  = INPUT port                         │     ║
* ║  │    port.internal → atom.getInput(contactName)                    │     ║
* ║  │                                                                  │     ║
* ║  │  atom.contact → SELF.pin_X  = OUTPUT port                        │     ║
* ║  │    atom.getOutput(contactName) → port.internal                   │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
* ║                                                                           ║
* ║  v1.5 — Ghost Connection Safety Net                                       ║
* ║  ──────────────────────────────────                                       ║
* ║  _createInternalConnections() removes broken connections at load time:    ║
* ║                                                                           ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  resolveContact() == null?                                       │     ║
* ║  │       │                                                          │     ║
* ║  │       ▼                                                          │     ║
* ║  │    trace(ERROR)                                                  │     ║
* ║  │       │                                                          │     ║
* ║  │       ▼                                                          │     ║
* ║  │    _sanitizeConnection(conn)                                     │     ║
* ║  │       ├── Remove conn from blueprint.internalConnections         │     ║
* ║  │       └── Log cleanup action                                     │     ║
* ║  │                                                                  │     ║
* ║  │  Result: Next save persists CLEANED blueprint                    │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
* ║                                                                           ║
* ║  v1.4 — Direct Input Port Link                                            ║
* ║  ─────────────────────────────────                                        ║
* ║  For INPUT ports: Creates DIRECT link port.external → atom.input          ║
* ║  (bypassing port.internal to avoid type issues and oscillation).          ║
* ║  This exactly replicates direct wire Port In → Atom behavior              ║
* ║                                                                           ║
* ║  v1.2 — Signal Flow Through Ports                                         ║
* ║  ──────────────────────────────────                                       ║
* ║  Added _ensureInternalAtomConnectedToPort() method that creates           ║
* ║  explicit link between internal atom and port.internal for OUTPUT ports.  ║
* ║                                                                           ║
* ║  ┌──────────────────────────────────────────────────────────────────┐     ║
* ║  │  Button.out ──link──► port.internal ──subscribe──► callback      │     ║
* ║  │                                         │                        │     ║
* ║  │                                         ▼                        │     ║
* ║  │                               port.external ──link──► LED.in     │     ║
* ║  └──────────────────────────────────────────────────────────────────┘     ║
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
        /**
        * v2.9: Legacy port-name aliases (pre-stable-naming name -> port).
        * Built from the PortNaming session cache after ports are created;
        * lets parents that still reference old names ("Button_out",
        * "incoming_1") resolve the migrated stable ports until their own
        * blueprints heal (in place) on first resolution.
        */
        private var _legacyPortNames:Map<String, ConductorPort> = new Map<String, ConductorPort>();


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

        /**
        * v2.2: Register a template→runtime mapping for an atom added at runtime.
        *
        * Commands like GroupAtomsCommand and CreateAtomCommand add atoms to a
        * live assembly. They write the new atom's instanceId into
        * bp.internalAtoms and add the runtime instance to internalAtoms map.
        * But _idMap is normally only populated by _createInternalInstances()
        * during Assembly construction — atoms added later are NOT in _idMap.
        *
        * This causes resolveContact() to fail when looking up the atom by its
        * template ID in blueprint.internalConnections, because the fallback
        * path (`if (internalAtoms.exists(point.atomId))`) only works when
        * the bp stores the runtime ID directly (which it shouldn't — bp
        * should always store template IDs, see Blueprint as SSOT principle).
        *
        * Commands that add atoms at runtime MUST call this method after
        * creating the instance, so that:
        *   1. resolveContact can find the atom by template ID
        *   2. getTemplateId can reverse-lookup the runtime ID
        *   3. saveAssemblyToLibrary can translate runtime→template on disk
        *
        * @param templateId The stable blueprint ID (e.g., "CustomAssembly_2741"
        *                   or "Button" — same as atomDef.typeId)
        * @param runtimeId  The live instance ID (UID.generate() result)
        */
        public function registerAtomMapping(templateId:String, runtimeId:String):Void
        {
                if (_idMap == null) _idMap = new Map();
                if (templateId == null || runtimeId == null) return;
                _idMap.set(templateId, runtimeId);
        }

        /**
        * v2.2: Remove a template→runtime mapping (e.g., on undo of
        * GroupAtomsCommand / CreateAtomCommand).
        *
        * Without this, the mapping would linger and point to a disposed
        * atom, causing resolveContact to return a stale reference.
        *
        * @param templateId The stable blueprint ID to remove from _idMap
        */
        public function unregisterAtomMapping(templateId:String):Void
        {
                if (_idMap != null && templateId != null) _idMap.remove(templateId);
        }

        private function get_inputs():Map<String, Contact>
        {
                var map = new Map<String, Contact>();
                for (p in ports)
                {
                        if (p != null && p.type != null && p.type == INPUT)
                        {
// The outher word seeks porta using outher name (externalName), or Lasso crash
                                map.set(p.externalName, p.external);
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
// The outher word seeks porta using outher name (externalName), or Lasso crash
                                map.set(p.externalName, p.external);
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
                trace(' ASSEMBLY QUARANTINE: ${this.id} - ${reason}');

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

// ═══════════════════════════════════════════════════════════════════
// v1.10 FIX: Initialize internal structure even if no internal atoms
//            but there are internal connections (SELF→SELF wires)
// ═══════════════════════════════════════════════════════════════════
                var hasInternalAtoms = (blueprint.internalAtoms != null && blueprint.internalAtoms.length > 0);
                var hasInternalConns = (blueprint.internalConnections != null && blueprint.internalConnections.length > 0);

// Suspend tick generator only if we have internal atoms
                if (hasInternalAtoms)
                {
                        TickGenerator.getInstance().suspend();
                        try
                        {
                                _createInternalInstances();
                        }
                        catch (e:Dynamic)
                        {
                                trace('ERROR during Assembly($id) internal instances creation: $e');
                        }
                }

// ALWAYS create internal connections if there are any (even without atoms)
                if (hasInternalConns)
                {
                        try
                        {
                                _createInternalConnections();
                        }
                        catch (e:Dynamic)
                        {
                                trace('ERROR during Assembly($id) internal connections creation: $e');
                        }
                }

// Initialize logic state and port links (always)
                _initializeLogicState();
                _updatePortLinks();

// Process pending signals only if we have internal atoms
                if (hasInternalAtoms)
                {
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
        * ┌─────────────────────────────────────────────────────────────────┐
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
        * v1.4 FIX: Does NOT force true/false values.
        * Values come ONLY from defaultValue, external links, or internal atoms.
        * This prevents overwriting String/Int values with booleans.
        */
        private function _initializeLogicState():Void
        {
                if (blueprint != null && blueprint.pins != null)
                {
                        for (pinDef in blueprint.pins)
                        {
                                if (pinDef == null || pinDef.name == null) continue;

                                var port = ports.get(pinDef.name);
                                if (port == null) continue;

// Set defaultValue ONLY if value is still null
// and defaultValue is defined in Blueprint
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
// FIX v1.3: PASS EXTERNAL VALUES INTO ASSEMBLY
// ═══════════════════════════════════════════════════════════════
// External atoms may have sent values BEFORE Assembly initialization.
// Force sync external → internal for INPUT ports.
// ═══════════════════════════════════════════════════════════════
                for (name in ports.keys())
                {
                        var port = ports.get(name);
                        if (port != null && port.type == INPUT)
                        {
                                if (port.external != null && port.internal != null)
                                {
// If external has value but internal doesn't or differs
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

// Re-pass external values inward
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

// Re-sync OUTPUT ports
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
        *
        * v1.9 FIX: Output callback includes triple null-safety check:
        *   • !_isDisposed — assembly still alive
        *   • !targetPort.isDisposed — port not disposed (ConductorPort v1.1 flag)
        *   • targetPort.external != null — contact still exists
        * This prevents NullReferenceException when port is disposed between
        * callback scheduling and execution (enter/exit editor race condition).
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
// ── Logic Mode (digital) ──
                                if (port.type == INPUT)
                                {
// Input: direct link external → internal
                                        port.external.link(port.internal);
                                }
                                else // OUTPUT
                                {
// Output: subscribe to internal → async delivery to external
                                        var callback = function(v:Dynamic)
                                        {
                                                var targetPort = port;
                                                TickGenerator.getInstance().scheduleNextTick(function()
                                                {
                                                        if (!_isDisposed
                                                                        && targetPort != null
                                                                        && !targetPort.isDisposed
                                                                        && targetPort.external != null
                                                                        && !isInitializing)
                                                        {
                                                                utils.Trap.log("COND-OUT", "port=" + targetPort.externalName + " value=" + Std.string(v));
                                                                targetPort.external.value = v;
                                                                targetPort.external.propagateCurrentValue();
                                                        }
                                                });
                                        };
                                        port.internal.subscribe(callback);
                                        _portCallbacks.set(name, callback);

// Instant delivery of current value (if already present)
                                        if (port.internal.value != null && port.external != null)
                                        {
                                                port.external.value = port.internal.value;
                                        }
                                }
                        }
                        else
                        {
// ── Analog Mode (immediate) ──
                                if (port.type == INPUT)
                                {
// Input: direct link external → internal
                                        port.external.link(port.internal);
                                }
                                else // OUTPUT
                                {
// Output: direct link internal → external
                                        port.internal.link(port.external);
                                }
                        }
                }
        }

        /**
         * Разрывает все существующие связи между внутренними атомами и портами.
         * Вызывается перед пересозданием связей в _restoreInternalPortLinks().
         */
        private function _clearInternalPortLinks():Void
        {
                if (internalAtoms == null || ports == null) return;

                for (port in ports)
                {
                        if (port == null || port.internal == null) continue;
                        var internalContact = port.internal;

                        for (runtimeId in internalAtoms.keys())
                        {
                                var atom:Atom = cast internalAtoms.get(runtimeId);
                                if (atom == null) continue;

                                // Проверяем все контакты атома
                                var allContacts = atom.getInputs().concat(atom.getOutputs());
                                for (contact in allContacts)
                                {
                                        if (contact != null && !contact.isDisposed && contact.hasLink(internalContact))
                                        {
                                                trace('Удаляем связь: ${contact.name} <-> ${internalContact.name}');
                                                contact.unlink(internalContact);
                                        }
                                }

                                // Проверяем все входы и выходы атома
                                var inputs = atom.getInputs();
                                if (inputs != null)
                                {
                                        for (contact in inputs)
                                        {
                                                if (contact != null && !contact.isDisposed)
                                                {
                                                        // Связь от порта к атому (port.internal -> contact)
                                                        if (internalContact.hasLink(contact))
                                                        {
                                                                internalContact.unlink(contact);
                                                        }
                                                        // Связь от атома к порту (contact -> port.internal)
                                                        if (contact.hasLink(internalContact))
                                                        {
                                                                contact.unlink(internalContact);
                                                        }
                                                }
                                        }
                                }
                                var outputs = atom.getOutputs();
                                if (outputs != null)
                                {
                                        for (contact in outputs)
                                        {
                                                if (contact != null && !contact.isDisposed)
                                                {
                                                        if (internalContact.hasLink(contact))
                                                        {
                                                                internalContact.unlink(contact);
                                                        }
                                                        if (contact.hasLink(internalContact))
                                                        {
                                                                contact.unlink(internalContact);
                                                        }
                                                }
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
        * v1.8 FIX: Now also restores internal atom ↔ port links that are
        * established by _ensureInternalAtomConnectedToPort(). Without this,
        * entering and exiting the nested editor would break signal flow
        * because _updatePortLinks() only handles external↔internal port links.
        *
        * - Removes ports that no longer exist
        * - Adds new ports from blueprint
        * - Preserves existing connections where possible
        * - v1.8: Re-establishes internal atom ↔ port.internal connections
        * - v1.10: Also rebuilds all internal port-to-port connections
        */
        public function updateFromBlueprint(newBp:Blueprint):Void
        {
                if (newBp.id != this.blueprint.id) return;
                this.name = newBp.name;

                // v2.9: a hot-reloaded blueprint may arrive pre-migration —
                // convert pin names to the stable scheme before ports are diffed.
                core.logic.PortNaming.migrateBlueprintInPlace(newBp);

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
// ═══════════════════════════════════════════════════════
// FIX: Сохраняем Dual Naming при горячей перезагрузке!
// ═══════════════════════════════════════════════════════
                                        var extName = pin.name;
                                        var extDyn = Reflect.field(pin, "externalName");
                                        if (extDyn != null && Std.string(extDyn) != "") extName = Std.string(extDyn);

                                        var newPort = new ConductorPort(extName, pin.type, pin.name, pin.defaultValue);
                                        // v1.2 (Port Labels): mirror the cosmetic label from the pin
                                        var lblDyn = Reflect.field(pin, "label");
                                        if (lblDyn != null && Std.string(lblDyn) != "")
                                        {
                                                newPort.label = Std.string(lblDyn);
                                        }

                                        ports.set(pin.name, newPort); // Ключ мапы - всегда internalName
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

// ═══════════════════════════════════════════════════════════════════
// FIX: Удаляем все старые связи между атомами и портами
// ═══════════════════════════════════════════════════════════════════
                _clearInternalPortLinks();

                // Теперь восстанавливаем связи заново
                _restoreInternalPortLinks();
                rebuildInternalConnections();
                reconnectExternalLinks();

// ═══════════════════════════════════════════════════════════════════
// v1.8 FIX: Restore internal atom ↔ port links with correct names
// ══════════════════════════════════════════════════════════════════
                _restoreInternalPortLinks();

// ═══════════════════════════════════════════════════════════════════
// v1.10 FIX: Rebuild all internal port-to-port connections
// ═══════════════════════════════════════════════════════════════════
                rebuildInternalConnections();

// ═══════════════════════════════════════════════════════════════════
// v2.1 FIX: Reconnect external links after hot-reload
// ═══════════════════════════════════════════════════════════════════
                //_initializeLogicState();   // Устанавливает значения по умолчанию
                //_processPendingSignals();  // Запускает активные драйверы (MiniAudioAtom)
                reconnectExternalLinks();

                // v2.9: aliases must point at the FRESH port objects
                _rebuildLegacyPortAliases();

                Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
        }

        /**
        * v2.1: Reconnect external links after hot-reload.
        *
        * After updateFromBlueprint() recreates ports and internal connections,
        * external connections (from parent assembly to this assembly) need to
        * be re-established physically.
        *
        * This method:
        * 1. Finds the parent assembly that contains this assembly
        * 2. Iterates through parent's blueprint connections
        * 3. Re-links contacts for connections involving this assembly
        */
        public function reconnectExternalLinks():Void
        {
// Find parent assembly through EditorContext stack
                var stack = Impulsys.quickEmit; // This won't work, need different approach

// Alternative: iterate through all assemblies in the system
// For now, we'll use a simpler approach - check if we have external connections
// in our blueprint that reference SELF ports

                if (blueprint == null || blueprint.internalConnections == null) return;

// For each connection involving SELF ports, ensure physical link exists
                for (conn in blueprint.internalConnections)
                {
                        if (conn.from.atomId == "SELF" || conn.to.atomId == "SELF")
                        {
                                var fromContact = resolveContact(conn.from);
                                var toContact = resolveContact(conn.to);

                                if (fromContact != null && toContact != null)
                                {
// Ensure physical link exists
                                        if (!fromContact.hasLink(toContact))
                                        {
                                                fromContact.link(toContact, true);
                                        }
                                }
                        }
                }
        }

        /**
        * v2.1: Syncs runtime displayName changes back to the blueprint's internalAtoms.
        * Called before exit/reconstruction to preserve user-renamed atoms.
        * This ensures that when the assembly is reconstructed via AssemblyFactory,
        * the new instance will inherit the correct display names from saved state.
        */
        public function syncDisplayNamesToBlueprint():Void
        {
                if (internalAtoms == null || blueprint.internalAtoms == null) return;

                for (runtimeId in internalAtoms.keys())
                {
                        var atom:Atom = cast internalAtoms.get(runtimeId);
                        if (atom == null) continue;

                        var templateId = getTemplateId(runtimeId);
                        for (atomDef in blueprint.internalAtoms)
                        {
                                if (atomDef.instanceId == templateId)
                                {
                                        // Store displayName in values map for persistence
                                        if (atom.displayName != null && atom.displayName != atom.type)
                                        {
                                                if (atomDef.values == null) atomDef.values = {};
                                                atomDef.values.displayName = atom.displayName;
                                        }
                                        break;
                                }
                        }
                }
        }

        /**
        * v2.3: Syncs the LIVE persistent state of internal atoms into
        * blueprint.internalAtoms[].values (matched by instanceId).
        *
        * WHY THIS EXISTS (BUG-B — inline values do not survive exit):
        * syncDisplayNamesToBlueprint() persists ONLY displayName. Edited
        * inline values (e.g., TextInput 50 → 3) live exclusively in the
        * runtime instances; atomDef.values receives them only when
        * ProjectManager writes to disk. pop()-reconstruction builds new
        * atoms from atomDef.values — i.e., from the LAST SAVED state —
        * so edits silently revert on every exit/re-enter cycle while
        * surviving a full save/load round-trip. That asymmetry violates
        * the Load-Symmetric Reconstruction principle.
        *
        * This method completes the symmetry:
        *     reconstruction = save = load
        *
        * ALGORITHM:
        *   for each internal atom (by runtimeId):
        *     1. templateId = getTemplateId(runtimeId)
        *     2. state = atom.getPersistentState()   (null → skip)
        *     3. merge EVERY field of state into atomDef.values
        *
        * NESTED ASSEMBLIES ARE INCLUDED DELIBERATELY. Their
        * getPersistentState() returns {isLogic, internalStates, displayName}
        * keyed by template IDs — exactly the shape a disk save stores.
        * The parent-side restoreState() (run by _createInternalInstances
        * AFTER the child constructor) OVERWRITES the freshly built child
        * internals with atomDef.values — stale internalStates there would
        * resurrect dead values and defeat the leaf-atom sync performed
        * one level deeper. EditorContext.pop() additionally syncs the
        * exited child state into the PARENT atomDef.values
        * (syncChildStateToParentAtomDef) for the very same reason.
        *
        * KNOWN LIMITATION (shared with syncDisplayNamesToBlueprint and
        * updateInstancesOf semantics): all instances of one blueprint
        * type share the registered blueprint — the values of the instance
        * being exited win. Same-type instances are treated as clones.
        */
        public function syncAtomValuesToBlueprint():Void
        {
                if (internalAtoms == null || blueprint == null
                        || blueprint.internalAtoms == null) return;

                for (runtimeId in internalAtoms.keys())
                {
                        var atom:Atom = cast internalAtoms.get(runtimeId);
                        if (atom == null) continue;

                        var templateId = getTemplateId(runtimeId);

// Live state of this atom: TextInput text, Toggle position, driver
// settings, nested Assembly internalStates... null → nothing to keep.
                        var state:Dynamic = null;
                        try
                        {
                                state = atom.getPersistentState();
                        }
                        catch (e:Dynamic)
                        {
                                trace('WARN: syncAtomValuesToBlueprint: getPersistentState() failed for "${templateId}": $e');
                                continue;
                        }
                        if (state == null) continue;

                        for (atomDef in blueprint.internalAtoms)
                        {
                                if (atomDef.instanceId == templateId)
                                {
                                        if (atomDef.values == null) atomDef.values = {};
                                        var fields:Array<String> = Reflect.fields(state);
                                        for (field in fields)
                                        {
                                                Reflect.setField(atomDef.values, field, Reflect.field(state, field));
                                        }
                                        trace('📦 syncAtomValues: "${templateId}" ← ${fields.length} field(s) [${fields.join(", ")}]');
                                        break;
                                }
                        }
                }
        }

        /**
        * v2.4: Static helper for COMMANDS that rebuild atoms (GroupAtomsCommand,
        * CreateAtomCommand): merges a LIVE atom persistent state into the
        * blueprint AtomDef.values BEFORE the original instance is disposed.
        *
        * This is the GROUPING-PATH counterpart of syncAtomValuesToBlueprint()
        * (BUG-B variant): at grouping, the new ComPort instance restored only
        * atomDef.values (displayName etc.) — the live driver settings (port
        * name COM17, baud) were never merged, so the fresh atom opened the
        * DEFAULT port (COM1) and the physical send went nowhere.
        *
        * Usage inside the command, per grouped atom, while it is STILL ALIVE:
        *     Assembly.mergeLiveStateInto(newAtomDef, liveAtom);
        *
        * Dynamic param keeps this helper free of Blueprint typedef imports.
        */
        public static function mergeLiveStateInto(atomDef:Dynamic, atom:Atom):Void
        {
                if (atomDef == null || atom == null) return;
                var state:Dynamic = null;
                try
                {
                        state = atom.getPersistentState();
                }
                catch (e:Dynamic)
                {
                        trace('WARN: mergeLiveStateInto: getPersistentState() failed: ' + e);
                        return;
                }
                if (state == null) return;

                if (atomDef.values == null) atomDef.values = {};
                var fields:Array<String> = Reflect.fields(state);
                for (field in fields)
                {
                        Reflect.setField(atomDef.values, field, Reflect.field(state, field));
                }
                utils.Trap.log("MERGE", "merged " + fields.length + " field(s) into def: " + fields.join(", "));
        }

        /**
        * v2.1: Translates all RUNTIME IDs in blueprint.internalConnections to TEMPLATE IDs.
        *
        * WHY THIS IS NEEDED:
        * ConnectCommand stores runtime IDs when the user creates wires inside an
        * assembly. ProjectManager.saveAssemblyToLibrary() performs the same
        * runtime→template translation when writing to disk, so disk-saved
        * blueprints are correct. But the IN-MEMORY blueprint used by
        * EditorContext.updateInstancesOf() still contains runtime IDs.
        *
        * When AssemblyFactory.createAtom() runs the constructor, _createInternalInstances()
        * generates NEW runtime IDs via UID.generate() and records them in _idMap
        * as (template → newRuntime). _createInternalConnections() then tries to
        * resolve the OLD runtime IDs from the blueprint — which no longer exist
        * in internalAtoms — and the SAFETY NET removes every connection as a
        * "ghost".
        *
        * This method brings the in-memory blueprint into the SAME state as a
        * freshly-loaded-from-disk blueprint, so that reconstruction works
        * identically to project load (Load-Symmetric Reconstruction principle).
        *
        * Idempotent: if the IDs are already template IDs (no match in _idMap
        * as a runtime ID), they are returned as-is by getTemplateId().
        *
        * MUST be called in EditorContext.pop() BEFORE registerBlueprint() +
        * updateInstancesOf(), so that the bp registered in AtomRegistry and
        * consumed by AssemblyFactory.createAtom is already in template-ID form.
        */
        public function syncConnectionsToTemplateIds():Void
        {
                if (blueprint == null || blueprint.internalConnections == null) return;

// Build runtime → template lookup once (reverse of _idMap)
// _idMap is: template → runtime. We need: runtime → template.
                var runtimeToTemplate = new Map<String, String>();
                if (_idMap != null)
                {
                        for (templateId in _idMap.keys())
                        {
                                var runtimeId = _idMap.get(templateId);
                                if (runtimeId != null) runtimeToTemplate.set(runtimeId, templateId);
                        }
                }

// Rewrite each connection's atomId in place
                for (conn in blueprint.internalConnections)
                {
                        if (conn.from.atomId != "SELF" && runtimeToTemplate.exists(conn.from.atomId))
                        {
                                conn.from.atomId = runtimeToTemplate.get(conn.from.atomId);
                        }
                        if (conn.to.atomId != "SELF" && runtimeToTemplate.exists(conn.to.atomId))
                        {
                                conn.to.atomId = runtimeToTemplate.get(conn.to.atomId);
                        }
                }
        }

        /**
        * v2.1: Updates port.externalName for every SELF port based on the
        * currently connected internal atom.
        */
        public function refreshExternalPortNames():Void
        {
                if (blueprint == null || blueprint.internalConnections == null) return;
                if (internalAtoms == null || ports == null) return;

                // Build a map: portInternalName → {atomDisplayName, contactName}
                var portInfos = new Map<String, {atomName:String, contactName:String}>();

                for (conn in blueprint.internalConnections)
                {
                        if (conn.from.atomId == "SELF")
                        {
                                var portName = conn.from.contactName;
                                var atom = _resolveInternalAtom(conn.to.atomId);
                                if (atom != null)
                                {
                                        var displayName = (atom.displayName != null && atom.displayName != "")
                                        ? atom.displayName : atom.type;
                                        portInfos.set(portName, {atomName: displayName, contactName: conn.to.contactName});
                                }
                        }
                        else if (conn.to.atomId == "SELF")
                        {
                                var portName = conn.to.contactName;
                                var atom = _resolveInternalAtom(conn.from.atomId);
                                if (atom != null)
                                {
                                        var displayName = (atom.displayName != null && atom.displayName != "")
                                                                          ? atom.displayName : atom.type;
                                        portInfos.set(portName, {atomName: displayName, contactName: conn.from.contactName});
                                }
                        }
                }

                // Apply updates
                // ═══════════════════════════════════════════════════════════════════
                // v2.7 FIX: Track used external names to prevent collisions
                // ═══════════════════════════════════════════════════════════════════
                // v2.7 CRITICAL FIX: Don't pre-populate usedExternalNames with
                // THIS assembly's OWN port externalNames!
                //
                // PREVIOUS BUG:
                //   - Pre-populate usedExternalNames with all current externalNames
                //   - For each port, compute baseExtName = atomName_contactName
                //   - If baseExtName is in usedExternalNames → append _N
                //
                //   Problem: when this method runs the SECOND time (e.g., during
                //   pop() → refreshExternalPortNames()), the port's externalName
                //   is ALREADY "Pass_in_2" (from the first refresh). When we
                //   re-compute baseExtName = "Pass_in_2" (because contactName on
                //   the child atom's port is "in_2" — actually let me re-check,
                //   this is contactName from the INNER atom's contact, e.g. "in")
                //   ... wait, the contactName here is the INNER atom's contact
                //   name (e.g., "in", "out"), NOT the port's externalName.
                //
                //   So baseExtName = "Pass_in" (from displayName="Pass",
                //   contactName="in"). If the port's current externalName is
                //   "Pass_in" (matching), the OLD code would still find it in
                //   usedExternalNames (from pre-populate) and append _2 →
                //   "Pass_in_2". On next refresh: "Pass_in_2_2". Etc.
                //
                //   This snowballs _N suffixes on every refresh.
                //
                // NEW ALGORITHM:
                //   1. Do NOT pre-populate usedExternalNames
                //   2. For each port (in deterministic order):
                //      a. Compute baseExtName
                //      b. If baseExtName is already used by ANOTHER port that
                //         we've already assigned in THIS pass → append _N
                //      c. Otherwise use baseExtName as-is
                //   3. This way, ports keep their stable names across refreshes
                //      (because we don't conflict with our own previous values)
                // ═══════════════════════════════════════════════════════════════════

                var usedExternalNames:Map<String, Bool> = new Map();

                // Process ports in deterministic order (sorted by portName)
                // to ensure consistent naming across refreshes
                var sortedPortNames = [for (p in portInfos.keys()) p];
                sortedPortNames.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));

                for (portName in sortedPortNames)
                {
                        var info = portInfos.get(portName);
                        var port = ports.get(portName);
                        if (port == null) continue;

                        // ═════════════════════════════════════════════════════════════════════════
                        // v2.9: STABLE PORTS NEVER RENAME. Inlet_N/Outlet_N keep their
                        // name for life — the semantic info lives in the hover tooltip
                        // (getPortBeneficiary*), not in the name. This kills the whole
                        // name-drift bug family (suffix chains, PORT-HEAL storms,
                        // frozen-name weirdness) at the root.
                        // ═════════════════════════════════════════════════════════════════════════
                        if (core.logic.PortNaming.isStableExternalName(port.externalName)) continue;

                        var baseExtName = StringTools.replace(info.atomName, " ", "_") + "_" + info.contactName;
                        var newExtName = baseExtName;

                        // Ensure uniqueness by appending _N if collision exists
                        // (collision = another port in THIS pass already took this name)
                        if (usedExternalNames.exists(newExtName))
                        {
                                var counter = 1;
                                while (usedExternalNames.exists(baseExtName + "_" + counter))
                                {
                                        counter++;
                                }
                                newExtName = baseExtName + "_" + counter;
                        }
                        usedExternalNames.set(newExtName, true);

                        if (port.externalName == newExtName) continue;

                        // Update PinDef.externalName in blueprint
                        if (blueprint.pins != null)
                        {
                                for (pin in blueprint.pins)
                                {
                                        if (pin.name == portName)
                                        {
                                                pin.externalName = newExtName;
                                                break;
                                        }
                                }
                        }

                        // Recreate ConductorPort with new externalName
                        _recreatePortWithNewExternalName(port, portName, newExtName);
                }
        }

        /**
        * v2.1: Helper — recreates a ConductorPort with a new externalName.
        *
        * ConductorPort's external Contact has its .name set at construction
        * time and cannot be changed (it would break Contact.identity invariants
        * used by WireRenderer and NodeView port lookups). So we must:
        *   1. Capture the port's current state (type, defaultValue, internalName)
        *   2. Remove the old external Contact from _inputs / _outputs
        *   3. Dispose the old ConductorPort (also disposes its Contacts)
        *   4. Create a new ConductorPort with the new externalName
        *   5. Re-add the new external Contact to _inputs / _outputs
        *   6. Re-establish internal ↔ external links via _updatePortLinks()
        *   7. Re-establish atom ↔ port.internal links via _restoreInternalPortLinks()
        */
        private function _recreatePortWithNewExternalName(oldPort:ConductorPort, internalName:String, newExtName:String):Void
        {
                if (oldPort == null) return;
                var portType = oldPort.type;
                var defaultValue = oldPort.defaultValue;
// v1.2 (Port Labels): the cosmetic label survives the passport rename
// (captured BEFORE dispose — oldPort.label dies with the old instance).
                var oldLabel:String = oldPort.label;

// 1. v2.8 POSITION-INTEGRITY: capture the old external contact's INDEX
//    before dispose. The old code did remove()+push(), which moved EVERY
//    renamed port to the END of _inputs/_outputs — external contact order
//    scrambled vs the internal wall order. Field repro: connect a button
//    to the LOWEST new internal port, then connect an atom to the port
//    above it — the second rename pushed its external contact to the end
//    and displaced the button's contact one slot UP on the parent-side
//    node ("не самый нижний контакт принимает иное название, а тот что
//    выше над самым последним").
                var extIdx:Int = -1;
                if (portType == INPUT)
                {
                        if (_inputs != null) extIdx = _inputs.indexOf(oldPort.external);
                }
                else
                {
                        if (_outputs != null) extIdx = _outputs.indexOf(oldPort.external);
                }

// 2. Dispose old port (disposes internal + external contacts)
//    IMPORTANT: this nullifies contact.callbackTargets, which is exactly
//    what we want — leaked DeviceView callbacks can no longer fire.
                oldPort.dispose();

// 3. Create new port with dual naming
                var newPort = new ConductorPort(newExtName, portType, internalName, defaultValue);
// v1.2 (Port Labels): re-attach the captured cosmetic label
                newPort.label = (oldLabel != null && oldLabel != "") ? oldLabel : "port";
                ports.set(internalName, newPort);

// 4. v2.8: replace external contact AT THE CAPTURED INDEX (position-stable).
//    Fallback push() only when the old contact was not found (defensive).
                if (portType == INPUT)
                {
                        if (extIdx >= 0) _inputs[extIdx] = newPort.external;
                        else _inputs.push(newPort.external);
                        newPort.external.owner = this;
                        while (_inputCache.length < _inputs.length) _inputCache.push(null);
                }
                else
                {
                        if (extIdx >= 0) _outputs[extIdx] = newPort.external;
                        else _outputs.push(newPort.external);
                        newPort.external.owner = this;
                }

// 5. Re-establish internal ↔ external port links (logic mode callbacks etc.)
                _updatePortLinks();

// 6. Re-establish atom ↔ port.internal links from blueprint
                _restoreInternalPortLinks();
        }

        /**
        * v1.8: Re-establish internal atom ↔ port.internal connections after hot-reload.
        *
        * Scans blueprint.internalConnections for any connection referencing "SELF"
        * and creates the appropriate link between the internal atom's contact
        * and the port's internal/external contact.
        *
        * KEY INSIGHT: The contact name comes from the NON-SELF end of the
        * connection, NOT from the port name. For example:
        *
        *   Connection: SELF.pin_0 → id_xxx.in
        *   Port name: "pin_0"
        *   Contact name: "in"  ← THIS is what we search for on the atom
        *
        * ┌─────────────────────────────────────────────────────────────────────┐
        * │  Connection: SELF.pin_X → atom.contact                              │
        * │  Meaning: Data ENTERS assembly through pin_X → goes to atom         │
        * │  Port type: INPUT                                                   │
        * │  Action: port.internal → atom.getInput(contactName)                 │
        * │                                                                     │
        * │  Connection: atom.contact → SELF.pin_X                              │
        * │  Meaning: Data EXITS assembly from atom → through pin_X             │
        * │  Port type: OUTPUT                                                  │
        * │  Action: atom.getOutput(contactName) → port.internal                │
        * └─────────────────────────────────────────────────────────────────────┘
        */
        private function _restoreInternalPortLinks():Void
        {
                if (blueprint == null || blueprint.internalConnections == null) return;

                for (conn in blueprint.internalConnections)
                {
                        if (conn.from.atomId == "SELF")
                        {
                                // INPUT PORT: SELF.portName → atom.contactName
                                var portName = conn.from.contactName;
                                var atomId = conn.to.atomId;
                                var contactName = conn.to.contactName;

                                var port = ports.get(portName);
                                if (port == null) continue;

                                // ═══════════════════════════════════════════════════════
                                // FIX: Ищем атом напрямую по Runtime ID в internalAtoms
                                // ═══════════════════════════════════════════════════════
                                var atom:Atom = null;
                                // Сначала пробуем найти по Runtime ID (если atomId уже Runtime)
                                if (internalAtoms.exists(atomId))
                                {
                                        atom = cast internalAtoms.get(atomId);
                                }
                                else
                                {
                                        // Иначе пробуем найти по Template ID через idMap
                                        var runtimeId = _idMap.get(atomId);
                                        if (runtimeId != null && internalAtoms.exists(runtimeId))
                                        {
                                                atom = cast internalAtoms.get(runtimeId);
                                        }
                                }

                                if (atom == null) continue;

                                var atomInput = atom.getInput(contactName);
                                if (atomInput != null)
                                {
                                        if (!port.internal.hasLink(atomInput))
                                        {
                                                port.internal.link(atomInput, true);
                                        }
                                }
                        }

                        if (conn.to.atomId == "SELF")
                        {
                                // OUTPUT PORT: atom.contactName → SELF.portName
                                var portName = conn.to.contactName;
                                var atomId = conn.from.atomId;
                                var contactName = conn.from.contactName;

                                var port = ports.get(portName);
                                if (port == null) continue;

                                // ═══════════════════════════════════════════════════════
                                // FIX: Ищем атом напрямую по Runtime ID в internalAtoms
                                // ═══════════════════════════════════════════════════════
                                var atom:Atom = null;
                                if (internalAtoms.exists(atomId))
                                {
                                        atom = cast internalAtoms.get(atomId);
                                }
                                else
                                {
                                        var runtimeId = _idMap.get(atomId);
                                        if (runtimeId != null && internalAtoms.exists(runtimeId))
                                        {
                                                atom = cast internalAtoms.get(runtimeId);
                                        }
                                }

                                if (atom == null) continue;

                                var atomOutput = atom.getOutput(contactName);
                                if (atomOutput != null)
                                {
                                        if (!atomOutput.hasLink(port.internal))
                                        {
                                                atomOutput.link(port.internal, true);
                                        }
                                }
                        }
                }
        }

        /**
        * Resolve an internal atom by its template ID or runtime ID.
        *
        * @param atomId Template ID (from blueprint) or runtime ID
        * @return Atom instance or null if not found
        */
        private function _resolveInternalAtom(atomId:String):Atom
        {
// Try runtime ID first
                var obj = internalAtoms.get(atomId);
                if (obj != null) return cast(obj, Atom);

// Try resolving template ID → runtime ID
                var runtimeId = _idMap.get(atomId);
                if (runtimeId != null)
                {
                        obj = internalAtoms.get(runtimeId);
                        if (obj != null) return cast(obj, Atom);
                }

                return null;
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
                // ══════════════════════════════════════════════════════════════════════════
                // v2.9: STABLE NAMING MIGRATION (Inlet/Arrival/Departure/Outlet).
                // One-shot in-place conversion of legacy pin names (incoming_N /
                // outgoing_N internals + semantic externals like "Button_out") to
                // the stable positional scheme. Idempotent; legacy names are kept
                // as session aliases (PortNaming) so parents still referencing
                // them resolve and heal in place.
                // ══════════════════════════════════════════════════════════════════════════
                var migratedStable:Bool = core.logic.PortNaming.migrateBlueprintInPlace(blueprint);
                if (migratedStable)
                {
                        utils.Trap.log("MIG", "blueprint migrated to stable naming: " + (blueprint.id != null ? blueprint.id : "?"));
                }

                for (pinDef in blueprint.pins)
                {
                        if (pinDef == null || pinDef.name == null) continue;

                        var portType:ContactType = pinDef.type;

// v2.0: Read externalName from PinDef (if available)
                        var externalName:String = pinDef.name; // default to internal name
// Get feild straigh forward
                        var extDyn = Reflect.field(pinDef, "externalName");
                        if (extDyn != null && Std.string(extDyn) != "")
                        {
                                externalName = Std.string(extDyn);
                        }

// v2.0: Create port with dual naming
// pinDef.name = internalName (for Assembly.ports map lookup)
// externalName = visible on parent schema
                        var port = new ConductorPort(externalName, portType, pinDef.name, pinDef.defaultValue);
// v1.2 (Port Labels): mirror the cosmetic label from PinDef (absent on
// legacy in-memory blueprints → keeps the ConductorPort default "port")
                        var lblDyn = Reflect.field(pinDef, "label");
                        if (lblDyn != null && Std.string(lblDyn) != "")
                        {
                                port.label = Std.string(lblDyn);
                        }
                        ports.set(pinDef.name, port); // key = internalName
                }
                // v2.9: rebuild legacy aliases AFTER ports exist (map holds ports)
                _rebuildLegacyPortAliases();
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
// v2.10 (Ghost AtomDef Self-Heal): dead AtomDefs (unresolvable typeId) are
// collected here and removed from the blueprint AFTER the iteration loop —
// never mutate blueprint.internalAtoms while iterating it with for-in.
                var deadDefs:Array<AtomDef> = null;
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

// Restore saved state (this also restores displayName from JSON)
                                if (atomDef.values != null)
                                {
                                        instance.restoreState(atomDef.values);
                                }

// ═══════════════════════════════════════════════════════════════════
// v2.1: Register instance displayName in NamingService (GLOBAL uniqueness)
// ═══════════════════════════════════════════════════════════════════
// After restoreState, displayName may be:
//   (a) A user-customized name loaded from JSON
//   (b) The default (= type, e.g. "Button")
//
// In both cases we MUST ensure global uniqueness across ALL Assemblies
// in the application. If the loaded name conflicts with an already-
// registered atom (e.g. duplicate name in saved file, or duplicate
// across two assemblies loaded into the same session), NamingService
// appends "_N" automatically.
//
// After this call, instance.displayName is the globally-unique final name.
// ═══════════════════════════════════════════════════════════════════
                                var desiredName:String = (instance.displayName != null)
                                                                                 ? instance.displayName
                                                                                 : instance.type;
                                var finalName:String = core.logic.NamingService.resolveUniqueInstanceName(
                                                                                   desiredName, newInstanceID);
                                if (finalName != desiredName)
                                {
                                        trace('NamingService: Resolved conflict "$desiredName" → "$finalName" for atom ${newInstanceID}');
                                }
                                instance.displayName = finalName;
                                core.logic.NamingService.registerInstanceName(finalName, newInstanceID);

// Register active drivers
                                var bpDef = AtomRegistry.get(atomDef.typeId);
                                if (bpDef != null && bpDef.isActive && !bpDef.isNative)
                                {
                                        DriverManager.getInstance().register(instance);
                                }
                        }
                        else
                        {
// v2.10 (Ghost AtomDef Self-Heal): AssemblyFactory.createAtom returned
// null — the typeId is not resolvable (createAtom returns null ONLY for a
// missing blueprint). Typical origins: an assembly deleted by an undone
// grouping in a pre-v3.18 build (undo removed the AtomRegistry entry and
// deleted the .atom file, but the AtomDef leaked into the save), or a
// missing library file. Drop the dead AtomDef and its dangling _idMap
// entry so it is NOT re-serialized by the next save. Connections to it
// (if any) are cleaned by the v1.5 Ghost Connection Safety Net.
                                trace('WARN: [self-heal] Dropping dead atomDef "${atomDef.instanceId}" — typeId "${atomDef.typeId}" not found in AtomRegistry');
                                _idMap.remove(atomDef.instanceId);
                                if (deadDefs == null) deadDefs = [];
                                deadDefs.push(atomDef);
                        }
                }
                if (deadDefs != null)
                {
                        for (d in deadDefs) blueprint.internalAtoms.remove(d);
                        trace('WARN: [self-heal] Removed ${deadDefs.length} dead AtomDef(s) from "${blueprint.id}"');
                }
        }

// ========================================================================
// INTERNAL CONNECTIONS
// ========================================================================
        /**
        * Create internal connections between atoms.
        *
        * v1.5 SAFETY NET: Removes ghost connections (referencing non-existent atoms)
        * from the blueprint at load time to prevent re-saving corrupted data.
        *
        * v1.2 FIX: Calls _ensureInternalAtomConnectedToPort() for SELF connections.
        *
        * Uses suppressPropagation=true to prevent oscillation during initialization.
        * Connections are later activated by _processPendingSignals().
        */
        private function _createInternalConnections():Void
        {
                if (blueprint == null || blueprint.internalConnections == null) return;

                // v2.5: dump the connection table this instance is built from.
                utils.Trap.log("ASM-CONN", "Assembly(" + this.id + ") bp connections=" + blueprint.internalConnections.length);
                for (conn in blueprint.internalConnections)
                {
                        utils.Trap.log("ASM-CONN", "  " + conn.from.atomId + "." + conn.from.contactName + " -> " + conn.to.atomId + "." + conn.to.contactName);
                }


// v1.5: Track connections to remove (avoid modifying array during iteration)
                var connectionsToRemove:Array<core.data.Blueprint.ConnectionDef> = [];

                for (conn in blueprint.internalConnections)
                {
                        var fromContact = resolveContact(conn.from);
                        var toContact = resolveContact(conn.to);

                        if (fromContact == null)
                        {
                                trace('ERROR: Assembly(${this.id}): fromContact NULL for ${conn.from.atomId}.${conn.from.contactName}');
                                connectionsToRemove.push(conn);
                                continue;
                        }
                        if (toContact == null)
                        {
                                trace('ERROR: Assembly(${this.id}): toContact NULL for ${conn.to.atomId}.${conn.to.contactName}');
                                connectionsToRemove.push(conn);
                                continue;
                        }
                        if (fromContact.type == null)
                        {
                                trace('ERROR: Assembly(${this.id}): fromContact.type is NULL for ${conn.from.atomId}.${conn.from.contactName}');
                                trace('  Contact ID: ${fromContact.id}');
                                trace('  Contact name: ${fromContact.name}');
                                trace('  Contact owner: ${fromContact.owner != null ? fromContact.owner.id : "null"}');
                                connectionsToRemove.push(conn);
                                continue;
                        }
                        if (toContact.type == null)
                        {
                                trace('ERROR: Assembly(${this.id}): toContact.type is NULL for ${conn.to.atomId}.${conn.to.contactName}');
                                trace('  Contact ID: ${toContact.id}');
                                trace('  Contact name: ${toContact.name}');
                                trace('  Contact owner: ${toContact.owner != null ? toContact.owner.id : "null"}');
                                connectionsToRemove.push(conn);
                                continue;
                        }

// ═══════════════════════════════════════════════════════════════════
// v2.0 FIX: REMOVED _ensureInternalAtomConnectedToPort() calls.
// They caused signal duplication (infinite loops) because resolveContact()
// + fromContact.link(toContact) already perfectly handles the connection.
// ═══════════════════════════════════════════════════════════════════

// Link with suppressed propagation (prevents oscillation during init)
                        fromContact.link(toContact, true);
                        utils.Trap.log("ASM-LINK", "linked " + conn.from.atomId + "." + conn.from.contactName + " -> " + conn.to.atomId + "." + conn.to.contactName);
                }

// ══════════════════════════════════════════════════════════════════
// v1.5 SAFETY NET: Remove ghost connections from blueprint
// ══════════════════════════════════════════════════════════════════
                for (conn in connectionsToRemove)
                {
                        _sanitizeConnection(conn);
                }
        }

        /**
        * v1.5 SAFETY NET: Remove a broken connection from the blueprint.
        *
        * Called when resolveContact() fails during _createInternalConnections().
        * This is the LAST LINE OF DEFENSE against ghost connections.
        *
        * Why not just skip? Because skipping leaves the broken connection in
        * blueprint.internalConnections, which gets re-saved on next project save,
        * perpetuating the corruption indefinitely.
        *
        * @param conn The broken connection to remove
        */
        private function _sanitizeConnection(conn:core.data.Blueprint.ConnectionDef):Void
        {
                if (blueprint == null || blueprint.internalConnections == null) return;

                var removed = blueprint.internalConnections.remove(conn);
                if (removed)
                {
                        trace('  🔧 SAFETY NET: Removed ghost connection: ' +
                        '${conn.from.atomId}.${conn.from.contactName} → ' +
                        '${conn.to.atomId}.${conn.to.contactName}');
                }
        }

        /**
        * v1.4 FIX / v2.0 UPDATE: Ensure internal atom is connected to assembly port.
        *
        * v2.0 FIX: Clean Gateway Topology.
        * Removed direct port.external → atom.input link. That caused "Delta Topology"
        * signal duplication (infinite loops) that froze the app.
        * The correct gateway flow (port.external → port.internal → atom.input)
        * is already perfectly handled by _createInternalConnections() via resolveContact().
        * This method is kept for API compatibility but safely neutralized for INPUTs.
        *
        * @param portName Name of the assembly port
        * @param portType Type of the port (INPUT or OUTPUT)
        */
        private function _ensureInternalAtomConnectedToPort(portName:String, portType:ContactType):Void
        {
// v2.0 FIX: Neutralized. Gateway flow is handled by _createInternalConnections via resolveContact.
// Kept for API compatibility, but safely disabled to prevent loops.
                return;

                /*
                // Весь старый код метода отсюда и ниже можно оставить или удалить,
                // он никогда не выполнится из-за return; выше
                if (internalAtoms == null) return;
                var port = ports.get(portName);
                if (port == null) return;

                for (id in internalAtoms.keys())
                {
                var atom:Atom = cast internalAtoms.get(id);
                if (atom == null) continue;

                if (portType == OUTPUT)
                {
                // OUTPUT: atom.output → port.internal (standard link)
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
                // v2.0 FIX: Clean Gateway Topology
                // We do NOT create direct port.external → atom.input links here.
                // That caused "Delta Topology" signal duplication (infinite loops).
                // The correct gateway flow (port.external → port.internal → atom.input)
                // is already perfectly handled by _createInternalConnections() via resolveContact().
                // We safely rely on that established link.
                // ═══════════════════════════════════════════════════════
                break;
                }
                }
                */
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
        * v2.1 FIX: For nested assemblies, searches by externalName first,
        * then falls back to internalName. This ensures that when parent
        * blueprint references a port by its external name (e.g., "MiniAudioAtom_gain"),
        * we can find the correct port even though Assembly.ports is keyed by
        * internal name (e.g., "incoming_1").
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

// ═══════════════════════════════════════════════════════════
// v2.1 FIX: Search by externalName first, then internalName
// ══════════════════════════════════════════════════════════
// Parent blueprint uses externalName (e.g., "MiniAudioAtom_gain")
// but Assembly.ports is keyed by internalName (e.g., "incoming_1")
                                var port:ConductorPort = null;

// First try: search by externalName
                                for (p in asm.ports)
                                {
                                        if (p != null && p.externalName == point.contactName)
                                        {
                                                port = p;
                                                break;
                                        }
                                }

// Fallback: search by internalName (for backward compatibility)
                                if (port == null)
                                {
                                        port = asm.ports.get(point.contactName);
                                }
                                // ══════════════════════════════════════════════════════════
                                // v2.9: LEGACY ALIAS — pre-stable-naming port name
                                // ("Button_out" / "incoming_1") resolving to the migrated
                                // stable port. On hit we HEAL the connection definition in
                                // place: the stale name disappears from this blueprint and
                                // from the next disk save.
                                // ══════════════════════════════════════════════════════════
                                if (port == null)
                                {
                                        port = asm.getPortByAnyName(point.contactName);
                                        if (port != null)
                                        {
                                                utils.Trap.log("MIG-HEAL", "parent ref \"" + point.contactName + "\" -> \"" + port.externalName + "\" on " + asm.id);
                                                point.contactName = port.externalName;
                                        }
                                }

                                if (port == null)
                                {
                                        trace('ERROR: Port "${point.contactName}" NOT FOUND on Assembly ${atom.name}(${realAtomId})');
                                        trace('  Available external ports: ${[for(k in asm.ports.keys()) asm.ports.get(k).externalName]}');
                                        trace('  Available internal ports: ${[for(k in asm.ports.keys()) k]}');
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

        // ========================================================================
        // STABLE NAMING v2.9 (Inlet/Arrival/Departure/Outlet)
        // ========================================================================
        /**
        * v2.9: Rebuild the legacy port-name alias map from the session cache
        * (PortNaming). Called after ports are (re)created — every instance of
        * the same blueprint derives the same aliases, so parents referencing
        * pre-migration names resolve regardless of construction order.
        */
        private function _rebuildLegacyPortAliases():Void
        {
                _legacyPortNames = new Map<String, ConductorPort>();
                if (blueprint == null || blueprint.id == null) return;
                var aliases = core.logic.PortNaming.getLegacyAliases(blueprint.id);
                if (aliases == null) return;
                for (oldName in aliases.keys())
                {
                        var p = ports.get(aliases.get(oldName));
                        if (p != null) _legacyPortNames.set(oldName, p);
                }
        }

        /**
        * v2.9: Resolve a port by ANY known name — internal name, external
        * name, or a legacy (pre-stable-naming) name. Used by parent-side
        * resolution paths to bridge references that predate migration.
        */
        public function getPortByAnyName(name:String):ConductorPort
        {
                if (name == null) return null;
                var p = ports.get(name);
                if (p != null) return p;
                for (port in ports)
                {
                        if (port != null && port.externalName == name) return port;
                }
                if (_legacyPortNames != null)
                {
                        return _legacyPortNames.get(name);
                }
                return null;
        }

        /**
        * v2.9: Human-readable beneficiary of a wall port — the internal atom
        * contact it serves. Derived LIVE from blueprint connections (nothing
        * to persist). Powers the port/wire hover tooltips that replaced the
        * old semantic port names.
        *
        * @param internalName Port key ("Arrival_3" / "Departure_1")
        * @return "Button.set"-style label, or null if the port feeds nothing
        */
        public function getPortBeneficiary(internalName:String):String
        {
                if (blueprint == null || blueprint.internalConnections == null) return null;
                if (!ports.exists(internalName)) return null;
                for (conn in blueprint.internalConnections)
                {
                        if (conn == null) continue;
                        if (conn.from != null && conn.from.atomId == "SELF" && conn.from.contactName == internalName)
                        {
                                var atom = _resolveInternalAtom(conn.to.atomId);
                                if (atom != null) return _beneficiaryLabel(atom, conn.to.contactName);
                        }
                        else if (conn.to != null && conn.to.atomId == "SELF" && conn.to.contactName == internalName)
                        {
                                var atom = _resolveInternalAtom(conn.from.atomId);
                                if (atom != null) return _beneficiaryLabel(atom, conn.from.contactName);
                        }
                }
                return null;
        }

        /**
        * v2.9: Beneficiary lookup by EXTERNAL port name ("Inlet_3"/"Outlet_1")
        * — the parent-side view used by NodeView port tooltips.
        */
        public function getPortBeneficiaryByExternalName(externalName:String):String
        {
                for (port in ports)
                {
                        if (port != null && port.externalName == externalName)
                        {
                                return getPortBeneficiary(port.internalName);
                        }
                }
                return null;
        }

        /** v2.9: "DisplayName.contactName" label for tooltip text. */
        private function _beneficiaryLabel(atom:Atom, contactName:String):String
        {
                if (atom == null || contactName == null) return null;
                var dn = (atom.displayName != null && atom.displayName != "") ? atom.displayName : atom.type;
                return dn + "." + contactName;
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

        /**
        * Adds a new gateway port to this assembly.
        *
        * v2.1 FIX: Now accepts an explicit externalName parameter.
        *
        * Previously addPort() created the ConductorPort with externalName = name,
        * which meant that for ports named "incoming_1" the externalName was also
        * "incoming_1" — and there was no way to give it a semantic name like
        * "Button_out". The externalName only got set much later (or never) if
        * the user happened to exit the assembly, and even then only if
        * refreshExternalPortNames() was called.
        *
        * Now callers can pass externalName explicitly:
        *   - AddPortCommand / context-menu "Add Port" → pass a default semantic
        *     name based on port type ("in_N" / "out_N") or a user-supplied name
        *   - refreshExternalPortNames() reconstructs the port with a new
        *     externalName when an atom gets connected
        *
        * If externalName is null, falls back to name (backward compat).
        *
        * @param name         Internal port name (used as map key, SELF.xxx in
        *                     blueprint.internalConnections inside this assembly)
        * @param type         INPUT / OUTPUT / BIDIRECTIONAL
        * @param defaultValue Optional default value
        * @param externalName Optional name visible on parent schema. If null,
        *                     defaults to `name`.
        * @return The created ConductorPort, or null if max ports reached or
        *         name already exists.
        */
        public function addPort(name:String, type:ContactType, defaultValue:Dynamic = null, ?externalName:String = null):ConductorPort
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

// v2.1: Build PinDef with externalName (dual naming)
// v1.2 (Port Labels): every NEW port starts with the default cosmetic
// label "port"; the user renames it inline in either editor.
                var extName = (externalName != null && externalName != "") ? externalName : name;
                var pinDef:PinDef = { name: name, type: type, defaultValue: defaultValue, externalName: extName, label: "port" };
                if (blueprint.pins != null) blueprint.pins.push(pinDef);

// v2.1: Create ConductorPort with dual naming (externalName, type, internalName=name)
                var port = new ConductorPort(extName, type, name, defaultValue);
                port.label = pinDef.label; // v1.2: runtime mirror
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
// v1.10: Rebuild internal connections to include new port in existing SELF links
                rebuildInternalConnections();
                Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
                return port;
        }

        /**
        * v1.11: Removes a port and its internal connections, then notifies the parent
        * assembly via PORT_REMOVED so that external wires are cleaned up.
        */
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

// v3.3 (Episod G-3): capture identity BEFORE dispose — the impulse must
// carry the EXTERNAL name (parent-side wires reference "Inlet_N", not the
// internal "Arrival_N") and the blueprint id (blueprints are shared: every
// instance of this template loses the port, so sibling instances' wires
// must be cleaned too).
                var removedExternalName:String = port.externalName;
                var removedBlueprintId:String = (blueprint != null) ? blueprint.id : null;

                port.dispose();
                ports.remove(name);
// v1.10: Rebuild internal connections after removing port
                rebuildInternalConnections();

// ═══════════════════════════════════════════════════════════════════
// v3.3 (Episod G-3): ORDER MATTERS — PORT_REMOVED fires FIRST so the
// parent-side wire cleanup (Main.onPortRemoved) completes BEFORE
// ASSEMBLY_PORTS_CHANGED triggers the visual rebuilds (background parent
// editor, the child's NodeView, the v2.12 auto-heal). Rebuilding from a
// half-cleaned blueprint would redraw the deleted wire — the "hanging
// wire" bug this episode fixes.
// ═══════════════════════════════════════════════════════════════════
                Impulsys.quickEmit(EventType.PORT_REMOVED, {
                        assemblyId: this.id,
                        portName: name,
                        externalName: removedExternalName,
                        blueprintId: removedBlueprintId
                });
                Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: this.id });
        }

// ========================================================================
// v1.10: REBUILD INTERNAL PORT-TO-PORT CONNECTIONS
// ========================================================================
        /**
        * Rebuilds all internal connections between ports (SELF→SELF) based on
        * the current blueprint.internalConnections.
        *
        * This method:
        * 1. Removes all existing links between internal contacts of ports,
        *    but preserves links between external and internal contacts of the same port
        *    (those are managed by _updatePortLinks()).
        * 2. Calls _createInternalConnections() to recreate links from blueprint.
        * 3. Calls _updatePortLinks() to re-establish external↔internal links
        *    (important after port changes).
        *
        * The removal is done using only public Contact API (hasLink / unlink)
        * to avoid accessing private fields.
        *
        * Call this method whenever the blueprint's internal connections change
        * (e.g., after adding/removing atoms, adding/removing connections, or
        * after hot-reload).
        */
// ========================================================================
// REBUILD INTERNAL CONNECTIONS (v2.1 Crash Protection)
// ========================================================================
        /**
        * Rebuilds all internal connections between ports (SELF→SELF) based on
        * the current blueprint.internalConnections.
        *
        * v2.1 FIX: Added !isDisposed checks to prevent Use-After-Free crashes
        * during deep nesting pop() operations when TickGenerator holds stale refs.
        */
        public function rebuildInternalConnections():Void
        {
// 1. Collect all port internal contacts
                var portInternals = [];
                for (port in ports)
                {
                        if (port != null && port.internal != null && !port.internal.isDisposed)
                        {
                                portInternals.push(port.internal);
                        }
                }

// 2. Remove all links between port internals (but NOT with external contacts)
                for (i in 0...portInternals.length)
                {
                        var contactA = portInternals[i];
                        if (contactA == null || contactA.isDisposed) continue;

                        for (j in 0...portInternals.length)
                        {
                                if (i == j) continue;
                                var contactB = portInternals[j];
                                if (contactB == null || contactB.isDisposed) continue;

// === FIX: Safe unlink ===
                                if (contactA.hasLink(contactB))
                                {
                                        contactA.unlink(contactB);
                                }
                        }
                }

// 3. Recreate internal connections from blueprint
                _createInternalConnections();

// 4. Re-establish external↔internal port links (logic mode)
                _updatePortLinks();
        }

// ========================================================================
// STATE SERIALIZATION
// ========================================================================
        /**
        * Save state for persistence.
        *
        * v2.0 FIX: Uses TEMPLATE IDs for internalStates keys.
        * This guarantees that nested states survive JSON save/load cycles,
        * because Runtime IDs change on every application restart, but Template IDs are stable.
        */
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
// v2.0 FIX: Map Runtime ID -> Template ID for stable JSON serialization
                                                var templateId = getTemplateId(runtimeId);
                                                Reflect.setField(states, templateId, state);
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
// ═══════════════════════════════════════════════════════════════════
// v2.1 FIX: Preserve displayName in Assembly persistent state.
// ═══════════════════════════════════════════════════════════════════
// Previously Assembly override DISCARDED baseState.displayName, which
// meant nested Assembly instances lost their custom display name on
// save/load. Now we merge displayName into the saved state so it
// survives JSON round-trips exactly like Atom.getPersistentState()
// does for leaf atoms.
// ═══════════════════════════════════════════════════════════════════
                var hasDisplayName:Bool = (baseState != null && baseState.displayName != null);
                if (hasStates || (baseState != null && baseState.isLogic == true) || hasDisplayName)
                {
                        var result:Dynamic =
                        {
                                isLogic: baseState != null ? baseState.isLogic : false,
                                internalStates: hasStates ? states : null
                        };
                        if (hasDisplayName)
                        {
                                result.displayName = baseState.displayName;
                        }
                        return result;
                }
                return null;
        }

        /**
        * Restore state from saved data.
        *
        * v2.0 FIX: Looks up states using TEMPLATE IDs.
        */
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
// v2.0 FIX: Map Runtime ID -> Template ID to find the saved state
                                var templateId = getTemplateId(runtimeId);
                                if (Reflect.hasField(states, templateId))
                                {
                                        var atom:Atom = cast internalAtoms.get(runtimeId);
                                        if (atom != null)
                                        {
                                                var atomState = Reflect.field(states, templateId);
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
// ═══════════════════════════════════════════════════════════════════
// v1.11 (v4.4): SILENT DISPOSE — suspend TickGenerator for the whole
// teardown cascade.
// ═══════════════════════════════════════════════════════════════════
// Assembly.dispose() recursively disposes internal atoms and ports.
// Contact.dispose() unlinks and scheduled propagations may still sit in
// TickGenerator queues; a task firing mid-teardown (between
// internalAtoms.clear() and ports.clear()) dereferences half-dead state.
// Suspending the generator freezes process() so the cascade runs in
// silence; try/finally guarantees resume even on exception — a stuck
// suspend would freeze the whole simulation permanently.
// NOTE: when called from EditorContext.pop() v2.6 the outer topology
// lock already defers propagations; this suspend is the belt-and-
// suspenders layer for ALL other dispose call sites (hard reset,
// GroupAtoms Phase 4, project reload).
utils.Trap.log("ASM-DISPOSE", "dispose enter: id=" + this.id);
        TickGenerator.getInstance().suspend();
                try {
                        // Dispose internal atoms
                        var keys = [for (k in internalAtoms.keys()) k];
                        for (key in keys) {
                                var obj = internalAtoms.get(key);
                                if (obj != null) {
                                        utils.Trap.log("ASM-DISPOSE", "atom down: " + key + " (" + Type.getClassName(Type.getClass(obj)) + ")");
                                        if (Std.isOfType(obj, IDisposable)) {
                                                try {
                                                        cast(obj, IDisposable).dispose();
                                                } catch (e:Dynamic) {
                                                        trace('Error: $e');
                                                }
                                        }
                                }
                        }
                        internalAtoms.clear();
                        utils.Trap.log("ASM-DISPOSE", "internalAtoms cleared");
                        internalAtoms = null;

                        // Dispose ports
                        var portKeys = [for (k in ports.keys()) k];
                        for (key in portKeys) {
                                var port = ports.get(key);
                                if (port != null) port.dispose();
                        }
                        ports.clear();
                        utils.Trap.log("ASM-DISPOSE", "ports cleared");
                        ports = null;

                        super.dispose();
                        utils.Trap.log("ASM-DISPOSE", "super.dispose done");
                        
                        utils.Trap.log("ASM-DISPOSE", "teardown OK -> resume");
                        // Если всё прошло успешно, возобновляем генератор
                        TickGenerator.getInstance().resume();
                } catch (e:Dynamic) {
                        // Если произошла ошибка, ВСЁ РАВНО возобновляем генератор
                        utils.Trap.log("ASM-DISPOSE", "EXCEPTION in dispose: " + e);
                        TickGenerator.getInstance().resume();
                        // Пробрасываем ошибку дальше, чтобы симуляция знала о сбое
                        throw e;
                }
        }
}
