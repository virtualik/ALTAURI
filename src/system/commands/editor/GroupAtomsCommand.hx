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
 * ║                      GROUP ATOMS COMMAND v3.0                             ║
 * ║                 (Semantic Port Naming: incoming/outgoing)                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Command to group selected atoms into a new Assembly.                     ║
 * ║  Supports full Undo/Redo with complete state restoration.                 ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     v3.0 CHANGES (Semantic Naming)                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  PORT NAMING CONVENTION:                                                  ║
 * ║  ────────────────────────                                                 ║
 * ║                                                                           ║
 * ║  External name (parent sees):  "{AtomDisplayName}_{ContactName}"          ║
 * ║  Internal name (wall inside):  "incoming_N" (INPUT) / "outgoing_N" (OUT) ║
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
 * ║  │  ┌── incoming_1 ──► PassThrough_1 [In]                             │  ║
 * ║  │  │                                                                 │  ║
 * ║  │  │     PassThrough_1 [Out] ──► outgoing_1 ──┘                     │  ║
 * ║  │  │                                                                 │  ║
 * ║  │  └─────────────────────────────────────────────────────────────────│  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ║  Collision handling:                                                      ║
 * ║  ─────────────────────                                                    ║
 * ║  If two atoms have same contact name (e.g., both have "out"):            ║
 * ║  - External: "PassThrough_1_out", "PassThrough_2_out"                    ║
 * ║  - Internal: "outgoing_1", "outgoing_2"                                  ║
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
     * Main grouping logic with semantic port naming.
     */
    private function executeGrouping():Void
    {
        trace('GroupAtomsCommand v3.0: Grouping ${_selectedNodeIds.length} atoms...');

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

        // Sort for deterministic ordering
        externalConnMeta.sort(sortByAtomId);

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
                // Internal atom's output → external world
                portType = OUTPUT;
                
                // Get the source atom's display name
                atomDisplayName = getAtomDisplayName(conn.from.atomId);
                contactName = conn.from.contactName;
                
                // External name: "{AtomDisplayName}_{ContactName}"
                externalName = atomDisplayName + "_" + contactName;
                
                // Handle external name collisions
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
                
                // Internal name: "outgoing_N"
                outgoingCount++;
                internalName = "outgoing_" + outgoingCount;
            }
            else
            {
                // ── INPUT PORT: data ENTERS assembly ──
                // External world → internal atom's input
                portType = INPUT;
                
                // Get the target atom's display name
                atomDisplayName = getAtomDisplayName(conn.to.atomId);
                contactName = conn.to.contactName;
                
                // External name: "{AtomDisplayName}_{ContactName}"
                externalName = atomDisplayName + "_" + contactName;
                
                // Handle external name collisions
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
                
                // Internal name: "incoming_N"
                incomingCount++;
                internalName = "incoming_" + incomingCount;
            }

            trace('  Port: external="$externalName", internal="$internalName" (${portType})');

            // Track port mapping for undo
            _snapshot.addPortMapping(conn, internalName, portType == INPUT);

            // Add pin to blueprint
            // PinDef.name = internalName (used for Assembly.ports map lookup)
            // PinDef.externalName = externalName (visible on parent)
            newPins.push({
                name: internalName,
                type: portType,
                externalName: externalName  // v2.0 PinDef field
            });

            // Create internal connection to SELF port
            // Uses internalName for SELF reference
            if (isFromSelected)
            {
                // atom.output → SELF.outgoing_N
                newInternalConnections.push({
                    from: {atomId: conn.from.atomId, contactName: conn.from.contactName},
                    to: {atomId: "SELF", contactName: internalName}
                });
            }
            else
            {
                // SELF.incoming_N → atom.input
                newInternalConnections.push({
                    from: {atomId: "SELF", contactName: internalName},
                    to: {atomId: conn.to.atomId, contactName: conn.to.contactName}
                });
            }
        }

        // Copy internal atoms
        for (atomDef in atomsToMove)
        {
            newInternalAtoms.push({
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y
            });
        }

        // Copy internal connections
        for (conn in internalConns)
        {
            newInternalConnections.push({
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

        // Remove atom definitions
        var atomDefsToRemove:Array<AtomDef> = [];
        for (atomDef in _blueprint.internalAtoms)
        {
            if (selectedTemplateIds.indexOf(atomDef.instanceId) != -1)
                atomDefsToRemove.push(atomDef);
        }
        for (atomDef in atomDefsToRemove) _blueprint.internalAtoms.remove(atomDef);

        // Remove connections
        for (conn in allConnsToRemove) _blueprint.internalConnections.remove(conn);

        // Remove atom instances
        for (nodeId in _selectedNodeIds) _assembly.internalAtoms.remove(nodeId);

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
                // External source → Assembly input port (uses internalName)
                newConn = {
                    from: originalConn.from,
                    to: {atomId: newInstance.id, contactName: pm.portName}
                };
            }
            else
            {
                // Assembly output port → External target (uses internalName)
                newConn = {
                    from: {atomId: newInstance.id, contactName: pm.portName},
                    to: originalConn.to
                };
            }

            _blueprint.internalConnections.push(newConn);
            createdExternalConns.push(newConn);

            var cOut = resolveContact(newConn.from.atomId, newConn.from.contactName, OUTPUT);
            var cIn = resolveContact(newConn.to.atomId, newConn.to.contactName, INPUT);
            if (cOut != null && cIn != null) cOut.link(cIn);
        }

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
        Impulsys.quickEmit(EventType.REDRAW_WIRES);
        _isExecuted = true;

        trace('GroupAtomsCommand v3.0: Created $newTypeId with ${newPins.length} semantic ports');
    }

    // ========================================================================
    // HELPER: Get atom display name from template/runtime ID
    // ========================================================================
    /**
     * Get human-readable display name for an atom.
     * Used to generate external port names like "PassThrough_1_in".
     *
     * @param atomId Template or Runtime ID
     * @return Display name (e.g., "PassThrough_1", "Button", "SignalGenerator")
     */
    private function getAtomDisplayName(atomId:String):String
    {
        // Try runtime ID first
        var atom = _assembly.internalAtoms.get(atomId);
        
        // Try via ID map (template → runtime)
        if (atom == null)
        {
            var runtimeId = _assembly.idMap.get(atomId);
            if (runtimeId != null) atom = _assembly.internalAtoms.get(runtimeId);
        }
        
        // Try direct template ID
        if (atom == null) atom = _assembly.internalAtoms.get(atomId);
        
        if (atom != null)
        {
            // Use displayName if available, otherwise type
            var name = atom.displayName;
            if (name == null || name == "" || name == atom.type)
            {
                name = atom.type;
            }
            // Sanitize: replace spaces with underscores
            return StringTools.replace(name, " ", "_");
        }
        
        // Fallback: use the ID itself
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
                try { cast(createdInst, IDisposable).dispose(); } catch (e:Dynamic) {}
            }
            _assembly.internalAtoms.remove(createdId);
        }

        AtomRegistry.remove(_snapshot.getCreatedTypeId());
        deleteAssemblyFile(_snapshot.getCreatedTypeId());

        for (atomDef in _snapshot.getRemovedAtomDefs())
        {
            _blueprint.internalAtoms.push({
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
            var realAtomId = _assembly.idMap.get(atomId);
            if (realAtomId == null)
            {
                if (_assembly.internalAtoms.exists(atomId)) realAtomId = atomId;
                else return null;
            }
            var obj = _assembly.internalAtoms.get(realAtomId);
            if (obj == null) return null;
            var atom:Atom = cast obj;
            return (type == INPUT) ? atom.getInput(contactName) : atom.getOutput(contactName);
        }
    }

    private function calculateCenterPosition(atoms:Array<AtomDef>):{x:Float, y:Float}
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

    private function sortByAtomId(
        a:{conn:ConnectionDef, isFromSelected:Bool},
        b:{conn:ConnectionDef, isFromSelected:Bool}
    ):Int
    {
        var nameA = a.conn.from.atomId + "_" + a.conn.from.contactName;
        var nameB = b.conn.from.atomId + "_" + b.conn.from.contactName;
        return Reflect.compare(nameA, nameB);
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
            var pinData:Dynamic = {
                name: pin.name,
                type: Std.string(pin.type),
                dataType: pin.dataType,
                defaultValue: pin.defaultValue
            };
            // v2.0: Save externalName if present
            if (Reflect.hasField(pin, "externalName"))
            {
                pinData.externalName = Reflect.field(pin, "externalName");
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
            try { sys.FileSystem.createDirectory(libPath); } catch(e:Dynamic) {}

        var path = libPath + "/" + bp.id + ".atom";
        try {
            sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
        } catch (e:Dynamic) {
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
            try { sys.FileSystem.deleteFile(path); } catch (e:Dynamic) {}
        #end
    }

    override public function getDescription():String
    {
        return 'Group ${_selectedNodeIds != null ? _selectedNodeIds.length : 0} Atoms';
    }
}