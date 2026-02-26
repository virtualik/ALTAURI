package core;

import openfl.events.EventDispatcher;
import openfl.events.Event;

/**
 * Базовый абстрактный класс команды.
 * Реализует инфраструктуру: события завершения, обработку ошибок.
 * Аналог AS3 Command.
 */
class Command extends EventDispatcher implements ICommand {

    public function new() {
        super();
    }

    /**
     * Точка входа. Вызывается UndoManager'ом или вручную.
     * Оборачивает выполнение в try-catch для безопасности.
     */
    public function execute():Void {
        try {
            executeInternal();
        } catch (e:Dynamic) {
            trace('[Command Error] ${getDescription()}: $e');
            // Можно диспатчить событие ошибки, если нужно глобально ловить
        }
    }

    /**
     * Внутренняя логика. Должна быть переопределена в наследниках.
     */
    private function executeInternal():Void {
        // Override me
    }

    /**
     * Логика отката. Должна быть переопределена.
     */
    public function undo():Void {
        // Override me
    }

    /**
     * Описание команды (для логов и UI).
     */
    public function getDescription():String {
        return "Abstract Command";
    }

    /**
     * Метод завершения команды. Вызывается внутри executeInternal.
     */
    private function complete():Void {
        dispatchEvent(new Event(Event.COMPLETE));
    }
}