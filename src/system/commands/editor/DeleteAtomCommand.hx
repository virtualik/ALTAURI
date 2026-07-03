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
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;
import core.base.AssemblyFactory;
import library.AtomRegistry;

/**
 * DELETE ATOM COMMAND v1.0
 * Deletes an atom and its connections from the assembly.
 * Supports Undo/Redo with full snapshot restoration.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   DeleteAtomCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  1. saveSnapshot() — capture atom definition and connections    │   │
 * │   │  2. Remove connections from blueprint                           │   │
 * │   │  3. Unlink physical connections between contacts                │   │
 * │   │  4. Remove atom definition from blueprint                       │   │
 * │   │  5. Dispose atom instance                                       │   │
 * │   │  6. Remove instance from assembly                               │   │
 * │   │  7. Emit ATOM_DELETED event                                     │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  1. Restore atom definition to blueprint                        │   │
 * │   │  2. Recreate atom instance via AssemblyFactory                  │   │
 * │   │  3. Add instance to assembly                                    │   │
 * │   │  4. Restore connections to blueprint                            │   │
 * │   │  5. Emit ATOM_RESTORED event                                    │   │
 * │   │  6. Delayed: restorePhysicalConnections()                       │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Snapshot Data:                                                        │
 * │   ────────────────                                                      │
 * │   - _atomDef: AtomDef (position, type, values)                          │
 * │   - _atomType: String (blueprint type ID)                               │
 * │   - _connections: Array<ConnectionDef> (all connected wires)            │
 * │   - _posX, _posY: Float (atom position)                                 │
 * │                                                                         │
 * │   ID Resolution:                                                        │
 * │   ──────────────                                                        │
 * │   - Runtime ID → Template ID via assembly.getTemplateId()               │
 * │   - Template ID → Runtime ID via assembly.idMap                         │
 * │   - Both IDs checked when matching connections                          │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class DeleteAtomCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _atomId:String; // Runtime ID
    private var _atomDef:AtomDef;
    private var _atomType:String;
    private var _connections:Array<ConnectionDef>;
    private var _posX:Float;
    private var _posY:Float;

    public function new(blueprint:Blueprint, assembly:Assembly, atomId:String) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _atomId = atomId;
    }

    override private function executeInternal():Void {
        saveSnapshot();

        // Remove connections
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.remove(conn);
                var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
                var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
                if (cOut != null && cIn != null) cOut.unlink(cIn);
            }
        }

        // Remove atom definition
        if (_atomDef != null) {
            _blueprint.internalAtoms.remove(_atomDef);
        }

        // Remove atom instance
        var atomInstance = _assembly.internalAtoms.get(_atomId);
        if (atomInstance != null) {
            if (Std.isOfType(atomInstance, IDisposable)) {
                try { cast(atomInstance, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing: $e'); }
            }
            _assembly.internalAtoms.remove(_atomId);
        }

        Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: _atomId});
        complete();
    }

    override public function undo():Void {
        // Restore atom definition
        if (_atomDef != null) {
            _blueprint.internalAtoms.push(_atomDef);
        }

        // Ensure blueprint exists in registry
        var bp = AtomRegistry.get(_atomType);
        if (bp == null) {
            if (_atomDef != null && _atomDef.typeId != null) {
                bp = new Blueprint(_atomDef.typeId, _assembly.blueprint.name, [], null, [], []);
                AtomRegistry.registerBlueprint(bp.id, bp);
            }
        }

        // Recreate atom instance
        var atom = AssemblyFactory.createAtom(_atomType, _atomId);
        if (atom == null) { trace('DeleteAtomCommand.undo: Failed to create $_atomType'); return; }
        _assembly.internalAtoms.set(_atomId, atom);

        // Restore connections to blueprint
        if (_connections != null) {
            for (conn in _connections) {
                _blueprint.internalConnections.push(conn);
            }
        }

        Impulsys.quickEmit(EventType.ATOM_RESTORED, {
            assemblyId: _assembly.id,
            id: _atomId,
            x: _posX,
            y: _posY,
            atom: atom
        });

        // Delayed physical connection restore
        haxe.Timer.delay(restorePhysicalConnections, 10);
    }

    private function restorePhysicalConnections():Void {
        if (_connections == null) return;
        for (conn in _connections) {
            var cOut = resolveContact(conn.from.atomId, conn.from.contactName, OUTPUT);
            var cIn = resolveContact(conn.to.atomId, conn.to.contactName, INPUT);
            if (cOut != null && cIn != null) cOut.link(cIn);
        }
        Impulsys.quickEmit(EventType.REDRAW_WIRES);
    }

    /**
     * Capture complete atom state for undo restoration.
     */
    private function saveSnapshot():Void {
        if (_atomDef != null) return;

        // Find Template ID via Assembly
        var templateId = _assembly.getTemplateId(_atomId);

        // Find atom definition in Blueprint by TEMPLATE ID
        for (a in _blueprint.internalAtoms) {
            if (a.instanceId == templateId) {
                _atomDef = a;
                break;
            }
        }

        var atomInst = _assembly.internalAtoms.get(_atomId);
        if (atomInst != null) {
            // Take type from definition if available, otherwise from instance
            if (_atomDef != null) _atomType = _atomDef.typeId;
            else _atomType = atomInst.type;
            _posX = (_atomDef != null && _atomDef.x != null) ? _atomDef.x : 0;
            _posY = (_atomDef != null && _atomDef.y != null) ? _atomDef.y : 0;
        }

        _connections = [];

        // Collect connections using TEMPLATE ID
        for (conn in _blueprint.internalConnections) {
            // Check connections where our atom participates
            // Compare conn.atomId with templateId (for loaded) and with _atomId (for created)
            var fromMatch = (conn.from.atomId == templateId || conn.from.atomId == _atomId);
            var toMatch = (conn.to.atomId == templateId || conn.to.atomId == _atomId);
            if (fromMatch || toMatch) {
                _connections.push(conn);
            }
        }
    }

    /**
     * Resolve a contact by atom ID and contact name.
     * Handles SELF (assembly ports) and regular atoms.
     */
    private function resolveContact(atomId:String, contactName:String, type:ContactType):Contact {
        if (atomId == "SELF") {
            var port:ConductorPort = _assembly.ports.get(contactName);
            if (port == null) return null;
            return port.internal;
        } else {
            // Convert Template ID to Runtime ID if needed
            var realAtomId = _assembly.idMap.get(atomId);
            if (realAtomId == null) realAtomId = atomId; // Already Runtime ID

            var atom = _assembly.internalAtoms.get(realAtomId);
            if (atom == null) return null;
            var a:Atom = cast atom;
            return (type == INPUT) ? a.getInput(contactName) : a.getOutput(contactName);
        }
    }

    override public function getDescription():String return 'Delete Atom $_atomId';
}