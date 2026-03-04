package system.commands.editor;

import system.commands.base.Command;
import core.base.Assembly;
import core.data.Blueprint;
import core.logic.Impulsys;

/**
 * CREATE NEW ASSEMBLY COMMAND
 * Creates a blank assembly context.
 * Since this creates a new "Root" context, Undo typically closes it or reverts to previous state.
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
        Impulsys.quickEmit("REQUEST_NEW_ASSEMBLY_CONTEXT", { blueprint: bp, id: id });
        
        complete();
    }

    override public function undo():Void {
        // Undoing the creation of a new assembly usually means closing the tab/view.
        // This logic is handled by Main.hx listening to history changes or specific events.
        // For simplicity, we can emit a "CLOSE_CURRENT_CONTEXT" if needed, 
        // but usually "New File" is not undone to "No File", but to "Previous File State".
        // Here we just signal to close.
        Impulsys.quickEmit("REQUEST_CLOSE_CURRENT_CONTEXT", {});
    }

    override public function getDescription():String return 'Create New Assembly';
}