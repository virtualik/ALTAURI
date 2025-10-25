package Src.Prog.Core.Commands {
    /**
     * ICommand Interface - base contract for all application commands
     * Defines standard interface for Command pattern implementation
     *
     * Core component of command system - all commands must implement this interface
     * Enables uniform command execution and composition in command sequences
     */
    public interface ICommand {
        /**
         * Execute command - main interface method
         * Starts execution of logic encapsulated in command
         * Implementation should handle command-specific logic and error cases
         */
        function execute():void;
    }
}
