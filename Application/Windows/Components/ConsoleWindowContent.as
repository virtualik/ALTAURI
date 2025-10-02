package Application.Windows.Components {
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.display.Sprite;

    /**
     * Console Window Content - manages text output for system messages
     * Handles creation and configuration of console text interface
     */
    public class ConsoleWindowContent {
        private var _textField:TextField;
        private var _container:Sprite;
        private var _width:int;
        private var _height:int;

        /**
         * Console Content constructor
         * @param container - graphic container for text field
         * @param width - available width for console
         * @param height - available height for console
         */
        public function ConsoleWindowContent(container:Sprite, width:int, height:int) {
            _container = container;
            _width = width;
            _height = height;
            initialize();
        }

        /**
         * Initialize console text field
         * Creates and configures terminal-style text field
         */
        private function initialize():void {
            _textField = new TextField();
            _textField.width = _width - 20;
            _textField.height = _height - 20;
            _textField.x = 10;
            _textField.y = 10;
            _textField.border = true;
            _textField.multiline = true;
            _textField.wordWrap = false;
            _textField.background = true;
            _textField.backgroundColor = 0x222222;
            _textField.textColor = 0x00FF00;

            var format:TextFormat = new TextFormat();
            format.font = "Consolas";
            format.size = 10;
            _textField.defaultTextFormat = format;

            _textField.text = "Console Log:\n";
            _container.addChild(_textField);
        }

        /**
         * Get console text field
         * @return TextField - reference to console text field
         */
        public function getTextField():TextField {
            return _textField;
        }

        /**
         * Add message to console
         * @param message - message text to add
         */
        public function appendMessage(message:String):void {
            _textField.appendText(message);
            _textField.scrollV = _textField.maxScrollV;
        }

        /**
         * Clear console
         * Completely clears console text field
         */
        public function clear():void {
            _textField.text = "Console Log:\n";
        }

        /**
         * Update console dimensions
         * @param width - new window width
         * @param height - new window height
         */
        public function resize(width:Number, height:Number):void {
            _width = width;
            _height = height;
            _textField.width = _width - 20;
            _textField.height = _height - 20;
        }
    }
}
