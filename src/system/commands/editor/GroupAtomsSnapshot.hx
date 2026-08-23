package system.commands.editor;

import core.data.Blueprint;
import core.data.Blueprint.AtomDef;
import core.data.Blueprint.ConnectionDef;
import core.data.Blueprint.ConnectionPoint;
import core.types.ContactType;

/**
 * GROUP ATOMS SNAPSHOT v2.1
 * Complete data container for GroupAtomsCommand undo/redo.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   GroupAtomsSnapshot                                                    │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  REMOVED DATA (restore on undo):                                │   │
 * │   │  - _removedAtomDefs: Array<AtomDef>                             │   │
 * │   │  - _removedInternalConnections: Array<ConnectionDef>            │   │
 * │   │  - _removedExternalConnections: Array<ConnectionDef>            │   │
 * │   │  - _selectedNodeIds: Array<String>                              │   │
 * │   │                                                                 │   │
 * │   │  CREATED DATA (delete on undo):                                 │   │
 * │   │  - _createdTypeId: String                                       │   │
 * │   │  - _createdInstanceId: String                                   │   │
 * │   │  - _createdAtomDef: AtomDef                                     │   │
 * │   │  - _createdConnections: Array<ConnectionDef>                    │   │
 * │   │                                                                 │   │
 * │   │  PORT MAPPINGS:                                                 │   │
 * │   │  - _portMappings: Array<PortMapping>                            │   │
 * │   │    (original connection → port name → is input)                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Stores all data needed to completely reverse a grouping operation:    │
 * │   - Removed atoms (definitions and positions)                           │
 * │   - Removed connections (internal and external)                         │
 * │   - Port mappings (external connections -> assembly ports)              │
 * │   - Created assembly data (for removal on undo)                         │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class GroupAtomsSnapshot {
    // =========================================================================
    // REMOVED DATA (restore on undo)
    // =========================================================================
    private var _removedAtomDefs:Array<AtomDef>;
    private var _removedInternalConnections:Array<ConnectionDef>;
    private var _removedExternalConnections:Array<ConnectionDef>;
    private var _selectedNodeIds:Array<String>;
    
    // =========================================================================
    // CREATED DATA (delete on undo)
    // =========================================================================
    private var _createdTypeId:String;
    private var _createdInstanceId:String;
    private var _createdAtomDef:AtomDef;
    private var _createdConnections:Array<ConnectionDef>;
    
    // =========================================================================
    // PORT MAPPINGS
    // =========================================================================
    private var _portMappings:Array<PortMapping>;
    
    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public function new() {
        _removedAtomDefs = [];
        _removedInternalConnections = [];
        _removedExternalConnections = [];
        _selectedNodeIds = [];
        _createdConnections = [];
        _portMappings = [];
    }
    
    // =========================================================================
    // GETTERS
    // =========================================================================
    public function getRemovedAtomDefs():Array<AtomDef> return _removedAtomDefs;
    public function getRemovedInternalConnections():Array<ConnectionDef> return _removedInternalConnections;
    public function getRemovedExternalConnections():Array<ConnectionDef> return _removedExternalConnections;
    public function getCreatedConnections():Array<ConnectionDef> return _createdConnections;
    public function getPortMappings():Array<PortMapping> return _portMappings;
    public function getCreatedTypeId():String return _createdTypeId;
    public function getCreatedInstanceId():String return _createdInstanceId;
    public function getCreatedAtomDef():AtomDef return _createdAtomDef;
    
    // =========================================================================
    // ADD METHODS
    // =========================================================================
    /**
     * Add an atom definition that will be removed.
     */
    public function addRemovedAtom(def:AtomDef):Void {
        // v2.1: Reflect.copy preserves ALL fields — values (displayName,
        // driver config, wasOpen), visualMode, and any future AtomDef
        // field. The previous stripped clone dropped them, so undo
        // resurrected atoms without configuration.
        _removedAtomDefs.push(Reflect.copy(def));
    }
    
    /**
     * Add an internal connection that will be removed.
     */
    public function addRemovedInternalConnection(conn:ConnectionDef):Void {
        _removedInternalConnections.push(cloneConnection(conn));
    }
    
    /**
     * Add an external connection that will be converted to port.
     */
    public function addRemovedExternalConnection(conn:ConnectionDef):Void {
        _removedExternalConnections.push(cloneConnection(conn));
    }
    
    /**
     * Set the selected node IDs.
     */
    public function setSelectedNodeIds(ids:Array<String>):Void {
        _selectedNodeIds = ids != null ? ids.copy() : [];
    }
    
    /**
     * Add a port mapping for undo restore.
     * @param originalConn The original external connection
     * @param portName The port name in new assembly
     * @param isInput Whether this is an input port
     */
    public function addPortMapping(originalConn:ConnectionDef, portName:String, isInput:Bool):Void {
        _portMappings.push({
            originalConnection: cloneConnection(originalConn),
            portName: portName,
            isInput: isInput
        });
    }
    
    /**
     * Store created assembly data for undo deletion.
     */
    public function setCreatedData(
        typeId:String,
        instanceId:String,
        atomDef:AtomDef,
        connections:Array<ConnectionDef>
    ):Void {
        _createdTypeId = typeId;
        _createdInstanceId = instanceId;
        
        if (atomDef != null) {
            _createdAtomDef = {
                instanceId: atomDef.instanceId,
                typeId: atomDef.typeId,
                x: atomDef.x,
                y: atomDef.y
            };
        }
        
        if (connections != null) {
            _createdConnections = [];
            for (c in connections) {
                _createdConnections.push(cloneConnection(c));
            }
        }
    }
    
    // =========================================================================
    // VALIDATION
    // =========================================================================
    /**
     * Validate snapshot has all required data for undo.
     * @return Error message or null if valid
     */
    public function validate():String {
        if (_removedAtomDefs == null || _removedAtomDefs.length == 0) {
            return "No atoms captured for restore";
        }
        
        if (_createdTypeId == null || _createdTypeId.length == 0) {
            return "Created assembly type ID not captured";
        }
        
        if (_createdInstanceId == null || _createdInstanceId.length == 0) {
            return "Created assembly instance ID not captured";
        }
        
        return null; // Valid
    }
    
    // =========================================================================
    // UTILITY
    // =========================================================================
    private function cloneConnection(conn:ConnectionDef):ConnectionDef {
        if (conn == null) return null;
        return {
            from: {
                atomId: conn.from.atomId,
                contactName: conn.from.contactName
            },
            to: {
                atomId: conn.to.atomId,
                contactName: conn.to.contactName
            }
        };
    }
    
    /**
     * Clear all stored data.
     */
    public function dispose():Void {
        if (_removedAtomDefs != null) {
            #if cpp
            cpp.vm.Gc.setFinalizer(_removedAtomDefs, null);
            #end
            _removedAtomDefs = [];
        }
        
        if (_removedInternalConnections != null) {
            _removedInternalConnections = [];
        }
        
        if (_removedExternalConnections != null) {
            _removedExternalConnections = [];
        }
        
        if (_selectedNodeIds != null) {
            _selectedNodeIds = [];
        }
        
        if (_createdConnections != null) {
            _createdConnections = [];
        }
        
        if (_portMappings != null) {
            _portMappings = [];
        }
        
        _createdTypeId = null;
        _createdInstanceId = null;
        _createdAtomDef = null;
    }
    
    /**
     * Debug string.
     */
    public function toString():String {
        return 'GroupAtomsSnapshot{' +
            'atoms=${_removedAtomDefs != null ? _removedAtomDefs.length : 0}, ' +
            'intConns=${_removedInternalConnections != null ? _removedInternalConnections.length : 0}, ' +
            'extConns=${_removedExternalConnections != null ? _removedExternalConnections.length : 0}, ' +
            'ports=${_portMappings != null ? _portMappings.length : 0}, ' +
            'created=$_createdTypeId' +
            '}';
    }
}

// =============================================================================
// PORT MAPPING TYPEDEF
// =============================================================================
/**
 * Port mapping record.
 * Stores the relationship between an original external connection
 * and its corresponding port in the created assembly.
 */
typedef PortMapping = {
    /**
     * The original connection before it was converted to a port.
     */
    var originalConnection:ConnectionDef;
    
    /**
     * The port name assigned in the new assembly.
     */
    var portName:String;
    
    /**
     * true = input port (external -> internal)
     * false = output port (internal -> external)
     */
    var isInput:Bool;
}