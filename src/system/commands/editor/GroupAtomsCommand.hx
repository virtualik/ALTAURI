//================================================================================
// FILE: system\commands\editor\GroupAtomsCommand.hx
// Lines: 854 | Chars: 35180
//================================================================================

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
* ║                      GROUP ATOMS COMMAND v3.6                             ║
* ║         (External Name Fix + Reentrancy-safe Topology Guard Integration   ║
* ║          + DeviceView Lifecycle Cleanup + Template ID as instanceId       ║
* ║          + Global externalName Uniqueness Check)                          ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Command to group selected atoms into a new Assembly.                     ║
* ║  Supports full Undo/Redo with complete state restoration.                 ║
* ║                                                                           ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                     v3.6 CHANGES (Template ID + Global Uniqueness)        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  PROBLEM A (wires lost after save/load):                                  ║
* ║  Phase 5 wrote instanceId = newInstance.id (RUNTIME ID) into the new      ║
* ║  AtomDef. After save + restart, the runtime ID no longer exists, and      ║
* ║  resolveContact fails → SAFETY NET purges all wires as ghost.             ║
* ║                                                                           ║
* ║  SOLUTION A:                                                              ║
* ║  Phase 5 now writes instanceId = newTypeId (Template ID). This matches    ║
* ║  the on-disk format and the Load-Symmetric Reconstruction principle.      ║
* ║  Also calls _assembly.registerAtomMapping(newTypeId, newInstance.id)      ║
* ║  so resolveContact can find the new instance by its template ID.          ║
* ║                                                                           ║
* ║  PROBLEM B (wires jumping to wrong ports):                                ║
* ║  The usedExternalNames Map only tracked collisions among newly created    ║
* ║  pins for THIS grouping. It did NOT check existing ports in the parent    ║
* ║  assembly. If the parent already had a port "SignalGenerator_out" and     ║
* ║  we grouped another SignalGenerator, the new port got the same name.      ║
* ║  Atom.getInput(name) returns the first match → wire jumps to wrong port.  ║
* ║                                                                           ║
* ║  SOLUTION B:                                                              ║
* ║  Pre-populate usedExternalNames with existing port externalNames from     ║
* ║  _assembly.ports before generating new names. The existing collision      ║
* ║  counter logic then handles both cases uniformly.                         ║
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
* ║                     v3.2 CHANGES (Dual Naming Fix)                        ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  - FIXED: External connections now correctly use `externalName`           ║
* ║    instead of `internalName`, ensuring wires connect to the correct       ║
* ║    port sprites on the Assembly boundary.                                 ║
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
// ========================================================================
// SNAPSHOT FOR UNDO
// ========================================================================
        private var _snapshot:GroupAtomsSnapshot;
        private var _isExecuted:Bool = false;
        private var _isUndone:Bool = false;
