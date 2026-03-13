package editor;

import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.data.Blueprint.AtomDef;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.Impulse;
import system.managers.UndoManager;
import system.commands.base.MacroCommand;
import system.commands.editor.CreateAtomCommand;
import system.commands.editor.DeleteAtomCommand;
import system.commands.editor.ConnectCommand;
import system.commands.editor.DeleteWiresCommand;
import system.commands.editor.MoveNodeCommand;
import system.commands.editor.AddPortCommand;
import system.commands.editor.RemovePortCommand;
import utils.UID;
import library.AtomRegistry;

/**
 * EDITOR ACTION HANDLER v1.0
 * Handles logic for modifying the schematic via Undo/Redo commands.
 * Extracted from NodeEditor.
 */
class EditorActionHandler {

    private var _assembly:Assembly;
    private var _blueprint:Blueprint;
    
    // Clipboard
    private static var _clipboard:{
        atoms:Array<ClipboardAtomData>,
        connections:Array<ConnectionDef>
    } = null;

    public function new(assembly:Assembly, blueprint:Blueprint) {
        _assembly = assembly;
        _blueprint = blueprint;
    }

    // ========================================================================
    // ATOMS
    // ========================================================================

    public function createAtom(typeId:String, x:Float, y:Float):Void {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return;
        
        var cmd = new CreateAtomCommand(_blueprint, _assembly, typeId, null, x, y);
        UndoManager.getInstance().executeAndStore(cmd);
    }

    public function deleteAtoms(ids:Array<String>):Void {
        if (ids == null || ids.length == 0) return;
        
        var macrocom = new MacroCommand();
        for (id in ids) {
            macrocom.addCommand(new DeleteAtomCommand(_blueprint, _assembly, id));
        }
        UndoManager.getInstance().executeAndStore(macrocom);
    }

    public function moveAtoms(moves:Array<{id:String, fromX:Float, fromY:Float, toX:Float, toY:Float}>):Void {
        var macrocom = new MacroCommand();
        for (m in moves) {
            macrocom.addCommand(new MoveNodeCommand(_blueprint, m.id, m.fromX, m.fromY, m.toX, m.toY));
        }
        UndoManager.getInstance().storeExecuted(macrocom);
    }

    // ========================================================================
    // CONNECTIONS
    // ========================================================================

    public function connect(fromId:String, fromContact:String, toId:String, toContact:String):Void {
        // Remove existing connection to input first (single input rule)
        var existingLink = findConnectionToInput(toId, toContact);
        if (existingLink != null) {
            deleteWires([getWireID(existingLink)]);
        }

        var cmd = new ConnectCommand(_blueprint, _assembly, fromId, fromContact, toId, toContact);
        UndoManager.getInstance().executeAndStore(cmd);
    }

    public function deleteWires(wireIds:Array<String>):Void {
        if (wireIds == null || wireIds.length == 0) return;
        var cmd = new DeleteWiresCommand(_blueprint, _assembly, wireIds);
        UndoManager.getInstance().executeAndStore(cmd);
    }

    // ========================================================================
    // PORTS
    // ========================================================================

    public function addPort(type:ContactType, ?name:String):Void {
        var cmd = new AddPortCommand(_assembly, type, name);
        UndoManager.getInstance().executeAndStore(cmd);
    }

    public function removePort(name:String):Void {
        var cmd = new RemovePortCommand(_assembly, name);
        UndoManager.getInstance().executeAndStore(cmd);
    }

    // ========================================================================
    // CLIPBOARD
    // ========================================================================

    public function copySelection(selectedIds:Array<String>):Void {
        if (selectedIds.length == 0) return;

        var atomsData:Array<ClipboardAtomData> = [];
        var connsData:Array<ConnectionDef> = [];

        // Collect atoms (positions are taken from Blueprint AtomDef)
        for (id in selectedIds) {
            var def = findAtomDef(id);
            if (def != null) {
                atomsData.push({
                    id: id,
                    typeId: def.typeId,
                    x: def.x,
                    y: def.y
                });
            }
        }

        // Collect connections
        if (_blueprint.internalConnections != null) {
            for (conn in _blueprint.internalConnections) {
                if (conn.from.atomId == "SELF" || conn.to.atomId == "SELF") continue;

                var fromTemplate = _assembly.getTemplateId(conn.from.atomId);
                var toTemplate = _assembly.getTemplateId(conn.to.atomId);

                var fromSelected = selectedIds.indexOf(fromTemplate) != -1 || selectedIds.indexOf(conn.from.atomId) != -1;
                var toSelected = selectedIds.indexOf(toTemplate) != -1 || selectedIds.indexOf(conn.to.atomId) != -1;

                if (fromSelected && toSelected) {
                    connsData.push(conn);
                }
            }
        }

        _clipboard = { atoms: atomsData, connections: connsData };
        trace('Copied ${atomsData.length} atoms');
    }

    public function cutSelection(selectedIds:Array<String>):Void {
        copySelection(selectedIds);
        deleteAtoms(selectedIds);
    }

    public function pasteSelection(offset:Float):Map<String, String> {
        if (_clipboard == null || _clipboard.atoms.length == 0) return null;

        var macrocom = new MacroCommand();
        var idMap = new Map<String, String>();

        // Create atoms
        for (data in _clipboard.atoms) {
            var newId = UID.generate();
            idMap.set(data.id, newId);

            var cmd = new CreateAtomCommand(
                _blueprint,
                _assembly,
                data.typeId,
                newId,
                data.x + offset,
                data.y + offset
            );
            macrocom.addCommand(cmd);
        }

        // Create connections
        for (conn in _clipboard.connections) {
            var sourceId = idMap.get(conn.from.atomId);
            if (sourceId == null) sourceId = idMap.get(_assembly.getTemplateId(conn.from.atomId));
            
            var targetId = idMap.get(conn.to.atomId);
            if (targetId == null) targetId = idMap.get(_assembly.getTemplateId(conn.to.atomId));

            if (sourceId != null && targetId != null) {
                var cmd = new ConnectCommand(
                    _blueprint,
                    _assembly,
                    sourceId,
                    conn.from.contactName,
                    targetId,
                    conn.to.contactName
                );
                macrocom.addCommand(cmd);
            }
        }

        UndoManager.getInstance().executeAndStore(macrocom);
        return idMap;
    }

    // ========================================================================
    // HELPERS
    // ========================================================================

    private function findConnectionToInput(atomId:String, contactName:String):ConnectionDef {
        if (_blueprint.internalConnections == null) return null;
        for (conn in _blueprint.internalConnections) {
            if (conn.to.atomId == atomId && conn.to.contactName == contactName) {
                return conn;
            }
        }
        return null;
    }

    private function getWireID(link:ConnectionDef):String {
        return '${link.from.atomId}_${link.from.contactName}->${link.to.atomId}_${link.to.contactName}';
    }

    private function findAtomDef(id:String):AtomDef {
        if (_blueprint.internalAtoms == null) return null;
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == id) return a;
        }
        var template = _assembly.getTemplateId(id);
        if (template != id) {
            for (a in _blueprint.internalAtoms) {
                if (a.instanceId == template) return a;
            }
        }
        return null;
    }
}

typedef ClipboardAtomData = {
    var id:String;
    var typeId:String;
    var x:Float;
    var y:Float;
}