package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.base.IDisposable;
import core.base.AssemblyFactory;
import core.logic.Impulsys;
import core.logic.Impulse;
import core.logic.EventType;
import core.types.ContactType;
import library.AtomRegistry;

/**
* ╔═══════════════════════════════════════════════════════════════════════════╗
* ║                      GROUP ATOMS COMMAND v3.15                            ║
* ║         (BP-SSOT Consistency + Parent Port Collision Fix + DeviceView     ║
* ║          Lifecycle Cleanup + Template ID as instanceId + Unique Names)    ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Command to group selected atoms into a new Assembly.                     ║
* ║  Supports full Undo/Redo with complete state restoration.                 ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ╠═════════════════════════════════════════════════════════════════════════════╣
* ╠═════════════════════════════════════════════════════════════════════════════╣
* ║                     v3.14 CHANGES (PHASE 2 Restored — undo fix)           ║
* ╠═════════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  CONFIRMED BUG: the v3.11 BP-SSOT refactor dropped ALL snapshot           ║
* ║  capture calls (addRemovedAtom / addRemovedInternalConnection /           ║
* ║  addRemovedExternalConnection / setSelectedNodeIds). undo() then          ║
* ║  aborted at validate() with "No atoms captured for restore" —             ║
* ║  grouping undo was silently dead (trace-only failure).                    ║
* ║                                                                           ║
* ║  FIX: PHASE 2 (SNAPSHOT BEFORE-STATE) restored in executeGrouping         ║
* ║  right after the atomsToMove guard. Together with GroupAtomsSnapshot      ║
* ║  v2.1 (Reflect.copy — captures values + visualMode), undo fully           ║
* ║  restores atoms, connections and configuration.                           ║
* ║                                                                           ║
* ║                     v3.13 CHANGES (Grouping Value Preservation)           ║
* ╠═════════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  NOTE: no mergeLiveStateInto() is needed — the v3.8 Phase-3               ║
* ║  live-state capture (liveAtom.getPersistentState() into                   ║
* ║  newInternalAtoms) + driver getPersistentState() overrides                ║
* ║  (ComPortAtom v3.2+) already preserve configuration through               ║
* ║  grouping. Field proof (crash_trap.log 23:58:11): grouping →              ║
* ║  dispose → auto-reopen (wasOpen=true) → opened COM17.                     ║
* ║                                                                           ║
* ║  BUG-1 FIXED: saveNewAssembly() wrote the .atom file with atoms           ║
* ║  stripped of `values` — a crash/restart right after grouping              ║
* ║  lost the live configuration (ComPort COM17 → COM1 on reload).            ║
* ║  values are now serialized with every atom.                               ║
* ║                                                                           ║
* ║  BUG-2 FIXED: undo() restored atoms with STRIPPED AtomDefs (no            ║
* ║  values, no visualMode) and recreated instances without                   ║
* ║  initialState. Original AtomDef objects are now pushed back               ║
* ║  as-is; instances are recreated with atomDef.values as                    ║
* ║  initialState (load-symmetric with execute()).                            ║
* ║                                                                           ║
* ║                     v3.12 CHANGES (Parent Port Name Collision Fix)        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  Pre-populating usedExternalNames with parent's port externalNames caused ║
* ║  new ports to get "_2" suffixes (e.g., "Pass_in_2"), breaking parent's    ║
* ║  blueprint connections which still referenced the original "Pass_in".     ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  Removed parent port pre-population. Parent ports are being absorbed/     ║
* ║  replaced anyway. Collision counter now only handles TRUE collisions      ║
* ║  (e.g., two atoms both named "Pass" both with contact "in" inside the     ║
* ║  selection).                                                              ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.11 CHANGES (Blueprint SSOT Consistency)            ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  Phase 5 saved Template ID to AtomDef, but Phase 6 saved Runtime ID to    ║
* ║  ConnectionDef. This inconsistency broke syncConnectionsToTemplateIds()   ║
* ║  and caused resolveContact to fail after reconstruction.                  ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  Phase 6 now normalizes BOTH sides of the connection to Template ID.      ║
* ║  resolveContact() and resolveContactInParent() both use _idMap            ║
* ║  (template→runtime) to find the instance. This enforces Blueprint-as-     ║
* ║  Single-Source-of-Truth (BP-SSOT).                                        ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.10 CHANGES (Atom Mapping Registration)             ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  Added _assembly.registerAtomMapping(newTypeId, newInstance.id) to ensure ║
* ║  the newly created assembly can be resolved by its Template ID.           ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.8 CHANGES (State Preservation & Cleanup)           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  - ADDED: Copy `values` field to preserve displayName + isLogic state.    ║
* ║  - ADDED: Properly dispose atoms BEFORE removing from internalAtoms to    ║
* ║    release NamingService slots and native drivers.                        ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.7 CHANGES (Unique Assembly Name)                   ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  Newly grouped assemblies were always named "Custom Assembly", leading    ║
* ║  to duplicate displayNames across the project hierarchy.                  ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  The command now accepts _isNameTakenGlobally callback and uses           ║
* ║  AssemblyFactory.generateUniqueDisplayName() to assign a globally unique  ║
* ║  name to the new assembly (e.g., "CustomAssembly", "CustomAssembly_1").   ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.5 CHANGES (DeviceView Lifecycle Cleanup)           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  When GroupAtomsCommand was triggered from the Device Panel, the widgets  ║
* ║  of the selected atoms "disappeared" visually but their DeviceViews       ║
* ║  remained alive in DeviceViewRegistry, still subscribed to the atoms'     ║
* ║  Contacts. After the atoms were absorbed into the new assembly and the    ║
* ║  old instances eventually disposed, those stale subscriptions caused      ║
* ║  use-after-free when signals propagated.                                  ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  In Phase 4 (MODIFY PARENT BLUEPRINT), BEFORE removing each atom from     ║
* ║  _assembly.internalAtoms, call:                                           ║
* ║    DeviceViewRegistry.getInstance().remove(atomId, true)                  ║
* ║  This disposes the widget (deactivates subscriptions, removes from any    ║
* ║  parent display list) and clears the registry entry. The new assembly     ║
* ║  gets fresh DeviceViews via NodeView.acquireWidget() when its NodeView    ║
* ║  is created — load-symmetric with project load.                           ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.4 CHANGES (External Name Fix)                      ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  resolveExternalPortName() used Reflect.hasField() to check for           ║
* ║  externalName in PinDef. However, Reflect.hasField() does NOT work        ║
* ║  reliably for Haxe typedef structures (anonymous objects).                ║
* ║                                                                           ║
* ║  This caused the method to fall back to returning pin.name (internalName) ║
* ║  instead of pin.externalName, resulting in external connections using     ║
* ║  the WRONG contact name.                                                  ║
* ║                                                                           ║
* ║  SYMPTOM:                                                                 ║
* ║  After grouping atoms, wires connected to the new Assembly were invisible ║
* ║  because WireRenderer couldn't find ports by internalName in NodeView     ║
* ║  (which is keyed by externalName).                                        ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  - Replaced Reflect.hasField() with direct field access                   ║
* ║  - Added null-safety check for optional externalName field                ║
* ║  - Added detailed comments explaining internal vs external name usage     ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║              CONTACT NAME RESOLUTION RULES (CRITICAL)                     ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  When creating connections in PARENT blueprint (external connections):    ║
* ║  ──────────────────────────────────────────────────────────────────────── ║
* ║  ✓ Use EXTERNAL name (e.g., "PassThrough_1_in")                           ║
* ║  ✓ Because parent sees Assembly as an atom with external port names       ║
* ║  ✓ atom.getInput(externalName) works because Contact.name = externalName  ║
* ║  ✓ NodeView.inputPorts keyed by externalName                              ║
* ║  ✓ WireRenderer.getWirePoint() uses externalName from blueprint           ║
* ║                                                                           ║
* ║  When creating connections INSIDE assembly (internal connections):        ║
* ║  ──────────────────────────────────────────────────────────────────────── ║
* ║  ✓ Use INTERNAL name (e.g., "incoming_1")                                 ║
* ║  ✓ Because inside assembly we connect to the wall (port.internal)         ║
* ║  ✓ Assembly.ports map keyed by internalName                               ║
* ║  ✓ SELF.xxx in blueprint.internalConnections uses internalName            ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.3 CHANGES (Spatial Sorting)                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM:                                                                 ║
* ║  Ports on the Assembly boundary were sorted alphabetically by Atom ID.    ║
* ║  This resulted in a random-looking order that didn't match the visual     ║
* ║  layout of the schematic (e.g., an atom at the bottom could end up        ║
* ║  with a port at the top of the assembly).                                 ║
* ║                                                                           ║
* ║  SOLUTION:                                                                ║
* ║  - Ports are now sorted by the Y-coordinate of the internal atom          ║
* ║    they connect to (Top -> Bottom).                                       ║
* ║  - Fallback to X-coordinate (Left -> Right) if Y is identical.            ║
* ║  - Fallback to Contact Name for deterministic order.                      ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  Atom A (Y=100)  ──► Port 1 (Top)                                   │  ║
* ║  │                                                                     │  ║
* ║  │  Atom B (Y=300)  ──► Port 2 (Middle)                                │  ║
* ║  │                                                                     │  ║
* ║  │  Atom C (Y=500)  ──► Port 3 (Bottom)                                │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.0 CHANGES (Semantic Naming)                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PORT NAMING CONVENTION:                                                  ║
* ║  ────────────────────────                                                 ║
* ║                                                                           ║
* ║  External name (parent sees):  "{AtomDisplayName}_{ContactName}"          ║
* ║  Internal name (wall inside):  "incoming_N" (INPUT) / "outgoing_N" (OUT)  ║
* ║                                                                           ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │  PARENT SCHEMA:                                                     │  ║
* ║  │                                                                     │  ║
* ║  │  Button [Out] ──wire──► Assembly [PassThrough_1_in]                 │  ║
* ║  │                                                                     │  ║
* ║  │                    Assembly [PassThrough_1_out] ──wire──► LED [In]  │  ║
* ║  │                                                                     │  ║
* ║  │  INSIDE ASSEMBLY:                                                   │  ║
* ║  │                                                                     │  ║
* ║  │  ┌── incoming_1 ──► PassThrough_1 [In]                              │  ║
* ║  │  │                                                                  │  ║
* ║  │  │     PassThrough_1 [Out] ──► outgoing_1 ──┘                       │  ║
* ║  │  │                                                                  │  ║
* ║  │  └───────────────────────────────────────────────────────────────── │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
// ═══════════════════════════════════════════════════════════════════════════
// v3.15 CHANGES (Naming & Integrity pack, 2026-08-24)
// ═══════════════════════════════════════════════════════════════════════════
//
//  CIRCULAR REFERENCE GUARD resurrected: validateNoCircularReference()
//  existed since v3.x but was never called (dead code — grep = 0 call
//  sites). Now invoked at the top of executeGrouping(); also upgraded
//  with a blueprint IDENTITY check (alias-proof, same idea as the
//  Assembly v2.6 / CreateAtomCommand v1.4 guards).
//
class GroupAtomsCommand extends Command
{
// ========================================================================
// CONSTANTS
// ========================================================================
	private static inline var MAX_NESTING_DEPTH:Int = 10;

// ========================================================================
// DEPENDENCIES
// ========================================================================
	private var _blueprint:Blueprint;
	private var _assembly:Assembly;
	private var _selectedNodeIds:Array<String>;

	private var _isNameTakenGlobally:(String, ?String) -> Bool; // v3.7: Global name uniqueness checker

// ========================================================================
// SNAPSHOT FOR UNDO
// ========================================================================
	private var _snapshot:GroupAtomsSnapshot;
	private var _isExecuted:Bool = false;
	private var _isUndone:Bool = false;

// ========================================================================
// CONSTRUCTOR
// ========================================================================
	public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>, ?isNameTakenGlobally:(String, ?String) -> Bool)
	{
		super();
		_blueprint = blueprint;
		_assembly = assembly;
		_selectedNodeIds = selectedIds != null ? selectedIds.copy() : [];
		_snapshot = new GroupAtomsSnapshot();
		_isNameTakenGlobally = isNameTakenGlobally;
	}

// ========================================================================
// EXECUTE
// ========================================================================
	override private function executeInternal():Void
	{
		if (_selectedNodeIds == null || _selectedNodeIds.length == 0)
		{
			trace('GroupAtomsCommand: Nothing to group');
			complete();
			return;
		}
		if (!validateNoCircularReference())
		{
			trace('GroupAtomsCommand: Aborted - circular reference detected');
			complete();
			return;
		}
		if (_isUndone)
		{
			redoInternal();
		}
		else
		{
			executeGrouping();
		}
		complete();
	}

	/**
	* Main grouping logic with semantic port naming and spatial sorting.
	*/
	private function executeGrouping():Void
	{
		trace('GroupAtomsCommand v3.12: Grouping ${_selectedNodeIds.length} atoms...');

// ═══ v3.15: CIRCULAR REFERENCE GUARD (resurrected). ═══
// validateNoCircularReference() existed since v3.x but was NEVER called.
// Grouping that would nest the current blueprint inside the selection
// is aborted cleanly BEFORE any mutation.
		if (!validateNoCircularReference())
		{
			trace('GroupAtomsCommand: ABORTED — circular reference detected (would nest "${_blueprint.id}" inside the selection).');
			return;
		}

// =====================================================================
// PHASE 0: ID RESOLUTION (Runtime → Template)
// =====================================================================
		var selectedTemplateIds:Array<String> = [];
		for (runtimeId in _selectedNodeIds)
		{
			var templateId = _assembly.getTemplateId(runtimeId);
			if (selectedTemplateIds.indexOf(templateId) == -1)
			{
				selectedTemplateIds.push(templateId);
			}
		}

// =====================================================================
// PHASE 1: ANALYZE CONNECTIONS
// =====================================================================
		var internalConns:Array<ConnectionDef> = [];
		var externalConns:Array<ConnectionDef> = [];
		var externalConnMeta:Array<{conn:ConnectionDef, isFromSelected:Bool}> = [];

		for (conn in _blueprint.internalConnections)
		{
			var fromTemplateId = conn.from.atomId == "SELF" ? "SELF" : _assembly.getTemplateId(conn.from.atomId);
			var toTemplateId = conn.to.atomId == "SELF" ? "SELF" : _assembly.getTemplateId(conn.to.atomId);
			var fromSelected = selectedTemplateIds.indexOf(fromTemplateId) != -1;
			var toSelected = selectedTemplateIds.indexOf(toTemplateId) != -1;

			if (fromSelected && toSelected)
			{
				internalConns.push(conn);
			}
			else if (fromSelected || toSelected)
			{
				externalConns.push(conn);
				externalConnMeta.push({conn: conn, isFromSelected: fromSelected});
			}
		}

		var atomsToMove:Array<AtomDef> = [];
		for (atomDef in _blueprint.internalAtoms)
		{
			if (selectedTemplateIds.indexOf(atomDef.instanceId) != -1)
			{
				atomsToMove.push(atomDef);
			}
		}

		if (atomsToMove.length == 0)
		{
			trace('ERROR: GroupAtomsCommand: No atoms to move!');
			return;
		}

// =====================================================================
// PHASE 2: SNAPSHOT BEFORE-STATE (v3.14 — RESTORED)
// =====================================================================
// The v3.11 BP-SSOT refactor accidentally removed these capture calls;
// undo() then aborted at validate() with "No atoms captured for
// restore" — grouping undo was silently dead. Capturing again:
//   - selected node ids (for events)
//   - atom defs of everything being moved (Reflect.copy — WITH values,
//     visualMode; see GroupAtomsSnapshot v2.1)
//   - internal connections (between selected atoms — removed)
//   - external connections (selected <-> outside — become ports)
		_snapshot.setSelectedNodeIds(_selectedNodeIds);
		for (atomDef in atomsToMove)
		{
			_snapshot.addRemovedAtom(atomDef);
		}
		for (conn in internalConns)
		{
			_snapshot.addRemovedInternalConnection(conn);
		}
		for (conn in externalConns)
		{
			_snapshot.addRemovedExternalConnection(conn);
		}


// =====================================================================
// PHASE 3: CREATE NEW ASSEMBLY BLUEPRINT (SEMANTIC NAMING)
// =====================================================================
		var newTypeId = "CustomAssembly_" + generateShortId();
		var newPins:Array<core.data.Blueprint.PinDef> = [];
		var newInternalAtoms:Array<AtomDef> = [];
		var newInternalConnections:Array<ConnectionDef> = [];
		var incomingCount = 0;
		var outgoingCount = 0;

// ═══════════════════════════════════════════════════════════════════
// v3.12 FIX: REMOVED pre-populate with parent's port externalNames.
// ═══════════════════════════════════════════════════════════════════
// PREVIOUS BUG (v3.6 "FIX"):
//   Pre-populated usedExternalNames with externalNames from
//   _assembly.ports (parent assembly's ports). The reasoning was
//   "avoid collisions with parent's existing ports".
//
//   But this is WRONG for two reasons:
//
//   (a) PARENT'S PORTS ARE BEING ABSORBED.
//       When we group selected atoms, the external connections that
//       went through parent's ports (e.g., parent.incoming_1 → atom.in)
//       become INTERNAL to the new sub-assembly. The parent's ports
//       that pointed at selected atoms will be REPLACED by new ports
//       pointing at the new sub-assembly. So we shouldn't worry about
//       "colliding" with parent's ports — they're not staying.
//
//   (b) PARENT'S PORT externalName MIRRORS ATOM NAMES.
//       Parent's port externalName is typically "AtomName_ContactName"
//       (e.g., "Pass_in"). When we create a NEW port for the same atom
//       Pass in the new sub-assembly, we naturally want the SAME name
//       "Pass_in". Pre-populate makes this look like a "collision" and
//       appends "_2" → "Pass_in_2". This breaks parent.bp.internalConnections
//       which references the OLD name "Pass_in".
//
//   WITHOUT pre-populate:
//   - The collision-counter in the loop below still handles TRUE
//     collisions (e.g., two atoms both named "Pass" both with contact
//     "in" → second becomes "Pass_in_2"). This is the only case that
//     actually needs collision handling.
//   - Parent's port names are irrelevant because they'll be replaced.
// ═══════════════════════════════════════════════════════════════════
		var usedExternalNames:Map<String, Int> = new Map();
		// Intentionally NOT pre-populated — see comment above.

// v3.3 FIX: Spatial sorting
		externalConnMeta.sort(sortByAtomPosition);

		for (meta in externalConnMeta)
		{
			var conn = meta.conn;
			var isFromSelected = meta.isFromSelected;

			var portType:ContactType;
			var externalName:String;
			var internalName:String;
			var atomDisplayName:String;
			var contactName:String;

			if (isFromSelected)
			{
				portType = OUTPUT;
				atomDisplayName = getAtomDisplayName(conn.from.atomId);
				contactName = conn.from.contactName;
				externalName = atomDisplayName + "_" + contactName;

				if (usedExternalNames.exists(externalName))
				{
					var count = usedExternalNames.get(externalName);
					usedExternalNames.set(externalName, count + 1);
					externalName = externalName + "_" + (count + 1);
				}
				else
				{
					usedExternalNames.set(externalName, 1);
				}
				outgoingCount++;
				internalName = "outgoing_" + outgoingCount;
			}
			else
			{
				portType = INPUT;
				atomDisplayName = getAtomDisplayName(conn.to.atomId);
				contactName = conn.to.contactName;
				externalName = atomDisplayName + "_" + contactName;

				if (usedExternalNames.exists(externalName))
				{
					var count = usedExternalNames.get(externalName);
					usedExternalNames.set(externalName, count + 1);
					externalName = externalName + "_" + (count + 1);
				}
				else
				{
					usedExternalNames.set(externalName, 1);
				}
				incomingCount++;
				internalName = "incoming_" + incomingCount;
			}

			_snapshot.addPortMapping(conn, internalName, portType == INPUT);

			newPins.push(
			{
				name: internalName,
				type: portType,
				externalName: externalName
			});

			if (isFromSelected)
			{
				newInternalConnections.push(
				{
					from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
					to: {atomId: "SELF", contactName: internalName}
				});
			}
			else
			{
				newInternalConnections.push(
				{
					from: {atomId: "SELF", contactName: internalName},
					to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
				});
			}
		}

// ═══════════════════════════════════════════════════════════════════
// v3.8 FIX: Copy `values` field too — it contains the saved
// displayName + isLogic state of the original atom.
// ═══════════════════════════════════════════════════════════════════
// Without this, the new Assembly's _createInternalInstances() would
// create atoms with default displayName = type (e.g., "PassThrough"),
// losing any user-customized name like "Pass" or "Pass_1".
//
// We also re-fetch the live atom's persistent state to capture the
// most current values (in case displayName was changed in this session
// and not yet serialized to atomDef.values).
// ═══════════════════════════════════════════════════════════════════
		for (atomDef in atomsToMove)
		{
			// Resolve live atom instance to capture current state
			var liveAtom:Atom = null;
			var liveAtomId:String = atomDef.instanceId;
			// Try direct (runtime ID)
			liveAtom = _assembly.internalAtoms.get(liveAtomId);
			// Try via idMap (template ID)
			if (liveAtom == null)
			{
				var rtId = _assembly.idMap.get(atomDef.instanceId);
				if (rtId != null) liveAtom = _assembly.internalAtoms.get(rtId);
			}

			// Get persistent state — prefer live atom's state (most current),
			// fall back to atomDef.values (from blueprint on disk)
			var values:Dynamic = null;
			if (liveAtom != null)
			{
				values = liveAtom.getPersistentState();
			}
			if (values == null) values = atomDef.values;

			newInternalAtoms.push(
			{
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y,
				values: values
			});
		}

		for (conn in internalConns)
		{
			newInternalConnections.push(
			{
				from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
				to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
			});
		}

// ═══════════════════════════════════════════════════════════════════
// v3.5: Resolve globally-unique blueprint.name via NamingService.
// ═══════════════════════════════════════════════════════════════════
// Each grouped operation creates a new blueprint in AtomRegistry.
// Without this, multiple groupings would all be named "Custom Assembly",
// making them indistinguishable on save/load.
// NamingService returns "Custom Assembly", "Custom Assembly_1", etc.
// ═══════════════════════════════════════════════════════════════════
		var bpName = core.logic.NamingService.resolveUniqueBlueprintName("Custom Assembly");
		var newBp = new Blueprint(newTypeId, bpName, newPins, null, newInternalAtoms, newInternalConnections);
		newBp.isNative = false;

// =====================================================================
// PHASE 4: MODIFY PARENT BLUEPRINT
// =====================================================================
		var allConnsToRemove = internalConns.concat(externalConns);
		for (conn in allConnsToRemove)
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null) cOut.unlink(cIn);
		}

		var atomDefsToRemove:Array<AtomDef> = [];
		for (atomDef in _blueprint.internalAtoms)
		{
			if (selectedTemplateIds.indexOf(atomDef.instanceId) != -1)
				atomDefsToRemove.push(atomDef);
		}
		for (atomDef in atomDefsToRemove) _blueprint.internalAtoms.remove(atomDef);
		for (conn in allConnsToRemove) _blueprint.internalConnections.remove(conn);

