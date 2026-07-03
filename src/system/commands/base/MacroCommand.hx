package system.commands.base;

import openfl.events.Event;
import system.commands.base.Command;
import system.commands.base.ICommand;

/**
 * MACRO COMMAND v1.0
 * 
 * Container command that executes multiple commands as a single atomic action.
 * Enables batch operations with unified Undo/Redo.
 * 
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   MacroCommand                                                          │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Structure:                                                     │   │
 * │   │  - _subCommands:Array<ICommand>                                 │   │
 * │   │                                                                 │   │
 * │   │  Methods:                                                       │   │
 * │   │  - addCommand(cmd)      → Add command to queue                  │   │
 * │   │  - executeInternal()    → Execute all in order                  │   │
 * │   │  - undo()               → Undo all in REVERSE order             │   │
 * │   │  - getDescription()     → "Macro Command (N steps)"             │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Execution Order:                                                      │
 * │   ─────────────────                                                     │
 * │   execute():  cmd1 → cmd2 → cmd3 → ... → cmdN                           │
 * │   undo():     cmdN → ... → cmd3 → cmd2 → cmd1                           │
 * │                                                                         │
 * │   Use Cases:                                                            │
 * │   - Group multiple atoms deletion                                       │
 * │   - Batch wire connections                                              │
 * │   - Complex assembly operations                                         │
 * │   - Any multi-step atomic action                                        │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class MacroCommand extends Command {
    
    private var _subCommands:Array<ICommand>;
    
    public function new() {
        super();
        _subCommands = [];
    }
    
    /**
     * Add a subcommand to the execution queue.
     * Commands are executed in the order they are added.
     * 
     * @param cmd Command to add
     */
    public function addCommand(cmd:ICommand):Void {
        _subCommands.push(cmd);
    }
    
    /**
     * Execute all subcommands sequentially.
     * Each command's execute() is called in order.
     */
    override private function executeInternal():Void {
        for (cmd in _subCommands) {
            cmd.execute();
        }
        complete();
    }
    
    /**
     * Undo all subcommands in REVERSE order.
     * Critical for maintaining consistency - last action undone first.
     */
    override public function undo():Void {
        var i = _subCommands.length - 1;
        while (i >= 0) {
            _subCommands[i].undo();
            i--;
        }
    }
    
    /**
     * Get description with command count.
     */
    override public function getDescription():String {
        return 'Macro Command (${_subCommands.length} steps)';
    }
}