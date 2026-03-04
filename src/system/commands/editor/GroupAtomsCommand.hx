package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.AssemblyFactory;
import core.base.IDisposable;
import core.types.ContactType;
import core.logic.Impulsys;
import library.AtomRegistry;

/**
 * GROUP ATOMS COMMAND v2.1 (Port Limits Support)
 * Command to group selected atoms into a new Assembly.
 * Respects MAX_INPUT_PORTS and MAX_OUTPUT_PORTS limits.
 */
class GroupAtomsCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _selectedNodeIds:Array<String>;

    public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _selectedNodeIds = selectedIds.copy();
    }

    override private function executeInternal():Void {
        if (_selectedNodeIds.length == 0) {
            trace("Nothing to group.");
            complete();
            return;
        }

        // 1. Collect data
        var newInternalAtoms:Array<AtomDef> = [];
        var newInternalConnections:Array<ConnectionDef> = [];
        var newPins:Array<{name:String, type:ContactType, ?dataType:String, ?defaultValue:Dynamic}> = [];
        
        // Separate internal and external connections
        var externalConnections:Array<{conn:ConnectionDef, isSourceSelected:Bool}> = [];
        
        for (conn in _blueprint.internalConnections) {
            var fromSel = _selectedNodeIds.indexOf(conn.from.atomId) != -1;
            var toSel = _selectedNodeIds.indexOf(conn.to.atomId) != -1;

            if (fromSel && toSel) {
                newInternalConnections.push(conn);
            } else if (fromSel || toSel) {
                externalConnections.push({conn: conn, isSourceSelected: fromSel});
            }
        }

        for (atomDef in _blueprint.internalAtoms) {
            if (_selectedNodeIds.indexOf(atomDef.instanceId) != -1) {
                newInternalAtoms.push(atomDef);
            }
        }

        // 2. PROCESS EXTERNAL CONNECTIONS WITH LIMITS
        // Sort to make priority deterministic (e.g., by source atom ID or contact name)
        externalConnections.sort(function(a, b) {
            var nameA = a.conn.from.atomId + a.conn.from.contactName;
            var nameB = b.conn.from.atomId + b.conn.from.contactName;
            return Reflect.compare(nameA, nameB);
        });

        var inputCount = 0;
        var outputCount = 0;
        var mapping:Array<{oldConn:ConnectionDef, newPinName:String, isInput:Bool}> = [];
        var pinCounter = 0;

        for (item in externalConnections) {
            var conn = item.conn;
            var type:ContactType = item.isSourceSelected ? OUTPUT : INPUT; // Direction relative to new Assembly
            
            var limitReached = false;
            var msg = "";

            // Check Limits
            if (type == INPUT) {
                if (inputCount >= Assembly.MAX_INPUT_PORTS) {
                    limitReached = true;
                    msg = 'WARN: Input ports limit (${Assembly.MAX_INPUT_PORTS}) reached. Connection ${conn.from.atomId}->${conn.to.atomId} ignored.';
                } else {
                    inputCount++;
                }
            } else {
                if (outputCount >= Assembly.MAX_OUTPUT_PORTS) {
                    limitReached = true;
                    msg = 'WARN: Output ports limit (${Assembly.MAX_OUTPUT_PORTS}) reached. Connection ${conn.from.atomId}->${conn.to.atomId} ignored.';
                } else {
                    outputCount++;
                }
            }

            if (limitReached) {
                trace(msg); // User feedback
                // We do NOT add this connection to the new assembly. 
                // The wire remains in the parent blueprint? Ideally, we should probably remove it 
                // or leave it dangling. For now, we just don't map it to the new assembly port.
                continue; 
            }

            // Create Pin
            var pinName = "pin_" + (pinCounter++);
            newPins.push({name: pinName, type: type, dataType: null, defaultValue: null});

            // Create internal connection for this pin
            if (item.isSourceSelected) {
                // Output of internal atom -> Output Port of Assembly (which is Input inside? No.)
                // Assembly Output Port -> Inside it acts as Input (Target).
                // So we connect Internal Source -> Self.Port
                newInternalConnections.push({
                    from: conn.from,
                    to: {atomId: "SELF", contactName: pinName}
                });
            } else {
                // Assembly Input Port -> Inside it acts as Output (Source).
                // Connect Self.Port -> Internal Target
                newInternalConnections.push({
                    from: {atomId: "SELF", contactName: pinName},
                    to: conn.to
                });
            }

            mapping.push({oldConn: conn, newPinName: pinName, isInput: !item.isSourceSelected});
        }

        // 3. Create and save Blueprint
        var newTypeId = "CustomAssembly_" + Std.random(10000);
        var newBp = new Blueprint(newTypeId, "Custom Assembly", newPins, null, newInternalAtoms, newInternalConnections);

        saveNewAssembly(newBp);
        AtomRegistry.registerBlueprint(newTypeId, newBp);

        // 4. Send ATOM_DELETED impulses
        for (id in _selectedNodeIds) {
            Impulsys.quickEmit("ATOM_DELETED", {id: id});
        }

        // 5. Dispose atoms
        for (id in _selectedNodeIds) {
            var def = findAtomDef(id);
            if (def != null) _blueprint.internalAtoms.remove(def);

            var inst = _assembly.internalAtoms.get(id);
            if (inst != null) {
                var disposable:IDisposable = cast inst;
                if (disposable != null) disposable.dispose();
                _assembly.internalAtoms.remove(id);
            }
        }

        // Remove old external connections that were mapped
        for (item in externalConnections) {
             // Check if it was mapped (limits might have prevented it)
             // Ideally we should check if it exists in mapping, but simpler to remove all original external connections
             // that involved the selected nodes.
            _blueprint.internalConnections.remove(item.conn);
        }

        // 6. Create new atom instance
        var newAtomInstance = AssemblyFactory.createAtom(newTypeId, newTypeId + "_inst");
        _assembly.internalAtoms.set(newAtomInstance.id, newAtomInstance);
        _blueprint.internalAtoms.push({instanceId: newAtomInstance.id, typeId: newTypeId, x: 300, y: 300});

        // 7. Restore external connections (wires to the new assembly)
        for (m in mapping) {
            var newConn:ConnectionDef;
            if (m.isInput) {
                // Incoming to new assembly
                newConn = {
                    from: m.oldConn.from, // External source
                    to: {atomId: newAtomInstance.id, contactName: m.newPinName}
                };
            } else {
                // Outgoing from new assembly
                newConn = {
                    from: {atomId: newAtomInstance.id, contactName: m.newPinName},
                    to: m.oldConn.to // External target
                };
            }
            _blueprint.internalConnections.push(newConn);
            
            var c1 = resolveContact(newConn.from);
            var c2 = resolveContact(newConn.to);
            if (c1 != null && c2 != null) c1.link(c2);
        }

        Impulsys.quickEmit("ATOM_RESTORED", {id: newAtomInstance.id, x: 300, y: 300, atom: newAtomInstance});
        Impulsys.quickEmit("REDRAW_WIRES");

        complete();
    }

    override public function undo():Void {
        trace("WARNING: GroupAtomsCommand undo not fully implemented");
    }

    private function saveNewAssembly(bp:Blueprint):Void {
        #if sys
        var data:Dynamic = { version: "1.0", blueprint: bp };
        var path = "library/" + bp.id + ".atom";
        sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
        #end
    }

    private function findAtomDef(id:String):AtomDef {
        for (a in _blueprint.internalAtoms) if (a.instanceId == id) return a;
        return null;
    }

    private function resolveContact(point:ConnectionPoint):Contact {
        if (point.atomId == "SELF") return null;
        var atom = _assembly.internalAtoms.get(point.atomId);
        if (atom == null) return null;
        var a:Atom = cast atom;
        return (a.getInput(point.contactName) != null) ? a.getInput(point.contactName) : a.getOutput(point.contactName);
    }

    override public function getDescription():String return 'Group ${_selectedNodeIds.length} Atoms';
}