// ═══════════════════════════════════════════════════════════════════
// v3.8 FIX: Properly dispose atoms before removing from internalAtoms.
// ═══════════════════════════════════════════════════════════════════
// Previously this only removed the map entry without calling dispose(),
// which caused two issues:
//   (a) The atom's displayName stayed registered in NamingService, so
//       when the new sub-assembly's _createInternalInstances() tried
//       to register the same name (e.g., "Pass"), NamingService
//       appended "_1" → blueprint said "Pass" but runtime said "Pass_1".
//   (b) Native drivers (audio, COM port) were never released — they
//       kept running in the background.
//
// Now we call dispose() FIRST (which releases the name slot via
// Atom.dispose() → NamingService.unregisterInstanceName), THEN remove
// from the map.
// ═══════════════════════════════════════════════════════════════════
		for (nodeId in _selectedNodeIds)
		{
			core.view.DeviceViewRegistry.getInstance().remove(nodeId, true);

			// Dispose atom properly — releases displayName from NamingService
			var atomToDispose = _assembly.internalAtoms.get(nodeId);
			if (atomToDispose != null)
			{
				if (Std.isOfType(atomToDispose, IDisposable))
				{
					try { cast(atomToDispose, IDisposable).dispose(); }
					catch (e:Dynamic) { trace('GroupAtoms: Error disposing atom $nodeId: $e'); }
				}
			}
			_assembly.internalAtoms.remove(nodeId);
		}