// ========================================================================
// CONSTRUCTOR
// ========================================================================
        public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>)
        {
                super();
                _blueprint = blueprint;
                _assembly = assembly;
                _selectedNodeIds = selectedIds != null ? selectedIds.copy() : [];
                _snapshot = new GroupAtomsSnapshot();
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
                trace('GroupAtomsCommand v3.4: Grouping ${_selectedNodeIds.length} atoms...');
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
// PHASE 2: CAPTURE SNAPSHOT - BEFORE STATE
// =====================================================================
                _snapshot.setSelectedNodeIds(_selectedNodeIds);
                for (atomDef in atomsToMove) _snapshot.addRemovedAtom(atomDef);
                for (conn in internalConns) _snapshot.addRemovedInternalConnection(conn);
                for (conn in externalConns) _snapshot.addRemovedExternalConnection(conn);
// =====================================================================
// PHASE 3: CREATE NEW ASSEMBLY BLUEPRINT (SEMANTIC NAMING)
// =====================================================================
                var newTypeId = "CustomAssembly_" + generateShortId();
                var newPins:Array<core.data.Blueprint.PinDef> = [];
                var newInternalAtoms:Array<AtomDef> = [];
                var newInternalConnections:Array<ConnectionDef> = [];
                var incomingCount = 0;
                var outgoingCount = 0;
// Track used external names to handle collisions
                var usedExternalNames:Map<String, Int> = new Map();
// ═══════════════════════════════════════════════════════════════════
// v3.6 FIX: Pre-populate with existing port externalNames from parent
// ═══════════════════════════════════════════════════════════════════
// Without this, if the parent already has a port "SignalGenerator_out"
// and we group another SignalGenerator, the new port would get the
// same externalName. Atom.getInput(name) returns the first match →
// wire jumps to the wrong port.
//
// Pre-populating ensures the existing collision counter logic in the
// for loop below handles both newly-created pins (within this grouping)
// and existing ports (already in _assembly.ports) uniformly.
// ═══════════════════════════════════════════════════════════════════
                if (_assembly.ports != null)
                {
                        for (existingPort in _assembly.ports)
                        {
                                if (existingPort != null && existingPort.externalName != null
                                        && existingPort.externalName != "")
                                {
                                        usedExternalNames.set(existingPort.externalName, 1);
                                }
                        }
                }
// ═══════════════════════════════════════════════════════════════════
// v3.3 FIX: SPATIAL SORTING
// Sort connections by the Y-coordinate of the internal atom involved.
// This ensures ports on the Assembly boundary appear in the same
// vertical order as the atoms on the schematic.
// ═══════════════════════════════════════════════════════════════════
                externalConnMeta.sort(sortByAtomPosition);
                for (meta in externalConnMeta)
                {
                        var conn = meta.conn;
                        var isFromSelected = meta.isFromSelected;
// ================================================================
// v3.0: SEMANTIC PORT NAMING
// ================================================================
                        var portType:ContactType;
                        var externalName:String;
                        var internalName:String;
                        var atomDisplayName:String;
                        var contactName:String;
                        if (isFromSelected)
                        {
// ── OUTPUT PORT: data LEAVES assembly ──
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
// ── INPUT PORT: data ENTERS assembly ──
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
                        trace('  Port: external="$externalName", internal="$internalName" (${portType})');
// Track port mapping for undo
                        _snapshot.addPortMapping(conn, internalName, portType == INPUT);
// Add pin to blueprint
// IMPORTANT: PinDef.name = internalName (used as key in Assembly.ports map)
// PinDef.externalName = externalName (visible on parent schema)
                        newPins.push(
                        {
                                name: internalName,
                                type: portType,
                                externalName: externalName
                        });
// Create internal connection to SELF port
// IMPORTANT: Inside assembly, we use internalName for SELF connections
                        if (isFromSelected)
                        {
                                newInternalConnections.push(
                                {
                                        from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
                                        to: {atomId: "SELF", contactName: internalName}  // ← internalName
                                });
                        }
                        else
                        {
                                newInternalConnections.push(
                                {
                                        from: {atomId: "SELF", contactName: internalName},  // ← internalName
                                        to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
                                });
                        }
                }
// Copy internal atoms
                for (atomDef in atomsToMove)
                {
                        newInternalAtoms.push(
                        {
                                instanceId: atomDef.instanceId,
                                typeId: atomDef.typeId,
                                x: atomDef.x,
                                y: atomDef.y
                        });
                }
// Copy internal connections
                for (conn in internalConns)
                {
                        newInternalConnections.push(
                        {
                                from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
                                to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
                        });
                }
                var newBp = new Blueprint(newTypeId, "Custom Assembly", newPins, null, newInternalAtoms, newInternalConnections);
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
// v3.5 FIX: Dispose DeviceViews for atoms being absorbed into the new
// assembly, BEFORE removing them from the parent's internalAtoms map.
//
// PROBLEM:
// The old code simply did _assembly.internalAtoms.remove(nodeId), which
// orphaned the atom instance. Its DeviceView, however, remained alive in
// DeviceViewRegistry._widgets[atom.id] and continued to be displayed in
// the DevicePanel (if active). The widget kept its Contact subscriptions
// pointing at the soon-to-be-disposed atom's contacts — leading to
// use-after-free when signals reached those contacts.
//
// This was especially visible when GroupAtomsCommand was triggered FROM
// the Device Panel: the widgets visually "disappeared" from the panel
// (because the panel iterates _assembly.internalAtoms to render cards),
// but they were still in the registry and still subscribed.
//
// SOLUTION:
// For each atom being moved into the new assembly:
//   1. Look up its DeviceView in DeviceViewRegistry
//   2. Call DeviceViewRegistry.remove(atom.id, true) — this calls
//      DeviceView.dispose() which:
//        - calls deactivate() → unsubscribeFromContacts()
//        - nullifies atom reference
//        - removes from any parent display list
//   3. Then remove the atom from _assembly.internalAtoms
//
// The new assembly will get fresh DeviceViews via NodeView.acquireWidget()
// when its NodeView is created — this is the load-symmetric path.
// ═══════════════════════════════════════════════════════════════════
                for (nodeId in _selectedNodeIds)
                {
                        // Dispose widget before removing the atom, so Contact
                        // subscriptions are cleanly released.
                        core.view.DeviceViewRegistry.getInstance().remove(nodeId, true);
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
                _assembly.internalAtoms.set(newInstance.id, newInstance);

// ═══════════════════════════════════════════════════════════════════
// v3.6 FIX: Register template→runtime mapping for the new assembly.
// ═══════════════════════════════════════════════════════════════════
// Without this, resolveContact cannot find the new assembly by its
// template ID in bp.internalConnections (because _idMap doesn't have
// the entry — only _createInternalInstances populates _idMap, and that
// runs only during Assembly construction, not when atoms are added
// later via GroupAtomsCommand).
//
// This is critical for the Phase 6 wire reconnection below, which uses
// newTypeId in the connection definitions.
// ═══════════════════════════════════════════════════════════════════
                _assembly.registerAtomMapping(newTypeId, newInstance.id);

// ═══════════════════════════════════════════════════════════════════
// v3.6 FIX: AtomDef.instanceId must be the TEMPLATE ID (newTypeId),
// NOT the runtime ID (newInstance.id).
// ═══════════════════════════════════════════════════════════════════
// PROBLEM:
// The old code wrote instanceId = newInstance.id (runtime). After save
// + restart, the runtime ID no longer exists, and resolveContact fails
// → SAFETY NET purges all wires as ghost.
//
// SOLUTION:
// Use newTypeId (Template ID) as instanceId. This matches the on-disk
// format and the Load-Symmetric Reconstruction principle: when the
// project is loaded, _createInternalInstances generates a fresh runtime
// ID via UID.generate(), records template→runtime in _idMap, and stores
// the atom under the runtime ID. We just did the same thing manually
// above (registerAtomMapping + internalAtoms.set).
// ═══════════════════════════════════════════════════════════════════
                var newAtomDef:AtomDef = {
                        instanceId: newTypeId,
                        typeId: newTypeId,
                        x: centerPos.x,
                        y: centerPos.y
                };
                _blueprint.internalAtoms.push(newAtomDef);
// =====================================================================
// PHASE 6: RECONNECT EXTERNAL CONNECTIONS (FIXED v3.4)
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
// v3.6 FIX: Use newTypeId (Template ID) in connection atomId fields,
// not newInstance.id (Runtime ID).
// ═══════════════════════════════════════════════════════════════════
// Blueprint is the Single Source of Truth and must store stable
// Template IDs. The physical link below uses resolveContact which
// translates template→runtime via _idMap (we just registered the
// mapping above).
//
// Also translate the originalConn side to Template ID for consistency
// (the original atomIds there may be runtime IDs from ConnectCommand).
// ═══════════════════════════════════════════════════════════════════
                        var fromTemplateId = originalConn.from.atomId == "SELF"
                                ? "SELF"
                                : _assembly.getTemplateId(originalConn.from.atomId);
                        var toTemplateId = originalConn.to.atomId == "SELF"
                                ? "SELF"
                                : _assembly.getTemplateId(originalConn.to.atomId);

                        if (pm.isInput)
                        {
// Input port: connection comes FROM parent TO assembly
                                newConn =
                                {
                                        from: { atomId: fromTemplateId, contactName: originalConn.from.contactName },
                                        to: { atomId: newTypeId, contactName: externalPortName }  // ← Template ID + externalName
                                };
                        }
                        else
                        {
// Output port: connection goes FROM assembly TO parent
                                newConn =
                                {
                                        from: { atomId: newTypeId, contactName: externalPortName },  // ← Template ID + externalName
                                        to: { atomId: toTemplateId, contactName: originalConn.to.contactName }
                                };
                        }
                        _blueprint.internalConnections.push(newConn);
                        createdExternalConns.push(newConn);
// Create physical link
// resolveContact will call atom.getInput(externalName) which works
// because Assembly._inputs contains contacts with name=externalName.
// resolveContact translates the template ID to runtime via _idMap.
                        var cOut = resolveContact(newConn.from.atomId, newConn.from.contactName, OUTPUT);
                        var cIn = resolveContact(newConn.to.atomId, newConn.to.contactName, INPUT);
                        if (cOut != null && cIn != null)
                        {
                                cOut.link(cIn);
                                trace('  ✓ Linked: ${cOut.name} → ${cIn.name}');
                        }
                        else
                        {
                                trace('  ✗ FAILED to link: cOut=${cOut != null}, cIn=${cIn != null}');
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
                trace('GroupAtomsCommand v3.4: Created $newTypeId with ${newPins.length} semantic ports (Spatially Sorted)');
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
// ========================================================================
        private function getAtomDisplayName(atomId:String):String
        {
                var atom = _assembly.internalAtoms.get(atomId);
                if (atom == null)
                {
                        var runtimeId = _assembly.idMap.get(atomId);
                        if (runtimeId != null) atom = _assembly.internalAtoms.get(runtimeId);
                }
                if (atom == null) atom = _assembly.internalAtoms.get(atomId);
                if (atom != null)
                {
                        var name = atom.displayName;
                        if (name == null || name == "" || name == atom.type) name = atom.type;
                        return StringTools.replace(name, " ", "_");
                }
                return atomId;
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
                for (atomDef in _snapshot.getRemovedAtomDefs())
                {
                        _blueprint.internalAtoms.push(
                        {
                                instanceId: atomDef.instanceId,
                                typeId: atomDef.typeId,
                                x: atomDef.x,
                                y: atomDef.y
                        });
                }
                for (conn in _snapshot.getRemovedInternalConnections()) _blueprint.internalConnections.push(conn);
                for (conn in _snapshot.getRemovedExternalConnections()) _blueprint.internalConnections.push(conn);
                for (atomDef in _snapshot.getRemovedAtomDefs())
                {
                        var atom = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
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
                                if (asm.blueprint != null && asm.blueprint.id == currentBpId) return false;
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
                        atomsData.push({instanceId: atomDef.instanceId, typeId: atomDef.typeId, x: atomDef.x, y: atomDef.y});
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
