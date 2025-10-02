package Application.Managers {
    import flash.events.Event;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Commands.SerialCommand;
    import Application.Commands.Windows.Window;
    import Application.Windows.BaseWindow;
    import Application.Windows.EditorWindow;
    import Application.Windows.DeviceWindow;
    import Application.Windows.ConsoleWindow;
    import Application.MainSystem;
    import flash.display.NativeWindow;
    import Application.Commands.ICommand;
    import Application.Commands.Utils.InvokeFunction;

    /**
     * Windows Manager - application window creation and control
     * Manages creation, control and coordination of all application windows
     * 
     * Main functions:
     * - Creation and configuration of editor, device and console windows
     * - Coordination of window creation sequence
     * - Access to created windows
     * - Window lifecycle management
     */
    public class WindowsManager {
        private static var instance:WindowsManager;
        public var nativeWindow:flash.display.NativeWindow;
        public var editorWindow:EditorWindow;
        public var deviceWindow:DeviceWindow;
        public var consoleWindow:ConsoleWindow;

        /**
         * Windows Manager constructor
         */
        public function WindowsManager() {}

        /**
         * Get singleton instance
         */
        public static function getInstance():WindowsManager {
            if (!instance) {
                instance = new WindowsManager();
            }
            return instance;
        }

        /**
         * Create all application windows
         * Main method that creates and configures all application windows
         * Uses Command pattern for sequential window creation
         */
        public static function CreateAllWindows():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "WindowsManager: [INFO] Calling window creation commands"
            }));

            var windowsManager:WindowsManager = getInstance();

            windowsManager.nativeWindow = MainSystem.root.stage.nativeWindow;

            // Editor window command with specific parameters
            var editorWindowCmd:Window = new Window("Editor", {
                x: 100,
                y: 100,
                width: 1100,
                height: 600,
                title: "Editor",
                visible: true,
                alpha: false,
                fullscreen: false
            });

            // Device window command
            var deviceWindowCmd:Window = new Window("Device", {
                x: 1200,
                y: 100,
                width: 640,
                height: 480,
                title: "Device",
                visible: true,
                alpha: false,
                fullscreen: false
            });

            // Console window command
            var consoleWindowCmd:Window = new Window("Console", {
                x: 1200,
                y: 600,
                width: 640,
                height: 320,
                title: "Console",
                visible: true,
                alpha: false,
                fullscreen: false
            });

            var serialCommand:SerialCommand = new SerialCommand(0,
                editorWindowCmd,
                deviceWindowCmd,
                consoleWindowCmd
            );

            serialCommand.addEventListener(Event.COMPLETE, function(event:Event):void {
                windowsManager.editorWindow = editorWindowCmd.content as EditorWindow;
                windowsManager.deviceWindow = deviceWindowCmd.content as DeviceWindow;
                windowsManager.consoleWindow = consoleWindowCmd.content as ConsoleWindow;

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "WindowsManager: [INFO] Completed window creation"
                }));

                MultiPulsator.emit(new Impulse("APP_WINDOWS_BUILDED_AND_READY", {
                    message: "Completed window creation",
                    windows: {
                        native: windowsManager.nativeWindow,
                        editor: windowsManager.editorWindow,
                        device: windowsManager.deviceWindow,
                        console: windowsManager.consoleWindow
                    }
                }));
            });

            serialCommand.execute();
        }

        /**
         * Find window by type
         * @param windowType - window type to find
         * @return * - found window or null if not found
         */
        public function findWindowByType(windowType:String):* {
            switch(windowType.toLowerCase()) {
                case "native":
                    return nativeWindow;
                case "editor":
                    return editorWindow;
                case "device":
                    return deviceWindow;
                case "console":
                    return consoleWindow;
                default:
                    return null;
            }
        }

        /**
         * Get window content
         * @param windowType - window type
         * @return * - window content or null if window not found
         */
        public function getWindowContent(windowType:String):* {
            var window:* = findWindowByType(windowType);
            return window ? window.content : null;
        }

        /**
         * Close all windows
         * Properly closes all created application windows
         */
        public function closeAllWindows():void {
            if (editorWindow) editorWindow.close();
            if (deviceWindow) deviceWindow.close();
            if (consoleWindow) consoleWindow.close();
        }

        /**
         * Get all windows
         * @return Object - object with references to all windows
         */
        public function getAllWindows():Object {
            return {
                native: nativeWindow,
                editor: editorWindow,
                device: deviceWindow,
                console: consoleWindow
            };
        }

        /**
         * Factory method for window building command
         * Creates and returns command for building all windows
         */
        public static function Run():ICommand {
            return new InvokeFunction(function():void {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "WindowsManager: [INFO] Executing window building command"
                }));
                WindowsManager.CreateAllWindows();
            });
        }
    }
}