// =====================================================================
// PHASE 5: CREATE NEW ASSEMBLY INSTANCE
// =====================================================================
		AtomRegistry.registerBlueprint(newTypeId, newBp);
		saveNewAssembly(newBp);

		var newInstance = AssemblyFactory.createAtom(newTypeId);
		if (newInstance == null)
		{
			trace('ERROR: GroupAtomsCommand failed to create assembly instance');
			return;
		}

		var centerPos = calculateCenterPosition(atomsToMove);

// ═══════════════════════════════════════════════════════════════════
// v3.10 FIX: Register mapping AND use Template ID in Blueprint!
// ═══════════════════════════════════════════════════════════════════
// Blueprint is Single Source of Truth (BP-SSOT). It MUST store stable
// Template IDs, NOT Runtime IDs. Runtime IDs are only for in-memory
// resolution via _idMap.
		_assembly.registerAtomMapping(newTypeId, newInstance.id);

		var finalInstanceName:String = AssemblyFactory.generateUniqueDisplayName(
										   newTypeId,
										   _isNameTakenGlobally,
										   bpName,
										   false
									   );
		newInstance.displayName = finalInstanceName;
		core.logic.NamingService.registerInstanceName(finalInstanceName, newInstance.id);

		_assembly.internalAtoms.set(newInstance.id, newInstance);

