package Src.Application.System.Managers {
    import flash.events.Event;
    
    import Src.Application.System.MultiPulsator.MultiPulsator;
    import Src.Application.System.MultiPulsator.Impulse;
    import Src.Application.System.Core.SerialCommand;
    import Src.Application.System.Core.CreateWindow;
    import Src.Application.System.Core.ICommand;
    import Src.Application.System.Core.InvokeFunction;
    
    import Src.Application.System.Modules.Windows.EditorWindow;
    import Src.Application.System.Modules.Windows.DeviceWindow;
    import Src.Application.MainSystem;
    import flash.display.NativeWindow;

    /**
     * Windows Manager - application window creation and control
     * Manages creation, control and coordination of all application windows
     * 
     * Main functions:
     * - Creation and configuration of editor and device windows
     * - Coordination of window creation sequence
     * - Access to created windows
     * - Window lifecycle management
     */
    public class WindowsManager {
        private static var instance:WindowsManager;
        public var nativeWindow:NativeWindow;
        public var editorWindow:EditorWindow;
        public var deviceWindow:DeviceWindow;

        /**
         * Windows Manager constructor
         */
        public function WindowsManager() {}

        /**
         * Get singleton instance
         * @return WindowsManager - singleton instance
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
            var windowsManager:WindowsManager = getInstance();
            windowsManager.nativeWindow = MainSystem.root.stage.nativeWindow;

            // Editor CreateWindow command with specific parameters
            var editorWindowCmd:CreateWindow = new CreateWindow("Editor", {
                x: 100,
                y: 100,
                width: 1100,
                height: 600,
                title: "Editor",
                visible: true,
                alpha: false,
                fullscreen: false
            });

            // Device CreateWindow command
            var deviceWindowCmd:CreateWindow = new CreateWindow("Device", {
                x: 1200,
                y: 100,
                width: 640,
                height: 480,
                title: "Device",
                visible: true,
                alpha: false,
                fullscreen: false
            });

            var serialCommand:SerialCommand = new SerialCommand(0,
                editorWindowCmd,
                deviceWindowCmd
            );

            serialCommand.addEventListener(Event.COMPLETE, function(event:Event):void {
                windowsManager.editorWindow = editorWindowCmd.content as EditorWindow;
                windowsManager.deviceWindow = deviceWindowCmd.content as DeviceWindow;

                MultiPulsator.emit(new Impulse("APP_WINDOWS_BUILDED_AND_READY", {
                    message: "Completed window creation",
                    windows: {
                        native: windowsManager.nativeWindow,
                        editor: windowsManager.editorWindow,
                        device: windowsManager.deviceWindow
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
        }

        /**
         * Get all windows
         * @return Object - object with references to all windows
         */
        public function getAllWindows():Object {
            return {
                native: nativeWindow,
                editor: editorWindow,
                device: deviceWindow
            };
        }

        /**
         * Factory method for window building command
         * Creates and returns command for building all windows
         * @return ICommand - window creation command sequence
         */
        public static function Run():ICommand {
            return new InvokeFunction(function():void {
                WindowsManager.CreateAllWindows();
            });
        }
    }
}
