package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.base.Contact;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     MOVE PORT COMMAND v1.0                                 ║
 * ║          (Reorder gateway ports: Move Up / Move Down)                      ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Moves a gateway port one slot up or down WITHIN its own type column.     ║
 * ║  Because PortNaming names are POSITIONAL IDENTITIES, not positions,       ║
 * ║  reordering never renames anything and never touches wires:               ║
 * ║  connections reference names + template IDs, so a moved port keeps        ║
 * ║  every wire attached. The swap is pure cosmetics + persistence:           ║
 * ║                                                                           ║
 * ║    blueprint.pins order        → saved order + NodeEditor wall ports      ║
 * ║      (NodeEditor.drawFrame → Assembly.getOrderedPorts → pins.copy())      ║
 * ║    _inputs / _outputs order    → NodeView of this assembly in the parent  ║
 * ║                                                                           ║
 * ║  Both sides move together through the wall: Inlet_N outside always        ║
 * ║  faces Arrival_N inside (same pin object, one swap).                      ║
 * ║                                                                           ║
 * ║  Menu gating: ContextMenuManager shows "Move Up"/"Move Down" only when    ║
 * ║  neighborPinIndex() finds a same-type neighbor in that direction          ║
 * ║  (first/last port in a column offers no move past the edge).              ║
 * ║                                                                           ║
 * ║  Undo: the swap is its own inverse — re-run with the inverted direction.  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class MovePortCommand extends Command {
    private var _assembly:Assembly;
    private var _portName:String;
    private var _up:Bool;

    /** Guards undo(): only invert after a successful execute. */
    private var _didMove:Bool = false;

    public function new(assembly:Assembly, portName:String, up:Bool) {
        super();
        _assembly = assembly;
        _portName = portName;
        _up = up;
    }

    /**
     * Shared neighbor lookup (single source of truth for menu + command).
     *
     * Finds the index of the NEAREST pin of the SAME TYPE above/below the
     * named pin in blueprint.pins. Inputs and outputs live in separate
     * visual columns, so a neighbor of the other type is skipped, not used.
     *
     * @return neighbor pin index, or -1 when the port is at the column edge
     *         (or the port/blueprint was not found).
     */
    public static function neighborPinIndex(assembly:Assembly, portName:String, up:Bool):Int {
        if (assembly == null || assembly.blueprint == null || assembly.blueprint.pins == null) return -1;
        var pins = assembly.blueprint.pins;

        var idx:Int = -1;
        var pinType:ContactType = null;
        for (i in 0...pins.length) {
            var p = pins[i];
            if (p != null && p.name == portName) {
                idx = i;
                pinType = p.type;
                break;
            }
        }
        if (idx == -1) return -1;

        var step:Int = up ? -1 : 1;
        var j:Int = idx + step;
        while (j >= 0 && j < pins.length) {
            var p = pins[j];
            if (p != null && p.type == pinType) return j;
            j += step;
        }
        return -1;
    }

    override private function executeInternal():Void {
        if (swap(_up)) {
            Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
        }
        complete();
    }

    override public function undo():Void {
        if (!_didMove) return;
        if (swap(!_up)) {
            Impulsys.quickEmit(EventType.ASSEMBLY_PORTS_CHANGED, { assemblyId: _assembly.id });
        }
    }

    /**
     * Performs the actual swap in BOTH order sources. Returns false (and
     * changes nothing) when the move is impossible.
     */
    private function swap(up:Bool):Bool {
        if (_assembly == null || _assembly.blueprint == null || _assembly.blueprint.pins == null) return false;
        var pins = _assembly.blueprint.pins;

        // 1. Locate the pin
        var idx:Int = -1;
        var pinType:ContactType = null;
        for (i in 0...pins.length) {
            var p = pins[i];
            if (p != null && p.name == _portName) {
                idx = i;
                pinType = p.type;
                break;
            }
        }
        if (idx == -1) return false;

        // 2. Same-type neighbor in the requested direction
        var neighborIdx:Int = neighborPinIndex(_assembly, _portName, up);
        if (neighborIdx == -1) return false;

        // 3. Swap in blueprint.pins (wall order + persisted order)
        var pin = pins[idx];
        pins.splice(idx, 1);
        pins.insert(neighborIdx, pin);

        // 4. Swap the port's Contact in _inputs/_outputs (parent-side
        //    NodeView order). getInputs()/getOutputs() return the live
        //    arrays, so an in-place element swap persists.
        //    Null guard: a disposed assembly has null arrays (Recent-menu
        //    replay can outlive the node) — reorder pins only, skip this.
        var port = _assembly.ports.get(_portName);
        if (port != null && port.external != null) {
            var arr:Array<Contact> = (pinType == INPUT)
                ? _assembly.getInputs()
                : _assembly.getOutputs();
            if (arr != null) {
                var ci:Int = arr.indexOf(port.external);
                var ni:Int = ci + (up ? -1 : 1);
                if (ci != -1 && ni >= 0 && ni < arr.length) {
                    var tmp:Contact = arr[ci];
                    arr[ci] = arr[ni];
                    arr[ni] = tmp;
                }
            }
        }

        _didMove = true;
        return true;
    }

    override public function getDescription():String return 'Move Port $_portName ${_up ? "Up" : "Down"}';
}