// ⚠️ CRITICAL FIX: instanceId MUST be newTypeId (Template ID),
// NOT newInstance.id (Runtime ID).
// If we save Runtime ID to blueprint, it breaks load-symmetric
// reconstruction because _createInternalInstances will generate a
// NEW runtime ID and map (Runtime ID -> New Runtime ID), corrupting
// the _idMap and causing resolveContact to fail.
		var newAtomDef:AtomDef = {
			instanceId: newTypeId, // <--- ИСПРАВЛЕНО: было newInstance.id
			typeId: newTypeId,
			x: centerPos.x,
			y: centerPos.y
		};
		_blueprint.internalAtoms.push(newAtomDef);

// =====================================================================
// PHASE 6: RECONNECT EXTERNAL CONNECTIONS
// =====================================================================
		var createdExternalConns:Array<ConnectionDef> = [];
		for (pm in _snapshot.getPortMappings())
		{
			var originalConn = pm.originalConnection;
			var newConn:ConnectionDef;

// ═══════════════════════════════════════════════════════════════════
// v3.4 FIX: Use externalName for connections in PARENT blueprint
// ═══════════════════════════════════════════════════════════════════
// pm.portName is internalName (e.g., "incoming_1")
// We need externalName (e.g., "PassThrough_1_in") for parent blueprint
// because parent sees Assembly as an atom with external port names
			var externalPortName = resolveExternalPortName(newPins, pm.portName);
			trace('  Reconnecting: internalName="${pm.portName}" → externalName="$externalPortName"');

// ═══════════════════════════════════════════════════════════════════
// v3.11 FIX: Enforce Blueprint-as-Single-Source-of-Truth (BP-SSOT)
// ═══════════════════════════════════════════════════════════════════
// Blueprint must store stable Template IDs, NOT Runtime IDs.
// Runtime IDs are only for in-memory resolution via _idMap.
//
// Both the new assembly AND the "other side" of the connection
// must be normalized to Template ID for consistency with Phase 5.
//
// How resolveContact handles this:
//   1. var realAtomId = _assembly.idMap.get(templateId); // → runtime ID
//   2. var obj = _assembly.internalAtoms.get(realAtomId); // → instance
//
// This works seamlessly for both fresh GroupAtoms execution and
// post-reconstruction, because _idMap persists, and
// forcedId=oldRuntimeId keeps newInstance.id stable.
// ═══════════════════════════════════════════════════════════════════

			// Normalize the OTHER side of the connection to Template ID.
			// originalConn may contain either template IDs (from loaded
			// blueprint) or runtime IDs (from ConnectCommand created
			// during this session). We normalize to template for consistency.
			var fromTemplateId:String = originalConn.from.atomId == "SELF"
										? "SELF"
										: _assembly.getTemplateId(originalConn.from.atomId);
			var toTemplateId:String = originalConn.to.atomId == "SELF"
									  ? "SELF"
									  : _assembly.getTemplateId(originalConn.to.atomId);

			if (pm.isInput)
			{
// Input port: connection comes FROM parent TO assembly
				newConn =
				{
					from: { atomId: fromTemplateId, contactName: originalConn.from.contactName },
					to:   { atomId: newTypeId, contactName: externalPortName }
				};
			}
			else
			{
// Output port: connection goes FROM assembly TO parent
				newConn =
				{
					from: { atomId: newTypeId, contactName: externalPortName },
					to:   { atomId: toTemplateId, contactName: originalConn.to.contactName }
				};
			}
			_blueprint.internalConnections.push(newConn);
			createdExternalConns.push(newConn);

			// Create physical link
			// resolveContact will call atom.getInput(externalName) which works
			// because Assembly._inputs contains contacts with name=externalName.
			var cOut = resolveContact(newConn.from.atomId, newConn.from.contactName, OUTPUT);
			var cIn = resolveContact(newConn.to.atomId, newConn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.link(cIn);
				trace('  ✓ Linked: ${cOut.name} → ${cIn.name}');
			}
			else
			{
				trace('  ✗ FAILED to link: cOut=${cOut != null ? cOut.name : "null"}, cIn=${cIn != null ? cIn.name : "null"}');
				trace('  DEBUG: newConn.to.atomId=${newConn.to.atomId}, contactName=${newConn.to.contactName}');
				trace('  DEBUG: newInstance.inputs=${[for (c in newInstance.getInputs()) c.name]}');
			}
		}

