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
*                      GROUP ATOMS COMMAND v2.2                              ║
* ║                 (Fixed Runtime/Template ID Resolution)                    ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                                                                           ║
* ║  Command to group selected atoms into a new Assembly.                     ║
*  Supports full Undo/Redo with complete state restoration.                   ║
* ║                                                                           
* ╠═══════════════════════════════════════════════════════════════════════════╣
* ║                        ARCHITECTURE                                       ║
* ╠═══════════════════════════════════════════════════════════════════════════╣
*                                                                            ║
* ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
* ║  │   PHASES:                                                           │  ║
* ║  │   1. ANALYZE CONNECTIONS (no modifications)                         │  ║
* ║  │      - Identify internal connections (both ends in selection)       │  ║
* ║  │      - Identify external connections (one end in selection)         │  ║
* ║  │                                                                     │  ║
* ║  │   2. CAPTURE SNAPSHOT - BEFORE STATE                                │  
* ║  │      - Store atoms to be removed                                    │  
* ║  │      - Store connections to be removed                              │  ║
* ║  │                                                                     │  ║
* ║  │   3. CREATE NEW ASSEMBLY BLUEPRINT                                  │  ║
*   │      - Generate ports from external connections                     │  ║
* ║  │      - Copy internal atoms and connections                          │  
* ║  │                                                                     │  
* ║  │   4. MODIFY PARENT BLUEPRINT (destructive)                          │  ║
* ║  │      - Unlink physical connections                                  │  ║
* ║  │      - Remove atom definitions                                      │  
* ║  │      - Remove connections                                           │  ║
* ║  │      - Remove atom instances                                        │  ║
* ║  │                                                                     │  ║
* ║  │   5. CREATE NEW ASSEMBLY INSTANCE                                   │  ║
* ║  │      - Register blueprint in AtomRegistry                           │  
* ║  │      - Save to disk                                                 │  ║
* ║  │      - Create instance via AssemblyFactory                          │  ║
* ║  │                                                                     │  ║
* ║  │   6. RECONNECT EXTERNAL CONNECTIONS                                 │  ║
* ║  │      - External source → Assembly input port                        │  ║
*   │      - Assembly output port → External target                       │  
* ║  │                                                                     │  
*   │   7. CAPTURE SNAPSHOT - AFTER STATE                                 │  
* ║  │      - Store created assembly data for undo                         │  ║
* ║  │                                                                     │  ║
* ║  │   8. EMIT EVENTS                                                    │  ║
* ║  │      - ATOM_DELETED for grouped atoms                               │  ║
* ║  │      - ATOM_RESTORED for new assembly                               │  ║
*   │      - REDRAW_WIRES                                                 │  ║
* ║  └─────────────────────────────────────────────────────────────────────┘  ║
* ║                                                                           ║
*   v2.2 Changes:                                                            ║
* ║  - FIXED: Added Runtime ID → Template ID conversion via                   ║
* ║    _assembly.getTemplateId(). Blueprint uses Template IDs, but            ║
* ║    _selectedNodeIds contains Runtime IDs. Without conversion,             ║
* ║    atomsToMove was always empty for loaded projects.                      ║
* ║  - FIXED: resolveContact() now resolves Template IDs to Runtime IDs       
* ║    using _assembly.idMap before accessing internalAtoms.                  ║
* ║                                                                           ║
* ╚═══════════════════════════════════════════════════════════════════════════╝
*/
class GroupAtomsCommand extends Command
{
	// ========================================================================
	// CONSTANTS
	// ========================================================================
	/** Maximum nesting depth to prevent circular references */
	private static inline var MAX_NESTING_DEPTH:Int = 10;

	// ========================================================================
	// DEPENDENCIES
	// ========================================================================
	/** Parent blueprint being modified */
	private var _blueprint:Blueprint;
	/** Parent assembly being modified */
	private var _assembly:Assembly;
	/** IDs of atoms to group (Runtime IDs from NodeView) */
	private var _selectedNodeIds:Array<String>;

	// ========================================================================
	// SNAPSHOT FOR UNDO
	// ========================================================================
	/** Complete snapshot of state before/after grouping */
	private var _snapshot:GroupAtomsSnapshot;
	/** Has command been executed? */
	private var _isExecuted:Bool = false;
	/** Has command been undone? */
	private var _isUndone:Bool = false;

