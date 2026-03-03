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
 * GROUP ATOMS COMMAND v2.0 (Memory Leak Fixed)
 * Command to group selected atoms into a new Assembly.
 * 
 * FIXES v2.0:
 * - Send ATOM_DELETED impulse BEFORE modifying blueprint (allows NodeEditor to cleanup wires)
 * - Proper atom disposal using IDisposable interface
 * - Send REDRAW_WIRES after all changes complete
 * - Copy selectedIds array to avoid external mutation
 */
class GroupAtomsCommand extends Command {

    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _selectedNodeIds:Array<String>;

    public function new(blueprint:Blueprint, assembly:Assembly, selectedIds:Array<String>) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _selectedNodeIds = selectedIds.copy(); // Copy to avoid external mutation
    }

    override private function executeInternal():Void {
        if (_selectedNodeIds.length == 0) {
            trace("Nothing to group.");
            complete();
            return;
        }

        // 1. Collect data about internal atoms
        var newInternalAtoms:Array<AtomDef> = [];
        var newInternalConnections:Array<ConnectionDef> = [];
        var newPins:Array<{name:String, type:ContactType, ?dataType:String, ?defaultValue:Dynamic}> = [];
        var externalConnections:Array<{conn:ConnectionDef, isSourceSelected:Bool}> = [];

        // Separate connections
        for (conn in _blueprint.internalConnections) {
            var fromSel = _selectedNodeIds.indexOf(conn.from.atomId) != -1;
            var toSel = _selectedNodeIds.indexOf(conn.to.atomId) != -1;

            if (fromSel && toSel) {
                // Internal connection
                newInternalConnections.push(conn);
            } else {
                // External connection (boundary)
                externalConnections.push({conn: conn, isSourceSelected: fromSel});
            }
        }

        // List of atoms to include
        for (atomDef in _blueprint.internalAtoms) {
            if (_selectedNodeIds.indexOf(atomDef.instanceId) != -1) {
                newInternalAtoms.push(atomDef);
            }
        }

        // 2. Create interface (Pins) based on external connections
        var pinCounter = 0;
        var mapping:Array<{oldConn:ConnectionDef, newPinName:String, isInput:Bool}> = [];

        for (item in externalConnections) {
            var conn = item.conn;
            var pinName = "pin_" + pinCounter++;
            var pinType:ContactType = item.isSourceSelected ? OUTPUT : INPUT;

            // Create Pin Definition
            newPins.push({name: pinName, type: pinType, dataType: null, defaultValue: null});

            // Create connection inside new assembly
            if (item.isSourceSelected) {
                // Case A: Outgoing
                newInternalConnections.push({
                    from: conn.from,
                    to: {atomId: "SELF", contactName: pinName}
                });
            } else {
                // Case B: Incoming
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

        // Save to disk
        saveNewAssembly(newBp);

        // Register in runtime
        AtomRegistry.registerBlueprint(newTypeId, newBp);

        // 4. ✅ FIX: Send ATOM_DELETED impulses FIRST for proper wire cleanup!
        // This allows NodeEditor to clear wire sprites and their cacheAsBitmap
        for (id in _selectedNodeIds) {
            Impulsys.quickEmit("ATOM_DELETED", {id: id});
        }

        // 5. ✅ FIX: Properly dispose atoms before removal
        for (id in _selectedNodeIds) {
            var def = findAtomDef(id);
            if (def != null) _blueprint.internalAtoms.remove(def);

            var inst = _assembly.internalAtoms.get(id);
            if (inst != null) {
                // ✅ FIX: Proper disposal with IDisposable interface
                // This ensures any cached resources are released
                var disposable:IDisposable = cast inst;
                if (disposable != null) disposable.dispose();
                _assembly.internalAtoms.remove(id);
            }
        }

        // Remove old connections
        for (item in externalConnections) {
            _blueprint.internalConnections.remove(item.conn);
        }

        // 6. Create new atom instance
        var newAtomInstance = AssemblyFactory.createAtom(newTypeId, newTypeId + "_inst");
        _assembly.internalAtoms.set(newAtomInstance.id, newAtomInstance);
        _blueprint.internalAtoms.push({instanceId: newAtomInstance.id, typeId: newTypeId, x: 300, y: 300});

        // 7. Restore external connections
        for (m in mapping) {
            var newConn:ConnectionDef;
            if (m.isInput) {
                // Incoming
                newConn = {
                    from: m.oldConn.from,
                    to: {atomId: newAtomInstance.id, contactName: m.newPinName}
                };
            } else {
                // Outgoing
                newConn = {
                    from: {atomId: newAtomInstance.id, contactName: m.newPinName},
                    to: m.oldConn.to
                };
            }

            _blueprint.internalConnections.push(newConn);

            // Physical connection
            var c1 = resolveContact(newConn.from);
            var c2 = resolveContact(newConn.to);
            if (c1 != null && c2 != null) c1.link(c2);
        }

        // 8. Create view for new assembly
        Impulsys.quickEmit("ATOM_RESTORED", {id: newAtomInstance.id, x: 300, y: 300, atom: newAtomInstance});

        // 9. ✅ FIX: Force wire rebuild after all changes
        Impulsys.quickEmit("REDRAW_WIRES");

        complete();
    }

    override public function undo():Void {
        trace("WARNING: GroupAtomsCommand undo not fully implemented");
    }

    private function saveNewAssembly(bp:Blueprint):Void {
        #if sys
        var data:Dynamic = {
            version: "1.0",
            blueprint: bp
        };
        var path = "library/" + bp.id + ".atom";
        sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "  "));
        trace("Assembly saved to: " + path);
        #end
    }

    private function findAtomDef(id:String):AtomDef {
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == id) return a;
        }
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