// === FIX: Синхронизируем родительскую сборку после добавления связей с SELF новой сборки ===
		_assembly.rebuildInternalConnections();

// Notify parent assembly that its ports have changed
		Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });

// =====================================================================
// PHASE 7: CAPTURE SNAPSHOT - AFTER STATE
// =====================================================================
		_snapshot.setCreatedData(newTypeId, newInstance.id, newAtomDef, createdExternalConns);

// =====================================================================
// PHASE 8: EMIT EVENTS
// =====================================================================
		for (nodeId in _selectedNodeIds)
		{
			Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: nodeId});
		}
		Impulsys.quickEmit(EventType.ATOM_RESTORED, {
			assemblyId: _assembly.id,
			id: newInstance.id,
			x: centerPos.x,
			y: centerPos.y,
			atom: newInstance
		});
		haxe.Timer.delay(function()
		{
			Impulsys.quickEmit(EventType.REDRAW_WIRES);
		}, 50);

		_isExecuted = true;
		trace('GroupAtomsCommand v3.12: Created $newTypeId with ${newPins.length} semantic ports (Spatially Sorted)');
	}

// ========================================================================
// HELPER: Resolve External Port Name (FIXED v3.4)
// ========================================================================
	/**
	* Get externalName from PinDef by internalName.
	*
	* v3.4 FIX: Replaced Reflect.hasField() with direct field access.
	* Reflect.hasField() does NOT work reliably for Haxe typedef structures.
	*
	* @param pins Array of PinDef from new assembly blueprint
	* @param internalName The internal name (e.g., "incoming_1")
	* @return The external name (e.g., "PassThrough_1_in") or fallback to internalName
	*/
	private function resolveExternalPortName(pins:Array<core.data.Blueprint.PinDef>, internalName:String):String
	{
		for (pin in pins)
		{
			if (pin.name == internalName)
			{
// v3.4 FIX: Direct field access instead of Reflect.hasField()
// PinDef.externalName is @:optional, so it may be null
				if (pin.externalName != null && pin.externalName != "")
				{
					return pin.externalName;
				}
// Fallback: if externalName not set, use internalName
				return pin.name;
			}
		}
// Ultimate fallback: return internalName
		return internalName;
	}