	// ========================================================================
	// CONSTRUCTOR
	// ========================================================================
	/**
	* Create new GroupAtomsCommand.
	*
	* @param blueprint    Parent blueprint to modify
	* @param assembly     Parent assembly to modify
	* @param selectedIds  Array of atom IDs to group (Runtime IDs)
	*/
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
	/**
	* Main execution entry point.
	* Validates input and executes grouping or redo.
	*/
	override private function executeInternal():Void
	{
		// Validate input
		if (_selectedNodeIds == null || _selectedNodeIds.length == 0)
		{
			trace('GroupAtomsCommand: Nothing to group');
			complete();
			return;
		}

		// Check for circular references
		if (!validateNoCircularReference())
		{
			trace('GroupAtomsCommand: Aborted - circular reference detected');
			complete();
			return;
		}

		if (_isUndone)
		{
			// This is REDO
			redoInternal();
		}
		else
		{
			// First execution
			executeGrouping();
		}

		complete();
	}

	/**
	* Main grouping logic - executes all 8 phases.
	*/
	private function executeGrouping():Void
	{
		trace('GroupAtomsCommand: Grouping ${_selectedNodeIds.length} atoms...');

		// =====================================================================
		// PHASE 0: ID RESOLUTION (Runtime → Template)
		// =====================================================================
		// _selectedNodeIds contains Runtime IDs (from NodeView.nodeId).
		// Blueprint uses Template IDs (from AtomDef.instanceId).
		// We must convert to compare them correctly.
		var selectedTemplateIds:Array<String> = [];
		for (runtimeId in _selectedNodeIds)
		{
			var templateId = _assembly.getTemplateId(runtimeId);
			if (selectedTemplateIds.indexOf(templateId) == -1)
			{
				selectedTemplateIds.push(templateId);
			}
		}
		trace('GroupAtomsCommand: Runtime IDs: $_selectedNodeIds');
		trace('GroupAtomsCommand: Template IDs: $selectedTemplateIds');

		// =====================================================================
		// PHASE 1: ANALYZE CONNECTIONS (no modifications)
		// =====================================================================
		var internalConns:Array<ConnectionDef> = [];  // Both ends in selection
		var externalConns:Array<ConnectionDef> = [];   // One end in selection
		var externalConnMeta:Array<{conn:ConnectionDef, isFromSelected:Bool}> = [];

		for (conn in _blueprint.internalConnections)
		{
			// Resolve connection endpoints to Template IDs for comparison
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

		// Collect atoms to move using Template IDs
		var atomsToMove:Array<AtomDef> = [];
		for (atomDef in _blueprint.internalAtoms)
		{
			if (selectedTemplateIds.indexOf(atomDef.instanceId) != -1)
			{
				atomsToMove.push(atomDef);
			}
		}

		trace('GroupAtomsCommand: atomsToMove=${atomsToMove.length}, internalConns=${internalConns.length}, externalConns=${externalConns.length}');

		if (atomsToMove.length == 0)
		{
			trace('ERROR: GroupAtomsCommand: No atoms to move! Check ID mapping.');
			complete();
			return;
		}

		// =====================================================================
		// PHASE 2: CAPTURE SNAPSHOT - BEFORE STATE
		// =====================================================================
		_snapshot.setSelectedNodeIds(_selectedNodeIds);

		// Capture atoms that will be removed
		for (atomDef in atomsToMove)
		{
			_snapshot.addRemovedAtom(atomDef);
		}

		// Capture connections that will be removed
		for (conn in internalConns)
		{
			_snapshot.addRemovedInternalConnection(conn);
		}
		for (conn in externalConns)
		{
			_snapshot.addRemovedExternalConnection(conn);
		}

		// =====================================================================
		// PHASE 3: CREATE NEW ASSEMBLY BLUEPRINT
		// =====================================================================
		var newTypeId = "CustomAssembly_" + generateShortId();
		var newPins:Array<core.data.Blueprint.PinDef> = [];
		var newInternalAtoms:Array<AtomDef> = [];
		var newInternalConnections:Array<ConnectionDef> = [];

		var inputCount = 0;
		var outputCount = 0;
		var portCounter = 0;

		// Sort external connections for deterministic port ordering
		externalConnMeta.sort(sortByAtomId);

		// Create ports from external connections
		for (meta in externalConnMeta)
		{
			var conn = meta.conn;
			var isFromSelected = meta.isFromSelected;

			// Determine port type:
			// If FROM is selected (internal), we need OUTPUT port to send to external
			// If TO is selected (internal), we need INPUT port to receive from external
			var portType:ContactType = isFromSelected ? OUTPUT : INPUT;

			var limit = (portType == INPUT) ? Assembly.MAX_INPUT_PORTS : Assembly.MAX_OUTPUT_PORTS;
			var currentCount = (portType == INPUT) ? inputCount : outputCount;

			if (currentCount >= limit)
			{
				trace('WARN: Port limit ($limit) reached, connection ${conn.from.atomId}->${conn.to.atomId} ignored');
				continue;
			}

			// Update counter
			if (portType == INPUT) inputCount++;
			else outputCount++;

			// Create port
			var portName = "pin_" + (portCounter++);

			// Track port mapping
			_snapshot.addPortMapping(conn, portName, portType == INPUT);

			// Add pin to blueprint (using standard PinDef fields only)
			newPins.push({
				name: portName,
				type: portType
			});

			// Create internal connection to SELF port
			if (isFromSelected)
			{
				// Output port: internal source -> SELF.port
				newInternalConnections.push({
					from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
					to: {atomId: "SELF", contactName: portName}
				});
			}
			else
			{
				// Input port: SELF.port -> internal target
				newInternalConnections.push({
					from: {atomId: "SELF", contactName: portName},
					to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
				});
			}
		}

		// Copy internal atoms (with same instance IDs - Template IDs)
		for (atomDef in atomsToMove)
		{
			newInternalAtoms.push({
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y
			});
		}

		// Copy internal connections (between grouped atoms)
		for (conn in internalConns)
		{
			newInternalConnections.push({
				from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
				to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
			});
		}

		// Create new blueprint
		var newBp = new Blueprint(
			newTypeId,
			"Custom Assembly",
			newPins,
			null,  // No logic - it's a composite
			newInternalAtoms,
			newInternalConnections
		);
		newBp.isNative = false;

		// =====================================================================
		// PHASE 4: MODIFY PARENT BLUEPRINT (destructive operations)
		// =====================================================================
		// Step 4a: Unlink physical connections
		var allConnsToRemove = internalConns.concat(externalConns);
		for (conn in allConnsToRemove)
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.unlink(cIn);
			}
		}

