package Src.Application.System.Core {
    import Src.Application.System.Core.Command;
    import Src.Application.System.Core.CommandErrorEvent;

    /**
     * Function invocation command wrapper
     * Encapsulates arbitrary function calls as command objects for integration with command system
     * 
     * Primary use cases:
     * - Integrating legacy code with command pattern
     * - Wrapping simple function calls for command sequences
     * - Rapid prototyping without creating dedicated command classes
     * 
     * Usage examples:
     * - new InvokeFunction(someFunction)
     * - new InvokeFunction(object.method, [param1, param2])
     * - new InvokeFunction(closureFunction)
     */
    public class InvokeFunction extends Command {
        /**
         * Function reference to be executed
         * Can be any Function object including methods, closures, or static functions
         */
        public var func:Function;
        
        /**
         * Optional arguments array for function invocation
         * Passed to function using Function.apply() when provided
         */
        public var args:Array;

        /**
         * Invoke function command constructor
         * @param func - Function object to be executed when command runs
         * @param args - Optional array of arguments to pass to the function (default null)
         */
        public function InvokeFunction(func:Function, args:Array = null) {
            super(0, null);
            this.func = func;
            this.args = args;
        }

        /**
         * Execute command - invoke wrapped function with provided arguments
         * Handles both parameterized and parameter-less function calls
         * Includes error handling for function execution failures
         */
        override protected function executeInternal():void {
            try {
                if (args != null && args.length > 0) {
                    func.apply(null, args);
                } else {
                    func();
                }
                complete();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(CommandErrorEvent.ERROR,
                    "InvokeFunction: Function execution failed - " + error.message));
            }
        }
    }
}
