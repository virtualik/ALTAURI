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
import core.types.ContactType;
import library.AtomRegistry;

/**
 * GROUP ATOMS COMMAND v2.0 (Full Undo/Redo Support)
 * Command to group selected atoms into a new Assembly.
 * 
 * v2.0 Changes:
 * - Added full undo/redo support via GroupAtomsSnapshot
 * - Safe iteration over blueprint collections (collect first, modify after)
 * - Circular reference protection with depth limit
 * - Proper cleanup of created resources
 * - Port limit checking (MAX_INPUT_PORTS, MAX_OUTPUT_PORTS)
 * 
 * DESIGN NOTES:
 * - Snapshot is captured DURING execute() (both before and after modifications)
 * - Undo completely reverses all changes
 * - Redo re-executes the grouping operation
 * - Physical connections (Contact.link) are handled separately from logical (Blueprint)
 */
class GroupAtomsCommand extends Command {

    private static inline var MAX_NESTING_DEPTH:Int = 10;

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _selectedNodeIds:Array<String>;

    // Snapshot for undo
    private var _snapshot:GroupAtomsSnapshot;
    private var _isExecuted:Bool = false;
    private var _isUndone:Bool = false;

    public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _selectedNodeIds = selectedIds != null ? selectedIds.copy() : [];
        _snapshot = new GroupAtomsSnapshot();
    }

    // =========================================================================
    // EXECUTE
    // =========================================================================

    override private function executeInternal():Void {
        // Validate input
        if (_selectedNodeIds == null || _selectedNodeIds.length == 0) {
            trace('GroupAtomsCommand: Nothing to group');
            complete();
            return;
        }

        // Check for circular references
        if (!validateNoCircularReference()) {
            trace('GroupAtomsCommand: Aborted - circular reference detected');
            complete();
            return;
        }

        if (_isUndone) {
            // This is REDO
            redoInternal();
        } else {
            // First execution
            executeGrouping();
        }

        complete();
    }

    /**
     * Main grouping logic.
     */
    private function executeGrouping():Void {
        trace('GroupAtomsCommand: Grouping ${_selectedNodeIds.length} atoms...');

        // =====================================================================
        // PHASE 1: ANALYZE CONNECTIONS (no modifications)
        // =====================================================================

        var internalConns:Array<ConnectionDef> = [];  // Both ends in selection
        var externalConns:Array<ConnectionDef> = [];   // One end in selection
        var externalConnMeta:Array<{conn:ConnectionDef, isFromSelected:Bool}> = [];

        for (conn in _blueprint.internalConnections) {
            var fromSelected = _selectedNodeIds.indexOf(conn.from.atomId) != -1;
            var toSelected = _selectedNodeIds.indexOf(conn.to.atomId) != -1;

            if (fromSelected && toSelected) {
                internalConns.push(conn);
            } else if (fromSelected || toSelected) {
                externalConns.push(conn);
                externalConnMeta.push({conn: conn, isFromSelected: fromSelected});
            }
        }

        // Collect atoms to move
        var atomsToMove:Array<AtomDef> = [];
        for (atomDef in _blueprint.internalAtoms) {
            if (_selectedNodeIds.indexOf(atomDef.instanceId) != -1) {
                atomsToMove.push(atomDef);
            }
        }

        // =====================================================================
        // PHASE 2: CAPTURE SNAPSHOT - BEFORE STATE
        // =====================================================================

        _snapshot.setSelectedNodeIds(_selectedNodeIds);

        // Capture atoms that will be removed
        for (atomDef in atomsToMove) {
            _snapshot.addRemovedAtom(atomDef);
        }

        // Capture connections that will be removed
        for (conn in internalConns) {
            _snapshot.addRemovedInternalConnection(conn);
        }
        for (conn in externalConns) {
            _snapshot.addRemovedExternalConnection(conn);
        }

        // =====================================================================
        // PHASE 3: CREATE NEW ASSEMBLY BLUEPRINT
        // =====================================================================

        var newTypeId = "CustomAssembly_" + generateShortId();
        var newPins:Array<{name:String, type:ContactType, ?dataType:String, ?defaultValue:Dynamic}> = [];
        var newInternalAtoms:Array<AtomDef> = [];
        var newInternalConnections:Array<ConnectionDef> = [];

        var inputCount = 0;
        var outputCount = 0;
        var portCounter = 0;

        // Sort external connections for deterministic port ordering
        externalConnMeta.sort(sortByAtomId);

        // Create ports from external connections
        for (meta in externalConnMeta) {
            var conn = meta.conn;
            var isFromSelected = meta.isFromSelected;

            // Determine port type:
            // If FROM is selected (internal), we need OUTPUT port to send to external
            // If TO is selected (internal), we need INPUT port to receive from external
            var portType:ContactType = isFromSelected ? OUTPUT : INPUT;
            var limit = (portType == INPUT) ? Assembly.MAX_INPUT_PORTS : Assembly.MAX_OUTPUT_PORTS;
            var currentCount = (portType == INPUT) ? inputCount : outputCount;

            if (currentCount >= limit) {
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

            // Add pin to blueprint
            newPins.push({name: portName, type: portType});

            // Create internal connection to SELF port
            if (isFromSelected) {
                // Output port: internal source -> SELF.port
                newInternalConnections.push({
                    from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
                    to: {atomId: "SELF", contactName: portName}
                });
            } else {
                // Input port: SELF.port -> internal target
                newInternalConnections.push({
                    from: {atomId: "SELF", contactName: portName},
                    to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
                });
            }
        }

        // Copy internal atoms (with same instance IDs)
        for (atomDef in atomsToMove) {
            newInternalAtoms.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y
            });
        }

        // Copy internal connections (between grouped atoms)
        for (conn in internalConns) {
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
        for (conn in allConnsToRemove) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) {
                cOut.unlink(cIn);
            }
        }

        // Step 4b: Remove atom definitions from blueprint
        var atomDefsToRemove:Array<AtomDef> = [];
        for (atomDef in _blueprint.internalAtoms) {
            if (_selectedNodeIds.indexOf(atomDef.instanceId) != -1) {
                atomDefsToRemove.push(atomDef);
            }
        }
        for (atomDef in atomDefsToRemove) {
            _blueprint.internalAtoms.remove(atomDef);
        }

        // Step 4c: Remove connections from blueprint
        for (conn in allConnsToRemove) {
            _blueprint.internalConnections.remove(conn);
        }

        // Step 4d: Remove atom instances from assembly
        for (nodeId in _selectedNodeIds) {
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
        if (newInstance == null) {
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

        for (pm in _snapshot.getPortMappings()) {
            var originalConn = pm.originalConnection;
            var newConn:ConnectionDef;

            if (pm.isInput) {
                // External source -> Assembly input port
                newConn = {
                    from: originalConn.from,
                    to: {atomId: newInstance.id, contactName: pm.portName}
                };
            } else {
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
            if (cOut != null && cIn != null) {
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
        for (nodeId in _selectedNodeIds) {
            Impulsys.quickEmit("ATOM_DELETED", {
                assemblyId: _assembly.id,
                id: nodeId
            });
        }

        // Emit restore event for new assembly
        Impulsys.quickEmit("ATOM_RESTORED", {
            assemblyId: _assembly.id,
            id: newInstance.id,
            x: centerPos.x,
            y: centerPos.y,
            atom: newInstance
        });

        Impulsys.quickEmit("REDRAW_WIRES");

        _isExecuted = true;
        trace('GroupAtomsCommand: Created $newTypeId with ${newPins.length} ports');
    }

    // =========================================================================
    // UNDO
    // =========================================================================

    override public function undo():Void {
        var error = _snapshot.validate();
        if (error != null) {
            trace('ERROR: GroupAtomsCommand undo failed: $error');
            return;
        }

        trace('GroupAtomsCommand: Undoing grouping...');

        // =====================================================================
        // PHASE 1: REMOVE CREATED ASSEMBLY
        // =====================================================================

        // Unlink and remove created external connections
        for (conn in _snapshot.getCreatedConnections()) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) {
                cOut.unlink(cIn);
            }
            _blueprint.internalConnections.remove(conn);
        }

        // Remove created atom definition
        var createdAtomDef = _snapshot.getCreatedAtomDef();
        if (createdAtomDef != null) {
            _blueprint.internalAtoms.remove(createdAtomDef);
        }

        // Remove and dispose created instance
        var createdId = _snapshot.getCreatedInstanceId();
        var createdInst = _assembly.internalAtoms.get(createdId);
        if (createdInst != null) {
            if (Std.isOfType(createdInst, IDisposable)) {
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
        for (atomDef in _snapshot.getRemovedAtomDefs()) {
            _blueprint.internalAtoms.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y
            });
        }

        // Restore internal connections
        for (conn in _snapshot.getRemovedInternalConnections()) {
            _blueprint.internalConnections.push(conn);
        }

        // Restore external connections
        for (conn in _snapshot.getRemovedExternalConnections()) {
            _blueprint.internalConnections.push(conn);
        }

        // =====================================================================
        // PHASE 3: RECREATE ATOM INSTANCES
        // =====================================================================

        for (atomDef in _snapshot.getRemovedAtomDefs()) {
            var atom = AssemblyFactory.createAtom(atomDef.typeId, atomDef.instanceId);
            if (atom != null) {
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
        Impulsys.quickEmit("ATOM_DELETED", {
            assemblyId: _assembly.id,
            id: createdId
        });

        // Emit restore for original atoms
        for (atomDef in _snapshot.getRemovedAtomDefs()) {
            var atom = _assembly.internalAtoms.get(atomDef.instanceId);
            Impulsys.quickEmit("ATOM_RESTORED", {
                assemblyId: _assembly.id,
                id: atomDef.instanceId,
                x: atomDef.x,
                y: atomDef.y,
                atom: atom
            });
        }

        Impulsys.quickEmit("REDRAW_WIRES");

        _isUndone = true;
        trace('GroupAtomsCommand: Undo complete');
    }

    /**
     * Restore physical connections after undo.
     */
    private function restorePhysicalConnections():Void {
        // Restore internal connections
        for (conn in _snapshot.getRemovedInternalConnections()) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) {
                cOut.link(cIn);
            }
        }

        // Restore external connections
        for (conn in _snapshot.getRemovedExternalConnections()) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) {
                cOut.link(cIn);
            }
        }

        Impulsys.quickEmit("REDRAW_WIRES");
    }

    // =========================================================================
    // REDO
    // =========================================================================

    private function redoInternal():Void {
        trace('GroupAtomsCommand: Redoing grouping...');

        // Reset snapshot for fresh capture
        _snapshot.dispose();
        _snapshot = new GroupAtomsSnapshot();
        _isUndone = false;

        executeGrouping();
    }

    // =========================================================================
    // HELPER METHODS
    // =========================================================================

    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            var obj = _assembly.internalAtoms.get(atomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    private function calculateCenterPosition(atoms:Array<AtomDef>):{x:Float, y:Float} {
        if (atoms == null || atoms.length == 0) return {x: 300, y: 300};

        var sumX = 0.0;
        var sumY = 0.0;
        var count = 0;

        for (atom in atoms) {
            var ax = atom.x != null ? atom.x : 0;
            var ay = atom.y != null ? atom.y : 0;
            sumX += ax;
            sumY += ay;
            count++;
        }

        if (count == 0) return {x: 300, y: 300};
        return {x: sumX / count, y: sumY / count};
    }

    private function validateNoCircularReference():Bool {
        var currentBpId = _blueprint.id;

        for (nodeId in _selectedNodeIds) {
            var atomInst = _assembly.internalAtoms.get(nodeId);
            if (atomInst != null && Std.isOfType(atomInst, Assembly)) {
                var asm = cast(atomInst, Assembly);

                // Direct self-reference
                if (asm.blueprint != null && asm.blueprint.id == currentBpId) {
                    trace('ERROR: Cannot group assembly into itself');
                    return false;
                }

                // Nested circular reference
                if (hasCircularReference(asm, currentBpId, 0)) {
                    trace('ERROR: Circular reference detected in nested assembly');
                    return false;
                }
            }
        }
        return true;
    }

    private function hasCircularReference(assembly:Assembly, targetId:String, depth:Int):Bool {
        if (depth > MAX_NESTING_DEPTH) return false;
        if (assembly.blueprint != null && assembly.blueprint.id == targetId) return true;

        if (assembly.internalAtoms != null) {
            for (id in assembly.internalAtoms.keys()) {
                var atom = assembly.internalAtoms.get(id);
                if (Std.isOfType(atom, Assembly)) {
                    if (hasCircularReference(cast(atom, Assembly), targetId, depth + 1)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private function sortByAtomId(
        a:{conn:ConnectionDef, isFromSelected:Bool},
        b:{conn:ConnectionDef, isFromSelected:Bool}
    ):Int {
        var nameA = a.conn.from.atomId + "_" + a.conn.from.contactName;
        var nameB = b.conn.from.atomId + "_" + b.conn.from.contactName;
        return Reflect.compare(nameA, nameB);
    }

    private function generateShortId():String {
        var chars = "0123456789abcdef";
        var str = "";
        for (i in 0...4) {
            str += chars.charAt(Std.random(chars.length));
        }
        return str;
    }

   private function saveNewAssembly(bp:Blueprint):Void {
        #if sys
        var atomsData:Array<Dynamic> = [];
        for (atomDef in bp.internalAtoms) {
            atomsData.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y
            });
        }

        var connsData:Array<Dynamic> = [];
        for (conn in bp.internalConnections) {
            connsData.push({
                from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
                to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
            });
        }

        var pinsData:Array<Dynamic> = [];
        for (pin in bp.pins) {
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

        // === ИСПРАВЛЕНИЕ ПУТИ ===
        // Используем путь из реестра, если он задан, иначе дефолтный
        var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0) 
            ? library.AtomRegistry.customLibraryPath 
            : "library";
        
        // Убедимся, что папка существует
        if (!sys.FileSystem.exists(libPath)) {
            try { sys.FileSystem.createDirectory(libPath); } catch(e:Dynamic) {}
        }

        var path = libPath + "/" + bp.id + ".atom";
        // =======================

        try {
            sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
            trace('GroupAtomsCommand: Saved $path');
        } catch (e:Dynamic) {
            trace('ERROR: Failed to save assembly: $e');
        }
        #end
    }

    private function deleteAssemblyFile(typeId:String):Void {
        #if sys
        // === ИСПРАВЛЕНИЕ ПУТИ ===
        var libPath = (library.AtomRegistry.customLibraryPath != null && library.AtomRegistry.customLibraryPath.length > 0) 
            ? library.AtomRegistry.customLibraryPath 
            : "library";
        var path = libPath + "/" + typeId + ".atom";
        // =======================

        if (sys.FileSystem.exists(path)) {
            try {
                sys.FileSystem.deleteFile(path);
                trace('GroupAtomsCommand: Deleted $path');
            } catch (e:Dynamic) {
                trace('WARN: Could not delete file: $path - $e');
            }
        }
        #end
    }

    override public function getDescription():String {
        return 'Group ${_selectedNodeIds != null ? _selectedNodeIds.length : 0} Atoms';
    }
}
