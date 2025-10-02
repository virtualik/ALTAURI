package Application.Managers {
    import flash.text.TextField;
    import Application.MultiPulsator.*;

    /**
     * Logging Manager - application event logging system
     * Comprehensive logging system with buffering and formatting support
     * 
     * Key features:
     * - Message buffering until console ready
     * - Dual output (impulses + direct display)
     * - Automatic formatting and alignment
     * - Error handling and message validation
     */
    public class LoggingManager {
        private static var _instance:LoggingManager;
        private var consoleTextField:TextField;
        private var clickedKey:String = "";
        private var messageBuffer:Array = [];
        private var isInitialized:Boolean = false;
        private var isTextFieldSet:Boolean = false;
        private static const KEEP_BUFFERING_AFTER_CONSOLE_READY:Boolean = true;
        private static const COLON_POSITION:int = 30;

        /**
         * Singleton property - main access point
         * Creates instance on first access and sets up impulse subscriptions
         */
        public static function get instance():LoggingManager {
            if (!_instance) {
                _instance = new LoggingManager();
                MultiPulsator.subscribeToImpulse("CONSOLE_WINDOW_READY", _instance.reactor_CONSOLE_WINDOW_READY);
                MultiPulsator.subscribeToImpulse("LOG_MESSAGE", _instance.reactor_LOG_MESSAGE);
            }
            return _instance;
        }

        /**
         * Singleton constructor
         */
        public function LoggingManager() {}

        /**
         * Console ready reactor - called when console window is ready
         * Initializes system and sends buffered messages
         */
        private function reactor_CONSOLE_WINDOW_READY(impulse:Impulse):void {
            initialize();
            flushBuffer();
            MultiPulsator.removeImpulse("CONSOLE_WINDOW_READY", reactor_CONSOLE_WINDOW_READY);
        }

        /**
         * Log message reactor - main message processing method
         * Supports buffering before initialization and dual output after
         */
        private function reactor_LOG_MESSAGE(impulse:Impulse):void {
            if (impulse && impulse.data && impulse.data.message) {
                var message:String = alignColon(impulse.data.message) + "\n";

                if (!isInitialized) {
                    // Before initialization: accumulate in buffer
                    messageBuffer.push(message);
                } else {
                    // After initialization: send to console
                    MultiPulsator.emit(new Impulse("CONSOLE_LOG_MESSAGE", { message: message }));

                    // Additionally: direct output to text field if set
                    if (isTextFieldSet && consoleTextField) {
                        consoleTextField.appendText(message);
                        consoleTextField.scrollV = consoleTextField.maxScrollV;
                    }

                    // Keep in buffer if continuous buffering is configured
                    if (KEEP_BUFFERING_AFTER_CONSOLE_READY) {
                        messageBuffer.push(message);
                    }
                }
            } else {
                // Handle invalid impulses
                var errorMessage:String = alignColon("LoggingManager: [WARNING] Invalid LOG_MESSAGE impulse received") + "\n";

                if (!isInitialized) {
                    messageBuffer.push(errorMessage);
                } else {
                    MultiPulsator.emit(new Impulse("CONSOLE_LOG_MESSAGE", { message: errorMessage }));

                    if (isTextFieldSet && consoleTextField) {
                        consoleTextField.appendText(errorMessage);
                        consoleTextField.scrollV = consoleTextField.maxScrollV;
                    }

                    if (KEEP_BUFFERING_AFTER_CONSOLE_READY) {
                        messageBuffer.push(errorMessage);
                    }
                }
            }
        }

        /**
         * Initialize logging system
         * Marks system as ready and sends initialization message
         */
        public function initialize():void {
            if (isInitialized) return;

            isInitialized = true;
            var initMessage:String = alignColon("Initializing to be ready to receive impulses") + "\n";

            MultiPulsator.emit(new Impulse("CONSOLE_LOG_MESSAGE", {
                level: "INFO",
                source: "LoggingManager",
                message: initMessage
            }));

            if (isTextFieldSet && consoleTextField) {
                consoleTextField.appendText(initMessage);
                consoleTextField.scrollV = consoleTextField.maxScrollV;
            }
        }

        /**
         * Set text field for direct output
         * Provides alternative output channel directly to text field
         */
        public function setConsoleTextField(textField:TextField):void {
            this.consoleTextField = textField;
            isTextFieldSet = true;
            flushBuffer();
        }

        /**
         * Send message buffer
         * Sends all buffered messages to console and/or text field
         */
        private function flushBuffer():void {
            for each (var message:String in messageBuffer) {
                MultiPulsator.emit(new Impulse("CONSOLE_LOG_MESSAGE", { message: message }));

                if (isTextFieldSet && consoleTextField) {
                    consoleTextField.appendText(message);
                    consoleTextField.scrollV = consoleTextField.maxScrollV;
                }
            }

            if (!KEEP_BUFFERING_AFTER_CONSOLE_READY) {
                messageBuffer = [];
            }
        }

        /**
         * Align colon in messages
         * Formats messages for beautiful output with colon alignment
         */
        private function alignColon(message:String):String {
            var colonIndex:int = message.indexOf(":");
            if (colonIndex == -1) {
                return message;
            }


			var leftPart:String = message.substring(0, colonIndex);
            var rightPart:String = message.substring(colonIndex);
            var spacesToAdd:int = COLON_POSITION - leftPart.length;

            if (spacesToAdd <= 0) {
                return message;
            }

            var padding:String = "";
            for (var i:int = 0; i < spacesToAdd; i++) {
                padding += " ";
            }

            return padding + leftPart + rightPart;
        }
    }
}
