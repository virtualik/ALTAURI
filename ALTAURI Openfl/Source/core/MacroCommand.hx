package core;

import openfl.events.Event;

/**
 * Команда-контейнер.
 * Позволяет выполнять и отменять группу команд как одно действие.
 * Ключевой элемент для "Удалить атом с проводами".
 */
class MacroCommand extends Command {
    
    private var _subCommands:Array<ICommand>;

    public function new() {
        super();
        _subCommands = [];
    }

    /**
     * Добавить подкоманду в очередь.
     */
    public function addCommand(cmd:ICommand):Void {
        _subCommands.push(cmd);
    }

    /**
     * Выполнить все подкоманды последовательно.
     */
    override private function executeInternal():Void {
        for (cmd in _subCommands) {
            cmd.execute();
        }
        complete();
    }

    /**
     * Отменить все подкоманды в ОБРАТНОМ порядке.
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