package Application.Windows {
    import Application.MultiPulsator.Impulse;
    import Application.MultiPulsator.MultiPulsator;
    import flash.text.TextField;
    import Application.Windows.Components.ConsoleWindowContent;

    /**
     * Console Window - system console for log and message output
     * Specialized window for displaying system messages and logs
     */
    public class ConsoleWindow extends BaseWindow {
        /**
         * Console Window constructor
         * Creates console window with standard system chrome
         * @param alpha - transparency flag (not used for standard chrome)
         */
        public function ConsoleWindow(alpha:Boolean):void {
            super("Console", "Console Window", alpha, "standard");

            MultiPulsator.subscribeToImpulse("CONSOLE_LOG_MESSAGE", reactor_CONSOLE_LOG_MESSAGE);
        }

        /**
         * Initialize console scene
         * Overrides base method for console-specific graphic content
         */
        override protected function initializeScene():void {
            super.initializeScene();

            _sceneCover.graphics.beginFill(0x333333, 1.0);
            _sceneCover.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            _sceneCover.graphics.endFill();

            _content = new ConsoleWindowContent(_sceneCover, stage.stageWidth, stage.stageHeight);
        }

        /**
         * Console message reactor - handles logging impulses
         * Processes CONSOLE_LOG_MESSAGE impulses and displays messages
         */
        private function reactor_CONSOLE_LOG_MESSAGE(impulse:Impulse):void {
            if (impulse && impulse.data && impulse.data.message) {
                var textField:TextField = _content.getTextField();

                if (textField) {
                    textField.appendText(impulse.data.message);
                    textField.scrollV = textField.maxScrollV;
                }
            }
        }
    }
}