// ========================================================================
// HELPER: Get atom display name
// v3.8 FIX: AtomId resolution was broken — internalAtoms is keyed by
// RUNTIME ID, but blueprint stores TEMPLATE IDs. The previous code
// tried .get(atomId) first (which always failed for loaded atoms),
// then .get(idMap.get(atomId)) which sometimes worked, but on failure
// returned atomId instead of falling back to atom.type — and even
// when it worked, it returned atom.type instead of atom.displayName
// for atoms whose displayName had been customized by the user.
//
// New algorithm:
//   1. atomId might be either Template ID (from loaded blueprint) OR
//      Runtime ID (from freshly created atom via ConnectCommand).
//   2. Try direct lookup first (covers runtime ID case).
//   3. If that fails, try via idMap (covers template ID case).
//   4. Prefer atom.displayName over atom.type.
//   5. Replace spaces with underscores so "My Button" → "My_Button"
//      to keep external port names valid identifiers.
//   6. Final fallback: typeId-derived name, NOT raw atomId.
// ========================================================================
	private function getAtomDisplayName(atomId:String):String
	{
		// Step 1-3: Resolve atomId → Atom instance
		var atom:Atom = null;

		// Try direct lookup (atomId is Runtime ID — fresh session creation)
		if (atomId != null && atomId != "SELF")
		{
			atom = _assembly.internalAtoms.get(atomId);
		}

		// Try via idMap (atomId is Template ID — loaded from blueprint)
		if (atom == null && atomId != null && atomId != "SELF")
		{
			var runtimeId = _assembly.idMap.get(atomId);
			if (runtimeId != null)
			{
				atom = _assembly.internalAtoms.get(runtimeId);
			}
		}

		// Step 4-5: Extract display name
		if (atom != null)
		{
			var name:String = atom.displayName;
			if (name == null || name == "" || name == atom.type)
			{
				// displayName not customized — fall back to type
				name = atom.type;
			}
			// Replace spaces with underscores so external port names
			// are valid identifiers (e.g., "Signal Generator" → "Signal_Generator")
			return StringTools.replace(name, " ", "_");
		}

		// Step 6: Final fallback — return a sane default, NOT raw atomId
		// (atomId looks like "id_65803c53" which makes a terrible port name)
		trace('GroupAtomsCommand.getAtomDisplayName: Could not resolve atom "$atomId" — using fallback');
		return "Atom";
	}

// ========================================================================
// UNDO
// ========================================================================
	override public function undo():Void
	{
		var error = _snapshot.validate();
		if (error != null)
		{
			trace('ERROR: GroupAtomsCommand undo failed: $error');
			return;
		}
		trace('GroupAtomsCommand: Undoing grouping...');

		for (conn in _snapshot.getCreatedConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null) cOut.unlink(cIn);
			_blueprint.internalConnections.remove(conn);
		}

		var createdAtomDef = _snapshot.getCreatedAtomDef();
		if (createdAtomDef != null) _blueprint.internalAtoms.remove(createdAtomDef);

		var createdId = _snapshot.getCreatedInstanceId();
		var createdInst = _assembly.internalAtoms.get(createdId);
		if (createdInst != null)
		{
			if (Std.isOfType(createdInst, IDisposable))
			{
				try { cast(createdInst, IDisposable).dispose(); }
				catch (e:Dynamic) {}
			}
			_assembly.internalAtoms.remove(createdId);
		}

