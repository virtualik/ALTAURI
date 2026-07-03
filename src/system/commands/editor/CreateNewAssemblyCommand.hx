package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.data.Blueprint;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * CREATE NEW ASSEMBLY COMMAND v1.0
 * Creates a blank assembly context.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   CreateNewAssemblyCommand                                              │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Generate unique ID (asm_XXXXX)                               │   │
 * │   │  - Create empty Blueprint with no pins                          │   │
 * │   │  - Emit REQUEST_NEW_ASSEMBLY_CONTEXT event                      │   │
 * │   │  - Main.hx handles view stack update                            │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  - Emit REQUEST_CLOSE_CURRENT_CONTEXT event                     │   │
 * │   │  - Main.hx handles closing the new assembly tab                 │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Note: This command creates a NEW ROOT context, not a nested assembly. │
 * │   The actual Assembly instance is created by Main.hx in response to     │
 * │   the REQUEST_NEW_ASSEMBLY_CONTEXT event.                               │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class CreateNewAssemblyCommand extends Command {
    public function new() {
        super();
    }

    override private function executeInternal():Void {
        // Create unique ID
        var id = "asm_" + Std.random(100000);
        var bp = new Blueprint(id, "New Assembly", []);

        // We emit a special impulse for Main.hx to handle the view stack update
        // Main.hx is responsible for the Editor lifecycle
        Impulsys.quickEmit(EventType.REQUEST_NEW_ASSEMBLY_CONTEXT, { blueprint: bp, id: id });

        complete();
    }

    override public function undo():Void {
        // Undoing the creation of a new assembly usually means closing the tab/view.
        // This logic is handled by Main.hx listening to history changes or specific events.
        // For simplicity, we can emit a "CLOSE_CURRENT_CONTEXT" if needed,
        // but usually "New File" is not undone to "No File", but to "Previous File State".
        // Here we just signal to close.
        Impulsys.quickEmit(EventType.REQUEST_CLOSE_CURRENT_CONTEXT, {});
    }

    override public function getDescription():String return 'Create New Assembly';
}