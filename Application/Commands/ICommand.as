package Application.Commands {
    /**
     * ICommand Interface - base contract for all application commands
     * Defines standard interface for Command pattern implementation
     */
    public interface ICommand {
        /**
         * Execute command - main interface method
         * Starts execution of logic encapsulated in command
         */
        function execute():void;
    }
}