// v3.6: Remove the template→runtime mapping we added in execute().
// Without this, the mapping would linger and point to a disposed atom.
		var createdTypeId = _snapshot.getCreatedTypeId();
		if (createdTypeId != null)
		{
			_assembly.unregisterAtomMapping(createdTypeId);
		}

		AtomRegistry.remove(createdTypeId);
		deleteAssemblyFile(createdTypeId);

		// v3.13 BUG-2 FIX: push the ORIGINAL AtomDef object back as-is —
		// the previous stripped copy (instanceId/typeId/x/y only) silently
		// dropped `values` (displayName, driver config) and `visualMode`.
		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			_blueprint.internalAtoms.push(atomDef);
		}

		for (conn in _snapshot.getRemovedInternalConnections()) _blueprint.internalConnections.push(conn);
		for (conn in _snapshot.getRemovedExternalConnections()) _blueprint.internalConnections.push(conn);

		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			// v3.13 BUG-2 FIX: pass values as initialState so the recreated
			// instance restores displayName/config (load-symmetric).
			var atom = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId, atomDef.values);
			if (atom != null) _assembly.internalAtoms.set(atomDef.instanceId, atom);
		}

		haxe.Timer.delay(restorePhysicalConnections, 15);

		Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: createdId});
		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			var atom = _assembly.internalAtoms.get(atomDef.instanceId);
			Impulsys.quickEmit(EventType.ATOM_RESTORED,
			{
				assemblyId: _assembly.id,
				id: atomDef.instanceId,
				x: atomDef.x,
				y: atomDef.y,
				atom: atom
			});
		}
		Impulsys.quickEmit(EventType.REDRAW_WIRES);
		_isUndone = true;
	}

	private function restorePhysicalConnections():Void
	{
		for (conn in _snapshot.getRemovedInternalConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null) cOut.link(cIn);
		}
		for (conn in _snapshot.getRemovedExternalConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null) cOut.link(cIn);
		}
		Impulsys.quickEmit(EventType.REDRAW_WIRES);
	}

// ========================================================================
// REDO
// ========================================================================
	private function redoInternal():Void
	{
		_snapshot.dispose();
		_snapshot = new GroupAtomsSnapshot();
		_isUndone = false;
		executeGrouping();
	}

// ========================================================================
// HELPERS
// ========================================================================
	/**
	* Resolve a contact by atom ID and contact name.
	*
	* IMPORTANT: For Assembly atoms, contactName should be EXTERNAL name
	* because Assembly.getInput() searches by Contact.name which = externalName.
	*/
	private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact
	{
		if (atomId == "SELF")
		{
// SELF: use internalName to find port in Assembly.ports map
			var port:ConductorPort = _assembly.ports.get(contactName);
			if (port == null) return null;
			return port.internal;
		}
		else
		{
			var realAtomId = _assembly.idMap.get(atomId);
			if (realAtomId == null)
			{
				if (_assembly.internalAtoms.exists(atomId)) realAtomId = atomId;
				else return null;
			}
			var obj = _assembly.internalAtoms.get(realAtomId);
			if (obj == null) return null;
			var atom:Atom = cast obj;
// For Assembly atoms, contactName should be externalName
// because atom.getInput() searches by Contact.name = externalName
			return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
		}
	}

	/**
	* v3.9: Resolve any atomId (template or runtime) to runtime ID.
	*
	* NOTE: As of v3.11, this method is NO LONGER USED in executeGrouping()
	* (replaced by _assembly.getTemplateId to enforce BP-SSOT).
	* It is kept here for potential use in undo/redo logic or legacy fallbacks.
	*
	* Tries:
	*   1. idMap.get(atomId) → returns runtime ID if atomId is template ID
	*   2. internalAtoms.exists(atomId) → returns atomId as-is if it's already runtime ID
	*   3. Returns null if neither works
	*
	* @param atomId Template ID or Runtime ID
	* @return Runtime ID, or null if unresolvable
	*/
	private function resolveRuntimeId(atomId:String):String
	{
		if (atomId == null) return null;

		// Try template → runtime mapping (populated by _createInternalInstances)
		var runtimeId = _assembly.idMap.get(atomId);
		if (runtimeId != null) return runtimeId;

		// Already a runtime ID?
		if (_assembly.internalAtoms.exists(atomId)) return atomId;

		trace('GroupAtomsCommand.resolveRuntimeId: Could not resolve "$atomId"');
		return null;
	}

	private function calculateCenterPosition(atoms:Array<AtomDef>): {x:Float, y:Float}
	{
		if (atoms == null || atoms.length == 0) return {x: 300, y: 300};
		var sumX = 0.0, sumY = 0.0, count = 0;
		for (atom in atoms)
		{
			sumX += (atom.x != null ? atom.x : 0);
			sumY += (atom.y != null ? atom.y : 0);
			count++;
		}
		return count > 0 ? {x: sumX / count, y: sumY / count} : {x: 300, y: 300};
	}

	private function validateNoCircularReference():Bool
	{
		var currentBpId = _blueprint.id;
		for (nodeId in _selectedNodeIds)
		{
			var atomInst = _assembly.internalAtoms.get(nodeId);
			if (atomInst != null && Std.isOfType(atomInst, Assembly))
			{
				var asm = cast(atomInst, Assembly);
				// v3.15: identity check first — catches registry aliases of the same
				// live Blueprint object even when its .id has been mutated.
				if (asm.blueprint != null && (asm.blueprint == _blueprint || asm.blueprint.id == currentBpId)) return false;
				if (hasCircularReference(asm, currentBpId, 0)) return false;
			}
		}
		return true;
	}

	private function hasCircularReference(assembly:Assembly, targetId:String, depth:Int):Bool
	{
		if (depth > MAX_NESTING_DEPTH) return false;
		if (assembly.blueprint != null && assembly.blueprint.id == targetId) return true;
		if (assembly.internalAtoms != null)
		{
			for (id in assembly.internalAtoms.keys())
			{
				var atom = assembly.internalAtoms.get(id);
				if (Std.isOfType(atom, Assembly) && hasCircularReference(cast(atom, Assembly), targetId, depth + 1))
					return true;
			}
		}
		return false;
	}

