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
 * EDITOR ACTION HANDLER v1.2 (Paste State Replication)
 * Handles logic for modifying the schematic via Undo/Redo commands.
 * Extracted from NodeEditor for better separation of concerns.
 *
 * v1.2 CHANGES (WP-2 Paste Semantics):
 *  - copySelection() now captures each atom's per-instance state snapshot
 *    (getPersistentState, sanitized) and its AtomDef.visualMode.
 *  - pasteSelection() forwards both to CreateAtomCommand, so a pasted atom
 *    replicates the source: toggle position, assembly internalStates,
 *    driver configs, node visual mode. The blueprint (structure) remains
 *    shared — ALTAURI's template semantics are preserved by design; the
 *    INSTANCE is what gets copied, exactly like a Unity prefab instance
 *    or an Unreal Blueprint actor.
 *  - _sanitizeStateForPaste(): strips displayName (owned by the paste
 *    naming path — source "Foo_2" pastes as "Foo_3") and wasOpen
 *    (ComPortAtom runtime reopen request — a copy must not race the
 *    source for the same serial port).
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   EditorActionHandler                                                   │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Atom Operations:                                               │   │
 * │   │  - createAtom(typeId, x, y)     → CreateAtomCommand             │   │
 * │   │  - deleteAtoms(ids)             → MacroCommand[DeleteAtomCmd]   │   │
 * │   │  - moveAtoms(moves)             → MacroCommand[MoveNodeCmd]     │   │
 * │   │                                                                 │   │
 * │   │  Connection Operations:                                         │   │
 * │   │  - connect(fromId, fromContact, toId, toContact)                │   │
 * │   │                         → ConnectCommand                        │   │
 * │   │  - deleteWires(wireIds)  → DeleteWiresCommand                   │   │
 * │   │                                                                 │   │
 * │   │  Port Operations:                                               │   │
 * │   │  - addPort(type, ?name)    → AddPortCommand                     │   │
 * │   │  - removePort(name)        → RemovePortCommand                  │   │
 * │   │                                                                 │   │
 * │   │  Clipboard Operations:                                          │   │
 * │   │  - copySelection(ids)      → Store atoms + connections + names  │   │
 * │   │  - cutSelection(ids)       → copy + delete                      │   │
 * │   │  - pasteSelection(offset)  → CreateAtom + Connect commands      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var handler = new EditorActionHandler(assembly, blueprint, checker);  │
 * │   handler.createAtom("Button", 100, 200);                               │
 * │   handler.connect("id_abc", "out", "id_def", "in");                     │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class EditorActionHandler
{
    // =========================================================================
    // DEPENDENCIES
    // =========================================================================
    private var _assembly:Assembly;
    private var _blueprint:Blueprint;
    
    // v1.1: Callback for checking global name uniqueness
    private var _isNameTakenGlobally:(String, ?String) -> Bool;
    // =========================================================================
    // CLIPBOARD
    // =========================================================================
    private static var _clipboard:{
        atoms:Array<ClipboardAtomData>,
        connections:Array<ConnectionDef>
    } = null;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    // v1.1: Added isNameTakenGlobally parameter
        

        public function new(assembly:Assembly, blueprint:Blueprint, ?isNameTakenGlobally:(String, ?String) -> Bool)
    {
        _assembly = assembly;
        _blueprint = blueprint;
        _isNameTakenGlobally = isNameTakenGlobally;
    }
    
    // =========================================================================
    // ATOM OPERATIONS
    // =========================================================================
    /**
     * Create a new atom at specified position.
     */
    public function createAtom(typeId:String, x:Float, y:Float):Void
    {
        var bp = AtomRegistry.get(typeId);
        if (bp == null) return;
        
        // v1.1: Pass global name checker, no desired name, isPaste = false
        var cmd = new CreateAtomCommand(
            _blueprint, 
            _assembly, 
            typeId, 
            null, 
            x, 
            y, 
            _isNameTakenGlobally, 
            null, 
            false
        );
        UndoManager.getInstance().executeAndStore(cmd);
    }

        /**
        * Creates an atom with a pre-known ID.
        * This is needed for programmatic scripting so we can connect the atoms right away.
        */
        public function createAtomWithId(typeId:String, instanceId:String, x:Float, y:Float):Void
        {
                var cmd = new CreateAtomCommand(
                        _blueprint,
                        _assembly,
                        typeId,
                        instanceId, // Passing our generated ID
                        x,
                        y,
                        _isNameTakenGlobally,
                        null,
                        false
                );
                UndoManager.getInstance().executeAndStore(cmd);
        }

    /**
     * Delete multiple atoms (batch operation).
     */
    public function deleteAtoms(ids:Array<String>):Void
    {
        if (ids == null || ids.length == 0) return;
        
        var macrocom = new MacroCommand();
        for (id in ids)
        {
            macrocom.addCommand(new DeleteAtomCommand(_blueprint, _assembly, id));
        }
        UndoManager.getInstance().executeAndStore(macrocom);
    }
    
    /**
     * Move multiple atoms (batch operation).
     */
    public function moveAtoms(moves:Array<{id:String, fromX:Float, fromY:Float, toX:Float, toY:Float}>):Void
    {
        var macrocom = new MacroCommand();
        for (m in moves)
        {
            macrocom.addCommand(new MoveNodeCommand(_blueprint, m.id, m.fromX, m.fromY, m.toX, m.toY));
        }
        UndoManager.getInstance().storeExecuted(macrocom);
    }
    
    // =========================================================================
    // CONNECTION OPERATIONS
    // =========================================================================
    /**
     * Connect two contacts.
     * Removes existing connection to input first (single input rule).
     */
    public function connect(fromId:String, fromContact:String, toId:String, toContact:String):Void
    {
        // Remove existing connection to input first (single input rule)
        var existingLink = findConnectionToInput(toId, toContact);
        if (existingLink != null)
        {
            deleteWires([getWireID(existingLink)]);
        }
        
        var cmd = new ConnectCommand(_blueprint, _assembly, fromId, fromContact, toId, toContact);
        UndoManager.getInstance().executeAndStore(cmd);
    }
    
    /**
     * Delete multiple wires (batch operation).
     */
    public function deleteWires(wireIds:Array<String>):Void
    {
        if (wireIds == null || wireIds.length == 0) return;
        
        var cmd = new DeleteWiresCommand(_blueprint, _assembly, wireIds);
        UndoManager.getInstance().executeAndStore(cmd);
    }
    
    // =========================================================================
    // PORT OPERATIONS
    // =========================================================================
    /**
     * Add a new gateway port to assembly.
     */
    public function addPort(type:ContactType, ?name:String):Void
    {
        var cmd = new AddPortCommand(_assembly, type, name);
        UndoManager.getInstance().executeAndStore(cmd);
    }
    
    /**
     * Remove a gateway port and its connections.
     */
    public function removePort(name:String):Void
    {
        var cmd = new RemovePortCommand(_assembly, name);
        UndoManager.getInstance().executeAndStore(cmd);
    }
    
    // =========================================================================
    // CLIPBOARD OPERATIONS
    // =========================================================================
    /**
     * Copy selected atoms and their internal connections to clipboard.
     * v1.1: Now also captures the displayName of each atom.
     */
    public function copySelection(selectedIds:Array<String>):Void
    {
        if (selectedIds.length == 0) return;
        
        var atomsData:Array<ClipboardAtomData> = [];
        var connsData:Array<ConnectionDef> = [];
        
        // Collect atoms (positions are taken from Blueprint AtomDef)
        for (id in selectedIds)
        {
            var def = findAtomDef(id);
            if (def != null)
            {
                // v1.1: Try to get the actual atom instance to read its displayName
                var atomInst:Atom = _assembly.internalAtoms.get(id);
                if (atomInst == null)
                {
                    var runtimeId = _assembly.idMap.get(id);
                    if (runtimeId != null) atomInst = _assembly.internalAtoms.get(runtimeId);
                }
                var dName = (atomInst != null) ? atomInst.displayName : null;

                // v1.2: capture the per-instance state snapshot so paste
                // replicates the source (toggle position, assembly
                // internalStates, driver configs). Volatile fields are
                // stripped — see _sanitizeStateForPaste().
                var values = (atomInst != null)
                    ? _sanitizeStateForPaste(atomInst.getPersistentState())
                    : null;

                atomsData.push({
                    id: id,
                    typeId: def.typeId,
                    x: def.x,
                    y: def.y,
                    displayName: dName, // v1.1: Store original display name
                    values: values,      // v1.2: sanitized state snapshot
                    visualMode: def.visualMode // v1.2: node appearance
                });
            }
        }
        
        // Collect connections
        if (_blueprint.internalConnections != null)
        {
            for (conn in _blueprint.internalConnections)
            {
                if (conn.from.atomId == "SELF" || conn.to.atomId == "SELF") continue;
                
                var fromTemplate = _assembly.getTemplateId(conn.from.atomId);
                var toTemplate = _assembly.getTemplateId(conn.to.atomId);
                
                var fromSelected = selectedIds.indexOf(fromTemplate) != -1 || selectedIds.indexOf(conn.from.atomId) != -1;
                var toSelected = selectedIds.indexOf(toTemplate) != -1 || selectedIds.indexOf(conn.to.atomId) != -1;
                
                if (fromSelected && toSelected)
                {
                    connsData.push(conn);
                }
            }
        }
        
        _clipboard = { atoms: atomsData, connections: connsData };
        trace('Copied ${atomsData.length} atoms');
    }
    
    /**
     * v1.2: Prepare a per-instance state snapshot for clipboard/paste.
     *
     * Shallow-copies the top level of getPersistentState() and strips the
     * fields a copy must NOT inherit:
     *  - displayName: owned by the paste naming path (source "Foo_2"
     *    pastes as "Foo_3" via AssemblyFactory.generateUniqueDisplayName);
     *  - wasOpen (ComPortAtom): a runtime port-reopen request — a pasted
     *    copy must not race the source instance for the same serial port.
     *
     * Nested state (Assembly.internalStates with per-atom values) is kept
     * as-is: the pasted instance shares the blueprint, so template-ID keys
     * resolve on the copy exactly like on the source (same map as load).
     */
    private function _sanitizeStateForPaste(state:Dynamic):Dynamic
    {
        if (state == null) return null;
        var copy:Dynamic = {};
        for (field in Reflect.fields(state))
        {
            if (field == "displayName" || field == "wasOpen") continue;
            Reflect.setField(copy, field, Reflect.field(state, field));
        }
        return copy;
    }
    
    /**
     * Cut selected atoms (copy + delete).
     */
    public function cutSelection(selectedIds:Array<String>):Void
    {
        copySelection(selectedIds);
        deleteAtoms(selectedIds);
    }
    
    /**
     * Paste atoms from clipboard with offset.
     * Creates new atoms and connections.
     * 
     * @param offset Position offset for pasted atoms
     * @return Map of old ID → new ID (for selection update)
     */
    public function pasteSelection(offset:Float):Map<String, String>
    {
        if (_clipboard == null || _clipboard.atoms.length == 0) return null;
        
        var macrocom = new MacroCommand();
        var idMap = new Map<String, String>();
        
        // Create atoms
        for (data in _clipboard.atoms)
        {
            var newId = UID.generate();
            idMap.set(data.id, newId);
            
            // v1.1: Pass global name checker, desired name from clipboard, and isPaste = true
            // v1.2: also pass the sanitized state snapshot + visual mode so
            // the pasted atom replicates the source instance.
            var cmd = new CreateAtomCommand(
                _blueprint,
                _assembly,
                data.typeId,
                newId,
                data.x + offset,
                data.y + offset,
                _isNameTakenGlobally,
                data.displayName,
                true, // isPaste = true forces suffix increment
                data.values,    // v1.2: replicate source state
                data.visualMode // v1.2: replicate node visual mode
            );
            macrocom.addCommand(cmd);
        }
        
        // Create connections
        for (conn in _clipboard.connections)
        {
            var sourceId = idMap.get(conn.from.atomId);
            if (sourceId == null) sourceId = idMap.get(_assembly.getTemplateId(conn.from.atomId));
            
            var targetId = idMap.get(conn.to.atomId);
            if (targetId == null) targetId = idMap.get(_assembly.getTemplateId(conn.to.atomId));
            
            if (sourceId != null && targetId != null)
            {
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
    
    // =========================================================================
    // HELPERS
    // =========================================================================
    /**
     * Find existing connection to a specific input contact.
     * Used to enforce single-input rule.
     */
    private function findConnectionToInput(atomId:String, contactName:String):ConnectionDef
    {
        if (_blueprint.internalConnections == null) return null;
        
        var targetTemplateId = _assembly.getTemplateId(atomId);
        
        for (conn in _blueprint.internalConnections)
        {
            if (conn.to.contactName == contactName)
            {
                // Check match by Template ID (loaded connections)
                // OR by Runtime ID (session-created connections)
                if (conn.to.atomId == targetTemplateId || conn.to.atomId == atomId)
                {
                    return conn;
                }
            }
        }
        return null;
    }
    
    /**
     * Generate wire ID from connection definition.
     */
    private function getWireID(link:ConnectionDef):String
    {
        // Important: use ID from the connection itself (Template ID),
        // as link is taken from blueprint
        return '${link.from.atomId}_${link.from.contactName}->${link.to.atomId}_${link.to.contactName}';
    }
    
    /**
     * Find atom definition in blueprint by ID.
     */
    private function findAtomDef(id:String):AtomDef
    {
        if (_blueprint.internalAtoms == null) return null;
        
        for (a in _blueprint.internalAtoms)
        {
            if (a.instanceId == id) return a;
        }
        
        var template = _assembly.getTemplateId(id);
        if (template != id)
        {
            for (a in _blueprint.internalAtoms)
            {
                if (a.instanceId == template) return a;
            }
        }
        return null;
    }
}

// v1.1: Added optional displayName to preserve original name during copy/paste
// v1.2: Added optional values (sanitized getPersistentState snapshot) and
// visualMode so pasted atoms replicate the source instance's state/appearance.
typedef ClipboardAtomData = {
    var id:String;
    var typeId:String;
    var x:Float;
    var y:Float;
    @:optional var displayName:String;
    @:optional var values:Dynamic;
    @:optional var visualMode:String;
}