		// Step 4b: Remove atom definitions from blueprint (using Template IDs)
		var atomDefsToRemove:Array<AtomDef> = [];
		for (atomDef in _blueprint.internalAtoms)
		{
			if (selectedTemplateIds.indexOf(atomDef.instanceId) != -1)
			{
				atomDefsToRemove.push(atomDef);
			}
		}
		for (atomDef in atomDefsToRemove)
		{
			_blueprint.internalAtoms.remove(atomDef);
		}

		// Step 4c: Remove connections from blueprint
		for (conn in allConnsToRemove)
		{
			_blueprint.internalConnections.remove(conn);
		}

		// Step 4d: Remove atom instances from assembly (using Runtime IDs)
		for (nodeId in _selectedNodeIds)
		{
			var atomInst = _assembly.internalAtoms.get(nodeId);
			// Don't dispose - atoms will live inside new assembly
			_assembly.internalAtoms.remove(nodeId);
		}

		// =====================================================================
		// PHASE 5: CREATE NEW ASSEMBLY INSTANCE
		// =====================================================================
		// Register new blueprint
		AtomRegistry.registerBlueprint(newTypeId, newBp);

		// Save to disk
		saveNewAssembly(newBp);

		// Create instance
		var newInstance = AssemblyFactory.createAtom(newTypeId);
		if (newInstance == null)
		{
			trace('ERROR: GroupAtomsCommand failed to create assembly instance');
			return;
		}

		// Calculate center position
		var centerPos = calculateCenterPosition(atomsToMove);

		// Add to parent assembly
		_assembly.internalAtoms.set(newInstance.id, newInstance);

