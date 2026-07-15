package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.data.Blueprint;
import core.types.ContactType;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                CREATE NEW ASSEMBLY COMMAND v2.0                           ║
 * ║                (Semantic Initial Ports: incoming/outgoing)                 ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Creates a blank assembly context with semantic initial ports.            ║
 * ║                                                                           ║
 * ║  v2.0 Changes:                                                            ║
 * ║  - Initial ports use semantic naming: incoming_1 (INPUT), outgoing_1 (OUT)║
 * ║  - External names match internal names for new assemblies                 ║
 * ║                                                                           ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │  New Assembly (empty):                                              │  ║
 * ║  │                                                                     │  ║
 * ║  │  External view:   [incoming_1] ─── Assembly ─── [outgoing_1]       │  ║
 * ║  │                                                                     │  ║
 * ║  │  Internal view:   ┌── incoming_1 (INPUT)                           │  ║
 * ║  │                   │                                                 │  ║
 * ║  │                   └── outgoing_1 (OUTPUT) ──┘                      │  ║
 * ║  │                                                                     │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class CreateNewAssemblyCommand extends Command {
    public function new() {
        super();
    }

    override private function executeInternal():Void {
        var id = "asm_" + Std.random(100000);
        
        // v2.0: Semantic initial ports
        // External name = Internal name for new assemblies (user can rename later)
        var pins:Array<core.data.Blueprint.PinDef> = [
            {
                name: "incoming_1",           // Internal name (wall)
                type: INPUT,
                externalName: "incoming_1"    // External name (parent view)
            },
            {
                name: "outgoing_1",           // Internal name (wall)
                type: OUTPUT,
                externalName: "outgoing_1"    // External name (parent view)
            }
        ];
        
        var bp = new Blueprint(id, "New Assembly", pins);
        
        Impulsys.quickEmit(EventType.REQUEST_NEW_ASSEMBLY_CONTEXT, { blueprint: bp, id: id });
        complete();
    }

    override public function undo():Void {
        Impulsys.quickEmit(EventType.REQUEST_CLOSE_CURRENT_CONTEXT, {});
    }

    override public function getDescription():String return 'Create New Assembly';
}