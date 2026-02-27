package system.commands.base;

import openfl.events.Event;
import system.commands.base.Command;
import system.commands.base.ICommand;

/**
 * MACRO COMMAND
 * Container command.
 * Allows executing and undoing a group of commands as a single action.
 */
class MacroCommand extends Command {

    private var _subCommands:Array<ICommand>;

    public function new() {
        super();
        _subCommands = [];
    }

    /**
     * Add a subcommand to the queue.
     */
    public function addCommand(cmd:ICommand):Void {
        _subCommands.push(cmd);
    }

    /**
     * Execute all subcommands sequentially.
     */
    override private function executeInternal():Void {
        for (cmd in _subCommands) {
            cmd.execute();
        }
        complete();
    }

    /**
     * Undo all subcommands in REVERSE order.
     */
    override public function undo():Void {
        var i = _subCommands.length - 1;
        while (i >= 0) {
            _subCommands[i].undo();
            i--;
        }
    }

    override public function getDescription():String {
        return 'Macro Command (${_subCommands.length} steps)';
    }
}