		// Create atom definition for parent blueprint
		var newAtomDef:AtomDef = {
			instanceId: newInstance.id,
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

			if (pm.isInput)
			{
				// External source -> Assembly input port
				newConn = {
					from: originalConn.from,
					to: {atomId: newInstance.id, contactName: pm.portName}
				};
			}
			else
			{
				// Assembly output port -> External target
				newConn = {
					from: {atomId: newInstance.id, contactName: pm.portName},
					to: originalConn.to
				};
			}

			_blueprint.internalConnections.push(newConn);
			createdExternalConns.push(newConn);

			// Create physical link
			var cOut = resolveContact(newConn.from.atomId, newConn.from.contactName, OUTPUT);
			var cIn = resolveContact(newConn.to.atomId, newConn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.link(cIn);
			}
		}

		// =====================================================================
		// PHASE 7: CAPTURE SNAPSHOT - AFTER STATE
		// =====================================================================
		_snapshot.setCreatedData(newTypeId, newInstance.id, newAtomDef, createdExternalConns);

		// =====================================================================
		// PHASE 8: EMIT EVENTS
		// =====================================================================
		// Emit delete events for grouped atoms
		for (nodeId in _selectedNodeIds)
		{
			Impulsys.quickEmit(EventType.ATOM_DELETED, {
				assemblyId: _assembly.id,
				id: nodeId
			});
		}

		// Emit restore event for new assembly
		Impulsys.quickEmit(EventType.ATOM_RESTORED, {
			assemblyId: _assembly.id,
			id: newInstance.id,
			x: centerPos.x,
			y: centerPos.y,
			atom: newInstance
		});

		Impulsys.quickEmit(EventType.REDRAW_WIRES);

