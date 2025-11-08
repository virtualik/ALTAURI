package Src.Prog.Core.Managers {
    import flash.events.Event;
    import flash.system.Capabilities;

    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Windows.Window;

    import Src.Prog.Core.Commands.InvokeFunction;
    import Src.Prog.Core.Commands.ICommand;
    import Src.Prog.Main;

    /**
     * Unified Window Manager - handles all window operations across platforms
     * Manages window creation, lifecycle, and platform-specific behavior
     *
     * Responsibilities:
     * - Platform-aware window creation (Desktop vs Mobile)
     * - Window instance management and access
     * - Coordination with application initialization system
     * - Impulsys integration for window events
     */
    public class WindowsManager {
        private static var _instance:WindowsManager;
        public var nativeWindow:Window;
        public var editorWindow:Window;
        public var deviceWindow:Window;

        // Platform detection
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Get singleton instance
         * @return WindowsManager - Singleton instance
         */
        public static function getInstance():WindowsManager {
            if (!_instance) {
                _instance = new WindowsManager();
            }
            return _instance;
        }

        /**
         * Create application windows based on platform capabilities
         * Desktop: Multiple windows, Mobile: Single window with adaptive UI
         */
        public static function createWindows():void {
            var manager:WindowsManager = getInstance();
            manager.nativeWindow = Main.root.stage.nativeWindow as Window;

            // Platform-specific window creation strategy
            if (_isDesktop) {
                // Desktop environment: multiple independent windows
                manager.editorWindow = new Window("Editor", {
                    x: 100, y: 100, width: 1100, height: 600, title: "Editor"
                });
                manager.editorWindow.activate();

                manager.deviceWindow = new Window("Device", {
                    x: 1200, y: 100, width: 640, height: 480, title: "Device"
                });
                manager.deviceWindow.activate();
            } else {
                // Mobile environment: single primary window
                manager.editorWindow = new Window("Editor", {
                    title: "Editor"
                });
                manager.editorWindow.activate();
            }

            // Signal window creation completion
            Impulsys.emit(new Impulse("APP_WINDOWS_READY", {
                windows: manager.getAllWindows(),
                platform: _isDesktop ? "desktop" : "mobile"
            }));
        }

        /**
         * Find window by type identifier
         * @param type - Window type to locate
         * @return Window - Found window or null
         */
        public function findWindow(type:String):Window {
			if (type == null) return null;
    
            switch(type.toLowerCase()) {
                case "editor": return editorWindow;
                case "device": return deviceWindow;
                case "native": return nativeWindow;
                default: return null;
            }
        }

        /**
         * Close all application windows
         * Performs clean shutdown of window resources
         */
        public function closeAllWindows():void {
            if (editorWindow) editorWindow.close();
            if (deviceWindow) deviceWindow.close();
        }

        /**
         * Get all window references
         * @return Object - Collection of window references
         */
        public function getAllWindows():Object {
            return {
                native: nativeWindow,
                editor: editorWindow,
                device: deviceWindow
            };
        }

        /**
         * Command interface for window creation
         * Provides ICommand-compatible interface for Director integration
         * @return ICommand - Window creation command
         */
        public static function Run():ICommand {
            return new InvokeFunction(createWindows);
        }
    }
}