// ════════════════════════════════════════════════════════════════════════
// v3.3: SPATIAL SORTING LOGIC
// ════════════════════════════════════════════════════════════════════════
	/**
	* Sort connections by the vertical position (Y) of the internal atom involved.
	* This ensures that ports on the Assembly boundary appear in the same order
	* as the atoms are visually arranged on the schematic (top-to-bottom).
	*
	* Fallback to X coordinate, then contact name.
	*/
	private function sortByAtomPosition(
		a: {conn:ConnectionDef, isFromSelected:Bool},
		b: {conn:ConnectionDef, isFromSelected:Bool}
	):Int
	{
// Identify the internal atom ID for each connection
		var idA = a.isFromSelected ? a.conn.from.atomId : a.conn.to.atomId;
		var idB = b.isFromSelected ? b.conn.from.atomId : b.conn.to.atomId;
		var yA = getAtomY(idA);
		var yB = getAtomY(idB);

// Primary sort: Y coordinate (Top -> Bottom)
		if (yA != yB) return yA < yB ? -1 : 1;

// Secondary sort: X coordinate (Left -> Right)
		var xA = getAtomX(idA);
		var xB = getAtomX(idB);
		if (xA != xB) return xA < xB ? -1 : 1;

// Tertiary sort: Contact name (for deterministic order if atoms overlap perfectly)
		var nameA = a.isFromSelected ? a.conn.from.contactName : a.conn.to.contactName;
		var nameB = b.isFromSelected ? b.conn.from.contactName : b.conn.to.contactName;
		return Reflect.compare(nameA, nameB);
	}

	/**
	* Get Y coordinate of an atom by its ID (Template or Runtime).
	*/
	private function getAtomY(atomId:String):Float
	{
// 1. Try direct match in blueprint (Template ID)
		for (def in _blueprint.internalAtoms)
		{
			if (def.instanceId == atomId) return def.y != null ? def.y : 0;
		}
// 2. Try resolving Runtime ID -> Template ID
		var templateId = _assembly.getTemplateId(atomId);
		if (templateId != atomId)
		{
			for (def in _blueprint.internalAtoms)
			{
				if (def.instanceId == templateId) return def.y != null ? def.y : 0;
			}
		}
		return 0; // Fallback
	}

	/**
	* Get X coordinate of an atom by its ID (Template or Runtime).
	*/
	private function getAtomX(atomId:String):Float
	{
// 1. Try direct match in blueprint (Template ID)
		for (def in _blueprint.internalAtoms)
		{
			if (def.instanceId == atomId) return def.x != null ? def.x : 0;
		}
// 2. Try resolving Runtime ID -> Template ID
		var templateId = _assembly.getTemplateId(atomId);
		if (templateId != atomId)
		{
			for (def in _blueprint.internalAtoms)
			{
				if (def.instanceId == templateId) return def.x != null ? def.x : 0;
			}
		}
		return 0; // Fallback
	}

	private function generateShortId():String
	{
		var chars = "0123456789abcdef";
		var str = "";
		for (i in 0...4) str += chars.charAt(Std.random(chars.length));
		return str;
	}

	private function saveNewAssembly(bp:Blueprint):Void
	{
		#if sys
		var atomsData:Array<Dynamic> = [];
		for (atomDef in bp.internalAtoms)
		{
			// v3.13 BUG-1 FIX: serialize values (live config: displayName,
			// driver settings, wasOpen...) — the disk copy must be
			// load-symmetric with the in-memory blueprint.
			var atomData:Dynamic = {instanceId: atomDef.instanceId, typeId: atomDef.typeId, x: atomDef.x, y: atomDef.y};
			if (atomDef.values != null) atomData.values = atomDef.values;
			atomsData.push(atomData);
		}
		var connsData:Array<Dynamic> = [];
		for (conn in bp.internalConnections)
			connsData.push({
			from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
			to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
		});
		var pinsData:Array<Dynamic> = [];
		for (pin in bp.pins)
		{
			var pinData:Dynamic =
			{
				name: pin.name,
				type: Std.string(pin.type),
				dataType: pin.dataType,
				defaultValue: pin.defaultValue
			};
			if (pin.externalName != null)
			{
				pinData.externalName = pin.externalName;
			}
			pinsData.push(pinData);
		}
		var data:Dynamic = {
			version: "1.2",
			blueprint: {
				id: bp.id, name: bp.name, category: bp.category,
				pins: pinsData, internalAtoms: atomsData, internalConnections: connsData
			}
		};
		var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0)
					  ? library.AtomRegistry.customLibraryPath : "library";
		if (!sys.FileSystem.exists(libPath))
			try { sys.FileSystem.createDirectory(libPath); }
			catch (e:Dynamic) {}
		var path = libPath + "/" + bp.id + ".atom";
		try {
			sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
		}
		catch (e:Dynamic)
		{
			trace('ERROR: Failed to save assembly: $e');
		}
		#end
	}

	private function deleteAssemblyFile(typeId:String):Void
	{
		#if sys
		var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0)
		? library.AtomRegistry.customLibraryPath : "library";
		var path = libPath + "/" + typeId + ".atom";
		if (sys.FileSystem.exists(path))
			try { sys.FileSystem.deleteFile(path); }
			catch (e:Dynamic) {}
		#end
	}

	override public function getDescription():String
	{
		return 'Group ${_selectedNodeIds != null ? _selectedNodeIds.length : 0} Atoms';
	}
}