		_isExecuted = true;
		trace('GroupAtomsCommand: Created $newTypeId with ${newPins.length} ports');
	}

	// ========================================================================
	// UNDO
	// ========================================================================
	/**
	* Undo the grouping operation.
	* Restores original atoms and removes created assembly.
	*/
	override public function undo():Void
	{
		var error = _snapshot.validate();
		if (error != null)
		{
			trace('ERROR: GroupAtomsCommand undo failed: $error');
			return;
		}

		trace('GroupAtomsCommand: Undoing grouping...');

		// =====================================================================
		// PHASE 1: REMOVE CREATED ASSEMBLY
		// =====================================================================
		// Unlink and remove created external connections
		for (conn in _snapshot.getCreatedConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.unlink(cIn);
			}
			_blueprint.internalConnections.remove(conn);
		}

		// Remove created atom definition
		var createdAtomDef = _snapshot.getCreatedAtomDef();
		if (createdAtomDef != null)
		{
			_blueprint.internalAtoms.remove(createdAtomDef);
		}

		// Remove and dispose created instance
		var createdId = _snapshot.getCreatedInstanceId();
		var createdInst = _assembly.internalAtoms.get(createdId);
		if (createdInst != null)
		{
			if (Std.isOfType(createdInst, IDisposable))
			{
				try {
					cast(createdInst, IDisposable).dispose();
				} catch (e:Dynamic) {
					trace('WARN: Error disposing created assembly: $e');
				}
			}
			_assembly.internalAtoms.remove(createdId);
		}

		// Unregister blueprint
		AtomRegistry.remove(_snapshot.getCreatedTypeId());

		// Delete file
		deleteAssemblyFile(_snapshot.getCreatedTypeId());

		// =====================================================================
		// PHASE 2: RESTORE ORIGINAL ATOMS
		// =====================================================================
		// Restore atom definitions
		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			_blueprint.internalAtoms.push({
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y
			});
		}

		// Restore internal connections
		for (conn in _snapshot.getRemovedInternalConnections())
		{
			_blueprint.internalConnections.push(conn);
		}

		// Restore external connections
		for (conn in _snapshot.getRemovedExternalConnections())
		{
			_blueprint.internalConnections.push(conn);
		}

		// =====================================================================
		// PHASE 3: RECREATE ATOM INSTANCES
		// =====================================================================
		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			var atom = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
			if (atom != null)
			{
				_assembly.internalAtoms.set(atomDef.instanceId, atom);
			}
		}

		// =====================================================================
		// PHASE 4: RESTORE PHYSICAL CONNECTIONS (delayed)
		// =====================================================================
		// Delay to ensure instances are created
		haxe.Timer.delay(restorePhysicalConnections, 15);

		// =====================================================================
		// PHASE 5: EMIT EVENTS
		// =====================================================================
		// Emit delete for assembly
		Impulsys.quickEmit(EventType.ATOM_DELETED, {
			assemblyId: _assembly.id,
			id: createdId
		});

		// Emit restore for original atoms
		for (atomDef in _snapshot.getRemovedAtomDefs())
		{
			var atom = _assembly.internalAtoms.get(atomDef.instanceId);
			Impulsys.quickEmit(EventType.ATOM_RESTORED, {
				assemblyId: _assembly.id,
				id: atomDef.instanceId,
				x: atomDef.x,
				y: atomDef.y,
				atom: atom
			});
		}

		Impulsys.quickEmit(EventType.REDRAW_WIRES);

		_isUndone = true;
		trace('GroupAtomsCommand: Undo complete');
	}

	/**
	* Restore physical connections after undo.
	* Called with delay to ensure all instances are created.
	*/
	private function restorePhysicalConnections():Void
	{
		// Restore internal connections
		for (conn in _snapshot.getRemovedInternalConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.link(cIn);
			}
		}

		// Restore external connections
		for (conn in _snapshot.getRemovedExternalConnections())
		{
			var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
			var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
			if (cOut != null && cIn != null)
			{
				cOut.link(cIn);
			}
		}

		Impulsys.quickEmit(EventType.REDRAW_WIRES);
	}

	// ========================================================================
	// REDO
	// ========================================================================
	/**
	* Redo the grouping operation.
	* Resets snapshot and re-executes grouping.
	*/
	private function redoInternal():Void
	{
		trace('GroupAtomsCommand: Redoing grouping...');

		// Reset snapshot for fresh capture
		_snapshot.dispose();
		_snapshot = new GroupAtomsSnapshot();
		_isUndone = false;

		executeGrouping();
	}

	// ========================================================================
	// HELPER METHODS
	// ========================================================================
	/**
	* Resolve a contact by atom ID and contact name.
	* Handles SELF (assembly ports) and regular atoms.
	* 
	* v2.2 FIX: Resolves Template IDs to Runtime IDs using _assembly.idMap
	* before accessing _assembly.internalAtoms.
	*
	* @param atomId       Atom ID (Template or Runtime) or "SELF"
	* @param contactName  Contact name
	* @param type         Contact type (INPUT or OUTPUT)
	* @return Contact instance or null
	*/
	private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact
	{
		if (atomId == "SELF")
		{
			var port:ConductorPort = _assembly.ports.get(contactName);
			if (port == null) return null;
			return port.internal;
		}
		else
		{
			// v2.2 FIX: Resolve Template ID to Runtime ID
			var realAtomId = _assembly.idMap.get(atomId);
			if (realAtomId == null)
			{
				// If not in idMap, assume it's already a Runtime ID
				if (_assembly.internalAtoms.exists(atomId))
				{
					realAtomId = atomId;
				}
				else
				{
					return null;
				}
			}

			var obj = _assembly.internalAtoms.get(realAtomId);
			if (obj == null) return null;
			var atom:Atom = cast obj;
			return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
		}
	}

	/**
	* Calculate center position of atoms for placing grouped assembly.
	*
	* @param atoms Array of atom definitions
	* @return Center position {x, y}
	*/
	private function calculateCenterPosition(atoms:Array<AtomDef>):{x:Float, y:Float}
	{
		if (atoms == null || atoms.length == 0) return {x: 300, y: 300};

		var sumX = 0.0;
		var sumY = 0.0;
		var count = 0;

		for (atom in atoms)
		{
			var ax = atom.x != null ? atom.x : 0;
			var ay = atom.y != null ? atom.y : 0;
			sumX += ax;
			sumY += ay;
			count++;
		}

		if (count == 0) return {x: 300, y: 300};

		return {x: sumX / count, y: sumY / count};
	}

	/**
	* Validate that grouping won't create circular references.
	* Checks if selected atoms contain the current assembly.
	*
	* @return true if no circular reference detected
	*/
	private function validateNoCircularReference():Bool
	{
		var currentBpId = _blueprint.id;

		for (nodeId in _selectedNodeIds)
		{
			var atomInst = _assembly.internalAtoms.get(nodeId);
			if (atomInst != null && Std.isOfType(atomInst, Assembly))
			{
				var asm = cast(atomInst, Assembly);

				// Direct self-reference
				if (asm.blueprint != null && asm.blueprint.id == currentBpId)
				{
					trace('ERROR: Cannot group assembly into itself');
					return false;
				}

				// Nested circular reference
				if (hasCircularReference(asm, currentBpId, 0))
				{
					trace('ERROR: Circular reference detected in nested assembly');
					return false;
				}
			}
		}

		return true;
	}

	/**
	* Recursively check for circular reference in nested assemblies.
	*
	* @param assembly  Assembly to check
	* @param targetId  Target blueprint ID to find
	* @param depth     Current nesting depth
	* @return true if circular reference found
	*/
	private function hasCircularReference(assembly:Assembly, targetId:String, depth:Int):Bool
	{
		if (depth > MAX_NESTING_DEPTH) return false;

		if (assembly.blueprint != null && assembly.blueprint.id == targetId) return true;

		if (assembly.internalAtoms != null)
		{
			for (id in assembly.internalAtoms.keys())
			{
				var atom = assembly.internalAtoms.get(id);
				if (Std.isOfType(atom, Assembly))
				{
					if (hasCircularReference(cast(atom, Assembly), targetId, depth + 1))
					{
						return true;
					}
				}
			}
		}

		return false;
	}

	/**
	* Sort connections by atom ID for deterministic port ordering.
	*/
	private function sortByAtomId(
		a:{conn:ConnectionDef, isFromSelected:Bool},
		b:{conn:ConnectionDef, isFromSelected:Bool}
	):Int
	{
		var nameA = a.conn.from.atomId + "_" + a.conn.from.contactName;
		var nameB = b.conn.from.atomId + "_" + b.conn.from.contactName;
		return Reflect.compare(nameA, nameB);
	}

	/**
	* Generate short random ID for assembly type.
	*
	* @return 4-character hex string
	*/
	private function generateShortId():String
	{
		var chars = "0123456789abcdef";
		var str = "";
		for (i in 0...4)
		{
			str += chars.charAt(Std.random(chars.length));
		}
		return str;
	}

	/**
	* Save new assembly to library folder.
	*
	* @param bp Blueprint to save
	*/
	private function saveNewAssembly(bp:Blueprint):Void
	{
		#if sys
		var atomsData:Array<Dynamic> = [];
		for (atomDef in bp.internalAtoms)
		{
			atomsData.push({
				instanceId: atomDef.instanceId,
				typeId: atomDef.typeId,
				x: atomDef.x,
				y: atomDef.y
			});
		}

		var connsData:Array<Dynamic> = [];
		for (conn in bp.internalConnections)
		{
			connsData.push({
				from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
				to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
			});
		}

		var pinsData:Array<Dynamic> = [];
		for (pin in bp.pins)
		{
			pinsData.push({
				name: pin.name,
				type: Std.string(pin.type),
				dataType: pin.dataType,
				defaultValue: pin.defaultValue
			});
		}

		var data:Dynamic = {
			version: "1.0",
			blueprint: {
				id: bp.id,
				name: bp.name,
				category: bp.category,
				pins: pinsData,
				internalAtoms: atomsData,
				internalConnections: connsData
			}
		};

		var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0)
			? library.AtomRegistry.customLibraryPath
			: "library";

		if (!sys.FileSystem.exists(libPath))
		{
			try { sys.FileSystem.createDirectory(libPath); } catch(e:Dynamic) {}
		}

		var path = libPath + "/" + bp.id + ".atom";
		try {
			sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
			trace('GroupAtomsCommand: Saved $path');
		} catch (e:Dynamic) {
			trace('ERROR: Failed to save assembly: $e');
		}
		#end
	}

	/**
	* Delete assembly file from library.
	*
	* @param typeId Assembly type ID (filename without extension)
	*/
	private function deleteAssemblyFile(typeId:String):Void
	{
		#if sys
		var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0)
			? library.AtomRegistry.customLibraryPath
			: "library";

		var path = libPath + "/" + typeId + ".atom";
		if (sys.FileSystem.exists(path))
		{
			try {
				sys.FileSystem.deleteFile(path);
				trace('GroupAtomsCommand: Deleted $path');
			} catch (e:Dynamic) {
				trace('WARN: Could not delete file: $path - $e');
			}
		}
		#end
	}

	// ========================================================================
	// DESCRIPTION
	// ========================================================================
	/**
	* Get human-readable description of command.
	*/
	override public function getDescription():String
	{
		return 'Group ${_selectedNodeIds != null ? _selectedNodeIds.length : 0} Atoms';
	}
}